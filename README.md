# 南京工业大学校园网自动登录脚本（路由器版）

> NJTech Campus Network Auto-Login for OpenWrt routers
> 适用于南京工业大学 Dr.COM / **新版 EPortal** 认证系统的 OpenWrt 路由器自动登录方案。

[![OpenWrt](https://img.shields.io/badge/OpenWrt-23.05%2B-blue)](https://openwrt.org/)
[![ImmortalWrt](https://img.shields.io/badge/ImmortalWrt-supported-green)](https://immortalwrt.org/)
[![Dr.COM](https://img.shields.io/badge/Dr.COM-EPortal-orange)]()
[![License](https://img.shields.io/badge/License-MIT-lightgrey)](LICENSE)

把路由器接到校园网，让它自动登录认证，后面的手机、电脑、平板等所有设备连这台路由器就能直接上网，**只占用一个认证名额**，断网自动重连，开机自启。

---

## ✨ 功能特点

- ✅ 自动检测网络状态，断网自动重连（cron 每 2 分钟）
- ✅ 开机自启（等 WAN 就绪后再登录，避免开机过早失败）
- ✅ 仅依赖 OpenWrt 自带的 `wget`(uclient-fetch)，**无需安装 curl**
- ✅ 适配学校**新版 EPortal**（关键账号格式坑已踩平，见下）
- ✅ NAT 共享，多设备共用一个认证名额
- ✅ 日志清晰，方便排查

---

## ⚠️ 最重要的一个坑：新版 EPortal 账号格式

南工大已把认证系统升级为**新版 EPortal**。网上很多老脚本（直接 POST 裸学号到
`/eportal/?c=ACSetting&a=Login`）**现在都失效了**，表现为：

> 登录接口返回 `{"result":1,"msg":"Portal协议认证成功！"}`，
> 但实际 `chkstatus` 一直是 `result:0`，根本上不了网。

**根因**：新版 EPortal 要求提交的账号格式必须是

```
,0,学号@运营商
```

例如电信用户：`,0,201234567890@telecom`

- 前缀 `,0,` 不能少
- 后缀按运营商：电信 `@telecom`、联通 `@unicom`、移动 `@cmcc`、校园网留空
- 只发裸学号 → 服务器「认证成功」但网关不放行（这就是大多数老脚本失效的原因）

本脚本已按此格式实现。**这个格式是通过浏览器手动登录、F12 抓 HAR 包对比真实成功请求确认的**——如果你学校情况不同，按本文「如何确认自己的参数」一节自查。

---

## 📦 环境要求

| 项目 | 说明 |
|------|------|
| 路由器固件 | OpenWrt 23.05+ / ImmortalWrt（实测 23.05.5, mediatek/filogic, aarch64） |
| HTTP 工具 | 系统自带 `wget`(uclient-fetch) 即可，**不需要 curl** |
| 上网方式 | **网线插校园网口（有线 WAN）** 最简单；无线客户端模式也可（需另配 wwan） |
| 认证服务器 | `10.50.255.11`（端口 80 状态查询，端口 801 登录） |

> 有线 WAN 方式无需配置无线客户端、无需 MAC 克隆，OpenWrt 默认 `wan`(eth0+DHCP) +
> 默认防火墙（lan→wan 转发、wan 区 masq）即可开箱 NAT 共享。

---

## 🚀 快速开始

### 1. 改配置

编辑 `campus-login.sh` 配置区：

```sh
USERNAME="YOUR_STUDENT_ID"   # 改成你的学号
PASSWORD="YOUR_PASSWORD"     # 改成你的密码（注意大小写）
ISP_SUFFIX="@telecom"        # 电信@telecom / 联通@unicom / 移动@cmcc / 校园网留空
ACCOUNT_PREFIX=",0,"         # 一般保持 ,0,
```

### 2. 传到路由器

OpenWrt 默认没有 `sftp-server`，`scp` 可能不可用。推荐直接 SSH 粘贴创建：

```sh
ssh root@192.168.1.1
cat > /root/campus-login.sh << 'EOF'
# 把 campus-login.sh 的完整内容粘贴到这里
EOF

cat > /root/campus-boot.sh << 'EOF'
# 把 campus-boot.sh 的完整内容粘贴到这里
EOF

chmod 700 /root/campus-login.sh /root/campus-boot.sh   # 含明文密码，仅 root 可读
```

### 3. 配置定时检测（cron）

```sh
echo "*/2 * * * * /root/campus-login.sh >/tmp/campus-login.cron.log 2>&1" > /etc/crontabs/root
/etc/init.d/cron enable
/etc/init.d/cron restart
```

### 4. 配置开机自启

```sh
sed -i '/^exit 0/i /root/campus-boot.sh >/tmp/campus-login.boot.log 2>&1 &' /etc/rc.local
```

### 5. 立即测试

```sh
/root/campus-login.sh
```

看到 `online after login` 或 `already online` 即成功。再验证真实联网：

```sh
wget -q -O - http://www.baidu.com | head    # 能返回真实首页就是通了
wget -q -O - 'http://10.50.255.11/drcom/chkstatus?callback=dr_status&v=1'   # result:1 = 在线
```

> 注意：`ping 223.5.5.5` 在认证前往往也能通（白名单），**不能用 ping 判断是否真上网**，
> 一定要用真实网站（baidu）或 `chkstatus` 的 `result` 判断。

---

## 🧰 常用命令

```sh
# 手动登录
/root/campus-login.sh

# 查看在线状态
wget -q -O - 'http://10.50.255.11/drcom/chkstatus?callback=dr_status&v=1'

# 登出（清除残留会话，重启后若提示「已经在线」可先登出）
wget -q -O - 'http://10.50.255.11:801/eportal/portal/logout?callback=dr&v=1'

# 看日志
logread | grep campus-login
cat /tmp/campus-login.cron.log
cat /tmp/campus-login.boot.log
```

---

## 🔍 如何确认自己的登录参数（换学校/认证异常时）

如果脚本对你不灵，用浏览器抓一次真实成功的登录请求来对比：

1. 电脑连到校园网，浏览器打开 `http://10.50.255.11`（或任意 http 网站触发跳转）
2. 按 `F12` → **Network/网络** 面板，勾选 **Preserve log/保留日志**
3. 如已登录先**登出**，再正常输账号密码登录
4. 在 Network 里找到 `portal/login?...` 这条请求
5. 看它的 `user_account`、`wlan_ac_ip`、`wlan_ac_name`、`terminal_type` 等参数
6. 把脚本里对应字段改成和它一致即可

> 经验：`wlan_ac_ip` / `wlan_ac_name` 在很多校区**即使成功也是空**，不必纠结；
> 真正容易错的是 `user_account` 的格式（前缀 + 后缀）和密码大小写。

---

## ❓ 常见问题

**Q：登录返回「认证成功」但还是上不了网？**
A：99% 是账号格式问题。确认用了 `,0,学号@运营商` 格式，后缀对不对，密码大小写对不对。

**Q：提示「IP xxx 已经在线」/ ret_code=2？**
A：服务器有残留会话。先执行上面的「登出」命令，再重新登录。重启路由器后常见，cron 会自动处理。

**Q：重启后没自动登录？**
A：检查 `/etc/rc.local` 是否有 `campus-boot.sh` 那一行；看 `cat /tmp/campus-login.boot.log`。
开机脚本会等 WAN 就绪再登录；即使开机那次失败，cron 每 2 分钟也会补登。

**Q：提示没有 curl？**
A：本脚本用的是 `wget`，不需要 curl。如果你硬要用 curl 版老脚本，先 `opkg update && opkg install curl`。

**Q：其他设备怎么用？**
A：连这台路由器的 WiFi 或 LAN 口（网关 192.168.1.1），自动通过 NAT 上网，无需再认证。

---

## 📱 关于手机/其他终端版本（招募）

本项目目前是 **路由器版**（OpenWrt shell 脚本）。

如果有人需要 **手机/电脑等单终端的自动登录版本**（比如安卓 App、Windows/macOS 后台脚本、
iOS 快捷指令等），欢迎在 Issues 留言。**有人感兴趣的话，我也可以做一版。** 也欢迎直接 PR。

核心登录逻辑（账号格式 `,0,学号@运营商` + 那个 JSONP 接口）是通用的，移植到任何平台都不难。

---

## 🤝 贡献

- 不同运营商后缀、不同校区参数，欢迎 PR 补充对照表
- 其他学校的 Dr.COM/EPortal 适配经验也欢迎分享
- **提交前请务必删除你的真实学号、密码、SSH 私钥、HAR 抓包文件**（本仓库 `.gitignore` 已做基础防护，但请自查）

---

## ⚠️ 免责声明

1. **本项目仅供学习交流与技术研究使用**，旨在帮助同学理解校园网认证原理、便利自己的多设备上网。
2. 使用本脚本即表示你**已拥有合法的校园网账号**，并对自己账号下的一切网络行为负责。
3. **请遵守学校的网络管理规定与相关法律法规**。请勿用于共享账号牟利、绕过计费、攻击认证系统等任何违规或非法用途。
4. 使用本脚本可能违反部分学校关于「禁止私接路由器 / 限制设备数量」的规定，由此产生的账号封停、处分等后果**由使用者自行承担**，与作者无关。
5. 脚本中需填写明文密码，请妥善保管你的配置文件，**切勿将含真实密码的文件公开或上传**。
6. 本项目按 **MIT 协议** 「按原样」提供，不对其可用性、安全性、适用性作任何担保。作者不对使用本项目造成的任何直接或间接损失负责。
7. 校园网认证系统若更新，脚本可能失效，需自行按上文方法重新抓包适配。

> 一句话：**自己用，别违规，出事自负，与作者无关。**

---

## 📄 License

[MIT](LICENSE) © fhy12130-afk
