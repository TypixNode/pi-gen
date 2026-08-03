#!/bin/bash -e

# shellcheck source=../slim-functions
source "${STAGE_DIR}/slim-functions"

# Documentation, manual pages and translation catalogues are dropped at unpack
# time so that the desktop packages installed by the later sub-stages never
# write them in the first place.
if [ "${SLIM_STRIP_DOCS:-1}" = "1" ]; then
	LOCALE_LANG="${LOCALE_DEFAULT%%_*}"
	install -m 644 files/99-slim-nodoc "${ROOTFS_DIR}/etc/dpkg/dpkg.cfg.d/99-slim-nodoc"
	printf 'path-include /usr/share/locale/%s*\n' "${LOCALE_LANG}" \
		>> "${ROOTFS_DIR}/etc/dpkg/dpkg.cfg.d/99-slim-nodoc"

	strip_docs "${ROOTFS_DIR}" "${LOCALE_LANG}"
fi

# apt keeps its package indices uncompressed and builds two binary caches from
# them; on a Debian + Raspberry Pi archive set that is several hundred MB of
# regenerable data. These settings survive the `apt-get update` that
# export-image runs, so they have to be configuration rather than a plain rm.
if [ "${SLIM_APT_TRIM:-1}" = "1" ]; then
	install -m 644 files/99-slim-apt "${ROOTFS_DIR}/etc/apt/apt.conf.d/99-slim-apt"
fi
