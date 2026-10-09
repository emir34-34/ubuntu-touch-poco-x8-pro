#!/usr/bin/env python3
"""Set DF_1_NODELETE in DT_FLAGS_1 of an ELF64 shared library (in place on a copy).

libhybris' bionic linker aborts ("unregister_tls_module CHECK
'mod.static_offset == SIZE_MAX' failed") when it unloads a library that has a
PT_TLS segment and was given static TLS. The Android 16 vendor libc++.so has
such a segment; marking it NODELETE means it is never unloaded.

usage: set_nodelete.py <in.so> <out.so>
"""
import struct
import sys

DT_NULL, DT_FLAGS_1 = 0, 0x6FFFFFFB
DF_1_NODELETE = 0x8


def main():
    src, dst = sys.argv[1], sys.argv[2]
    b = bytearray(open(src, "rb").read())
    assert b[:4] == b"\x7fELF" and b[4] == 2
    e_phoff, = struct.unpack_from("<Q", b, 0x20)
    e_phentsize, e_phnum = struct.unpack_from("<HH", b, 0x36)
    for i in range(e_phnum):
        p_type, _, p_offset, _, _, p_filesz = struct.unpack_from("<IIQQQQ", b, e_phoff + i * e_phentsize)
        if p_type != 2:  # PT_DYNAMIC
            continue
        for off in range(p_offset, p_offset + p_filesz, 16):
            tag, val = struct.unpack_from("<qQ", b, off)
            if tag == DT_NULL:
                break
            if tag == DT_FLAGS_1:
                struct.pack_into("<qQ", b, off, tag, val | DF_1_NODELETE)
                open(dst, "wb").write(b)
                print("DT_FLAGS_1: 0x%x -> 0x%x" % (val, val | DF_1_NODELETE))
                return
    raise SystemExit("no DT_FLAGS_1 entry")


if __name__ == "__main__":
    main()
