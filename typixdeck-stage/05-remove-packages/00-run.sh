#!/bin/bash -e

# Remove packages that make no sense on the TypixDeck:
#
#   * rpi-connect / rpi-connect-lite - Raspberry Pi Connect remote access
#     (rpi-connect-lite is installed by stage2/01-sys-tweaks; purging it here
#     keeps the shared stages identical to upstream for the stock images).
#   * squeekboard / wfplug-squeek - the on-screen keyboard and its wf-panel
#     plugin, pulled in by the stage4 desktop; the TypixDeck has a physical
#     KeebDeck keyboard.
#
# Only purge what is actually installed so this stage also works on stage
# combinations that never installed some of these (e.g. the Plasma Mobile
# variant, which skips stage4).

on_chroot << EOF
PURGE=""
for pkg in rpi-connect rpi-connect-lite squeekboard wfplug-squeek; do
	if dpkg -s "\$pkg" > /dev/null 2>&1; then
		PURGE="\$PURGE \$pkg"
	fi
done
if [ -n "\$PURGE" ]; then
	apt-get purge -y \$PURGE
fi
apt-get autoremove --purge -y
EOF
