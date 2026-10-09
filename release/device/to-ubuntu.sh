#!/system/bin/sh
# Run on the phone inside Axion as root:  su -c sh /sdcard/klee-ut/to-ubuntu.sh
# Writes the Ubuntu Touch boot + init_boot to the active slot and reboots.
set -e
D=/sdcard/klee-ut
S=$(getprop ro.boot.slot_suffix)
[ "$(getprop ro.product.device)" = "klee" ] || { echo "not klee"; exit 1; }
for p in boot init_boot; do
	f=$D/ut_$p.img
	[ -f "$f" ] || { echo "missing $f"; exit 1; }
	blk=/dev/block/by-name/$p$S
	blockdev --setrw $blk 2>/dev/null || true
	size=$(blockdev --getsize64 $blk)
	[ "$(stat -c %s $f)" -le "$size" ] || { echo "$f too big for $blk"; exit 1; }
	echo "writing $f -> $blk"
	dd if=$f of=$blk bs=1M conv=fsync
done
sync
echo "Rebooting into Ubuntu Touch..."
reboot
