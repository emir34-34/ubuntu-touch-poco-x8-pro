#!/usr/bin/env python3
"""Minimal full-OTA payload.bin extractor (no protobuf dependency).

Usage: payload_extract.py <ota.zip|payload.bin> <outdir> [partition ...]
"""
import bz2
import lzma
import os
import struct
import sys
import zipfile

try:
    import zstandard
except ImportError:
    zstandard = None


def varint(b, i):
    r = s = 0
    while True:
        c = b[i]
        i += 1
        r |= (c & 0x7F) << s
        s += 7
        if c < 128:
            return r, i


def fields(b):
    i = 0
    out = []
    while i < len(b):
        k, i = varint(b, i)
        fn, wt = k >> 3, k & 7
        if wt == 0:
            v, i = varint(b, i)
        elif wt == 2:
            l, i = varint(b, i)
            v = b[i:i + l]
            i += l
        elif wt == 1:
            v = b[i:i + 8]
            i += 8
        elif wt == 5:
            v = b[i:i + 4]
            i += 4
        else:
            raise ValueError("wire type %d" % wt)
        out.append((fn, v))
    return out


def extents(b):
    d = dict(fields(b))
    return d.get(1, 0), d.get(2, 0)


def open_payload(path):
    if zipfile.is_zipfile(path):
        z = zipfile.ZipFile(path)
        info = z.getinfo("payload.bin")
        if info.compress_type != zipfile.ZIP_STORED:
            raise SystemExit("payload.bin is compressed inside zip")
        f = open(path, "rb")
        f.seek(info.header_offset)
        h = f.read(30)
        n, e = struct.unpack("<HH", h[26:30])
        base = info.header_offset + 30 + n + e
        return f, base
    return open(path, "rb"), 0


def main():
    src, outdir = sys.argv[1], sys.argv[2]
    want = set(sys.argv[3:])
    f, base = open_payload(src)
    f.seek(base)
    magic, ver, msize, sigsz = struct.unpack(">4sQQI", f.read(24))
    assert magic == b"CrAU", magic
    manifest = f.read(msize)
    data_start = base + 24 + msize + sigsz
    block_size = 4096
    parts = []
    for fn, v in fields(manifest):
        if fn == 3:
            block_size = v
        elif fn == 13:
            parts.append(v)
    os.makedirs(outdir, exist_ok=True)
    for p in parts:
        pf = fields(p)
        name = [v for k, v in pf if k == 1][0].decode()
        if want and name not in want:
            continue
        ops = [v for k, v in pf if k == 8]
        size = [dict(fields(v)).get(1) for k, v in pf if k == 7][0]
        print("extracting %s (%d MiB, %d ops)" % (name, size >> 20, len(ops)), flush=True)
        with open(os.path.join(outdir, name + ".img"), "wb") as o:
            o.truncate(size)
            for op in ops:
                of = fields(op)
                d = {}
                dst = []
                for k, v in of:
                    if k == 6:
                        dst.append(extents(v))
                    else:
                        d[k] = v
                typ = d.get(1, 0)
                if typ in (6, 7):  # ZERO / DISCARD (file already zero)
                    continue
                f.seek(data_start + d.get(2, 0))
                raw = f.read(d.get(3, 0))
                if typ == 0:
                    out = raw
                elif typ == 1:
                    out = bz2.decompress(raw)
                elif typ == 8:
                    out = lzma.decompress(raw)
                elif typ == 14:
                    if zstandard is None:
                        raise SystemExit("zstd op: pip install zstandard")
                    out = zstandard.ZstdDecompressor().decompress(raw, max_output_size=1 << 30)
                else:
                    raise SystemExit("unsupported op type %d (incremental OTA?)" % typ)
                pos = 0
                for start, num in dst:
                    o.seek(start * block_size)
                    n = num * block_size
                    o.write(out[pos:pos + n])
                    pos += n


if __name__ == "__main__":
    main()
