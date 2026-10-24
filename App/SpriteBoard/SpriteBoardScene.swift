import MahjongCore
import SpriteKit
import UIKit

/// 2.5D board: a fixed oblique view where each layer is shifted up and to the
/// left, so every tile shows its thickness on its right and bottom sides.
@MainActor
final class SpriteBoardScene: SKScene {
    var onTap: ((Int) -> Void)?

    private let tileset: Tileset
    private var state: BoardState?
    private var metrics: Metrics?
    private var drawOrder: [Int] = []
    private var tiles: [Int: TileNode] = [:]
    private var faceTextures: [Face: SKTexture] = [:]

    private let board = SKNode()

    init(tileset: Tileset) {
        self.tileset = tileset
        super.init(size: CGSize(width: 1, height: 1))
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = UIColor(red: 0.12, green: 0.36, blue: 0.24, alpha: 1)
        addChild(board)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        rebuild()
    }

    func apply(_ new: BoardState) {
        let old = state
        state = new
        guard let old, old.dealSeed == new.dealSeed, old.layout == new.layout, old.faces == new.faces else {
            rebuild()
            return
        }
        for i in new.layout.positions.indices where old.present[i] != new.present[i] {
            tiles[i]?.setPresent(new.present[i], animated: true)
        }
        if old.selected != new.selected {
            old.selected.map { tiles[$0]?.isSelected = false }
            new.selected.map { tiles[$0]?.isSelected = true }
        }
        if let shake = new.shake, shake != old.shake {
            tiles[shake.index]?.shake(distance: (metrics?.tileWidth ?? 40) * 0.06)
        }
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
        board.removeAllChildren()
        tiles = [:]
        guard let state, size.width > 1, size.height > 1 else { return }
        let metrics = Metrics.fitting(state.layout, in: size)
        self.metrics = metrics
        drawOrder = BoardState.drawOrder(for: state.layout)

        let art = TileArtwork(metrics: metrics, scale: view?.contentScaleFactor ?? 3)
        let body = SKTexture(image: art.body)
        let highlight = SKTexture(image: art.highlight)
        for (rank, i) in drawOrder.enumerated() {
            let face = state.faces[i]
            let node = TileNode(
                body: body, bodyAnchor: art.bodyAnchor, highlight: highlight,
                face: faceTexture(face), faceSize: art.faceSize(aspect: tileset.info.faceAspect),
                metrics: metrics)
            let topLeft = metrics.topLeft(state.layout.positions[i])
            node.position = CGPoint(x: topLeft.x, y: size.height - topLeft.y)
            node.zPosition = CGFloat(rank)
            node.setPresent(state.present[i], animated: false)
            node.isSelected = state.selected == i
            board.addChild(node)
            tiles[i] = node
        }
    }

    private func faceTexture(_ face: Face) -> SKTexture {
        if let texture = faceTextures[face] {
            return texture
        }
        let texture = SKTexture(image: tileset.image(for: face))
        faceTextures[face] = texture
        return texture
    }

    // MARK: Input

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let state, let metrics else { return }
        let p = touch.location(in: self)
        let viewPoint = CGPoint(x: p.x, y: size.height - p.y)
        // Front-most tile under the finger wins.
        for i in drawOrder.reversed() where state.present[i] {
            if metrics.hitRect(state.layout.positions[i]).contains(viewPoint) {
                onTap?(i)
                return
            }
        }
    }
}

/// One tile: pre-rendered body (sides, top and shadow), face art, and a
/// selection overlay. Positioned at the top-left of its top face.
@MainActor
private final class TileNode: SKNode {
    private let highlight: SKSpriteNode

    init(body: SKTexture, bodyAnchor: CGPoint, highlight: SKTexture, face: SKTexture, faceSize: CGSize,
         metrics: SpriteBoardScene.Metrics) {
        self.highlight = SKSpriteNode(texture: highlight)
        super.init()

        let bodySprite = SKSpriteNode(texture: body)
        bodySprite.anchorPoint = bodyAnchor
        addChild(bodySprite)

        let faceSprite = SKSpriteNode(texture: face, size: faceSize)
        faceSprite.position = CGPoint(x: metrics.tileWidth / 2, y: -metrics.tileHeight / 2)
        faceSprite.zPosition = 0.1
        addChild(faceSprite)

        self.highlight.anchorPoint = CGPoint(x: 0, y: 1)
        self.highlight.zPosition = 0.2
        self.highlight.isHidden = true
        addChild(self.highlight)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    var isSelected = false {
        didSet { highlight.isHidden = !isSelected }
    }

    func setPresent(_ present: Bool, animated: Bool) {
        removeAction(forKey: "presence")
        guard animated else {
            isHidden = !present
            alpha = 1
            setScale(1)
            return
        }
        if present {
            isHidden = false
            alpha = 0
            setScale(1)
            run(.fadeIn(withDuration: 0.15), withKey: "presence")
        } else {
            let out = SKAction.group([.fadeOut(withDuration: 0.15), .scale(to: 1.04, duration: 0.15)])
            run(.sequence([out, .hide(), .scale(to: 1, duration: 0)]), withKey: "presence")
        }
    }

    func shake(distance: CGFloat) {
        let x = position.x
        let step = 0.04
        run(.sequence([
            .moveTo(x: x + distance, duration: step),
            .moveTo(x: x - distance, duration: step * 2),
            .moveTo(x: x + distance / 2, duration: step * 1.5),
            .moveTo(x: x, duration: step),
        ]), withKey: "shake")
    }
}
