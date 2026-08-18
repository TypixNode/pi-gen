#!/bin/bash
# KeebDeck 6R11C（STM32F042）键盘批量 DFU 刷机
# 用法：./flash_kbd.sh          刷 default（日常固件）
#       ./flash_kbd.sh diag     刷触点检测版（产线测按键用，测完务必刷回 default）
# 进 DFU：空片插 USB 自动进（F042 empty-check）；已刷 QMK 的按 Fn+菱形 或 Sym+菱形
set -u
cd "$(dirname "$0")"
BIN=keebdeck_6r11c_default_20260818.bin
[ "${1:-}" = "diag" ] && BIN=keebdeck_6r11c_diag_20260818.bin
[ -f "$BIN" ] || { echo "找不到 $BIN"; exit 1; }

echo "== KeebDeck 批量 DFU 刷机（$BIN）=="
while true; do
    if lsusb | grep -q "0483:df11"; then
        echo "== 发现 DFU 设备，开始刷写 =="
        if dfu-util -a 0 -d 0483:df11 -s 0x08000000:leave -D "$BIN"; then
            sleep 2
            if lsusb | grep -qi "c182:6b11"; then
                echo "== ✔ OK：已枚举 c182:6b11 KeebDeck 键盘，拔板换下一块 =="
            else
                echo "== 刷写完成（:leave 已自动运行），确认按键有输出后换板 =="
            fi
        else
            echo "!! dfu-util 失败，重插重试 !!"
        fi
        while lsusb | grep -q "0483:df11"; do sleep 1; done
    fi
    sleep 1
done
