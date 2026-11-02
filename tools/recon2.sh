#!/bin/sh
# Second read-only survey: details the first one missed.
# Usage (from the repo root):
#   ssh root@192.168.8.1 'sh -s' < tools/recon2.sh > recon2.txt
# Changes nothing on the router.

section() { printf '\n##### %s\n' "$*"; }
run() { printf '$ %s\n' "$*"; sh -c "$*" 2>&1; }

section "Hardware acceleration"
run 'uci show mtkhnat'
run 'cat /sys/kernel/debug/hnat/hnat_setting 2>/dev/null | head -5'

section "Policy routing tables GL uses"
run 'ip route show table 16800'
run 'ip route show table 9910'
run 'ip route show table 999'
run 'iptables -t mangle -S | sed -n "60,120p"'
run 'iptables -t nat -S PREROUTING'

section "GL RPC loader"
run 'head -80 /usr/share/gl-ngx/oui-rpc.lua'
run 'ls /usr/lib/lua/oui /usr/share/gl-ngx'
run 'grep -nE "worker_processes|lua_package_path|lua_code_cache" /etc/nginx/nginx.conf /etc/nginx/conf.d/gl.conf'

section "GL front end"
run 'zcat /www/js/app.*.js.gz | grep -oE "Vue\.js v[0-9.]+|vue@[0-9.]+|version:\"2\.[0-9.]+\"" | sort -u | head'
run 'zcat /www/js/app.*.js.gz | grep -oE "\\\$rpcRequest|rpcRequest" | sort | uniq -c'
run 'zcat /www/js/app.*.js.gz | grep -oE "views/gl-sdk4-ui-[^\"]{0,30}|\.common\.js[^\"]{0,20}" | sort -u | head'

section "LuCI web"
run 'uci show uhttpd.main | grep -E "listen|home"'

section "Packages"
run 'opkg list-installed | grep -E "^(ca-bundle|ca-certificates|libpthread|librt|libc|libopenssl|libmbedtls|libwolfssl)"'
run 'for p in iptables-mod-iprange kmod-ipt-iprange ca-bundle ca-certificates coreutils-base64 coreutils-nohup lyaml libyaml; do printf "%-22s %s\n" "$p" "$(opkg list "$p" 2>/dev/null | head -1 | cut -c1-80)"; done'
run 'ls /lib/libc.so* /lib/ld-musl-* 2>/dev/null'
