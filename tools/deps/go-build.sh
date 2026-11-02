#!/bin/bash
# Runs inside the Go image (see tools/build-deps.sh). Builds Xray and geoview
# as static Linux binaries from the source versions and hashes pinned in
# PassWall's package feed, with the same flags its OpenWrt Makefiles use.
set -euo pipefail
# Without this a failed checksum inside $(fetch ...) would not stop the build.
shopt -s inherit_errexit
: "${FEED_RAW:?}" "${GOARCH:?}"

stage=/out/stage
mkdir -p "$stage"
work=$(mktemp -d)

mk_var() {
	sed -n "s/^$2:=//p" "$1" | head -n 1
}

# fetch <package>: download and verify its source, print its version
fetch() {
	local pkg=$1 mk="$work/$1.mk" ver hash url
	curl -fsSL "$FEED_RAW/$pkg/Makefile" -o "$mk"
	ver=$(mk_var "$mk" PKG_VERSION)
	hash=$(mk_var "$mk" PKG_HASH)
	url=$(mk_var "$mk" PKG_SOURCE_URL)
	url=${url//\$(PKG_VERSION)/$ver}
	url=${url%\?}
	curl -fsSL "$url" -o "$work/$pkg.tar.gz"
	echo "$hash  $work/$pkg.tar.gz" | sha256sum -c - >&2
	mkdir -p "$work/$pkg"
	tar -xzf "$work/$pkg.tar.gz" -C "$work/$pkg" --strip-components=1
	echo "$ver" > "$stage/$pkg.version"
	echo "$ver"
}

export CGO_ENABLED=0 GOOS=linux GOARCH GOFLAGS=-trimpath

ver=$(fetch xray-core)
(cd "$work/xray-core" && go build \
	-ldflags "-s -w -buildid= -X github.com/xtls/xray-core/core.build=OpenWrt -X github.com/xtls/xray-core/core.version=$ver" \
	-o "$stage/xray" ./main)

fetch geoview >/dev/null
(cd "$work/geoview" && go build -ldflags "-s -w -buildid=" -o "$stage/geoview" .)

ls -l "$stage"
