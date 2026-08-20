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
#
# CAUTION: rpd-wayland-core hard-depends on wfplug-squeek, so purging the
# on-screen keyboard drags the desktop metapackage out with it, and everything
# else the metapackage anchored (labwc, wf-panel-pi, xwayland, ...) becomes an
# orphan that the autoremove below would sweep away. That exact cascade once
# shipped Desktop/slim images that booted to a blinking cursor. So before
# purging, pin every other installed dependency of the rpd-*-core
# metapackages as manually installed, and fail the build if the compositor is
# gone afterwards anyway.

on_chroot << 'EOF'
REMOVE="rpi-connect rpi-connect-lite squeekboard wfplug-squeek"

for meta in rpd-wayland-core rpd-x-core; do
	dpkg -s "$meta" > /dev/null 2>&1 || continue
	deps="$(apt-cache depends --installed --important "$meta" \
		| sed -n 's/^ *|\{0,1\}\(Pre\)\{0,1\}Depends: \([^<][^ ]*\)$/\2/p')"
	keep=""
	for dep in $deps; do
		case " $REMOVE " in
			*" $dep "*) continue ;;
		esac
		if dpkg -s "$dep" > /dev/null 2>&1; then
			keep="$keep $dep"
		fi
	done
	if [ -n "$keep" ]; then
		apt-mark manual $keep
	fi
done

HAD_COMPOSITOR=0
if dpkg -s labwc > /dev/null 2>&1; then
	HAD_COMPOSITOR=1
fi

PURGE=""
for pkg in $REMOVE; do
	if dpkg -s "$pkg" > /dev/null 2>&1; then
		PURGE="$PURGE $pkg"
	fi
done
if [ -n "$PURGE" ]; then
	apt-get purge -y $PURGE
fi
apt-get autoremove --purge -y

if [ "$HAD_COMPOSITOR" = 1 ] && ! dpkg -s labwc > /dev/null 2>&1; then
	echo "ERROR: purging the on-screen keyboard uninstalled labwc;" >&2
	echo "the desktop would boot to a blinking cursor. Aborting." >&2
	exit 1
fi
EOF
