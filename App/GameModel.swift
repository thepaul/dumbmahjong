import MahjongCore
import Observation
import UIKit

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
    private(set) var stats: Stats
    @ObservationIgnored private let store: GameStore?
    @ObservationIgnored private let statsStore: StatsStore?
    @ObservationIgnored private var hintSearch: Task<Solver.Result, Never>?
    /// When the play clock last started running, if it's running now.
    @ObservationIgnored private var clockStarted: ContinuousClock.Instant?
    /// Whether the screen allows the clock to run: the app is in front and
    /// no sheet or dialog is covering the board.
    @ObservationIgnored private var clockAllowed = false

    struct Notice: Equatable {
        let text: String
        let serial: Int
    }

    init() {
        store = try? GameStore.applicationSupport()
        statsStore = try? StatsStore.applicationSupport()
        stats = statsStore?.load() ?? Stats()
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
            announce("Blocked")
        case .select(let i):
            selected = i
        case .deselect:
            selected = nil
        case .match(let pair):
            selected = nil
            let name = game.board.faces[index].spokenName
            update { $0.remove(pair) }
            announce(game.isWon ? "Board cleared" : "Matched \(name). \(tilesLeftPhrase)")
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
        announce("Hint: \(game.board.faces[pair.a].spokenName) and \(game.board.faces[pair.b].spokenName)")
    }

    private func show(_ text: String) {
        notice = Notice(text: text, serial: (notice?.serial ?? 0) + 1)
        announce(text)
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
        endOpenGame()
        // Stop the clock first, so none of the old attempt's time leaks into
        // the fresh one.
        clockStarted = nil
        update { $0.restart() }
    }

    func undo() {
        selected = nil
        update { $0.undo() }
        announce("Undone. \(tilesLeftPhrase)")
    }

    func redo() {
        selected = nil
        update { $0.redo() }
        announce("Redone. \(tilesLeftPhrase)")
    }

    private var tilesLeftPhrase: String {
        let n = game.board.present.presentCount
        return n == 1 ? "1 tile left" : "\(n) tiles left"
    }

    /// Speaks to VoiceOver users what sighted players see happen on the board.
    private func announce(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    /// Applies a change to the game, records stats, and saves.
    func update(_ change: (inout Game) -> Void) {
        cancelHint()
        flushClock()
        let movesBefore = game.history.count
        let wonBefore = game.isWon
        change(&game)
        // The first move of a fresh attempt (after a deal or restart).
        if movesBefore == 0 && game.history.count == 1 && game.undoCount == 0 {
            stats.gameStarted(layoutID: game.deal.layoutID)
            saveStats()
        }
        if game.isWon && !wonBefore {
            stats.gameWon(layoutID: game.deal.layoutID, time: Self.seconds(game.elapsed))
            saveStats()
        }
        updateClock()
        save()
    }

    /// Starts a new game: a random deal, or a specific deal number.
    func newGame(seed: UInt64? = nil) {
        cancelHint()
        selected = nil
        endOpenGame()
        clockStarted = nil
        game = Self.freshGame(seed: seed)
        save()
    }

    /// Counts an unfinished game with moves as abandoned.
    private func endOpenGame() {
        guard stats.openGame != nil else { return }
        stats.abandonOpenGame()
        saveStats()
    }

    func resetStats() {
        let open = stats.openGame
        stats = Stats()
        stats.openGame = open
        saveStats()
    }

    private func saveStats() {
        do {
            try statsStore?.save(stats)
        } catch {
            print("Couldn't save stats: \(error)")
        }
    }

    // MARK: Play clock

    /// Play time so far, including the current running stretch.
    var elapsed: Duration {
        game.elapsed + (clockStarted.map { ContinuousClock.now - $0 } ?? .zero)
    }

    /// Called by the screen when the board becomes visible and uncovered, or
    /// stops being so.
    func setClockAllowed(_ allowed: Bool) {
        flushClock()
        clockAllowed = allowed
        updateClock()
    }

    /// The clock runs from the first move until the board is cleared, only
    /// while the player can see and use the board.
    private func updateClock() {
        let started = !game.history.isEmpty || game.undoCount > 0 || game.elapsed > .zero
        if clockAllowed && started && !game.isWon {
            if clockStarted == nil {
                clockStarted = .now
            }
        } else {
            flushClock()
            clockStarted = nil
        }
    }

    /// Moves the running stretch into the game's saved elapsed time.
    private func flushClock() {
        guard let start = clockStarted else { return }
        let now = ContinuousClock.now
        game.elapsed += now - start
        clockStarted = now
    }

    private static func seconds(_ d: Duration) -> Double {
        Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    private func cancelHint() {
        hintSearch?.cancel()
        hintSearch = nil
        isFindingHint = false
    }

    func save() {
        flushClock()
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
