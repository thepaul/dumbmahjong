import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 6) {
                        Text("Mahjong")
                            .font(.title.weight(.semibold))
                        Text("Version \(version)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                Section {
                    Text("Mahjong Solitaire without the nonsense: no ads, no in-app purchases, no accounts, no fireworks. Every deal can be won, and undo is unlimited.")
                    Text("This app collects no data. Your games and statistics stay on this device.")
                }
                Section("Tile Art") {
                    Text(markdown(Tileset.standard.info.credits))
                }
                Section("Source Code") {
                    Text("Released under the MIT License.")
                    Link("github.com/thepaul/dumbmahjong",
                         destination: URL(string: "https://github.com/thepaul/dumbmahjong")!)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// Credits files are Markdown, so their links are tappable.
    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                      options: options))
            ?? AttributedString(text)
    }
}

#Preview {
    AboutView()
}
