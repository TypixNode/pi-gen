#!/bin/bash
# Shrink a pi-gen .img so it fits a fixed-size target (CM4/CM5 eMMC, a small SD).
#
# Why this exists: export-image/02-set-sources runs apt dist-upgrade *inside* the
# already-sized image, so the root partition has to be built with enough slack to
# hold the downloaded archives (ROOT_MARGIN_PERCENT=45 in config-typixdeck-dev,
# ~1.5 GB). That slack is dead weight afterwards - the first boot grows the root
# partition to fill the storage anyway - but it pushes the image past the 8 GB of
# a CM4002008. This cuts the root filesystem back to what it actually uses plus
# SLACK_MB, moves the partition end in and truncates the file.
#
# Runs inside the Lima VM (needs losetup/e2fsck/resize2fs/parted, all Linux-only):
#   limactl shell default -- sudo bash scripts/shrink-image.sh <image.img> [slack_mb]
set -euo pipefail

IMG="${1:?usage: $0 <image.img> [slack_mb]}"
SLACK_MB="${2:-300}"
[ -f "$IMG" ] || { echo "no such image: $IMG" >&2; exit 1; }

before=$(stat -c%s "$IMG")
echo "== $IMG: $((before / 1000000)) MB before"

LOOP=$(losetup -Pf --show "$IMG")
cleanup() { losetup -d "$LOOP" 2>/dev/null || true; }
trap cleanup EXIT
ROOT="${LOOP}p2"

e2fsck -fy "$ROOT" >/dev/null 2>&1 || true   # resize2fs refuses an unchecked fs
BLK=$(tune2fs -l "$ROOT" | awk -F: '/Block size/ {gsub(/ /,"",$2); print $2}')
blocks() { tune2fs -l "$ROOT" | awk -F: '/Block count/ {gsub(/ /,"",$2); print $2}'; }

# One "resize2fs -M" rarely reaches the real minimum: ext4 leaves blocks near the
# end that it will only relocate on a later pass (a 7.0 GB fs holding 5.5 GB
# stopped at 7.3 GB on the first try). Keep going until it stops shrinking.
min_blocks=$(blocks)
for pass in 1 2 3 4 5; do
	resize2fs -M "$ROOT" >/dev/null 2>&1 || break
	e2fsck -fy "$ROOT" >/dev/null 2>&1 || true
	now=$(blocks)
	echo "   pass $pass: $((now * BLK / 1000000)) MB"
	[ "$now" -ge "$min_blocks" ] && { min_blocks=$now; break; }
	min_blocks=$now
done
target_blocks=$((min_blocks + SLACK_MB * 1024 * 1024 / BLK))
resize2fs "$ROOT" "$target_blocks" >/dev/null
fs_bytes=$((target_blocks * BLK))
echo "   root fs: $((min_blocks * BLK / 1000000)) MB minimum + ${SLACK_MB} MB slack"

losetup -d "$LOOP"; trap - EXIT

# Move the partition end in to match the filesystem, keeping the start put.
# sfdisk, not parted: "parted -s resizepart" still stops on its own "are you
# sure?" prompt and leaves the table untouched.
start_s=$(sfdisk -d "$IMG" | awk '/2 :/ {gsub(/,/,"",$4); print $4}')
size_s=$((fs_bytes / 512))
echo ",${size_s}" | sfdisk -q --no-reread -N 2 "$IMG" >/dev/null
truncate -s $(((start_s + size_s) * 512)) "$IMG"

after=$(stat -c%s "$IMG")
echo "== $((after / 1000000)) MB after (saved $(((before - after) / 1000000)) MB)"

# Prove the result still mounts and the partition table agrees with the fs.
LOOP=$(losetup -Pf --show "$IMG"); trap 'losetup -d "$LOOP" 2>/dev/null || true' EXIT
e2fsck -fn "${LOOP}p2" >/dev/null && echo "   root fs checks out"
mkdir -p /mnt/shrink-verify && mount -o ro "${LOOP}p2" /mnt/shrink-verify
echo "   mounted: $(df -h --output=size,used,avail /mnt/shrink-verify | tail -1)"
ls /mnt/shrink-verify/usr/src >/dev/null && echo "   rootfs looks intact"
umount /mnt/shrink-verify
