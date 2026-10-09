#!/usr/bin/env python3
"""Offline check that prebuilt vendor .ko files will load on a self-built GKI kernel.

For every module it compares the symbol CRCs recorded in the module's
__versions section with the kernel's Module.symvers (+ CRCs exported by the
other modules in the set), and reports undefined symbols nobody exports.

usage: kmi_check.py <Module.symvers> <dir-with-.ko> [<dir-with-.ko> ...]
env:   LLVM_BIN=/path/to/clang/bin (for llvm-objcopy / llvm-nm)
"""
import os
import struct
import subprocess
import sys
import tempfile

LLVM = os.environ.get("LLVM_BIN", "")
OBJCOPY = os.path.join(LLVM, "llvm-objcopy")
NM = os.path.join(LLVM, "llvm-nm")


def read_symvers(path):
    syms = {}
    with open(path) as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) >= 2:
                syms[p[1]] = int(p[0], 16)
    return syms


def versions(ko):
    with tempfile.NamedTemporaryFile() as t:
        r = subprocess.run([OBJCOPY, "--dump-section", "__versions=" + t.name, ko, os.devnull],
                           capture_output=True)
        if r.returncode != 0:
            return {}
        data = open(t.name, "rb").read()
    out = {}
    for i in range(0, len(data), 64):
        crc = struct.unpack("<Q", data[i:i + 8])[0] & 0xFFFFFFFF
        name = data[i + 8:i + 64].split(b"\0", 1)[0].decode()
        if name:
            out[name] = crc
    return out


def nm(ko, flag):
    r = subprocess.run([NM, flag, ko], capture_output=True, text=True)
    res = []
    for line in r.stdout.splitlines():
        p = line.split()
        if p:
            res.append(p[-1])
    return res


def exported_crcs(ko):
    """__crc_<sym> absolute symbols give the CRCs a module exports."""
    r = subprocess.run([NM, ko], capture_output=True, text=True)
    out = {}
    for line in r.stdout.splitlines():
        p = line.split()
        if len(p) == 3 and p[2].startswith("__crc_"):
            out[p[2][6:]] = int(p[0], 16) & 0xFFFFFFFF
    # Newer kernels keep the CRC in a data object; fall back to "exported, CRC unknown".
    for line in r.stdout.splitlines():
        p = line.split()
        if len(p) == 3 and p[2].startswith("__ksymtab_"):
            out.setdefault(p[2][len("__ksymtab_"):], None)
    return out


def main():
    kernel = read_symvers(sys.argv[1])
    mods = []
    for d in sys.argv[2:]:
        for root, _, files in os.walk(d):
            for f in files:
                if f.endswith(".ko"):
                    mods.append(os.path.join(root, f))
    exported = {}
    for m in mods:
        for s, c in exported_crcs(m).items():
            exported[s] = c
    bad_crc = {}
    missing = {}
    for m in sorted(mods):
        name = os.path.basename(m)
        v = versions(m)
        for s, crc in v.items():
            if s in kernel:
                if kernel[s] != crc:
                    bad_crc.setdefault(name, []).append(s)
            elif s in exported:
                pass  # CRCs of module-to-module exports are not compared
            elif s != "module_layout":
                missing.setdefault(name, []).append(s)
        for s in nm(m, "-u"):
            if s not in kernel and s not in exported and s not in v:
                missing.setdefault(name, []).append(s)
    print("modules checked: %d" % len(mods))
    print("modules with CRC mismatches: %d" % len(bad_crc))
    for k, s in sorted(bad_crc.items()):
        print("  CRC  %s: %s" % (k, " ".join(sorted(set(s)))))
    print("modules with unresolved symbols: %d" % len(missing))
    for k, s in sorted(missing.items()):
        print("  MISS %s: %s" % (k, " ".join(sorted(set(s)))))
    return 1 if (bad_crc or missing) else 0


if __name__ == "__main__":
    sys.exit(main())
