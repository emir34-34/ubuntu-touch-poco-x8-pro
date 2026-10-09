#!/bin/bash
# Go back from a STANDALONE Ubuntu Touch install to Android.
# Writes the saved Android boot + init_boot back to the active slot, then
# reboots into recovery, where userdata has to be formatted for Android
# (Ubuntu Touch's ext4 userdata, and everything in it, is lost).
#
# Start with the phone in bootloader fastboot mode (Vol- + Power), or in
# Ubuntu Touch: systemctl reboot --reboot-argument=bootloader
#   ./restore-android.sh backup-standalone-<date>
set -euo pipefail
BK="${1:?usage: $0 backup-standalone-<date>}"
for f in boot.img init_boot.img; do
	[ -f "$BK/$f" ] || { echo "missing $BK/$f"; exit 1; }
	head -c 8 "$BK/$f" | grep -q 'ANDROID!' || { echo "$BK/$f is not a boot image"; exit 1; }
done
echo "waiting for the bootloader (fastboot)..."
until fastboot devices 2>/dev/null | grep -q fastboot; do sleep 1; done
fastboot getvar is-userspace 2>&1 | grep -q 'yes' && { echo "this is fastbootd, use the bootloader's fastboot (Vol- + Power)"; exit 1; }
cur=$(fastboot getvar current-slot 2>&1 | awk '/current-slot:/{print $2}')
SLOT="_${cur#_}"
[ "$SLOT" = "_a" ] || [ "$SLOT" = "_b" ] || { echo "unknown slot '$cur'"; exit 1; }
[ -f "$BK/slot" ] && [ "$(cat "$BK/slot")" != "$SLOT" ] && \
	echo "note: the backup is from slot $(cat "$BK/slot"), the active slot is now $SLOT"
fastboot flash "boot$SLOT" "$BK/boot.img"
fastboot flash "init_boot$SLOT" "$BK/init_boot.img"
fastboot reboot recovery
cat <<'EOF'

Android's boot images are back. The phone is starting the recovery now.
In the recovery choose "Format Data" (OrangeFox: Wipe > Format Data, type "yes"),
then reboot to system. Android starts with a fresh setup.
If the recovery is not there any more, flash your ROM again from fastboot.
EOF
