#!/bin/bash -e

# Backlight brightness tray applet (StatusNotifier/AppIndicator icon in the
# wf-panel-pi tray, scroll wheel = one step, menu = presets). It talks to
# /sys/class/backlight directly, so it needs no extra privileges beyond the
# stock raspberrypi-sys-mods udev rules (video group).
#
# This sub-stage is labwc-only: the Plasma Mobile variant reuses this stage
# without stage4, so when the rootfs has no labwc there is no tray to sit in
# and we skip both the applet and its GTK/Ayatana dependency.

if [ ! -x "${ROOTFS_DIR}/usr/bin/labwc" ]; then
	echo "labwc not present in rootfs; skipping brightness tray install"
	exit 0
fi

on_chroot << EOF
apt-get -o Acquire::Retries=3 install -y gir1.2-ayatanaappindicator3-0.1
EOF

install -m 755 files/brightness-tray.py "${ROOTFS_DIR}/usr/local/bin/brightness-tray"

# System-wide labwc autostart (runs before the per-user
# ~/.config/labwc/autostart). "sleep 3" gives wf-panel-pi time to bring the
# tray up, same approach as CyberFold's power tray (scripts/README.md).
AUTOSTART="${ROOTFS_DIR}/etc/xdg/labwc/autostart"
if ! grep -qs 'brightness-tray' "${AUTOSTART}"; then
	install -d "${ROOTFS_DIR}/etc/xdg/labwc"
	cat >> "${AUTOSTART}" << EOF
# TypixDeck: backlight brightness tray (wait for the panel tray to be ready)
sleep 3 && /usr/local/bin/brightness-tray &
EOF
fi
