#!/bin/bash -e

# Wi-Fi/Bluetooth blobs for chipsets that no Compute Module carries, cloud-init,
# the compiler toolchain and tools that are one `apt install` away on the
# running system.
PURGE=(
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

# The kernel flavour to keep: rpi-v8 covers BCM2837/2711, rpi-2712 is Raspberry
# Pi 5 only. Both are installed by stage0 along with their headers, which drag in
# a whole cross-toolchain.
KEEP_KERNEL="${SLIM_KEEP_KERNEL:-rpi-v8}"

# apt refuses to autoremove installed linux-image and linux-headers packages
# (APT::NeverAutoRemove in 01autoremove), so purging the metapackages leaves the
# versioned packages, their modules and their build dependencies in place. They
# have to be named, and only dpkg inside the image knows their versioned names.
# ${PURGE[*]} rather than the array so the list reaches the chroot as one line.
on_chroot <<- EOF
	installed() {
		dpkg-query -W -f='\${Status}\n' "\$1" 2>/dev/null | grep -q "ok installed"
	}

	PURGE_LIST=""
	for PKG in ${PURGE[*]}; do
		if installed "\$PKG"; then
			PURGE_LIST="\$PURGE_LIST \$PKG"
		fi
	done

	for PKG in \$(dpkg-query -W -f='\${Package}\n' 'linux-headers-*' 2>/dev/null); do
		if installed "\$PKG"; then
			PURGE_LIST="\$PURGE_LIST \$PKG"
		fi
	done
	for PKG in \$(dpkg-query -W -f='\${Package}\n' 'linux-image-*' 2>/dev/null); do
		case "\$PKG" in
			*${KEEP_KERNEL}) continue ;;
		esac
		if installed "\$PKG"; then
			PURGE_LIST="\$PURGE_LIST \$PKG"
		fi
	done

	if [ -n "\$PURGE_LIST" ]; then
		apt-get purge -y \$PURGE_LIST
	fi
	apt-get autoremove --purge -y
EOF
