#!/bin/bash
# Ubuntu Touch dual boot installer for Poco X8 Pro (klee)
#
# Android (Axion) and its /data stay untouched. Ubuntu Touch is installed into a
# NEW logical partition "ut_data" in the free space of super. Switching between
# the two systems = swapping the boot + init_boot images of the active slot.
#
# Start with the phone booted into Axion, USB debugging on, root (KernelSU)
# granted to the "Shell" app.
#
#   ./install.sh            full install (backup, create ut_data, flash rootfs)
#   ./install.sh --dry-run  only checks + backups, changes nothing on the phone
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
IMG="$HERE/images"
WORK="$HERE/work"
DRY=""
[ "${1:-}" = "--dry-run" ] && DRY=1

UT_DATA_MIN_MIB=2560     # ubuntu.img (EROFS, ~1.2 GiB) + >=1.3 GiB for apps/settings/home
UT_DATA_MAX_MIB=6144

say()  { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mXX %s\033[0m\n' "$*"; exit 1; }
asu()  { adb shell "su -c '$*'"; }

for f in ut_boot.img ut_init_boot.img ubuntu.img; do
	[ -f "$IMG/$f" ] || die "missing $IMG/$f"
done
command -v adb >/dev/null && command -v fastboot >/dev/null || die "adb/fastboot not found"
command -v mkfs.ext4 >/dev/null && command -v debugfs >/dev/null && command -v img2simg >/dev/null \
	|| die "need e2fsprogs (mkfs.ext4, debugfs) and android-tools (img2simg)"

say "1/6 Checking the phone (must be booted into Axion with adb)"
adb wait-for-device
dev=$(adb shell getprop ro.product.device | tr -d '\r')
[ "$dev" = "klee" ] || die "this is '$dev', not klee"
SLOT=$(adb shell getprop ro.boot.slot_suffix | tr -d '\r')
[ "$SLOT" = "_a" ] || [ "$SLOT" = "_b" ] || die "unknown slot '$SLOT'"
asu id | grep -q 'uid=0' || die "no root: allow 'Shell' in KernelSU manager and retry"
echo "device=klee slot=$SLOT"

say "2/6 Backing up boot images of slot $SLOT (needed to go back to Axion)"
STAMP=$(date +%Y%m%d-%H%M%S)
BK="$HERE/backup-$STAMP"
mkdir -p "$BK"
for p in boot init_boot vendor_boot dtbo vbmeta vbmeta_system vbmeta_vendor; do
	if asu "dd if=/dev/block/by-name/$p$SLOT of=/data/local/tmp/$p.img bs=1M 2>/dev/null" \
	   && adb pull "/data/local/tmp/$p.img" "$BK/$p.img" >/dev/null; then
		echo "  saved $p$SLOT ($(stat -c %s "$BK/$p.img") bytes)"
	else
		case $p in boot|init_boot) die "could not back up $p$SLOT";; esac
		warn "could not back up $p$SLOT (not needed for dual boot)"
	fi
	asu "rm -f /data/local/tmp/$p.img" || true
done
# sanity: the boot backup must be a real Android boot image
head -c 8 "$BK/boot.img" | grep -q 'ANDROID!' || die "boot backup looks wrong"
head -c 8 "$BK/init_boot.img" | grep -q 'ANDROID!' || die "init_boot backup looks wrong"
echo "$SLOT" > "$BK/slot"

# IMEI / modem calibration / device-unique data (MediaTek). Not slotted.
# Kept OFF the phone too: restore with "fastboot flash <name> <name>.img" if
# they ever get damaged (e.g. lost IMEI). Ubuntu Touch's Android container mounts
# nvdata/nvcfg/protect*/md_sec/persist read-write exactly like Android does.
say "2b/6 Backing up IMEI / NVRAM partitions (keep this folder safe!)"
mkdir -p "$BK/imei"
for p in nvram nvdata nvcfg protect1 protect2 md_sec persist proinfo; do
	if asu "dd if=/dev/block/by-name/$p of=/data/local/tmp/$p.img bs=1M 2>/dev/null" \
	   && adb pull "/data/local/tmp/$p.img" "$BK/imei/$p.img" >/dev/null; then
		echo "  saved $p ($(stat -c %s "$BK/imei/$p.img") bytes)"
	else
		case $p in nvram|nvdata|protect1|protect2) die "could not back up $p (IMEI data) - stopping for safety";; esac
		warn "could not back up $p"
	fi
	asu "rm -f /data/local/tmp/$p.img" || true
done
(cd "$BK/imei" && sha256sum *.img > SHA256SUMS)
ln -sfn "backup-$STAMP" "$HERE/backup-latest"

say "3/6 Checking free space in super"
asu "lpdump --slot=${SLOT#_}" > "$BK/lpdump.txt" 2>&1 || asu "lpdump" > "$BK/lpdump.txt"
if grep -q 'Name: ut_data' "$BK/lpdump.txt"; then
	EXISTS=1
	warn "ut_data already exists (re-install: it will be recreated, Ubuntu Touch data is lost)"
else
	EXISTS=""
fi
super_bytes=$(awk '/Block device table/{f=1} f&&/Size:/{print $2; exit}' "$BK/lpdump.txt")
# lines look like: "super: 2048 .. 3456592: odm_b (3454544 sectors)"
used_sectors=$(awk '/^super: /{s=$6; gsub(/[(]/,"",s); n+=s} END{print n+0}' "$BK/lpdump.txt")
# don't count an old ut_data as used
old_ut=$(awk '/^super: / && $5=="ut_data"{s=$6; gsub(/[(]/,"",s); n+=s} END{print n+0}' "$BK/lpdump.txt")
free_mib=$(( (super_bytes - (used_sectors - old_ut) * 512) / 1048576 - 64 ))
echo "super=$((super_bytes/1048576)) MiB, free≈${free_mib} MiB"
[ "$free_mib" -ge "$UT_DATA_MIN_MIB" ] || die "not enough free space in super (${free_mib} MiB < ${UT_DATA_MIN_MIB} MiB)"
UT_MIB=$free_mib
[ "$UT_MIB" -gt "$UT_DATA_MAX_MIB" ] && UT_MIB=$UT_DATA_MAX_MIB
echo "ut_data will be ${UT_MIB} MiB"

say "4/6 Building ut_data image (${UT_MIB} MiB ext4 with ubuntu.img + Axion boot backups)"
mkdir -p "$WORK"
RAW="$WORK/ut_data.raw"
rm -f "$RAW" "$WORK/ut_data.img"
truncate -s "${UT_MIB}M" "$RAW"
# Halium's initramfs ships e2fsck 1.43: keep the feature set it understands
mkfs.ext4 -q -F -L ut_data -b 4096 -m 0 -O ^metadata_csum,^metadata_csum_seed,^orphan_file "$RAW"
# debugfs can't cope with spaces in paths (this folder has them): use symlinks
L=$(mktemp -d /tmp/klee-ut.XXXXXX)
ln -s "$IMG/ubuntu.img" "$L/ubuntu.img"
ln -s "$IMG/ut_boot.img" "$L/ut_boot.img"
ln -s "$IMG/ut_init_boot.img" "$L/ut_init_boot.img"
ln -s "$BK/boot.img" "$L/android_boot.img"
ln -s "$BK/init_boot.img" "$L/android_init_boot.img"
ln -s "$BK/slot" "$L/slot"
{
	echo "write $L/ubuntu.img ubuntu.img"
	echo "mkdir klee-dualboot"
	for f in android_boot.img android_init_boot.img ut_boot.img ut_init_boot.img slot; do
		echo "write $L/$f klee-dualboot/$f"
	done
} | debugfs -w -f - "$RAW" >/dev/null
rm -f "$L"/*; rmdir "$L"
for f in ubuntu.img klee-dualboot/android_boot.img klee-dualboot/android_init_boot.img; do
	debugfs -R "stat $f" "$RAW" 2>/dev/null | grep -q 'Type: regular' || die "failed to write $f into ut_data"
done
e2fsck -fn "$RAW" >/dev/null || die "ut_data image check failed"
img2simg "$RAW" "$WORK/ut_data.img"
rm -f "$RAW"

if [ -n "$DRY" ]; then
	say "Dry run finished: backups in $BK, image in $WORK/ut_data.img. Nothing was changed on the phone."
	exit 0
fi

say "5/6 Pushing switch scripts + images to the phone (/sdcard/klee-ut)"
adb shell mkdir -p /sdcard/klee-ut
adb push "$IMG/ut_boot.img" "$IMG/ut_init_boot.img" "$HERE/device/to-ubuntu.sh" "$HERE/klee-ubuntu-gec.zip" /sdcard/klee-ut/ >/dev/null

say "6/6 Creating ut_data in super (fastbootd) and flashing it"
adb reboot fastboot
echo "waiting for fastbootd..."
until fastboot devices 2>/dev/null | grep -q fastboot; do sleep 1; done
fastboot getvar is-userspace 2>&1 | grep -q 'yes' || die "not in fastbootd (userspace fastboot)"
fastboot getvar snapshot-update-status 2>&1 | grep -qE 'none|status: *$' \
	|| warn "an OTA snapshot may be pending; if creating the partition fails, boot Axion once and retry"
[ -n "$EXISTS" ] && fastboot delete-logical-partition ut_data
fastboot create-logical-partition ut_data $((UT_MIB * 1048576))
fastboot flash ut_data "$WORK/ut_data.img"
fastboot getvar partition-size:ut_data

say "Done. Rebooting back into Axion (still untouched)."
fastboot reboot
cat <<EOF

Next:
  * Boot Ubuntu Touch:   ./boot-ubuntu.sh        (or on the phone: su -c sh /sdcard/klee-ut/to-ubuntu.sh)
  * Back to Axion:       ./boot-axion.sh         (or in Ubuntu Touch: sudo klee-boot-android)
Backups of your Axion boot images: $BK
EOF
