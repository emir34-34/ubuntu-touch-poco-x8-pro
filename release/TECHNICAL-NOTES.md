# klee Ubuntu Touch port: technical notes

These are the notes written before the first on-device boot. For everything learned on the
device afterwards, see [../docs/DEVELOPMENT-NOTES.md](../docs/DEVELOPMENT-NOTES.md).

## Sources
- **Port:** `port/`, from the UBports `halium-gki` template.
  - Build: `port/build-klee.sh`, with `SKIP_KERNEL=1` and `SKIP_ROOTFS=1` options.
  - The build directory path must not contain spaces.
- **Kernel:** `gitlab.com/ubports/.../kernel-android-common`, branch `android15-6.6-halium`
  (6.6.138).
  - `mali_kbase_mt6899_r49` was added to `gki_quirks.c` (see `kernel/klee-kernel.patch`).
  - Compiler: AOSP clang r510928, the same as the stock kernel.
- **Rootfs:** UBports CI `halium-gki` → `devel-flashable-android14-6.1` (UT 24.04-1.x, Halium 14 GSI).

## Verified without the device
- **`host-tools/kmi_check.py`:** checked 592 modules from vendor_boot, vendor_dlkm, odm_dlkm and
  system_dlkm against our `Module.symvers`. There were **0 kernel symbol CRC mismatches**, and a
  negative test confirmed the checker works.
- **`host-tools/abi_check.py`:** scanned the vendor ELFs against the GSI system libraries.
  - The only missing symbol was `AIBinder_Class_setTransactionCodeToFunctionNameMap`, needed by
    49 AIDL interface libraries.
  - `host-tools/add_noop_syms.py` added it to the GSI `libbinder_ndk.so`, without shifting code
    (DT_HASH).
- **QEMU** (aarch64 virt, our kernel + our init_boot ramdisk):
  - The chain lp-map → `ut_data` → `ubuntu.img` → Android GSI → systemd ran and printed
    "Welcome to Ubuntu 24.04.5 LTS".
  - `mount-android-partitions` succeeded with the real Axion vendor/odm/dlkm partitions.
- **QEMU round 2 (`qemu-test/run.sh`):** the Android container runs with **55 services
  registered** (allocator, health, power, sensors, vibrator, wifi, bluetooth, audio core, NFC,
  GNSS, memtrack...). The composer crashes in QEMU because there is no MTK hardware, as expected.
- **QEMU real-module test (`qemu-test/modload-loop.sh`):**
  - All 223 first-stage modules from Axion's vendor_boot loaded into our kernel with the Halium
    initramfs.
  - There were 0 kernel-caused symbol or version errors.
  - `log_store` and `aee_hangdet` crash in QEMU without MTK hardware, so the test skips them.
  - The only "disagrees about version" is `mtk_battery_manager` ↔ `mtk_charger_framework`
    (`usb_get_property`). This is an internal mismatch in Xiaomi/Axion's vendor, also present on
    the stock kernel. It can be checked on Axion with `dmesg | grep disagrees`.

## Android 14 GSI ↔ Android 16 vendor compatibility patches
1. VINTF manifests `version="9.0"` → `8.0`. The GSI's libvintf recognises at most 8.0.
2. A no-op `AIBinder_Class_setTransactionCodeToFunctionNameMap` in `libbinder_ndk.so`.
3. The vendor `mount_all`/`swapon_all` are neutralised, and `/metadata` is an empty tmpfs.
4. `/vendor/apex` is hidden (boot/cas/widevine). The 9.0 VINTF inside it dropped the whole device
   manifest.
5. vndbinder: Android 16's `vndservicemanager` aborts without an SELinux context, so the GSI's
   `/system/bin/servicemanager /dev/vndbinder` is used.
6. A UBports `common.sh` bug was fixed: `build_partname_cache` clobbered the global `partname`,
   so unknown labels resolved to the last block device.

## Important device facts
- **Super:** the active slot is `_b`. Super uses VAB and its metadata has 3 slots.
  `parse-android-dynparts` reads only slot 0, so the port uses its own `lp-map`.
- **`/data`:** f2fs with metadata encryption (`/metadata/vold/metadata_encryption`), which Linux
  cannot read.
- **Firmware path:** the LK cmdline passes `firmware_class.path=/vendor/firmware,/odm/firmware`.
- **Wi-Fi:** writing `1` to `/dev/wmtWifi` brings up `wlan0` (`klee-wifi.service`). On the real
  device Wi-Fi still did not work (see the development notes).
- **USB networking:** the GKI kernel has no RNDIS but has NCM. usb-moded and the initrd telnet
  fall back to NCM.

## Known open points
- `leds-mtk-disp.ko` wants an unresolvable symbol (`mtk_drm_gateic_set_backlight`). The same
  happens on stock Axion.
- Audio: the vendor has AIDL audio core v2. Ubuntu Touch's pulseaudio-droid path is untested.
