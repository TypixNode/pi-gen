# 在官方 Raspberry Pi Imager 中烧录 TypixDeck 镜像

本仓库的 CI 会自动构建 TypixDeck（基于 Raspberry Pi CM4/CM5 的折叠 cyberdeck，带 1024x768 DPI 触摸屏）的系统镜像，并发布一份 Raspberry Pi Imager 可以直接读取的 `os_list.json`。**不需要安装任何修改版 Imager**，官方 Imager 填一个自定义仓库 URL 即可看到 TypixDeck 设备和它的全部镜像。

## 版本要求

- 自定义设备条目（`imager.devices[]`）需要 **Imager v1.7.3 及以上**；
- `capabilities` 字段（控制自定义向导能力）需要 **Imager 2.x**；
- 建议直接安装[最新版官方 Imager](https://www.raspberrypi.com/software/)。

## 一、配置自定义仓库

仓库地址（稳定 URL，始终指向最新构建）：

```
https://github.com/TypixNode/pi-gen/releases/download/typixdeck-latest/os_list.json
```

### 方式 A：图形界面

1. 打开 Raspberry Pi Imager；
2. 进入 **App Options（应用选项）→ Content Repository（内容仓库）**；
3. 选择 **Use custom URL（使用自定义 URL）**，粘贴上面的地址并确认；
4. Imager 会重新加载镜像列表。

### 方式 B：命令行

```bash
rpi-imager --repo https://github.com/TypixNode/pi-gen/releases/download/typixdeck-latest/os_list.json
```

## 二、选择设备和镜像

1. 点击 **CHOOSE DEVICE（选择设备）**，列表第一项即为 **TypixDeck**（带图标和描述，默认选中）；
2. 点击 **CHOOSE OS（选择镜像）**，会看到：
   - **Raspberry Pi OS Desktop (Trixie arm64) for TypixDeck** —— 正式版（由 `typixdeck-v*` tag 构建），面向 CM4/CM5；
   - **Raspberry Pi OS Slim Desktop (Trixie arm64) for TypixDeck** —— 裁剪版桌面，适配 Compute Module 3 的 4GB eMMC（约 3GB 镜像），同样带全套 TypixDeck 硬件支持；
   - **Raspberry Pi OS + KDE Plasma Mobile (Trixie arm64) for TypixDeck (Beta)** —— Plasma Mobile 变体，触摸优先界面，**始终标记为 Beta**（KMS 驱动下已知有渲染问题，见构建方案文档）；
   - **… (Beta builds)** 文件夹 —— 每个变体各有一个折叠子目录，按时间倒序存放历史 Beta 构建。Beta 条目名称形如
     `Raspberry Pi OS Desktop (Trixie arm64) for TypixDeck 20260818-080953 (Beta)`（UTC 构建时间戳），描述中带有构建来源信息（`Pre-release build. commit <sha7>, workflow run #<编号>.`），方便反馈问题时精确定位到构建；
3. 选择存储卡 / eMMC，正常走 Imager 流程即可。高级选项（主机名、用户名密码、SSH、Wi-Fi、时区等）通过 cloud-init（`init_format: cloudinit-rpi`）生效，与官方 Trixie 镜像机制相同。

> 注意：TypixDeck 设备的 `matching_type` 为 `exclusive`，即选中 TypixDeck 后只显示为它构建的镜像；反之，选择其他树莓派设备时不会看到 TypixDeck 镜像。想看到所有条目可选择 "No filtering"。

## 三、Beta 镜像保留策略

CI 只保留每个变体**最近 5 个** Beta 构建的 Release，`os_list.json` 中的 Beta 子目录也同步只列最近 5 个。更早的 Beta 下载链接会失效（404）。如果想长期固定某一个构建，可以使用该构建自己 Release 页面里的 `os_list.json`（镜像和校验和永不变化）：

```bash
rpi-imager --repo https://github.com/TypixNode/pi-gen/releases/download/<构建tag>/os_list.json
```

## 附：os_list.json 的 `imager.devices` 字段说明

`os_list.json` 顶层的 `imager.devices[]` 定义了设备选择页的条目，TypixDeck 条目如下：

```json
{
  "name": "TypixDeck",
  "tags": ["typixdeck"],
  "default": true,
  "icon": "https://raw.githubusercontent.com/TypixNode/pi-gen/typixdeck/imager/typixdeck-icon.png",
  "description": "Foldable cyberdeck based on the Raspberry Pi CM4/CM5 with a 1024x768 DPI touchscreen",
  "matching_type": "exclusive",
  "capabilities": []
}
```

| 字段 | 含义 |
| --- | --- |
| `name` | 设备选择页显示的名称 |
| `tags` | 设备标签；OS 条目通过自己的 `devices[]` 引用这些标签来声明兼容性 |
| `default` | 是否默认选中该设备 |
| `icon` | 设备图标（PNG URL） |
| `description` | 设备选择页第二行的描述文字 |
| `matching_type` | `exclusive`：只显示明确声明了匹配标签的 OS；`inclusive`：未声明标签的 OS 也显示 |
| `capabilities` | Imager 2.x 的自定义向导能力开关（本设备暂不使用） |

OS 条目通过 `"devices": ["typixdeck"]` 与设备关联；`extract_size`、`extract_sha256`、`image_download_size`、`image_download_sha256` 由 CI 从真实产物测量得出，Imager 下载后会校验，保证烧录内容与发布内容一致。

相关参考：[官方博客 How to add your own images to Imager](https://www.raspberrypi.com/news/how-to-add-your-own-images-to-imager/)、[rpi-imager schema-notes](https://github.com/raspberrypi/rpi-imager/blob/main/doc/schema-notes.md)。
