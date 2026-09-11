#!/bin/bash -e

# Dev loop, Mac side: stream the newest local build onto the TF card of a
# TypixDeck that is currently running from its SSD, then inject the SSD
# system's Wi-Fi profiles so the candidate comes up on the network.
#
#   scripts/dev-flash-tf.sh [image.img]     (default: newest deploy/*-dev.img)
#   PI=pi@<addr> scripts/dev-flash-tf.sh    (default target below)

PI="${PI:-pi@192.168.50.98}"
TF_DEV=/dev/mmcblk0

cd "$(dirname "$0")/.."

IMG="${1:-$(ls -t deploy/image_*-dev.img 2>/dev/null | head -n1)}"
if [ -z "${IMG}" ] || [ ! -f "${IMG}" ]; then
	echo "ERROR: no image given and no deploy/image_*-dev.img found" >&2
	exit 1
fi

echo "image : ${IMG} ($(du -h "${IMG}" | cut -f1))"
echo "target: ${PI} ${TF_DEV}"

# Never dd over the disk the Pi is running from.
ROOTDEV="$(ssh "${PI}" findmnt -no SOURCE /)"
if [ -z "${ROOTDEV}" ]; then
	echo "ERROR: cannot determine the root device on ${PI}; refusing to flash" >&2
	exit 1
fi
case "${ROOTDEV}" in
	${TF_DEV}*)
		echo "ERROR: ${PI} is running FROM the TF card (${ROOTDEV})." >&2
		echo "Boot it from the SSD first (scripts/dev-boot.sh ssd)." >&2
		exit 1
		;;
esac
echo "Pi rootfs is on ${ROOTDEV} (good, not the TF card)"
ssh "${PI}" "lsblk -dno NAME,SIZE,MODEL ${TF_DEV}"

read -r -p "Flash this TF card? [y/N] " ANSWER
[ "${ANSWER}" = "y" ] || exit 1

time zstd -T0 -3 -c "${IMG}" | ssh "${PI}" \
	"zstd -dc | sudo dd of=${TF_DEV} bs=8M conv=fsync status=progress"

echo "Injecting Wi-Fi profiles from the SSD system into the candidate..."
ssh "${PI}" "sudo partprobe ${TF_DEV} 2>/dev/null; sudo udevadm settle; \
	sudo mount ${TF_DEV}p2 /mnt \
	&& sudo cp -a /etc/NetworkManager/system-connections/. \
		/mnt/etc/NetworkManager/system-connections/ 2>/dev/null; \
	sudo umount /mnt"

echo "Done. Boot into it with: scripts/dev-boot.sh tf"
