#!/bin/bash
# Ubuntu Touch STANDALONE installer for Poco X8 Pro (klee)
#
# Replaces Android: Ubuntu Touch gets the whole userdata partition (ext4) and
# the active slot's boot + init_boot. ALL ANDROID DATA (/data, internal
# storage: photos, apps, everything) IS ERASED. For keeping Android, use
# install.sh (dual boot) instead.
#
# Start with the phone booted into Android, USB debugging on, root (KernelSU)
# granted to the "Shell" app. Root is only needed for the backups (boot images
# and the IMEI/NVRAM partitions), which are taken before anything is changed.
#
#   ./install-standalone.sh            full install
#   ./install-standalone.sh --dry-run  only checks + backups + image, changes nothing on the phone
#
# NOT TESTED ON A DEVICE. The dual boot setup was tested; this mode uses the
# same kernel/ramdisk/rootfs, only the data partition differs.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
IMG="$HERE/images"
WORK="$HERE/work"
DRY=""
[ "${1:-}" = "--dry-run" ] && DRY=1

# The image is built small and the initramfs grows the filesystem to the whole
# userdata partition on the first boot (resize_userdata_if_needed).
DATA_IMG_MIB=4096

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

cat <<'EOF'

  #####################################################################
  #  STANDALONE INSTALL: this ERASES ALL ANDROID DATA on the phone.   #
  #  Photos, apps, chats, internal storage: everything in /data.      #
  #  Copy what you want to keep to a computer first.                  #
  #  Not tested on a device. Use install.sh to keep Android.          #
  #####################################################################

EOF

say "1/6 Checking the phone (must be booted into Android with adb)"
adb wait-for-device
dev=$(adb shell getprop ro.product.device | tr -d '\r')
[ "$dev" = "klee" ] || die "this is '$dev', not klee"
SLOT=$(adb shell getprop ro.boot.slot_suffix | tr -d '\r')
[ "$SLOT" = "_a" ] || [ "$SLOT" = "_b" ] || die "unknown slot '$SLOT'"
asu id | grep -q 'uid=0' || die "no root: allow 'Shell' in KernelSU manager and retry"
echo "device=klee slot=$SLOT"
# The initramfs prefers the dual boot partition when it exists
if asu "ls /dev/block/mapper/ut_data" >/dev/null 2>&1; then
	die "a dual boot ut_data partition exists; Ubuntu Touch would keep using it. Run ./uninstall.sh first"
fi

say "2/6 Backing up the boot images of slot $SLOT (needed to go back to Android)"
STAMP=$(date +%Y%m%d-%H%M%S)
BK="$HERE/backup-standalone-$STAMP"
mkdir -p "$BK"
for p in boot init_boot vendor_boot dtbo vbmeta vbmeta_system vbmeta_vendor; do
	if asu "dd if=/dev/block/by-name/$p$SLOT of=/data/local/tmp/$p.img bs=1M 2>/dev/null" \
	   && adb pull "/data/local/tmp/$p.img" "$BK/$p.img" >/dev/null; then
		echo "  saved $p$SLOT ($(stat -c %s "$BK/$p.img") bytes)"
	else
		case $p in boot|init_boot) die "could not back up $p$SLOT";; esac
		warn "could not back up $p$SLOT"
	fi
	asu "rm -f /data/local/tmp/$p.img" || true
done
head -c 8 "$BK/boot.img" | grep -q 'ANDROID!' || die "boot backup looks wrong"
head -c 8 "$BK/init_boot.img" | grep -q 'ANDROID!' || die "init_boot backup looks wrong"
echo "$SLOT" > "$BK/slot"

# IMEI / modem calibration / device-unique data (MediaTek). Not slotted.
# Restore with "fastboot flash <name> <name>.img" if they ever get damaged.
say "2b/6 Backing up IMEI / NVRAM partitions (keep this folder safe, also off this computer!)"
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

say "3/6 Building the userdata image (${DATA_IMG_MIB} MiB ext4 with ubuntu.img, grows on first boot)"
mkdir -p "$WORK"
RAW="$WORK/ut_userdata.raw"
SIMG="$WORK/ut_userdata.img"
rm -f "$RAW" "$SIMG"
truncate -s "${DATA_IMG_MIB}M" "$RAW"
# Halium's initramfs ships e2fsck 1.43: keep the feature set it understands
mkfs.ext4 -q -F -L userdata -b 4096 -m 0 -O ^metadata_csum,^metadata_csum_seed,^orphan_file "$RAW"
# debugfs can't cope with spaces in paths: use a symlink
L=$(mktemp -d /tmp/klee-ut.XXXXXX)
ln -s "$IMG/ubuntu.img" "$L/ubuntu.img"
echo "write $L/ubuntu.img ubuntu.img" | debugfs -w -f - "$RAW" >/dev/null
rm -f "$L/ubuntu.img"; rmdir "$L"
debugfs -R "stat ubuntu.img" "$RAW" 2>/dev/null | grep -q 'Type: regular' || die "failed to write ubuntu.img into the image"
e2fsck -fn "$RAW" >/dev/null || die "userdata image check failed"
img2simg "$RAW" "$SIMG"
rm -f "$RAW"

if [ -n "$DRY" ]; then
	say "Dry run finished: backups in $BK, image in $SIMG. Nothing was changed on the phone."
	exit 0
fi

echo
read -r -p "Type ERASE (capital letters) to wipe Android's data and install Ubuntu Touch: " ans
[ "$ans" = "ERASE" ] || die "cancelled, nothing was changed on the phone"

say "4/6 Rebooting into the bootloader (fastboot)"
adb reboot bootloader
echo "waiting for fastboot..."
until fastboot devices 2>/dev/null | grep -q fastboot; do sleep 1; done
fastboot getvar is-userspace 2>&1 | grep -q 'yes' && die "this is fastbootd, expected the bootloader's fastboot"
size=$(fastboot getvar partition-size:userdata 2>&1 | awk '/partition-size:userdata:/{print $2}')
[ -n "$size" ] && [ $((size)) -gt $((DATA_IMG_MIB * 1048576)) ] \
	|| die "could not read the userdata size ('$size'), nothing was flashed"
echo "userdata: $(( size / 1073741824 )) GiB"

say "5/6 Flashing boot + init_boot (slot $SLOT)"
fastboot flash "boot$SLOT" "$IMG/ut_boot.img"
fastboot flash "init_boot$SLOT" "$IMG/ut_init_boot.img"

say "6/6 Writing Ubuntu Touch to userdata (Android's data is erased now)"
fastboot flash userdata "$SIMG"

say "Done. Booting Ubuntu Touch (the first boot can take a few minutes)."
fastboot reboot
cat <<EOF

Backups (boot images + IMEI/NVRAM): $BK
Copy this folder somewhere safe. To go back to Android later: ./restore-android.sh $BK
EOF
