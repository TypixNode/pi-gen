# TypixDeckOS in Raspberry Pi Imager

`typixnode-os.json` is a Raspberry Pi Imager OS list (the same v4 format as
the official `os_list_imagingutility_v4.json`). Pointing Imager at it puts
**TypixDeckOS** into the OS picker, with all of Imager's advanced options
(hostname, username/password, Wi-Fi, SSH, locale) working — the image ships
cloud-init and declares `init_format: cloudinit-rpi`, which is how Trixie
images receive that customisation.

## Publishing a release

1. Build the image: `./build-docker.sh -c config-typixdeck` — the artifact is
   `deploy/<date>-TypixDeckOS.img.xz`.
2. Upload it, e.g. to a GitHub release of this repo:

   ```bash
   gh release create v2026.08.14 deploy/2026-08-14-TypixDeckOS.img.xz \
       --repo TypixNode/pi-gen --title "TypixDeckOS 2026-08-14"
   ```

3. Fill the sizes and hashes in and commit:

   ```bash
   imager/update-json.sh deploy/2026-08-14-TypixDeckOS.img.xz \
       https://github.com/TypixNode/pi-gen/releases/download/v2026.08.14/2026-08-14-TypixDeckOS.img.xz
   git commit -am "imager: publish 2026-08-14 image"
   ```

   The script streams the archive through xz once to compute
   `image_download_size`, `image_download_sha256`, `extract_size` and
   `extract_sha256` — never edit those by hand: Imager verifies them and a
   published archive must stay immutable.

Keep the download URL and the JSON in step: Imager fetches the JSON from the
raw URL below every time it starts, so the JSON in the `typixdeck` branch
must always describe an archive that is actually downloadable.

## Using it in Imager

The raw JSON URL:

```
https://raw.githubusercontent.com/TypixNode/pi-gen/typixdeck/imager/typixnode-os.json
```

Either launch Imager with the repository flag:

```bash
# macOS
/Applications/Raspberry\ Pi\ Imager.app/Contents/MacOS/rpi-imager \
    --repo https://raw.githubusercontent.com/TypixNode/pi-gen/typixdeck/imager/typixnode-os.json

# Linux / Windows: same --repo flag on the rpi-imager binary
```

or set it persistently: Imager ≥ 1.8 reads the `os_list_url` key from its
settings file (`~/Library/Preferences/org.raspberrypi.Imager.plist` on macOS,
`~/.config/Raspberry Pi/Imager.conf` on Linux, registry on Windows — add
`os_list_url=<raw JSON URL>` under `[General]` in the .conf).

Then: choose *Raspberry Pi 5* as the device (a CM5 counts as one), pick
**TypixDeckOS (64-bit)**, hit the gear (or Ctrl/Cmd-Shift-X) for the advanced
options, flash. On first boot cloud-init applies the customisation; the
default hostname is `typixdeck` when none is set.

`icon` currently points at `imager/typixnode.png` in this branch, which does
not exist yet — Imager falls back to a generic icon until someone commits a
40x40-ish PNG logo there.
