#!/bin/bash
# EXPERIMENTAL: boot Ubuntu Touch once WITHOUT writing anything to the phone
# ("fastboot boot" of a single kernel+ramdisk image). On devices with an
# init_boot partition some bootloaders ignore the RAM ramdisk; if the phone just
# boots Axion again (or hangs on the logo), use ./boot-ubuntu.sh instead.
# Needs install.sh to have been run (the ut_data partition must exist).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
if adb get-state >/dev/null 2>&1; then adb reboot bootloader; fi
echo "waiting for fastboot..."
until fastboot devices 2>/dev/null | grep -q fastboot; do sleep 1; done
fastboot boot "$HERE/images/ut_boot_fastboot-boot.img"
