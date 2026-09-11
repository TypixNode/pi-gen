#!/bin/bash -e

# First-boot provisioning of the MCUs from the bundled firmware
# (see files/typixdeck-provision for the flow). Needs esptool >= 5 for the
# stub flasher + `--after watchdog-reset`; the apt esptool (4.7, no stub
# files) stays as fallback. The venv is created inside the chroot so the
# interpreter path matches the target.

install -m 755 files/typixdeck-provision "${ROOTFS_DIR}/usr/local/bin/typixdeck-provision"
install -m 644 files/typixdeck-provision.service "${ROOTFS_DIR}/etc/systemd/system/typixdeck-provision.service"
install -d "${ROOTFS_DIR}/var/lib/typixdeck" "${ROOTFS_DIR}/etc/typixdeck"

on_chroot << CHROOT
python3 -m venv /opt/typixdeck/esptool-venv
/opt/typixdeck/esptool-venv/bin/pip install --no-cache-dir 'esptool>=5,<6'
/opt/typixdeck/esptool-venv/bin/esptool version
systemctl enable typixdeck-provision.service
CHROOT
