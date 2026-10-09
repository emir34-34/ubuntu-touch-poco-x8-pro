#!/usr/bin/env python3
"""Will the (newer) vendor ELFs link against an (older) system image?

Resolves DT_NEEDED libraries and undefined dynamic symbols of every vendor/odm
ELF against: vendor+odm libs, the GSI's /system/lib64, and the GSI's APEX libs.
Prints, per ELF, missing libraries and missing symbols.

usage: abi_check.py --system DIR [--system DIR...] --vendor DIR [--vendor DIR...] [--only REGEX]
env:   LLVM_BIN for llvm-readelf / llvm-nm
"""
import argparse
import os
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor

LLVM = os.environ.get("LLVM_BIN", "")
READELF = os.path.join(LLVM, "llvm-readelf")
NM = os.path.join(LLVM, "llvm-nm")


def is_elf64(p):
    try:
        with open(p, "rb") as f:
            h = f.read(5)
        return h[:4] == b"\x7fELF" and h[4] == 2
    except OSError:
        return False


def scan(dirs):
    out = []
    for d in dirs:
        for root, _, files in os.walk(d):
            if "/lib/" in root + "/" and "/lib64" not in root:
                continue  # skip 32-bit
            for f in files:
                p = os.path.join(root, f)
                if not os.path.islink(p) and is_elf64(p):
                    out.append(p)
    return out


def needed(p):
    r = subprocess.run([READELF, "-d", p], capture_output=True, text=True)
    return re.findall(r"\(NEEDED\).*\[(.+?)\]", r.stdout)


def syms(p):
    r = subprocess.run([NM, "-D", p], capture_output=True, text=True)
    defined, undef = set(), set()
    for line in r.stdout.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[0] in ("U", "w", "v"):
            if parts[0] == "U":
                undef.add(parts[1].split("@")[0])
        elif len(parts) == 3:
            defined.add(parts[2].split("@")[0])
    return defined, undef


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--system", action="append", default=[])
    ap.add_argument("--vendor", action="append", default=[])
    ap.add_argument("--only", default=None)
    a = ap.parse_args()

    libs = {}  # soname/basename -> path (vendor first)
    for p in scan(a.vendor) + scan(a.system):
        libs.setdefault(os.path.basename(p), p)
    info = {}

    def load(p):
        return p, needed(p), syms(p)

    with ThreadPoolExecutor(16) as ex:
        for p, n, (d, u) in ex.map(load, list(set(libs.values()) | set(scan(a.vendor)))):
            info[p] = (n, d, u)

    def closure(p, seen):
        for n in info.get(p, ([], set(), set()))[0]:
            q = libs.get(n)
            if q and q not in seen:
                seen.add(q)
                closure(q, seen)
        return seen

    only = re.compile(a.only) if a.only else None
    bad = 0
    for p in sorted(scan(a.vendor)):
        if only and not only.search(p):
            continue
        n, d, u = info[p]
        miss_libs = [x for x in n if x not in libs]
        prov = set()
        for q in closure(p, set()):
            prov |= info[q][1]
        miss_syms = sorted(s for s in u if s not in prov and s not in d)
        if miss_libs or miss_syms:
            bad += 1
            print(p)
            if miss_libs:
                print("   missing libs:", " ".join(miss_libs))
            if miss_syms:
                print("   missing syms (%d): %s" % (len(miss_syms), " ".join(miss_syms[:15])))
    print("ELFs with problems:", bad)


if __name__ == "__main__":
    main()
