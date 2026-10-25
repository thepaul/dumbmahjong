import Foundation
import MahjongCore
import Testing

@Suite struct StatsTests {
    @Test func winsAndStreaks() {
        var stats = Stats()
        stats.gameStarted(layoutID: "turtle")
        stats.gameWon(layoutID: "turtle", time: 300)
        stats.gameStarted(layoutID: "turtle")
        stats.gameWon(layoutID: "turtle", time: 200)
        let r = stats.record(for: "turtle")
        #expect(r.played == 2 && r.won == 2)
        #expect(r.currentStreak == 2 && r.bestStreak == 2)
        #expect(r.bestTime == 200)
        #expect(r.averageTime == 250)
        #expect(r.winRate == 1)
        #expect(stats.openGame == nil)
    }

    @Test func abandoningBreaksTheStreak() {
        var stats = Stats()
        stats.gameStarted(layoutID: "turtle")
        stats.gameWon(layoutID: "turtle", time: nil)
        stats.gameStarted(layoutID: "turtle")
        stats.abandonOpenGame()
        let r = stats.record(for: "turtle")
        #expect(r.played == 2 && r.won == 1)
        #expect(r.currentStreak == 0 && r.bestStreak == 1)
        #expect(r.winRate == 0.5)
    }

    @Test func startingAnotherGameAbandonsTheOpenOne() {
        var stats = Stats()
        stats.gameStarted(layoutID: "turtle")
        stats.gameWon(layoutID: "turtle", time: nil)
        stats.gameStarted(layoutID: "turtle")
        stats.gameStarted(layoutID: "turtle")
        #expect(stats.record(for: "turtle").currentStreak == 0)
        #expect(stats.record(for: "turtle").played == 3)
    }

    @Test func untimedWinsDontAffectTimes() {
        var stats = Stats()
        stats.gameStarted(layoutID: "turtle")
        stats.gameWon(layoutID: "turtle", time: nil)
        #expect(stats.record(for: "turtle").bestTime == nil)
        #expect(stats.record(for: "turtle").averageTime == nil)
    }

    @Test func winWithoutOpenGameIsIgnored() {
        var stats = Stats()
        stats.gameWon(layoutID: "turtle", time: 100)
        #expect(stats.record(for: "turtle") == Stats.Record())
    }

    @Test func emptyRecordHasNoRates() {
        #expect(Stats().record(for: "turtle").winRate == nil)
    }

    @Test func storeRoundTripsAndToleratesGarbage() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "stats-\(UUID().uuidString).json")
        let store = StatsStore(url: url)
        #expect(store.load() == Stats())
        var stats = Stats()
        stats.gameStarted(layoutID: "turtle")
        try store.save(stats)
        #expect(store.load() == stats)
        try Data("nope".utf8).write(to: url)
        #expect(store.load() == Stats())
    }
}
