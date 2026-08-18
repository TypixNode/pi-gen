#!/usr/bin/env python3
# TypixDeck 背光亮度托盘小程序（wf-panel-pi 右上角托盘区）
#
# 背景：wf-panel-pi 没有官方亮度插件（截至 Trixie 1.13，2026-08 实查），
# 本程序用 StatusNotifier(AppIndicator) 协议挂进 libtray.so 托盘区。
# 依赖：gir1.2-ayatanaappindicator3-0.1（apt）
# 亮度后端：/sys/class/backlight/backlight_pwm（pwm-backlight overlay，16 级）
# 写权限来自 raspberrypi-sys-mods 的 udev 规则（video 组），无需 root。
#
# 交互：图标滚轮 = ±1 级；点开菜单选预设档位。
# 最低到 1 不到 0：0 级 = 背光全灭，触屏环境下会把自己锁在黑屏里。

import glob
import os
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("AyatanaAppIndicator3", "0.1")
from gi.repository import AyatanaAppIndicator3 as AppIndicator
from gi.repository import GLib, Gtk

BL_DIR = next(iter(glob.glob("/sys/class/backlight/*")), None)
MIN_LEVEL = 1

if BL_DIR is None:
    sys.exit("no /sys/class/backlight device")

MAX_LEVEL = int(open(os.path.join(BL_DIR, "max_brightness")).read())

PRESETS = [  # (标签, 级别)
    ("100%", MAX_LEVEL),
    ("80%", max(MIN_LEVEL, round(MAX_LEVEL * 0.8))),
    ("60%", max(MIN_LEVEL, round(MAX_LEVEL * 0.6))),
    ("40%", max(MIN_LEVEL, round(MAX_LEVEL * 0.4))),
    ("20%", max(MIN_LEVEL, round(MAX_LEVEL * 0.2))),
    ("最低", MIN_LEVEL),
]


def get_level() -> int:
    return int(open(os.path.join(BL_DIR, "brightness")).read())


def set_level(level: int) -> None:
    level = max(MIN_LEVEL, min(MAX_LEVEL, level))
    with open(os.path.join(BL_DIR, "brightness"), "w") as f:
        f.write(str(level))


class BrightnessTray:
    def __init__(self):
        self.ind = AppIndicator.Indicator.new(
            "brightness-tray",
            "display-brightness-symbolic",
            AppIndicator.IndicatorCategory.HARDWARE,
        )
        self.ind.set_status(AppIndicator.IndicatorStatus.ACTIVE)
        self.ind.connect("scroll-event", self.on_scroll)

        self.menu = Gtk.Menu()
        self.current_item = Gtk.MenuItem(label="")
        self.current_item.set_sensitive(False)
        self.menu.append(self.current_item)
        self.menu.append(Gtk.SeparatorMenuItem())
        for label, level in PRESETS:
            item = Gtk.MenuItem(label=label)
            item.connect("activate", self.on_preset, level)
            self.menu.append(item)
        self.menu.show_all()
        self.ind.set_menu(self.menu)

        self.refresh()
        GLib.timeout_add_seconds(3, self.refresh)  # 跟随外部修改（如 Control Centre）

    def refresh(self) -> bool:
        level = get_level()
        pct = round(level * 100 / MAX_LEVEL)
        self.current_item.set_label(f"亮度：{pct}%（{level}/{MAX_LEVEL}）")
        self.ind.set_title(f"背光 {pct}%")
        return True

    def on_preset(self, _item, level: int) -> None:
        set_level(level)
        self.refresh()

    def on_scroll(self, _ind, _steps, direction) -> None:
        from gi.repository import Gdk

        delta = 1 if direction == Gdk.ScrollDirection.UP else -1
        set_level(get_level() + delta)
        self.refresh()


if __name__ == "__main__":
    BrightnessTray()
    Gtk.main()
