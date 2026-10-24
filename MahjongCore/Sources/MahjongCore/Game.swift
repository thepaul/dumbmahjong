/// A game in progress: a deal plus the moves made so far, with unlimited undo
/// and redo.
public struct Game: Sendable {
    public let deal: Deal
    public private(set) var board: Board
    /// Pairs removed so far, oldest first.
    public private(set) var history: [TilePair] = []
    /// Undone pairs, most recently undone last.
    public private(set) var redoStack: [TilePair] = []
    /// Active play time. The app adds to this while the game is on screen.
    public var elapsed: Duration = .zero
    public private(set) var undoCount = 0
    public private(set) var hintCount = 0

    public init(deal: Deal, geometry: LayoutGeometry) {
        self.deal = deal
        board = Board(deal: deal, geometry: geometry)
    }

    /// A fresh game on `layout` from the deal for `seed`.
    public init(layout: Layout, seed: UInt64) throws(Deal.GenerationError) {
        let geometry = LayoutGeometry(layout)
        self.init(deal: try Deal.generate(geometry: geometry, seed: seed), geometry: geometry)
    }

    public var isWon: Bool { board.isCleared }

    /// No moves are left but tiles remain. Deals are always solvable, so this
    /// means an earlier choice of pairing needs undoing.
    public var isStuck: Bool { !isWon && board.availablePairs().isEmpty }

    public var canUndo: Bool { !history.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Removes the pair if it is a legal move. Returns whether it was.
    @discardableResult
    public mutating func remove(_ pair: TilePair) -> Bool {
        guard board.canRemove(pair) else { return false }
        board.remove(pair)
        history.append(pair)
        redoStack.removeAll()
        return true
    }

    /// Puts back the most recently removed pair and returns it.
    @discardableResult
    public mutating func undo() -> TilePair? {
        guard let pair = history.popLast() else { return nil }
        board.restore(pair)
        redoStack.append(pair)
        undoCount += 1
        return pair
    }

    /// Removes the most recently undone pair again and returns it.
    @discardableResult
    public mutating func redo() -> TilePair? {
        guard let pair = redoStack.popLast() else { return nil }
        board.remove(pair)
        history.append(pair)
        return pair
    }

    /// Starts the same deal over from the beginning.
    public mutating func restart() {
        self = Game(deal: deal, geometry: board.geometry)
    }

    /// Counts a hint toward the end-of-game summary.
    public mutating func recordHint() {
        hintCount += 1
    }
}

extension Game {
    /// Everything needed to save and restore a game.
    public struct Snapshot: Codable, Sendable {
        public static let currentVersion = 1

        public var version: Int
        public var deal: Deal
        public var history: [TilePair]
        public var redoStack: [TilePair]
        public var elapsedSeconds: Double
        public var undoCount: Int
        public var hintCount: Int
    }

    public enum RestoreError: Error, Equatable {
        case unsupportedVersion(Int)
        case unknownLayout(String)
        case wrongLayout
        case illegalMove
    }

    public var snapshot: Snapshot {
        Snapshot(
            version: Snapshot.currentVersion, deal: deal, history: history, redoStack: redoStack,
            elapsedSeconds: Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18,
            undoCount: undoCount, hintCount: hintCount)
    }

    /// Rebuilds a saved game, replaying and checking every move so a damaged
    /// save can't produce an impossible board.
    public init(snapshot: Snapshot, geometry: LayoutGeometry) throws(RestoreError) {
        guard snapshot.version == Snapshot.currentVersion else {
            throw .unsupportedVersion(snapshot.version)
        }
        guard snapshot.deal.layoutID == geometry.layout.id,
              snapshot.deal.faces.count == geometry.count else {
            throw .wrongLayout
        }
        self.init(deal: snapshot.deal, geometry: geometry)
        for pair in snapshot.history {
            guard remove(pair) else { throw .illegalMove }
        }
        // The redo stack must also replay cleanly from here.
        var scratch = board
        for pair in snapshot.redoStack.reversed() {
            guard scratch.canRemove(pair) else { throw .illegalMove }
            scratch.remove(pair)
        }
        redoStack = snapshot.redoStack
        elapsed = .seconds(max(0, snapshot.elapsedSeconds))
        undoCount = snapshot.undoCount
        hintCount = snapshot.hintCount
    }

    /// Rebuilds a saved game on one of the bundled layouts.
    public init(snapshot: Snapshot) throws(RestoreError) {
        guard let layout = Layout.bundled(id: snapshot.deal.layoutID) else {
            throw .unknownLayout(snapshot.deal.layoutID)
        }
        try self.init(snapshot: snapshot, geometry: LayoutGeometry(layout))
    }
}
