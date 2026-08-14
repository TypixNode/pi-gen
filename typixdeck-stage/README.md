# typixdeck-stage

Turns the slim labwc desktop image into **TypixDeckOS** for the
TypixDeck / TypixNode handheld (Raspberry Pi CM5 carrier board). Built with
`config-typixdeck`, which runs
`stage0 stage1 stage2 slim-desktop-stage typixdeck-stage`.

## What it does

### `00-install-kernel`

Installs a custom kernel: **rpi-6.18.y + the dwc2 ISO-OUT split fix**
(`drivers/usb/dwc2/hcd_queue.c`: no ISOC OUT start-split allowed in
uframe 7). Without it, a USB full-speed sound card behind the on-board FE2.1
hub is silently muted on the CM5's dwc2 controller (the begin/end-SSPLIT pair
of one FS transaction straddles a HS frame boundary and the hub's TT drops
the packet). See `docs/dwc2_iso_out_split_uframe7_rootcause_2026-08.md` in the
CyberFold repo for the full root cause, and
`docs/patches/0001-usb-dwc2-host-No-ISOC-OUT-start-split-allowed-in-ufr.patch`
for the patch itself.

The kernel is installed from `.deb` packages that are **not in git** (33MB+):
drop them into `files/debs/` before building. They are produced from the
patched kernel tree (branch `rpi-6.18.y` of
[TypixNode/linux](https://github.com/TypixNode/linux), `.config` derived from
`bcm2712_defconfig` with `CONFIG_LOCALVERSION="-dwc2fix"`) with:

```bash
make -j8 bindeb-pkg      # produces ../linux-image-6.18.44-dwc2fix+_*_arm64.deb
```

The stage then:

* `dpkg -i` the image (and, if present, headers) deb;
* runs `update-initramfs -c` for the new kernel;
* copies the kernel to `/boot/firmware/kernel-dwc2fix.img` (decompressed),
  the initramfs to `/boot/firmware/initramfs-dwc2fix`, and the 6.18 `bcm2712*`
  DTBs + overlays over the stock ones;
* appends to `config.txt`:

  ```
  kernel=kernel-dwc2fix.img
  initramfs initramfs-dwc2fix followkernel
  ```

Why this and not the official kernel package hooks: a `kernel=` line naming a
file the stock packages never write is the one mechanism an apt upgrade
cannot clobber — `linux-image-rpi-2712` only ever touches `kernel_2712.img`,
which stays installed as a fallback (comment out the two lines to boot it).
The counterpart trade-off is that a stock kernel upgrade rewrites the shared
DTBs/overlays in `/boot/firmware`; the 6.18 kernel still boots with those.

### `01-typixdeck-hw`

Compiles the display overlays with `dtc` inside the chroot and preloads them:

* `vc4-kms-dpi-3inch2-1024x768` — 3.2" 1024x768 DPI panel
  (HD317001C40 / JD9168S);
* `gt911-touch-3inch2-1024x768` — GT911 touch over bit-banged I2C.

The `.dts` sources are copies of
`display/device_tree/HD317001C40_1024x768/*.dts` from the CyberFold repo
(decompiled style with explicit `__fixups__`, compiled without `-@`).
`config.txt` gets the two `dtoverlay=` lines plus `enable_uart=0` (the UART
pins belong to the DPI panel).

## Imager customisation

Nothing here touches cloud-init: the image keeps
`init_format: cloudinit-rpi`, so Raspberry Pi Imager's hostname / user /
password / Wi-Fi / SSH / locale options keep working. See `imager/README.md`
for publishing the image to a custom Imager repository.
