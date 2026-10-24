import MahjongCore
import Testing

@Suite struct DealRandomTests {
    @Test func sameSeedSameSequence() {
        var a = DealRandom(seed: 7)
        var b = DealRandom(seed: 7)
        for _ in 0..<100 {
            #expect(a.next() == b.next())
        }
    }

    @Test func boundedValuesInRange() {
        var rng = DealRandom(seed: 1)
        var seen = Set<Int>()
        for _ in 0..<1000 {
            let v = rng.next(below: 6)
            #expect((0..<6).contains(v))
            seen.insert(v)
        }
        #expect(seen.count == 6)
    }
}

@Suite struct DealTests {
    let geometry = LayoutGeometry(.turtle)

    @Test(arguments: 0..<500 as Range<UInt64>)
    func solutionClearsBoard(seed: UInt64) throws {
        let deal = try Deal.generate(geometry: geometry, seed: seed)
        var board = Board(deal: deal, geometry: geometry)
        for pair in deal.solution {
            #expect(board.canRemove(pair))
            board.remove(pair)
        }
        #expect(board.isCleared)
    }

    @Test func usesExactlyTheStandardSet() throws {
        let deal = try Deal.generate(geometry: geometry, seed: 3)
        #expect(deal.faces.sorted { $0.rawValue < $1.rawValue }
            == Face.standardSet.sorted { $0.rawValue < $1.rawValue })
    }

    @Test func sameSeedSameDeal() throws {
        #expect(try Deal.generate(geometry: geometry, seed: 99) == Deal.generate(geometry: geometry, seed: 99))
        #expect(try Deal.generate(geometry: geometry, seed: 99) != Deal.generate(geometry: geometry, seed: 100))
    }

    /// Pins the generator's output. If this fails, deal numbers no longer
    /// reproduce the same deals as before; only update it deliberately.
    @Test func generatorIsStable() throws {
        let deal = try Deal.generate(geometry: geometry, seed: 12345)
        #expect(deal.faces.prefix(8).map(\.rawValue) == [
            "dots4", "dots6", "flowerOrchid", "characters8", "bamboo7", "dots7", "bamboo6", "bamboo6",
        ])
    }

    @Test func rejectsWrongTileCount() {
        #expect(throws: Deal.GenerationError.tileCountMismatch(positions: 144, tiles: 4)) {
            try Deal.generate(geometry: geometry, seed: 1, tiles: [.dots1, .dots1, .dots2, .dots2])
        }
    }

    @Test func rejectsUnpairableTiles() {
        var tiles = Face.standardSet
        tiles[0] = .dots2
        #expect(throws: Deal.GenerationError.unpairableTiles) {
            try Deal.generate(geometry: geometry, seed: 1, tiles: tiles)
        }
    }
}
