#!/bin/bash
# Collect debugging logs after an Ubuntu Touch boot attempt.
#   ./collect-logs.sh android   phone is back in Axion (adb + root): saves the
#                               kernel log of the previous (UT) boot from pstore
#   ./collect-logs.sh ubuntu    phone is in Ubuntu Touch and reachable over USB
#                               (ssh phablet@10.15.19.82 -p 8022 in rescue mode,
#                               or adb if developer mode is on)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/logs/$(date +%Y%m%d-%H%M%S)-${1:-android}"
mkdir -p "$OUT"
case "${1:-android}" in
android)
	adb shell "su -c 'ls -la /sys/fs/pstore'" > "$OUT/pstore-ls.txt"
	for f in $(adb shell "su -c 'ls /sys/fs/pstore'" | tr -d '\r'); do
		adb shell "su -c 'cat /sys/fs/pstore/$f'" > "$OUT/$f.txt"
	done
	adb shell "su -c 'cat /proc/cmdline; cat /proc/bootconfig'" > "$OUT/android-cmdline.txt"
	;;
ubuntu)
	SSH="ssh -p 8022 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null phablet@10.15.19.82"
	if adb get-state >/dev/null 2>&1; then RUN="adb shell"; else RUN="$SSH"; fi
	$RUN 'dmesg' > "$OUT/dmesg.txt"
	$RUN 'journalctl -b --no-pager' > "$OUT/journal.txt"
	$RUN 'cat /proc/cmdline; uname -a; cat /etc/klee-port-version; mount' > "$OUT/system.txt"
	$RUN 'sudo -n /usr/bin/lxc-attach -n android -- /system/bin/logcat -d' > "$OUT/logcat.txt" 2>&1
	$RUN 'sudo -n /usr/bin/lxc-attach -n android -- /system/bin/getprop' > "$OUT/getprop.txt" 2>&1
	;;
esac
ls -la "$OUT"
echo "logs saved in $OUT"
