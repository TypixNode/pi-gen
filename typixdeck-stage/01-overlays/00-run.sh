#!/bin/bash -e

# TypixDeck hardware overlays, compiled from source inside the chroot so the
# shipped .dtbo files are always reproducible from the .dts in this repo.
#
# The sources come from the CyberFold repo,
# display/device_tree/HD317001C40_1024x768/:
#   * vc4-kms-dpi-3inch2-1024x768 - 3.2" 1024x768 DPI panel (HD317001C40/JD9168S)
#   * gt911-touch-3inch2-1024x768 - GT911 touch over bit-banged I2C
#   * pwm-backlight-3inch2-bcm    - PWM backlight, BCM283x SoCs (&pwm, GPIO18 ALT5)
#   * pwm-backlight-3inch2-rp1    - PWM backlight, CM5/BCM2712 (&rp1_pwm0 chan 2)
#
# dtc emits "unit_address_vs_reg" style warnings for the decompiled-style
# sources (vc4/gt911); they are harmless and the output is bit-identical to
# the production .dtbo files.

OVERLAYS="vc4-kms-dpi-3inch2-1024x768 gt911-touch-3inch2-1024x768 pwm-backlight-3inch2-bcm pwm-backlight-3inch2-rp1"

install -d "${ROOTFS_DIR}/var/tmp/typixdeck-overlays"
for ov in ${OVERLAYS}; do
	install -m 644 "files/${ov}.dts" "${ROOTFS_DIR}/var/tmp/typixdeck-overlays/"
done

for ov in ${OVERLAYS}; do
	on_chroot << EOF
dtc -@ -I dts -O dtb \
	-o "/boot/firmware/overlays/${ov}.dtbo" \
	"/var/tmp/typixdeck-overlays/${ov}.dts"
EOF
done

rm -rf "${ROOTFS_DIR}/var/tmp/typixdeck-overlays"
