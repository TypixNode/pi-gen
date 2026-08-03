#!/bin/bash -e

case "${SLIM_DESKTOP_SESSION:-wayland}" in
	wayland) SESSION_PACKAGES="rpd-wayland-core" ;;
	x11)     SESSION_PACKAGES="rpd-x-core" ;;
	both)    SESSION_PACKAGES="rpd-wayland-core rpd-x-core" ;;
	*)
		echo "Invalid SLIM_DESKTOP_SESSION: ${SLIM_DESKTOP_SESSION}" >&2
		exit 1
		;;
esac

case "${SLIM_BROWSER:-chromium}" in
	chromium) BROWSER_PACKAGES="chromium chromium-sandbox rpi-chromium-mods" ;;
	firefox)  BROWSER_PACKAGES="firefox rpi-firefox-mods" ;;
	none)     BROWSER_PACKAGES="" ;;
	*)
		echo "Invalid SLIM_BROWSER: ${SLIM_BROWSER}" >&2
		exit 1
		;;
esac

# rpd-theme and rpd-preferences are empty metapackages that only carry
# Recommends, which is why the desktop can be assembled from their contents by
# hand: the look and the control panels are kept, the wallpaper collection and
# the CUPS/SANE printing and scanning stack are left out.
THEME_PACKAGES="${SLIM_THEME_PACKAGES-pixtrix-theme pixtrix-icons fonts-nunito-sans fonts-liberation2}"
PREFS_PACKAGES="${SLIM_PREFS_PACKAGES-rpcc pipanel rc-gui raindrop rasputin rp-prefapps merp}"
APP_PACKAGES="${SLIM_APP_PACKAGES-piwiz pi-package rp-bookshelf agnostics piclone \
mousepad eom evince xarchiver galculator lxtask \
gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-alsa gstreamer1.0-x}"

on_chroot <<- EOF
	apt-get -o Acquire::Retries=3 install --no-install-recommends -y \
		${SESSION_PACKAGES} ${THEME_PACKAGES} ${PREFS_PACKAGES} \
		${BROWSER_PACKAGES} ${APP_PACKAGES} ${SLIM_EXTRA_PACKAGES}
EOF

# The shipped default points at a wallpaper from rpd-wallpaper-trixie. When that
# collection is left out, fall back to the image rpd-common installs itself so
# the desktop does not come up with a missing background.
if [ ! -e "${ROOTFS_DIR}/usr/share/rpd-wallpaper/sunrise.jpg" ]; then
	sed -i 's|^wallpaper=.*|wallpaper=/usr/share/rpd-wallpaper/RPiSystem.png|' \
		"${ROOTFS_DIR}"/etc/xdg/pcmanfm/default/desktop-items-*.conf
fi
