#!/bin/bash
# Runs inside the OpenWrt SDK image (see tools/build-deps.sh). Builds PassWall's
# C helpers, ChinaDNS-NG and the geo data from the pinned PassWall package feed,
# so they link against the same musl as the router's firmware.
set -euo pipefail
: "${FEED_REPO:?}" "${FEED_REF:?}" "${PACKAGES:?}"

# Runs from the image's working directory, where the SDK lives
# (/home/build/openwrt in the 21.02 images, /builder in newer ones).
# Newer images download the SDK itself on first run.
[ -x ./setup.sh ] && ./setup.sh

{
	grep -E '^src-git(-full)? (base|packages) ' feeds.conf.default
	echo "src-git passwall_packages ${FEED_REPO}^${FEED_REF}"
} > feeds.conf

./scripts/feeds update -a
# shellcheck disable=SC2086
./scripts/feeds install -p passwall_packages $PACKAGES
make defconfig

for p in $PACKAGES; do
	extra=
	# Git sources are pinned to a commit (PKG_SOURCE_VERSION), but the 21.02 SDK
	# packs the checkout differently from the newer SDK that produced
	# PKG_MIRROR_HASH, so that tarball hash can never match here. The pinned
	# commit still fixes the code; only the tarball check is skipped.
	if grep -q '^PKG_SOURCE_PROTO:=git' "feeds/passwall_packages/$p/Makefile"; then
		echo "note: $p comes from git at $(sed -n 's/^PKG_SOURCE_VERSION:=//p' "feeds/passwall_packages/$p/Makefile"); skipping the tarball hash"
		extra=PKG_MIRROR_HASH=skip
	fi
	make "package/$p/compile" -j"$(nproc)" V=s $extra || { echo "build failed: $p" >&2; exit 1; }
done

find bin/packages -path '*passwall_packages*' -name '*.ipk' -exec cp -v {} /out/ \;
# The SDK image starts with an empty dl/, so it now holds exactly what these
# builds downloaded: sources, plus ChinaDNS-NG's upstream binary and the geo data.
mkdir -p /out/sources
cp -v dl/* /out/sources/
# The package recipes too: Makefiles, patches, and sources that live in the
# feed itself rather than being downloaded (dns2socks).
# shellcheck disable=SC2086
tar -czf /out/sources/openwrt-package-recipes.tar.gz -C feeds/passwall_packages $PACKAGES
