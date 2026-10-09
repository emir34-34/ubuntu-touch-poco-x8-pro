#!/bin/bash
set -ex

HERE=$(pwd)
source "${HERE}/deviceinfo"

deviceinfo_ubuntu_touch_release=${deviceinfo_ubuntu_touch_release:-24.04-2.x}

device=$1
output=$(realpath "$2")
dir=$(realpath "$3")
# "normal", "usrmerge", "overlaystore"
mode=${4:-normal}

echo "Working on device: $device; mode: $mode"
if [ ! -f "$dir/partitions/boot.img" ]; then
    echo "boot.img does not exist!"
    exit 1
elif [[ -d "$dir/system/opt/halium-overlay" && -d "$dir/system/usr/share/halium-overlay" ]]; then
    echo "both /usr/share/halium-overlay & /opt/halium-overlay cannot exist at the same time!"
    exit 1
fi

cp -av overlay/* "${dir}/"

if [ -e "${HERE}/${deviceinfo_ubuntu_touch_release}-overlay" ]; then
    cp -a ${HERE}/${deviceinfo_ubuntu_touch_release}-overlay/system/* $dir/system/
fi

INITRC_PATHS="
${dir}/system/opt/halium-overlay/system/etc/init
${dir}/system/usr/share/halium-overlay/system/etc/init
${dir}/system/opt/halium-overlay/vendor/etc/init
${dir}/system/usr/share/halium-overlay/vendor/etc/init
${dir}/system/android/system/etc/init
${dir}/system/android/vendor/etc/init
"
while IFS= read -r path ; do
    if [ -d "$path" ]; then
        find "$path" -type f -exec chmod 644 {} \;
    fi
done <<< "$INITRC_PATHS"

BUILDPROP_PATHS="
${dir}/system/opt/halium-overlay/system
${dir}/system/usr/share/halium-overlay/system
${dir}/system/opt/halium-overlay/vendor
${dir}/system/usr/share/halium-overlay/vendor
${dir}/system/android/system
${dir}/system/android/vendor
"
while IFS= read -r path ; do
    if [ -d "$path" ]; then
        find "$path" -type f \( -name "prop.halium" -o -name "build.prop" \) -exec chmod 600 {} \;
    fi
done <<< "$BUILDPROP_PATHS"

if [ "$mode" = "usrmerge" ]; then
    cd "$dir"
    # make sure udev rules and kernel modules are installed into /usr/lib
    # as /lib is symlink to /usr/lib on focal+
    # https://wiki.debian.org/UsrMerge
    if [ -d system/lib ]; then
        mkdir -p system/usr
        cp -a system/lib system/usr/ && rm -rf system/lib
    fi
elif [ "$mode" = "overlaystore" ]; then
    cd "$dir"
    # Expects everything under system/ to be configured properly for overlay store.
    # Use .opt to that * won't match it.
    mkdir -p system/.opt/halium-overlay/
    mv system/* system/.opt/halium-overlay/
    mv system/.opt system/opt
fi

output_name=device_"$device"

# Fix up permissions of / for classic snaps
chmod 755 "$dir/system"

tar -cJf "$output/$output_name.tar.xz" -C "$dir" \
    --owner=root --group=root \
    partitions/ system/
date --utc '+%Y%m%d-%H%M%SZ' > "$output/$output_name.tar.build"
