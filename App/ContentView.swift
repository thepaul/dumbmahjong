import MahjongCore
import SwiftUI

/// The game screen: the board plus a slim toolbar.
struct ContentView: View {
    let model: GameModel
    @AppStorage(SettingsKey.dimBlocked) private var dimBlocked = false
    @AppStorage(SettingsKey.showTimer) private var showTimer = false
    @AppStorage(SettingsKey.tableColor) private var tableColor = TableColor.felt
    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.sidewaysInPortrait) private var sidewaysInPortrait = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirming: Confirmation?
    @State private var askingForDealNumber = false
    @State private var dealNumberText = ""
    @State private var showingStats = false
    @State private var showingSettings = false
    @State private var showingAbout = false

    enum Confirmation: Identifiable {
        case newGame, restart
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            SpriteBoardView(state: boardState, tileset: .standard, onTap: model.tap)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) { noticeBanner }
                .overlay { winCard }
                // Let the last pair finish fading before the card appears.
                .animation(.easeOut(duration: 0.25).delay(model.game.isWon ? 0.3 : 0), value: model.game.isWon)
            toolbar
                .animation(.easeOut(duration: 0.2), value: model.game.isStuck)
        }
        .background(tableColor.color)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: model.game.history.count) { old, new in
            haptics && new > old
        }
        .onChange(of: clockAllowed, initial: true) { _, allowed in
            model.setClockAllowed(allowed)
        }
        .sheet(isPresented: $showingStats) { StatsView(model: model) }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $showingAbout) { AboutView() }
        .confirmationDialog(confirmationTitle, isPresented: isConfirming, titleVisibility: .visible,
                            presenting: confirming) { action in
            switch action {
            case .newGame: Button("New Game", role: .destructive) { model.newGame() }
            case .restart: Button("Restart", role: .destructive, action: model.restart)
            }
        }
        .alert("Play Deal Number", isPresented: $askingForDealNumber) {
            TextField("Deal number", text: $dealNumberText)
                .keyboardType(.numberPad)
            Button("Play") {
                if let seed = UInt64(dealNumberText.filter(\.isNumber)) {
                    model.newGame(seed: seed)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Any deal number replays the same deal.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 20) {
            Button("New Game", systemImage: "plus.square") { ask(.newGame) }
                .keyboardShortcut("n")
            Button("Undo", systemImage: "arrow.uturn.backward", action: model.undo)
                .disabled(!model.game.canUndo)
                .buttonRepeatBehavior(.enabled)
                .keyboardShortcut("z")
                // When stuck, Undo is the way out; make it easy to find.
                .background {
                    if model.game.isStuck {
                        Circle().fill(.white.opacity(0.22)).frame(width: 40, height: 40)
                    }
                }
            Button("Redo", systemImage: "arrow.uturn.forward", action: model.redo)
                .disabled(!model.game.canRedo)
                .buttonRepeatBehavior(.enabled)
                .keyboardShortcut("z", modifiers: [.command, .shift])
            if !model.game.isStuck {
                hintButton
            }
            Spacer(minLength: 0)
            // Drop the least important parts when space runs out (narrow
            // phones, large text), rather than wrapping or clipping.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    if showTimer { timer }
                    status(compact: false)
                }
                status(compact: false)
                status(compact: true)
            }
            menu
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .buttonStyle(ToolbarButtonStyle())
        .tint(.white)
        .padding(.horizontal)
        .padding(.vertical, 8)
        // Like system toolbars: cap the size so everything fits, and let a
        // long press show any button's name large instead.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityShowsLargeContentViewer()
    }

    private var timer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let seconds = model.elapsed.components.seconds
            Text(formatPlayTime(seconds: Double(seconds)))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.8))
                .accessibilityLabel("Time, \(Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide)))")
        }
    }

    /// Tiles left, or the stuck notice. Compact drops words to save space.
    @ViewBuilder private func status(compact: Bool) -> some View {
        if model.game.isStuck {
            stuckNotice(compact: compact)
        } else {
            Text(compact ? "\(model.game.board.present.presentCount)" : "\(model.game.board.present.presentCount) left")
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.8))
                .accessibilityLabel("\(model.game.board.present.presentCount) tiles left")
        }
    }

    private var hintButton: some View {
        Group {
            if model.isFindingHint {
                ProgressView()
                    .tint(.white)
            } else {
                Button("Hint", systemImage: "lightbulb", action: model.showHint)
                    .disabled(model.game.isWon)
                    .keyboardShortcut("h", modifiers: [])
            }
        }
        .frame(minWidth: 28)
    }

    private var menu: some View {
        Menu {
            Section("Deal \(String(model.game.deal.seed))") {
                Button("Restart This Deal", systemImage: "arrow.counterclockwise") { ask(.restart) }
                    .disabled(model.game.history.isEmpty)
                Button("Play Deal Number…", systemImage: "number") {
                    dealNumberText = ""
                    askingForDealNumber = true
                }
            }
            Button("Statistics", systemImage: "chart.bar") { showingStats = true }
            Button("Settings", systemImage: "gearshape") { showingSettings = true }
            Button("About", systemImage: "info.circle") { showingAbout = true }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    @ViewBuilder private var noticeBanner: some View {
        if let notice = model.notice {
            Text(notice.text)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 8)
                .transition(.opacity)
                .onTapGesture(perform: model.dismissNotice)
                .task(id: notice) {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation { model.dismissNotice() }
                }
        }
    }

    /// No moves left. Deals are always solvable, so this always means an
    /// earlier pairing needs undoing; say so plainly and offer the way out.
    /// Shown in the toolbar so it never covers tiles.
    private func stuckNotice(compact: Bool) -> some View {
        HStack(spacing: 8) {
            if !compact {
                Text("No moves")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .accessibilityLabel("No moves left")
            }
            Button("Restart", action: model.restart)
                .font(.callout)
                .buttonStyle(.borderless)
                .tint(.accentColor)
                .accessibilityLabel(compact ? "No moves left. Restart" : "Restart")
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .transition(.opacity)
    }

    @ViewBuilder private var winCard: some View {
        if model.game.isWon {
            VStack(spacing: 12) {
                Text("Board cleared")
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(winSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Side by side when they fit, stacked at large text sizes.
                ViewThatFits {
                    HStack(spacing: 12) { winButtons }
                    VStack(spacing: 10) { winButtons }
                }
                .padding(.top, 4)
            }
            .multilineTextAlignment(.center)
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
            .padding()
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    @ViewBuilder private var winButtons: some View {
        Button("Replay Deal", action: model.restart)
            .buttonStyle(.bordered)
        Button("New Game") { model.newGame() }
            .buttonStyle(.borderedProminent)
    }

    private var winSummary: String {
        let game = model.game
        let undos = game.undoCount == 1 ? "1 undo" : "\(game.undoCount) undos"
        let hints = game.hintCount == 1 ? "1 hint" : "\(game.hintCount) hints"
        var parts = ["Deal \(String(game.deal.seed))", undos, hints]
        if showTimer {
            parts.insert(formatPlayTime(seconds: Double(game.elapsed.components.seconds)), at: 1)
        }
        return parts.joined(separator: " · ")
    }

    /// The play clock runs only while the board is in front and uncovered.
    private var clockAllowed: Bool {
        scenePhase == .active && confirming == nil && !askingForDealNumber && !showingStats && !showingSettings
            && !showingAbout
    }

    /// Asks before throwing away a game in progress; otherwise just does it.
    private func ask(_ action: Confirmation) {
        if model.hasProgressToLose {
            confirming = action
        } else {
            switch action {
            case .newGame: model.newGame()
            case .restart: model.restart()
            }
        }
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
    }

    private var confirmationTitle: String {
        switch confirming {
        case .restart: "Restart this deal from the beginning?"
        default: "Abandon this game and start a new one?"
        }
    }

    private var boardState: BoardState {
        var state = model.boardState
        state.dimBlocked = dimBlocked
        state.tableColor = tableColor
        state.allowSideways = sidewaysInPortrait
        return state
    }
}

/// White icons that stay visible on the table when disabled, just dimmer.
private struct ToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
            .contentShape(Rectangle())
    }
}

#Preview {
    ContentView(model: GameModel())
}
