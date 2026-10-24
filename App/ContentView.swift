import MahjongCore
import SwiftUI

/// Interim game screen: the board plus a minimal toolbar. The real game screen
/// comes with #15.
struct ContentView: View {
    let model: GameModel
    @AppStorage("dimBlocked") private var dimBlocked = false

    var body: some View {
        VStack(spacing: 0) {
            SpriteBoardView(state: boardState, tileset: .standard, onTap: model.tap)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 20) {
                Button("New", systemImage: "plus.square", action: model.newGame)
                Button("Undo", systemImage: "arrow.uturn.backward", action: model.undo)
                    .disabled(!model.game.canUndo)
                Button("Redo", systemImage: "arrow.uturn.forward", action: model.redo)
                    .disabled(!model.game.canRedo)
                Spacer()
                Text("\(model.game.board.present.presentCount) left")
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .tint(.white)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color.felt)
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

#Preview {
    ContentView(model: GameModel())
}
