#!/bin/bash -e
# Install the "eggfly" custom boot splash:
#   * a Plymouth theme carrying the baked-in default image + rainbow spinner,
#   * an initramfs hook that lets a file on the FAT boot partition override it,
#   * config.txt / cmdline.txt tweaks so our splash cleanly replaces the
#     firmware rainbow and the kernel log spam.

THEME_DIR="${ROOTFS_DIR}/usr/share/plymouth/themes/eggfly"
INITRD_SCRIPTS="${ROOTFS_DIR}/etc/initramfs-tools/scripts/init-top"
INITRD_MODULES="${ROOTFS_DIR}/etc/initramfs-tools/modules"
CONFIG_TXT="${ROOTFS_DIR}/boot/firmware/config.txt"
CMDLINE_TXT="${ROOTFS_DIR}/boot/firmware/cmdline.txt"

# --- Plymouth theme ---------------------------------------------------------
install -d "${THEME_DIR}"
install -m 644 files/plymouth/eggfly.plymouth "${THEME_DIR}/"
install -m 644 files/plymouth/eggfly.script "${THEME_DIR}/"
install -m 644 files/plymouth/splash.png "${THEME_DIR}/"
for frame in files/plymouth/eggfly-anim-*.png; do
	install -m 644 "${frame}" "${THEME_DIR}/"
done

# --- initramfs override hook (boot-partition image) -------------------------
install -d "${INITRD_SCRIPTS}"
install -m 755 files/initramfs/scripts/init-top/eggfly-splash "${INITRD_SCRIPTS}/eggfly-splash"

# FAT + charset modules so the override script can read the boot partition.
if [ -f "${INITRD_MODULES}" ] && ! grep -q '^vfat$' "${INITRD_MODULES}"; then
	cat files/initramfs/modules >> "${INITRD_MODULES}"
fi

# --- make eggfly the default Plymouth theme ---------------------------------
# Sets the update-alternatives link that both the running system and the
# initramfs hook read. The initramfs itself is (re)generated at the end of the
# build by export-image/05-finalise, so no rebuild is needed here.
on_chroot <<- EOF
	plymouth-set-default-theme eggfly
EOF

# --- hide the firmware rainbow (Plymouth replaces it) -----------------------
if [ -f "${CONFIG_TXT}" ] && ! grep -q '^disable_splash=1' "${CONFIG_TXT}"; then
	printf '\n# eggfly custom boot splash: hide the firmware rainbow (Plymouth replaces it)\ndisable_splash=1\n' >> "${CONFIG_TXT}"
fi

# --- quiet boot + enable Plymouth splash ------------------------------------
# Appended to the single-line cmdline.txt (before its trailing newline).
if [ -f "${CMDLINE_TXT}" ] && ! grep -q 'plymouth.ignore-serial-consoles' "${CMDLINE_TXT}"; then
	sed -i '1 s/$/ quiet splash plymouth.ignore-serial-consoles logo.nologo loglevel=3 vt.global_cursor_default=0/' "${CMDLINE_TXT}"
fi
