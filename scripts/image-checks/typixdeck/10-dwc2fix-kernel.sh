# shellcheck shell=bash
# The dwc2-fixed CM5 kernel from typixdeck-stage/00-install-kernel. Without it
# USB audio behind the FE2.1 hub on the CM5 carrier plays silence - and until
# 2026-09 every CI image shipped without it, with only a warning in the build
# log. Required when the variant config sets TYPIXDECK_REQUIRE_KERNEL=1.

if [ "${TYPIXDECK_REQUIRE_KERNEL:-0}" != 1 ]; then
	skip "dwc2fix kernel" "not required by ${BUILD_CONFIG:-the environment}"
	return 0
fi

DWC2FIX_KVERS="$(ls "$ROOT/usr/lib/modules" 2>/dev/null | grep dwc2fix || true)"
DWC2FIX_COUNT="$(printf '%s' "$DWC2FIX_KVERS" | grep -c dwc2fix || true)"
check "exactly one dwc2fix kernel installed (found: ${DWC2FIX_KVERS:-none})" \
	test "$DWC2FIX_COUNT" -eq 1

check "boot partition has kernel-dwc2fix.img" test -s "$BOOT/kernel-dwc2fix.img"
check "boot partition has initramfs-dwc2fix" test -s "$BOOT/initramfs-dwc2fix"
check "config.txt boots kernel-dwc2fix.img under [cm5]" \
	config_txt_has cm5 "kernel=kernel-dwc2fix.img"
check "config.txt loads initramfs-dwc2fix under [cm5]" \
	config_txt_has cm5 "initramfs initramfs-dwc2fix followkernel"

if [ "$DWC2FIX_COUNT" -ne 1 ]; then
	skip "dwc2fix kernel contents" "no single dwc2fix kernel to inspect"
	return 0
fi

KVER="$DWC2FIX_KVERS"
check "kernel-dwc2fix.img is the $KVER kernel" \
	kernel_image_has_version "$BOOT/kernel-dwc2fix.img" "$KVER"

DWC2_KO="$(find "$ROOT/usr/lib/modules/$KVER" -path '*/drivers/usb/dwc2/dwc2.ko*' 2>/dev/null | head -n1)"
check "dwc2 driver is a module of $KVER" test -n "$DWC2_KO"
if [ -n "$DWC2_KO" ]; then
	# The fix itself: srcversion hashes the module's sources, so only a build
	# of the patched hcd_queue.c matches an entry of the allow-list.
	SRCVERSION="$(module_field "$DWC2_KO" srcversion)"
	check "dwc2.ko srcversion ${SRCVERSION:-unknown} is a known patched build (dwc2fix-srcversions)" \
		grep -qE "^${SRCVERSION:-none}([[:space:]]|$)" "$CHECK_DIR/dwc2fix-srcversions"
	# A stale initramfs brings the unpatched dwc2.ko back at boot.
	check "initramfs-dwc2fix carries the same dwc2.ko as the root filesystem" \
		initramfs_file_matches "$BOOT/initramfs-dwc2fix" "${DWC2_KO#"$ROOT"/}" "$DWC2_KO"
fi
