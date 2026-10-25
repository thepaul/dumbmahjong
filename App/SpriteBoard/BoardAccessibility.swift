import MahjongCore
import UIKit

/// VoiceOver access to the SpriteKit board. Every tile with nothing on top of
/// it becomes an element over its on-screen frame, in reading order;
/// double-tapping one taps the tile. A "Free Tiles" rotor jumps between tiles
/// that can be played.
///
/// The elements live on `layer`, a transparent view laid exactly over the
/// board that ignores touches. SKView publishes its own node tree to
/// accessibility and ignores elements set on it, so the board view itself is
/// hidden from accessibility instead.
@MainActor
final class BoardAccessibility {
    let layer = AccessibilityLayerView()
    private var elements: [TileElement] = []

    /// Rebuilds the elements for `state`. `frame(i)` gives tile `i`'s frame
    /// in the board view's coordinates, which are also the layer's.
    func update(state: BoardState, geometry: LayoutGeometry,
                frame: (Int) -> CGRect, onTap: @escaping (Int) -> Void) {
        let view = layer
        let visible = state.layout.positions.indices.filter { i in
            state.present[i] && !geometry.above[i].contains { state.present[$0] }
        }
        elements = visible.map { i in
            let element = TileElement(accessibilityContainer: view)
            element.index = i
            element.onTap = onTap
            let free = state.free[i]
            element.accessibilityLabel = "\(state.faces[i].spokenName), \(free ? "free" : "blocked")"
            element.accessibilityTraits = state.selected == i ? [.button, .selected] : free ? .button : .notEnabled
            element.isFree = free
            element.accessibilityFrameInContainerSpace = frame(i)
            return element
        }
        // Reading order follows the screen, whichever way the board is turned:
        // rows of half a tile's height, then left to right.
        let rowHeight = max(1, (elements.first?.accessibilityFrameInContainerSpace.height ?? 1) / 2)
        func key(_ e: TileElement) -> (Int, CGFloat) {
            let f = e.accessibilityFrameInContainerSpace
            return (Int(f.midY / rowHeight), f.midX)
        }
        elements.sort { key($0) < key($1) }
        view.accessibilityElements = elements
        view.accessibilityCustomRotors = [freeTilesRotor()]
    }

    private func freeTilesRotor() -> UIAccessibilityCustomRotor {
        UIAccessibilityCustomRotor(name: "Free Tiles") { [weak self] predicate in
            guard let self else { return nil }
            let free = self.elements.filter(\.isFree)
            guard !free.isEmpty else { return nil }
            let current = predicate.currentItem.targetElement as? TileElement
            let position = current.flatMap { c in free.firstIndex { $0 === c } }
            let next: Int
            switch (predicate.searchDirection, position) {
            case (.next, let p?): next = p + 1
            case (.previous, let p?): next = p - 1
            case (.next, nil): next = 0
            default: next = free.count - 1
            }
            guard free.indices.contains(next) else { return nil }
            return UIAccessibilityCustomRotorItemResult(targetElement: free[next], targetRange: nil)
        }
    }
}

final class AccessibilityLayerView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }
}

private final class TileElement: UIAccessibilityElement {
    var index = 0
    var isFree = false
    var onTap: ((Int) -> Void)?

    override func accessibilityActivate() -> Bool {
        onTap?(index)
        return true
    }
}
