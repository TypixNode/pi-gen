#!/bin/bash -e

# Remove packages that make no sense on the TypixDeck (it has a physical
# KeebDeck keyboard and no use for Raspberry Pi Connect):
#
#   * rpi-connect / rpi-connect-lite - remote access agent
#   * squeekboard - the on-screen keyboard itself
#
# NEVER purge wfplug-squeek here: rpd-wayland-core hard-depends on it, and
# rpd-wayland-core is NOT a pure metapackage - it ships the wayland session
# entry (/usr/share/wayland-sessions/rpd-labwc.desktop), the labwc and
# labwc-greeter configs and the session launcher scripts (labwc-pi,
# lwrespawn, ...). Purging it black-screens the desktop even when every
# dependency is pinned and stays installed (verified on-device, twice).
#
# NEVER run apt-get autoremove here either: after the metapackage is gone it
# sweeps labwc/wf-panel-pi/xwayland and friends. The handful of orphans that
# purging squeekboard leaves behind (feedbackd, gnome theme data, ~5 MB) is
# the price of a desktop that boots.

on_chroot << 'EOF'
PURGE=""
for pkg in rpi-connect rpi-connect-lite squeekboard; do
	if dpkg -s "$pkg" > /dev/null 2>&1; then
		PURGE="$PURGE $pkg"
	fi
done
if [ -n "$PURGE" ]; then
	apt-get purge -y $PURGE
fi
EOF
