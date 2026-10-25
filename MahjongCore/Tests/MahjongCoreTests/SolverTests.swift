import MahjongCore
import Testing

@Suite struct SolverTests {
    /// Stacks far enough apart that they never block each other sideways.
    /// Each stack lists faces from the top down.
    func board(stacks: [[Face]]) -> Board {
        var positions: [Position] = []
        var faces: [Face] = []
        for (s, stack) in stacks.enumerated() {
            for (depth, face) in stack.enumerated() {
                positions.append(Position(x: s * 10, y: 0, z: stack.count - 1 - depth))
                faces.append(face)
            }
        }
        return Board(geometry: LayoutGeometry(Layout(id: "t", name: "t", positions: positions)), faces: faces)
    }

    func replay(_ path: [TilePair], on board: Board) -> Bool {
        var b = board
        for pair in path {
            guard b.canRemove(pair) else { return false }
            b.remove(pair)
        }
        return b.isCleared
    }

    /// Node budget only, so results don't depend on machine speed.
    let solver = Solver(maxNodes: 200_000, timeLimit: .seconds(3600))

    @Test(arguments: 0..<40 as Range<UInt64>)
    func solvesFreshTurtleDealsWithGuide(seed: UInt64) throws {
        let deal = try Deal.generate(layout: .turtle, seed: seed)
        let board = Board(deal: deal, geometry: LayoutGeometry(.turtle))
        guard case .solvable(let path) = solver.solve(board, guide: deal.solution) else {
            Issue.record("seed \(seed) not solved")
            return
        }
        #expect(replay(path, on: board))
    }

    @Test func solvesMidGame() throws {
        var game = try Game(layout: .turtle, seed: 77)
        for pair in game.deal.solution.prefix(30) {
            game.remove(pair)
        }
        guard case .solvable(let path) = solver.solve(game.board, guide: game.deal.solution) else {
            Issue.record("not solved")
            return
        }
        #expect(replay(path, on: game.board))
    }

    /// After random play the position may or may not be winnable, but the
    /// solver should almost always be able to say which.
    @Test func decidesPositionsAfterRandomPlay() throws {
        var undecided = 0
        for seed in 0..<30 as Range<UInt64> {
            var game = try Game(layout: .turtle, seed: seed)
            var rng = DealRandom(seed: seed &+ 1000)
            for _ in 0..<(10 + rng.next(below: 40)) {
                let pairs = game.board.availablePairs()
                if pairs.isEmpty { break }
                game.remove(pairs[rng.next(below: pairs.count)])
            }
            switch solver.solve(game.board, guide: game.deal.solution) {
            case .solvable(let path):
                #expect(replay(path, on: game.board), "seed \(seed)")
            case .unsolvable:
                break
            case .unknown:
                undecided += 1
            }
        }
        #expect(undecided <= 2)
    }

    @Test func avoidsTheTrap() {
        // Three free A's. Pairing the two lone ones strands the A under the B
        // in stack 0; only taking stack 0's top A with stack 1's wins.
        let b = board(stacks: [[.dots1, .dots2, .dots1], [.dots1, .dots2], [.dots1]])
        guard case .solvable(let path) = solver.solve(b) else {
            Issue.record("not solved")
            return
        }
        #expect(replay(path, on: b))
        let first = Set([path[0].a, path[0].b])
        #expect(first.contains(0))
    }

    @Test func detectsUnwinnablePosition() {
        // One move is available, but it leaves B over C and C over B.
        let b = board(stacks: [[.dots1, .dots2, .dots3], [.dots1, .dots3, .dots2]])
        #expect(!b.availablePairs().isEmpty)
        #expect(solver.solve(b) == .unsolvable)
    }

    @Test func clearedBoardIsTriviallySolvable() {
        var b = board(stacks: [[.dots1], [.dots1]])
        b.remove(TilePair(0, 1))
        #expect(solver.solve(b) == .solvable([]))
    }

    @Test func givesUpWhenOverBudget() throws {
        let b = board(stacks: [[.dots1, .dots2, .dots3], [.dots1, .dots3, .dots2]])
        #expect(Solver(maxNodes: 0).solve(b) == .unknown)
    }
}
