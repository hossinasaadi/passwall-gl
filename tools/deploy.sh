#!/bin/sh
# Copy development builds to a router. Changes the router, so read first.
#
#   tools/deploy.sh page [host]   Copy only the GL page, its RPC module and
#                                 backend. Fast; needs PassWall already installed.
#   tools/deploy.sh ipk  [host]   Copy dist/*.ipk to /tmp and install with opkg.
#
# host defaults to root@192.168.8.1. Extra ssh options can go in SSH_OPTS,
# e.g. to reuse an open connection:
#   SSH_OPTS="-o ControlPath=~/.ssh/cm-glrouter -o BatchMode=yes" tools/deploy.sh page
# Build first:
#   npm --prefix passwall-gl/ui run build && python3 tools/build-ipk.py

set -e
cd "$(dirname "$0")/.."

mode=${1:-}
host=${2:-root@192.168.8.1}

# Dropbear has no SFTP server, so stream files over plain ssh instead of scp.
push() {
	# shellcheck disable=SC2086
	ssh $SSH_OPTS "$host" "mkdir -p '$(dirname "$2")' && cat > '$2'" < "$1"
}

case "$mode" in
page)
	r=passwall-gl/root
	push $r/usr/share/oui/menu.d/passwall.json /usr/share/oui/menu.d/passwall.json
	push $r/usr/lib/oui-httpd/rpc/passwall /usr/lib/oui-httpd/rpc/passwall
	push $r/usr/share/gl-validator.d/passwall.lua /usr/share/gl-validator.d/passwall.lua
	push $r/usr/share/passwall-gl/api.lua /usr/share/passwall-gl/api.lua
	push $r/www/views/gl-sdk4-ui-passwall.common.js.gz /www/views/gl-sdk4-ui-passwall.common.js.gz
	# GL's web server workers cache RPC modules; start fresh ones (graceful).
	# shellcheck disable=SC2086
	ssh $SSH_OPTS "$host" 'nginx -s reload'
	echo "Page copied. Reload the GL admin panel; it is under VPN > PassWall."
	;;
ipk)
	for f in dist/*.ipk; do
		push "$f" "/tmp/$(basename "$f")"
	done
	# shellcheck disable=SC2086
	ssh $SSH_OPTS "$host" 'opkg install /tmp/luci-app-passwall_*_all.ipk /tmp/passwall-gl_*_all.ipk'
	;;
*)
	sed -n '2,13p' "$0"
	exit 1
	;;
esac
