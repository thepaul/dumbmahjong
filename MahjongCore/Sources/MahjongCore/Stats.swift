import Foundation

/// Win/loss records per layout, and across all layouts.
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

        mutating func win(time: Double?) {
            won += 1
            currentStreak += 1
            bestStreak = max(bestStreak, currentStreak)
            if let time {
                bestTime = min(bestTime ?? time, time)
                totalWinTime += time
                timedWins += 1
            }
        }
    }

    public var records: [String: Record] = [:]
    /// Every game on every layout. Streaks run across layouts in the order
    /// games were played, so this is kept alongside the per-layout records
    /// rather than added up from them.
    public var overall = Record()
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
        overall.played += 1
        openGame = layoutID
    }

    /// The open game was cleared. `time` is nil if it wasn't timed.
    public mutating func gameWon(layoutID: String, time: Double?) {
        guard openGame == layoutID else { return }
        openGame = nil
        records[layoutID, default: Record()].win(time: time)
        overall.win(time: time)
    }

    /// The player moved on from an open game without finishing it.
    public mutating func abandonOpenGame() {
        guard let layoutID = openGame else { return }
        openGame = nil
        records[layoutID, default: Record()].currentStreak = 0
        overall.currentStreak = 0
    }

    private enum CodingKeys: String, CodingKey {
        case records, overall, openGame
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        records = try c.decode([String: Record].self, forKey: .records)
        openGame = try c.decodeIfPresent(String.self, forKey: .openGame)
        overall = try c.decodeIfPresent(Record.self, forKey: .overall) ?? Self.combined(records)
    }

    /// Overall stats rebuilt from per-layout records, for files saved before
    /// overall stats were kept. Streaks across layouts can't be recovered,
    /// except when only one layout has been played.
    static func combined(_ records: [String: Record]) -> Record {
        if records.count == 1, let only = records.values.first {
            return only
        }
        var all = Record()
        for r in records.values {
            all.played += r.played
            all.won += r.won
            all.bestStreak = max(all.bestStreak, r.bestStreak)
            all.totalWinTime += r.totalWinTime
            all.timedWins += r.timedWins
            if let t = r.bestTime {
                all.bestTime = min(all.bestTime ?? t, t)
            }
        }
        return all
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
