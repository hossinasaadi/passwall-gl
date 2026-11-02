#!/bin/sh
# Pack the end-user bundle: install.sh plus every package it installs.
#   tools/make-bundle.sh   ->   dist/passwall-gl-<version>-<arch>.tar.gz
#
# Run tools/build-deps.sh first. The bundle is installed on the router with:
#   tar -xzf passwall-gl-*.tar.gz && sh passwall-gl-*/install.sh

set -eu
cd "$(dirname "$0")/.."

ARCH=aarch64_cortex-a53
version=$(sed -n 's/^PKG_VERSION:=//p' passwall-gl/Makefile)
name="passwall-gl-$version-$ARCH"

ls dist/deps/*_"$ARCH".ipk >/dev/null 2>&1 || {
	echo "No dependency packages for $ARCH in dist/deps; run tools/build-deps.sh first." >&2
	exit 1
}

npm --prefix passwall-gl/ui run build
python3 -I tools/build-ipk.py

stage="dist/bundle/$name"
rm -rf dist/bundle
mkdir -p "$stage/packages"
cp dist/luci-app-passwall_*_all.ipk dist/passwall-gl_*_all.ipk dist/deps/*.ipk "$stage/packages/"
cp passwall-gl/bundle/install.sh "$stage/"
echo "$ARCH" > "$stage/ARCH"
cp LICENSE "$stage/LICENSE"

{
	echo "Sources for the packages in this bundle"
	echo
	echo "PassWall for GL.iNet (luci-app-passwall, passwall-gl): this repository, branch gl-main,"
	echo "commit $(git rev-parse HEAD). It is a fork of https://github.com/Openwrt-Passwall/openwrt-passwall."
	if [ -n "$(git status --porcelain)" ]; then
		echo "Built with uncommitted changes on top of that commit: a development build, not a release."
	fi
	echo
	echo "The other packages are built from the sources and hashes pinned in"
	echo "https://github.com/Openwrt-Passwall/openwrt-passwall-packages at commit"
	echo "$(sed -n 's/^FEED_REF=\([0-9a-f]*\).*/\1/p' tools/build-deps.sh), by tools/build-deps.sh in this repository."
	echo
	echo "Package licenses:"
	for f in "$stage"/packages/*.ipk; do
		tar -xzOf "$f" ./control.tar.gz | tar -xzOf - ./control |
			awk -F': ' '/^Package:/ {p=$2} /^Version:/ {v=$2} /^License:/ {l=$2} END {printf "  %-20s %-22s %s\n", p, v, l}'
	done
} > "$stage/SOURCES.txt"

COPYFILE_DISABLE=1 tar -C dist/bundle -czf "dist/$name.tar.gz" "$name"
echo "built dist/$name.tar.gz ($(du -h "dist/$name.tar.gz" | cut -f1))"
