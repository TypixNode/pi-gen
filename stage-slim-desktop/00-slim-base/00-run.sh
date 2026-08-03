#!/bin/bash -e

# Documentation, manual pages and translation catalogues are dropped at unpack
# time so that the desktop packages installed by the later sub-stages never
# write them in the first place.
if [ "${SLIM_STRIP_DOCS:-1}" = "1" ]; then
	LOCALE_LANG="${LOCALE_DEFAULT%%_*}"
	install -m 644 files/99-slim-nodoc "${ROOTFS_DIR}/etc/dpkg/dpkg.cfg.d/99-slim-nodoc"
	printf 'path-include /usr/share/locale/%s*\n' "${LOCALE_LANG}" \
		>> "${ROOTFS_DIR}/etc/dpkg/dpkg.cfg.d/99-slim-nodoc"

	find "${ROOTFS_DIR}/usr/share/doc" -mindepth 1 -not -name copyright -delete
	find "${ROOTFS_DIR}/usr/share/man" "${ROOTFS_DIR}/usr/share/info" \
		"${ROOTFS_DIR}/usr/share/groff" "${ROOTFS_DIR}/usr/share/lintian" \
		-mindepth 1 -delete 2>/dev/null || true
	find "${ROOTFS_DIR}/usr/share/locale" -mindepth 1 -maxdepth 1 -type d \
		-not -name "${LOCALE_LANG}*" -exec rm -rf {} +
fi

# apt keeps its package indices uncompressed and builds two binary caches from
# them; on a Debian + Raspberry Pi archive set that is several hundred MB of
# regenerable data. These settings survive the `apt-get update` that
# export-image runs, so they have to be configuration rather than a plain rm.
if [ "${SLIM_APT_TRIM:-1}" = "1" ]; then
	install -m 644 files/99-slim-apt "${ROOTFS_DIR}/etc/apt/apt.conf.d/99-slim-apt"
fi
