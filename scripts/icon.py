#!/usr/bin/python3
"""Draw the app icon without dependencies."""

import math
from pathlib import Path
import struct
import subprocess
import sys
import zlib


def chunk(name, data):
    return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name + data) & 0xFFFFFFFF)


def pixel(x, y):
    dx = max(abs(x - 0.5) - 0.275, 0)
    dy = max(abs(y - 0.5) - 0.275, 0)
    if math.hypot(dx, dy) > 0.175:
        return (0, 0, 0, 0)
    background = round(44 + 16 * (1 - y))
    ring = 0.069 < math.hypot(x - 0.395, y - 0.395) < 0.133
    diagonal = x + y
    shaft = 0.075 > abs(x - y) and 0.84 < diagonal < 1.355
    tooth_one = 0.58 < x < 0.665 and 0.635 < y < 0.71
    tooth_two = 0.655 < x < 0.73 and 0.675 < y < 0.75
    return (239, 241, 246, 255) if ring or shaft or tooth_one or tooth_two else (background, background + 3, background + 10, 255)


def png(size):
    data = bytearray()
    for y in range(size):
        data.append(0)
        for x in range(size):
            data.extend(pixel((x + 0.5) / size, (y + 0.5) / size))
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(bytes(data), 9)) + chunk(b"IEND", b"")


directory = Path(sys.argv[1])
iconset = directory / "Secret.iconset"
iconset.mkdir(parents=True, exist_ok=True)
for size in (16, 32, 128, 256, 512):
    (iconset / ("icon_%dx%d.png" % (size, size))).write_bytes(png(size))
    (iconset / ("icon_%dx%d@2x.png" % (size, size))).write_bytes(png(size * 2))
subprocess.run(["/usr/bin/iconutil", "-c", "icns", str(iconset), "-o", str(directory / "Secret.icns")], check=True)
