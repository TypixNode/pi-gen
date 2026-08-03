#!/bin/bash -e

# Wi-Fi/Bluetooth blobs for chipsets that no Compute Module carries, cloud-init,
# and tools that are one `apt install` away on the running system.
PURGE=(
	mkvtoolnix
	rpi-update
	rpi-connect-lite
)

if [ "${ENABLE_CLOUD_INIT}" != "1" ]; then
	PURGE+=(cloud-init rpi-cloud-init-mods)
fi

# The compiler, the debugger and the headers for the kernel that stays, so that
# out-of-tree modules can still be built on the device. Together they are about
# 250MB; drop them if the image is only ever going to run software from the
# archive.
KEEP_TOOLCHAIN="${SLIM_KEEP_TOOLCHAIN:-1}"
if [ "${KEEP_TOOLCHAIN}" != "1" ]; then
	PURGE+=(build-essential gdb manpages-dev)
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
# Pi 5 only. stage0 installs both along with both sets of headers.
KEEP_KERNEL="${SLIM_KEEP_KERNEL:-rpi-v8}"

# apt refuses to autoremove installed linux-image and linux-headers packages
# (APT::NeverAutoRemove in 01autoremove), so purging the metapackages would leave
# the versioned packages and their modules in place. They have to be named, and
# only dpkg inside the image knows their versioned names.
# ${PURGE[*]} rather than the array so the list reaches the chroot as one line.
on_chroot <<- EOF
	installed() {
		dpkg-query -W -f='\${Status}\n' "\$1" 2>/dev/null | grep -q "ok installed"
	}

	PURGE_LIST=""
	add_if_installed() {
		if installed "\$1"; then
			PURGE_LIST="\$PURGE_LIST \$1"
		fi
	}

	for PKG in ${PURGE[*]}; do
		add_if_installed "\$PKG"
	done

	keep_kernel_package() {
		case "\$1" in
		linux-headers-*)
			[ "${KEEP_TOOLCHAIN}" = "1" ] || return 1
			case "\$1" in
				# The -common- headers hold the build system every
				# flavour shares.
				*-common-*|*${KEEP_KERNEL}) return 0 ;;
				*) return 1 ;;
			esac
			;;
		*)
			case "\$1" in
				*${KEEP_KERNEL}) return 0 ;;
				*) return 1 ;;
			esac
			;;
		esac
	}

	for PKG in \$(dpkg-query -W -f='\${Package}\n' 'linux-image-*' 'linux-headers-*' \
			2>/dev/null); do
		keep_kernel_package "\$PKG" || add_if_installed "\$PKG"
	done

	if [ -n "\$PURGE_LIST" ]; then
		apt-get purge -y \$PURGE_LIST
	fi
	apt-get autoremove --purge -y
EOF
