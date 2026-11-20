#!/usr/bin/python3
from pathlib import Path
import subprocess
import sys


master = Path(__file__).resolve().parents[1] / "docs" / "icon.png"
directory = Path(sys.argv[1])
iconset = directory / "Secret.iconset"
iconset.mkdir(parents=True, exist_ok=True)

for size in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        suffix = "@2x" if scale == 2 else ""
        filename = iconset / f"icon_{size}x{size}{suffix}.png"
        pixels = str(size * scale)
        subprocess.run(
            ["/usr/bin/sips", "-z", pixels, pixels, str(master), "--out", str(filename)],
            check=True,
            stdout=subprocess.DEVNULL,
        )

subprocess.run(
    ["/usr/bin/iconutil", "-c", "icns", str(iconset), "-o", str(directory / "Secret.icns")],
    check=True,
)
