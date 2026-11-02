#!/bin/sh
# Read-only survey of a GL.iNet 4.x router for the PassWall GL port.
# Usage (from the repo root on your computer):
#   ssh root@192.168.8.1 'sh -s' < tools/recon.sh > recon.txt
#
# It changes nothing on the router except refreshing the opkg package lists
# in RAM (the same thing GL's Plug-ins page does). It deliberately skips
# configs that hold secrets (wireless, network, VPN, users).

section() { printf '\n##### %s\n' "$*"; }
run() { printf '$ %s\n' "$*"; sh -c "$*" 2>&1; }

section "Firmware"
run 'cat /etc/glversion'
run 'cat /etc/openwrt_release'
run 'cat /proc/version'
run 'ubus call system board'
run 'uname -m'

section "Resources"
run 'free -m'
run 'df -h'

section "Firewall stack"
run 'ls /etc/init.d | grep -E "^firewall|^fw"'
run 'command -v fw4 fw3 nft iptables iptables-legacy ip6tables ipset'
run 'iptables -V'
run 'nft --version'
run 'lsmod | grep -Ei "tproxy|nft_|xt_socket|xt_TPROXY|ip_set|tun "'
run 'uci show firewall | grep -Ei "offload|defaults"'
run 'ip rule show'
run 'ip -6 rule show'
run 'iptables -t mangle -S | head -60'
run 'nft list tables'

section "Hardware acceleration / NAT offload"
run 'ls /etc/config'
run 'lsmod | grep -Ei "hnat|ppe|flow|offload|fast"'
run 'uci -q show glconfig | grep -Ei "accel|hnat|offload|sfe|ppe"'

section "DNS"
run 'netstat -lntup | grep -E ":53 |:5353 |:3053 |:15353 "'
run 'uci show dhcp.@dnsmasq[0]'
run 'ls -la /tmp/dnsmasq.d /tmp/dnsmasq.cfg*.d 2>/dev/null'
run 'uci -q show adguardhome'

section "Lua and LuCI"
run 'ls /usr/lib/lua /usr/lib/lua/5.* /usr/lib/lua/luci 2>/dev/null | head -80'
run 'lua -v'
run 'command -v lua lua5.1 lua5.3 lua5.4 eco'

section "GL web stack (oui)"
run 'ps w | grep -E "oui|nginx|uhttpd|lua" | grep -v grep'
run 'ls -la /usr/lib/oui-httpd /usr/lib/oui-httpd/rpc /usr/share/oui 2>/dev/null'
run 'find /usr/share/oui -maxdepth 2 | head -80'
run 'head -5 /usr/lib/oui-httpd/rpc/tor'
run 'grep -nE "^local .*require|^function M\.|^M\.[a-z_]+ *=|return M" /usr/lib/oui-httpd/rpc/tor | head -40'
run 'grep -nE "require|acl|function" /usr/lib/oui-httpd/rpc/acl | head -40'
run 'cat /usr/share/oui/menu.d/torview.json'
run 'ls /etc/nginx /etc/nginx/conf.d 2>/dev/null'
run 'grep -nE "location|views|rpc|gzip_static" /etc/nginx/conf.d/*.conf | head -40'
run 'ls /www | head -50'
run 'ls /www/js 2>/dev/null | head -50'
run 'for f in /www/js/*.js /www/*.js; do [ -f "$f" ] && grep -o "Vue.js v[0-9.]*" "$f" | head -1; done'
run 'cat /www/js/*.js 2>/dev/null | grep -o "rpcRequest" | sort | uniq -c'
run 'cat /www/js/*.js 2>/dev/null | grep -oE "component\(\"gl-[a-z0-9-]+\"" | sort -u | head -100'
run 'cat /www/js/*.js 2>/dev/null | grep -oE "name:\"gl-[a-z0-9-]+\"" | sort -u | head -100'
run 'cat /www/js/*.js 2>/dev/null | grep -oE "\.common\.js[^\"]{0,40}" | sort -u | head -20'

section "Packages"
run 'opkg update >/dev/null 2>&1; echo "opkg update exit: $?"'
run 'cat /etc/opkg/distfeeds.conf /etc/opkg/customfeeds.conf 2>/dev/null'
run 'opkg print-architecture'
run 'opkg list-installed | grep -E "^(dnsmasq|luci|lua|libuci-lua|liblua|curl|coreutils|ip-full|kmod-nft|kmod-ipt|kmod-tun|iptables|ipset|nftables|firewall|xray|v2ray|sing-box|chinadns|smartdns|haproxy|unzip|lyaml|libyaml|microsocks|dns2socks|tcping|ipt2socks|geoview|resolveip|cjson|lua-cjson)"'
run 'for p in xray-core v2ray-geoip v2ray-geosite chinadns-ng dns2socks microsocks tcping ipt2socks geoview lyaml luci-compat luci-base luci-lib-jsonc libuci-lua smartdns haproxy dnsmasq-full ip-full resolveip coreutils-nohup coreutils-timeout coreutils-base64 kmod-nft-tproxy kmod-nft-socket iptables-mod-tproxy iptables-mod-socket ipset unzip; do printf "%-22s %s\n" "$p" "$(opkg list "$p" 2>/dev/null | head -1)"; done'
