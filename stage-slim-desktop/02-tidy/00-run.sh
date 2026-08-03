#!/bin/bash -e

# shellcheck source=../slim-functions
source "${STAGE_DIR}/slim-functions"

on_chroot <<- \EOF
	apt-get autoremove --purge -y
	apt-get clean
EOF

if [ "${SLIM_STRIP_DOCS:-1}" = "1" ]; then
	strip_docs "${ROOTFS_DIR}" "${LOCALE_DEFAULT%%_*}"
fi

rm -rf "${ROOTFS_DIR}"/var/cache/apt/*.bin
rm -rf "${ROOTFS_DIR}"/var/lib/apt/lists/*

log "slim-desktop rootfs usage:"
du -x -h -s "${ROOTFS_DIR}" | tee -a "${LOG_FILE}"
du -x -h -d1 "${ROOTFS_DIR}/usr" "${ROOTFS_DIR}/var" | sort -h | tail -12 | \
	tee -a "${LOG_FILE}"
