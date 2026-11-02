#!/bin/sh
# PassWall for GL.iNet: uninstaller. Stops PassWall, removes what the bundle
# installed and undoes the settings PassWall's installer changed.
#   sh /usr/share/passwall-gl/uninstall.sh

set -u

saved=/etc/passwall-gl/saved

say() { printf '%s\n' "$*"; }

[ "$(id -u)" = 0 ] || { say "Error: run this as root" >&2; exit 1; }

# This file is removed below along with its package, so run from a copy.
case "$0" in
/tmp/*) ;;
*)
	cp "$0" /tmp/passwall-gl-uninstall.sh
	exec sh /tmp/passwall-gl-uninstall.sh "$@"
	;;
esac

say "Stopping PassWall"
/etc/init.d/passwall stop >/dev/null 2>&1
/etc/init.d/passwall disable >/dev/null 2>&1
/etc/init.d/passwall_server stop >/dev/null 2>&1

say "Removing packages"
# Installed either as one package (uploaded through a web page) or as the
# bundle's separate packages. Packages from GL's feed stay; other things may
# depend on them.
if opkg status passwall-gl-full | grep -q '^Status: .* installed'; then
	opkg remove passwall-gl-full
else
	opkg remove passwall-gl luci-app-passwall
	opkg remove xray-core geoview chinadns-ng dns2socks microsocks tcping ipt2socks \
		v2ray-geoip v2ray-geosite 2>/dev/null
fi

say "Undoing PassWall's settings changes"
uci -q delete firewall.passwall
uci -q delete firewall.passwall_server
uci commit firewall
while uci -q delete ucitrack.@passwall[-1]; do :; done
while uci -q delete ucitrack.@passwall_server[-1]; do :; done
uci commit ucitrack

restore() { # <uci key> <saved value>
	if [ -n "$2" ]; then uci -q set "$1=$2"; else uci -q delete "$1"; fi
}
if [ -f "$saved" ]; then
	localuse=$(sed -n 's/^localuse=//p' "$saved")
	max_requests=$(sed -n 's/^max_requests=//p' "$saved")
	restore dhcp.@dnsmasq[0].localuse "$localuse"
	uci commit dhcp
	restore uhttpd.main.max_requests "$max_requests"
	uci commit uhttpd
	rm -rf /etc/passwall-gl
fi

/etc/init.d/dnsmasq restart >/dev/null 2>&1
/etc/init.d/firewall restart >/dev/null 2>&1
# Drop the PassWall module GL's web server workers still hold.
nginx -s reload >/dev/null 2>&1
rm -f /tmp/passwall-gl-uninstall.sh
say "PassWall removed."
