import Foundation

/// A tile slot in a layout, in half-tile units: a tile at `(x, y)` covers the
/// cells `[x, x+2) × [y, y+2)` on layer `z`. Half units let layouts place tiles
/// offset by half a tile, as the Turtle's end caps and peak are.
///
/// Encoded in JSON as `[x, y, z]`.
public struct Position: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var z: Int

    public init(x: Int, y: Int, z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// Whether the footprints of the two positions overlap, ignoring layers.
    func overlapsFootprint(of other: Position) -> Bool {
        abs(x - other.x) < 2 && abs(y - other.y) < 2
    }
}

extension Position: Codable {
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        self.init(x: try c.decode(Int.self), y: try c.decode(Int.self), z: try c.decode(Int.self))
        if !c.isAtEnd {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Position must be [x, y, z]")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x)
        try c.encode(y)
        try c.encode(z)
    }
}

/// An arrangement of tile slots, such as the Turtle.
public struct Layout: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var positions: [Position]

    public init(id: String, name: String, positions: [Position]) {
        self.id = id
        self.name = name
        self.positions = positions
    }

    public enum ValidationError: Error, Equatable {
        case oddTileCount(Int)
        case negativeCoordinate(index: Int)
        case overlapping(Int, Int)
        case unsupported(index: Int)
    }

    /// Checks that the layout can be played: an even number of tiles, no two
    /// tiles overlapping on the same layer, and every tile above layer 0
    /// resting entirely on tiles one layer down.
    public func validate() throws(ValidationError) {
        if positions.count % 2 != 0 {
            throw .oddTileCount(positions.count)
        }
        for (i, p) in positions.enumerated() {
            if p.x < 0 || p.y < 0 || p.z < 0 {
                throw .negativeCoordinate(index: i)
            }
            for j in positions.indices where j > i {
                let q = positions[j]
                if p.z == q.z && p.overlapsFootprint(of: q) {
                    throw .overlapping(i, j)
                }
            }
            if p.z > 0 {
                let below = positions.filter { $0.z == p.z - 1 }
                for cx in p.x..<(p.x + 2) {
                    for cy in p.y..<(p.y + 2) {
                        let covered = below.contains { b in
                            (b.x..<(b.x + 2)).contains(cx) && (b.y..<(b.y + 2)).contains(cy)
                        }
                        if !covered {
                            throw .unsupported(index: i)
                        }
                    }
                }
            }
        }
    }
}

extension Layout {
    /// Layouts shipped with the game, in menu order.
    public static let bundled: [Layout] = bundledIDs.map(loadBundled)

    public static var turtle: Layout { bundled(id: "turtle")! }

    public static func bundled(id: String) -> Layout? {
        bundled.first { $0.id == id }
    }

    private static let bundledIDs = ["turtle", "pyramid", "fortress", "rows"]

    private static func loadBundled(id: String) -> Layout {
        guard let url = Bundle.module.url(forResource: id, withExtension: "json", subdirectory: "Layouts") else {
            fatalError("Missing bundled layout \(id)")
        }
        do {
            return try JSONDecoder().decode(Layout.self, from: Data(contentsOf: url))
        } catch {
            fatalError("Bad bundled layout \(id): \(error)")
        }
    }
}
