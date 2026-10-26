/// Searches for a way to clear the board from its current position. Used to
/// give hints that keep the game winnable, and to check deals in tests.
///
/// Follows the "practical algorithm" of de Bondt, *Solving Mahjong Solitaire
/// boards with peeking* (arXiv:1203.6559). Rather than searching over moves,
/// it searches over pairings: the four remaining tiles of a kind can be split
/// into two pairs in only three ways, and once every kind's pairing is fixed,
/// removing any removable pair never hurts, so a greedy pass decides the rest.
/// Kinds down to two tiles already have their pairing.
///
/// What makes it fast is the pruning scan, a relaxed game that can't be lost
/// by choosing badly: kinds with a pairing remove their pairs as usual, while
/// each other kind removes any two of its tiles once both are free, then its
/// last two one at a time. If even that can't clear the board, no real play
/// can. Before branching, every open pairing of every kind is tried against
/// the scan; pairings that fail are ruled out for the whole subtree, a kind
/// left with one pairing takes it without branching, and the search branches
/// on the kind that has had the most pairings ruled out so far, relative to
/// how many it has left. (The paper finds critical kinds differently; this
/// conflict count did better here.)
///
/// Given a `guide` (a known solution of the deal, such as `Deal.solution`),
/// each kind tries the pairing the guide uses first.
public struct Solver: Sendable {
    public enum Result: Equatable, Sendable {
        /// A sequence of moves that clears the board.
        case solvable([TilePair])
        case unsolvable
        /// Gave up: ran out of budget or was cancelled.
        case unknown
    }

    /// The most branching points to visit before giving up.
    public var maxNodes: Int
    public var timeLimit: Duration

    public init(maxNodes: Int = 100_000, timeLimit: Duration = .seconds(2)) {
        self.maxNodes = maxNodes
        self.timeLimit = timeLimit
    }

    public func solve(_ board: Board, guide: [TilePair]? = nil) -> Result {
        var search = Search(board: board, guide: guide, maxNodes: maxNodes,
                            deadline: ContinuousClock.now.advanced(by: timeLimit))
        var pairing = search.initialPairing
        var ruledOut = Array(repeating: UInt8(0), count: search.kinds.count)
        switch search.run(&pairing, ruledOut: &ruledOut) {
        case .solved: return .solvable(search.removalOrder(pairing))
        case .dead: return .unsolvable
        case .gaveUp: return .unknown
        }
    }
}

/// Up to 256 tiles as a fixed-size bitset, so the scan never allocates.
private struct Bits: Equatable {
    var w0: UInt64 = 0, w1: UInt64 = 0, w2: UInt64 = 0, w3: UInt64 = 0

    static let capacity = 256

    init() {}

    init(_ indices: some Sequence<Int>) {
        for i in indices {
            insert(i)
        }
    }

    subscript(i: Int) -> Bool {
        let bit = UInt64(1) << UInt64(i & 63)
        switch i >> 6 {
        case 0: return w0 & bit != 0
        case 1: return w1 & bit != 0
        case 2: return w2 & bit != 0
        default: return w3 & bit != 0
        }
    }

    mutating func insert(_ i: Int) {
        let bit = UInt64(1) << UInt64(i & 63)
        switch i >> 6 {
        case 0: w0 |= bit
        case 1: w1 |= bit
        case 2: w2 |= bit
        default: w3 |= bit
        }
    }

    mutating func remove(_ i: Int) {
        let bit = ~(UInt64(1) << UInt64(i & 63))
        switch i >> 6 {
        case 0: w0 &= bit
        case 1: w1 &= bit
        case 2: w2 &= bit
        default: w3 &= bit
        }
    }

    func intersects(_ other: Bits) -> Bool {
        (w0 & other.w0) | (w1 & other.w1) | (w2 & other.w2) | (w3 & other.w3) != 0
    }

    var isEmpty: Bool { (w0 | w1 | w2 | w3) == 0 }
}

private struct Search {
    enum Outcome {
        case solved, dead, gaveUp
    }

    /// The three ways to split four tiles into two pairs, as the partner of
    /// each of the four positions.
    static let partners: [[Int]] = [[1, 0, 3, 2], [2, 3, 0, 1], [3, 2, 1, 0]]

    let geometry: LayoutGeometry
    let start: Bits
    let above: [Bits]
    let left: [Bits]
    let right: [Bits]
    /// Remaining tiles of each kind that matter: two or four.
    let kinds: [[Int]]
    /// Which kind each tile belongs to, and its place within the kind.
    let kindOf: [Int]
    let placeOf: [Int]
    /// The guide's pairing of each four-tile kind, if it has one.
    let preferred: [Int?]
    /// Pairing per kind before any search: fixed (0) for two-tile kinds,
    /// open (-1) for four.
    let initialPairing: [Int]
    let maxNodes: Int
    let deadline: ContinuousClock.Instant
    var nodes = 0
    var scans = 0
    /// How often each kind has had a pairing ruled out, anywhere in the search.
    var conflicts: [Int]

    init(board: Board, guide: [TilePair]?, maxNodes: Int, deadline: ContinuousClock.Instant) {
        precondition(board.faces.count <= Bits.capacity, "layout too large for the solver")
        geometry = board.geometry
        let count = board.faces.count
        let present = (0..<count).filter { board.present[$0] }
        start = Bits(present)
        above = geometry.above.map(Bits.init)
        left = geometry.left.map(Bits.init)
        right = geometry.right.map(Bits.init)

        var kinds: [[Int]] = []
        for i in present {
            if let k = kinds.firstIndex(where: { board.faces[$0[0]].matches(board.faces[i]) }) {
                kinds[k].append(i)
            } else {
                kinds.append([i])
            }
        }
        var kindOf = Array(repeating: -1, count: count)
        var placeOf = Array(repeating: -1, count: count)
        for (k, tiles) in kinds.enumerated() {
            for (n, i) in tiles.enumerated() {
                kindOf[i] = k
                placeOf[i] = n
            }
        }
        precondition(kinds.allSatisfy { $0.count == 2 || $0.count == 4 }, "kinds come in twos and fours")
        self.kinds = kinds
        self.kindOf = kindOf
        self.placeOf = placeOf
        initialPairing = kinds.map { $0.count == 4 ? -1 : 0 }

        var preferred = Array(repeating: Int?.none, count: kinds.count)
        for pair in guide ?? [] where board.present[pair.a] && board.present[pair.b] {
            let k = kindOf[pair.a]
            guard kinds[k].count == 4, kindOf[pair.b] == k else { continue }
            preferred[k] = Self.partners.firstIndex { $0[placeOf[pair.a]] == placeOf[pair.b] }
        }
        self.preferred = preferred
        conflicts = Array(repeating: 0, count: kinds.count)
        self.maxNodes = maxNodes
        self.deadline = deadline
    }

    /// Searches for pairings that clear the board, filling in `pairing`.
    /// `ruledOut` holds, per kind, a bit for each pairing known to fail.
    mutating func run(_ pairing: inout [Int], ruledOut: inout [UInt8]) -> Outcome {
        nodes += 1
        if nodes > maxNodes || ContinuousClock.now > deadline || Task.isCancelled {
            return .gaveUp
        }
        guard scan(pairing) else { return .dead }

        // Rule out pairings the scan rejects, settling any kind left with one,
        // until nothing changes; remember the kind with the fewest left.
        var branch = -1
        var changed = true
        while changed {
            changed = false
            branch = -1
            var best = 0.0
            for k in kinds.indices where pairing[k] < 0 {
                for p in 0..<3 where ruledOut[k] & (1 << p) == 0 {
                    pairing[k] = p
                    if !scan(pairing) {
                        ruledOut[k] |= 1 << p
                        conflicts[k] += 1
                    }
                    pairing[k] = -1
                }
                let left = (0..<3).filter { ruledOut[k] & (1 << $0) == 0 }
                switch left.count {
                case 0:
                    return .dead
                case 1:
                    pairing[k] = left[0]
                    changed = true
                default:
                    let score = Double(conflicts[k] + 1) / Double(left.count)
                    if score > best {
                        best = score
                        branch = k
                    }
                }
            }
            if scans > 4096 {
                scans = 0
                if ContinuousClock.now > deadline || Task.isCancelled {
                    return .gaveUp
                }
            }
        }
        // Every kind has a pairing and the scan passed, so it's exact.
        guard branch >= 0 else { return .solved }

        var options = (0..<3).filter { ruledOut[branch] & (1 << $0) == 0 }
        if let p = preferred[branch], let n = options.firstIndex(of: p) {
            options.swapAt(0, n)
        }
        for p in options {
            var childPairing = pairing
            var childRuledOut = ruledOut
            childPairing[branch] = p
            switch run(&childPairing, ruledOut: &childRuledOut) {
            case .solved:
                pairing = childPairing
                return .solved
            case .gaveUp:
                return .gaveUp
            case .dead:
                // Pairings this one ruled out may still work with another.
                ruledOut[branch] |= 1 << p
            }
        }
        return .dead
    }

    func isFree(_ i: Int, in present: Bits) -> Bool {
        !above[i].intersects(present) && (!left[i].intersects(present) || !right[i].intersects(present))
    }

    /// The pruning scan: whether the board can be cleared when kinds with a
    /// pairing play by it and the others relax as described above. With every
    /// pairing fixed there is nothing left to relax, and this is exact.
    mutating func scan(_ pairing: [Int]) -> Bool {
        scans += 1
        var present = start
        // Open kinds that have already given up their first two tiles.
        var split = Bits()
        var progress = true
        while progress && !present.isEmpty {
            progress = false
            var free = Bits()
            for k in kinds.indices {
                for i in kinds[k] where present[i] && isFree(i, in: present) {
                    free.insert(i)
                }
            }
            for k in kinds.indices {
                let tiles = kinds[k]
                if pairing[k] >= 0 {
                    let partner = Self.partners[pairing[k]]
                    for n in tiles.indices where free[tiles[n]] && present[tiles[n]] {
                        let m = partner[n]
                        if free[tiles[m]] {
                            present.remove(tiles[n])
                            present.remove(tiles[m])
                            progress = true
                        }
                    }
                } else if split[k] {
                    for i in tiles where free[i] && present[i] {
                        present.remove(i)
                        progress = true
                    }
                } else {
                    var first = -1
                    for i in tiles where free[i] {
                        if first < 0 {
                            first = i
                        } else {
                            present.remove(first)
                            present.remove(i)
                            split.insert(k)
                            progress = true
                            break
                        }
                    }
                }
            }
        }
        return present.isEmpty
    }

    /// An order of moves that clears the board with every kind's pairing
    /// fixed: repeatedly remove whichever pairs are free.
    func removalOrder(_ pairing: [Int]) -> [TilePair] {
        var present = start
        var order: [TilePair] = []
        while !present.isEmpty {
            let before = order.count
            let free = Bits((0..<kindOf.count).filter { present[$0] && isFree($0, in: present) })
            for (k, tiles) in kinds.enumerated() {
                let partner = Self.partners[pairing[k]]
                for n in tiles.indices {
                    let m = partner[n]
                    if n < m && free[tiles[n]] && free[tiles[m]] && present[tiles[n]] {
                        present.remove(tiles[n])
                        present.remove(tiles[m])
                        order.append(TilePair(tiles[n], tiles[m]))
                    }
                }
            }
            precondition(order.count > before, "pairing doesn't clear the board")
        }
        return order
    }
}
