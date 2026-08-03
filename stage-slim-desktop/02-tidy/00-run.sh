#!/bin/bash -e

on_chroot <<- \EOF
	apt-get autoremove --purge -y
	apt-get clean
EOF

if [ "${SLIM_STRIP_DOCS:-1}" = "1" ]; then
	# Packages that were already unpacked before the dpkg path-exclude rules
	# landed, plus anything that recreated these paths from a maintainer script.
	find "${ROOTFS_DIR}/usr/share/doc" -mindepth 1 -not -name copyright -delete
	find "${ROOTFS_DIR}/usr/share/locale" -mindepth 1 -maxdepth 1 -type d \
		-not -name "${LOCALE_DEFAULT%%_*}*" -exec rm -rf {} +
fi

rm -rf "${ROOTFS_DIR}"/var/cache/apt/*.bin
rm -rf "${ROOTFS_DIR}"/var/lib/apt/lists/*

log "slim-desktop rootfs usage:"
du -x -h -s "${ROOTFS_DIR}" | tee -a "${LOG_FILE}"
du -x -h -d1 "${ROOTFS_DIR}/usr" "${ROOTFS_DIR}/var" | sort -h | tail -12 | \
	tee -a "${LOG_FILE}"
