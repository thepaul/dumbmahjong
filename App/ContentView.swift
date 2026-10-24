import MahjongCore
import SwiftUI

/// Spike screen for comparing the two board renderers (#11, #12). The real
/// game screen comes with #15.
struct ContentView: View {
    let model: GameModel
    @AppStorage("spikeRenderer") private var renderer = Renderer.sprite

    enum Renderer: String, CaseIterable {
        case sprite = "2.5D"
        case reality = "3D"
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch renderer {
                case .sprite:
                    SpriteBoardView(state: model.boardState, tileset: .standard, onTap: model.tap)
                case .reality:
                    RealityBoardView(state: model.boardState, tileset: .standard, onTap: model.tap)
                }
            }
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
                Picker("Renderer", selection: $renderer) {
                    ForEach(Renderer.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .tint(.white)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color.felt)
    }
}

extension Color {
    static let felt = Color(red: 0.12, green: 0.36, blue: 0.24)
}

#Preview {
    ContentView(model: GameModel())
}
