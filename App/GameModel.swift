import MahjongCore
import Observation

/// Owns the current game for the UI and keeps the saved copy up to date.
@MainActor @Observable
final class GameModel {
    private(set) var game: Game
    private(set) var selected: Int?
    private(set) var shake: BoardState.Pulse?
    private(set) var hint: BoardState.Pulse?
    private(set) var isFindingHint = false
    /// A short message for the player, shown briefly over the board.
    private(set) var notice: Notice?
    @ObservationIgnored private let store: GameStore?
    @ObservationIgnored private var hintSearch: Task<Solver.Result, Never>?

    struct Notice: Equatable {
        let text: String
        let serial: Int
    }

    init() {
        store = try? GameStore.applicationSupport()
        if let saved = store?.load() {
            game = saved
        } else {
            game = Self.freshGame()
            save()
        }
    }

    var boardState: BoardState {
        let board = game.board
        var free = TileMask(count: board.faces.count, allPresent: false)
        board.freeTiles().forEach { free.insert($0) }
        return BoardState(
            dealSeed: game.deal.seed, layout: board.layout, faces: board.faces,
            present: board.present, free: free, selected: selected, shake: shake, hint: hint)
    }

    /// Handles a tap on a tile: select it, match it with the selection, or
    /// shake it if it's blocked.
    func tap(_ index: Int) {
        switch game.board.outcome(ofTapping: index, selected: selected) {
        case .ignored:
            break
        case .blocked:
            shake = BoardState.Pulse(tiles: [index], serial: (shake?.serial ?? 0) + 1)
        case .select(let i):
            selected = i
        case .deselect:
            selected = nil
        case .match(let pair):
            selected = nil
            update { $0.remove(pair) }
        }
    }

    /// Finds a pair that keeps the game winnable and pulses it. If the
    /// solver proves the game can't be won from here, says so instead.
    func showHint() {
        guard !isFindingHint, !game.isWon else { return }
        let board = game.board
        let guide = game.deal.solution
        let search = Task.detached(priority: .userInitiated) {
            Solver().solve(board, guide: guide)
        }
        hintSearch = search
        isFindingHint = true
        Task {
            let result = await search.value
            isFindingHint = false
            // Ignore a stale answer if the board changed meanwhile.
            guard !search.isCancelled, game.board.present == board.present else { return }
            switch result {
            case .solvable(let path):
                if let move = path.first {
                    pulse(move)
                }
            case .unsolvable:
                show(board.availablePairs().isEmpty
                     ? "No moves left. Undo to back up."
                     : "This game can't be won from here. Undo to back up.")
            case .unknown:
                // Couldn't tell in time; any legal move is better than nothing.
                if let move = board.availablePairs().first {
                    pulse(move)
                }
            }
        }
    }

    private func pulse(_ pair: TilePair) {
        game.recordHint()
        save()
        hint = BoardState.Pulse(tiles: [pair.a, pair.b], serial: (hint?.serial ?? 0) + 1)
    }

    private func show(_ text: String) {
        notice = Notice(text: text, serial: (notice?.serial ?? 0) + 1)
    }

    func dismissNotice() {
        notice = nil
    }

    /// Whether starting over would throw away a game in progress.
    var hasProgressToLose: Bool {
        !game.history.isEmpty && !game.isWon
    }

    func restart() {
        selected = nil
        update { $0.restart() }
    }

    func undo() {
        selected = nil
        update { $0.undo() }
    }

    func redo() {
        selected = nil
        update { $0.redo() }
    }

    /// Applies a change to the game and saves it.
    func update(_ change: (inout Game) -> Void) {
        cancelHint()
        change(&game)
        save()
    }

    /// Starts a new game: a random deal, or a specific deal number.
    func newGame(seed: UInt64? = nil) {
        cancelHint()
        selected = nil
        game = Self.freshGame(seed: seed)
        save()
    }

    private func cancelHint() {
        hintSearch?.cancel()
        hintSearch = nil
        isFindingHint = false
    }

    func save() {
        do {
            try store?.save(game)
        } catch {
            print("Couldn't save game: \(error)")
        }
    }

    private static func freshGame(seed: UInt64? = nil) -> Game {
        // Random deal numbers are kept to nine digits so they're easy to read out.
        let seed = seed ?? UInt64.random(in: 1...999_999_999)
        do {
            return try Game(layout: .turtle, seed: seed)
        } catch {
            fatalError("Couldn't deal the Turtle: \(error)")
        }
    }
}
