#!/bin/bash
set -ex

TMPDOWN=$(realpath $1)
KERNEL_OBJ=$(realpath $2)
OUT=$(realpath $3)

HERE=$(pwd)
source "${HERE}/deviceinfo"

kernel_arch="${deviceinfo_kernel_arch:-$deviceinfo_arch}"

case "$kernel_arch" in
    aarch64) ARCH="arm64" ;;
    *) ARCH="$kernel_arch" ;;
esac

if [ -z "$deviceinfo_dtbo" ]; then
    echo "Please define deviceinfo_dtbo in deviceinfo"
    exit 1
fi

PREFIX=$KERNEL_OBJ/arch/$ARCH/boot/dts/

IFS=" " read -r -a DTBOS <<< "$deviceinfo_dtbo"
IFS=" " read -r -a IDS <<< "$deviceinfo_dtbo_ids"
DTBO_ARGS=""

i=0
for dtbo in "${DTBOS[@]}"; do
    if [ -n "${IDS[i]}" ]; then
        DTBO_ARGS="$DTBO_ARGS --id=${IDS[i]}"
    fi
    DTBO_ARGS="$DTBO_ARGS $PREFIX${dtbo// / $PREFIX}"
    i=$((i + 1))
done

python2 "$TMPDOWN/libufdt/utils/src/mkdtboimg.py" create "$OUT" $DTBO_ARGS
