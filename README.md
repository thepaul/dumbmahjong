# dumbmahjong

Mahjong Solitaire for iPhone and iPad, without the nonsense. No ads, no in-app
purchases, no accounts, no network access, and no fireworks every time you match
a pair. Just pleasant tiles, deals that are always solvable, and unlimited undo.

See [DESIGN.md](DESIGN.md) for the design and the
[issues](https://github.com/thepaul/dumbmahjong/issues) for the work plan.

## Layout

| Path | What |
|---|---|
| `App/` | SwiftUI app target (an Xcode synchronized folder: new files are picked up automatically) |
| `MahjongCore/` | Swift package with all game logic. No UIKit/SwiftUI. |
| `Resources/Layouts/` | Board layouts (JSON) |
| `Resources/Tilesets/` | Rasterized tile faces plus credits |
| `tools/` | Asset and layout scripts |

## Building

Requires Xcode 16 or later. Deployment target is iOS 18.

```sh
# Core logic tests (no simulator needed)
swift test --package-path MahjongCore

# App build
xcodebuild -project DumbMahjong.xcodeproj -scheme DumbMahjong \
  -destination 'generic/platform=iOS Simulator' build
```

To run on a device, open `DumbMahjong.xcodeproj` and pick your team under
Signing & Capabilities.

## License

Code is under the [MIT license](LICENSE). Tile art is under its own terms. See
`CREDITS.md` in each tileset directory.
