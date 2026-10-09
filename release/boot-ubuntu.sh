#!/bin/bash
# Switch the phone to Ubuntu Touch: flash UT boot + init_boot to the active slot.
# Works from Axion (adb) or with the phone already in bootloader fastboot mode.
# Axion's /data is not touched; ./boot-axion.sh switches back.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SLOT=$(cat "$HERE/backup-latest/slot" 2>/dev/null || echo _b)
if adb get-state >/dev/null 2>&1; then adb reboot bootloader; fi
echo "waiting for fastboot..."
until fastboot devices 2>/dev/null | grep -q fastboot; do sleep 1; done
cur=$(fastboot getvar current-slot 2>&1 | awk '/current-slot:/{print $2}')
[ -n "$cur" ] && SLOT="_${cur#_}"
echo "active slot: $SLOT"
fastboot flash boot$SLOT "$HERE/images/ut_boot.img"
fastboot flash init_boot$SLOT "$HERE/images/ut_init_boot.img"
fastboot reboot
echo "Booting Ubuntu Touch. First boot can take a few minutes."
