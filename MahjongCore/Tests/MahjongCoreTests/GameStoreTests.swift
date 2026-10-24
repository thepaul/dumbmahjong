import Foundation
import MahjongCore
import Testing

@Suite struct GameStoreTests {
    let dir: URL
    let store: GameStore

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "GameStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = GameStore(url: dir.appending(path: "game.json"))
    }

    func midGame() throws -> Game {
        var game = try Game(layout: .turtle, seed: 8)
        for pair in game.deal.solution.prefix(12) {
            game.remove(pair)
        }
        game.undo()
        return game
    }

    @Test func missingFileLoadsNil() {
        #expect(store.load() == nil)
    }

    @Test func saveAndLoad() throws {
        let game = try midGame()
        try store.save(game)
        let loaded = try #require(store.load())
        #expect(loaded.board.present == game.board.present)
        #expect(loaded.redoStack == game.redoStack)
        #expect(loaded.deal == game.deal)
    }

    @Test func corruptFileLoadsNilAndIsMovedAside() throws {
        try Data("{ not json".utf8).write(to: store.url)
        #expect(store.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: store.url.path(percentEncoded: false)))
        let aside = store.url.appendingPathExtension("unreadable")
        #expect(FileManager.default.fileExists(atPath: aside.path(percentEncoded: false)))
    }

    @Test func unknownFieldsAreIgnored() throws {
        try store.save(try midGame())
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as! [String: Any]
        json["someFutureField"] = ["anything": 1]
        try JSONSerialization.data(withJSONObject: json).write(to: store.url)
        #expect(store.load() != nil)
    }

    @Test func unknownFaceLoadsNil() throws {
        try store.save(try midGame())
        let text = try String(contentsOf: store.url, encoding: .utf8)
            .replacingOccurrences(of: "\"dots1\"", with: "\"dots10\"")
        try Data(text.utf8).write(to: store.url)
        #expect(store.load() == nil)
    }
}
