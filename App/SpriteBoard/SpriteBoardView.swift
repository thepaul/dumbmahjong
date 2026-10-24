import SpriteKit
import SwiftUI

/// SwiftUI wrapper for the 2.5D SpriteKit board.
struct SpriteBoardView: View {
    let state: BoardState
    let tileset: Tileset
    let onTap: (Int) -> Void

    @State private var scene: SpriteBoardScene?

    var body: some View {
        Group {
            if let scene {
                SpriteView(scene: scene, options: [.ignoresSiblingOrder])
            } else {
                Color.felt
            }
        }
        .onAppear {
            let scene = SpriteBoardScene(tileset: tileset)
            scene.onTap = onTap
            scene.apply(state)
            self.scene = scene
        }
        .onChange(of: state) { _, new in
            scene?.apply(new)
        }
    }
}
