#!/bin/bash -e
# Fill imager/typixnode-os.json in from a built image.
#
#   imager/update-json.sh <TypixDeckOS.img.xz> [download-url] [release-date]
#
# Computes image_download_size/image_download_sha256 from the archive and
# extract_size/extract_sha256 by streaming it through xz, then rewrites the
# TypixDeckOS entry in imager/typixnode-os.json (a thin wrapper around
# scripts/make-os-list-json). The url defaults to the GitHub Releases path
# for a tag named after the archive; pass the real one once the release
# exists, then commit the JSON so the raw URL Imager polls stays current.

ARCHIVE="${1:?usage: update-json.sh <TypixDeckOS.img.xz> [download-url] [release-date]}"
BASENAME="$(basename "${ARCHIVE}")"
TAG="${BASENAME%.img.xz}"
URL="${2:-https://github.com/TypixNode/pi-gen/releases/download/${TAG}/${BASENAME}}"
DATE="${3:-$(date +%Y-%m-%d)}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JSON="${SCRIPT_DIR}/typixnode-os.json"

"${SCRIPT_DIR}/../scripts/make-os-list-json" \
	--archive "${ARCHIVE}" \
	--url "${URL}" \
	--name "TypixDeckOS (64-bit)" \
	--description "Raspberry Pi OS Trixie with the labwc desktop for the TypixDeck / TypixNode handheld (CM5): dwc2-fixed 6.18 kernel, 3.2\" 1024x768 DPI panel and GT911 touch preconfigured." \
	--icon "https://raw.githubusercontent.com/TypixNode/pi-gen/typixdeck/imager/typixnode.png" \
	--release-date "${DATE}" \
	--init-format cloudinit-rpi \
	--devices pi5-64bit \
	--capabilities rpi_connect \
	--website "https://github.com/TypixNode/pi-gen" \
	--merge-into "${JSON}" \
	--output "${JSON}"

echo "Updated ${JSON}:"
python3 -c "import json,sys; e=[o for o in json.load(open('${JSON}'))['os_list'] if o['name']=='TypixDeckOS (64-bit)'][0]; print(json.dumps(e, indent=2))"
