#!/bin/bash
set -ex

TMPDOWN=$1
INSTALL_MOD_PATH=$2
MENUCONFIG=$3
HERE=$(pwd)
source "${HERE}/deviceinfo"

KERNEL_DIR="${TMPDOWN}/$(basename "${deviceinfo_kernel_source}")"
KERNEL_DIR="${KERNEL_DIR%.git}"
OUT="${TMPDOWN}/KERNEL_OBJ"

mkdir -p "$OUT"

kernel_arch="${deviceinfo_kernel_arch:-$deviceinfo_arch}"

case "$kernel_arch" in
    aarch64) ARCH="arm64" ;;
    *) ARCH="$kernel_arch" ;;
esac

if [ -n "$deviceinfo_kernel_clang_compile" ] && $deviceinfo_kernel_clang_compile; then
    # Newer Android kernels no longer support setting CLANG_TRIPLE
    if grep -q CLANG_TRIPLE "$KERNEL_DIR/Makefile"; then
        : "${CLANG_TRIPLE:=${kernel_arch}-linux-gnu-}"
    else
        : "${CROSS_COMPILE:=${kernel_arch}-linux-gnu-}"
    fi
fi

: "${CROSS_COMPILE:=${kernel_arch}-linux-android-}"
export ARCH CLANG_TRIPLE CROSS_COMPILE

if [ "$ARCH" == "arm64" ]; then
    : "${CROSS_COMPILE_ARM32:=arm-linux-androideabi-}"
    export CROSS_COMPILE_ARM32
fi
MAKEOPTS=""
if [ -n "$CC" ]; then
    MAKEOPTS="CC=$CC"
fi
if [ -n "$LD" ]; then
    MAKEOPTS+=" LD=$LD"
fi
if [ -n "$deviceinfo_kernel_llvm_compile" ] && $deviceinfo_kernel_llvm_compile; then
    MAKEOPTS+=" LLVM=1 LLVM_IAS=1"
     # Have host compiler use LLD and compiler-rt.
    export HOSTLDFLAGS="-fuse-ld=lld --rtlib=compiler-rt"
fi

cd "$KERNEL_DIR"
make O="$OUT" $MAKEOPTS $deviceinfo_kernel_defconfig
if ${MENUCONFIG:-false}; then
    make O="$OUT" $MAKEOPTS menuconfig
fi
make O="$OUT" $MAKEOPTS -j$(nproc --all)
if [ "$deviceinfo_kernel_disable_modules" != "true" ]
then
    make O="$OUT" $MAKEOPTS INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH="$INSTALL_MOD_PATH" modules_install
fi
ls "$OUT/arch/$ARCH/boot/"*Image*

if [ -n "$deviceinfo_kernel_apply_overlay" ] && $deviceinfo_kernel_apply_overlay; then
    ${TMPDOWN}/ufdt_apply_overlay "$OUT/arch/arm64/boot/dts/qcom/${deviceinfo_kernel_appended_dtb}.dtb" \
        "$OUT/arch/arm64/boot/dts/qcom/${deviceinfo_kernel_dtb_overlay}.dtbo" \
        "$OUT/arch/arm64/boot/dts/qcom/${deviceinfo_kernel_dtb_overlay}-merged.dtb"
    cat "$OUT/arch/$ARCH/boot/Image.gz" \
        "$OUT/arch/arm64/boot/dts/qcom/${deviceinfo_kernel_dtb_overlay}-merged.dtb" > "$OUT/arch/$ARCH/boot/Image.gz-dtb"
fi

if [ -n "$deviceinfo_use_overlaystore" ]; then
    # Config this directory in the overlay store to override (i.e. bind-mount)
    # the whole directory. Rootfs won't ship any device-specific kernel module.
    touch "${INSTALL_MOD_PATH}/lib/modules/.halium-override-dir"
fi
