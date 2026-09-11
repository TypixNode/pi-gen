#!/bin/bash -e

# Phosh session setup: boot to graphical.target and let phosh.service (shipped
# by the phosh package: tty7, User=1000 = the first user, PAMName=login) start
# the shell directly - no display manager on this Lite-based image.
on_chroot << CHROOT
systemctl set-default graphical.target
systemctl enable phosh
CHROOT

# phoc output config (panel scale) - phosh-session reads /etc/phosh/phoc.ini
# in preference to the package default.
install -d -m 755 "${ROOTFS_DIR}/etc/phosh"
install -m 644 files/phoc.ini "${ROOTFS_DIR}/etc/phosh/phoc.ini"

# Start the shell unlocked (drop-in for the systemd user unit phosh runs as).
install -d -m 755 "${ROOTFS_DIR}/etc/systemd/user/mobi.phosh.Shell.service.d"
install -m 644 files/typixdeck-unlocked.conf \
	"${ROOTFS_DIR}/etc/systemd/user/mobi.phosh.Shell.service.d/typixdeck-unlocked.conf"

# System-wide dconf defaults (lock screen off, no blanking, battery %).
install -d -m 755 "${ROOTFS_DIR}/etc/dconf/profile" "${ROOTFS_DIR}/etc/dconf/db/local.d"
if [ ! -f "${ROOTFS_DIR}/etc/dconf/profile/user" ]; then
	printf 'user-db:user\nsystem-db:local\n' > "${ROOTFS_DIR}/etc/dconf/profile/user"
fi
install -m 644 files/10-typixdeck-phosh "${ROOTFS_DIR}/etc/dconf/db/local.d/10-typixdeck-phosh"
on_chroot << CHROOT
dconf update
CHROOT
