#!/bin/bash -e

# Default desktop scale for the built-in 3.2" 1024x768 DPI panel: x1.25.
#
# Same file and format the Control Centre (raindrop plugin) writes, so the
# user can still change it there (1.0/1.5/2.0/3.0) or in the TypixDeck
# Toolbox (1.0/1.25/1.5). kanshi is started from /etc/xdg/labwc/autostart
# and applies the profile at login; the greeter copy scales the login
# screen the same way. Harmless on the lite image (no compositor, the files
# simply sit unused).

install -d -m 755 "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/.config/kanshi"
install -m 644 files/kanshi.config "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/.config/kanshi/config"
# raindrop keeps a pristine copy as config.init and a backup as config.bak
install -m 644 files/kanshi.config "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/.config/kanshi/config.init"
on_chroot << CHROOT
chown -R ${FIRST_USER_NAME}:${FIRST_USER_NAME} "/home/${FIRST_USER_NAME}/.config"
CHROOT

install -d -m 755 "${ROOTFS_DIR}/etc/xdg/labwc-greeter"
install -m 644 files/kanshi.config "${ROOTFS_DIR}/etc/xdg/labwc-greeter/config.kanshi"
