# plasma-mobile-stage

Adds a **KDE Plasma Mobile 6** touch UI on top of the Lite rootfs produced by
`stage2`. Used by the `config-typixdeck-plasma-mobile` variant:

```
STAGE_LIST="stage0 stage1 stage2 plasma-mobile-stage typixdeck-stage"
```

> **Status: Beta.** Plasma Mobile on the Raspberry Pi KMS driver has known
> rendering issues (see below). The image is published as a pre-release /
> Beta variant and is not the recommended daily driver yet.

## What it does

- Installs from the Debian trixie repositories (recommends enabled, which
  Plasma needs): `plasma-mobile`, `plasma-mobile-tweaks`, `plasma-settings`,
  `sddm`, `kscreen`, `vulkan-tools`.
- Sets the default systemd target to `graphical.target` and enables `sddm`.
- Configures SDDM autologin for the first user (pi-gen `FIRST_USER_NAME`)
  into the Plasma Mobile Wayland session via
  `/etc/sddm.conf.d/autologin.conf` (`Session=plasma-mobile`, i.e.
  `/usr/share/wayland-sessions/plasma-mobile.desktop`).
- Presets the Qt Quick rendering backend to `software` (see below).

This stage does **not** export an image itself (no `EXPORT_IMAGE` here); the
final image of the variant is exported by `typixdeck-stage`.

## Known rendering issue and how to switch back to OpenGL

Plasma Mobile 6 on the Raspberry Pi KMS/V3D driver has reported rendering
problems (e.g. a black screen in the task switcher under OpenGL, missing
drawer icons under software rendering). As a conservative default this stage
ships `/etc/xdg/plasma-workspace/env/00-qt-quick-backend.sh`, which sets

```sh
export QT_QUICK_BACKEND=software
```

for Plasma sessions only (startplasma sources `*.sh` files from
`plasma-workspace/env/` at session startup; the SDDM greeter and non-Plasma
sessions are unaffected).

To switch back to GPU (OpenGL/RHI) rendering, either:

- delete `/etc/xdg/plasma-workspace/env/00-qt-quick-backend.sh`, or
- override it per user — user scripts are sourced after the system-wide
  ones — e.g.:

  ```sh
  mkdir -p ~/.config/plasma-workspace/env
  echo 'export QT_QUICK_BACKEND=rhi' > ~/.config/plasma-workspace/env/99-qt-quick-backend.sh
  ```

then log out and back in (or reboot). The Qt Quick backend can also be
inspected/changed through the "Qt Quick Settings" KCM
(`kcm_qtquicksettings`) where available.

## Caveats

- The SDDM autologin entry is written for the build-time `FIRST_USER_NAME`.
  If the first-boot setup (cloud-init / userconf) renames the user,
  `/etc/sddm.conf.d/autologin.conf` must be updated to match.
- Plasma Mobile is designed for touch; on the TypixDeck DPI panel the
  1024x768 layout and touch input need real-hardware validation.
