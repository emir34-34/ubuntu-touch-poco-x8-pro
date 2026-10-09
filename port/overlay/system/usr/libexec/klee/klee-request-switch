#!/bin/sh
# klee dual boot: ask OrangeFox to switch OS. Leaves an OpenRecoveryScript on
# the rescue partition (OrangeFox's /cache) and reboots to recovery; after the
# PIN is entered OrangeFox runs klee-switch.sh and boots the system again.
# Runs as root on Axion and on Ubuntu Touch.
#   klee-request-switch.sh ubuntu|android
set -u
export PATH=/system/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH

case "${1:-}" in
	ubuntu|android) TARGET=$1 ;;
	*) echo "usage: $0 ubuntu|android"; exit 2 ;;
esac
die() { echo "ERROR: $*"; exit 1; }

[ "$(id -u)" = 0 ] || die "not running as root"

# Axion can check the images early; Ubuntu Touch cannot read Android's
# encrypted /data, there klee-switch.sh checks them again in OrangeFox anyway
D=/data/adb/klee
if [ -d /system/app ] && [ ! -d /run/systemd/system ]; then
	[ -f "$D/klee-switch.sh" ] || die "$D/klee-switch.sh not found"
	(cd "$D" && sha256sum -c SHA256SUMS >/dev/null 2>&1) || die "image files are corrupt (SHA256 mismatch)"
	echo "Images verified"
fi

RESCUE=
for p in /dev/block/by-name/rescue /dev/disk/by-partlabel/rescue; do
	[ -b "$p" ] && RESCUE=$p && break
done
[ -n "$RESCUE" ] || die "rescue partition not found"

M=/mnt/klee-rescue
[ -d /run/systemd/system ] && M=/run/klee-rescue  # Ubuntu Touch: / is read-only
mkdir -p "$M" || die "could not create $M"
mount -t ext4 "$RESCUE" "$M" || die "could not mount rescue"
mkdir -p "$M/recovery"
cat > "$M/recovery/openrecoveryscript" <<EOF
cmd sh /data/adb/klee/klee-switch.sh $TARGET
reboot system
EOF
ok=$?
chmod 644 "$M/recovery/openrecoveryscript"
sync
umount "$M"
rmdir "$M" 2>/dev/null
[ $ok = 0 ] || die "could not write the script"

echo "Restarting into OrangeFox."
echo "Enter your lock screen PIN; the rest is automatic."
sleep 2
if [ -d /run/systemd/system ]; then
	systemctl reboot recovery
else
	reboot recovery
fi
