#!/bin/bash -e

# Ship the TypixDeck MCU firmware images and flashing scripts inside the OS
# image, so a device can reflash its own peripherals in the field:
#
#   /opt/typixdeck/firmware/esp32s3/  - ESP32-S3 co-processor (LCD init, touch
#                                       bridge, GUI, UAC audio, CDC console),
#                                       flashed with esptool over /dev/ttyACM*
#   /opt/typixdeck/firmware/keebdeck/ - KeebDeck 6R11C keyboard (STM32F042),
#                                       flashed with dfu-util (DFU 0483:df11)
#
# esptool and dfu-util are installed by 00-install-packages.

FIRMWARE_DIR="${ROOTFS_DIR}/opt/typixdeck/firmware"

install -d "${FIRMWARE_DIR}/esp32s3" "${FIRMWARE_DIR}/keebdeck"

install -m 755 files/esp32s3/flash_esp32.sh "${FIRMWARE_DIR}/esp32s3/"
install -m 644 files/esp32s3/*.bin "${FIRMWARE_DIR}/esp32s3/"

install -m 755 files/keebdeck/flash_kbd.sh "${FIRMWARE_DIR}/keebdeck/"
install -m 644 files/keebdeck/*.bin "${FIRMWARE_DIR}/keebdeck/"
