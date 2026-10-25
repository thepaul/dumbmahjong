import MahjongCore
import SwiftUI

struct StatsView: View {
    let model: GameModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReset = false

    var body: some View {
        NavigationStack {
            List {
                Section("All Layouts") {
                    StatsRows(record: model.stats.overall)
                }
                if !played.isEmpty {
                    Section {
                        ForEach(played) { layout in
                            NavigationLink {
                                List { StatsRows(record: model.stats.record(for: layout.id)) }
                                    .navigationTitle(layout.name)
                                    .navigationBarTitleDisplayMode(.inline)
                            } label: {
                                LabeledContent(layout.name, value: summary(model.stats.record(for: layout.id)))
                            }
                        }
                    } header: {
                        Text("By Layout")
                    } footer: {
                        Text("Other layouts appear here once you've played them.")
                    }
                }
                Section {
                    Button("Reset Statistics", role: .destructive) { confirmingReset = true }
                } footer: {
                    Text("A game counts as played after its first move. Leaving a game unfinished ends your streak.")
                }
            }
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset all statistics?", isPresented: $confirmingReset,
                                titleVisibility: .visible) {
                Button("Reset", role: .destructive, action: model.resetStats)
            }
        }
    }

    /// Layouts with at least one game played, in menu order.
    private var played: [MahjongCore.Layout] {
        MahjongCore.Layout.bundled.filter { model.stats.record(for: $0.id).played > 0 }
    }

    /// "12 of 20 won · best 4:32"
    private func summary(_ r: Stats.Record) -> String {
        var text = "\(r.won) of \(r.played) won"
        if let best = r.bestTime {
            text += " · best \(formatPlayTime(seconds: best))"
        }
        return text
    }
}

private struct StatsRows: View {
    let record: Stats.Record

    var body: some View {
        let r = record
        LabeledContent("Played", value: "\(r.played)")
        LabeledContent("Won", value: "\(r.won)")
        LabeledContent("Win Rate", value: r.winRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–")
        LabeledContent("Best Time", value: r.bestTime.map { formatPlayTime(seconds: $0) } ?? "–")
        LabeledContent("Average Time", value: r.averageTime.map { formatPlayTime(seconds: $0) } ?? "–")
        LabeledContent("Current Streak", value: "\(r.currentStreak)")
        LabeledContent("Best Streak", value: "\(r.bestStreak)")
    }
}
