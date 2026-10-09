# Development notes (2026-10-07 → 2026-10-08)

Everything learned while testing on the device, in rough chronological order. Paths refer to
the developer's machine (`~/klee-ut/...`). Their counterparts in this repository are under
`port/`, `kernel/`, `host-tools/` and so on.

## Device

- Poco X8 Pro: codename `klee`, model 2511FPC34G, MediaTek mt6899, Android 16.
- A/B with Virtual A/B and dynamic partitions.
- `/data` is f2fs with metadata encryption, which Linux cannot read.
- Tested ROM: AxionAOSP v2.8 (Android 16 QPR2) with KernelSU Next in LKM mode (patched
  `init_boot`). Axion ships its own `boot` and `vendor_boot` images.
- **Super partition:** in practice only ~8.5 GiB is usable, not 12. Its metadata has 3 slots.
  The stock `parse-android-dynparts` only reads slot 0, so the port uses its own
  `ramdisk-overlay/sbin/lp-map`.
- **Boot command line:**
  - LK mangles the boot.img cmdline, so the ramdisk hardcodes `datapart=/dev/mapper/ut_data`.
  - LK passes `firmware_class.path=/vendor/firmware,/odm/firmware` and `kvm-arm.mode=protected`.
  - On a normal boot `/proc/bootconfig` contains `androidboot.force_normal_boot = "1"`. It is
    not on the cmdline.
- `expdb` (sdc4) holds the preloader/LK logs (RAM_CONSOLE, watchdog status).
- The bootloader is unlocked, but the ROM side (Fenrir) reports locked/green. Do not trust
  `ro.boot.verifiedbootstate`.

## Design

- **Base:** UBports `halium-gki` plus the `android15-6.6-halium` kernel, the same GKI generation
  as the stock 6.6.89-android15-8.
- **Rootfs:** UT 24.04-1.x on a Halium 14 GSI (CI artifact `devel-flashable-android14-6.1`).
- **`ut_data`:** a new logical partition in super's default group.
  - ext4 without `metadata_csum`/`orphan_file`, because the initrd's e2fsck is 1.43.
  - Holds `/ubuntu.img` (EROFS, ~1.24 GB) and the backups.
- **Switching OS:** replace the `boot` + `init_boot` images of the active slot.
- **Safety:**
  - `/metadata` is never mounted; the container sees an empty tmpfs.
  - The boot never falls back to `userdata`.
  - The boot stops if the data partition is not ext4.
  - The vendor `mount_all`/`swapon_all` commands are neutralised at runtime.

## Android 14 GSI ↔ Android 16 vendor compatibility

1. VINTF `meta-version="9.0"` → `8.0` (bind-mounted copies).
2. A no-op `AIBinder_Class_setTransactionCodeToFunctionNameMap` was added to the GSI's
   `libbinder_ndk.so`.
   - 49 vendor AIDL `-ndk` libraries need this symbol.
   - Patched with `host-tools/add_noop_syms.py`, without shifting any code (DT_HASH).
   - Shipped through `/usr/share/halium-overlay/system/lib64`.
3. `/vendor/apex` is hidden with a tmpfs. Its 9.0 VINTF fragments made the whole device
   manifest NULL.
4. Android 16's `vndservicemanager` aborts without an SELinux SID. The GSI's
   `/system/bin/servicemanager /dev/vndbinder` is used instead.
5. UBports `common.sh` bug: `build_partname_cache` clobbered the global `$partname`, so unknown
   labels resolved to the last block device. Fixed with private variables.
6. The vendor `libc++` is loaded through the halium-overlay (NODELETE). `libGLES_meow` needs it.
7. `mount_all --late` → `trigger nonencrypted`. Without this, `class_start main` never ran,
   PQ never started and the composer kept waiting.

## Offline verification

- **`host-tools/kmi_check.py`:** checked 592 modules across vendor_boot, vendor_dlkm, odm_dlkm
  and system_dlkm. There were 0 CRC mismatches, and a negative test confirmed the checker works.
- **`host-tools/abi_check.py`:** compared the vendor ELFs with the GSI libraries. The only missing
  symbol was the one above.
- **QEMU (`qemu-test/run.sh`):** lp-map → `ut_data` → `ubuntu.img` → Android container, with
  55 services registered.
- **`modload-loop.sh`:** loaded all 223 first-stage modules from Axion's vendor_boot.

## Problems solved on the device

### Reset after ~140 s
MediaTek MKP (kernel protection) resets the phone when it sees a PID above 32768
(`bootreason=RebootException`). systemd sets `pid_max=4194304`. The fix has two parts:
- the ramdisk runs `echo 32768 > /proc/sys/kernel/pid_max`
- `/etc/klee/50-pid-max.conf` is bind-mounted over the rootfs's `/usr/lib/sysctl.d/50-pid-max.conf`

`modprobe.d/klee-blacklist.conf` also blocks aee_hangdet, monitor_hang and mtk_heap_debug.

### Battery
The stock `mtk_battery_manager.ko` has a `usb_get_property` CRC mismatch: 0x8939cfe6 versus
charger_framework's 0xb4dcf409, with the same signature.
- **Effect:** the module did not load, so there was no `battery` power supply and the thermal HAL
  crashed.
- **Fix:** a copy with the corrected CRC lives in the ramdisk's `/lib/klee/` and is insmod'ed after
  the modprobe loop. The checker is `host-tools/crc_check_module.py`.
- The mismatch is internal to Axion's own vendor. The version in OrangeFox's vendor_boot does not
  have it.

### Display
- **`lomiri-system-compositor` failed with "mapper.mediatek.so not found".** Fix: add
  `/odm/lib64/hw:/vendor/lib64/hw:/vendor/lib64/egl` to `HYBRIS_LD_LIBRARY_PATH` (lsc-wrapper).
- **glibc `free(): invalid pointer`.** Bionic (scudo) memory was being passed to glibc's
  `free()`.
  - Fix: `shims/klee_free.c` (`libklee_free.so`, via LD_PRELOAD).
  - Built with AOSP clang `--target=aarch64-linux-gnu -nostdlib` against the sysroot's `libc.so.6`
    and `libhybris-common.so.1`.
- **Black screen.** Brightness reaches the panel only through
  `/sys/class/mi_display/disp-DSI-0/backlight` (DCS 0x51).
  - The `lcd-backlight` LED does not reach the panel.
  - The driver does not resend an unchanged value, and writes made before panel init finishes
    are lost.
  - Fix: `klee-brightness.service` alternates want-1/want for 3 s after every change.
- **AMOLED pitfall.** Black content looks exactly like a panel that is off.
- `mirscreencast` returns garbage on this GPU.
- **Waking the screen:** write a KEY_POWER (116) event to `/dev/input/event0`.
- **Punch hole.** The screen is 1268×2756 with a 78×102 px top-centre camera hole and a 190 px
  corner radius. The port uses a 120 px status bar, 64 px side margins and GridUnit 24
  (`rootfs-patches/lomiri-klee.sh`).

### Other
- **USB networking:** `usb-moded` is masked and replaced by `klee-usbnet` (NCM, `10.15.19.82`,
  `ssh -p 8022`).
  - On the host, run `nmcli dev set <if> managed no` and assign `10.15.19.1/24`.
  - The GKI kernel has no RNDIS.
- **Wi-Fi (NOT working):** writing `1` to `/dev/wmtWifi` brings up `wlan0` (`klee-wifi.service`),
  but Wi-Fi did not actually work in Ubuntu Touch. Not debugged yet.
- **Power key:** during boot it triggered a logind poweroff. Fix: `HandlePowerKey=ignore`.
- **Fastboot from Ubuntu Touch:** `systemctl reboot --reboot-argument=bootloader`.
- **Updating the rootfs without flashing:**
  1. Copy the new image to `/userdata/ubuntu.img.new`.
  2. Verify its sha256.
  3. `mv` it into place and reboot.
- **Live-testing tip:** `/run` is noexec. Mount a tmpfs with `-o exec` on `/run/kleebin` and
  bind-mount the modified script over the original.
- **Open issue:** hybris `getprop` aborts with "unregister_tls_module CHECK" (vendor libc++ PT_TLS).

## !!! The IMEI incident (CRITICAL)

After returning from Ubuntu Touch to Axion the IMEI was gone. The modem crashed on every boot
(md_state 5, NV_ASSERT LID 0xF00A `nvram_get_dev_boot_times`, `dev_fs_move FS -16 ACCESS_DENIED`).

- **Root cause:**
  - SELinux is off in Ubuntu Touch.
  - In the container, `ccci_fsd` and related services rewrote 17 files under `protect_s/md`
    plus `persist/data/7` **without labels** (`u:object_r:unlabeled:s0`).
  - Axion runs enforcing, so `avc denied unlink` (ccci_mdinit) followed and the modem crashed.
- **Manual fix:**
  - `chcon u:object_r:protect_s_data_file:s0` on protect_s/md/*
  - `chcon u:object_r:mitee_sfs_file:s0` on persist/data/7
  - then reboot

  `restorecon -R -F` did NOT work on these partitions. The IMEI files themselves were never
  damaged.
- **Diagnosis:**
  - `su -c "ls -laZR /mnt/vendor/{protect_f,protect_s,nvdata,nvcfg,persist,md_sec} | grep unlabeled"`
  - dmesg `md_state`
  - logcat avc
- **Permanent protection (both worked on the device):**
  - **Ubuntu Touch:** `klee-selinux-guard.service`
    - Every 10 s it scans `/proc/<lxc pid>/root/mnt/vendor/*`.
    - It gives each unlabeled file its parent directory's `security.selinux` xattr.
    - On shutdown it stops after the container and runs a final scan.
  - **Android:** the KernelSU module `klee_dualboot` (`port/android-side/ksu-module`)
    - It does the same with `chcon` in post-fs-data.
    - It uses full `/system/bin/...` paths, because ksud runs it with busybox.
    - Log: `/data/adb/klee-selinux-fix.log`.

## Boot partition write protection

The active slot's `boot`/`init_boot` cannot be written while Android **or** Ubuntu Touch is
running (UFS sense key 0x7 DATA PROTECT). Where it can be written:
- the inactive slot, at any time
- the active slot, from fastboot or OrangeFox recovery

Writing a boot partition with `dd` from inside Ubuntu Touch gave fsync EIO and once caused a BROM
loop. Only write boot images from fastboot.

## OrangeFox-based switching attempt (unfinished)

### Why the stock OrangeFox vendor_boot does not work
OrangeFox R12 for klee ("system-compatible") is flashed to `vendor_boot`. With the stock OF
vendor_boot, Ubuntu Touch does not boot: OF's platform fragment contains the whole recovery and
collides with Ubuntu Touch's halium ramdisk.

### Hybrid vendor_boot
- Axion's dtb, bootconfig, cmdline and platform fragment are kept unchanged.
- The recovery fragment is OF00 (minus the `.ko` files byte-identical to Axion's) + OF01,
  compressed with `lz4 -l`.
- An AVB footer is added with `avbtool add_hash_footer --partition_size 67108864`.
- Tool: `port/tools/make-hybrid-vendor-boot-ramdisk.py`.

**Lesson learned:** keep the directory entries when merging cpio archives, because the Linux
initramfs does not create missing parent directories. In v1:
- 17 files (e.g. `libmtk_bsg.so`) were not unpacked
- so the boot HAL crashed
- so OF sat on its splash screen, waiting for IBootControl

### Recovery-mode ramdisk clash
In recovery mode the ramdisk is the vendor fragments plus `init_boot` (the Ubuntu Touch halium
ramdisk). Ubuntu Touch's `/init`, `/bin` and `/etc` then override OF's.

Fix, at the top of `port/ramdisk-overlay/init`: if `/system/bin/recovery` exists and
`force_normal_boot=1` is absent:
1. move these to `/.klee-ut`
2. recreate the symlinks
3. `exec /init`

### SELinux vs AppArmor
The Ubuntu Touch kernel picks AppArmor, because it comes before selinux in CONFIG_LSM and the two
are exclusive. OF's init then cannot find selinuxfs.

Fix: `kernel/klee-kernel.patch` (`security/security.c`) uses `lsm=...selinux...` unless
`force_normal_boot=1` is set. Verified in QEMU.

### Switching flow
1. `android-side/klee-request-switch.sh` leaves an OpenRecoveryScript on the `rescue` partition
   (OF's /cache).
2. OF starts. After the PIN is entered, `klee-switch.sh` writes `boot`/`init_boot`.
3. The phone reboots to system.

### Last attempt
- **What happened:** while `klee-switch.sh ubuntu` was running inside OF, the phone rebooted by
  itself into a preloader↔BROM loop (on USB, `0e8d:2000` and `0e8d:0003` alternating).
- **Recovery:** Volume Down + Power into fastboot, then flash Axion's `boot`/`init_boot` and
  the stock OF `vendor_boot`.
- **Cause:** not found.

### OF fastbootd
OF's fastbootd rejects every command, including reboot, with "Unable to query battery data". Use
"Reboot to system" on the screen to get out.

So `fastboot delete-logical-partition ut_data` does not work from OF. The bootloader's fastbootd,
or `lpmake`/`lptools` from Android, may be needed.

## Uninstalling

Use `release/uninstall.sh`. A leftover `ut_data` is harmless; it takes ~3.2 GB of super. Before
touching the super metadata, back up the `lpdump` output and the first 8 MiB of super.

## Standalone install (added 2026-10-09, untested)

`release/install-standalone.sh` installs Ubuntu Touch in place of Android. The only change to the
port is in `port/ramdisk-overlay/scripts/halium` (`mountroot`): when `/dev/mapper/ut_data` does not
exist, the initramfs takes `/dev/disk/by-partlabel/userdata`. The existing ext4 check still
applies, so Android's metadata-encrypted userdata is never mounted or fsck'ed.

The installer builds a 4 GiB ext4 image (same feature set as `ut_data`, because the initrd's
e2fsck is 1.43) with `/ubuntu.img` at its root. It flashes the image as a sparse image to
`userdata` from bootloader fastboot. `resize_userdata_if_needed` then grows it to the whole
partition on the first boot.

Unknowns to check on a device:
- whether the Xiaomi LK fastboot accepts a sparse `userdata` flash
- that `resize2fs` in the initrd handles the large partition
- that nothing in the Android container expects Android's `/data` layout
