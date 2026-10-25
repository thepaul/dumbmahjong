/// Searches for a way to clear the board from its current position. Used to
/// give hints that keep the game winnable, and to check deals in tests.
///
/// Depth-first over available pairs, remembering positions already shown to
/// be dead ends. Moves that can't hurt (removing every remaining tile of a
/// kind when all of them are free) are taken without branching, and positions
/// where some tile can never be paired are cut off early.
///
/// Move order matters most. Given a `guide` (a known solution of the deal,
/// such as `Deal.solution`), the solver tries tiles that come out earliest in
/// it first; this finds a fresh deal's solution without backtracking and stays
/// a strong hint after the player deviates. Without one it prefers moves that
/// free the most tiles.
public struct Solver: Sendable {
    public enum Result: Equatable, Sendable {
        /// A sequence of moves that clears the board.
        case solvable([TilePair])
        case unsolvable
        /// Gave up: ran out of budget or was cancelled.
        case unknown
    }

    public var maxNodes: Int
    public var timeLimit: Duration

    public init(maxNodes: Int = 300_000, timeLimit: Duration = .seconds(2)) {
        self.maxNodes = maxNodes
        self.timeLimit = timeLimit
    }

    public func solve(_ board: Board, guide: [TilePair]? = nil) -> Result {
        var search = Search(board: board, guide: guide, maxNodes: maxNodes,
                            deadline: ContinuousClock.now.advanced(by: timeLimit))
        var path: [TilePair] = []
        switch search.run(board.present, path: &path) {
        case .solved: return .solvable(path)
        case .dead: return .unsolvable
        case .gaveUp: return .unknown
        }
    }
}

private struct Search {
    enum Outcome {
        case solved, dead, gaveUp
    }

    let geometry: LayoutGeometry
    /// Tiles that can match each other share a key.
    let keys: [Int]
    let keyCount: Int
    /// Every tile that must be gone before this one can be free from above.
    let cones: [TileMask]
    /// Position of each tile in the guide's removal order, if there is one.
    let rank: [Int]?
    let maxNodes: Int
    let deadline: ContinuousClock.Instant
    var nodes = 0
    var deadEnds: Set<TileMask> = []

    init(board: Board, guide: [TilePair]?, maxNodes: Int, deadline: ContinuousClock.Instant) {
        geometry = board.geometry
        let caseCount = Face.allCases.count
        keys = board.faces.map { face in
            switch face.bonus {
            case .flower: caseCount
            case .season: caseCount + 1
            case nil: Face.allCases.firstIndex(of: face)!
            }
        }
        keyCount = caseCount + 2

        // Build cones from the top layer down, so each tile's cone can reuse
        // the cones of the tiles directly above it.
        let count = board.faces.count
        var cones = Array(repeating: TileMask(count: count, allPresent: false), count: count)
        let order = (0..<count).sorted { board.layout.positions[$0].z > board.layout.positions[$1].z }
        for i in order {
            for j in geometry.above[i] {
                cones[i].insert(j)
                cones[i].formUnion(cones[j])
            }
        }
        self.cones = cones

        if let guide {
            var rank = Array(repeating: guide.count, count: count)
            for (n, pair) in guide.enumerated() {
                rank[pair.a] = n
                rank[pair.b] = n
            }
            self.rank = rank
        } else {
            rank = nil
        }
        self.maxNodes = maxNodes
        self.deadline = deadline
    }

    mutating func run(_ start: TileMask, path: inout [TilePair]) -> Outcome {
        var present = start
        let mark = path.count
        takeSafeMoves(&present, path: &path)
        if present.isEmpty {
            return .solved
        }
        if deadEnds.contains(present) || hasStrandedTile(present) {
            path.removeSubrange(mark...)
            return .dead
        }
        nodes += 1
        if nodes > maxNodes || (nodes % 512 == 0 && (ContinuousClock.now > deadline || Task.isCancelled)) {
            path.removeSubrange(mark...)
            return .gaveUp
        }

        for move in orderedMoves(present) {
            var next = present
            next.remove(move.a)
            next.remove(move.b)
            path.append(move)
            switch run(next, path: &path) {
            case .solved:
                return .solved
            case .gaveUp:
                path.removeSubrange(mark...)
                return .gaveUp
            case .dead:
                path.removeLast()
            }
        }
        deadEnds.insert(present)
        path.removeSubrange(mark...)
        return .dead
    }

    /// Present tiles grouped by key.
    func groups(_ present: TileMask) -> [[Int]] {
        var groups = Array(repeating: [Int](), count: keyCount)
        for i in 0..<keys.count where present[i] {
            groups[keys[i]].append(i)
        }
        return groups
    }

    /// Removes every kind whose remaining tiles (two or four) are all free.
    /// No other pairing exists for those tiles, so this never loses a win.
    func takeSafeMoves(_ present: inout TileMask, path: inout [TilePair]) {
        var changed = true
        while changed {
            changed = false
            for group in groups(present) where !group.isEmpty && group.count % 2 == 0 {
                guard group.allSatisfy({ geometry.isFree($0, in: present) }) else { continue }
                for n in stride(from: 0, to: group.count, by: 2) {
                    let pair = TilePair(group[n], group[n + 1])
                    present.remove(pair.a)
                    present.remove(pair.b)
                    path.append(pair)
                }
                changed = true
            }
        }
    }

    /// A tile is stranded when every other remaining tile of its kind sits
    /// somewhere above it: they must all go before it's free, leaving it with
    /// no partner.
    func hasStrandedTile(_ present: TileMask) -> Bool {
        for group in groups(present) where group.count >= 2 {
            for t in group where group.allSatisfy({ $0 == t || cones[t][$0] }) {
                return true
            }
        }
        return false
    }

    func orderedMoves(_ present: TileMask) -> [TilePair] {
        let free = geometry.freeTiles(in: present)
        var moves: [(pair: TilePair, score: Int)] = []
        for (n, i) in free.enumerated() {
            for j in free[(n + 1)...] where keys[i] == keys[j] {
                let score: Int
                if let rank {
                    // Earliest in the guide first.
                    score = -max(rank[i], rank[j])
                } else {
                    var next = present
                    next.remove(i)
                    next.remove(j)
                    score = geometry.freeTiles(in: next).count
                }
                moves.append((TilePair(i, j), score))
            }
        }
        return moves.sorted { $0.score > $1.score }.map(\.pair)
    }
}
