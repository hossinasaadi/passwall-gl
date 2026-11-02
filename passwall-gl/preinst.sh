#!/bin/sh
# passwall-gl preinst: note, once, the two settings PassWall's first-run
# script changes, so /usr/share/passwall-gl/uninstall.sh can put them back.
# opkg runs every preinst before any postinst, so these are the values from
# before PassWall's script ran.
[ -n "${IPKG_INSTROOT}" ] && exit 0
saved=/etc/passwall-gl/saved
[ -f "$saved" ] && exit 0
mkdir -p /etc/passwall-gl
{
	echo "localuse=$(uci -q get dhcp.@dnsmasq[0].localuse)"
	echo "max_requests=$(uci -q get uhttpd.main.max_requests)"
} > "$saved"
exit 0
