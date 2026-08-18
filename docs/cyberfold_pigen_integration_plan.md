# CyberFold (TypixDeck) → pi-gen 集成技术方案

> 状态：待 review。日期：2026-08-18。
> 目标仓库：`eggfly/pi-gen`（master，已含 CI workflows）。素材来源：`eggfly/CyberFold`。

---

## 0. 一句话目标

把 CyberFold 的硬件支持（DPI RGB 屏、GT911 触摸、CM5/非 CM5 两套 PWM 背光 overlay）、亮度托盘、MCU 刷机脚本全部打进 pi-gen，产出两种 arm64 镜像变体（官方 Raspberry Pi Desktop / KDE Plasma Mobile），CI 加缓存提速，自动生成带详细 Beta 构建信息的 Pi Imager `os_list.json`，并在自定义仓库 JSON 里定义我们自己的设备条目（带图标和描述，**不需要改 Imager 源码**）。

---

## 1. 现状盘点（已调研核实）

### 1.1 pi-gen fork（本仓库 master）

- 相对上游只有 2 个自有 commit：CI workflows（`d38311e`）+ 文档（`f8e1838`），stage0–5 业务逻辑未动。
- **已有 4 个 GitHub Actions workflow**（回答"actions workflow 已经有了？"——是的）：
  - `build-image.yml`：可复用核心，跑在 `ubuntu-24.04-arm` 原生 arm64 runner（无 QEMU），发 GitHub Release（`.img.xz` + sha256 + bmap + info），slim 变体会生成 `os_list.json` 并上传到指针 Release。
  - `build.yml`：手动构建 stock lite/desktop/full。
  - `build-slim-desktop.yml`：push 到 `slim-desktop-v*`/`cursor/**` 自动构建并更新 `slim-desktop-latest` 指针上的 `os_list.json`。
  - `append-os-list.yml`：把已有 Release 合并进 os_list。
  - 生成脚本：`scripts/make-os-list-json`。
- **当前完全没有缓存**（无 actions/cache、无 apt 缓存），每次全量构建。
- 注意：`build-slim-desktop.yml` 引用的 `config-slim-desktop`、`slim-desktop-stage/` 只在分支 `origin/cursor/slim-desktop-4gb-emmc-225e` 上，master 没有——master 直接跑 slim 会失败。
- `stage2/01-sys-tweaks/00-packages` 里 **装了 `rpi-connect-lite`**（本次要删）。

### 1.2 CyberFold 仓库可移植资产

| 资产 | 路径 | 状态 |
|------|------|------|
| DPI RGB 屏 overlay（HD317001C40/JD9168S 1024×768） | `display/device_tree/HD317001C40_1024x768/vc4-kms-dpi-3inch2-1024x768.dts/.dtbo` | 量产可用 |
| GT911 触摸 overlay（i2c-gpio SDA=10 SCL=11, INT=27, 0x14+0x5D） | 同目录 `gt911-touch-3inch2-1024x768.dts/.dtbo` | 量产可用 |
| PWM 背光 overlay（**非 CM5**：BCM283x，`&pwm` 通道 0，GPIO18 ALT5） | 同目录 `pwm-backlight-3inch2-bcm.dts/.dtbo` | 量产可用 |
| PWM 背光 overlay（**CM5**：RP1，`&rp1_pwm0` 通道 2，GPIO18 func=pwm0） | 同目录 `pwm-backlight-3inch2-rp1.dts/.dtbo` | 量产可用 |
| 亮度托盘（右上角） | `scripts/brightness_tray/brightness-tray.py` | 单文件 Python，依赖 `gir1.2-ayatanaappindicator3-0.1` |
| ESP32-S3 刷机脚本 + 固件 | `firmware/typixdeck_esp32s3_lcd_init_touch_gui_uac_cdc/release/flash_esp32.sh` + `typixdeck_esp32s3_full_20260818.bin` | 魔法串重启进 boot；Pi 上需 `--no-stub` + 460800 |
| STM32 键盘刷机脚本 + 固件 | `firmware/keebdeck_6r11c/release/flash_kbd.sh` + `*_20260818.bin` | dfu-util, DFU `0483:df11` |
| 已有 pi-gen stage 雏形 | `third_party/pi-gen/typixdeck-stage`（只做了 DPI+GT911，**没有 PWM、没有托盘**） | 参考，合并进本仓库 |
| 安装 SOP | `docs/typixdeck_cm5_pi_setup_2026-08.md`（config.txt 权威版本） | 依据 |

### 1.3 对原始需求描述的三处澄清（重要）

1. **"C3 插件"实际不存在**：协处理器是 **ESP32-S3**（C3 只出现在 LoRa/Meshtastic 设想文档里）。右上角亮度控件是 `brightness-tray.py`，通过写 `/sys/class/backlight/backlight_pwm/brightness` 调节（16 档），**不与 MCU 通信**。本方案按 brightness-tray 移植。
2. **overlay 顺序**：CyberFold 文档中的硬性要求是 **"PWM 背光 overlay 必须在 DPI overlay 之后"**（背光 fragment 要挂到 `/panel` 节点），而非"触摸在 DPI 之后"。实际采用顺序：`DPI → GT911 触摸 → PWM 背光`，三者都满足。
3. **".32 那个 IP 的包清单"没有找到**：CyberFold 仓库和历史会话里出现过的实机 IP 是 `192.168.3.84 / 192.168.3.85（CM5 桌面）/ 192.168.50.150（pi-gen 镜像机）/ 192.168.50.132 / 192.168.110.135`，没有以 `.32` 结尾的记录。目前从文档/脚本汇总出的确认包清单见 §3.4，**请 review 时确认是否还有遗漏来源**。

---

## 2. 互联网验证结论（已核实）

### 2.1 自定义仓库 JSON 可以定义自定义设备（不用改 Imager）✅

官方 **Repository JSON V4** 格式在顶层 `imager.devices[]` 里支持完整的自定义设备定义：

| 字段 | 说明 |
|------|------|
| `name` | 设备显示名（如 "CardputerZero"） |
| `description` | 描述文本（设备选择页第二行） |
| `icon` | PNG 图标 URL（设备选择页图标） |
| `tags` | OS 条目通过 `devices[]` 引用的标签 |
| `default` | 是否默认选中 |
| `matching_type` | `inclusive` / `exclusive`：未声明 tag 的 OS 是否显示 |
| `capabilities` | Imager 2.x 新增，控制自定义向导能力 |

加载方式：Imager「App Options → Content Repository → Use custom URL」（即第一张截图那个入口）或 `rpi-imager --repo <url>`。
参考：[官方博客 How to add your own images to Imager](https://www.raspberrypi.com/news/how-to-add-your-own-images-to-imager/)、[rpi-imager schema-notes](https://github.com/raspberrypi/rpi-imager/blob/main/doc/schema-notes.md)、[uConsole 社区实践](https://forum.clockworkpi.com/t/experimental-content-repository-for-raspberry-imager/22077)。

**结论：不需要 fork Imager。** 只要用户装的是官方 Imager 较新版本（v1.7.3+ 支持 devices，capabilities 需 2.x），我们只维护一个 `os_list.json` 即可实现自定义设备 + 图标 + 描述的效果。（注：M5 Imager 是另一个无关项目，与本项目无任何关系，不在方案范围内。）

### 2.2 KDE Plasma Mobile 在 Debian trixie arm64 可行 ✅（有风险）

- `plasma-mobile 6.3.6-3` 在 **trixie (stable) arm64** 官方仓库可用，另有元包 `plasma-mobile-full`、`plasma-mobile-phone-components`、`plasma-mobile-tweaks`。
- 安装路径：Lite 基础（stage2）上 `apt install plasma-mobile plasma-mobile-tweaks sddm` + `systemctl set-default graphical.target`。
- **已知风险**：树莓派论坛报告 Plasma Mobile 6 在 Pi 5 + KMS 驱动上有渲染问题（OpenGL 下任务切换器黑屏、Software 渲染下抽屉图标不显示），可能需要调 `kcm_qtquicksettings` 渲染后端，我们的 DPI 面板需实测。方案：镜像标记为 Beta，进 CI 但不阻塞主线。

### 2.3 CI 缓存最佳实践 ✅

社区共识（`usimd/pi-gen-action` 及其 [PR #201](https://github.com/usimd/pi-gen-action/pull/201) 的教训）：

- **推荐：apt-cacher-ng + actions/cache**。runner 上装 apt-cacher-ng（端口 9999），`actions/cache` 持久化 `/var/cache/apt-cacher-ng`，pi-gen 用现成的 `APT_PROXY` 配置项指过去。包下载是 pi-gen 最大耗时项之一，且我们是原生 arm64 runner（无 QEMU），此方案收益最直接。
- **不要缓存 WORK_DIR/rootfs**：恢复陈旧 rootfs 后 `export-image` 按旧尺寸分区，dist-upgrade 撑爆分区（上面 PR 就是修这个的）；且单份缓存易吃掉 10GB 配额的一半。
- 补充：cache key 带 `runner.arch` 和 stage 列表 hash，避免污染。

### 2.4 触摸屏虚拟键盘包名 ✅

Raspberry Pi OS（bookworm/trixie, labwc）的屏幕键盘是 **`squeekboard` + `wfplug-squeek`**（任务栏切换插件）。删除方式：包列表尾部 `-` 语法或 stage 内 purge。需确认它是否被 `rpd-wayland-core` recommends 拉入，实测后用最干净的方式排除。

### 2.5 其他"好看界面"候选（后续可选变体）

| 变体 | 包基础 | 备注 |
|------|--------|------|
| KDE Plasma Desktop | trixie `kde-plasma-desktop` (Plasma 6.3) | 社区在 Pi 5 上反馈流畅，最成熟的"好看"选项 |
| GNOME 48 | `gnome-core` | 触屏手势体验最好，但资源占用高，4GB+ 推荐 |
| Hyprland | trixie 有包；社区有 Pi 5 预配置项目 Pimarchy | 最炫，配置成本高，适合发烧友变体 |
| LXQt 2.x | `lxqt` | 轻量现代，低配设备候补 |

建议：本期只做「官方 Desktop」+「Plasma Mobile」两个变体，把变体机制（每变体一个 config + stage 组合）做通用，后续加新桌面只是加 config。

---

## 3. 实施方案

### 3.1 WS1 — `typixdeck-stage`：硬件支持 stage（新建于本仓库）

新建 `typixdeck-stage/`（构建时 `STAGE_LIST="stage0 stage1 stage2 stage3 stage4 typixdeck-stage"`，Lite/PlasmaMobile 变体则接在 stage2 后），内容：

1. **overlays 子步骤**：拷入 4 个 `.dts` 源文件，构建时用 `dtc -@` 现场编译进 `/boot/firmware/overlays/`（装 `device-tree-compiler`；不直接用仓库里的 `.dtbo`，保证可追溯可重编）。
2. **config.txt 注入**（追加到 `/boot/firmware/config.txt`，权威顺序来自 `typixdeck_cm5_pi_setup_2026-08.md`）：

   ```ini
   [cm4]
   otg_mode=1
   [cm5]
   dtoverlay=dwc2,dr_mode=host

   [all]
   dtoverlay=vc4-kms-dpi-3inch2-1024x768
   dtoverlay=gt911-touch-3inch2-1024x768
   enable_uart=0

   # PWM 背光必须在 DPI overlay 之后（挂 /panel）
   [cm5]
   dtoverlay=pwm-backlight-3inch2-rp1
   [cm4]
   dtoverlay=pwm-backlight-3inch2-bcm
   [pi0]
   dtoverlay=pwm-backlight-3inch2-bcm
   [all]
   ```

   同时确保 BCM 机型不启用 `dtparam=audio=on`（PWM 硬件冲突，处理 stage1 默认 config.txt 中的该行）。
3. **亮度托盘**：`brightness-tray.py` 装到 `/usr/local/bin/`，包依赖 `gir1.2-ayatanaappindicator3-0.1`，labwc 自启动（`/etc/xdg/labwc/autostart` 系统级，参考 CyberFold `scripts/README.md` 的 `sleep 3` 方案）；附装 `brightnessctl`、`swayosd`（键盘亮度键 OSD）。Plasma Mobile 变体不装托盘（面板体系不同），只保留 sysfs 背光 + brightnessctl。
4. **刷机工具**：`flash_esp32.sh`、`flash_kbd.sh` 及各版本 firmware `.bin` 放入镜像 `/opt/typixdeck/firmware/`（按日期版本保留多版本），装 `dfu-util`、`esptool`（Pi 上走 `--no-stub` 路径）。firmware 体积小（<10MB），进镜像便于现场维护。
5. **删包**：
   - `rpi-connect` / `rpi-connect-lite`（stage2 已装 lite，用 `rpi-connect-lite-` 覆盖或 stage 内 purge）；
   - `squeekboard` + `wfplug-squeek`（触摸屏虚拟键盘）。
6. **实用包**：`evtest`、`i2c-tools`、`python3-smbus`、`fbset`、`device-tree-compiler`（§3.4 清单）。

### 3.2 WS2 — 两个镜像变体 + Imager 元数据

命名决议（已确认）：**设备名叫 TypixDeck；镜像名保持树莓派原有命名风格**（IMG_NAME 沿用 `raspios-trixie-arm64` 风格加后缀）。

| 变体 | stage 组合 | IMG_NAME | Imager 显示名 |
|------|-----------|----------|----------------------|
| 官方桌面 | stage0–4 + typixdeck-stage | `raspios-trixie-arm64-typixdeck` | `Raspberry Pi OS Desktop (Trixie arm64) for TypixDeck` — "Debian Trixie arm64 with Raspberry Pi Desktop, for TypixDeck." |
| Plasma Mobile | stage0–2 + plasma-mobile-stage + typixdeck-stage | `raspios-trixie-arm64-typixdeck-plasma-mobile` | `Raspberry Pi OS + KDE Plasma Mobile (Trixie arm64) for TypixDeck (Beta)` — "KDE Plasma Mobile 6 touch UI. Pre-release." |

- 新建 `plasma-mobile-stage/`：`plasma-mobile plasma-mobile-tweaks plasma-settings sddm kscreen` + `graphical.target`，sddm 自动登录，渲染后端预设写好（规避 §2.2 的已知问题）。
- 每变体一个 config 文件（`config-typixdeck`、`config-typixdeck-plasma-mobile`），`IMG_NAME`/`RELEASE=trixie`/`ARCH=arm64`。
- **Beta 详细构建信息**（第三张截图效果）：`scripts/make-os-list-json` 增强，正式版和 Beta 版条目区分：
  - `name`: `TypixDeck OS (Trixie arm64) 20260818-080953 (Beta)`（UTC 构建时间戳）
  - `description`: `Debian Trixie arm64 desktop for TypixDeck. Pre-release build. commit <sha7>, workflow run #<run_number>.`
  - `release_date`、`extract_size`、`extract_sha256`、`image_download_size`、`devices` 照常生成。

### 3.3 WS3 — CI/CD：缓存 + os_list 发布

1. `build-image.yml` 增加：
   - `actions/cache`（`apt-cache/` ↔ `/var/cache/apt-cacher-ng`，key 含 `runner.arch` + variant）；
   - runner 装 apt-cacher-ng（Port 9999），pi-gen config 设 `APT_PROXY=http://127.0.0.1:9999`（原生构建非 docker，直接 localhost）；
   - **不缓存 WORK_DIR**（§2.3 的坑）。
2. 新增/改造 `build-typixdeck.yml`：matrix 两个变体，push tag `typixdeck-v*` 或手动触发；Beta 由 push 非 tag 分支触发。
3. os_list 发布沿用现有机制：每次构建后合并进指针 Release（新建 `typixdeck-latest` tag）上的 `os_list.json`，稳定 URL 即"包地址 JSON"：
   `https://github.com/eggfly/pi-gen/releases/download/typixdeck-latest/os_list.json`
4. os_list.json 顶层增加 `imager.devices[]`：定义 `TypixDeck`（及后续 CardputerZero / CM4Stack）设备条目，icon PNG 放仓库内用 raw URL 或 Release asset。OS 条目结构：正式版置顶 + 按时间倒序的 Beta 子列表（`subitems` 折叠，模仿官方仓库层级）。

### 3.4 已确认的 apt 包清单（来自 CyberFold 文档/脚本）

装：`device-tree-compiler`、`gir1.2-ayatanaappindicator3-0.1`、`brightnessctl`、`swayosd`、`evtest`、`i2c-tools`、`python3-smbus`、`fbset`、`dfu-util`、`esptool`。
删：`rpi-connect-lite`（stage2 默认装）、`rpi-connect`（防 recommends）、`squeekboard`、`wfplug-squeek`。
（"`.32` 机器"的额外包清单待确认，见 §5 问题 1。）

---

## 4. Subagent 执行划分（review 通过后启动）

| # | 任务 | 产出 | 依赖 |
|---|------|------|------|
| A | WS1：`typixdeck-stage`（overlay 编译、config.txt、托盘、刷机工具、删包） | 新 stage 目录 + config-typixdeck | 无 |
| B | WS2：`plasma-mobile-stage` + 变体 config | 新 stage + config | A（共用 typixdeck-stage） |
| C | WS3：CI 缓存 + build-typixdeck workflow + make-os-list-json 增强（Beta 命名/描述、imager.devices、指针 Release） | workflow + 脚本改动 | A/B 的 config 名确定即可并行 |
| D | 设备 icon（PNG）+ 自定义仓库 README（用户如何在 Imager 填 URL） | 图标资产 + 文档 | 可完全并行 |

验收：CI 全绿产出两个 `.img.xz` + `os_list.json`；官方 Imager 填自定义 URL 后能看到自定义设备（图标+描述）和两类镜像（正式 + Beta 带构建详情）；镜像烧录后屏幕/触摸/背光/托盘可用（人工实机验收）。

---

## 5. 已确认的决议（2026-08-18 review）

1. **包清单**：不再追查 ".32" 机器，按 §3.4 汇总清单执行。
2. **亮度插件**：按 `brightness-tray.py`（sysfs 方案）移植，不做 ESP32-S3 串口通信插件。
3. **firmware 刷机脚本**：进镜像 `/opt/typixdeck/firmware/`。
4. **squeekboard**：确认删除（有 KeebDeck 实体键盘）。
5. **Imager**：只面向官方 Imager + 自定义 repo URL。M5 Imager 是无关项目，与本项目无任何关系。
6. **命名**：设备名 `TypixDeck`；镜像名保持树莓派原有命名风格（见 §3.2）。
