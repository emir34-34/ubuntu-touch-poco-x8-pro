#!/bin/bash
# QEMU safety tests for the klee dual boot.
#   A: no ut_data in super  -> initramfs must stop, "userdata" must be untouched
#   B: normal boot, then `klee-boot-android` -> boot_b/init_boot_b get the
#      Android backups from ut_data, "userdata" must be untouched
set -euo pipefail
Q="$(cd "$(dirname "$0")" && pwd)"
A="$HOME/poco x8 pro ub touch/axion_imgs"
REL="$HOME/poco x8 pro ub touch/release/images"
SC=${1:?A or B}
cd "$Q"
export SUDO_ASKPASS=${SUDO_ASKPASS:?}
W=safety-$SC; mkdir -p $W

rm -rf ib; mkdir ib
unpack_bootimg --boot_img "$REL/ut_init_boot.img" --out ib >/dev/null
cat vendor_ramdisk.lz4 ib/ramdisk > initrd.img
cp "$HOME/klee-ut/kout/arch/arm64/boot/Image" Image

# fake Android images (the ones install.sh would back up)
cp "$HOME/Desktop/axion/boot.img" $W/android_boot.img
cp "$A/init_boot.img" $W/android_init_boot.img
# fake metadata-encrypted userdata: random bytes
head -c $((64*1024*1024)) /dev/urandom > $W/userdata.raw
sha256sum $W/userdata.raw | cut -d' ' -f1 > $W/userdata.sha

SUPER_ARGS=()
for p in vendor odm vendor_dlkm system_dlkm odm_dlkm; do
	s=$(( ($(stat -L -c %s "$A/$p.img") + 1048575) / 1048576 * 1048576 ))
	SUPER_ARGS+=(--partition "${p}_b:readonly:$s:main_b" --image "${p}_b=$A/$p.img")
done

if [ "$SC" = B ]; then
	cp --sparse=always "$REL/ubuntu.img" $W/ubuntu-test.img
	mkdir -p m
	sudo -A mount -o loop $W/ubuntu-test.img m
	sudo -A install -m 755 klee-qtest-safety m/usr/local/bin/klee-qtest
	sudo -A install -m 644 klee-qtest.service m/etc/systemd/system/klee-qtest.service
	sudo -A ln -sf /etc/systemd/system/klee-qtest.service m/etc/systemd/system/multi-user.target.wants/klee-qtest.service
	sudo -A umount m
	rm -f $W/ut_data.raw; truncate -s 4608M $W/ut_data.raw
	mkfs.ext4 -q -F -L ut_data -b 4096 -m 0 -O ^metadata_csum,^metadata_csum_seed,^orphan_file $W/ut_data.raw
	printf '_b\n' > $W/slot
	cp "$REL/ut_boot.img" $W/ut_boot.img; cp "$REL/ut_init_boot.img" $W/ut_init_boot.img
	{
		echo "write $Q/$W/ubuntu-test.img ubuntu.img"
		echo "mkdir klee-dualboot"
		for f in android_boot.img android_init_boot.img ut_boot.img ut_init_boot.img slot; do
			echo "write $Q/$W/$f klee-dualboot/$f"
		done
	} | debugfs -w -f - $W/ut_data.raw >/dev/null 2>&1
	SUPER_ARGS+=(--partition ut_data:none:$((4608*1024*1024)) --image ut_data=$W/ut_data.raw)
fi

rm -f $W/super.img $W/disk.img
lpmake --metadata-size 65536 --super-name super --metadata-slots 3 --device super:$((9*1024*1024*1024)) \
	--group main_b:$((4*1024*1024*1024)) "${SUPER_ARGS[@]}" --output $W/super.img >/dev/null 2>&1

# GPT: super, userdata, boot_b, init_boot_b (UT images flashed, as after boot-ubuntu.sh)
SUPER_S=$((9*1024*1024*2)); UD_S=$((64*1024*2)); BOOT_S=$((64*1024*2)); IB_S=$((8*1024*2))
truncate -s $((9*1024 + 64 + 64 + 8 + 4))M $W/disk.img
cat <<EOF | sfdisk -q $W/disk.img
label: gpt
start=2048, size=$SUPER_S, name=super
size=$UD_S, name=userdata
size=$BOOT_S, name=boot_b
size=$IB_S, name=init_boot_b
EOF
off() { sfdisk -J $W/disk.img | python3 -c "import json,sys;print(json.load(sys.stdin)['partitiontable']['partitions'][$1]['start'])"; }
dd if=$W/super.img of=$W/disk.img bs=512 seek=$(off 0) conv=notrunc,sparse status=none
dd if=$W/userdata.raw of=$W/disk.img bs=512 seek=$(off 1) conv=notrunc status=none
dd if="$REL/ut_boot.img" of=$W/disk.img bs=512 seek=$(off 2) conv=notrunc status=none
dd if="$REL/ut_init_boot.img" of=$W/disk.img bs=512 seek=$(off 3) conv=notrunc status=none
rm -f $W/super.img $W/ut_data.raw
echo "$(off 1) $(off 2) $(off 3)" > $W/offsets

rm -f $W/serial.log
timeout "${QEMU_TIMEOUT:-1500}" "$HOME/klee-ut/qemu/usr/bin/qemu-system-aarch64" \
	-M virt,gic-version=3 -cpu max,pauth-impdef=on -smp 8 -m 6144 -accel tcg,thread=multi -no-reboot \
	-kernel Image -initrd initrd.img \
	-append "console=ttyAMA0 earlycon datapart=/dev/mapper/ut_data printk.devkmsg=on androidboot.slot_suffix=_b androidboot.hardware=mt6899 firmware_class.path=/vendor/firmware loglevel=6" \
	-drive if=none,file=$W/disk.img,format=raw,id=hd -device virtio-blk-pci,drive=hd \
	-nic none -display none -serial file:$W/serial.log -monitor none || true

# verify
read UDO BO IBO < $W/offsets
dd if=$W/disk.img bs=512 skip=$UDO count=$UD_S status=none | sha256sum | cut -d' ' -f1 > $W/userdata.after
if cmp -s $W/userdata.sha $W/userdata.after; then echo "RESULT userdata: UNTOUCHED"; else echo "RESULT userdata: MODIFIED!!!"; fi
dd if=$W/disk.img bs=512 skip=$BO count=$BOOT_S status=none | cmp -s - $W/android_boot.img && echo "RESULT boot_b: android" || echo "RESULT boot_b: not android"
dd if=$W/disk.img bs=512 skip=$IBO count=$IB_S status=none | cmp -s - $W/android_init_boot.img && echo "RESULT init_boot_b: android" || echo "RESULT init_boot_b: not android"
grep -a 'initrd: PANIC' $W/serial.log | head -2 || true
echo "QEMU finished"
