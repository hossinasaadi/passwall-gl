#!/bin/sh
# PassWall for GL.iNet: installer. Run on the router as root from the
# unpacked bundle:   sh install.sh
#
# It checks the router, notes the few settings PassWall's installer changes
# (so uninstall.sh can put them back), then installs everything in one opkg
# transaction. PassWall stays switched off until you turn it on under
# VPN > PassWall.

set -eu

here=$(cd "$(dirname "$0")" && pwd)
arch=$(cat "$here/ARCH")
saved=/etc/passwall-gl/saved
# Needed by PassWall's iptables rules but not a package dependency (upstream
# selects these in its build config instead). The rest of that list ships
# with GL's firmware.
feed_extras="iptables-mod-iprange"

say() { printf '%s\n' "$*"; }
die() { say "Error: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run this as root"
[ -f /etc/glversion ] || die "this is not GL.iNet firmware"
case "$(cat /etc/glversion)" in
4.*) ;;
*) die "needs GL.iNet firmware 4.x (found $(cat /etc/glversion))" ;;
esac
grep -q "DISTRIB_RELEASE='21.02" /etc/openwrt_release ||
	die "this bundle is built for OpenWrt 21.02-based firmware"
opkg print-architecture | grep -q " $arch " ||
	die "this bundle is for $arch routers"
[ -d /usr/lib/oui-httpd/rpc ] && [ -d /usr/share/oui/menu.d ] ||
	die "GL admin panel files not found where expected"

free_kb=$(df -k /overlay | awk 'NR==2 {print $4}')
[ "${free_kb:-0}" -ge 61440 ] || die "need at least 60 MB free in /overlay"

# PassWall's first-run script sets these two; keep the originals once.
if [ ! -f "$saved" ]; then
	mkdir -p "$(dirname "$saved")"
	{
		echo "localuse=$(uci -q get dhcp.@dnsmasq[0].localuse)"
		echo "max_requests=$(uci -q get uhttpd.main.max_requests)"
	} > "$saved"
fi

say "Updating package lists"
opkg update >/dev/null || die "opkg update failed; is the router online?"

say "Checking dependencies"
# opkg installs whatever it can when a dependency is missing, so try the whole
# set without changing anything first.
opkg install --noaction $feed_extras "$here"/packages/*.ipk >/tmp/passwall-gl-check.log 2>&1 || {
	cat /tmp/passwall-gl-check.log >&2
	die "some dependencies can't be installed; nothing was changed"
}

say "Installing"
# The bundled packages plus what they need from GL's feed (lyaml,
# coreutils-nohup and so on).
opkg install $feed_extras "$here"/packages/*.ipk

say ""
say "Done. Open the GL admin panel and go to VPN > PassWall."
say "PassWall is off until you add a node and switch it on."
say "To remove it later: sh /usr/share/passwall-gl/uninstall.sh"
