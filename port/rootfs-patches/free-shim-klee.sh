#!/bin/bash
# klee: preload libklee_free.so (shims/klee_free.c) next to libtls-padding.so.
# Vendor libraries (Mali EGL/GLES) allocate through unhooked bionic functions
# and later free() through glibc, which aborts with "free(): invalid pointer"
# in the system compositor, Lomiri and every GL app.
set -euo pipefail
R="${1:?rootfs}"
LIB=/usr/lib/aarch64-linux-gnu/libklee_free.so
[ -e "$R$LIB" ] || { echo "free-shim-klee: $LIB missing" >&2; exit 1; }

# user sessions (Lomiri, apps)
F="$R/etc/profile.d/ld_preload_tls_padding.sh"
grep -q libklee_free "$F" || \
	sed -i "s#libtls-padding.so\${LD_PRELOAD#libtls-padding.so:$LIB\${LD_PRELOAD#" "$F"
grep -q libklee_free "$F"

# system compositor
W="$R/usr/share/ubuntu-touch-session/lsc-wrapper"
grep -q libklee_free "$W" || \
	sed -i "s#^export LD_PRELOAD=libtls-padding.so\$#export LD_PRELOAD=\"libtls-padding.so $LIB\"#" "$W"
grep -q libklee_free "$W"
echo "free-shim-klee: ok"
