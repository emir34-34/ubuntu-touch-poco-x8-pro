# If something goes wrong

Everything below was hit on a real Poco X8 Pro during development. The bootloader (LK) is never
modified by this port, so **fastboot is always reachable**. Keep calm, keep your backups at
hand, and do not flash random partitions.

Before anything else: **hold Volume Down + Power** until the phone shows the fastboot screen.
That works from almost every state described here.

## The phone is in a boot loop and the screen stays black

**Symptom:** the screen stays black, the phone keeps restarting, and on the computer the USB
device appears and disappears every few seconds as `0e8d:2000` (MediaTek Preloader) and
`0e8d:0003` (BROM). Check with `lsusb` on Linux.

**Cause:** a boot image that does not work with the current `vendor_boot`, or a boot partition
written badly (e.g. with `dd` from inside a running system).

**Fix:**
1. Hold **Volume Down + Power** until the fastboot screen appears. Keep holding through the
   reboots; it can take 10–20 seconds.
2. Write Android's boot images back from your backup, for the active slot:
   ```
   fastboot getvar current-slot
   fastboot flash boot_b    backup-<date>/boot.img
   fastboot flash init_boot_b backup-<date>/init_boot.img
   ```
   (Use `_a` instead of `_b` if that is the active slot.)
3. If you changed `vendor_boot` (for example for OrangeFox), write that back too:
   `fastboot flash vendor_boot_b backup-<date>/vendor_boot.img`.
4. `fastboot reboot`.

`release/boot-axion.sh` does steps 2 and 4 for you.

## Android starts, but there is no IMEI / no signal

**Symptom:** after using Ubuntu Touch, Android shows no IMEI. In the logs the modem crashes on
every boot (`md_state 5`, `NV_ASSERT`, `ACCESS_DENIED`).

**Cause:** Ubuntu Touch runs without SELinux. The modem services in its Android container
rewrite files in `/mnt/vendor/protect_s` and `/mnt/vendor/persist` without SELinux labels.
Android runs enforcing, so it refuses to touch them and the modem crashes. The IMEI data itself
is normally **not** damaged.

**Fix:**
1. Install the KernelSU module `klee-dualboot-ksu-module.zip` (from Releases) and reboot. It
   restores the labels at every boot. Its log is `/data/adb/klee-selinux-fix.log`.
2. Or fix it by hand as root:
   ```
   ls -laZR /mnt/vendor/{protect_f,protect_s,nvdata,nvcfg,persist,md_sec} | grep unlabeled
   chcon u:object_r:protect_s_data_file:s0 /mnt/vendor/protect_s/md/*
   chcon u:object_r:mitee_sfs_file:s0 /mnt/vendor/persist/data/7
   reboot
   ```
   `restorecon -R -F` does **not** work on these partitions.
3. Only if the IMEI files themselves are damaged: restore the backup made by the installer
   (`backup-<date>/imei/`) from bootloader fastboot, e.g. `fastboot flash nvdata nvdata.img`.

## OrangeFox hangs on its splash screen

**Cause:** a `vendor_boot` whose recovery ramdisk is missing files. The boot HAL then fails and
OrangeFox waits forever for it. In this project, a broken hybrid image (cpio merge without
directory entries) caused this.

**Fix:** Volume Down + Power → fastboot → flash a known-good `vendor_boot` (your backup, or the
stock OrangeFox image) → reboot.

## OrangeFox's fastbootd refuses every command

**Symptom:** every command, even `fastboot reboot`, fails with
`Unable to query battery data`.

**Fix:** use **Reboot → System** (or Bootloader) on the phone's screen. Use the bootloader's
fastboot (Volume Down + Power) for flashing.

## Ubuntu Touch boots but the screen stays black

- It is an AMOLED panel: a black UI looks exactly like a panel that is off. Touch the screen,
  or press the power key once.
- The brightness only reaches the panel through `/sys/class/mi_display/disp-DSI-0/backlight`.
  `klee-brightness.service` handles this; check that it is running.
- Connect over USB and look at the logs:
  `ssh -p 8022 root@10.15.19.82` (your key in `/etc/klee/authorized_keys`), then
  `journalctl -b`. Or run `release/collect-logs.sh ubuntu`.

## The phone resets about 140 seconds after Ubuntu Touch boots

**Cause:** MediaTek's kernel protection (MKP) resets the phone as soon as it sees a process ID
above 32768, and systemd raises `pid_max`. The port's initramfs and rootfs keep `pid_max` at
32768. If you build your own rootfs, keep `/etc/klee/50-pid-max.conf` bind-mounted over
`/usr/lib/sysctl.d/50-pid-max.conf`.

## Getting back to Android completely

- **Dual boot:** `release/uninstall.sh` (writes the Android boot images back and deletes
  `ut_data`). A leftover `ut_data` partition is harmless.
- **Standalone:** `release/restore-android.sh backup-standalone-<date>`, then **Format Data** in
  the recovery.
- **No backups at all:** flash your ROM's own `boot.img`, `init_boot.img` and `vendor_boot.img`
  (from the ROM zip / payload, `host-tools/payload_extract.py` can extract them) from
  bootloader fastboot.
