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

# The apt indices and caches are deliberately left in place: export-image
# installs userconf-pi before it refreshes them, and it rebuilds both anyway.
# What keeps them small is files/99-slim-apt, not deleting them here.

log "slim-desktop rootfs usage:"
du -x -h -s "${ROOTFS_DIR}" | tee -a "${LOG_FILE}"
du -x -h -d1 "${ROOTFS_DIR}/usr" "${ROOTFS_DIR}/var" | sort -h | tail -12 | \
	tee -a "${LOG_FILE}"
