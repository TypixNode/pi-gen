# shellcheck shell=bash
# The STC3117 battery gauge driver from typixdeck-stage/03-battery-dkms has to
# be built for every kernel the image can boot - the dwc2fix one included -
# or the battery reads N/A on that module.

for kdir in "$ROOT"/usr/lib/modules/*/; do
	kver="$(basename "$kdir")"
	check "stc3117 gauge module built for $kver" \
		sh -c 'ls "$1"/updates/dkms/stc3117_fuel_gauge.ko* >/dev/null 2>&1' _ "$kdir"
done
