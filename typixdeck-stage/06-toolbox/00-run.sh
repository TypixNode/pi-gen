#!/bin/bash -e

# TypixDeck toolbox: GTK app for hardware options that live in
# config.txt (currently the Wi-Fi antenna: internal PCB vs external U.FL).
# python3-gi and GTK are already part of the desktop stages.
#
# The image ships NO antenna configuration at all (hardware default ant1 =
# module PCB antenna); switching to the external antenna is a user choice
# made in this app.

install -m 755 files/typixdeck-toolbox "${ROOTFS_DIR}/usr/local/bin/typixdeck-toolbox"
install -m 644 files/typixdeck-toolbox.desktop "${ROOTFS_DIR}/usr/share/applications/typixdeck-toolbox.desktop"

# Desktop shortcut for the first user. NO exec bit: pcmanfm/libfm launches
# .desktop entries directly, and an executable bit instead triggers the
# "seems to be an executable script" Execute/Open prompt.
install -d "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/Desktop"
install -m 644 files/typixdeck-toolbox.desktop \
	"${ROOTFS_DIR}/home/${FIRST_USER_NAME}/Desktop/typixdeck-toolbox.desktop"
on_chroot << EOF
chown -R ${FIRST_USER_NAME}:${FIRST_USER_NAME} "/home/${FIRST_USER_NAME}/Desktop"
EOF
