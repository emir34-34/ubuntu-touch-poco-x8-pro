#!/system/bin/sh
# klee dual boot safety net (KernelSU post-fs-data.d, runs before the modem
# starts): Ubuntu Touch runs the Android vendor services with SELinux off, so
# files the modem rewrites there come back to Android *unlabeled*. With such
# files in protect_s/protect_f/nvdata the modem asserts on boot and the phone
# loses its IMEI until the labels are fixed. Give every unlabeled file the
# label of the directory it is in (that is how these partitions are labeled).
LOG=/data/adb/klee-selinux-fix.log
ROOTS="/mnt/vendor/protect_f /mnt/vendor/protect_s /mnt/vendor/nvdata /mnt/vendor/nvcfg /mnt/vendor/persist /mnt/vendor/md_sec"

# proof that KernelSU ran us on this boot
date > /data/adb/klee-selinux-fix.last

# fast path: one recursive listing; nothing unlabeled -> done
existing=""
for r in $ROOTS; do [ -d "$r" ] && existing="$existing $r"; done
if ! ls -laZR $existing 2>/dev/null | grep -q -e ':unlabeled:' -e ' ? '; then
	exit 0
fi

{
	echo "== $(date) boot: unlabeled files found"
	for r in $ROOTS; do
		[ -d "$r" ] || continue
		find "$r" -mindepth 1 2>/dev/null | while read -r f; do
			ctx=$(ls -dZ "$f" 2>/dev/null | cut -d' ' -f1)
			case "$ctx" in
			*:unlabeled:*|"?") ;;
			*) continue ;;
			esac
			parent=${f%/*}
			# directories right below /mnt/vendor/persist have their own labels
			if [ "$parent" = /mnt/vendor/persist ]; then
				echo "SKIP (top-level persist entry): $f"
				continue
			fi
			plabel=$(ls -dZ "$parent" | cut -d' ' -f1)
			case "$plabel" in *:unlabeled:*) echo "SKIP (parent unlabeled): $f"; continue ;; esac
			chcon "$plabel" "$f" && echo "fixed $f -> $plabel"
		done
	done
	echo "done"
} >> "$LOG" 2>&1

# keep the log small
tail -n 300 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
