#!/usr/bin/env python3
"""Run shell commands on the Halium initrd telnet (192.168.2.15:23).
usage: tn.py 'command; command'   (prints output)"""
import socket
import sys
import time

HOST = "192.168.2.15"
MARK = "__KLEE_END__"


def strip_iac(b):
    out = bytearray()
    i = 0
    while i < len(b):
        if b[i] == 255 and i + 2 < len(b):
            i += 3
            continue
        out.append(b[i])
        i += 1
    return bytes(out)


def main():
    cmd = sys.argv[1]
    s = socket.create_connection((HOST, 23), timeout=10)
    s.settimeout(2)
    time.sleep(0.5)
    try:
        s.recv(65536)
    except socket.timeout:
        pass
    s.sendall((cmd + f"; echo {MARK}\n").encode())
    buf = b""
    end = time.time() + float(sys.argv[2] if len(sys.argv) > 2 else 60)
    while time.time() < end:
        try:
            d = s.recv(65536)
            if not d:
                break
            buf += d
            if buf.count(MARK.encode()) >= 2:
                break
        except socket.timeout:
            pass
    text = strip_iac(buf).decode(errors="replace")
    # drop the echoed command line
    parts = text.split(MARK)
    print(parts[1] if len(parts) > 2 else text)
    s.close()


if __name__ == "__main__":
    main()
