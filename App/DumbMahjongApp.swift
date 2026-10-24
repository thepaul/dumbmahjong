import SwiftUI

@main
struct DumbMahjongApp: App {
    @State private var model = GameModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
            #if DEBUG
                .onAppear(perform: Self.applyDebugOrientation)
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                model.save()
            }
        }
    }

    #if DEBUG
    /// `-debugLandscape YES` launches in landscape, for headless simulator
    /// screenshots.
    private static func applyDebugOrientation() {
        guard UserDefaults.standard.bool(forKey: "debugLandscape"),
              let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
    }
    #endif
}
