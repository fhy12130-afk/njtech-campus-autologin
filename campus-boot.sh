#!/bin/sh

# ============================================================================
# 开机自启包装脚本：等 WAN 口就绪后再执行登录，cron 负责后续保活。
# 用法：在 /etc/rc.local 的 exit 0 之前加一行
#       /root/campus-boot.sh >/tmp/campus-login.boot.log 2>&1 &
# ============================================================================

i=0
while [ "$i" -lt 30 ]; do
	ip -4 addr show eth0 2>/dev/null | grep -q 'inet ' && break
	i=$((i + 1))
	sleep 2
done

sleep 3
/root/campus-login.sh
