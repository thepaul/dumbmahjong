import MahjongCore
import Observation

/// Owns the current game for the UI and keeps the saved copy up to date.
@MainActor @Observable
final class GameModel {
    private(set) var game: Game
    private(set) var selected: Int?
    private(set) var shake: BoardState.Shake?
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
        BoardState(
            dealSeed: game.deal.seed, layout: game.board.layout, faces: game.board.faces,
            present: game.board.present, selected: selected, shake: shake)
    }

    /// Handles a tap on a tile: select it, match it with the selection, or
    /// shake it if it's blocked.
    func tap(_ index: Int) {
        let board = game.board
        guard board.present[index] else { return }
        guard board.isFree(index) else {
            shake = BoardState.Shake(index: index, serial: (shake?.serial ?? 0) + 1)
            return
        }
        if let selected, selected != index, board.faces[selected].matches(board.faces[index]) {
            self.selected = nil
            update { $0.remove(TilePair(selected, index)) }
        } else {
            selected = selected == index ? nil : index
        }
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
