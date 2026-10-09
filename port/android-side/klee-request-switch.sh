#!/bin/sh
# klee dual boot: ask OrangeFox to switch OS. Leaves an OpenRecoveryScript on
# the rescue partition (OrangeFox's /cache) and reboots to recovery; after the
# PIN is entered OrangeFox runs klee-switch.sh and boots the system again.
# Runs as root on Axion and on Ubuntu Touch.
#   klee-request-switch.sh ubuntu|android
set -u
export PATH=/system/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH

case "${1:-}" in
	ubuntu|android) TARGET=$1 ;;
	*) echo "kullanım: $0 ubuntu|android"; exit 2 ;;
esac
die() { echo "HATA: $*"; exit 1; }

[ "$(id -u)" = 0 ] || die "root yetkisi yok"

# Axion can check the images early; Ubuntu Touch cannot read Android's
# encrypted /data, there klee-switch.sh checks them again in OrangeFox anyway
D=/data/adb/klee
if [ -d /system/app ] && [ ! -d /run/systemd/system ]; then
	[ -f "$D/klee-switch.sh" ] || die "$D/klee-switch.sh bulunamadı"
	(cd "$D" && sha256sum -c SHA256SUMS >/dev/null 2>&1) || die "imaj dosyaları bozuk (SHA256 tutmuyor)"
	echo "İmajlar doğrulandı"
fi

RESCUE=
for p in /dev/block/by-name/rescue /dev/disk/by-partlabel/rescue; do
	[ -b "$p" ] && RESCUE=$p && break
done
[ -n "$RESCUE" ] || die "rescue bölümü bulunamadı"

M=/mnt/klee-rescue
[ -d /run/systemd/system ] && M=/run/klee-rescue  # Ubuntu Touch: / is read-only
mkdir -p "$M" || die "$M oluşturulamadı"
mount -t ext4 "$RESCUE" "$M" || die "rescue bağlanamadı"
mkdir -p "$M/recovery"
cat > "$M/recovery/openrecoveryscript" <<EOF
cmd sh /data/adb/klee/klee-switch.sh $TARGET
reboot system
EOF
ok=$?
chmod 644 "$M/recovery/openrecoveryscript"
sync
umount "$M"
rmdir "$M" 2>/dev/null
[ $ok = 0 ] || die "komut dosyası yazılamadı"

echo "OrangeFox'a yeniden başlatılıyor."
echo "Ekran kilidi PIN'ini gir; gerisi otomatik."
sleep 2
if [ -d /run/systemd/system ]; then
	systemctl reboot recovery
else
	reboot recovery
fi
