import MahjongCore

/// Everything a board renderer needs to draw the current game. Renderers diff
/// successive states to decide what to animate.
struct BoardState: Equatable {
    /// A one-off effect on some tiles. A new serial retriggers it.
    struct Pulse: Equatable {
        let tiles: [Int]
        let serial: Int
    }

    var dealSeed: UInt64
    var layout: Layout
    var faces: [Face]
    var present: TileMask
    var free: TileMask
    var selected: Int?
    /// A tap on a blocked tile.
    var shake: Pulse?
    var hint: Pulse?
    /// Setting: draw blocked tiles darker so free ones stand out.
    var dimBlocked = false
    var tableColor = TableColor.felt

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
