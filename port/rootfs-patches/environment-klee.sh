#!/bin/bash
# klee: same libhybris search path for every session (Lomiri, apps), not only
# for the system compositor (see /etc/default/lsc-wrapper.d/20-klee-hybris.conf).
set -euo pipefail
E="${1:?rootfs}/etc/environment"
L='HYBRIS_LD_LIBRARY_PATH="/system/lib64:/odm/lib64:/vendor/lib64:/odm/lib64/hw:/vendor/lib64/hw:/vendor/lib64/egl"'
grep -q '^HYBRIS_LD_LIBRARY_PATH=' "$E" || echo "$L" >> "$E"
echo "environment-klee: ok"
