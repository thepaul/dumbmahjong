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

    @Test func overallSpansLayouts() {
        var stats = Stats()
        stats.gameStarted(layoutID: "turtle")
        stats.gameWon(layoutID: "turtle", time: 300)
        stats.gameStarted(layoutID: "pyramid")
        stats.gameWon(layoutID: "pyramid", time: 200)
        stats.gameStarted(layoutID: "turtle")
        stats.abandonOpenGame()
        stats.gameStarted(layoutID: "pyramid")
        stats.gameWon(layoutID: "pyramid", time: nil)
        let all = stats.overall
        #expect(all.played == 4 && all.won == 3)
        #expect(all.bestStreak == 2 && all.currentStreak == 1)
        #expect(all.bestTime == 200 && all.averageTime == 250)
        #expect(stats.record(for: "turtle").played == 2)
        #expect(stats.record(for: "pyramid").currentStreak == 2)
    }

    @Test func overallIsRebuiltForOldFiles() throws {
        var turtle = Stats.Record()
        turtle.played = 5
        turtle.won = 3
        turtle.currentStreak = 2
        turtle.bestStreak = 3
        turtle.bestTime = 250
        turtle.totalWinTime = 900
        turtle.timedWins = 3
        var pyramid = Stats.Record()
        pyramid.played = 2
        pyramid.won = 1
        pyramid.currentStreak = 1
        pyramid.bestStreak = 1
        pyramid.bestTime = 200
        pyramid.totalWinTime = 200
        pyramid.timedWins = 1
        let encoder = JSONEncoder()
        let oneLayout = try encoder.encode(["records": ["turtle": turtle]])
        #expect(try JSONDecoder().decode(Stats.self, from: oneLayout).overall == turtle)

        let twoLayouts = try encoder.encode(["records": ["turtle": turtle, "pyramid": pyramid]])
        let all = try JSONDecoder().decode(Stats.self, from: twoLayouts).overall
        #expect(all.played == 7 && all.won == 4)
        #expect(all.bestStreak == 3 && all.currentStreak == 0)
        #expect(all.bestTime == 200 && all.averageTime == 275)
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
