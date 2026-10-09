#!/bin/bash
# Runs release/install-standalone.sh and release/restore-android.sh against the
# fake adb/fastboot in tests/mock. No phone needed, nothing real is touched.
# Needs e2fsprogs and android-tools (img2simg, simg2img).
set -euo pipefail
T="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$T")"
export MOCK_DIR=$(mktemp -d /tmp/klee-mock.XXXXXX)
trap 'rm -rf "$MOCK_DIR"' EXIT
M=$MOCK_DIR
mkdir -p $M/dev $M/tmp $M/sdcard $M/flashed $M/rel/images
echo android > $M/mode; : > $M/logical; : > $M/calls.log

fakeboot() { { printf 'ANDROID!'; head -c $(( $2 - 8 )) /dev/urandom; } > "$1"; }
fakeboot $M/dev/boot_b 65536
fakeboot $M/dev/init_boot_b 32768
for p in vendor_boot_b dtbo_b vbmeta_b vbmeta_system_b vbmeta_vendor_b nvram nvdata nvcfg protect1 protect2 md_sec persist proinfo; do
	head -c 4096 /dev/urandom > $M/dev/$p
done
cp $M/dev/boot_b $M/android_boot.orig; cp $M/dev/init_boot_b $M/android_init_boot.orig

cp "$REPO/release/install-standalone.sh" "$REPO/release/restore-android.sh" $M/rel/
fakeboot $M/rel/images/ut_boot.img 65536
fakeboot $M/rel/images/ut_init_boot.img 32768
head -c $((8 * 1048576)) /dev/urandom > $M/rel/images/ubuntu.img
export PATH="$T/mock:$PATH"

ok()   { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; exit 1; }

echo "== 1. dry run changes nothing"
(cd $M/rel && ./install-standalone.sh --dry-run >/dev/null)
grep -q '^fastboot flash' $M/calls.log && fail "dry run flashed something"
[ "$(cat $M/mode)" = android ] || fail "dry run rebooted the phone"
ok "no flash, phone still in Android"

echo "== 2. answering anything but ERASE cancels"
: > $M/calls.log
(cd $M/rel && echo no | ./install-standalone.sh >/dev/null 2>&1) && fail "install did not stop"
grep -q '^fastboot' $M/calls.log && fail "cancelled install touched fastboot"
ok "cancelled before fastboot"

echo "== 3. existing dual boot ut_data blocks the install"
echo "ut_data 3221225472" > $M/logical
(cd $M/rel && echo ERASE | ./install-standalone.sh >/dev/null 2>&1) && fail "install ignored ut_data"
: > $M/logical
ok "refused while ut_data exists"

echo "== 4. full install"
: > $M/calls.log
(cd $M/rel && echo ERASE | ./install-standalone.sh >/dev/null)
cmp -s $M/flashed/boot_b $M/rel/images/ut_boot.img || fail "boot_b is not ut_boot.img"
cmp -s $M/flashed/init_boot_b $M/rel/images/ut_init_boot.img || fail "init_boot_b is not ut_init_boot.img"
[ "$(blkid -o value -s TYPE $M/flashed/userdata.raw)" = ext4 ] || fail "userdata is not ext4"
debugfs -R "dump ubuntu.img $M/check.img" $M/flashed/userdata.raw 2>/dev/null
cmp -s $M/check.img $M/rel/images/ubuntu.img || fail "ubuntu.img in userdata differs"
e2fsck -fn $M/flashed/userdata.raw >/dev/null 2>&1 || fail "userdata fsck failed"
BK=$(ls -d $M/rel/backup-standalone-* | head -1)
cmp -s $BK/boot.img $M/android_boot.orig || fail "boot backup wrong"
cmp -s $BK/init_boot.img $M/android_init_boot.orig || fail "init_boot backup wrong"
[ -f $BK/imei/nvdata.img ] && (cd $BK/imei && sha256sum -c --quiet SHA256SUMS) || fail "IMEI backup wrong"
grep -q '^adb reboot bootloader' $M/calls.log || fail "did not use the bootloader"
ok "boot/init_boot flashed, ext4 userdata with ubuntu.img, backups correct"

echo "== 5. restore-android.sh"
echo bootloader > $M/mode
(cd $M/rel && ./restore-android.sh "$BK" >/dev/null)
cmp -s $M/dev/boot_b $M/android_boot.orig || fail "boot_b not restored"
cmp -s $M/dev/init_boot_b $M/android_init_boot.orig || fail "init_boot_b not restored"
[ "$(cat $M/mode)" = recovery ] || fail "did not reboot to recovery"
ok "Android boot images restored, rebooted to recovery"

echo "all tests passed"
