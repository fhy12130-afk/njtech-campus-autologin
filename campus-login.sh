#!/bin/sh

# ============================================================================
# 南京工业大学校园网自动登录脚本 (OpenWrt / 新版 EPortal)
# NJTech Campus Network Auto-Login for OpenWrt routers
#
# 适用于已自带 wget(uclient-fetch) 但未安装 curl 的 OpenWrt / ImmortalWrt。
# 仅供学习交流，详见 README 免责声明。
#
# ⚠️ 关键坑：学校已升级为「新版 EPortal」，登录账号格式必须为
#            ,0,学号@运营商   （例：,0,201234567890@telecom）
#            前缀 ,0, + 学号 + 运营商后缀；裸学号会「认证成功」但网关不放行。
#            此格式由浏览器成功登录请求 HAR 抓包确认。
# ============================================================================

PORTAL_HOST="10.50.255.11"
PORTAL_URL="http://${PORTAL_HOST}/"
STATUS_URL="http://${PORTAL_HOST}/drcom/chkstatus?callback=dr_status&jsVersion=4.X&v=1000"
LOGIN_URL="http://${PORTAL_HOST}:801/eportal/portal/login"

# ==================== 配置区域（改成你自己的）====================
USERNAME="YOUR_STUDENT_ID"   # 学号，例如 201234567890
PASSWORD="YOUR_PASSWORD"     # 校园网密码（注意大小写）
ISP_SUFFIX="@telecom"        # 运营商后缀（见下表），不确定先用 @telecom 试
ACCOUNT_PREFIX=",0,"         # 新版 EPortal 账号前缀，一般保持 ,0,
                             #
                             # 运营商后缀对照（不同学校/套餐可能不同）：
                             #   电信  @telecom
                             #   联通  @unicom
                             #   移动  @cmcc
                             #   校园网 留空 ""
                             # 完整账号 = ${ACCOUNT_PREFIX}${USERNAME}${ISP_SUFFIX}

LOG_TAG="campus-login"
TMP_PAGE="/tmp/campus-login-page.html"
TMP_STATUS="/tmp/campus-login-status.jsonp"
TMP_RESULT="/tmp/campus-login-result.jsonp"

log() {
	logger -t "$LOG_TAG" "$*"
	echo "$LOG_TAG: $*"
}

url_escape() {
	# Minimal escaping for the account strings used by this portal.
	echo "$1" | sed \
		-e 's/%/%25/g' \
		-e 's/,/%2C/g' \
		-e 's/@/%40/g' \
		-e 's/+/%2B/g' \
		-e 's/ /%20/g'
}

fetch_portal() {
	wget -q -T 8 -O "$TMP_PAGE" "$PORTAL_URL"
}

is_logged_in() {
	wget -q -T 8 -O "$TMP_STATUS" "$STATUS_URL" 2>/dev/null
	grep -q '"result":1' "$TMP_STATUS" 2>/dev/null && return 0
	grep -q "Dr.COMWebLoginID_1.htm" "$TMP_PAGE" 2>/dev/null && return 0
	return 1
}

login() {
	account="${ACCOUNT_PREFIX}${USERNAME}${ISP_SUFFIX}"
	encoded_account="$(url_escape "$account")"
	user_ip="$(ip -4 addr show eth0 2>/dev/null | sed -n 's/.*inet \([0-9.]*\)\/.*/\1/p' | head -n 1)"
	user_mac="$(cat /sys/class/net/eth0/address 2>/dev/null | tr -d ":" | tr "a-z" "A-Z")"
	[ -n "$user_mac" ] || user_mac="000000000000"
	[ -n "$user_ip" ] || user_ip="0.0.0.0"

	# 参数精确复刻浏览器成功登录请求（HAR 抓包）：
	#   user_account=,0,学号@运营商, ac_ip/ac_name 留空,
	#   terminal_type=1, jsVersion=4.1.3，wlan_user_mac 全零也可
	query="callback=dr_login&login_method=1&user_account=${encoded_account}&user_password=${PASSWORD}&wlan_user_ip=${user_ip}&wlan_user_ipv6=&wlan_user_mac=${user_mac}&wlan_ac_ip=&wlan_ac_name=&jsVersion=4.1.3&terminal_type=1&lang=zh-cn&v=$(date +%s)"

	wget -q -T 10 -O "$TMP_RESULT" "${LOGIN_URL}?${query}"
	rc=$?

	if [ "$rc" -ne 0 ]; then
		log "login request failed, wget exit code: $rc"
		return "$rc"
	fi

	if grep -q '"result":1\|"result":"ok"' "$TMP_RESULT" 2>/dev/null; then
		log "login request succeeded for ${account}"
		return 0
	fi

	msg="$(sed -n 's/.*"msg":"\([^"]*\)".*/\1/p' "$TMP_RESULT" 2>/dev/null | head -n 1)"
	ret_code="$(sed -n 's/.*"ret_code":\([^,}]*\).*/\1/p' "$TMP_RESULT" 2>/dev/null | head -n 1)"
	log "login rejected for ${account}; ret_code=${ret_code:-unknown}; msg=${msg:-unknown}"
	return 1
}

main() {
	if fetch_portal && is_logged_in; then
		log "already online"
		return 0
	fi

	log "not online, trying campus portal login"
	login

	if fetch_portal && is_logged_in; then
		log "online after login"
		return 0
	fi

	log "still not confirmed online after login"
	return 1
}

main "$@"
