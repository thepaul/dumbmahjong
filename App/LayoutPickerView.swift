import MahjongCore
import SwiftUI

/// Picks the layout for the next game, showing each as an empty board.
struct LayoutPickerView: View {
    let model: GameModel
    @AppStorage(SettingsKey.tableColor) private var tableColor = TableColor.felt
    @Environment(\.dismiss) private var dismiss
    @State private var confirming: MahjongCore.Layout?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                    ForEach(MahjongCore.Layout.bundled) { layout in
                        card(layout)
                    }
                }
                .padding()
            }
            .navigationTitle("Layouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog("Abandon this game and start a new one?", isPresented: isConfirming,
                                titleVisibility: .visible, presenting: confirming) { layout in
                Button("New \(layout.name) Game", role: .destructive) { play(layout) }
            }
        }
    }

    private func card(_ layout: MahjongCore.Layout) -> some View {
        let isCurrent = layout.id == model.game.deal.layoutID
        return Button {
            pick(layout)
        } label: {
            VStack(spacing: 8) {
                LayoutThumbnail(layout: layout)
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)
                    .background(tableColor.color, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        if isCurrent {
                            RoundedRectangle(cornerRadius: 12).strokeBorder(.tint, lineWidth: 3)
                        }
                    }
                HStack(spacing: 4) {
                    Text(layout.name)
                    if isCurrent {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .font(.body.weight(isCurrent ? .semibold : .regular))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(layout.name)
        .accessibilityValue(isCurrent ? "Current layout" : "")
        .accessibilityHint(isCurrent ? "" : "Starts a new game")
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    /// Picking the current layout keeps the game; another starts a new game,
    /// asking first if that would throw away progress.
    private func pick(_ layout: MahjongCore.Layout) {
        if layout.id == model.game.deal.layoutID {
            dismiss()
        } else if model.hasProgressToLose {
            confirming = layout
        } else {
            play(layout)
        }
    }

    private func play(_ layout: MahjongCore.Layout) {
        model.newGame(layout: layout)
        dismiss()
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
    }
}

/// A layout's empty board, drawn with the same geometry as the real board so
/// the shape and layer offsets match.
struct LayoutThumbnail: View {
    let layout: MahjongCore.Layout

    var body: some View {
        Canvas { context, size in
            let metrics = SpriteBoardScene.Metrics.fitting(layout, in: size)
            let w = metrics.tileWidth, h = metrics.tileHeight, d = metrics.depth
            let radius = w * 0.12
            for i in BoardState.drawOrder(for: layout) {
                let top = metrics.topLeft(layout.positions[i])
                let face = CGRect(origin: top, size: CGSize(width: w, height: h))
                // The extruded sides, then the top face over them.
                context.fill(Path(roundedRect: face.offsetBy(dx: d, dy: d), cornerRadius: radius),
                             with: .color(Color(uiColor: TileArtwork.back)))
                context.fill(Path(roundedRect: face, cornerRadius: radius),
                             with: .color(Color(uiColor: TileArtwork.ivory)))
                context.stroke(Path(roundedRect: face, cornerRadius: radius),
                               with: .color(Color(uiColor: TileArtwork.ivorySide)), lineWidth: max(0.5, w * 0.05))
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    LayoutPickerView(model: GameModel())
}
