import MahjongCore
import Observation

/// Owns the current game for the UI and keeps the saved copy up to date.
@MainActor @Observable
final class GameModel {
    private(set) var game: Game
    private(set) var selected: Int?
    private(set) var shake: BoardState.Pulse?
    private(set) var hint: BoardState.Pulse?
    @ObservationIgnored private let store: GameStore?

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

    /// Briefly highlights a pair, for the Hint button.
    func pulse(_ pair: TilePair) {
        hint = BoardState.Pulse(tiles: [pair.a, pair.b], serial: (hint?.serial ?? 0) + 1)
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
        change(&game)
        save()
    }

    func newGame() {
        selected = nil
        game = Self.freshGame()
        save()
    }

    func save() {
        do {
            try store?.save(game)
        } catch {
            print("Couldn't save game: \(error)")
        }
    }

    private static func freshGame() -> Game {
        // Deal numbers are kept to nine digits so they're easy to read out.
        let seed = UInt64.random(in: 1...999_999_999)
        do {
            return try Game(layout: .turtle, seed: seed)
        } catch {
            fatalError("Couldn't deal the Turtle: \(error)")
        }
    }
}
