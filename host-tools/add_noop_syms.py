#!/usr/bin/env python3
"""Add no-op exported functions to an aarch64 Android shared library, in place.

Newer (Android 15/16) vendor AIDL libraries reference libbinder_ndk functions
that an Android 14 system lacks (e.g. AIBinder_Class_setTransactionCodeToFunctionNameMap,
which only records names for tracing). Exporting a symbol that points at an
existing `ret` instruction is enough for those.

Nothing existing is moved (Android packed relocations stay valid):
  * new .dynsym/.gnu.version/.dynstr copies + a SysV DT_HASH table are appended
    at the end of the file,
  * the PT_NOTE program header is turned into a PT_LOAD mapping them,
  * DT_SYMTAB/DT_STRTAB/DT_STRSZ/DT_VERSYM are redirected and DT_GNU_HASH is
    replaced by DT_HASH (bionic uses DT_HASH when there is no DT_GNU_HASH).
New symbols are unversioned (global): bionic accepts them for a versioned
reference to a version the library does not define.

usage: add_noop_syms.py <in.so> <out.so> SYMBOL [SYMBOL...]
"""
import struct
import sys

PT_LOAD, PT_NOTE = 1, 4
DT_NULL, DT_HASH, DT_STRTAB, DT_SYMTAB, DT_STRSZ = 0, 4, 5, 6, 10
DT_GNU_HASH, DT_VERSYM = 0x6FFFFEF5, 0x6FFFFFF0
RET = b"\xc0\x03\x5f\xd6"  # aarch64 "ret"
PAGE = 0x1000


def elf_hash(name):
    h = 0
    for c in name:
        h = ((h << 4) + c) & 0xFFFFFFFF
        g = h & 0xF0000000
        if g:
            h ^= g >> 24
        h &= ~g & 0xFFFFFFFF
    return h


def align(x, a):
    return (x + a - 1) & ~(a - 1)


def main():
    src, dst, names = sys.argv[1], sys.argv[2], [n.encode() for n in sys.argv[3:]]
    b = bytearray(open(src, "rb").read())
    assert b[:4] == b"\x7fELF" and b[4] == 2 and b[5] == 1, "need ELF64 LE"
    (e_phoff, e_shoff, e_flags, e_ehsize, e_phentsize, e_phnum,
     e_shentsize, e_shnum, e_shstrndx) = struct.unpack_from("<QQIHHHHHH", b, 0x20)

    phdrs = [list(struct.unpack_from("<IIQQQQQQ", b, e_phoff + i * e_phentsize)) for i in range(e_phnum)]
    shdrs = [list(struct.unpack_from("<IIQQQQIIQQ", b, e_shoff + i * e_shentsize)) for i in range(e_shnum)]
    shstr_off = shdrs[e_shstrndx][4]

    def sname(sh):
        s = shstr_off + sh[0]
        return bytes(b[s:b.index(b"\0", s)]).decode()

    secs = {sname(s): (i, s) for i, s in enumerate(shdrs)}

    def vaddr_to_off(va):
        for p in phdrs:
            if p[0] == PT_LOAD and p[3] <= va < p[3] + p[5]:
                return va - p[3] + p[2]
        raise ValueError(hex(va))

    dyn_ph = [p for p in phdrs if p[0] == 2][0]
    dyn = []
    for i in range(dyn_ph[5] // 16):
        tag, val = struct.unpack_from("<qQ", b, dyn_ph[2] + i * 16)
        dyn.append([tag, val])
        if tag == DT_NULL:
            break
    d = {t: v for t, v in dyn}

    symtab, strtab, strsz = d[DT_SYMTAB], d[DT_STRTAB], d[DT_STRSZ]
    versym = d.get(DT_VERSYM)
    # number of dynamic symbols = size of the .dynsym section
    dynsym_sec = secs[".dynsym"][1]
    nsyms = dynsym_sec[5] // 24
    dynsym = bytes(b[vaddr_to_off(symtab):vaddr_to_off(symtab) + nsyms * 24])
    dynstr = bytes(b[vaddr_to_off(strtab):vaddr_to_off(strtab) + strsz])
    vers = bytes(b[vaddr_to_off(versym):vaddr_to_off(versym) + nsyms * 2]) if versym else b""

    existing = set()
    for i in range(nsyms):
        st_name = struct.unpack_from("<I", dynsym, i * 24)[0]
        existing.add(dynstr[st_name:dynstr.index(b"\0", st_name)])

    text_idx, text = secs[".text"]
    tdata = b[text[4]:text[4] + text[5]]
    ret_va = None
    for off in range(0, len(tdata) - 4, 4):
        if tdata[off:off + 4] == RET:
            ret_va = text[3] + off
            break
    assert ret_va is not None

    new_syms, new_str, new_vers = bytearray(dynsym), bytearray(dynstr), bytearray(vers)
    added = []
    for n in names:
        if n in existing:
            print("already present:", n.decode())
            continue
        name_off = len(new_str)
        new_str += n + b"\0"
        # st_name, st_info (GLOBAL<<4 | FUNC), st_other, st_shndx, st_value, st_size
        new_syms += struct.pack("<IBBHQQ", name_off, (1 << 4) | 2, 0, text_idx, ret_va, 4)
        if vers:
            new_vers += struct.pack("<H", 1)
        added.append(n)
    if not added:
        open(dst, "wb").write(b)
        return
    total = len(new_syms) // 24

    # SysV hash over all symbols (index 0 is the null symbol)
    nbucket = max(1, total // 2) | 1
    buckets = [0] * nbucket
    chains = [0] * total
    for i in range(1, total):
        st_name = struct.unpack_from("<I", new_syms, i * 24)[0]
        nm = bytes(new_str[st_name:new_str.index(b"\0", st_name)])
        h = elf_hash(nm) % nbucket
        chains[i] = buckets[h]
        buckets[h] = i
    hashtab = struct.pack("<II", nbucket, total) + struct.pack("<%dI" % nbucket, *buckets) \
        + struct.pack("<%dI" % total, *chains)

    # lay out the new region
    max_va = max(p[3] + p[5] for p in phdrs if p[0] == PT_LOAD)
    file_end = len(b)
    region_off = align(file_end, PAGE)
    region_va = align(max_va, PAGE)
    blob = bytearray()

    def put(data, al):
        nonlocal blob
        blob += b"\0" * (align(len(blob), al) - len(blob))
        off = len(blob)
        blob += data
        return region_va + off

    va_sym = put(new_syms, 8)
    va_ver = put(new_vers, 2) if vers else None
    va_hash = put(hashtab, 4)
    va_str = put(new_str, 1)

    b += b"\0" * (region_off - file_end)
    b += blob

    note = [i for i, p in enumerate(phdrs) if p[0] == PT_NOTE]
    assert note, "no PT_NOTE to repurpose"
    ni = note[0]
    phdrs[ni] = [PT_LOAD, 4, region_off, region_va, region_va, len(blob), len(blob), PAGE]
    struct.pack_into("<IIQQQQQQ", b, e_phoff + ni * e_phentsize, *phdrs[ni])

    for i, (tag, val) in enumerate(dyn):
        if tag == DT_SYMTAB:
            val = va_sym
        elif tag == DT_STRTAB:
            val = va_str
        elif tag == DT_STRSZ:
            val = len(new_str)
        elif tag == DT_VERSYM and va_ver:
            val = va_ver
        elif tag == DT_GNU_HASH:
            tag, val = DT_HASH, va_hash
        struct.pack_into("<qQ", b, dyn_ph[2] + i * 16, tag, val)

    # keep section headers consistent with the dynamic section (tools, sanity checks)
    def reloc_sec(name, va, size, sh_type=None, entsize=None):
        if name not in secs:
            return
        i, s = secs[name]
        s[3], s[4], s[5] = va, va - region_va + region_off, size
        if sh_type is not None:
            s[1] = sh_type
        if entsize is not None:
            s[9] = entsize
        struct.pack_into("<IIQQQQIIQQ", b, e_shoff + i * e_shentsize, *s)

    reloc_sec(".dynsym", va_sym, len(new_syms))
    reloc_sec(".dynstr", va_str, len(new_str))
    if va_ver:
        reloc_sec(".gnu.version", va_ver, len(new_vers))
    reloc_sec(".gnu.hash", va_hash, len(hashtab), sh_type=5, entsize=4)  # SHT_HASH

    open(dst, "wb").write(b)
    for n in added:
        print("added %s -> 0x%x" % (n.decode(), ret_va))


if __name__ == "__main__":
    main()
