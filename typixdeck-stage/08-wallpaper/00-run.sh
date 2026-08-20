#!/bin/bash -e

# Default wallpaper: Mt. Fuji with the Chureito Pagoda, 2048x1536 (4:3, same
# as the 1024x768 panel; cropped right-aligned so the pagoda survives the
# 3:2 -> 4:3 cut).
#
# Installed into the stock wallpaper directory so it shows up in the
# Appearance Settings chooser, then set as the system-wide default for the
# desktop (pcmanfm profile "default") and the lightdm greeter. Per-user
# configs are generated from these defaults on first login, so no files in
# /home are touched. The first-boot wizard background (wizard-items-*.conf)
# stays stock on purpose.

WALLPAPER=typixdeck-fuji.jpg

install -m 644 "files/${WALLPAPER}" \
	"${ROOTFS_DIR}/usr/share/rpd-wallpaper/${WALLPAPER}"

for conf in "${ROOTFS_DIR}"/etc/xdg/pcmanfm/default/desktop-items-*.conf; do
	sed -i \
		-e "s|^wallpaper=.*|wallpaper=/usr/share/rpd-wallpaper/${WALLPAPER}|" \
		-e "s|^wallpaper_mode=.*|wallpaper_mode=crop|" \
		"${conf}"
done

GREETER="${ROOTFS_DIR}/etc/lightdm/pi-greeter.conf"
if [ -f "${GREETER}" ]; then
	sed -i \
		-e "s|^wallpaper=.*|wallpaper=/usr/share/rpd-wallpaper/${WALLPAPER}|" \
		-e "s|^wallpaper_mode=.*|wallpaper_mode=crop|" \
		"${GREETER}"
fi
