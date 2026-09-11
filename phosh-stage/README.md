# phosh-stage

Adds **Phosh** (the GNOME mobile shell: phoc compositor + phosh + squeekboard)
on top of the Lite rootfs produced by `stage2`. Used by the
`config-typixdeck-phosh` variant:

```
STAGE_LIST="stage0 stage1 stage2 phosh-stage typixdeck-stage"
```

> **Status: Beta.** Verified on a CM4 0720 board (Pi OS Trixie, kernel 6.18)
> on 2026-09-11; see "Known issues".

## What it does

- `00-install-packages/00-run.sh` pins `libwlroots-0.18` to the **Debian**
  build (`/etc/apt/preferences.d/typixdeck-phosh-wlroots`, priority 1001).
  The Raspberry Pi archive rebuilds libwlroots-0.18 with its own patches and
  Debian's `phoc` is not ABI compatible with it: phoc crashes with
  `*** stack smashing detected ***` / SIGSEGV in `phoc_output_compute_scale`
  right after `Output 'DPI-1' added` and the session bounces straight back
  to the login screen. labwc on Trixie links libwlroots-0.19, so phoc is the
  only consumer of 0.18 and the pin has no side effects. **This is a
  Phosh-only need** - the other variants keep the Raspberry Pi build.
- `00-install-packages/01-packages`: `phosh-core`, `phosh-mobile-settings`,
  `gnome-console`, `dconf-cli`, plus `wlr-randr` / `grim` for remote
  debugging (phoc is wlroots-based, so `grim` screenshots and wayvnc work).
- `01-phosh-config`:
  - `systemctl set-default graphical.target` + `systemctl enable phosh`:
    the `phosh.service` unit shipped by the package starts the shell on tty7
    as uid 1000 (the first user) - no display manager.
  - `/etc/phosh/phoc.ini`: `xwayland=false`, `[output:DPI-1] scale = 1.5`.
    Auto-scale on the ~400 ppi 3.2" panel is 1.25 (too small); 2.0 leaves a
    512x384 logical screen where Phosh's lock-screen keypad no longer fits.
  - `/etc/systemd/user/mobi.phosh.Shell.service.d/typixdeck-unlocked.conf`:
    `phosh --unlocked`.
  - dconf system defaults (`/etc/dconf/db/local.d/10-typixdeck-phosh`):
    lock screen disabled (`lock-enabled=false`, `disable-lock-screen=true`,
    `sm.puri.phosh.lockscreen require-unlock=false`), **no screensaver /
    blanking / dimming / suspend** (`idle-delay=0`, `idle-dim=false`,
    `sleep-inactive-*-type='nothing'`) and `show-battery-percentage=true`.

`typixdeck-stage` then runs as for every variant. Two of its steps are
Phosh-aware: `05-remove-packages` keeps `squeekboard` when `phosh` is
installed (it is Phosh's on-screen keyboard), and `03-keyboard-hwdb` swallows
the F13 the keyboard's square key sends - xkb maps F13 to `XF86Tools`, which
GNOME binds to "open Settings", so without the quirk every display toggle
popped up Settings.

## Known issues

- **No blanking on purpose.** phoc cannot change the DPI panel's power state
  (`Failed to set output power mode for DPI-1`), so GNOME's idle "blank" only
  paints a black frame with the backlight still on: it looks powered off and
  saves nothing. Until the backlight is wired into the session (e.g. via
  `brightnessctl` on idle), the screen simply stays on.
- Phosh assumes a tall phone screen. On the 4:3 landscape panel some dialogs
  need "scale to fit" (Mobile Settings -> Compositor) and the lock screen is
  unusable above scale ~1.3, which is why it is disabled.
- `Failed to set gamma for DPI-1` in the journal is harmless.
- The battery indicator needs the STC3117 driver from `typixdeck-stage`
  (`03-battery-dkms`); it shows "unknown" while the Pi/ESP I2C mux is on the
  ESP side.
