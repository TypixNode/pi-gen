#!/bin/bash -e

# TypixDeck hardware: the 3.2" 1024x768 DPI panel (HD317001C40 / JD9168S) and
# its GT911 touch controller. The overlay sources live in the CyberFold repo
# under display/device_tree/HD317001C40_1024x768/ and are decompiled-style
# .dts with explicit __fixups__, so they are compiled with plain dtc (no -@).

OVERLAYS="vc4-kms-dpi-3inch2-1024x768 gt911-touch-3inch2-1024x768"

install -d "${ROOTFS_DIR}/var/tmp/typixdeck-overlays"
for ov in ${OVERLAYS}; do
	install -m 644 "files/${ov}.dts" "${ROOTFS_DIR}/var/tmp/typixdeck-overlays/"
done

for ov in ${OVERLAYS}; do
	on_chroot << EOF
dtc -q -I dts -O dtb \
	-o "/boot/firmware/overlays/${ov}.dtbo" \
	"/var/tmp/typixdeck-overlays/${ov}.dts"
EOF
done

on_chroot << EOF
rm -rf /var/tmp/typixdeck-overlays
EOF

cat >> "${ROOTFS_DIR}/boot/firmware/config.txt" << EOF

# TypixDeck: 3.2" 1024x768 DPI panel + GT911 touch
dtoverlay=vc4-kms-dpi-3inch2-1024x768
dtoverlay=gt911-touch-3inch2-1024x768

# The UART pins are taken by the DPI panel; keep the serial console off.
enable_uart=0
EOF
