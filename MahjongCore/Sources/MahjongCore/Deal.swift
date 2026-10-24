/// A starting arrangement of faces on a layout, with a known solution.
public struct Deal: Hashable, Codable, Sendable {
    public let layoutID: String
    public let seed: UInt64
    /// The face at each layout position.
    public let faces: [Face]
    /// A removal order that clears the board, proving the deal is solvable.
    public let solution: [TilePair]

    public enum GenerationError: Error, Equatable {
        case tileCountMismatch(positions: Int, tiles: Int)
        case unpairableTiles
        case noRemovalOrder
    }

    /// Generates the deal for `seed`. The same layout, seed and tiles always
    /// give the same deal.
    ///
    /// Works backwards from positions alone: repeatedly remove two random free
    /// positions, recording each pair, until the board is empty. Freeness
    /// never depends on faces, so assigning a matching pair of faces to each
    /// recorded pair yields a deal that this order solves.
    public static func generate(
        geometry: LayoutGeometry, seed: UInt64, tiles: [Face] = Face.standardSet
    ) throws(GenerationError) -> Deal {
        let count = geometry.count
        guard tiles.count == count else {
            throw .tileCountMismatch(positions: count, tiles: tiles.count)
        }
        var rng = DealRandom(seed: seed)
        var facePairs = try matchingPairs(of: tiles, rng: &rng)
        guard let order = removalOrder(geometry: geometry, rng: &rng) else {
            throw .noRemovalOrder
        }
        rng.shuffle(&facePairs)
        var faces = Array(repeating: Face.dots1, count: count)
        for (pair, facePair) in zip(order, facePairs) {
            faces[pair.a] = facePair.0
            faces[pair.b] = facePair.1
        }
        return Deal(layoutID: geometry.layout.id, seed: seed, faces: faces, solution: order)
    }

    public static func generate(
        layout: Layout, seed: UInt64, tiles: [Face] = Face.standardSet
    ) throws(GenerationError) -> Deal {
        try generate(geometry: LayoutGeometry(layout), seed: seed, tiles: tiles)
    }

    /// Splits the tiles into matching pairs. Regular faces pair with
    /// themselves; bonus tiles are shuffled within their group, then paired.
    private static func matchingPairs(
        of tiles: [Face], rng: inout DealRandom
    ) throws(GenerationError) -> [(Face, Face)] {
        var pairs: [(Face, Face)] = []
        var groups: [Face.Bonus: [Face]] = [:]
        // Iterate in allCases order, never dictionary order, to stay deterministic.
        for face in Face.allCases {
            let n = tiles.count { $0 == face }
            if let bonus = face.bonus {
                groups[bonus, default: []] += Array(repeating: face, count: n)
            } else {
                guard n % 2 == 0 else { throw .unpairableTiles }
                pairs += Array(repeating: (face, face), count: n / 2)
            }
        }
        for bonus in [Face.Bonus.flower, .season] {
            var group = groups[bonus] ?? []
            guard group.count % 2 == 0 else { throw .unpairableTiles }
            rng.shuffle(&group)
            for i in stride(from: 0, to: group.count, by: 2) {
                pairs.append((group[i], group[i + 1]))
            }
        }
        return pairs
    }

    /// A random order of position pairs that clears the layout, or nil if
    /// every attempt ran into a dead end.
    private static func removalOrder(geometry: LayoutGeometry, rng: inout DealRandom) -> [TilePair]? {
        for _ in 0..<1000 {
            var present = TileMask(count: geometry.count, allPresent: true)
            var order: [TilePair] = []
            while !present.isEmpty {
                var free = geometry.freeTiles(in: present)
                guard free.count >= 2 else { break }
                let a = free.remove(at: rng.next(below: free.count))
                let b = free[rng.next(below: free.count)]
                present.remove(a)
                present.remove(b)
                order.append(TilePair(a, b))
            }
            if present.isEmpty {
                return order
            }
        }
        return nil
    }
}

extension Board {
    public init(deal: Deal, geometry: LayoutGeometry) {
        precondition(deal.layoutID == geometry.layout.id, "deal is for a different layout")
        self.init(geometry: geometry, faces: deal.faces)
    }
}
