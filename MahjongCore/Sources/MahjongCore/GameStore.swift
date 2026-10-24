import Foundation
import os

/// Saves the game in progress to a single JSON file and loads it back.
public struct GameStore: Sendable {
    public let url: URL

    private static let log = Logger(subsystem: "org.thepaul.dumbmahjong", category: "GameStore")

    public init(url: URL) {
        self.url = url
    }

    /// The store in the app's Application Support directory.
    public static func applicationSupport() throws -> GameStore {
        let dir = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return GameStore(url: dir.appending(path: "CurrentGame.json"))
    }

    /// Writes the game atomically, so a crash mid-write leaves the previous
    /// save intact.
    public func save(_ game: Game) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        try encoder.encode(game.snapshot).write(to: url, options: .atomic)
    }

    /// The saved game, or nil if there is none or it can't be used. An
    /// unusable save is moved aside rather than deleted, for debugging.
    public func load() -> Game? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        do {
            let snapshot = try JSONDecoder().decode(Game.Snapshot.self, from: Data(contentsOf: url))
            return try Game(snapshot: snapshot)
        } catch {
            Self.log.error("Discarding saved game: \(String(describing: error), privacy: .public)")
            let aside = url.appendingPathExtension("unreadable")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
            return nil
        }
    }

    public func delete() throws {
        try FileManager.default.removeItem(at: url)
    }
}
