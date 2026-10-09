# klee Ubuntu Touch portu — teknik notlar

## Kaynaklar
- Port deposu: `~/klee-ut/ubports-klee` (UBports `halium-gki` şablonundan). Derleme:
  `~/klee-ut/ubports-klee/build-klee.sh` (`SKIP_KERNEL=1`, `SKIP_ROOTFS=1` seçenekleri var).
- Çekirdek: `~/klee-ut/kernel` = `gitlab.com/ubports/.../kernel-android-common` dalı
  `android15-6.6-halium` (6.6.138) + `gki_quirks.c`'ye `mali_kbase_mt6899_r49` eklendi.
  Derleyici: AOSP clang r510928 (stok çekirdekle aynı), `~/klee-ut/toolchain`.
- Rootfs: UBports CI `halium-gki` → `devel-flashable-android14-6.1` (UT 24.04-1.x, Halium 14 GSI).
- Proje yolunda boşluk olduğu için her şey `~/klee-ut` altında derleniyor.

## Doğrulananlar (cihaz olmadan)
- `tools/kmi_check.py`: vendor_boot + vendor_dlkm + odm_dlkm + system_dlkm içindeki 592 modülün
  çekirdek sembol CRC'leri bizim `Module.symvers` ile **0 uyumsuzluk** (negatif testle doğrulandı).
- `tools/abi_check.py`: vendor ELF'leri, GSI sistem kütüphanelerine karşı tarandı. Tek eksik sembol
  `AIBinder_Class_setTransactionCodeToFunctionNameMap` (49 AIDL arayüz kütüphanesi) →
  `tools/add_noop_syms.py` ile GSI `libbinder_ndk.so`'ya eklendi (kod kaydırılmadan, DT_HASH).
- QEMU (aarch64 virt, kendi çekirdeğimiz + init_boot ramdisk'imiz): lp-map → `ut_data` →
  `ubuntu.img` → Android GSI → systemd "Welcome to Ubuntu 24.04.5 LTS" çalıştı. Gerçek Axion
  vendor/odm/dlkm bölümleriyle `mount-android-partitions` başarılı.

- QEMU 2. tur (`~/klee-ut/qtest/run.sh`): Android konteyneri çalışıyor, **55 servis kayıtlı**
  (allocator, health, power, sensors, vibrator, wifi, bluetooth, audio core, NFC, GNSS, memtrack...).
  Composer QEMU'da MTK donanımı olmadığı için çöküyor (beklenen).

- QEMU gerçek modül testi (`~/klee-ut/qtest/modload-loop.sh`): Axion vendor_boot'undaki 223 ilk aşama
  modülünün tamamı Halium initramfs'i ile bizim çekirdeğe yüklendi. Çekirdek kaynaklı sembol/sürüm
  hatası 0. QEMU'da MTK donanımı olmadığı için çöken 2 modül (`log_store`, `aee_hangdet`) yalnızca testte
  atlandı. Tek "disagrees about version": `mtk_battery_manager` ↔ `mtk_charger_framework`
  (`usb_get_property`): Xiaomi/Axion vendor'ının kendi iç uyumsuzluğu, stok çekirdekte de aynı.
  Axion'da `dmesg | grep disagrees` ile doğrulanabilir.

## Android 14 GSI ↔ Android 16 vendor uyumluluk yamaları
1. VINTF manifestleri `version="9.0"` → `8.0` (GSI libvintf'i en fazla 8.0 tanıyor).
2. `libbinder_ndk.so`'ya no-op `AIBinder_Class_setTransactionCodeToFunctionNameMap`.
3. Vendor `mount_all`/`swapon_all` etkisizleştirildi, `/metadata` boş tmpfs.
4. `/vendor/apex` gizlendi (boot/cas/widevine). İçlerindeki 9.0 VINTF tüm cihaz manifest'ini düşürüyordu.
5. vndbinder: A16 `vndservicemanager` SELinux bağlamı olmadan abort ediyor → GSI'nin
   `/system/bin/servicemanager /dev/vndbinder` kullanılıyor.
6. UBports `common.sh` hatası düzeltildi: `build_partname_cache` global `partname`'i eziyordu,
   bilinmeyen etiketler son blok aygıtına çözülüyordu.

## Önemli cihaz bilgileri
- Aktif slot `_b`, super 12 GiB (VAB, metadata slot sayısı 3). `parse-android-dynparts` yalnızca
  slot 0'ı okuduğu için kendi `lp-map`'imiz kullanılıyor.
- `/data`: f2fs + metadata şifreleme (`/metadata/vold/metadata_encryption`) → Linux okuyamaz.
- LK cmdline'ı `firmware_class.path=/vendor/firmware,/odm/firmware` veriyor.
- Wi-Fi: `/dev/wmtWifi`'ye `1` yazılınca `wlan0` çıkıyor (`klee-wifi.service`).
- GKI'de RNDIS yok, NCM var. usb-moded ve initrd telnet NCM'ye düşüyor.

## Bilinen açık noktalar
- `leds-mtk-disp.ko` stokta da çözülemeyen bir sembol istiyor (`mtk_drm_gateic_set_backlight`),
  stok Axion'da da aynı.
- Ses: vendor AIDL audio core v2. UT'nin pulseaudio-droid yolu test edilmedi.
