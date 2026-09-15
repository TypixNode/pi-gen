# TypixDeck image checks

Run by `scripts/verify-typixdeck-image` after every TypixDeck variant build
(the "Verify the image" step of `.github/workflows/build-image.yml`). A `FAIL`
fails the build, so no release is published; `WARN` and `SKIP` only report.
Results also go to the job summary.

Every `NN-name.sh` here is sourced in name order. Current groups:

| File | What it guards |
|---|---|
| `10-dwc2fix-kernel.sh` | the dwc2-fixed CM5 kernel (USB audio behind the FE2.1 hub): boot files, `[cm5]` config.txt lines, the patched `dwc2.ko` by srcversion (`dwc2fix-srcversions`), and the initramfs copy of it. Required when the config sets `TYPIXDECK_REQUIRE_KERNEL=1` |
| `20-stc3117-dkms.sh` | the battery gauge module built for every installed kernel |
| `30-overlays.sh` | the panel/touch/backlight/gauge overlays and their config.txt lines |
| `40-firmware.sh` | the ESP32-S3 and KeebDeck firmware bundle |

## Adding a check

Create `50-something.sh` (pick the number for its place in the order). It
runs in the verifier's shell, so use `return` to leave early, and these:

* `$BOOT`, `$ROOT` - the mounted boot and root partitions (read-only)
* `$BUILD_CONFIG`, `$TYPIXDECK_REQUIRE_KERNEL` - the variant being checked;
  read other config settings with `config_value NAME`
* `check "description" cmd args...` - PASS if the command succeeds, else FAIL
* `warn "description" cmd args...` - same, but a miss is only a warning
* `skip "description" "reason"`
* `config_txt_has <section> <line>` - config.txt has the line under
  `[section]` (`all` before any filter)
* `decompress <file>`, `module_field <module> <field>`,
  `kernel_image_has_version <kernel.img> <release>`,
  `initramfs_file_matches <initramfs> <path-inside> <file>`

Try it against a local image before pushing:

    sudo BUILD_CONFIG=config-typixdeck ./scripts/verify-typixdeck-image deploy/<image>.img
