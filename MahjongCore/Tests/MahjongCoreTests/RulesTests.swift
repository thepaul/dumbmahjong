import MahjongCore
import Testing

@Suite struct FaceTests {
    @Test func standardSetComposition() {
        let set = Face.standardSet
        #expect(set.count == 144)
        #expect(Face.allCases.count == 42)
        #expect(set.filter { $0 == .dots5 }.count == 4)
        #expect(set.filter { $0.bonus == .flower }.count == 4)
        #expect(set.filter { $0.bonus == .season }.count == 4)
    }

    @Test func matching() {
        #expect(Face.bamboo3.matches(.bamboo3))
        #expect(!Face.bamboo3.matches(.dots3))
        #expect(Face.flowerPlum.matches(.flowerBamboo))
        #expect(!Face.flowerBamboo.matches(.bamboo1))
        #expect(Face.seasonSpring.matches(.seasonWinter))
        #expect(!Face.seasonSpring.matches(.flowerPlum))
        #expect(!Face.windEast.matches(.windWest))
    }
}

@Suite struct FreeTileTests {
    func board(_ positions: [(Int, Int, Int)], faces: [Face]? = nil) -> Board {
        let layout = Layout(
            id: "t", name: "t",
            positions: positions.map { Position(x: $0.0, y: $0.1, z: $0.2) })
        return Board(
            geometry: LayoutGeometry(layout),
            faces: faces ?? Array(repeating: .dots1, count: positions.count))
    }

    @Test func rowOfThree() {
        let b = board([(0, 0, 0), (2, 0, 0), (4, 0, 0), (8, 0, 0)])
        // Ends of the row and the lone tile are free; the middle is not.
        #expect(b.freeTiles() == [0, 2, 3])
    }

    @Test func stackedTileBlocksBelow() {
        let b = board([(0, 0, 0), (0, 0, 1)])
        #expect(b.freeTiles() == [1])
    }

    @Test func bridgingTileBlocksBothBelow() {
        let b = board([(0, 0, 0), (2, 0, 0), (1, 0, 1), (6, 0, 0)])
        #expect(b.freeTiles() == [2, 3])
    }

    @Test func halfOffsetNeighborBlocksSide() {
        // Tile 1 is half a row lower than tile 0 but still touches its right
        // side; tile 2 is a full row lower and does not.
        var b = board([(0, 0, 0), (2, 1, 0), (4, 0, 0), (2, 3, 0)])
        #expect(b.freeTiles() == [0, 2, 3])
        // With both outer tiles removed, tile 1 opens up.
        b.remove(TilePair(0, 2))
        #expect(b.freeTiles() == [1, 3])
    }

    @Test func turtleInitialFreeTiles() {
        let b = Board(geometry: LayoutGeometry(.turtle), faces: Face.standardSet)
        let free = b.freeTiles()
        #expect(free.count == 35)
        let freeByLayer = Dictionary(grouping: free) { b.layout.positions[$0].z }.mapValues(\.count)
        #expect(freeByLayer == [0: 14, 1: 12, 2: 8, 4: 1])
    }

    @Test func removeAndRestore() {
        var b = board([(0, 0, 0), (2, 0, 0), (4, 0, 0), (6, 0, 0)],
                      faces: [.dots1, .dots2, .dots2, .dots1])
        #expect(b.availablePairs() == [TilePair(0, 3)])
        #expect(!b.canRemove(TilePair(1, 2)))
        b.remove(TilePair(0, 3))
        #expect(b.availablePairs() == [TilePair(1, 2)])
        b.remove(TilePair(1, 2))
        #expect(b.isCleared)
        b.restore(TilePair(1, 2))
        b.restore(TilePair(0, 3))
        #expect(b.present == TileMask(count: 4, allPresent: true))
    }
}

@Suite struct TapTests {
    // A row of four: tiles 0 and 3 are free; 0 and 3 match, 1 and 2 match.
    let board = Board(
        geometry: LayoutGeometry(Layout(
            id: "row", name: "Row", positions: (0..<4).map { Position(x: 2 * $0, y: 0, z: 0) })),
        faces: [.seasonSpring, .dots2, .dots2, .seasonWinter])

    @Test func selectingAndDeselecting() {
        #expect(board.outcome(ofTapping: 0, selected: nil) == .select(0))
        #expect(board.outcome(ofTapping: 0, selected: 0) == .deselect)
    }

    @Test func blockedTile() {
        #expect(board.outcome(ofTapping: 1, selected: nil) == .blocked)
        #expect(board.outcome(ofTapping: 1, selected: 0) == .blocked)
    }

    @Test func matching() {
        #expect(board.outcome(ofTapping: 3, selected: 0) == .match(TilePair(0, 3)))
    }

    @Test func nonMatchingFreeTileMovesSelection() {
        let other = Board(geometry: board.geometry, faces: [.dots1, .dots2, .dots2, .dots3])
        #expect(other.outcome(ofTapping: 3, selected: 0) == .select(3))
    }

    @Test func removedTileIsIgnored() {
        var b = board
        b.remove(TilePair(0, 3))
        #expect(b.outcome(ofTapping: 0, selected: nil) == .ignored)
        // A stale selection of a removed tile is dropped.
        #expect(b.outcome(ofTapping: 1, selected: 0) == .select(1))
    }
}
