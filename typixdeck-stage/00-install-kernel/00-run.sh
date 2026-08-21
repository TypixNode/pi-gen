#!/bin/bash -e

# Install the TypixDeck kernel: rpi-6.18.y plus the dwc2 ISO-OUT split fix
# (drivers/usb/dwc2/hcd_queue.c: no ISOC OUT start-split in uframe 7), which
# is what makes USB audio behind the FE2.1 hub work on the CM5 carrier.
#
# The .deb files are produced by `make bindeb-pkg` in the kernel tree and are
# too big for git; drop them into files/debs/ before building (see the stage
# README for where they come from).

DEB_DIR="files/debs"
IMAGE_DEB="$(ls "${DEB_DIR}"/linux-image-*dwc2fix*_arm64.deb 2>/dev/null | head -n1 || true)"

if [ -z "${IMAGE_DEB}" ]; then
	if [ "${TYPIXDECK_REQUIRE_KERNEL:-0}" = "1" ]; then
		echo "ERROR: no linux-image .deb in ${STAGE_WORK_DIR:-$(pwd)}/${DEB_DIR}" >&2
		echo "Build it with 'make bindeb-pkg' in the patched kernel tree first." >&2
		exit 1
	fi
	# The debs are too big for git and are not available in CI, so the stock
	# kernel is kept: everything but USB audio behind the FE2.1 hub on the
	# CM5 carrier works with it. Set TYPIXDECK_REQUIRE_KERNEL=1 (factory
	# builds) to make a missing deb fatal instead.
	echo "WARNING: no dwc2fix kernel .deb in ${DEB_DIR}; keeping the stock kernel." >&2
	exit 0
fi

install -d "${ROOTFS_DIR}/var/tmp/typixdeck-debs"
cp "${DEB_DIR}"/linux-*dwc2fix*_arm64.deb "${ROOTFS_DIR}/var/tmp/typixdeck-debs/"

on_chroot << EOF
dpkg -i /var/tmp/typixdeck-debs/linux-image-*.deb
if ls /var/tmp/typixdeck-debs/linux-headers-*.deb >/dev/null 2>&1; then
	dpkg -i /var/tmp/typixdeck-debs/linux-headers-*.deb
fi
rm -rf /var/tmp/typixdeck-debs
EOF

# The version string is whatever the deb installed under /lib/modules.
KVER="$(ls "${ROOTFS_DIR}/lib/modules" | grep dwc2fix | head -n1)"
if [ -z "${KVER}" ]; then
	echo "ERROR: kernel deb did not populate /lib/modules with a dwc2fix kernel" >&2
	exit 1
fi
echo "Installed TypixDeck kernel ${KVER}"

# A vanilla bindeb-pkg deb has no Raspberry Pi OS boot hooks, so build the
# initramfs and place the boot files ourselves.
on_chroot << EOF
update-initramfs -c -k "${KVER}"
EOF

# vmlinuz from an arm64 bindeb-pkg is usually a gzipped Image; the Pi firmware
# can boot either, but ship it uncompressed to keep things unambiguous.
VMLINUZ="${ROOTFS_DIR}/boot/vmlinuz-${KVER}"
KERNEL_IMG="${ROOTFS_DIR}/boot/firmware/kernel-dwc2fix.img"
if [ "$(od -An -tx1 -N2 "${VMLINUZ}" | tr -d ' ')" = "1f8b" ]; then
	zcat "${VMLINUZ}" > "${KERNEL_IMG}"
else
	cp "${VMLINUZ}" "${KERNEL_IMG}"
fi

cp "${ROOTFS_DIR}/boot/initrd.img-${KVER}" \
	"${ROOTFS_DIR}/boot/firmware/initramfs-dwc2fix"

# Ship the DTBs and overlays that were built together with this kernel, so the
# device tree matches the 6.18 drivers instead of the stock kernel's. An apt
# upgrade of the stock kernel packages will write its own DTBs back over
# these, which is harmless for the stock kernel and is the documented
# trade-off of this approach.
KLIB="${ROOTFS_DIR}/usr/lib/linux-image-${KVER}"
cp "${KLIB}"/broadcom/bcm2712*.dtb "${ROOTFS_DIR}/boot/firmware/"
cp "${KLIB}"/overlays/* "${ROOTFS_DIR}/boot/firmware/overlays/"

# Boot this kernel by name, on the CM5 ONLY. The dwc2 fix matters only
# there: the CM5 carrier routes USB through the dwc2 controller
# (dtoverlay=dwc2,dr_mode=host), while the CM4 runs otg_mode=1 on the 2711
# built-in XHCI, which has no ISO-OUT split problem - and the CM4 firmware
# does not boot this image anyway (stuck on the rainbow splash, verified
# on-device). Everything else keeps the stock kernel8.img/kernel_2712.img,
# which apt upgrades keep maintaining as the fallback.
cat >> "${ROOTFS_DIR}/boot/firmware/config.txt" << EOF

# TypixDeck: the CM5 boots the dwc2-fixed kernel (USB audio behind the
# FE2.1 hub); the CM4 needs no fix (otg_mode=1 XHCI) and stays on the
# stock kernel. Comment out to fall back to kernel_2712.img on the CM5.
[cm5]
kernel=kernel-dwc2fix.img
initramfs initramfs-dwc2fix followkernel
[all]
EOF
