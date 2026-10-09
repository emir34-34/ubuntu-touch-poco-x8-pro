#!/bin/bash
# Switch the phone back to Axion: restore the boot + init_boot backups taken by install.sh.
# Use with the phone in bootloader fastboot mode (Vol- + Power), or from Ubuntu Touch
# run "sudo klee-boot-android" instead.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BK="${1:-$HERE/backup-latest}"
[ -f "$BK/boot.img" ] && [ -f "$BK/init_boot.img" ] || { echo "no backup in $BK"; exit 1; }
SLOT=$(cat "$BK/slot")
echo "waiting for fastboot..."
until fastboot devices 2>/dev/null | grep -q fastboot; do sleep 1; done
cur=$(fastboot getvar current-slot 2>&1 | awk '/current-slot:/{print $2}')
[ -n "$cur" ] && SLOT="_${cur#_}"
echo "active slot: $SLOT"
fastboot flash boot$SLOT "$BK/boot.img"
fastboot flash init_boot$SLOT "$BK/init_boot.img"
fastboot reboot
echo "Booting Axion."
