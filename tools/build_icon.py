#!/usr/bin/env python3 -I
"""Build the app icon: one ivory tile on felt, in the same 2.5D style as the
board, with a face from the standard tileset.

Usage: python3 -I tools/build_icon.py [face]   (default: dragonRed)

Writes App/Assets.xcassets/AppIcon.appiconset/AppIcon.png (1024x1024). The
face PNG comes from App/Tilesets.xcassets, so build the tileset first.
Requires rsvg-convert and ImageMagick 7 (brew install librsvg imagemagick).
"""
import base64
import json
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SIZE = 1024

# Tile geometry, matching the board's proportions (TileArtwork / Metrics).
W = 500                  # top face width
H = W / 0.75             # top face height
D = W * 0.15             # visible thickness (a touch thicker than in play)
R = W * 0.1              # corner radius
X = (SIZE - W - D) / 2   # center the whole tile, thickness included
Y = (SIZE - H - D) / 2

IVORY, IVORY_SHADE, IVORY_SIDE = "#f7f0db", "#e6dbbf", "#d6c9ab"
BACK, BACK_SIDE = "#1a6b54", "#124d3d"


def rect(x, y, fill, extra=""):
    return f'<rect x="{x:.1f}" y="{y:.1f}" width="{W:.1f}" height="{H:.1f}" rx="{R:.1f}" fill="{fill}" {extra}/>'


def main():
    face = sys.argv[1] if len(sys.argv) > 1 else "dragonRed"
    face_png = ROOT / "App/Tilesets.xcassets/commons" / f"{face}.imageset" / f"{face}.png"
    face_b64 = base64.b64encode(face_png.read_bytes()).decode()

    # Extrude by stamping the outline from the back forward, as the game does.
    steps = 60
    layers = []
    for n in range(steps, 0, -1):
        t = D * n / steps
        color = BACK_SIDE if t > D * 0.9 else BACK if t > D * 0.45 else IVORY_SIDE
        layers.append(rect(X + t, Y + t, color))

    face_w = W * 0.82
    face_h = face_w / (395 / 512)
    if face_h > H * 0.86:
        face_h = H * 0.86
        face_w = face_h * (395 / 512)

    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
     width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">
  <defs>
    <radialGradient id="felt" cx="45%" cy="40%" r="75%">
      <stop offset="0" stop-color="#2f7d55"/>
      <stop offset="1" stop-color="#16472f"/>
    </radialGradient>
    <linearGradient id="top" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0.35" stop-color="{IVORY}"/>
      <stop offset="1" stop-color="{IVORY_SHADE}"/>
    </linearGradient>
    <filter id="shadow" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="{D * 0.55:.1f}"/>
    </filter>
  </defs>
  <rect width="{SIZE}" height="{SIZE}" fill="url(#felt)"/>
  {rect(X + D * 1.5, Y + D * 1.7, "#000", 'opacity="0.45" filter="url(#shadow)"')}
  {"".join(layers)}
  {rect(X, Y, "url(#top)")}
  <rect x="{X + 3:.1f}" y="{Y + 3:.1f}" width="{W - 6:.1f}" height="{H - 6:.1f}" rx="{R - 3:.1f}"
        fill="none" stroke="#fff" stroke-opacity="0.7" stroke-width="4"/>
  <image x="{X + (W - face_w) / 2:.1f}" y="{Y + (H - face_h) / 2:.1f}" width="{face_w:.1f}" height="{face_h:.1f}"
         xlink:href="data:image/png;base64,{face_b64}"/>
</svg>
'''
    out_dir = ROOT / "App/Assets.xcassets/AppIcon.appiconset"
    with tempfile.TemporaryDirectory() as tmp:
        svg_path = pathlib.Path(tmp) / "icon.svg"
        svg_path.write_text(svg)
        png = pathlib.Path(tmp) / "icon.png"
        subprocess.run(["rsvg-convert", "-w", str(SIZE), "-h", str(SIZE), "-o", png, svg_path], check=True)
        # App icons must be opaque.
        subprocess.run(["magick", png, "-alpha", "remove", "-alpha", "off", "-strip",
                        out_dir / "AppIcon.png"], check=True)
    (out_dir / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")
    print("wrote", out_dir / "AppIcon.png")


if __name__ == "__main__":
    main()
