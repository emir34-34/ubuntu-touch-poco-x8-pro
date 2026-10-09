#!/bin/bash
# QEMU integration test of the klee Ubuntu Touch dual-boot images:
# real kernel + init_boot ramdisk + rootfs, with Axion's real vendor/odm/dlkm
# partitions inside an LP "super" (slot _b) next to ut_data.
# Diagnostics are printed on the serial console (serial.log) by klee-qtest.
set -euo pipefail
Q="$(cd "$(dirname "$0")" && pwd)"
A="$HOME/poco x8 pro ub touch/axion_imgs"
REL="$HOME/poco x8 pro ub touch/release/images"
cd "$Q"
export SUDO_ASKPASS=${SUDO_ASKPASS:?}

# initrd = fake vendor ramdisk (virtio modules) + our init_boot ramdisk
rm -rf ib; mkdir ib
unpack_bootimg --boot_img "$REL/ut_init_boot.img" --out ib >/dev/null
cat vendor_ramdisk.lz4 ib/ramdisk > initrd.img
cp "$HOME/klee-ut/kout/arch/arm64/boot/Image" Image

# rootfs copy + diagnostics service
# release rootfs is EROFS: inject into the ext4 work copy, then build an EROFS test image
cp --sparse=always "$HOME/klee-ut/work/ubuntu.img" ubuntu-test-ext4.img
mkdir -p m
sudo -A mount -o loop ubuntu-test-ext4.img m
sudo -A install -m 755 klee-qtest m/usr/local/bin/klee-qtest
sudo -A install -m 644 klee-qtest.service m/etc/systemd/system/klee-qtest.service
sudo -A ln -sf /etc/systemd/system/klee-qtest.service m/etc/systemd/system/multi-user.target.wants/klee-qtest.service
sudo -A mount -o remount,ro m
rm -f ubuntu-test.img
sudo -A mkfs.erofs -zlz4hc,12 -E ztailpacking -C 65536 ubuntu-test.img m >/dev/null
sudo -A umount m
sudo -A chown "$(id -u):$(id -g)" ubuntu-test.img
rm -f ubuntu-test-ext4.img

# ut_data (same layout as release/install.sh)
rm -f ut_data.raw
truncate -s 3086M ut_data.raw
mkfs.ext4 -q -F -L ut_data -b 4096 -m 0 -O ^metadata_csum,^metadata_csum_seed,^orphan_file ut_data.raw
printf '_b\n' > slot
printf 'write %s ubuntu.img\nmkdir klee-dualboot\nwrite %s klee-dualboot/slot\n' "$Q/ubuntu-test.img" "$Q/slot" \
	| debugfs -w -f - ut_data.raw >/dev/null 2>&1

# super (slot _b) + GPT disk
sz() { echo $(( ($(stat -L -c %s "$1") + 1048575) / 1048576 * 1048576 )); }
ARGS=()
for p in vendor odm vendor_dlkm system_dlkm odm_dlkm; do
	ARGS+=(--partition "${p}_b:readonly:$(sz "$A/$p.img"):main_b" --image "${p}_b=$A/$p.img")
done
rm -f super.img disk.img
lpmake --metadata-size 65536 --super-name super --metadata-slots 3 --device super:$((9*1024*1024*1024)) \
	--group main_b:$((4*1024*1024*1024)) "${ARGS[@]}" \
	--partition ut_data:none:$((3086*1024*1024)) --image ut_data=ut_data.raw --output super.img >/dev/null 2>&1
truncate -s $((9*1024 + 4))M disk.img
printf 'label: gpt\nstart=2048, size=%d, name=super\n' $((9*1024*1024*2)) | sfdisk -q disk.img
dd if=super.img of=disk.img bs=1M seek=1 conv=notrunc,sparse status=none
rm -f super.img ut_data.raw

rm -f serial.log
timeout "${QEMU_TIMEOUT:-1500}" "$HOME/klee-ut/qemu/usr/bin/qemu-system-aarch64" \
	-M virt,gic-version=3 -cpu max,pauth-impdef=on -smp 8 -m 6144 -accel tcg,thread=multi \
	-kernel Image -initrd initrd.img \
	-append "console=ttyAMA0 earlycon datapart=/dev/mapper/ut_data printk.devkmsg=on androidboot.slot_suffix=_b androidboot.hardware=mt6899 firmware_class.path=/vendor/firmware loglevel=6" \
	-drive if=none,file=disk.img,format=raw,id=hd -device virtio-blk-pci,drive=hd \
	-nic none -display none -serial file:serial.log -monitor none || true
echo "QEMU finished"
