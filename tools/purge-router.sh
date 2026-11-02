#!/bin/sh
# Remove PassWall for GL.iNet from a router completely: its packages, the
# extra packages the installer pulled from GL's feed, PassWall's settings and
# rule files, and leftovers from development installs. Run from the repo root:
#   ssh root@192.168.8.1 'sh -s' < tools/purge-router.sh
#
# This deletes your nodes, subscriptions and routing lists. To keep them,
# copy /etc/config/passwall and /etc/passwall/rules/ off the router first.

say() { printf '%s\n' "$*"; }

say "Stopping PassWall"
for s in passwall passwall_server; do
	[ -x "/etc/init.d/$s" ] && { "/etc/init.d/$s" stop; "/etc/init.d/$s" disable; } >/dev/null 2>&1
done

say "Removing packages"
# Dependents first, so each removal succeeds without forcing. libyaml and
# coreutils were on the router before, so they stay.
for p in passwall-gl-full passwall-gl luci-app-passwall \
	xray-core geoview chinadns-ng dns2socks microsocks tcping ipt2socks v2ray-geoip v2ray-geosite \
	lyaml coreutils-nohup coreutils-base64 iptables-mod-iprange kmod-ipt-iprange; do
	if opkg status "$p" | grep -q '^Status: .* installed'; then
		opkg remove "$p" >/dev/null 2>&1 && say "  removed $p" || say "  could not remove $p"
	fi
done

say "Undoing PassWall's settings changes"
uci -q delete firewall.passwall
uci -q delete firewall.passwall_server
uci commit firewall
while uci -q delete ucitrack.@passwall[-1]; do :; done
while uci -q delete ucitrack.@passwall_server[-1]; do :; done
uci commit ucitrack
saved=/etc/passwall-gl/saved
if [ -f "$saved" ]; then
	restore() { # <uci key> <saved value>
		if [ -n "$2" ]; then uci -q set "$1=$2"; else uci -q delete "$1"; fi
	}
	restore dhcp.@dnsmasq[0].localuse "$(sed -n 's/^localuse=//p' "$saved")"
	uci commit dhcp
	restore uhttpd.main.max_requests "$(sed -n 's/^max_requests=//p' "$saved")"
	uci commit uhttpd
fi

say "Deleting PassWall's settings and leftover files"
rm -rf /etc/config/passwall /etc/config/passwall_server /etc/config/passwall-opkg \
	/etc/config/passwall_server-opkg /etc/passwall /etc/passwall-gl \
	/usr/share/passwall /usr/share/passwall-gl /usr/lib/lua/luci/passwall \
	/usr/lib/oui-httpd/rpc/passwall /usr/share/gl-validator.d/passwall.lua \
	/usr/share/oui/menu.d/passwall.json /www/views/gl-sdk4-ui-passwall.common.js.gz \
	/tmp/etc/passwall /tmp/etc/passwall_tmp /tmp/etc/passwall_server /tmp/log/passwall.log \
	/tmp/passwall-gl.err /tmp/passwall-gl-* /tmp/pw-bundle.tar.gz /tmp/pw.ipk \
	/tmp/luci-indexcache* /tmp/luci-modulecache
# Geo data PassWall may have downloaded itself, outside its packages.
rm -f /usr/share/v2ray/geoip.dat /usr/share/v2ray/geosite.dat
rmdir /usr/share/v2ray 2>/dev/null

say "Restarting DNS, firewall and the admin panel's workers"
/etc/init.d/dnsmasq restart >/dev/null 2>&1
/etc/init.d/firewall restart >/dev/null 2>&1
nginx -s reload >/dev/null 2>&1

say "Done. PassWall is gone from this router."
