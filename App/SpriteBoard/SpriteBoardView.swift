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
                    .accessibilityHidden(true)
                    .overlay { AccessibilityLayer(view: scene.accessibility.layer) }
            } else {
                state.tableColor.color
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

/// Hosts the board's accessibility layer over the SpriteKit view.
private struct AccessibilityLayer: UIViewRepresentable {
    let view: AccessibilityLayerView

    func makeUIView(context: Context) -> AccessibilityLayerView { view }
    func updateUIView(_ uiView: AccessibilityLayerView, context: Context) {}
}
