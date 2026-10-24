#!/usr/bin/env python3 -I
"""Build a tileset's face images into the app's asset catalog.

Usage: python3 -I tools/build_tileset.py <tileset-dir> [--out App/Tilesets.xcassets]

<tileset-dir> holds manifest.json, CREDITS.md and an svg/ folder. The manifest:

    {
      "id": "commons",            # namespace in the asset catalog
      "name": "Commons",          # shown in Settings
      "sourceSize": [75, 95.1],   # source tile size in SVG units
      "inset": 2.75,              # SVG units cropped off each edge (removes frames)
      "background": "white",      # flattened, then turned transparent; or null
      "frameCorner": {"center": 6, "radius": 3.75},
                                  # optional: clear everything outside the
                                  # frame's rounded inner corners (SVG units,
                                  # center measured from each edge)
      "faces": {"dots1": {"source": "MJ1bing.svg"}, ...}
    }

Each face becomes <out>/<id>/<face>.imageset/<face>.png: just the art on a
transparent background, cropped to the tile's face area. The renderer draws
the tile body itself, so every tileset shares one look. tileset.json (as a
data asset) records the name, face aspect ratio and credits.

Requires rsvg-convert and ImageMagick 7 (brew install librsvg imagemagick).
"""
import argparse
import json
import pathlib
import shutil
import subprocess
import tempfile

FACE_HEIGHT = 512  # px; comfortably above the largest on-screen tile at @3x

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG_INFO = {"info": {"author": "xcode", "version": 1}}


def write_json(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2) + "\n")


def render_face(svg, out_png, source_size, inset, background, frame_corner):
    src_w, src_h = source_size
    scale = FACE_HEIGHT / (src_h - 2 * inset)
    full_h = round(src_h * scale)
    crop = round(inset * scale)
    with tempfile.TemporaryDirectory() as tmp:
        full = pathlib.Path(tmp) / "full.png"
        subprocess.run(["rsvg-convert", "-h", str(full_h), "-o", full, svg], check=True)
        cmd = ["magick", full]
        if background:
            cmd += ["-background", background, "-alpha", "remove"]
        cmd += ["-gravity", "center", "-crop", f"0x{FACE_HEIGHT}+0+0", "+repage",
                "-shave", f"{crop}x0", "+repage"]
        if background == "white":
            # "Color to alpha" for white: alpha is how far the pixel is from
            # white, and the color is un-blended so anti-aliased ink keeps its
            # true color over any tile body.
            cmd += [
                "(", "-clone", "0", "-fx", "max(max(1-r,1-g),1-b)", ")",
                "(", "-clone", "0,1", "-fx", "v==0 ? 0 : 1-(1-u)/v", ")",
                "-delete", "0", "-swap", "0,1",
                "-alpha", "off", "-compose", "CopyOpacity", "-composite",
            ]
        if frame_corner:
            c = (frame_corner["center"] - inset) * scale
            r = frame_corner["radius"] * scale
            dx = f"max(max({c}-i,i-(w-1-{c})),0)"
            dy = f"max(max({c}-j,j-(h-1-{c})),0)"
            cmd += ["-channel", "A", "-fx", f"hypot({dx},{dy}) > {r} ? 0 : u", "+channel"]
        cmd += ["-define", "png:color-type=6", "-strip", out_png]
        subprocess.run(cmd, check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("tileset_dir", type=pathlib.Path)
    parser.add_argument("--out", type=pathlib.Path, default=ROOT / "App" / "Tilesets.xcassets")
    args = parser.parse_args()

    src = args.tileset_dir.resolve()
    manifest = json.loads((src / "manifest.json").read_text())
    out = args.out / manifest["id"]
    if out.exists():
        shutil.rmtree(out)

    write_json(args.out / "Contents.json", CATALOG_INFO)
    write_json(out / "Contents.json", {**CATALOG_INFO, "properties": {"provides-namespace": True}})

    for face, entry in sorted(manifest["faces"].items()):
        imageset = out / f"{face}.imageset"
        imageset.mkdir(parents=True)
        render_face(src / "svg" / entry["source"], imageset / f"{face}.png",
                    manifest["sourceSize"], manifest["inset"], manifest.get("background"),
                    manifest.get("frameCorner"))
        write_json(imageset / "Contents.json", {
            **CATALOG_INFO,
            "images": [{"filename": f"{face}.png", "idiom": "universal"}],
        })
        print(face)

    src_w, src_h = manifest["sourceSize"]
    inset = manifest["inset"]
    info = {
        "id": manifest["id"],
        "name": manifest["name"],
        "faceAspect": round((src_w - 2 * inset) / (src_h - 2 * inset), 4),
        "credits": (src / "CREDITS.md").read_text(),
    }
    write_json(out / "tileset.dataset" / "tileset.json", info)
    write_json(out / "tileset.dataset" / "Contents.json", {
        **CATALOG_INFO,
        "data": [{"filename": "tileset.json", "idiom": "universal"}],
    })


if __name__ == "__main__":
    main()
