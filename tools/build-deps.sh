#!/bin/sh
# Build PassWall's binary dependencies for GL firmware based on OpenWrt 21.02
# on aarch64_cortex-a53 (GL-MT3000 and similar). Writes dist/deps/*.ipk.
#
# Needs Docker. The first run downloads the OpenWrt 21.02.3 SDK image
# (about 590 MB, x86-64, emulated on Apple Silicon), the Go image and the
# package sources. Versions and source hashes come from PassWall's package
# feed at the pinned commit below.

set -eu
cd "$(dirname "$0")/.."

ARCH=aarch64_cortex-a53
GOARCH=arm64
SDK_IMAGE="openwrt/sdk:${ARCH}-21.02.3"
GO_IMAGE="golang:1.27-bookworm"

FEED_REPO=https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git
FEED_REF=da712cf06cf4e6fd39e147fb36e6ec936003fcc9 # 2026-10-31
FEED_RAW="https://raw.githubusercontent.com/Openwrt-Passwall/openwrt-passwall-packages/$FEED_REF"

# What GL's own feed lacks (see recon.txt). Everything else PassWall needs is
# already on the router or installable from GL's feed.
SDK_PACKAGES="dns2socks microsocks tcping ipt2socks chinadns-ng v2ray-geodata"

out="$PWD/dist/deps"
rm -rf "$out"
mkdir -p "$out/stage"

echo "== C helpers, ChinaDNS-NG and geo data (OpenWrt 21.02.3 SDK)"
docker run --rm --platform linux/amd64 \
	-e FEED_REPO="$FEED_REPO" -e FEED_REF="$FEED_REF" -e PACKAGES="$SDK_PACKAGES" \
	-v "$out:/out" -v "$PWD/tools/deps:/scripts:ro" \
	"$SDK_IMAGE" bash /scripts/sdk-build.sh

echo "== Xray and geoview (Go, static)"
docker run --rm \
	-e FEED_RAW="$FEED_RAW" -e GOARCH="$GOARCH" \
	-v "$out:/out" -v "$PWD/tools/deps:/scripts:ro" \
	"$GO_IMAGE" bash /scripts/go-build.sh

python3 -I tools/build-ipk.py bin --out "$out" --arch "$ARCH" \
	--name xray-core --version "$(cat "$out/stage/xray-core.version")-1" \
	--depends ca-bundle --license MPL-2.0 \
	--description "Xray, Penetrates Everything (built from XTLS/Xray-core)" \
	"$out/stage/xray=/usr/bin/xray"

python3 -I tools/build-ipk.py bin --out "$out" --arch "$ARCH" \
	--name geoview --version "$(cat "$out/stage/geoview.version")-1" \
	--license Apache-2.0 \
	--description "Geo data parser for PassWall (built from snowie2000/geoview)" \
	"$out/stage/geoview=/usr/bin/geoview"

rm -rf "$out/stage"
ls -l "$out"
