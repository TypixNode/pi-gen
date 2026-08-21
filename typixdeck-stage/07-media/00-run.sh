#!/bin/bash -e

# Demo video for the first user: Coldplay live at River Plate, 1080p H.264
# so both the CM4 and CM5 can hardware-decode it.
#
# The 112MB file lives outside git (GitHub rejects LFS uploads to public
# forks): local builds use the copy in files/ (gitignored), CI downloads it
# from the media-assets release. Either way the pinned sha256 must match.

VIDEO="Coldplay_RiverPlate_1080_h264.mp4"
VIDEO_URL="https://github.com/TypixNode/pi-gen/releases/download/media-assets-v1/${VIDEO}"
VIDEO_SHA256="566b842eedd06318609ba6d377ceb5d4b70fa398c3982c04bb0d6838e9f0dc19"

checksum_ok() {
	echo "${VIDEO_SHA256}  files/${VIDEO}" | sha256sum -c - > /dev/null 2>&1
}

if [ ! -f "files/${VIDEO}" ] || ! checksum_ok; then
	# files/ only holds the gitignored video, so a fresh checkout lacks it
	mkdir -p files
	curl -fL --retry 3 -o "files/${VIDEO}" "${VIDEO_URL}"
	if ! checksum_ok; then
		echo "07-media: checksum mismatch for ${VIDEO}" >&2
		exit 1
	fi
fi

install -d "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/Videos"
install -m 644 "files/${VIDEO}" \
	"${ROOTFS_DIR}/home/${FIRST_USER_NAME}/Videos/${VIDEO}"
on_chroot << EOF
chown -R ${FIRST_USER_NAME}:${FIRST_USER_NAME} "/home/${FIRST_USER_NAME}/Videos"
EOF
