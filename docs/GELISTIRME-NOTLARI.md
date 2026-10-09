# Geliştirme notları (2026-10-07 → 2026-10-08)

Cihaz üzerinde denenirken öğrenilen her şey, kabaca kronolojik sırayla. Yollar
geliştiricinin makinesine göredir (`~/klee-ut/...`); depoda karşılıkları `port/`,
`kernel/`, `host-tools/` vb. altında.

## Cihaz

- Poco X8 Pro, `klee`, 2511FPC34G, MediaTek mt6899, Android 16, A/B + Virtual A/B,
  dinamik bölümler, `/data` f2fs + metadata şifreleme (Linux okuyamaz).
- Test edilen ROM: AxionAOSP v2.8 (Android 16 QPR2), KernelSU Next LKM (init_boot yamalı).
  Axion kendi `boot` ve `vendor_boot` imajlarıyla geliyor.
- Super gerçekte ~8.5 GiB kullanılabilir (12 değil). Metadata slot sayısı 3.
  Stok `parse-android-dynparts` yalnızca slot 0'ı okuyor → kendi `ramdisk-overlay/sbin/lp-map`'imiz.
- LK, boot.img cmdline'ını bozuyor → ramdisk `datapart=/dev/mapper/ut_data`'yı sabit kodluyor.
  LK cmdline: `firmware_class.path=/vendor/firmware,/odm/firmware`, `kvm-arm.mode=protected`.
- Normal açılışta `/proc/bootconfig`'te `androidboot.force_normal_boot = "1"` var (cmdline'da yok).
- `expdb` (sdc4) preloader/LK loglarını tutuyor (RAM_CONSOLE, wdt durumu).
- Bootloader açık ama ROM tarafı (Fenrir) kilitli/green gösteriyor; `ro.boot.verifiedbootstate`'e güvenmeyin.

## Tasarım

- Taban: UBports `halium-gki` + çekirdek `android15-6.6-halium` (stok 6.6.89-android15-8 ile aynı GKI nesli).
  Rootfs: UT 24.04-1.x, Halium 14 GSI (CI artifact `devel-flashable-android14-6.1`).
- `ut_data`: super'ın default grubunda yeni mantıksal bölüm, ext4 (initrd e2fsck 1.43 olduğu için
  `metadata_csum`/`orphan_file` kapalı). İçinde `/ubuntu.img` (EROFS, ~1.24 GB) + yedekler.
- Geçiş = aktif slotun `boot` + `init_boot` imajlarını değiştirmek.
- Güvenlik: `/metadata` asla bağlanmaz (konteyner boş tmpfs görür), `userdata`'ya asla düşülmez,
  ext4 olmayan datapart'ta açılış durur, vendor `mount_all`/`swapon_all` çalışma anında etkisiz.

## Android 14 GSI ↔ Android 16 vendor uyumluluğu

1. VINTF `meta-version="9.0"` → `8.0` (bind-mount kopyalar).
2. GSI `libbinder_ndk.so`'ya no-op `AIBinder_Class_setTransactionCodeToFunctionNameMap`
   (49 vendor AIDL `-ndk` kütüphanesi istiyor). `host-tools/add_noop_syms.py`, kod kaydırmadan, DT_HASH.
   `/usr/share/halium-overlay/system/lib64` üzerinden.
3. `/vendor/apex` gizlendi (tmpfs): içindeki 9.0 VINTF tüm cihaz manifestini NULL yapıyordu.
4. A16 `vndservicemanager` SELinux sid olmadan abort ediyor → GSI'nin
   `/system/bin/servicemanager /dev/vndbinder`'ı kullanılıyor.
5. UBports `common.sh` hatası: `build_partname_cache` global `$partname`'i eziyordu, bilinmeyen
   etiketler son blok aygıtına çözülüyordu → özel değişkenlerle düzeltildi.
6. Vendor `libc++` halium-overlay ile (NODELETE) — `libGLES_meow` için.
7. `mount_all --late` → `trigger nonencrypted` (yoksa `class_start main` gelmiyor, PQ başlamıyor,
   composer bekliyordu).

## Çevrimdışı doğrulama

- `host-tools/kmi_check.py`: vendor_boot + vendor_dlkm + odm_dlkm + system_dlkm, 592 modül,
  0 CRC uyumsuzluğu (negatif testle doğrulandı).
- `host-tools/abi_check.py`: vendor ELF'leri ↔ GSI kütüphaneleri; tek eksik yukarıdaki sembol.
- QEMU (`qemu-test/run.sh`): lp-map → ut_data → ubuntu.img → Android konteyneri, 55 servis kayıtlı.
  `modload-loop.sh`: Axion vendor_boot'undaki 223 ilk aşama modülü yüklendi.

## Cihazda çözülen sorunlar

### ~140 sn'de reset
MediaTek MKP (kernel protection) pid > 32768 görünce telefonu resetliyor
(`bootreason=RebootException`). systemd `pid_max=4194304` yapıyor. Çözüm: ramdisk'te
`echo 32768 > /proc/sys/kernel/pid_max` + `/etc/klee/50-pid-max.conf`'u rootfs'taki
`/usr/lib/sysctl.d/50-pid-max.conf` üzerine bind-mount. Ayrıca `modprobe.d/klee-blacklist.conf`
(aee_hangdet, monitor_hang, mtk_heap_debug).

### Pil
Stok `mtk_battery_manager.ko`'da `usb_get_property` CRC uyuşmazlığı (0x8939cfe6 vs
charger_framework 0xb4dcf409, imza aynı) → yüklenmiyordu, `battery` psy yoktu, thermal HAL
çöküyordu. CRC'si düzeltilmiş kopya ramdisk `/lib/klee/`'de, modprobe döngüsünden sonra insmod.
Araç: `host-tools/crc_check_module.py`. (Axion'un kendi vendor'ının iç uyumsuzluğu; OrangeFox'un
vendor_boot'undaki sürümde yok.)

### Ekran
- `lomiri-system-compositor`: "mapper.mediatek.so not found" → `HYBRIS_LD_LIBRARY_PATH`'e
  `/odm/lib64/hw:/vendor/lib64/hw:/vendor/lib64/egl` eklendi (lsc-wrapper).
- glibc `free(): invalid pointer`: bionic (scudo) belleği glibc `free()`'ye gidiyordu →
  `shims/klee_free.c` (`libklee_free.so`, LD_PRELOAD). Derleme: AOSP clang
  `--target=aarch64-linux-gnu -nostdlib`, sysroot `libc.so.6` + `libhybris-common.so.1`.
- Siyah ekran: parlaklık yalnızca `/sys/class/mi_display/disp-DSI-0/backlight` ile panele gidiyor
  (DCS 0x51). `lcd-backlight` LED'i ulaşmıyor; sürücü aynı değeri tekrar göndermiyor ve panel init
  bitmeden yazılan kayboluyor → `klee-brightness.service` değişiklikten sonra 3 sn boyunca
  want-1/want dönüşümlü yazıyor.
- AMOLED'de siyah içerik kapalı panel gibi görünür. `mirscreencast` bu GPU'da çöp döndürüyor.
- Ekranı uyandırmak: `/dev/input/event0`'a KEY_POWER (116).
- Kamera deliği: ekran 1268×2756, delik üst-orta 78×102 px, köşe yarıçapı 190 px →
  durum çubuğu 120 px, kenar boşluğu 64 px, GridUnit 24 (`rootfs-patches/lomiri-klee.sh`).

### Diğer
- `usb-moded` maskelendi, kendi `klee-usbnet` (NCM, `10.15.19.82`, `ssh -p 8022`).
  Bilgisayarda: `nmcli dev set <if> managed no` + `10.15.19.1/24`. GKI'de RNDIS yok.
- Wi-Fi: `/dev/wmtWifi`'ye `1` → `wlan0` (`klee-wifi.service`).
- Güç tuşu açılışta logind poweroff tetikliyordu → `HandlePowerKey=ignore`.
- Fastboot'a geçiş UT'den: `systemctl reboot --reboot-argument=bootloader`.
- Rootfs'u flash'sız güncelleme: yeni imajı `/userdata/ubuntu.img.new`'e kopyala, sha256 doğrula,
  `mv`, reboot.
- Canlı test ipucu: `/run` noexec → `/run/kleebin`'e `-o exec` tmpfs, değiştirilmiş betiği bind-mount.
- Açık sorun: hybris `getprop`, "unregister_tls_module CHECK" ile abort (vendor libc++ PT_TLS).

## !!! IMEI olayı (KRİTİK)

UT'den Axion'a dönünce IMEI yoktu: modem her açılışta çöküyordu (md_state 5, NV_ASSERT LID
0xF00A `nvram_get_dev_boot_times`, `dev_fs_move FS -16 ACCESS_DENIED`).

- **Kök neden:** UT'de SELinux kapalı. Konteynerdeki `ccci_fsd` vb. `protect_s/md` altındaki 17
  dosyayı ve `persist/data/7`'yi **etiketsiz** (`u:object_r:unlabeled:s0`) yeniden yazdı. Axion
  enforcing → `avc denied unlink` (ccci_mdinit) → modem çöker.
- **Elle düzeltme:** `chcon u:object_r:protect_s_data_file:s0` (protect_s/md/*),
  `chcon u:object_r:mitee_sfs_file:s0` (persist/data/7), reboot. `restorecon -R -F` bu bölümlerde
  ÇALIŞMADI. IMEI dosyalarının kendisi bozulmamıştı.
- **Teşhis:** `su -c "ls -laZR /mnt/vendor/{protect_f,protect_s,nvdata,nvcfg,persist,md_sec} | grep unlabeled"`,
  dmesg `md_state`, logcat avc.
- **Kalıcı koruma (ikisi de cihazda çalıştı):**
  - UT: `klee-selinux-guard.service` 10 sn'de bir `/proc/<lxc pid>/root/mnt/vendor/*`'ı tarar,
    etiketsiz dosyaya üst klasörün `security.selinux` xattr'ını yazar; kapanışta konteynerden sonra
    durur ve son taramayı yapar.
  - Android: KernelSU modülü `klee_dualboot` (`port/android-side/ksu-module`), post-fs-data'da
    aynısını `chcon` ile yapar (tam yol `/system/bin/...` — ksud busybox ile çalıştırır).
    Kayıt: `/data/adb/klee-selinux-fix.log`.

## Boot bölümü yazma koruması

Android **ve** UT açıkken aktif slotun `boot`/`init_boot`'u yazılamıyor (UFS sense key 0x7
DATA PROTECT); pasif slot yazılabiliyor; fastboot ve OrangeFox recovery'de yazılabiliyor.
UT içinden `dd` ile boot yazmak fsync EIO verdi ve bir kez BROM döngüsüne yol açtı → boot
imajlarını yalnızca fastboot'tan yazın.

## OrangeFox ile bilgisayarsız geçiş denemesi (yarım)

- OrangeFox R12 (klee, "system-compatible") `vendor_boot`'a flash'lanıyor. Normal OF vendor_boot ile
  UT açılmıyor: OF'un platform fragmanı tüm recovery'yi içeriyor ve UT'nin halium ramdisk'iyle çakışıyor.
- Karma vendor_boot: Axion'un dtb/bootconfig/cmdline/platform fragmanı + recovery fragmanı =
  OF00 (Axion'la bayt bayt aynı `.ko`'lar hariç) + OF01, lz4 -l, `avbtool add_hash_footer
  --partition_size 67108864`. Araç: `port/tools/make-hybrid-vendor-boot-ramdisk.py`.
  - **Hata dersi:** cpio birleştirirken dizin kayıtlarını atlamayın; Linux initramfs eksik üst
    klasörleri oluşturmaz. v1'de 17 dosya (ör. `libmtk_bsg.so`) açılmadı → boot HAL çöktü → OF
    splash'te kaldı (IBootControl bekliyor).
- Recovery modunda ramdisk = vendor fragmanları + init_boot (UT halium) → UT'nin `/init`,`/bin`,`/etc`'si
  OF'unkini eziyor. Çözüm `port/ramdisk-overlay/init` başında: `/system/bin/recovery` varsa ve
  `force_normal_boot=1` yoksa bunları `/.klee-ut`'e taşı, symlinkleri kur, `exec /init`.
- UT çekirdeği AppArmor seçiyor (CONFIG_LSM'de selinux'tan önce; ikisi exclusive) → OF init selinuxfs
  bulamaz. `kernel/klee-kernel.patch` (`security/security.c`): `force_normal_boot=1` yoksa
  `lsm=...selinux...`. QEMU'da doğrulandı.
- Akış: `android-side/klee-request-switch.sh` OpenRecoveryScript'i `rescue` bölümüne (OF'un /cache'i)
  bırakır → OF'ta PIN girilince `klee-switch.sh` boot/init_boot yazar → sistem.
- **Son deneme:** OF içinden `klee-switch.sh ubuntu` çalışırken telefon kendiliğinden yeniden
  başladı ve preloader↔BROM döngüsüne girdi (USB'de `0e8d:2000`/`0e8d:0003` dönüşümlü). Ses Kısma +
  Güç ile fastboot'a girip Axion boot/init_boot ve stok OF vendor_boot yazılarak kurtarıldı.
  Nedeni bulunamadı.
- OF fastbootd her komutu "Unable to query battery data" ile reddediyor (reboot dahil) → ekrandan
  "Reboot to system". Bu yüzden `fastboot delete-logical-partition ut_data` OF'tan çalışmadı;
  bootloader'ın fastbootd'si veya Android'den `lpmake`/`lptools` gerekebilir.

## Kaldırma

`release/uninstall.sh`. `ut_data` silinmezse zararsızdır (super'da ~3.2 GB yer tutar).
Super metadata'sına dokunmadan önce `lpdump` çıktısı ve super'ın ilk 8 MiB'ını yedekleyin.
