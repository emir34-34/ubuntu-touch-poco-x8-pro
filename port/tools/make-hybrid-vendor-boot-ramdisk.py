#!/usr/bin/env python3
"""Build the recovery vendor ramdisk fragment of the klee hybrid vendor_boot.

The hybrid image keeps Axion's vendor_boot for normal boots (platform
fragment, dtb, bootconfig, cmdline) and only swaps in OrangeFox as the
recovery fragment. OrangeFox ships most of its recovery in its *platform*
fragment, so the new recovery fragment is OrangeFox's platform fragment +
its recovery fragment, minus the kernel modules that are byte-identical to
the ones in Axion's platform fragment (both are loaded in recovery mode).

usage: make-hybrid-vendor-boot-ramdisk.py AX00.cpio OF00.cpio OF01.cpio OUT.cpio
(all uncompressed newc archives)
"""
import sys


S_IFMT, S_IFDIR = 0o170000, 0o040000


def entries(path):
    d = open(path, 'rb').read()
    off = 0
    while True:
        hdr = d[off:off + 110]
        assert hdr[:6] in (b'070701', b'070702'), f'{path}: bad magic at {off}'
        f = [int(hdr[6 + 8 * i:14 + 8 * i], 16) for i in range(13)]
        namesize, filesize = f[11], f[6]
        name = d[off + 110:off + 110 + namesize - 1].decode()
        doff = (off + 110 + namesize + 3) & ~3
        end = (doff + filesize + 3) & ~3
        if name == 'TRAILER!!!':
            return
        yield name, d[off:end], d[doff:doff + filesize], f[1]
        off = end


def main(ax00, of00, of01, out):
    ax = {n: data for n, _, data, _ in entries(ax00)}
    late = {n for n, _, _, _ in entries(of01)}
    kept = dropped = 0
    with open(out, 'wb') as o:
        for n, raw, data, mode in entries(of00):
            # directories stay: the kernel does not create missing parents,
            # so files of this fragment need them before the later copy
            if n in late and mode & S_IFMT != S_IFDIR:
                continue  # the recovery fragment's copy wins anyway
            if n.endswith('.ko') and ax.get(n) == data:
                dropped += 1
                continue  # Axion's platform fragment has the same module
            o.write(raw)
            kept += 1
        for n, raw, _, _ in entries(of01):
            o.write(raw)
            kept += 1
        # newc trailer
        t = b'070701' + b'0' * 8 * 11 + b'%08X' % 11 + b'0' * 8 + b'TRAILER!!!\0'
        o.write(t + b'\0' * ((4 - len(t) % 4) % 4))
        o.write(b'\0' * ((512 - o.tell() % 512) % 512))
    print(f'kept {kept} entries, dropped {dropped} duplicate modules')


if __name__ == '__main__':
    main(*sys.argv[1:5])
