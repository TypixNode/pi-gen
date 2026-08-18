#!/bin/bash -e

# Boot into the graphical session by default and make sure SDDM is the
# enabled display manager (its postinst normally does this, but be explicit).
on_chroot << EOF
systemctl set-default graphical.target
systemctl enable sddm
EOF

# Autologin the first user straight into the Plasma Mobile Wayland session.
# "plasma-mobile" refers to /usr/share/wayland-sessions/plasma-mobile.desktop,
# shipped by the plasma-mobile package.
install -d -m 755 "${ROOTFS_DIR}/etc/sddm.conf.d"
cat > "${ROOTFS_DIR}/etc/sddm.conf.d/autologin.conf" << EOF
[Autologin]
User=${FIRST_USER_NAME}
Session=plasma-mobile
Relogin=false
EOF

# Conservative Qt Quick rendering default for Plasma sessions only
# (see the comment inside the file and this stage's README).
install -d -m 755 "${ROOTFS_DIR}/etc/xdg/plasma-workspace/env"
install -m 644 files/00-qt-quick-backend.sh \
	"${ROOTFS_DIR}/etc/xdg/plasma-workspace/env/00-qt-quick-backend.sh"
