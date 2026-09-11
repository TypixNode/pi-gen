#!/bin/bash -e

# TypixDeck toolbox: GTK app (tabbed: Wi-Fi antenna + display scale + APT sources).
# python3-gi and GTK are already part of the desktop stages.
#
# The image ships NO antenna configuration at all (hardware default ant1 =
# module PCB antenna); switching to the external antenna is a user choice
# made in this app.

install -m 755 files/typixdeck-toolbox "${ROOTFS_DIR}/usr/local/bin/typixdeck-toolbox"
install -m 644 files/typixdeck-toolbox.desktop "${ROOTFS_DIR}/usr/share/applications/typixdeck-toolbox.desktop"

# Desktop shortcut for the first user. A Type=Link entry pointing at the
# installed launcher - the same pattern the stock desktop uses for its
# Chromium icon. libfm treats Type=Application files in the home dir as
# untrusted executables and pops an Execute/Open prompt (with or without
# the exec bit, verified on-device); Type=Link entries launch directly.
install -d "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/Desktop"
cat > "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/Desktop/typixdeck-toolbox.desktop" << 'EOF'
[Desktop Entry]
Type=Link
Name=TypixDeck Toolbox
Name[zh_CN]=TypixDeck 工具箱
Icon=preferences-system
URL=/usr/share/applications/typixdeck-toolbox.desktop
EOF
chmod 644 "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/Desktop/typixdeck-toolbox.desktop"
on_chroot << EOF
chown -R ${FIRST_USER_NAME}:${FIRST_USER_NAME} "/home/${FIRST_USER_NAME}/Desktop"
EOF
