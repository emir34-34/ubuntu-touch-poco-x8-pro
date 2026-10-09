# Poco X8 Pro (klee) — Ubuntu Touch dual boot

Axion ve /data verilerin **hiç silinmiyor, formatlanmıyor**. Ubuntu Touch, super
bölümündeki boş alanda yeni bir mantıksal bölüme (`ut_data`) kuruluyor. İki sistem
arasında geçiş, aktif slotun `boot` + `init_boot` imajlarını değiştirmekten ibaret.

## Klasör içeriği

| Dosya | Ne işe yarar |
|---|---|
| `images/ut_boot.img` | Ubuntu Touch çekirdeği (UBports android15-6.6-halium GKI, cihazdaki 6.6.89 ile aynı KMI) |
| `images/ut_init_boot.img` | Halium initramfs + klee yamaları (slot farkındalıklı super eşleme, güvenlik kontrolleri) |
| `images/ubuntu.img` | Ubuntu Touch 24.04-1.x rootfs (Halium 14) + klee overlay + 6.6 modülleri |
| `images/ut_boot_fastboot-boot.img` | Flash etmeden tek seferlik `fastboot boot` denemesi için |
| `install.sh` | Kurulum: yedek alır, `ut_data` bölümünü oluşturur, rootfs'u yazar |
| `boot-ubuntu.sh` / `boot-axion.sh` | Bilgisayardan sistem değiştirme |
| `device/to-ubuntu.sh` | Telefondan (Axion, root) Ubuntu'ya geçiş |
| `try-ubuntu-noflash.sh` | Deneysel: hiçbir şey yazmadan bir kez Ubuntu açmayı dener |
| `collect-logs.sh` | Hata ayıklama logları |
| `uninstall.sh` | Ubuntu Touch'ı tamamen kaldırır |

## Kurulum (telefon Axion'da açık, USB hata ayıklama açık)

1. KernelSU yöneticisinde **Shell** uygulamasına root izni ver.
2. Önce kuru çalıştırma (telefonda hiçbir şeyi değiştirmez, yalnızca yedek alır ve imajı hazırlar):
   ```
   ./install.sh --dry-run
   ```
3. Asıl kurulum (yedek → `fastbootd` → `ut_data` oluştur → flash → Axion'a geri döner):
   ```
   ./install.sh
   ```
   Yedekler `backup-<tarih>/` klasörüne kaydedilir (`backup-latest` en sonuncuya bağlıdır).
   **Bu klasörü silme**, Axion'a dönüş için gerekli. Aynı yedekler `ut_data` içine de konur.

## Sistem değiştirme

- **Ubuntu'ya geç:** `./boot-ubuntu.sh` veya telefonda (Axion, root):
  `su -c sh /sdcard/klee-ut/to-ubuntu.sh`
- **Axion'a dön:** Ubuntu Touch içinde terminalde `sudo klee-boot-android`, ya da
  telefon açılmıyorsa **Ses Kısma + Güç** ile bootloader'a (fastboot) gir ve
  `./boot-axion.sh` çalıştır.
- Bootloader (LK) hiç değiştirilmiyor; fastboot moduna her zaman girilebilir.
- Ubuntu aktifken `adb reboot fastboot` (fastbootd) çalışmaz. Bootloader fastboot'u kullan.

## İlk açılışta beklenenler / hata ayıklama

- İlk açılış birkaç dakika sürebilir. Ekran logoda kalabilir.
- Ekran gelmezse USB kablosu takılıyken Ubuntu Touch "rescue mode"da bir USB ağ
  arabirimi açar: `ssh -p 8022 phablet@10.15.19.82` (şifre yok), ardından
  `./collect-logs.sh ubuntu`.
- Initramfs aşamasında hata olursa telefon USB üzerinden `192.168.2.15` adresinde
  telnet açar: `telnet 192.168.2.15`.
- Hiçbiri yoksa: Ses Kısma + Güç → `./boot-axion.sh` → Axion açılınca
  `./collect-logs.sh android` (önceki açılışın çekirdek logunu pstore'dan alır).

## Güvenlik önlemleri (Axion verisini korumak için)

- Ubuntu Touch **asla** `userdata`'ya dokunmaz. `datapart` bulunamazsa açılış durur.
  Bölüm ext4 değilse de durur.
- `/metadata` (Axion'un şifreleme anahtarları) hiç bağlanmaz. Konteyner içinde boş
  bir tmpfs görür.
- Vendor'ın `mount_all`/`swapon_all` komutları çalışma anında etkisizleştirilir.

## Bilinen riskler / yapılamayanlar

- Halium 14 (Android 14) sistemi, Android 16 vendor ile çalışıyor. Uyumluluk için
  `libbinder_ndk.so`'ya eksik bir sembol eklendi ve VINTF 9.0 manifestleri 8.0 olarak
  sunuluyor. Bunlar çevrimdışı doğrulandı, cihazda henüz test edilmedi.
- Ses (AIDL audio HAL v2), kamera, parmak izi, VoLTE gibi parçaların ilk denemede
  çalışması beklenmemeli. Hedef önce açılış + ekran + dokunmatik + Wi-Fi.

## Ekran ayarları (kamera deliği / durum çubuğu)

Axion'un ekran ayarlarından alınan değerler: ekran 1268×2756, kamera deliği üst-ortada
78×102 px, köşe yarıçapı 190 px.

- Durum çubuğu 120 px (Lomiri'nin varsayılanı 72 px'di, kamera deliği taşıyordu).
- Durum çubuğu simgelerine sağ/sol 64 px boşluk (yuvarlak köşeler kesmesin diye).
- Arayüz ölçeği: GridUnit 24 (`/etc/deviceinfo/devices/halium.yaml`).

Telefonda denemek için (Ubuntu Touch terminali):
```
sudo mount -o remount,rw /
sudo nano /usr/share/lomiri/Shell.qml          # "klee: clear the punch-hole" satırındaki 120
sudo nano /usr/share/lomiri/Panel/PanelMenu.qml # leftMargin/rightMargin: 64
sudo nano /etc/deviceinfo/devices/halium.yaml   # GridUnit (büyük = her şey büyür)
sudo mount -o remount,ro /
restart lomiri   # veya telefonu yeniden başlat
```
Kalıcı değerler derleme tarafında: `~/klee-ut/ubports-klee/rootfs-patches/lomiri-klee.sh`.

## IMEI / SIM

- `install.sh`, Ubuntu ilk kez açılmadan **önce** IMEI ve modem verilerinin bulunduğu
  bölümleri (nvram, nvdata, nvcfg, protect1/2, md_sec, persist, proinfo) yedekler:
  `backup-<tarih>/imei/`. **Bu klasörü başka bir yere de kopyala.**
- IMEI bir gün kaybolursa: bootloader (fastboot) modunda
  `fastboot flash nvdata nvdata.img` (ve aynı şekilde diğerleri) ile geri yüklenir.
- SIM/arama: Ubuntu Touch'ta ofono + binder RIL + MTK eklentisi var, ama Android 16 RIL'iyle
  ilk denemede çalışması garanti değil. Önce açılış + ekran, sonra SIM.
