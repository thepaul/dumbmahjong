/// Neighbor relationships for a layout, computed once and used to decide which
/// tiles are free.
public struct LayoutGeometry: Sendable {
    public let layout: Layout
    /// Tiles one layer up whose footprint overlaps this tile.
    public let above: [[Int]]
    /// Tiles on the same layer touching this tile's left edge.
    public let left: [[Int]]
    /// Tiles on the same layer touching this tile's right edge.
    public let right: [[Int]]

    public init(_ layout: Layout) {
        self.layout = layout
        let ps = layout.positions
        var above = Array(repeating: [Int](), count: ps.count)
        var left = above
        var right = above
        for (i, p) in ps.enumerated() {
            for (j, q) in ps.enumerated() where j != i {
                if q.z == p.z + 1 && p.overlapsFootprint(of: q) {
                    above[i].append(j)
                } else if q.z == p.z && abs(q.y - p.y) < 2 {
                    if q.x == p.x - 2 {
                        left[i].append(j)
                    } else if q.x == p.x + 2 {
                        right[i].append(j)
                    }
                }
            }
        }
        self.above = above
        self.left = left
        self.right = right
    }

    public var count: Int { layout.positions.count }

    /// A tile is free when it is present, nothing above it is present, and
    /// either its whole left side or its whole right side is open.
    public func isFree(_ i: Int, in present: TileMask) -> Bool {
        present[i]
            && !above[i].contains { present[$0] }
            && (!left[i].contains { present[$0] } || !right[i].contains { present[$0] })
    }

    public func freeTiles(in present: TileMask) -> [Int] {
        (0..<count).filter { isFree($0, in: present) }
    }
}
