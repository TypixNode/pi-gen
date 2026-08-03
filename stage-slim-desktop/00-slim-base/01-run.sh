#!/bin/bash -e

# Wi-Fi/Bluetooth blobs for chipsets that no Compute Module carries, the second
# kernel flavour (rpi-2712 only boots on BCM2712), the kernel headers with their
# cross-toolchain, and tools that are one `apt install` away on the running
# system.
PURGE=(
	linux-image-rpi-2712
	linux-headers-rpi-v8
	linux-headers-rpi-2712
	build-essential
	gdb
	manpages-dev
	mkvtoolnix
	rpi-update
	rpi-connect-lite
)

if [ "${ENABLE_CLOUD_INIT}" != "1" ]; then
	PURGE+=(cloud-init rpi-cloud-init-mods)
fi

KEEP_FIRMWARE="${SLIM_KEEP_FIRMWARE-firmware-brcm80211}"
for FW in firmware-atheros firmware-libertas firmware-realtek firmware-mediatek \
		firmware-brcm80211 firmware-misc-nonfree; do
	case " ${KEEP_FIRMWARE} " in
		*" ${FW} "*) ;;
		*) PURGE+=("${FW}") ;;
	esac
done

if [ -n "${SLIM_PURGE_PACKAGES+set}" ]; then
	read -r -a PURGE <<< "${SLIM_PURGE_PACKAGES}"
fi

# ${PURGE[*]} rather than a here-document of the array so that the list reaches
# the chroot's `for` loop as a single line.
on_chroot <<- EOF
	INSTALLED=""
	for PKG in ${PURGE[*]}; do
		if dpkg-query -W -f='\${Status}' "\$PKG" 2>/dev/null | grep -q "ok installed"; then
			INSTALLED="\$INSTALLED \$PKG"
		fi
	done
	if [ -n "\$INSTALLED" ]; then
		apt-get purge -y \$INSTALLED
	fi
	apt-get autoremove --purge -y
EOF
