# shellcheck shell=bash
# MCU firmware and flashing tools bundled by typixdeck-stage/04-firmware-tools,
# which the first-boot provisioning flashes onto blank boards.

FW="$ROOT/opt/typixdeck/firmware"
check "ESP32-S3 full image is bundled" \
	sh -c 'ls "$1"/esp32s3/typixdeck_esp32s3_full_*.bin >/dev/null 2>&1' _ "$FW"
check "flash_esp32.sh is executable" test -x "$FW/esp32s3/flash_esp32.sh"
check "KeebDeck default firmware is bundled" \
	sh -c 'ls "$1"/keebdeck/keebdeck_6r11c_default_*.bin >/dev/null 2>&1' _ "$FW"
check "flash_kbd.sh is executable" test -x "$FW/keebdeck/flash_kbd.sh"
