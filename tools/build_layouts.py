#!/usr/bin/env python3 -I
"""Compile layouts drawn as text into the JSON the game bundles.

Usage: python3 -I tools/build_layouts.py [<layout.txt> ...] [--out DIR]
       python3 -I tools/build_layouts.py --show <layout.json>

With no inputs, builds every tools/layouts/*.txt into
MahjongCore/Sources/MahjongCore/Layouts/<id>.json, where the id is the file's
stem. --show prints an existing JSON layout in the text format, which is handy
for checking a design or starting a new one from an old one.

A layout file names the layout, then draws each layer from the bottom up:

    // Comment lines start with '//' and aren't part of any drawing.
    name: Pyramid

    layer
    ##########
    ##########
     ########
     ########

    layer
    ...

Each character is a half-tile cell, so a tile is a 2x2 block of any
non-blank character ('.' and ' ' are blank). Every layer shares the same
origin: column 0 of the line right after "layer". Blank lines inside a layer
are empty rows. Blocks are read greedily, top to bottom and left to right, so
"######" is three tiles side by side, and a block that starts a column or row
late is a tile offset by half. Positions are written in that same order,
layer by layer, and the order matters: deals are generated from it, so
changing a shipped layout changes its deals.
"""
import argparse
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "tools" / "layouts"
OUT = ROOT / "MahjongCore" / "Sources" / "MahjongCore" / "Layouts"
BLANK = " ."


class LayoutError(Exception):
    pass


def parse(text, source):
    name = None
    layers = []
    for lineno, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        if stripped == "layer":
            layers.append([])
        elif layers:
            layers[-1].append((lineno, line.rstrip()))
        elif stripped.startswith("name:"):
            name = stripped[len("name:"):].strip()
        elif stripped:
            raise LayoutError(f"{source}:{lineno}: expected 'name:' or 'layer'")
    if not name:
        raise LayoutError(f"{source}: missing 'name:'")
    if not layers:
        raise LayoutError(f"{source}: no layers")

    positions = []
    for z, rows in enumerate(layers):
        cells = {(x, y) for y, (_, row) in enumerate(rows)
                 for x, ch in enumerate(row) if ch not in BLANK}
        width = max((len(r) for _, r in rows), default=0)
        for y, (lineno, _) in enumerate(rows):
            for x in range(width):
                if (x, y) not in cells:
                    continue
                block = {(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)}
                if not block <= cells:
                    raise LayoutError(
                        f"{source}:{lineno}: layer {z}: the cell at column {x} "
                        "doesn't start a complete 2x2 tile")
                cells -= block
                positions.append([x, y, z])
        if not any(p[2] == z for p in positions):
            raise LayoutError(f"{source}: layer {z} is empty")
    return name, positions


def validate(positions, source):
    """Mirrors Layout.validate() so mistakes show up before the tests run."""
    if len(positions) % 2:
        raise LayoutError(f"{source}: odd tile count {len(positions)}")
    covered = {}
    for x, y, z in positions:
        for cell in [(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)]:
            covered.setdefault(z, set()).add(cell)
    for x, y, z in positions:
        if z == 0:
            continue
        below = covered.get(z - 1, set())
        if not {(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)} <= below:
            raise LayoutError(f"{source}: tile at {[x, y, z]} isn't fully supported")


def show(positions, name):
    lines = [f"name: {name}"]
    for z in range(max(p[2] for p in positions) + 1):
        layer = [p for p in positions if p[2] == z]
        width = max(p[0] for p in positions) + 2
        height = max(p[1] for p in positions) + 2
        grid = [[" "] * width for _ in range(height)]
        for x, y, _ in layer:
            for cx, cy in [(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)]:
                grid[cy][cx] = "#"
        rows = ["".join(r).rstrip() for r in grid]
        while rows and not rows[-1]:
            rows.pop()
        lines += ["", "layer"] + rows
    return "\n".join(lines) + "\n"


def write_json(layout_id, name, positions, out):
    # One row of the drawing per JSON line, like turtle.json.
    rows = []
    for p in positions:
        if rows and rows[-1][-1][1:] == p[1:]:
            rows[-1].append(p)
        else:
            rows.append([p])
    body = ",\n".join("    " + ", ".join(json.dumps(p) for p in row)
                      for row in rows)
    text = (f'{{\n  "id": {json.dumps(layout_id)},\n  "name": {json.dumps(name)},\n'
            f'  "positions": [\n{body}\n  ]\n}}\n')
    path = out / f"{layout_id}.json"
    path.write_text(text)
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("inputs", nargs="*", type=pathlib.Path)
    parser.add_argument("--out", type=pathlib.Path, default=OUT)
    parser.add_argument("--show", type=pathlib.Path, metavar="JSON")
    args = parser.parse_args()

    if args.show:
        data = json.loads(args.show.read_text())
        sys.stdout.write(show(data["positions"], data["name"]))
        return

    inputs = args.inputs or sorted(SOURCES.glob("*.txt"))
    try:
        for src in inputs:
            name, positions = parse(src.read_text(), src)
            validate(positions, src)
            path = write_json(src.stem, name, positions, args.out)
            print(f"{path.relative_to(ROOT) if path.is_relative_to(ROOT) else path}: "
                  f"{len(positions)} tiles")
    except LayoutError as e:
        sys.exit(f"error: {e}")


if __name__ == "__main__":
    main()
