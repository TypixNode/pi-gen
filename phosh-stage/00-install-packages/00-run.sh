#!/bin/bash -e

# Runs before phosh-core is installed (01-packages of this substage): pin
# libwlroots-0.18 to the Debian build.
#
# The Raspberry Pi archive ships its own libwlroots-0.18 (0.18.2-3+rptN, with
# labwc/VNC/libliftoff patches). Debian's phoc is compiled against the
# unpatched Debian build and the two are not ABI compatible: phoc dies with
# "stack smashing detected" / SIGSEGV in phoc_output_compute_scale right
# after "Output 'DPI-1' added" and the session bounces back to the login
# screen. labwc on Trixie uses libwlroots-0.19, so phoc is the only user of
# 0.18 and forcing the Debian build has no side effects. Priority 1001 also
# wins over an installed higher version, so apt upgrades keep following Debian.

install -d -m 755 "${ROOTFS_DIR}/etc/apt/preferences.d"
cat > "${ROOTFS_DIR}/etc/apt/preferences.d/typixdeck-phosh-wlroots" << PIN
# phoc (Phosh compositor) is ABI-incompatible with the Raspberry Pi rebuild
# of libwlroots-0.18; keep the Debian build (see phosh-stage/README.md).
Package: libwlroots-0.18
Pin: release o=Debian
Pin-Priority: 1001
PIN
