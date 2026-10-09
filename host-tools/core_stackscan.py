#!/usr/bin/env python3
"""Poor man's unwinder for an aarch64 Linux core file.

Finds the crashing thread's registers (first NT_PRSTATUS), then scans its stack
for values that point into mapped code of shared objects (NT_FILE) and prints
them as <library>+<offset>, plus pc/lr. Useful when the libraries are stripped
and lldb/gdb can't unwind (libhybris/Android libraries).

usage: core_stackscan.py <core> [words=2048]
"""
import struct
import sys


def main():
    core = open(sys.argv[1], "rb").read()
    nwords = int(sys.argv[2]) if len(sys.argv) > 2 else 2048
    phoff, = struct.unpack_from("<Q", core, 0x20)
    phnum, = struct.unpack_from("<H", core, 0x38)
    loads, maps, regs = [], [], None
    for i in range(phnum):
        t, flags, off, vaddr, _, fsz = struct.unpack_from("<IIQQQQ", core, phoff + i * 56)
        if t == 1:
            loads.append((vaddr, vaddr + fsz, off))
        elif t == 4:
            p = off
            while p < off + fsz:
                nsz, dsz, nt = struct.unpack_from("<III", core, p)
                p += 12
                p += (nsz + 3) & ~3
                desc = core[p:p + dsz]
                p += (dsz + 3) & ~3
                if nt == 1 and regs is None:  # NT_PRSTATUS: pr_reg at offset 112
                    regs = struct.unpack_from("<34Q", desc, 112)
                elif nt == 0x46494C45:  # NT_FILE
                    cnt, pg = struct.unpack_from("<QQ", desc, 0)
                    ents = [struct.unpack_from("<QQQ", desc, 16 + k * 24) for k in range(cnt)]
                    names = desc[16 + cnt * 24:].split(b"\0")
                    for (s, e, o), n in zip(ents, names):
                        maps.append((s, e, o * pg, n.decode()))

    def where(a):
        for s, e, o, f in maps:
            if s <= a < e:
                return "%s+0x%x" % (f.split("/")[-1], a - s + o)
        return None

    def read(a, n):
        for s, e, o in loads:
            if s <= a and a + n <= e:
                return core[o + a - s:o + a - s + n]
        return None

    pc, lr, sp = regs[32], regs[30], regs[31]
    print("pc", where(pc), "lr", where(lr), "sp", hex(sp))
    seen = 0
    for k in range(nwords):
        b = read(sp + k * 8, 8)
        if b is None:
            break
        v, = struct.unpack("<Q", b)
        w = where(v)
        if w and not w.startswith("[") and (".so" in w or "compositor" in w):
            print("sp+0x%04x %s" % (k * 8, w))
            seen += 1
            if seen > 60:
                break


if __name__ == "__main__":
    main()
