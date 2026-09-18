#!/bin/bash -e

# Phosh session setup: boot to graphical.target and let phosh.service (shipped
# by the phosh package: tty7, User=1000 = the first user, PAMName=login) start
# the shell directly - no display manager on this Lite-based image.
#
# greetd has to go first, or none of that happens: phosh-core depends on phrog,
# which pulls in greetd, whose postinst makes it /etc/systemd/system/
# display-manager.service. Both units are then enabled, greetd takes tty7 and
# the deck boots to the phrog lock screen instead of the shell - on a 4:3 panel
# whose keypad does not fit, with the keyboard in the deck, which is as good as
# locked out. The image shipped that way until 2026-09-18.
on_chroot << CHROOT
systemctl disable greetd || true
rm -f /etc/systemd/system/display-manager.service
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
