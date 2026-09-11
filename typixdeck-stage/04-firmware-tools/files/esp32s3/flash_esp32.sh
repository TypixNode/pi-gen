#!/bin/bash
# TypixDeck ESP32-S3 批量刷机（完整镜像 @0x0：bootloader+分区表+app+字体）
# ⚠️ 会清空 NVS（语言设置回默认英文）。只升级 app 保留设置请手动：
#    esptool --no-stub --chip esp32s3 -p /dev/ttyACM0 write_flash 0x10000 app.bin
# 用法：./flash_esp32.sh   然后逐块插板，刷完拔板换下一块；Ctrl-C 退出
set -u
cd "$(dirname "$0")"
BIN=typixdeck_esp32s3_full_20260910.bin
[ -f "$BIN" ] || { echo "找不到 $BIN"; exit 1; }

flash_one() {
    local port=$1
    # 板上 app 在跑（303a:80c3）→ 先发魔法串重启进 ROM 下载模式
    if lsusb | grep -q "303a:80c3"; then
        echo ">> 检测到运行中固件，发魔法串进下载模式"
        echo EGGFLY_REBOOT_TO_BOOT_MODE > "$port" 2>/dev/null
        sleep 3
        port=$(ls /dev/ttyACM* 2>/dev/null | head -1)
        [ -z "$port" ] && { echo "!! 魔法串后设备消失"; return 1; }
    fi
    # 先试 stub（快），失败回退 --no-stub（apt 版 esptool 缺 stub JSON 时）
    esptool --chip esp32s3 -p "$port" -b 921600 write_flash 0x0 "$BIN" ||
    esptool --no-stub --chip esp32s3 -p "$port" -b 460800 write_flash 0x0 "$BIN"
}

echo "== TypixDeck ESP32-S3 批量刷机（$BIN）=="
echo "   空片直接插 USB 即可；已刷过的板自动发魔法串；坏固件按住 BOOT(SW2) 点 RESET(SW1)"
while true; do
    PORT=$(ls /dev/ttyACM* 2>/dev/null | head -1)
    if [ -n "${PORT}" ]; then
        echo "== 发现 $PORT，开始刷写 =="
        if flash_one "$PORT"; then
            sleep 3
            # 刷完验证以 PID 为准：80c3=app 正常跑；1001/0009=还在下载模式
            if lsusb | grep -q "303a:80c3"; then
                echo "== ✔ OK：已枚举 303a:80c3（UAC+CDC），拔板换下一块 =="
            else
                echo "!! 刷写成功但未自动复位——请按板上 RESET(SW1)，看到屏幕动画即 OK !!"
            fi
        else
            echo "!! 刷写失败：确认设备在下载模式（lsusb 应有 303a:1001 或 :0009）!!"
        fi
        echo "-- 等待拔板 --"
        while ls /dev/ttyACM* >/dev/null 2>&1; do sleep 1; done
        echo "-- 已拔出，等下一块 --"
    fi
    sleep 1
done
