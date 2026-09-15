# shellcheck shell=bash
# Device tree overlays compiled by typixdeck-stage/01-overlays, and the
# config.txt lines from 02-config-txt that enable them.

for ovl in vc4-kms-dpi-3inch2-1024x768 gt911-touch-3inch2-1024x768 \
	pwm-backlight-3inch2-rp1 pwm-backlight-3inch2-bcm stc3117-gauge; do
	check "overlay $ovl.dtbo is on the boot partition" test -s "$BOOT/overlays/$ovl.dtbo"
done

check "config.txt enables the DPI panel" \
	config_txt_has all "dtoverlay=vc4-kms-dpi-3inch2-1024x768"
check "config.txt enables the GT911 touch" \
	config_txt_has all "dtoverlay=gt911-touch-3inch2-1024x768"
check "config.txt enables the RP1 PWM backlight under [cm5]" \
	config_txt_has cm5 "dtoverlay=pwm-backlight-3inch2-rp1"
