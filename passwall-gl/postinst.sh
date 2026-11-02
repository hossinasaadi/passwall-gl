#!/bin/sh
# passwall-gl postinst: GL's web server keeps each RPC module loaded in its
# worker processes, so start fresh workers to pick up this version. The
# reload is graceful; the admin panel stays up.
[ -n "${IPKG_INSTROOT}" ] || nginx -s reload >/dev/null 2>&1 || true
