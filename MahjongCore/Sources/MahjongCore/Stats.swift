import Foundation

/// Win/loss records per layout.
///
/// A game counts as played once its first move is made. It ends as a win
/// when cleared, or as abandoned when the player starts something else while
/// it's open (new game, restart, another deal). Abandoned games break the
/// winning streak; games with no moves don't count at all.
public struct Stats: Codable, Equatable, Sendable {
    public struct Record: Codable, Equatable, Sendable {
        public var played = 0
        public var won = 0
        public var bestStreak = 0
        public var currentStreak = 0
        /// Fastest win, in seconds; nil until there's a timed win.
        public var bestTime: Double?
        /// Sum and count of timed wins, for the average.
        public var totalWinTime: Double = 0
        public var timedWins = 0

        public init() {}

        public var winRate: Double? {
            played == 0 ? nil : Double(won) / Double(played)
        }

        public var averageTime: Double? {
            timedWins == 0 ? nil : totalWinTime / Double(timedWins)
        }
    }

    public var records: [String: Record] = [:]
    /// The layout of the game that has started and not yet ended, if any.
    public var openGame: String?

    public init() {}

    public func record(for layoutID: String) -> Record {
        records[layoutID] ?? Record()
    }

    /// The first move of a game was made. Ends any other open game first.
    public mutating func gameStarted(layoutID: String) {
        abandonOpenGame()
        records[layoutID, default: Record()].played += 1
        openGame = layoutID
    }

    /// The open game was cleared. `time` is nil if it wasn't timed.
    public mutating func gameWon(layoutID: String, time: Double?) {
        guard openGame == layoutID else { return }
        openGame = nil
        var r = records[layoutID, default: Record()]
        r.won += 1
        r.currentStreak += 1
        r.bestStreak = max(r.bestStreak, r.currentStreak)
        if let time {
            r.bestTime = min(r.bestTime ?? time, time)
            r.totalWinTime += time
            r.timedWins += 1
        }
        records[layoutID] = r
    }

    /// The player moved on from an open game without finishing it.
    public mutating func abandonOpenGame() {
        guard let layoutID = openGame else { return }
        openGame = nil
        records[layoutID, default: Record()].currentStreak = 0
    }
}

/// Saves stats to a JSON file.
public struct StatsStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func applicationSupport() throws -> StatsStore {
        let dir = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return StatsStore(url: dir.appending(path: "Stats.json"))
    }

    public func save(_ stats: Stats) throws {
        try JSONEncoder().encode(stats).write(to: url, options: .atomic)
    }

    /// The saved stats, or empty stats if there are none or they can't be read.
    public func load() -> Stats {
        guard let data = try? Data(contentsOf: url),
              let stats = try? JSONDecoder().decode(Stats.self, from: data) else {
            return Stats()
        }
        return stats
    }
}
