#!/bin/bash -e

# udev hwdb quirk for the KeebDeck 6R11C keyboard: swallow the F13 that the
# square (display-toggle) key sends to the host. xkb turns F13 into
# XF86Tools and GNOME/Phosh/Plasma open Settings on it; labwc ignores it,
# which is why stock Raspberry Pi OS never showed the problem.

install -m 644 files/90-typixdeck-keebdeck.hwdb \
	"${ROOTFS_DIR}/etc/udev/hwdb.d/90-typixdeck-keebdeck.hwdb"

on_chroot << EOF2
systemd-hwdb update
EOF2
