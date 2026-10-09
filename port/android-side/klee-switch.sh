#!/system/bin/sh
# klee dual boot: write the boot + init_boot images of one OS to the active
# slot. Must run where those partitions are writable, i.e. in OrangeFox
# recovery (Android and Ubuntu Touch keep the active slot's boot partitions
# write protected). Every write is read back and verified; if anything fails
# the images of the other OS are written back, so the phone always stays
# bootable.
#   klee-switch.sh ubuntu|android
# Files (all in /data/adb/klee, which is not FBE encrypted):
#   ut_boot.img ut_init_boot.img        Ubuntu Touch images
#   axion_boot.img axion_init_boot.img  Axion images
#   SHA256SUMS                          checksums of the four images
set -u
export PATH=/system/bin:/sbin:/bin:/system/xbin:$PATH
D=/data/adb/klee
LOG=$D/last-switch.log
say() { echo "$*"; echo "$*" >> "$LOG" 2>/dev/null; }
die() { say "ERROR: $*"; exit 1; }

case "${1:-}" in
	ubuntu) NEW=ut; OLD=axion; NAME="Ubuntu Touch" ;;
	android) NEW=axion; OLD=ut; NAME="Axion" ;;
	*) echo "usage: $0 ubuntu|android"; exit 2 ;;
esac

say "== $(date) target=$NAME"
SLOT=$(getprop ro.boot.slot_suffix)
case "$SLOT" in _a|_b) ;; *) die "could not read the active slot ($SLOT)" ;; esac
say "Active slot: $SLOT"

cd "$D" 2>/dev/null || die "$D not found"
sha256sum -c SHA256SUMS >/dev/null 2>&1 || die "image files are corrupt (SHA256 mismatch), nothing was written"
say "Images verified"

same() { # image partition: is the image already on the partition?
	size=$(stat -c %s "$1")
	want=$(sha256sum < "$1" | cut -d' ' -f1)
	got=$(head -c "$size" "/dev/block/by-name/$2$SLOT" | sha256sum | cut -d' ' -f1)
	[ "$want" = "$got" ]
}

write_verify() { # image partition
	part=/dev/block/by-name/$2$SLOT
	[ -b "$part" ] || { say "partition missing: $part"; return 1; }
	dd if="$1" of="$part" bs=1M conv=fsync 2>/dev/null || say "write error: $2$SLOT"
	sync
	echo 3 > /proc/sys/vm/drop_caches
	same "$1" "$2" || { say "verification failed: $2$SLOT"; return 1; }
	say "$2$SLOT written and verified"
}

if same ${NEW}_boot.img boot && same ${NEW}_init_boot.img init_boot; then
	say "$NAME is already installed, nothing written"
	exit 0
fi

if write_verify ${NEW}_boot.img boot && write_verify ${NEW}_init_boot.img init_boot; then
	say "Done: the phone will boot $NAME"
	exit 0
fi

say "Something went wrong, writing the previous system back..."
if write_verify ${OLD}_boot.img boot && write_verify ${OLD}_init_boot.img init_boot; then
	die "the previous system was restored, the phone will boot it"
fi
die "the restore could not be verified either! Do NOT power off; stay in recovery and connect a computer"
