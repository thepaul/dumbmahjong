# dumbmahjong — design

Mahjong Solitaire for iPhone and iPad, without the nonsense: no ads, no in-app
purchases, no accounts, no network, no confetti.

## Principles

- **Calm.** Animations are short (≤ 200 ms) and functional: a selection tint, a quick
  fade/lift when a pair is removed. No particles, no sound by default, no
  "AMAZING!" banners. Respect Reduce Motion.
- **Fair.** Every deal is solvable by construction. Undo is unlimited and free.
- **Legible.** Tiles must be easy to read and you must be able to tell at a glance
  how they stack and which ones are free.
- **Offline and private.** No networking code at all. Stats live on the device.

## Rules (standard Shanghai / Mahjong Solitaire)

- 144 tiles: 4 copies each of the 34 suit/honor tiles (dots, bamboo, characters
  1–9; four winds; three dragons) plus 4 unique Flowers and 4 unique Seasons.
- Two tiles match if they have the same face, or if both are Flowers, or both are
  Seasons.
- A tile is **free** when no tile sits on top of it (even partly) and its left or
  right side is open (no tile at the same height touching it on that side, even
  partly).
- Remove matching pairs of free tiles. You win when the board is empty.

## Architecture

```
dumbmahjong/
  MahjongCore/          Swift package, no UIKit/SwiftUI. Fully unit-tested.
    Layout              Positions in half-tile grid units, plus loader
    Tiles               Face kinds, match rule
    Board               Occupancy, free-tile computation
    DealGenerator       Seeded, solvable-by-construction deals
    Solver              Bounded DFS, used for hints and tests
    Game                State + move history (undo/redo/restart), Codable
    Layouts/*.json      Bundled layouts (package resources)
  App/                  SwiftUI app shell (menus, settings, stats)
    SpriteBoard/        2.5D SpriteKit board renderer
    Tilesets.xcassets   Rasterized faces per tileset (generated)
  tools/                Asset pipeline (build_tileset.py), tileset sources
```

The core is plain Swift, so `swift test` runs on CI without a simulator. The
renderer gets an immutable board snapshot (positions, faces, free/selected flags)
and reports taps as position indices. Both renderer spikes can plug into the same
game logic.

Target: iOS 18+, Swift 6, SwiftUI app lifecycle. Code is MIT-licensed; distribution
is via the App Store (free, no IAP).

### Layouts

A layout is a list of tile positions `(x, y, z)`. `x` and `y` are in **half-tile**
units, so a tile at `(x, y)` covers the 2×2 cells `[x, x+2) × [y, y+2)`. This
handles the half-offset tiles that classic layouts need (such as the Turtle's
end tiles and its peak). It is stored as JSON in `MahjongCore/Sources/MahjongCore/Layouts/`:

```json
{ "id": "turtle", "name": "Turtle", "positions": [[2,0,0], [4,0,0], ...] }
```

Validation (unit test + `tools/` script): exactly 144 positions, no two tiles
overlapping on the same layer, and every tile above layer 0 fully supported.

**Turtle** (144 tiles), in whole-tile units (multiply by 2 for the file):

| Layer | Tiles | Shape |
|---|---|---|
| 0 | 87 | Rows 0–7 spanning cols 1–12, 3–10, 2–11, 1–12, 1–12, 2–11, 3–10, 1–12; plus one tile at col 0 and two at cols 13, 14, all at row 3.5 |
| 1 | 36 | 6×6, cols 4–9, rows 1–6 |
| 2 | 16 | 4×4, cols 5–8, rows 2–5 |
| 3 | 4 | 2×2, cols 6–7, rows 3–4 |
| 4 | 1 | col 6.5, row 3.5 |

### Free-tile rule

For each tile, precompute (once per layout) three sets of neighbors: tiles that
overlap it from layer z+1, tiles touching its left edge on layer z, and tiles
touching its right edge on layer z. A tile is free iff it is present, no "above"
neighbor is present, and either all left neighbors or all right neighbors are
gone. That makes it O(neighbors) per tile, which is trivial at this size.

### Solvable deals

Generation runs in reverse, using only positions, and assigns faces afterwards:

1. Start with every position occupied (no faces yet).
2. Repeat: compute the free positions and pick two at random. Remove them and
   record that pair. If fewer than two positions are free while tiles remain
   (rare, e.g. a lone tower), restart with the next PRNG state.
3. You now have 72 position pairs in a valid removal order. Shuffle the 72 face
   pairs (34 kinds × 2 pairs, 2 Flower pairs, 2 Season pairs) and assign one
   face pair to each position pair.

Whether a position is free never depends on faces, so the recorded order is a
guaranteed solution. Deals are deterministic from `(layoutID, seed)` using our own
PRNG (SplitMix64 / xoshiro256**), never `SystemRandomNumberGenerator`. That gives
us reproducible bugs, "restart this deal", and shareable deal numbers.

Note: the deal is solvable, but because each face has four copies the *player*
can still pair them in a way that leads to a dead end. That is normal for the
genre, and it's why undo is unlimited and stuck detection exists. Difficulty
tuning (for example, preferring pairs that are far apart or on different layers
during generation) can come later.

### Solver

A depth-first search over removal moves, with memoization on the
present-tile bitset (a 144-bit key) and a node/time budget. It is used for:

- **Hint:** suggest a pair that keeps the game winnable when the solver can
  show that within budget; otherwise suggest any available pair.
- **Tests:** checking generator output and fuzzing the rules.

### Game state, undo, redo

`Game` holds `layoutID`, `seed`, the dealt faces, `removed: [Pair]` (history), and
`redo: [Pair]`. A move appends to history and clears redo. Undo pops history and
pushes redo; redo does the reverse; restart moves everything back. Undo depth has
no limit. The whole thing is `Codable` and saved after every move (Application
Support, atomic write), so killing the app never loses a game.

### Rendering

**2.5D SpriteKit** (chosen after spiking it against RealityKit 3D; see
`docs/spikes/renderers.md`). Fixed oblique view like GNOME Mahjongg/Kyodai.
Each tile is a pre-rendered Core Graphics body (rounded ivory top, extruded
ivory-and-green sides, soft drop shadow) with the face art on top. Each layer is
shifted a little up-left, so stacks read clearly. Draw order is `(z, x+y, x)`,
which handles half-offset tiles correctly. Taps are hit-tested in board
coordinates, and the front-most tile wins.

The renderer only sees an immutable `BoardState` and reports taps as tile
indices. Selection and matching live in `GameModel`.

**Interaction:** tap a free tile to select it (tint). Tap a matching free tile to
remove both. Tap a different non-matching free tile to move the selection. Tap a
blocked tile for a tiny shake, and nothing else. Optional setting: dim blocked
tiles.

**Screen fit:** the board scales to the largest size that fits the safe area,
upright by default. With the "Turn Board Sideways in Portrait" setting (iPhone
only, off by default), when upright tiles would be narrower than 36 pt and a
quarter turn makes them at least 20% bigger, the whole board turns 90°
counterclockwise (faces sideways, tops toward the left edge). In practice that
affects iPhone portrait only. Pinch zooms up to 3× around the pinch point; pan
works only while zoomed; pinch and pan run together, and pinching back to 1×
recenters. A drag cancels the touch, so it never taps a tile. Zoom is a
fallback, not the main way to play.

### UI

A single game screen with a slim toolbar: **New**, **Undo**, **Redo**, **Hint**,
and a menu (Restart deal, Layout, Stats, Settings). Optional timer, hidden
unless turned on. When no moves are left, a quiet banner says "No moves left"
with an Undo button. Winning shows a small card with the time and a New Game
button.

### Stats & settings

Stats per layout (`MahjongCore.Stats`, saved as JSON): played, won, win rate,
best and average time, current and best streak. A game counts as played at its
first move; starting something else while it's unfinished (new game, restart,
another deal) counts as abandoning it and ends the streak.

The play clock runs from the first move until the board is cleared, and only
while the board is in front and uncovered (paused in the background and behind
sheets and dialogs). Times are always recorded for stats; the toolbar timer and
the time on the win card show only when the setting is on.

Settings (`@AppStorage`): show timer (off), dim blocked tiles (off), table
color (Felt, Slate, Walnut, Charcoal), haptics on match (on), and a tile set
picker once there's more than one set. There are no sounds.

### Accessibility

- **VoiceOver:** SKView publishes SpriteKit's node tree and ignores elements
  set on it, so the board view is hidden from accessibility. A transparent,
  touch-ignoring layer laid over it carries one element per uncovered tile
  ("3 Bamboo, free", "Red Dragon, blocked", with the selected trait), with
  frames that follow rotation, zoom and pan, in reading order. Double-tap
  plays the tile, and a "Free Tiles" rotor jumps between playable tiles.
  Matches (with the tile name and tiles left), blocked taps, undo/redo, hints
  and notices are announced.
- **Reduce Motion:** fades only. No lift on removal, and a tint flash instead of
  the blocked-tile shake.
- **Dynamic Type:** sheets and the win card scale fully (the card's buttons
  stack when needed). The toolbar caps at xxLarge like system toolbars, with
  the Large Content Viewer on long press, and drops the timer, then words,
  before anything would wrap or clip.

### Tile art

**Decision:** v1 ships the public-domain
[Wikimedia Commons Unicode color set](https://commons.wikimedia.org/wiki/Category:Unicode_1F000-1F02F_Mahjong_Tiles_(color))
(by Shizhao), which is complete, including all 4 Flowers and 4 Seasons.

Art in this (public, MIT) repo must be compatible with that: public domain, CC0,
MIT, or CC-BY with credits. Art under other terms (paid packs, commissions without a
PD release) goes in a **separate private repo**. The build picks it up when it's
available, so public clones and CI still build using only the public sets.

Other sources considered:

| Source | License | Flowers/Seasons | Notes |
|---|---|---|---|
| [tempai-dev/riichi-mahjong-tiles-svg](https://github.com/tempai-dev/riichi-mahjong-tiles-svg) | MIT or CC-PDDC | Seasons only as raster (set 1); no Flowers | Nicest traditional faces; a candidate for a hybrid second set |
| [FluffyStuff/riichi-mahjong-tiles](https://github.com/FluffyStuff/riichi-mahjong-tiles) | CC-BY 4.0 (per downstream credits; repo says NOASSERTION) | No | Riichi only |
| [TakSuyu/tile-art](https://github.com/TakSuyu/tile-art) | Unclear (redraw of a pixiv work) | Flowers only | License too vague to rely on |
| GNOME Mahjongg / KMahjongg / Ullrich sets | GPL | Yes | Ruled out |
| Paid packs (itch.io etc.) | Custom | Some | Private art repo only |

The asset pipeline doesn't care which set we pick. `tools/tilesets/<id>/` holds
source SVGs, `CREDITS.md`, and a manifest mapping the 42 face IDs to SVGs (plus
how to strip each source's frame and background). `tools/build_tileset.py`
renders them into `App/Tilesets.xcassets/<id>/` as face-only PNGs on transparent
backgrounds, 512 px tall, plus a `tileset` data asset with name, face aspect
ratio and credits. Generated output is committed, so building the app never
needs the tools.
