# stage2/05-boot-splash — eggfly custom boot splash

Replaces the boot experience with a custom **eggfly** splash. It is built on
**Plymouth** (the same mechanism the ClockworkPi uConsole/DevTerm use to change
their boot logo) plus a small **initramfs** hook that lets you override the
image at runtime from the FAT boot partition — without rebuilding the image.

## What it does

1. Installs the `plymouth` package.
2. Installs a Plymouth theme at `/usr/share/plymouth/themes/eggfly/`:
   - `splash.png` — the baked-in default still image;
   - `eggfly-anim-*.png` — a small rainbow spinner (a non-blocking animation);
   - `eggfly.script` / `eggfly.plymouth` — the theme definition.
3. Makes `eggfly` the default Plymouth theme (`plymouth-set-default-theme`).
4. Installs an initramfs `init-top` script (`eggfly-splash`) that runs **before**
   Plymouth shows and can override the image from the boot partition.
5. Adds `vfat` + `nls_*` to the initramfs modules so the boot partition is
   readable that early.
6. Edits the firmware boot files:
   - `config.txt`: `disable_splash=1` (hides the firmware rainbow so our splash
     takes its place);
   - `cmdline.txt`: appends `quiet splash plymouth.ignore-serial-consoles
     logo.nologo loglevel=3 vt.global_cursor_default=0` (enables Plymouth and
     hides the kernel logo/log spam).

The initramfs itself is regenerated at the end of the build by
`export-image/05-finalise` (`update-initramfs -k all -c`), which bundles the
theme and the override script automatically.

## Fallback chain (matches the requested behaviour)

When the splash is about to be shown, the source image is chosen in this order:

- **(c) TF-card image present** → use the image from the FAT boot partition.
- **(a) TF-card image absent** → use the baked-in `eggfly` default.
- **(b) baked-in default also absent** → Plymouth just shows its background.

## Customising from the boot partition (no rebuild)

The boot partition is the small FAT drive that mounts at `/boot/firmware` on the
running Pi, and shows up as a removable drive when you put the card in another
computer. Drop **either** of these onto it:

- `eggfly-splash.png` — a single custom still image; **or**
- `eggfly-splash/` — a folder of PNG frames (`00.png`, `01.png`, …) for a custom
  animation. Frames are used in sorted filename order.

Delete them to fall back to the baked-in default. No `update-initramfs` needed —
the override happens live, each boot, inside the initramfs.

## Timing / expectations

- Plymouth appears within roughly the first **2–3 seconds**, right after the
  firmware hands off to the kernel — i.e. in place of the rainbow screen.
- The spinner is animated and **does not block** boot: it is driven by
  Plymouth's refresh callback, which runs in parallel with the rest of startup.
- Truly sub-second, "the very instant of the rainbow" display is only possible
  with the closed firmware or the kernel's built-in logo; with KMS the
  framebuffer only exists once the display driver probes. Plymouth at ~2–3s is
  the robust, animation-capable sweet spot. If you want an additional *static*
  image even earlier, enable the official kernel early splash
  (`fullscreen_logo=1` + a TGA in `/lib/firmware`) alongside this.
- Because the boot-partition override runs in `init-top`, on boot media that
  enumerate late the override may not be ready in time and the baked-in default
  is shown instead. This is by design (graceful fallback).

## Regenerating the default artwork

The PNGs are committed so the image build needs no image tooling. To change the
default artwork, edit and re-run the generator (needs `pip install Pillow`):

```bash
python3 files/tools/generate-splash.py
```

## Testing

This cannot be verified in CI (it requires booting real Pi hardware or an
emulator with a framebuffer). To test on a device:

1. Build an image that includes this stage and flash it.
2. Boot: you should see the eggfly splash with a spinning rainbow, no rainbow
   firmware screen, and no kernel log text.
3. Copy an `eggfly-splash.png` onto the boot partition, reboot, and confirm your
   image replaces the default.
4. `sudo plymouth-set-default-theme` should report `eggfly`.
5. To preview the theme on a running desktop Pi without rebooting:
   `sudo plymouthd; sudo plymouth --show-splash; sleep 5; sudo plymouth --quit`.
