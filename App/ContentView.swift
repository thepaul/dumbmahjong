import MahjongCore
import SwiftUI

/// Placeholder until the board renderer exists.
struct ContentView: View {
    let model: GameModel

    var body: some View {
        ZStack {
            Color(red: 0.12, green: 0.36, blue: 0.24)
                .ignoresSafeArea()
            VStack(spacing: 8) {
                Text("Mahjong")
                    .font(.largeTitle.weight(.semibold))
                Text("Deal \(model.game.deal.seed) · \(model.game.board.present.presentCount) tiles left")
                    .font(.footnote)
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
        }
    }
}

#Preview {
    ContentView(model: GameModel())
}
