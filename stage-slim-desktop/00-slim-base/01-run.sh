#!/bin/bash -e

# Wi-Fi/Bluetooth blobs for chipsets that no Compute Module carries, the second
# kernel flavour (rpi-2712 only boots on BCM2712), the kernel headers with their
# cross-toolchain, and tools that are one `apt install` away on the running
# system.
PURGE_DEFAULT="
linux-image-rpi-2712
linux-headers-rpi-v8
linux-headers-rpi-2712
build-essential
gdb
manpages-dev
mkvtoolnix
rpi-update
rpi-connect-lite
"

if [ "${ENABLE_CLOUD_INIT}" != "1" ]; then
	PURGE_DEFAULT="${PURGE_DEFAULT} cloud-init rpi-cloud-init-mods"
fi

KEEP_FIRMWARE="${SLIM_KEEP_FIRMWARE-firmware-brcm80211}"
for FW in firmware-atheros firmware-libertas firmware-realtek firmware-mediatek \
		firmware-brcm80211 firmware-misc-nonfree; do
	case " ${KEEP_FIRMWARE} " in
		*" ${FW} "*) ;;
		*) PURGE_DEFAULT="${PURGE_DEFAULT} ${FW}" ;;
	esac
done

PURGE="${SLIM_PURGE_PACKAGES-${PURGE_DEFAULT}}"

on_chroot <<- EOF
	set -e
	INSTALLED=""
	for PKG in ${PURGE}; do
		if dpkg-query -W -f='\${Status}' "\$PKG" 2>/dev/null | grep -q "ok installed"; then
			INSTALLED="\$INSTALLED \$PKG"
		fi
	done
	if [ -n "\$INSTALLED" ]; then
		apt-get purge -y \$INSTALLED
	fi
	apt-get autoremove --purge -y
EOF
