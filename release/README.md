# Poco X8 Pro (klee): Ubuntu Touch dual boot

Axion and your /data are **never wiped or formatted**. Ubuntu Touch is installed into a new
logical partition (`ut_data`) in the free space of the super partition. Switching between the two
systems only swaps the active slot's `boot` + `init_boot` images.

The images are not in this repository. Build them with `port/build-klee.sh`; it writes them to
`release/images/`.

## Contents

| File | Purpose |
|---|---|
| `images/ut_boot.img` | Ubuntu Touch kernel: UBports android15-6.6-halium GKI, same KMI as the phone's 6.6.89 |
| `images/ut_init_boot.img` | Halium initramfs + klee patches: slot-aware super mapping, safety checks |
| `images/ubuntu.img` | Ubuntu Touch 24.04-1.x rootfs (Halium 14) + klee overlay + 6.6 modules |
| `images/ut_boot_fastboot-boot.img` | For a one-off `fastboot boot` test without flashing |
| `install.sh` | Installer: takes backups, creates `ut_data`, writes the rootfs |
| `boot-ubuntu.sh` / `boot-axion.sh` | Switch systems from the computer |
| `device/to-ubuntu.sh` | Switch to Ubuntu from the phone (Axion, root) |
| `try-ubuntu-noflash.sh` | Experimental: tries to boot Ubuntu once without writing anything |
| `collect-logs.sh` | Debug logs |
| `uninstall.sh` | Removes Ubuntu Touch completely |

## Installation

Start with the phone running Axion and USB debugging enabled.

1. In the KernelSU manager, grant root to the **Shell** app.
2. Do a dry run first. It changes nothing on the phone; it only takes backups and prepares the image:
   ```
   ./install.sh --dry-run
   ```
3. Run the real installation:
   ```
   ./install.sh
   ```
   It backs up the phone, enters `fastbootd`, creates `ut_data`, flashes the images and returns
   to Axion.

   Backups are saved to `backup-<date>/`, and `backup-latest` points to the newest one.
   - **Do not delete this folder.** You need it to return to Axion.
   - The same backups are also copied into `ut_data`.

## Switching systems

- **To Ubuntu:** run `./boot-ubuntu.sh`. Or, on the phone in Axion as root:
  `su -c sh /sdcard/klee-ut/to-ubuntu.sh`.
- **Back to Axion:**
  1. From flashed Ubuntu Touch, enter the bootloader (fastboot):
     `systemctl reboot --reboot-argument=bootloader`, or hold **Volume Down + Power** if the
     phone does not boot.
  2. Run `./boot-axion.sh`.

  Do not use `klee-boot-android` (or `dd` from inside Ubuntu Touch): the active slot's boot
  partitions are write-protected there, and that path once caused a BROM loop.
- The bootloader (LK) is never touched, so fastboot is always reachable.
- `adb reboot fastboot` (fastbootd) does not work while Ubuntu is active. Use bootloader fastboot.

## First boot / debugging

- The first boot can take a few minutes, and the screen may stay on the logo.
- **No UI:** keep the USB cable plugged in. Ubuntu Touch "rescue mode" opens a USB network
  interface:
  ```
  ssh -p 8022 phablet@10.15.19.82
  ```
  No password is needed. Then run `./collect-logs.sh ubuntu`.
- **Failure in the initramfs stage:** the phone opens telnet over USB:
  ```
  telnet 192.168.2.15
  ```
- **Neither works:**
  1. Hold Volume Down + Power and run `./boot-axion.sh`.
  2. Once Axion is up, run `./collect-logs.sh android`. It reads the previous boot's kernel log
     from pstore.

## Safety measures (to protect Axion's data)

- Ubuntu Touch **never** touches `userdata`. If `datapart` is not found, the boot stops. It also
  stops if the partition is not ext4.
- `/metadata`, which holds Axion's encryption keys, is never mounted. The container sees an empty
  tmpfs.
- The vendor's `mount_all`/`swapon_all` commands are neutralised at runtime.

## Known risks / limitations

- A Halium 14 (Android 14) system runs on an Android 16 vendor. For compatibility:
  - a missing symbol was added to `libbinder_ndk.so`
  - VINTF 9.0 manifests are presented as 8.0

  On the device this worked through the UI and modem detection; Wi-Fi did not work. Other HALs are untested.
- Do not expect audio (AIDL audio HAL v2), camera, fingerprint or VoLTE to work on the first try.
  The goal was boot + display + touch + Wi-Fi first.

## Display settings (punch hole / status bar)

These values come from Axion's display configuration:
- screen 1268×2756
- camera hole at the top centre, 78×102 px
- corner radius 190 px

The port adjusts Lomiri to match:
- **Status bar:** 120 px. Lomiri's default of 72 px overlapped the camera hole.
- **Status bar icons:** 64 px margin on the left and right, so the rounded corners do not cut them off.
- **UI scale:** GridUnit 24 (`/etc/deviceinfo/devices/halium.yaml`).

To try other values on the phone (Ubuntu Touch terminal):
```
sudo mount -o remount,rw /
sudo nano /usr/share/lomiri/Shell.qml          # the 120 on the "klee: clear the punch-hole" line
sudo nano /usr/share/lomiri/Panel/PanelMenu.qml # leftMargin/rightMargin: 64
sudo nano /etc/deviceinfo/devices/halium.yaml   # GridUnit (bigger = everything bigger)
sudo mount -o remount,ro /
restart lomiri   # or reboot the phone
```
The permanent values are set at build time in `port/rootfs-patches/lomiri-klee.sh`.

## IMEI / SIM

- **Backup:** before Ubuntu boots for the first time, `install.sh` backs up the partitions that
  hold the IMEI and modem data (nvram, nvdata, nvcfg, protect1/2, md_sec, persist, proinfo) to
  `backup-<date>/imei/`. **Copy this folder somewhere else as well.**
- **Restore:** if the IMEI is ever lost, boot into the bootloader (fastboot) and run
  `fastboot flash nvdata nvdata.img`, and the same for the other partitions.
- **Read the IMEI incident in [../docs/DEVELOPMENT-NOTES.md](../docs/DEVELOPMENT-NOTES.md) first.**
  Losing the SELinux labels is the real danger, not the data itself.
- **SIM/calls:** Ubuntu Touch has ofono + binder RIL + the MTK plugin, but they are not guaranteed
  to work with the Android 16 RIL on the first try. Get boot and display working first, then the SIM.
