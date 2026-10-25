import MahjongCore
import SpriteKit
import UIKit

/// 2.5D board: a fixed oblique view where each layer is shifted up and to the
/// left, so every tile shows its thickness on its right and bottom sides.
///
/// The view is paused whenever nothing is animating, so an idle board costs no
/// rendering. Anything that changes what's on screen must call `wake()`.
///
/// Tiles live in `board`, laid out on an upright canvas. `container` centers
/// the canvas in the scene, turns it a quarter turn when allowed and that
/// gives much bigger tiles (a wide layout on a portrait phone), and carries
/// pinch zoom and pan.
@MainActor
final class SpriteBoardScene: SKScene, UIGestureRecognizerDelegate {
    var onTap: ((Int) -> Void)?

    private let tileset: Tileset
    private var state: BoardState?
    private var metrics: Metrics?
    private var drawOrder: [Int] = []
    private var tiles: [Int: TileNode] = [:]
    private var faceTextures: [Face: SKTexture] = [:]
    private var idleFrames = 0
    private var pending: BoardState?
    private var geometry: LayoutGeometry?
    let accessibility = BoardAccessibility()
    /// Size of the upright canvas the board is laid out on.
    private var canvas = CGSize.zero
    private var zoom: CGFloat = 1

    private let container = SKNode()
    private let board = SKNode()

    /// Rotate only when upright tiles would be narrower than this…
    static let comfortableTileWidth: CGFloat = 36
    /// …and turning the board makes them at least this much bigger.
    static let rotationGain: CGFloat = 1.2
    static let maxZoom: CGFloat = 3

    init(tileset: Tileset) {
        self.tileset = tileset
        super.init(size: CGSize(width: 1, height: 1))
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = TableColor.felt.uiColor
        container.addChild(board)
        addChild(container)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        rebuild()
    }

    override func update(_ currentTime: TimeInterval) {
        if tiles.values.contains(where: \.isAnimating) {
            idleFrames = 0
        } else {
            // Let a couple of frames render the final state before pausing.
            idleFrames += 1
            if idleFrames > 2 {
                view?.isPaused = true
            }
        }
    }

    /// Applies a state that arrived since the last frame. New states wait for
    /// a live frame: the first frame after the view was paused sees the whole
    /// idle stretch as elapsed time, and animations started before it would
    /// jump straight to their end. Applied here, after this frame's actions
    /// have run, new animations start cleanly on the next frame.
    override func didFinishUpdate() {
        if let pending {
            self.pending = nil
            applyNow(pending)
        }
    }

    private func wake() {
        idleFrames = 0
        view?.isPaused = false
    }

    func apply(_ new: BoardState) {
        pending = new
        wake()
    }

    private func applyNow(_ new: BoardState) {
        let old = state
        state = new
        backgroundColor = new.tableColor.uiColor
        guard let old, old.dealSeed == new.dealSeed, old.layout == new.layout, old.faces == new.faces,
              old.allowSideways == new.allowSideways else {
            rebuild()
            return
        }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        for i in new.layout.positions.indices {
            guard let tile = tiles[i] else { continue }
            if old.present[i] != new.present[i] {
                tile.setPresent(new.present[i], animated: true, reduceMotion: reduceMotion)
            }
            tile.isDimmed = new.dimBlocked && !new.free[i]
        }
        if old.selected != new.selected {
            old.selected.map { tiles[$0]?.isSelected = false }
            new.selected.map { tiles[$0]?.isSelected = true }
        }
        if let shake = new.shake, shake != old.shake {
            for i in shake.tiles {
                tiles[i]?.signalBlocked(distance: (metrics?.tileWidth ?? 40) * 0.06, reduceMotion: reduceMotion)
            }
        }
        if let hint = new.hint, hint != old.hint {
            hint.tiles.forEach { tiles[$0]?.pulseHint() }
        }
        refreshAccessibility()
    }

    // MARK: Layout

    /// Tile sizes in points. Everything scales with the tile width.
    struct Metrics {
        static let tileAspect = 0.75          // top face width / height
        static let depthRatio = 0.13          // layer thickness / tile width
        static let shadowRatio = 0.12         // shadow reach / tile width

        let tileWidth: CGFloat
        let origin: CGPoint                   // view coords, y down

        var tileHeight: CGFloat { tileWidth / Self.tileAspect }
        var depth: CGFloat { tileWidth * Self.depthRatio }

        /// Top-left of a tile's top face, in view coordinates (y down).
        func topLeft(_ p: Position) -> CGPoint {
            CGPoint(
                x: origin.x + CGFloat(p.x) / 2 * tileWidth - CGFloat(p.z) * depth,
                y: origin.y + CGFloat(p.y) / 2 * tileHeight - CGFloat(p.z) * depth)
        }

        /// The tile's whole footprint on screen, top face plus visible sides.
        func hitRect(_ p: Position) -> CGRect {
            CGRect(origin: topLeft(p), size: CGSize(width: tileWidth + depth, height: tileHeight + depth))
        }

        /// The largest tiles that fit the layout in `size`, centered.
        static func fitting(_ layout: Layout, in size: CGSize) -> Metrics {
            // Bounds at a tile width of 1; everything is linear in it.
            let unit = Metrics(tileWidth: 1, origin: .zero)
            let rects = layout.positions.map(unit.hitRect)
            let bounds = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
                .insetBy(dx: -shadowRatio, dy: -shadowRatio)
            let margin: CGFloat = 12
            let scale = min((size.width - 2 * margin) / bounds.width, (size.height - 2 * margin) / bounds.height)
            let used = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            return Metrics(
                tileWidth: scale,
                origin: CGPoint(
                    x: (size.width - used.width) / 2 - bounds.minX * scale,
                    y: (size.height - used.height) / 2 - bounds.minY * scale))
        }
    }

    private func rebuild() {
        wake()
        board.removeAllChildren()
        tiles = [:]
        guard let state, size.width > 1, size.height > 1 else { return }
        let upright = Metrics.fitting(state.layout, in: size)
        let turnedSize = CGSize(width: size.height, height: size.width)
        let turned = Metrics.fitting(state.layout, in: turnedSize)
        let rotate = state.allowSideways
            && upright.tileWidth < Self.comfortableTileWidth
            && turned.tileWidth >= upright.tileWidth * Self.rotationGain
        let metrics = rotate ? turned : upright
        self.metrics = metrics
        canvas = rotate ? turnedSize : size
        // A quarter turn counterclockwise: tile tops face the left edge, so
        // turning the phone to the usual landscape grip makes them upright.
        container.zRotation = rotate ? .pi / 2 : 0
        container.position = CGPoint(x: size.width / 2, y: size.height / 2)
        board.position = CGPoint(x: -canvas.width / 2, y: -canvas.height / 2)
        setZoom(1, keeping: nil)
        drawOrder = BoardState.drawOrder(for: state.layout)
        if geometry?.layout != state.layout {
            geometry = LayoutGeometry(state.layout)
        }

        let art = TileArtwork(metrics: metrics, scale: view?.contentScaleFactor ?? 3)
        let textures = TileNode.Textures(
            body: SKTexture(image: art.body), bodyAnchor: art.bodyAnchor,
            selection: SKTexture(image: art.selection), hint: SKTexture(image: art.hint),
            blockedFlash: SKTexture(image: art.blockedFlash), dim: SKTexture(image: art.dim),
            faceSize: art.faceSize(aspect: tileset.info.faceAspect))
        for (rank, i) in drawOrder.enumerated() {
            let node = TileNode(textures: textures, face: faceTexture(state.faces[i]), metrics: metrics)
            let topLeft = metrics.topLeft(state.layout.positions[i])
            node.position = CGPoint(x: topLeft.x, y: canvas.height - topLeft.y)
            node.zPosition = CGFloat(rank)
            node.setPresent(state.present[i], animated: false, reduceMotion: true)
            node.isSelected = state.selected == i
            node.isDimmed = state.dimBlocked && !state.free[i]
            board.addChild(node)
            tiles[i] = node
        }
        refreshAccessibility()
    }

    private func faceTexture(_ face: Face) -> SKTexture {
        if let texture = faceTextures[face] {
            return texture
        }
        let texture = SKTexture(image: tileset.image(for: face))
        faceTextures[face] = texture
        return texture
    }

    // MARK: Zoom and pan

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
        // Pinch and pan run together, like a map. Otherwise, once zoomed, the
        // pan grabs the first finger of a pinch and the pinch never starts.
        pinch.delegate = self
        pan.delegate = self
        // Both cancel the touch, so a drag never also taps a tile.
        [pinch, pan].forEach(view.addGestureRecognizer)
    }

    @objc private func pinched(_ pinch: UIPinchGestureRecognizer) {
        guard let view, pinch.state == .changed || pinch.state == .ended else { return }
        wake()
        let focus = convertPoint(fromView: pinch.location(in: view))
        setZoom(zoom * pinch.scale, keeping: focus)
        pinch.scale = 1
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        guard let view, pan.state == .changed || pan.state == .ended else { return }
        wake()
        let t = pan.translation(in: view)
        // View coordinates grow downward; the scene's grow upward.
        container.position.x += t.x
        container.position.y -= t.y
        clampPan()
        pan.setTranslation(.zero, in: view)
    }

    /// Only pan when zoomed in; at 1× the whole board is already on screen.
    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        !(recognizer is UIPanGestureRecognizer) || zoom > 1
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    /// Sets the zoom, keeping the scene point `focus` (if given) under the
    /// same spot on screen.
    private func setZoom(_ newZoom: CGFloat, keeping focus: CGPoint?) {
        let z = min(max(newZoom, 1), Self.maxZoom)
        if let focus {
            let local = convert(focus, to: container)
            container.setScale(z)
            let moved = convert(local, from: container)
            container.position.x += focus.x - moved.x
            container.position.y += focus.y - moved.y
        } else {
            container.setScale(z)
        }
        zoom = z
        clampPan()
    }

    /// Keeps the zoomed board covering the view: no panning past its edges,
    /// and centered again at 1×.
    private func clampPan() {
        let rotated = container.zRotation != 0
        let extent = CGSize(
            width: (rotated ? canvas.height : canvas.width) * zoom,
            height: (rotated ? canvas.width : canvas.height) * zoom)
        let slackX = max(0, (extent.width - size.width) / 2)
        let slackY = max(0, (extent.height - size.height) / 2)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        container.position.x = min(max(container.position.x, center.x - slackX), center.x + slackX)
        container.position.y = min(max(container.position.y, center.y - slackY), center.y + slackY)
        refreshAccessibility()
    }

    // MARK: Accessibility

    private func refreshAccessibility() {
        guard view != nil, let state, let metrics, let geometry else { return }
        accessibility.update(state: state, geometry: geometry, frame: { i in
            self.viewFrame(of: metrics.hitRect(state.layout.positions[i]))
        }, onTap: { [weak self] i in self?.onTap?(i) })
    }

    /// Converts a rect on the upright canvas (y down) to view coordinates,
    /// through the board's rotation, zoom and pan.
    private func viewFrame(of rect: CGRect) -> CGRect {
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
        ].map { p in
            convertPoint(toView: board.convert(CGPoint(x: p.x, y: canvas.height - p.y), to: self))
        }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    // MARK: Input

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let state, let metrics else { return }
        let p = touch.location(in: board)
        let viewPoint = CGPoint(x: p.x, y: canvas.height - p.y)
        // Front-most tile under the finger wins.
        for i in drawOrder.reversed() where state.present[i] {
            if metrics.hitRect(state.layout.positions[i]).contains(viewPoint) {
                onTap?(i)
                return
            }
        }
    }
}

/// One tile: pre-rendered body (sides, top and shadow), face art, and state
/// overlays. Positioned at the top-left of its top face.
@MainActor
private final class TileNode: SKNode {
    struct Textures {
        let body: SKTexture
        let bodyAnchor: CGPoint
        let selection: SKTexture
        let hint: SKTexture
        let blockedFlash: SKTexture
        let dim: SKTexture
        let faceSize: CGSize
    }

    private let selection: SKSpriteNode
    private let hint: SKSpriteNode
    private let blockedFlash: SKSpriteNode
    private let dim: SKSpriteNode

    init(textures: Textures, face: SKTexture, metrics: SpriteBoardScene.Metrics) {
        func overlay(_ texture: SKTexture, z: CGFloat) -> SKSpriteNode {
            let sprite = SKSpriteNode(texture: texture)
            sprite.anchorPoint = CGPoint(x: 0, y: 1)
            sprite.zPosition = z
            sprite.alpha = 0
            return sprite
        }
        dim = overlay(textures.dim, z: 0.2)
        selection = overlay(textures.selection, z: 0.3)
        hint = overlay(textures.hint, z: 0.4)
        blockedFlash = overlay(textures.blockedFlash, z: 0.5)
        super.init()

        let body = SKSpriteNode(texture: textures.body)
        body.anchorPoint = textures.bodyAnchor
        addChild(body)

        let faceSprite = SKSpriteNode(texture: face, size: textures.faceSize)
        faceSprite.position = CGPoint(x: metrics.tileWidth / 2, y: -metrics.tileHeight / 2)
        faceSprite.zPosition = 0.1
        addChild(faceSprite)

        [dim, selection, hint, blockedFlash].forEach(addChild)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    var isAnimating: Bool {
        hasActions() || hint.hasActions() || blockedFlash.hasActions()
    }

    var isSelected = false {
        didSet { selection.alpha = isSelected ? 1 : 0 }
    }

    var isDimmed = false {
        didSet { dim.alpha = isDimmed ? 1 : 0 }
    }

    func setPresent(_ present: Bool, animated: Bool, reduceMotion: Bool) {
        removeAction(forKey: "presence")
        setScale(1)
        guard animated else {
            isHidden = !present
            alpha = 1
            return
        }
        if present {
            isHidden = false
            alpha = 0
            run(.fadeIn(withDuration: 0.15), withKey: "presence")
        } else {
            // A slight lift as it fades, unless motion is reduced.
            let fade = SKAction.fadeOut(withDuration: 0.15)
            let out = reduceMotion ? fade : .group([fade, .scale(to: 1.04, duration: 0.15)])
            run(.sequence([out, .hide(), .scale(to: 1, duration: 0)]), withKey: "presence")
        }
    }

    /// Feedback for tapping a blocked tile: a tiny shake, or a brief tint when
    /// motion is reduced.
    func signalBlocked(distance: CGFloat, reduceMotion: Bool) {
        if reduceMotion {
            blockedFlash.removeAllActions()
            blockedFlash.run(.sequence([.fadeIn(withDuration: 0.08), .fadeOut(withDuration: 0.25)]))
            return
        }
        // Starting over mid-shake would leave the tile off its resting spot.
        guard action(forKey: "shake") == nil else { return }
        let x = position.x
        let step = 0.04
        run(.sequence([
            .moveTo(x: x + distance, duration: step),
            .moveTo(x: x - distance, duration: step * 2),
            .moveTo(x: x + distance / 2, duration: step * 1.5),
            .moveTo(x: x, duration: step),
        ]), withKey: "shake")
    }

    /// Two gentle glows, for the Hint button. A fade, so it suits Reduce Motion
    /// as well.
    func pulseHint() {
        hint.removeAllActions()
        let glow = SKAction.sequence([.fadeIn(withDuration: 0.2), .fadeOut(withDuration: 0.35)])
        glow.timingMode = .easeInEaseOut
        hint.alpha = 0
        hint.run(.repeat(glow, count: 2))
    }
}
