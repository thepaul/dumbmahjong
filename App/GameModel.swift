import MahjongCore
import Observation

/// Owns the current game for the UI and keeps the saved copy up to date.
@MainActor @Observable
final class GameModel {
    private(set) var game: Game
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

    /// Applies a change to the game and saves it.
    func update(_ change: (inout Game) -> Void) {
        change(&game)
        save()
    }

    func newGame() {
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
