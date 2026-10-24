import Foundation
@testable import MahjongCore
import Testing

@Suite struct GameTests {
    func newGame(seed: UInt64 = 1) throws -> Game {
        try Game(layout: .turtle, seed: seed)
    }

    @Test func playingTheSolutionWins() throws {
        var game = try newGame()
        #expect(!game.isWon && !game.canUndo && !game.canRedo)
        for pair in game.deal.solution {
            let removed = game.remove(pair)
            #expect(removed)
        }
        #expect(game.isWon)
        #expect(!game.isStuck)
    }

    @Test func rejectsIllegalMoves() throws {
        var game = try newGame()
        let blocked = (0..<144).first { !game.board.isFree($0) }!
        let free = game.board.freeTiles()
        let blockedMove = game.remove(TilePair(blocked, free[0]))
        let sameTile = game.remove(TilePair(free[0], free[0]))
        #expect(!blockedMove && !sameTile)
        #expect(game.history.isEmpty)
    }

    @Test func undoRedoRoundTripsAtEveryStep() throws {
        var game = try newGame(seed: 2)
        let start = game.board.present
        var states = [start]
        for pair in game.deal.solution {
            game.remove(pair)
            states.append(game.board.present)
            let here = game.board.present
            let depth = game.history.count
            while game.undo() != nil {}
            #expect(game.board.present == start)
            #expect(game.redoStack.count == depth)
            while game.redo() != nil {}
            #expect(game.board.present == here)
        }
        // Walk all the way back, checking each intermediate state.
        for expected in states.reversed().dropFirst() {
            game.undo()
            #expect(game.board.present == expected)
        }
        #expect(!game.canUndo)
    }

    @Test func newMoveClearsRedo() throws {
        var game = try newGame(seed: 3)
        let solution = game.deal.solution
        game.remove(solution[0])
        game.remove(solution[1])
        game.undo()
        #expect(game.canRedo)
        game.remove(solution[1])
        #expect(!game.canRedo)
    }

    @Test func restartMatchesFreshDeal() throws {
        var game = try newGame(seed: 4)
        for pair in game.deal.solution.prefix(10) {
            game.remove(pair)
        }
        game.undo()
        game.recordHint()
        game.elapsed = .seconds(30)
        game.restart()
        let fresh = try newGame(seed: 4)
        #expect(game.board.present == fresh.board.present)
        #expect(game.deal == fresh.deal)
        #expect(game.history.isEmpty && game.redoStack.isEmpty)
        #expect(game.undoCount == 0 && game.hintCount == 0 && game.elapsed == .zero)
    }

    @Test func detectsStuck() {
        // A row of four with mismatched ends: no legal first move.
        let layout = Layout(id: "row", name: "Row", positions: (0..<4).map { Position(x: 2 * $0, y: 0, z: 0) })
        let deal = Deal(layoutID: "row", seed: 0, faces: [.dots1, .dots2, .dots1, .dots2], solution: [])
        let game = Game(deal: deal, geometry: LayoutGeometry(layout))
        #expect(game.isStuck)
    }
}

@Suite struct SnapshotTests {
    func midGame() throws -> Game {
        var game = try Game(layout: .turtle, seed: 5)
        for pair in game.deal.solution.prefix(20) {
            game.remove(pair)
        }
        game.undo()
        game.undo()
        game.recordHint()
        game.elapsed = .milliseconds(83_500)
        return game
    }

    @Test func roundTrip() throws {
        let game = try midGame()
        let data = try JSONEncoder().encode(game.snapshot)
        let restored = try Game(snapshot: JSONDecoder().decode(Game.Snapshot.self, from: data))
        #expect(restored.board.present == game.board.present)
        #expect(restored.history == game.history)
        #expect(restored.redoStack == game.redoStack)
        #expect(restored.elapsed == .milliseconds(83_500))
        #expect(restored.undoCount == 2 && restored.hintCount == 1)
    }

    @Test func rejectsIllegalHistory() throws {
        var snapshot = try midGame().snapshot
        snapshot.history.append(snapshot.history[0])
        #expect(throws: Game.RestoreError.illegalMove) { try Game(snapshot: snapshot) }
    }

    @Test func rejectsIllegalRedo() throws {
        var snapshot = try midGame().snapshot
        snapshot.redoStack.append(snapshot.history[0])
        #expect(throws: Game.RestoreError.illegalMove) { try Game(snapshot: snapshot) }
    }

    @Test func rejectsFutureVersion() throws {
        var snapshot = try midGame().snapshot
        snapshot.version = 99
        #expect(throws: Game.RestoreError.unsupportedVersion(99)) { try Game(snapshot: snapshot) }
    }
}
