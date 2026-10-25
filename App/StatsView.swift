import MahjongCore
import SwiftUI

struct StatsView: View {
    let model: GameModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReset = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(Layout.bundled) { layout in
                    Section(layout.name) {
                        rows(model.stats.record(for: layout.id))
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

    @ViewBuilder private func rows(_ r: Stats.Record) -> some View {
        LabeledContent("Played", value: "\(r.played)")
        LabeledContent("Won", value: "\(r.won)")
        LabeledContent("Win Rate", value: r.winRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–")
        LabeledContent("Best Time", value: r.bestTime.map { formatPlayTime(seconds: $0) } ?? "–")
        LabeledContent("Average Time", value: r.averageTime.map { formatPlayTime(seconds: $0) } ?? "–")
        LabeledContent("Current Streak", value: "\(r.currentStreak)")
        LabeledContent("Best Streak", value: "\(r.bestStreak)")
    }
}
