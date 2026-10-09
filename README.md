# Ubuntu Touch — Poco X8 Pro (klee, MT6899)

Xiaomi Poco X8 Pro (kod adı `klee`, model 2511FPC34G, MediaTek Dimensity / mt6899) için
deneysel Ubuntu Touch portu. Android ROM (AxionAOSP, Android 16) ile **dual boot** olarak
tasarlandı: `/data` silinmiyor, Ubuntu Touch super bölümündeki boş alanda açılan yeni bir
mantıksal bölümde (`ut_data`) duruyor.

> **Durum: ilk yazar tarafından bırakıldı (2026-10-08).** Kod, betikler ve tüm notlar
> başkaları devam edebilsin diye burada. Pull request ve fork'lar memnuniyetle karşılanır.

*English summary: experimental Ubuntu Touch (UBports halium-gki, Halium 14 GSI rootfs,
android15-6.6-halium kernel) port for the Poco X8 Pro (klee). It boots to the Lomiri UI on
real hardware with display, touch, Wi-Fi and modem detection. Dual-boot switching and the
OrangeFox-based switcher were not finished. The original author stopped working on it; all
sources and notes are here so others can continue. Docs are in Turkish; read
[docs/GELISTIRME-NOTLARI.md](docs/GELISTIRME-NOTLARI.md) for the hard-won device details,
**especially the IMEI/SELinux section before booting anything**.*

## Gerçek cihazda ne çalıştı

| Parça | Durum |
|---|---|
| Çekirdek (UBports `android15-6.6-halium`, 6.6.x GKI) + vendor modülleri | ✅ 592 modülde 0 KMI CRC uyumsuzluğu |
| Halium 14 GSI konteyneri, Android 16 vendor ile | ✅ uyumluluk yamalarıyla |
| Ekran (composer3), Lomiri arayüzü, parlaklık | ✅ (bkz. notlar: free() shim, `mi_display` backlight) |
| Dokunmatik | ✅ |
| Wi-Fi | ✅ (`/dev/wmtWifi`) |
| Modem / SIM algılama | ✅ ICCID okundu; arama/veri test edilmedi |
| Pil (`mtk_battery_manager` CRC yaması) | ✅ |
| ~140 sn'de reset (MediaTek MKP, pid_max) | ✅ çözüldü |
| Ses, kamera, parmak izi, VoLTE | ❌ denenmedi |
| Bilgisayarsız OS geçişi (OrangeFox üzerinden) | ❌ yarım; telefon BROM döngüsüne girdi |

## ⚠️ Başlamadan önce okuyun

1. **IMEI riski:** UT'de SELinux kapalı. Android konteynerindeki modem servisleri
   `protect_s`/`persist` içindeki dosyaları **etiketsiz** yeniden yazıyor; Android'e dönünce
   modem çöküyor ve IMEI görünmüyor. Koruma iki katmanlı:
   `port/overlay/.../klee-selinux-guard` (UT tarafı) ve `port/android-side/ksu-module`
   (Android tarafı, KernelSU post-fs-data). İkisi olmadan UT'yi açmayın. Ayrıntılar notlarda.
2. **IMEI/NVRAM bölümlerini yedekleyin** (`release/install.sh` bunu yapıyor:
   nvram, nvdata, nvcfg, protect1/2, md_sec, persist, proinfo).
3. Android açıkken **aktif slotun boot/init_boot bölümleri donanımsal yazma korumalı**
   (UFS DATA PROTECT). Boot imajları yalnızca fastboot veya recovery'den yazılabiliyor.
4. Bootloader (LK) hiç değiştirilmiyor; **Ses Kısma + Güç** ile her zaman fastboot'a girilebilir.
   Her şey bozulursa oradan Android'in boot/init_boot/vendor_boot imajlarını geri yazın.

## Depo düzeni

| Klasör | İçerik |
|---|---|
| `port/` | Asıl port (UBports `halium-gki` şablonundan): `build-klee.sh`, `deviceinfo`, `klee.config`, `ramdisk-overlay/` (initramfs yamaları, slot farkındalıklı `sbin/lp-map`), `overlay/` (rootfs'a eklenen dosyalar, servisler), `rootfs-patches/`, `android-side/` (Android/OrangeFox tarafı betikler + KernelSU modülü), `tools/make-hybrid-vendor-boot-ramdisk.py` |
| `kernel/` | UBports `kernel-android-common` (`android15-6.6-halium`) üzerine yama (`klee-kernel.patch`), `klee.config`, taban commit (`BASE_COMMIT`) |
| `shims/` | glibc↔bionic köprüleri (`klee_free.c`: bionic belleğinin glibc `free()`'ye gitmesi; GL/pencere hata ayıklama shim'leri) |
| `host-tools/` | Bilgisayar tarafı doğrulama araçları: `kmi_check.py`, `abi_check.py`, `add_noop_syms.py`, `crc_check_module.py`, `payload_extract.py` vb. |
| `qemu-test/` | Gerçek çekirdek + initramfs + rootfs + Axion vendor bölümleriyle QEMU entegrasyon testi |
| `apps/android-reboot-ubuntu/` | Android'den "Ubuntu'ya Geç" uygulaması (gradle'sız `build.sh`) |
| `release/` | Kullanıcı betikleri: `install.sh`, `boot-ubuntu.sh`, `boot-axion.sh`, `uninstall.sh`, `collect-logs.sh`, `BENIOKU.md`, `TEKNIK-NOTLAR.md` |
| `docs/` | **`GELISTIRME-NOTLARI.md`** — cihaz üzerinde öğrenilen her şey, kronolojik |

Derlenmiş imajlar (`ut_boot.img`, `ut_init_boot.img`, `ubuntu.img`) bu depoda **yok**:
boyutları büyük ve içlerinde geliştiricinin SSH anahtarı vardı. Kaynaktan derleyin.

## Derleme (özet)

Gerekenler: Linux, AOSP clang `r510928` (stok çekirdekle aynı), `sudo` (loop mount),
`lz4`, `mkbootimg`/`avbtool` (betik indiriyor), UBports CI'dan Halium 14 rootfs
(`halium-gki` → `devel-flashable-android14-6.1`).

```sh
# çekirdek
git clone -b android15-6.6-halium https://gitlab.com/ubports/porting/community-ports/android12/generic/kernel-android-common.git ~/klee-ut/kernel
cd ~/klee-ut/kernel && git checkout $(cut -d' ' -f1 /yol/kernel/BASE_COMMIT) && git apply /yol/kernel/klee-kernel.patch

# port (yolları build-klee.sh başındaki değişkenlerden ayarlayın; yolda boşluk olmasın)
cp -r port ~/klee-ut/ubports-klee
~/klee-ut/ubports-klee/build-klee.sh          # SKIP_KERNEL=1 / SKIP_ROOTFS=1 seçenekleri var
```

USB SSH için kendi anahtarınızı `port/overlay/system/etc/klee/authorized_keys` olarak koyun
(UT açılınca `ssh -p 8022 root@10.15.19.82`, USB NCM).

Kurulum ve geçiş adımları: [release/BENIOKU.md](release/BENIOKU.md).

## Sıradaki işler (devralacak kişi için)

- Bilgisayarsız geçiş: Android açıkken aktif slot boot'u yazılamıyor. Seçenekler:
  (a) OrangeFox recovery üzerinden yazmak — `android-side/klee-switch.sh` + karma
  vendor_boot (`tools/make-hybrid-vendor-boot-ramdisk.py`); son denemede yazma sırasında
  telefon yeniden başlayıp BROM döngüsüne girdi, nedeni bulunamadı. (b) Slot yöntemi:
  pasif slot `_a`'ya Axion kopyası + UT boot.
- Ses (vendor AIDL audio core v2/v3 ↔ pulseaudio-droid / audiosystem-passthrough).
- Kamera, parmak izi, arama/veri, güç yönetimi.

## Teşekkür

UBports (halium-gki, kernel-android-common), Halium, OrangeFox klee bakımcıları,
AxionAOSP klee bakımcısı.

## Lisans

Bu depodaki klee'ye özgü kod, betikler ve araçlar GPL-2.0 ile paylaşılmıştır. UBports
`halium-gki`'den gelen dosyalar (`port/build/`, ramdisk betiklerinin temeli) UBports'un kendi
şartlarına tabidir (halium-gki `e05c1ebd0aab`, build alt deposu `78d5df8abeaa`). Çekirdek yaması GPL-2.0.
`port/overlay/.../halium-overlay/system/lib64/` altındaki ikili dosyalar AOSP/LLVM
kaynaklıdır (Apache-2.0); `libbinder_ndk.so` `host-tools/add_noop_syms.py` ile yamalanmıştır.
