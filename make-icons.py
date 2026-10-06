#!/usr/bin/env python3
"""Genera los iconos (puntos de color) que se muestran en las notificaciones.

Solo usa la librería estándar, sin dependencias. Uso:

    python3 make-icons.py [directorio_salida]

El directorio por defecto es ~/.pr-watcher/icons.
"""
import struct, zlib, os, sys

def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

def make_circle_png(path, r, g, b, size=64, dot_radius=8.0):
    cx = cy = size / 2.0
    radius = dot_radius
    rows = []
    for y in range(size):
        row = bytearray([0])  # filter byte
        for x in range(size):
            dx = x + 0.5 - cx
            dy = y + 0.5 - cy
            d = (dx * dx + dy * dy) ** 0.5
            if d <= radius - 1.0:
                a = 255
            elif d >= radius + 1.0:
                a = 0
            else:
                a = int(255 * (1.0 - (d - (radius - 1.0)) / 2.0))
            row += bytes([r, g, b, a])
        rows.append(bytes(row))
    raw = b"".join(rows)
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)
    print("wrote", path)

out = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.pr-watcher/icons")
os.makedirs(out, exist_ok=True)
make_circle_png(os.path.join(out, "approved.png"), 52, 199, 89)
make_circle_png(os.path.join(out, "changes.png"), 255, 149, 0)
make_circle_png(os.path.join(out, "comment.png"), 0, 122, 255)
make_circle_png(os.path.join(out, "none.png"), 142, 142, 147)
make_circle_png(os.path.join(out, "review.png"), 175, 82, 222)
