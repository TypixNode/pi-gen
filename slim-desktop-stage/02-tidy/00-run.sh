#!/bin/bash -e

# shellcheck source=../slim-functions
source "${STAGE_DIR}/slim-functions"

on_chroot <<- \EOF
	apt-get autoremove --purge -y
	apt-get clean
EOF

# stage0 enables armhf multiarch on arm64 so that 32-bit binaries can be
# installed. Nothing in the image is armhf, and carrying the architecture costs
# ~20MB of package indices plus the entries for them in apt's binary cache. It
# comes back with `dpkg --add-architecture armhf && apt update`.
if [ "${SLIM_DROP_FOREIGN_ARCH:-1}" = "1" ]; then
	on_chroot <<- \EOF
		for ARCH in $(dpkg --print-foreign-architectures); do
			if [ -z "$(dpkg-query -f '${Architecture}\n' -W "*:$ARCH" 2>/dev/null)" ]; then
				dpkg --remove-architecture "$ARCH"
			fi
		done
	EOF
fi

if [ "${SLIM_STRIP_DOCS:-1}" = "1" ]; then
	strip_docs "${ROOTFS_DIR}" "${LOCALE_DEFAULT%%_*}"
fi

# apt's binary caches are ~65MB each and are stale by now anyway. export-image
# rebuilds pkgcache.bin during its `apt-get update`; files/99-slim-apt is what
# keeps srcpkgcache.bin from coming back. The indices themselves are left alone
# because export-image installs userconf-pi before it refreshes them.
rm -f "${ROOTFS_DIR}"/var/cache/apt/*.bin

log "slim-desktop rootfs usage:"
du -x -h -s "${ROOTFS_DIR}" | tee -a "${LOG_FILE}"
du -x -h -d1 "${ROOTFS_DIR}/usr" "${ROOTFS_DIR}/var" | sort -h | tail -12 | \
	tee -a "${LOG_FILE}"
