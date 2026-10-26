# Changelog

Everything that happened on this port, newest first. Times are Turkey time
(UTC+3). Times from 2026-10-17 on are when the result was seen on the phone;
earlier ones are commit times.

## 2026-10-26: ztOS listed, storage being grown to 64 GB

- **10:28** README rewritten for the current state of the port; this changelog added.
- **09:53** ztOS Supported Devices entry written and sent for review.
  Confirmed on the phone: mobile data, SMS, calls with the microphone, the
  ambient light sensor and the rear RGB light. GPS is broken for now.
- **~00:00** (in progress) ztOS storage from 16 GB to 64 GB. Done from HyperOS:
  the pinned file made longer (`ztos-pinfile grow`, new command; the first
  16 GB kept their place on the disk), the new extents map and the trailer at
  the new end written, a new `init_boot` built with the new map. Still to do:
  flash it, then grow the ext4 filesystem.

## 2026-10-25: Waydroid (Android 16) on the GPU, Flatpak apps

- **23:40** Flatpak installs failing: Bazaar's error was `min-free-space-size
  500MB would be exceeded`, a full `/userdata` (16 GB). Space freed; the
  leftover system installation removed, so only the user installation is used.
- **23:25** Flatpak apps draw on the Mali GPU: libhybris goes into the sandbox
  (`/opt/hybris-flatpak`, its EGL as the glvnd vendor) through a `flatpak`
  wrapper.
- **23:18** Bazaar (Flatpak) opens. `bwrap` could not `pivot_root` in the
  chroot (shared mount propagation). Each chroot entry now gets its own mount
  namespace with slave propagation.
- **23:03** Waydroid codecs: Waydroid's FFmpeg Codec2 decoders were hidden by
  the phone's MediaTek codec lists in `/vendor_extra`. Waydroid's own lists are
  now mounted over them in the container. Video decoders are listed (H.264,
  HEVC, VP9, AV1). YouTube still reports a player error.
- **22:36** Android's `mediaserver`/`drmserver` ran as 32-bit only (this CPU has
  no AArch32). Replaced by the 64-bit builds from Google's Android 16 QPR2 GSI,
  each with its own library set.
- **22:31** Closing the LineageOS window shuts Android down. Restarting ztMETRO
  stops a running Android.
- **22:23** LineageOS tile on Start: one tap boots Android and shows it from
  the boot animation to the home screen. Touch works.
- **22:12** Android visible on the screen: wlroots copied RGBX (no alpha) wlegl
  frames as RGBA, which GLES refuses, so they were black.
- **21:55** 64-bit audio HAL (from the LineageOS 20 arm64-only vendor, with a
  small libhidlbase shim). IR and NFC feature files removed from Android
  (no HAL for them: system_server crashed, NFC hung).
- **21:39** Android 16 boots (`sys.boot_completed=1`): the
  `android.hardware.graphics.composer` HAL chosen explicitly
  (`ro.hardware.hwcomposer=waydroid`; with the device name it allocated a
  2.8 GB framebuffer and the phone ran out of memory); service manager protocol
  `aidl6`.
- **17:49–17:55** Two lock-ups from running out of memory while testing
  Waydroid. Added: 4 GB zram swap, a memory ceiling for the container and a
  guard script for tests.
- **17:13** Waydroid image chosen: LineageOS 23.2 (Android 16 QPR2) GAPPS,
  arm64, with the phone's MediaTek allocator, `mapper.mediatek` and Mali GLES in
  the vendor overlay. SurfaceFlinger runs on the Mali-G720.
- **16:41** CPU and GPU checked. The CPU was capped at 2.0/2.5/2.7 GHz with a
  1.0 GHz floor: the vendor's boot tune, lifted only on
  `sys.boot_completed`, which Halium never sets. `klee-cpufreq` lifts it at
  boot; full 2.2/3.2/3.4 GHz now.
- **15:56** Long vibration after calls fixed (haptic effect uploaded again each
  time; the modem service closes the motor).
- **15:49** Media audio back on the loudspeaker after a call.
- **15:42** Volume banner: both levels draggable, keys repeat when held.
- **15:30** Loudspeaker crackle fixed for good: the droid card opened at
  48 kHz, default sink `sink.fast`.
- **15:02** Instagram app: infinite feed, videos play inline.
- **14:40** Native Metro Instagram app.
- **00:08** KleeToys (rear RGB light) ported to ztOS.

## 2026-10-24: ztOS apps, boot 83 s → 31 s

- **23:53** Now-playing card on the lock screen and in the control panel, with
  only the buttons the player supports.
- **23:44** Start tile sizes: small, medium, tall, wide, large, ultrawide, from
  a menu with previews. Tiles can be placed into gaps.
- **23:25** YouTube Music app: instant start, up next, Metro controls.
- **22:52** YouTube Music app (speed dial, search, library).
- **22:46** YouTube app: Google sign-in, feed, subscriptions, history.
- **22:37** YouTube app with mpv on the GPU, landscape button.
- **21:46** Boot time cut from 83 s to 31 s: the initrd's `klee-pinmap` read
  16 GB with `od -j` to check backup superblocks; now `dd skip | od`.
  New `init_boot_b` flashed with fastboot.

## 2026-10-21: ztOS everyday use

- **21:38** Firefox on the GPU, with sound.
- **21:01** Bluetooth pairing (Soundcore Q30) works.
- **20:38** Wi-Fi and Bluetooth settings for ztOS.
- **20:16** Display at 120 Hz, with a 60/120 Hz switch.
- **19:50** Lumia ringtones and a ringtone test button.
- **19:40** Vibration on touch.
- **19:30** Calls, call audio and app switching fixed after a regression.

## 2026-10-20: ztOS on the GPU, Lumia frame

- **18:25** Status bar fitted around the camera cut-out.
- **17:22** Media volume up to 150%.
- **16:44** Ringtones in ztOS.
- **16:37** SIM in ztOS.
- **16:00** Sound in ztOS.
- **15:46** Lumia 1020-style virtual frame, with colours and an on/off switch.
- **14:48** ztOS session usable (KDE Plasma Mobile trial archived).

## 2026-10-19: ztOS starts

- **23:06** Plasma Mobile tried in a chroot (later archived).
- **22:28** Persistent ztOS session, switchable to and from Lomiri.
- **22:26** ztMETRO on the Mali GPU through libhybris (wlroots 0.20 with a
  gralloc allocator).
- **21:55** ztOS (ztMETRO) first shown on the phone.

## 2026-10-18: Ubuntu Touch on HyperOS's side

- **23:38** Caffeine switch in the indicator panel.
- **23:21** Ear detection during calls (screen off from the ambient light
  sensor; the ultrasound proximity sensor is not supported) and automatic
  brightness.
- **22:51** Fingerprint unlock, with an icon over the sensor.
- **22:34** GPS fixes a position.
- **22:16** SMS received; headphones work.
- **22:15** Panel bar fitted around the camera.
- **21:51** KleeToys: rear RGB light app with effects that keep running.
- **17:00** Mobile data works.
- **16:52** Call audio on the loudspeaker; signal bars.
- **16:21** Calls work.
- **15:50** First Waydroid try removed (too slow at the time).
- **02:18** Flashlight.
- **02:06** Camera photos and flash.
- **01:55** Apps open again.
- **01:42** Volume control.
- **00:52** Sound.

## 2026-10-17: new install next to HyperOS

- **23:20** Wi-Fi connects.
- **23:10** Ubuntu Touch 24.04 boots on slot B, with HyperOS kept on slot A.
  Its data is a pinned file in HyperOS's userdata, mapped by the initrd
  (`klee-pinmap`), because the super partition is full.
- **21:30–22:45** Boot loops on slot B traced and fixed.
- **20:33** Plan: install on slot B, keep HyperOS on slot A.

## 2026-10-09: first public release (AxionAOSP dual boot)

- **17:23** Wi-Fi: cause found in the boot logs, `wifi-on` fixed.
- **16:56** License, troubleshooting guide, screenshots.
- **16:26** Disclaimer.
- **15:55** Standalone install script (untested).
- **15:04** Sources and notes published.

## 2026-10-07 → 2026-10-08: first port

Ubuntu Touch first brought up next to AxionAOSP (Android 16), with
`ut_data` in the super partition. See
[docs/DEVELOPMENT-NOTES.md](docs/DEVELOPMENT-NOTES.md) for that work,
including the IMEI incident.
