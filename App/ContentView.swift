import MahjongCore
import SwiftUI

/// The game screen: the board plus a slim toolbar.
struct ContentView: View {
    let model: GameModel
    @AppStorage("dimBlocked") private var dimBlocked = false
    @State private var confirming: Confirmation?
    @State private var askingForDealNumber = false
    @State private var dealNumberText = ""

    enum Confirmation: Identifiable {
        case newGame, restart
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            SpriteBoardView(state: boardState, tileset: .standard, onTap: model.tap)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) { noticeBanner }
            toolbar
        }
        .background(Color.felt)
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
        HStack(spacing: 22) {
            Button("New Game", systemImage: "plus.square") { ask(.newGame) }
                .keyboardShortcut("n")
            Button("Undo", systemImage: "arrow.uturn.backward", action: model.undo)
                .disabled(!model.game.canUndo)
                .buttonRepeatBehavior(.enabled)
                .keyboardShortcut("z")
            Button("Redo", systemImage: "arrow.uturn.forward", action: model.redo)
                .disabled(!model.game.canRedo)
                .buttonRepeatBehavior(.enabled)
                .keyboardShortcut("z", modifiers: [.command, .shift])
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
            Spacer()
            Text("\(model.game.board.present.presentCount) left")
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.8))
            menu
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .buttonStyle(ToolbarButtonStyle())
        .tint(.white)
        .padding(.horizontal)
        .padding(.vertical, 8)
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
        return state
    }
}

extension Color {
    static let felt = Color(red: 0.12, green: 0.36, blue: 0.24)
}

/// White icons that stay visible on the felt when disabled, just dimmer.
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
