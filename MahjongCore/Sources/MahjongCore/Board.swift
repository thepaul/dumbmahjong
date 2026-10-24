/// Two tile indices removed together.
public struct TilePair: Hashable, Codable, Sendable {
    public var a: Int
    public var b: Int

    public init(_ a: Int, _ b: Int) {
        self.a = a
        self.b = b
    }
}

/// A dealt layout: which face is at each position, and which tiles remain.
public struct Board: Sendable {
    public let geometry: LayoutGeometry
    public let faces: [Face]
    public private(set) var present: TileMask

    public init(geometry: LayoutGeometry, faces: [Face]) {
        precondition(faces.count == geometry.count, "one face per position")
        self.geometry = geometry
        self.faces = faces
        present = TileMask(count: faces.count, allPresent: true)
    }

    public var layout: Layout { geometry.layout }

    public var isCleared: Bool { present.isEmpty }

    public func isFree(_ i: Int) -> Bool {
        geometry.isFree(i, in: present)
    }

    public func freeTiles() -> [Int] {
        geometry.freeTiles(in: present)
    }

    /// Whether the pair can be removed right now: two different free tiles
    /// with matching faces.
    public func canRemove(_ pair: TilePair) -> Bool {
        pair.a != pair.b && isFree(pair.a) && isFree(pair.b) && faces[pair.a].matches(faces[pair.b])
    }

    /// Every removable pair, each listed once with `a < b`.
    public func availablePairs() -> [TilePair] {
        let free = freeTiles()
        var pairs: [TilePair] = []
        for (n, i) in free.enumerated() {
            for j in free[(n + 1)...] where faces[i].matches(faces[j]) {
                pairs.append(TilePair(i, j))
            }
        }
        return pairs
    }

    public mutating func remove(_ pair: TilePair) {
        precondition(canRemove(pair), "pair is not removable")
        present.remove(pair.a)
        present.remove(pair.b)
    }

    /// Puts a removed pair back, for undo.
    public mutating func restore(_ pair: TilePair) {
        precondition(!present[pair.a] && !present[pair.b], "pair is already on the board")
        present.insert(pair.a)
        present.insert(pair.b)
    }
}

extension Board {
    /// What tapping a tile should do, given the current selection.
    public enum TapOutcome: Equatable, Sendable {
        /// The tile is gone; nothing happens.
        case ignored
        /// The tile can't be picked up yet.
        case blocked
        case select(Int)
        case deselect
        case match(TilePair)
    }

    public func outcome(ofTapping index: Int, selected: Int?) -> TapOutcome {
        guard present[index] else { return .ignored }
        guard isFree(index) else { return .blocked }
        guard let selected, present[selected] else { return .select(index) }
        if selected == index {
            return .deselect
        }
        let pair = TilePair(selected, index)
        return canRemove(pair) ? .match(pair) : .select(index)
    }
}
