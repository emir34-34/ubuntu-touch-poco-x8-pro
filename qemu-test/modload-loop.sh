#!/bin/bash
# Load Axion's real vendor_boot (first stage) modules with our kernel in QEMU.
# Modules that crash/hang because the MTK hardware is missing in QEMU are
# blocklisted one by one (test only) until the initramfs finishes loading.
set -uo pipefail
Q="$(cd "$(dirname "$0")" && pwd)"
cd "$Q"
V=$Q/realvr
BL=$Q/modload-blocklist.txt
: > "$BL"
for it in $(seq 1 60); do
	awk "{print \$1}" "$BL" > $V/lib/modules/modules.blocklist
	sed -i 's/^/blocklist /' $V/lib/modules/modules.blocklist
	(cd $V && find . | cpio -o -H newc 2>/dev/null | lz4 -l -9 > $Q/real_vendor_ramdisk.lz4)
	cat $Q/real_vendor_ramdisk.lz4 $Q/ib/ramdisk > $Q/initrd-real.img
	LOG=$Q/modload-$it.log; rm -f "$LOG"
	"$HOME/klee-ut/qemu/usr/bin/qemu-system-aarch64" -M virt,gic-version=3 -cpu max,pauth-impdef=on -smp 8 -m 6144 \
		-accel tcg,thread=multi -no-reboot -kernel Image -initrd initrd-real.img \
		-append "console=ttyAMA0 earlycon datapart=/dev/mapper/ut_data printk.devkmsg=on androidboot.slot_suffix=_b loglevel=6" \
		-drive if=none,file=disk.img,format=raw,id=hd,snapshot=on -device virtio-blk-pci,drive=hd \
		-nic none -display none -serial file:"$LOG" -monitor none &
	QP=$!
	last=""; idle=0; result=""
	while kill -0 $QP 2>/dev/null; do
		sleep 3
		if grep -qa 'Finished loading kernel modules' "$LOG"; then result=done; break; fi
		if grep -qaE 'Kernel panic|Internal error' "$LOG"; then result=crash; break; fi
		cur=$(grep -a 'initrd: Loading ' "$LOG" | tail -1)
		if [ "$cur" = "$last" ]; then idle=$((idle + 3)); else idle=0; last=$cur; fi
		if [ $idle -ge 90 ]; then result=hang; break; fi
	done
	kill $QP 2>/dev/null; wait $QP 2>/dev/null
	[ -z "$result" ] && result=exited
	mod=$(grep -a 'initrd: Loading ' "$LOG" | tail -1 | awk '{print $NF}')
	if [ "$result" = crash ]; then
		# prefer the module named in the oops backtrace
		m2=$(grep -aoE 'pc : [^ ]+ \[[a-zA-Z0-9_]+\]' "$LOG" | head -1 | sed -E 's/.*\[([^]]+)\]/\1/')
		[ -n "$m2" ] && mod=$m2
	fi
	echo "iteration $it: $result (last module: $mod)"
	if [ "$result" = done ]; then
		cp "$LOG" $Q/modload-final.log
		break
	fi
	[ -n "$mod" ] && echo "$mod $result" >> "$BL"
done
echo "blocklisted for QEMU:"; cat "$BL"
