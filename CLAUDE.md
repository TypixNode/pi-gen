# pi-gen (TypixNode fork) — notes for AI agents

Branch `typixdeck` (arm64) carries `typixdeck-stage/` and the `config-typixdeck*`
files. CI (`.github/workflows/build-typixdeck.yml`) builds every push that touches
the stages, publishes `typixdeck-build-<date>-<sha>` pre-releases (`.img.xz`,
`.bmap`, `.info`) and merges them into the `typixdeck-latest` OS list for
Raspberry Pi Imager. A CI build takes ~17 min plus the 1.6 GB download.

## Local build on this Mac (fast dev loop, same environment as CI)

The build runs in a Docker container inside the **Lima VM `default`** (native
aarch64, 4 CPU / 4 GiB / 100 GiB, `~` mounted writable at the same path). Two
Docker daemons live in that VM — get this right or nothing works:

| daemon | socket | used for |
|---|---|---|
| rootless (user 501) | `~/.lima/default/sock/docker.sock` = Mac `docker` CLI, context `lima-default` | `apt-cacher-ng` container (port 3142 published on all VM interfaces) |
| **rootful** (`sudo docker` inside the VM) | `/var/run/docker.sock` in the VM | **the pi-gen build** — rootless cannot `losetup` for export-image |

The rootful daemon keeps the preserved container **`pigen_work`** whose volume holds
`/pi-gen/work/raspios-trixie-arm64-typixdeck-dev/` with stage0–4 already built
(~25 GB). `WORK_DIR` is keyed by `IMG_NAME`, not by date, so it is reused
automatically with `CONTINUE=1`.

`config-typixdeck-dev` (git-ignored: bakes in `FIRST_USER_PASS=raspberry`,
`ENABLE_SSH=1`, no first-boot rename, `WPA_COUNTRY=CN`, `IMG_NAME=…-dev`,
`DEPLOY_COMPRESSION=none`, `APT_PROXY=http://127.0.0.1:3142`,
`export ROOT_MARGIN_PERCENT=45`) sources `config-typixdeck`. Recreate it from
those values if it is missing.

### Recipe

```bash
# 0. VM + daemons (after a Mac reboot the VM is Stopped and both daemons are down)
limactl start default
limactl shell default -- sudo systemctl start user@501.service   # user bus for rootless
limactl shell default -- bash -c 'XDG_RUNTIME_DIR=/run/user/501 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/501/bus systemctl --user start docker'
limactl shell default -- sudo systemctl start docker              # rootful
docker context use lima-default && docker start apt-cacher-ng     # proxy (rootless)

# 1. only rebuild typixdeck-stage (stage0-4 come from the cached work dir)
cd ~/github/eggfly/pi-gen
touch stage0/SKIP stage1/SKIP stage2/SKIP stage3/SKIP stage4/SKIP   # git-ignored
# drop the stale stage rootfs so the stage runs on a fresh copy of stage4
limactl shell default -- sudo docker run --rm --volumes-from pigen_work debian:trixie \
  rm -rf /pi-gen/work/raspios-trixie-arm64-typixdeck-dev/typixdeck-stage \
         /pi-gen/work/raspios-trixie-arm64-typixdeck-dev/export-image /pi-gen/deploy

# 2. build (~10-15 min: copy stage4 rootfs, run the stage, export the image)
limactl shell default -- sudo bash -c 'cd /Users/eggfly/github/eggfly/pi-gen && \
  CONTINUE=1 PRESERVE_CONTAINER=1 PIGEN_DOCKER_OPTS="--network host" \
  ./build-docker.sh -c config-typixdeck-dev' 2>&1 | tee /tmp/pigen-local-build.log

# 3. result: build-docker.sh `docker cp`s /pi-gen/deploy into ./deploy on the Mac
ls -lh deploy/*-typixdeck-dev.img      # ~7 GB uncompressed, flash with Raspberry Pi Imager / dd
```

Full rebuild from scratch: remove the SKIP files and `sudo docker rm -v pigen_work`
(re-downloads everything through apt-cacher-ng; hours).

### Gotchas

- `--network host` is mandatory: `build.sh` curl-checks `APT_PROXY` and aborts if
  `127.0.0.1:3142` is unreachable from inside the build container.
- Disk: the VM had ~15 GB free with the cache present; the export needs ~8 GB.
  `docker image prune` on the rootless side and deleting old `deploy/*.img` on the
  Mac are the safe ways to make room. Never `docker rm -v pigen_work` casually —
  that is the 25 GB stage cache.
- `deploy/` on the Mac accumulates 7 GB images; delete old ones by hand.
- `typixdeck-stage/prerun.sh` copies the previous stage rootfs only when the stage
  dir does not exist — hence step 1 deletes it, otherwise the stage re-runs on top
  of its own old output (stale files survive).
- The cached stage rootfs ages; export-image dist-upgrades it inside the sized
  image and the stock 20 % margin overflowed on 2026-09-11 (`not enough free
  space in /var/cache/apt/archives`) — hence `ROOT_MARGIN_PERCENT=45` in the dev
  config. A full rebuild (fresh cache) does not need it.
- Lima's `docker` socket forward can report `EOF` right after `limactl start`
  while the rootless daemon is still down; start `user@501` + the user docker
  unit as in step 0.
