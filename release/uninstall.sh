#!/bin/bash
# Remove Ubuntu Touch completely: restore Axion's boot images (if UT is the
# active system) and delete the ut_data logical partition. Axion /data untouched.
# Start with the phone in bootloader fastboot mode (Vol- + Power) or in Axion.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BK="${1:-$HERE/backup-latest}"
[ -f "$BK/boot.img" ] || { echo "no backup in $BK"; exit 1; }
if adb get-state >/dev/null 2>&1; then adb reboot bootloader; fi
echo "waiting for fastboot..."
until fastboot devices 2>/dev/null | grep -q fastboot; do sleep 1; done
cur=$(fastboot getvar current-slot 2>&1 | awk '/current-slot:/{print $2}')
SLOT="_${cur#_}"
fastboot flash boot$SLOT "$BK/boot.img"
fastboot flash init_boot$SLOT "$BK/init_boot.img"
fastboot reboot fastboot
echo "waiting for fastbootd..."
sleep 5
until fastboot devices 2>/dev/null | grep -q fastboot; do sleep 1; done
fastboot delete-logical-partition ut_data || echo "(ut_data was not there)"
fastboot reboot
echo "Ubuntu Touch removed; booting Axion."
