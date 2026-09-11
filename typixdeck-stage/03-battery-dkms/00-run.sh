#!/bin/bash -e

# STC3117 battery gauge driver (Pi side of the I2C mux) as a DKMS module.
#
# Raspberry Pi OS kernels leave CONFIG_FUEL_GAUGE_STC3117 unset, so the
# mainline v6.18 driver is built out-of-tree - with the TypixDeck fixes
# documented in linux/stc3117-fuel-gauge/README.md of the TypixDeck repo
# (16x16-bit OCV table, percent CAPACITY, signed current, read-only takeover
# of a gauge the ESP32 already configured, probe survives an unreachable
# chip). DKMS registers the source under /usr/src and rebuilds it whenever a
# new kernel + matching linux-headers package land (dkms kernel postinst
# hook), so apt kernel upgrades keep the battery indicator working.
#
# Here the module is built for every kernel in the image that has headers
# (stock v8 + 2712, and the dwc2fix kernel when 00-install-kernel shipped
# one). The overlay comes from 01-overlays / 02-config-txt.

PKG=stc3117-fuel-gauge
VER=6.18
SRC="${ROOTFS_DIR}/usr/src/${PKG}-${VER}"

install -d "${SRC}"
install -m 644 files/stc3117_fuel_gauge.c files/Makefile files/dkms.conf "${SRC}/"

on_chroot << CHROOT
set -e
dkms add -m ${PKG} -v ${VER} || true   # already added when re-running the stage
built=0
for k in /lib/modules/*/; do
	kver=\$(basename "\$k")
	if [ -e "/lib/modules/\${kver}/build/Makefile" ]; then
		dkms install --force -m ${PKG} -v ${VER} -k "\${kver}"
		built=\$((built+1))
	else
		echo "WARNING: no headers for \${kver}; dkms builds it once headers are installed" >&2
	fi
done
[ "\$built" -gt 0 ] || { echo "ERROR: stc3117 module built for no kernel" >&2; exit 1; }
dkms status
CHROOT
