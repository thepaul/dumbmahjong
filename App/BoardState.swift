import MahjongCore

/// Everything a board renderer needs to draw the current game. Renderers diff
/// successive states to decide what to animate.
struct BoardState: Equatable {
    struct Shake: Equatable {
        let index: Int
        let serial: Int
    }

    var dealSeed: UInt64
    var layout: Layout
    var faces: [Face]
    var present: TileMask
    var selected: Int?
    var shake: Shake?

    /// Back-to-front order for 2D drawing: by layer, then along the diagonal,
    /// so tiles to the right of or below a tile cover its visible sides even
    /// when they are offset by half a tile.
    static func drawOrder(for layout: Layout) -> [Int] {
        layout.positions.indices.sorted { a, b in
            let p = layout.positions[a], q = layout.positions[b]
            return (p.z, p.x + p.y, p.x) < (q.z, q.x + q.y, q.x)
        }
    }
}
