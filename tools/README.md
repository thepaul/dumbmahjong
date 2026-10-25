# tools

Scripts for building assets and checking layouts. Each script documents its
own dependencies (for example `rsvg-convert` from `brew install librsvg`). Their
outputs are committed, so building the app never requires running them.

- `build_layouts.py` compiles the layout drawings in `layouts/` into the JSON
  bundled with MahjongCore. It needs only Python 3.
