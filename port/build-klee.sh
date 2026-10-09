#!/bin/bash
# Build everything for the klee Ubuntu Touch dual boot:
#   release/images/ut_boot.img       halium GKI kernel (android15-6.6-halium)
#   release/images/ut_init_boot.img  halium initramfs + klee ramdisk overlay
#   release/images/ubuntu.img        UT 24.04-1.x rootfs + klee overlay + 6.6 modules
#
# Needs: sudo (loop-mounting ubuntu.img), the kernel tree in ~/klee-ut (no spaces).
set -euo pipefail

PORT="$(cd "$(dirname "$0")" && pwd -P)"
TOP="$HOME/poco x8 pro ub touch"
KSRC="$HOME/klee-ut/kernel"
KOUT="$HOME/klee-ut/kout"
CLANG="$HOME/klee-ut/toolchain/clang-r510928/bin"
REL="$TOP/release/images"
BASE_ROOTFS="$TOP/downloads/out/ubuntu.img"
WORK="$HOME/klee-ut/work"
DL="$PORT/workdir/downloads"
SUDO="${SUDO:-sudo}"

mkdir -p "$REL" "$WORK" "$DL"
export PATH="$CLANG:$PATH"
KMAKE=(make -C "$KSRC" O="$KOUT" ARCH=arm64 LLVM=1 LLVM_IAS=1)

step() { printf '\n\033[1;34m### %s\033[0m\n' "$*"; }

step "kernel"
if [ "${SKIP_KERNEL:-}" != 1 ]; then
	cp "$PORT/klee.config" "$KSRC/arch/arm64/configs/klee.config"
	"${KMAKE[@]}" gki_defconfig halium.config klee.config >/dev/null
	"${KMAKE[@]}" -j"$(nproc)" Image modules
fi
KREL=$(cat "$KOUT/include/config/kernel.release")
echo "kernel release: $KREL"

step "modules_install"
rm -rf "$WORK/modroot"
"${KMAKE[@]}" INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH="$WORK/modroot" modules_install >/dev/null
rm -f "$WORK/modroot/lib/modules/$KREL/build" "$WORK/modroot/lib/modules/$KREL/source"

step "boot images"
[ -f "$DL/halium-boot-ramdisk.img" ] || curl -sL -o "$DL/halium-boot-ramdisk.img" \
	https://github.com/halium/initramfs-tools-halium/releases/download/dynparts/initrd.img-touch-arm64
[ -d "$DL/avb" ] || git clone -q --depth 1 -b android13-gsi https://android.googlesource.com/platform/external/avb "$DL/avb"
[ -d "$DL/android_system_tools_mkbootimg" ] || git clone -q --depth 1 -b lineage-20.0 \
	https://github.com/LineageOS/android_system_tools_mkbootimg "$DL/android_system_tools_mkbootimg"
rm -rf "$DL/KERNEL_OBJ"
ln -s "$KOUT" "$DL/KERNEL_OBJ"
rm -rf "$PORT/workdir/tmp"; mkdir -p "$PORT/workdir/tmp/partitions"
(
	cd "$PORT"
	deviceinfo_kernel_image_name="Image.lz4" ./build/make-bootimage.sh "$DL" "$DL/KERNEL_OBJ" \
		"$DL/halium-boot-ramdisk.img" "$PORT/workdir/tmp/partitions/boot.img" "$WORK/modroot"
)
cp "$PORT/workdir/tmp/partitions/boot.img" "$REL/ut_boot.img"
cp "$PORT/workdir/tmp/partitions/init_boot.img" "$REL/ut_init_boot.img"

# Single image (kernel + ramdisk) for a no-flash "fastboot boot" attempt
source "$PORT/deviceinfo"
python3 "$DL/android_system_tools_mkbootimg/mkbootimg.py" --header_version 4 \
	--kernel "$KOUT/arch/arm64/boot/Image.lz4" \
	--ramdisk "$DL/halium-boot-ramdisk.img.lz4-merged" \
	--cmdline "$deviceinfo_kernel_cmdline" \
	--os_version "$deviceinfo_bootimg_os_version" --os_patch_level "$deviceinfo_bootimg_os_patch_level" \
	-o "$REL/ut_boot_fastboot-boot.img"

step "rootfs"
if [ "${SKIP_ROOTFS:-}" != 1 ]; then
	cp --sparse=always "$BASE_ROOTFS" "$WORK/ubuntu.img"
	MNT="$WORK/mnt"; mkdir -p "$MNT"
	$SUDO mount -o loop "$WORK/ubuntu.img" "$MNT"
	trap '$SUDO umount "$MNT" 2>/dev/null || true' EXIT
	# replace the generic 6.1 GKI modules with ours
	$SUDO rm -rf "$MNT"/usr/lib/modules/*
	$SUDO cp -a "$WORK/modroot/lib/modules/$KREL" "$MNT/usr/lib/modules/"
	$SUDO chown -R root:root "$MNT/usr/lib/modules"
	$SUDO depmod -b "$MNT" "$KREL"
	# device overlay (same layout as the halium device tarball "system/")
	$SUDO cp -a --no-preserve=ownership "$PORT/overlay/system/." "$MNT/"
	$SUDO chown -R root:root "$MNT/usr/libexec/lxc-android-config" "$MNT/usr/bin/klee-"* "$MNT/etc/deviceinfo"
	# rootfs patches (Lomiri status bar / punch-hole / rounded corners, ...)
	for p in "$PORT"/rootfs-patches/*.sh; do $SUDO bash "$p" "$MNT"; done
	echo "klee $(date -u +%Y%m%d-%H%M)" | $SUDO tee "$MNT/etc/klee-port-version" >/dev/null
	sync
	$SUDO umount "$MNT"; trap - EXIT
	e2fsck -fy "$WORK/ubuntu.img" >/dev/null || true
	# klee: ship the rootfs as compressed EROFS (3.5 GiB ext4 -> ~1.2 GiB) so it
	# fits, together with user data, into the ~3 GiB of free space in super.
	$SUDO mount -o loop,ro "$WORK/ubuntu.img" "$MNT"
	trap '$SUDO umount "$MNT" 2>/dev/null || true' EXIT
	rm -f "$WORK/ubuntu.erofs"
	$SUDO mkfs.erofs -zlz4hc,12 -E ztailpacking -C 65536 "$WORK/ubuntu.erofs" "$MNT" >/dev/null
	$SUDO umount "$MNT"; trap - EXIT
	$SUDO chown "$(id -u):$(id -g)" "$WORK/ubuntu.erofs"
	cp "$WORK/ubuntu.erofs" "$REL/ubuntu.img"
fi

step "done"
ls -la "$REL"
