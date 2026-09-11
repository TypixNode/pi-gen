#!/bin/bash -e

# Dev loop: flip the TypixDeck EEPROM boot order and reboot.
#
#   scripts/dev-boot.sh tf    # boot the TF card (candidate), SSD as fallback
#   scripts/dev-boot.sh ssd   # boot the USB SSD (resident), TF as fallback
#
# BOOT_ORDER nibbles are tried right to left: 1=SD card, 2=network,
# 4=USB-MSD, 6=NVMe, f=retry. The device default is 0xf2461 (SD first,
# NVMe, then USB), so "tf" restores the default and "ssd" only moves the
# USB nibble to the front.

PI="${PI:-pi@192.168.50.98}"

case "$1" in
	tf)  ORDER=0xf2461 ;;
	ssd) ORDER=0xf2614 ;;
	*)
		echo "usage: $0 tf|ssd   (applies the boot order and reboots ${PI})" >&2
		exit 1
		;;
esac

ssh "${PI}" "sudo rpi-eeprom-config --out /tmp/boot.conf \
	&& sudo sed -i 's/^BOOT_ORDER=.*/BOOT_ORDER=${ORDER}/' /tmp/boot.conf \
	&& sudo rpi-eeprom-config --apply /tmp/boot.conf \
	&& grep ^BOOT_ORDER /tmp/boot.conf \
	&& (sudo reboot || true)"

echo "Rebooting into: $1 (BOOT_ORDER=${ORDER})"
