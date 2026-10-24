import Foundation
import MahjongCore
import Testing

@Suite struct LayoutTests {
    let turtle = Layout.turtle

    @Test func turtleLoadsAndValidates() throws {
        #expect(turtle.name == "Turtle")
        #expect(turtle.positions.count == 144)
        try turtle.validate()
    }

    @Test func turtleLayerCounts() {
        let counts = Dictionary(grouping: turtle.positions, by: \.z).mapValues(\.count)
        #expect(counts == [0: 87, 1: 36, 2: 16, 3: 4, 4: 1])
    }

    @Test func allBundledLayoutsValidate() throws {
        for layout in Layout.bundled {
            try layout.validate()
        }
    }

    @Test func positionCodesAsArray() throws {
        let data = try JSONEncoder().encode(Position(x: 1, y: 2, z: 3))
        #expect(String(decoding: data, as: UTF8.self) == "[1,2,3]")
        let decoded = try JSONDecoder().decode(Position.self, from: Data("[4,5,6]".utf8))
        #expect(decoded == Position(x: 4, y: 5, z: 6))
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Position.self, from: Data("[4,5,6,7]".utf8))
        }
    }

    @Test func validationRejectsOddCount() {
        let layout = Layout(id: "t", name: "t", positions: [Position(x: 0, y: 0, z: 0)])
        #expect(throws: Layout.ValidationError.oddTileCount(1)) { try layout.validate() }
    }

    @Test func validationRejectsOverlap() {
        let layout = Layout(id: "t", name: "t", positions: [
            Position(x: 0, y: 0, z: 0), Position(x: 1, y: 1, z: 0),
        ])
        #expect(throws: Layout.ValidationError.overlapping(0, 1)) { try layout.validate() }
    }

    @Test func validationRejectsPartialSupport() {
        // The upper tile hangs half off the single tile below it.
        let layout = Layout(id: "t", name: "t", positions: [
            Position(x: 0, y: 0, z: 0), Position(x: 1, y: 0, z: 1),
        ])
        #expect(throws: Layout.ValidationError.unsupported(index: 1)) { try layout.validate() }
    }

    @Test func validationAcceptsBridgingTile() throws {
        // An upper tile straddling two lower tiles is fully supported.
        let layout = Layout(id: "t", name: "t", positions: [
            Position(x: 0, y: 0, z: 0), Position(x: 2, y: 0, z: 0),
            Position(x: 1, y: 0, z: 1), Position(x: 6, y: 0, z: 0),
        ])
        try layout.validate()
    }

    @Test func turtleEndCapNeighbors() throws {
        let geometry = LayoutGeometry(turtle)
        let index = { (x: Int, y: Int, z: Int) in
            try #require(self.turtle.positions.firstIndex(of: Position(x: x, y: y, z: z)))
        }
        // The left cap sits between rows 3 and 4, touching both.
        let leftCap = try index(0, 7, 0)
        #expect(Set(geometry.right[leftCap]) == [try index(2, 6, 0), try index(2, 8, 0)])
        #expect(geometry.left[leftCap].isEmpty)
        // The inner right cap is blocked by rows 3 and 4 on its left and the
        // outer cap on its right.
        let innerRight = try index(26, 7, 0)
        #expect(Set(geometry.left[innerRight]) == [try index(24, 6, 0), try index(24, 8, 0)])
        #expect(geometry.right[innerRight] == [try index(28, 7, 0)])
        // The peak covers all four tiles of layer 3.
        let peak = try index(13, 7, 4)
        for (x, y) in [(12, 6), (14, 6), (12, 8), (14, 8)] {
            #expect(geometry.above[try index(x, y, 3)] == [peak])
        }
    }
}
