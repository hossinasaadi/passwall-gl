#!/bin/sh
# Capture the README screenshots of the GL page from the local preview, which
# uses sample data, so no real nodes or addresses end up in the images.
# (panel-basic-settings.png and panel-node-list.png are captures of the real
# admin panel with the sample node painted in; they aren't made here.)
#
# Start the preview first:
#   npm --prefix passwall-gl/ui run dev -- --port 5178
# then:
#   tools/screenshots.sh

set -eu
cd "$(dirname "$0")/.."

CHROME=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
BASE=${BASE:-http://localhost:5178/}
OUT=.github/screenshots

mkdir -p "$OUT"

# shot <name> <width> <height> <query> [page]
shot() {
	"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
		--window-size="$2,$3" --virtual-time-budget=8000 \
		--screenshot="$PWD/$OUT/$1.png" "${BASE}${5:-}?shot=1&$4" >/dev/null 2>&1
	echo "wrote $OUT/$1.png"
}

shot subscriptions 1100 700 "tab=subscriptions&run=edit"
shot routing 1100 690 "tab=routing"

# Phone width: Chrome won't go below ~500 px, so render in a centred 390 px
# frame (phone.html) and keep the middle 780 px of the 2x image.
shot mobile 500 844 "tab=status&run=probe" phone.html
sips -c 1688 780 "$OUT/mobile.png" >/dev/null
