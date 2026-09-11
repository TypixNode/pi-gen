#!/bin/bash -e

# Pi → ESP32-S3 telemetry: a system (root) unit, started by udev the moment the
# ESP's CDC port (303a:80c3) enumerates, writes one EGGFLY_PI_INFO line every
# 2 s with model / CPU temp / NVMe temp / fan RPM / throttle flags. BindsTo the
# device unit, so it stops automatically while flash_esp32.sh reflashes the chip.
# No user session involved: it works on the lite image and before login.

install -m 755 files/typixdeck-pi-info "${ROOTFS_DIR}/usr/local/bin/typixdeck-pi-info"
install -m 644 files/typixdeck-pi-info.service "${ROOTFS_DIR}/etc/systemd/system/typixdeck-pi-info.service"
install -m 644 files/99-typixdeck-esp.rules "${ROOTFS_DIR}/etc/udev/rules.d/99-typixdeck-esp.rules"
# Not enabled in any target on purpose: udev's SYSTEMD_WANTS is the only trigger.
