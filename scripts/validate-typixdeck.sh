#!/bin/bash

# TypixDeck image validation. Run it on the device, or from the Mac:
#
#   ssh pi@<addr> 'bash -s' < scripts/validate-typixdeck.sh
#
# PASS/FAIL gate the exit code; WARN lines depend on optional wiring (fan FG).
#
# Exit code 0 = all checks passed. speaker-test still needs your ears.

FAIL=0

check() {
	local desc="$1"; shift
	local out
	if out="$("$@" 2>&1)"; then
		printf 'PASS  %s\n' "${desc}"
	else
		printf 'FAIL  %s\n' "${desc}"
		printf '%s\n' "${out}" | head -n3 | sed 's/^/      /'
		FAIL=1
	fi
}

# Like check, but a miss only warns (things that depend on optional wiring).
warn() {
	local desc="$1"; shift
	if "$@" >/dev/null 2>&1; then
		printf 'PASS  %s\n' "${desc}"
	else
		printf 'WARN  %s\n' "${desc}"
	fi
}

echo "== TypixDeck validate: $(hostname), $(uname -r), $(date '+%F %T') =="

check "no failed systemd units" sh -c '[ -z "$(systemctl --failed --quiet --no-legend)" ]'
check "labwc compositor up"     pgrep -x labwc
check "wf-panel-pi up"          pgrep -f wf-panel-pi
check "ALSA playback card"      sh -c 'aplay -l 2>/dev/null | grep -q "^card"'
check "ALSA capture card"       sh -c 'arecord -l 2>/dev/null | grep -q "^card"'
check "USB audio (UAC) card"    sh -c 'aplay -l 2>/dev/null | grep -qi "usb\|uac"'
check "backlight sysfs"         sh -c 'ls /sys/class/backlight/ | grep -q .'
check "GT911 touch input"       sh -c 'grep -liq gt911 /sys/class/input/input*/name'
check "DPI panel connected"     sh -c 'grep -q ^connected /sys/class/drm/card*-DPI-1/status'
check "cloud-init finished"     sh -c 'cloud-init status 2>/dev/null | grep -qE "done|disabled"'

# --- ESP32-S3 co-processor + telemetry (typixdeck-stage 04 / 09) ---
check "ESP32-S3 app enumerated (303a:80c3)" sh -c 'lsusb | grep -q 303a:80c3'
check "udev symlink /dev/typixdeck-esp"     test -e /dev/typixdeck-esp
check "typixdeck-pi-info.service active"    systemctl is-active --quiet typixdeck-pi-info
check "pi-info collects model/cpu/freq"     bash -c '
	source <(sed -n "/^model_short/,/^MODEL=/p" /usr/local/bin/typixdeck-pi-info)
	[ -n "$(model_short)" ] && [ -n "$(cpu_temp)" ] && [ -n "$(cpu_freq_mhz)" ]'
check "ESP firmware bundled in /opt"        sh -c 'ls /opt/typixdeck/firmware/esp32s3/typixdeck_esp32s3_full_*.bin >/dev/null'
check "esptool + dfu-util installed"        sh -c 'command -v esptool >/dev/null && command -v dfu-util >/dev/null'

# --- fan (typixdeck-stage 02): driver must load; tacho needs the FG wire ---
check "config.txt has i2c-fan emc2301"      grep -q '^dtoverlay=i2c-fan,emc2301' /boot/firmware/config.txt
check "EMC2301 hwmon present (emc2305)"     sh -c 'grep -qx emc2305 /sys/class/hwmon/hwmon*/name'
warn  "fan tacho > 0 rpm (FG wire on CN5.4)" sh -c 'd=$(grep -lx emc2305 /sys/class/hwmon/hwmon*/name) && [ "$(cat "${d%/name}/fan1_input")" -gt 0 ]'

# --- desktop scale + toolbox (typixdeck-stage 06 / 10) ---
check "kanshi profile has DPI-1 scale"      sh -c 'grep -q "output DPI-1 .*scale" "$HOME/.config/kanshi/config"'
check "greeter kanshi profile present"      test -s /etc/xdg/labwc-greeter/config.kanshi
check "typixdeck-toolbox installed"         test -x /usr/local/bin/typixdeck-toolbox
check "keebdeck F13 hwdb quirk installed"   test -f /etc/udev/hwdb.d/90-typixdeck-keebdeck.hwdb
check "stc3117 gauge module (dkms)"        sh -c 'modinfo stc3117_fuel_gauge > /dev/null 2>&1'
check "stc3117 battery power_supply node"  test -d /sys/class/power_supply/stc3117-battery

echo
echo "== pi-info telemetry line =="
bash -c 'source <(sed -n "/^model_short/,/^MODEL=/p" /usr/local/bin/typixdeck-pi-info) 2>/dev/null
	echo "model=$(model_short) rev=$(model_rev) cpu=$(cpu_temp) freq=$(cpu_freq_mhz) fan=$(fan_rpm) fanpwm=$(fan_pwm_pct) fansrc=$(fan_src) thr=$(throttled)"' 2>/dev/null
echo "kanshi: $(grep -o "scale [0-9.]*" "$HOME/.config/kanshi/config" 2>/dev/null || echo none)"

echo
echo "== sound cards =="
aplay -l 2>/dev/null | grep '^card' || echo "(none)"

echo
echo "== dmesg: dwc2 / usb audio / errors (last 15) =="
{ sudo -n dmesg 2>/dev/null || dmesg 2>/dev/null; } \
	| grep -iE 'dwc2|usb.*audio|snd|error|fail' | tail -n15

echo
echo "== speaker-test: listen for noise on both channels =="
if timeout 8 speaker-test -c2 -t wav -l1 > /dev/null 2>&1; then
	echo "speaker-test ran - confirm by ear"
else
	echo "speaker-test FAILED to run"
	FAIL=1
fi

exit "${FAIL}"
