import MahjongCore
import RealityKit
import SwiftUI

/// 3D board: rounded two-layer tiles (ivory over green) on a felt table, lit by
/// one shadow-casting key light and seen through a fixed, slightly tilted camera.
struct RealityBoardView: View {
    let state: BoardState
    let tileset: Tileset
    let onTap: (Int) -> Void

    @State private var board = RealityBoard()

    var body: some View {
        GeometryReader { geometry in
            RealityView { content in
                content.camera = .virtual
                await board.setUp(tileset: tileset)
                content.add(board.root)
            } update: { _ in
                board.apply(state, viewSize: geometry.size)
            }
            .ignoresSafeArea(edges: .horizontal)
            .gesture(
                SpatialTapGesture()
                    .targetedToAnyEntity()
                    .onEnded { value in
                        if let index = board.tileIndex(of: value.entity) {
                            onTap(index)
                        }
                    })
        }
        .background(Color.felt)
    }
}

@MainActor
final class RealityBoard {
    // Tile size in meters-ish world units: width (x), length (z), thickness (y).
    static let width: Float = 1.0
    static let length: Float = 1.3
    static let thickness: Float = 0.62
    static let gap: Float = 0.03
    static let tilt: Float = 34 * .pi / 180      // camera angle away from straight down
    static let fieldOfView: Float = 28           // degrees, vertical

    let root = Entity()
    private let camera = PerspectiveCamera()
    private let table = ModelEntity()
    private var tiles: [Int: TileEntity] = [:]
    private var state: BoardState?
    private var viewSize: CGSize = .zero

    private var faceMaterials: [Face: UnlitMaterial] = [:]
    private var bone = PhysicallyBasedMaterial()
    private var boneSelected = PhysicallyBasedMaterial()
    private var back = PhysicallyBasedMaterial()
    private var boneMesh: MeshResource?
    private var backMesh: MeshResource?
    private var faceMesh: MeshResource?

    func setUp(tileset: Tileset) async {
        bone = Self.material(red: 0.95, green: 0.92, blue: 0.84, roughness: 0.32, clearcoat: 0.5)
        boneSelected = Self.material(red: 1.0, green: 0.82, blue: 0.42, roughness: 0.32, clearcoat: 0.5)
        back = Self.material(red: 0.08, green: 0.38, blue: 0.29, roughness: 0.4, clearcoat: 0.3)

        let w = Self.width - Self.gap, l = Self.length - Self.gap, t = Self.thickness
        boneMesh = MeshResource.generateBox(width: w, height: t * 0.58, depth: l, cornerRadius: 0.09)
        backMesh = MeshResource.generateBox(width: w, height: t * 0.44, depth: l, cornerRadius: 0.09)
        let aspect = Float(tileset.info.faceAspect)
        let faceLength = l * 0.86
        faceMesh = MeshResource.generatePlane(width: min(w * 0.86, faceLength * aspect), depth: faceLength)

        for face in Face.allCases {
            guard let cgImage = tileset.image(for: face).cgImage,
                  let texture = try? await TextureResource(image: cgImage, options: .init(semantic: .color)) else {
                continue
            }
            // Unlit and outside tone mapping, so the ink keeps its true color.
            var material = UnlitMaterial(applyPostProcessToneMap: false)
            material.color = .init(texture: .init(texture))
            material.blending = .transparent(opacity: 1.0)
            faceMaterials[face] = material
        }

        var felt = PhysicallyBasedMaterial()
        felt.baseColor = .init(tint: UIColor(red: 0.12, green: 0.36, blue: 0.24, alpha: 1))
        felt.roughness = .init(floatLiteral: 1)
        table.model = ModelComponent(mesh: .generatePlane(width: 200, depth: 200), materials: [felt])
        root.addChild(table)

        let light = DirectionalLight()
        light.light.intensity = 1000
        light.shadow = DirectionalLightComponent.Shadow(maximumDistance: 40, depthBias: 1.5)
        light.look(at: .zero, from: [-5, 12, -4], relativeTo: nil)
        root.addChild(light)

        let fill = PointLight()
        fill.light.intensity = 3_000
        fill.light.attenuationRadius = 60
        fill.position = [6, 10, 14]
        root.addChild(fill)

        camera.camera.fieldOfViewInDegrees = Self.fieldOfView
        root.addChild(camera)
    }

    func apply(_ new: BoardState, viewSize: CGSize) {
        let old = state
        state = new
        if viewSize != self.viewSize {
            self.viewSize = viewSize
            if old != nil { frameCamera(on: new.layout) }
        }
        guard let old, old.dealSeed == new.dealSeed, old.layout == new.layout, old.faces == new.faces else {
            rebuild(new)
            return
        }
        for i in new.layout.positions.indices where old.present[i] != new.present[i] {
            tiles[i]?.setPresent(new.present[i], animated: true)
        }
        if old.selected != new.selected {
            old.selected.map { tiles[$0]?.setTopMaterial(bone) }
            new.selected.map { tiles[$0]?.setTopMaterial(boneSelected) }
        }
        if let shake = new.shake, shake != old.shake {
            tiles[shake.index]?.shake()
        }
    }

    func tileIndex(of entity: Entity) -> Int? {
        var current: Entity? = entity
        while let e = current {
            if let tile = e as? TileEntity {
                return tile.index
            }
            current = e.parent
        }
        return nil
    }

    private func rebuild(_ state: BoardState) {
        tiles.values.forEach { $0.removeFromParent() }
        tiles = [:]
        guard let boneMesh, let backMesh, let faceMesh else { return }
        let center = Self.center(of: state.layout)
        for (i, p) in state.layout.positions.enumerated() {
            guard let faceMaterial = faceMaterials[state.faces[i]] else { continue }
            let tile = TileEntity(
                index: i, boneMesh: boneMesh, bone: state.selected == i ? boneSelected : bone,
                backMesh: backMesh, back: back, faceMesh: faceMesh, face: faceMaterial)
            tile.restingPosition = Self.worldPosition(p) - center
            tile.setPresent(state.present[i], animated: false)
            root.addChild(tile)
            tiles[i] = tile
        }
        frameCamera(on: state.layout)
    }

    /// Center of the tile footprint, at table height.
    private static func worldPosition(_ p: Position) -> SIMD3<Float> {
        [(Float(p.x) / 2 + 0.5) * width, (Float(p.z) + 0.5) * thickness, (Float(p.y) / 2 + 0.5) * length]
    }

    private static func center(of layout: MahjongCore.Layout) -> SIMD3<Float> {
        let ps = layout.positions.map(worldPosition)
        let lo = ps.reduce(ps[0]) { pointwiseMin($0, $1) }, hi = ps.reduce(ps[0]) { pointwiseMax($0, $1) }
        return [(lo.x + hi.x) / 2, 0, (lo.z + hi.z) / 2]
    }

    /// Moves the camera back until every tile corner projects inside the view.
    private func frameCamera(on layout: MahjongCore.Layout) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        let center = Self.center(of: layout)
        var corners: [SIMD3<Float>] = []
        for p in layout.positions {
            let c = Self.worldPosition(p) - center
            for dx in [-Self.width / 2, Self.width / 2] {
                for dy in [-Self.thickness / 2, Self.thickness / 2] {
                    for dz in [-Self.length / 2, Self.length / 2] {
                        corners.append(c + [dx, dy, dz])
                    }
                }
            }
        }
        // Camera basis: looking along -back, tilted toward the player.
        let back: SIMD3<Float> = [0, cos(Self.tilt), sin(Self.tilt)]
        let up = normalize(cross(back, [1, 0, 0])) * -1
        let right = cross(up, back)
        let tanV = tan(Self.fieldOfView / 2 * .pi / 180)
        let tanH = tanV * Float(viewSize.width / viewSize.height)
        let margin: Float = 0.97
        // For each corner, the distance along `back` at which it just fits.
        var distance: Float = 0
        for c in corners {
            let x = abs(dot(c, right)), y = abs(dot(c, up)), z = dot(c, back)
            distance = max(distance, z + x / (tanH * margin), z + y / (tanV * margin))
        }
        camera.look(at: .zero, from: distance * back, relativeTo: nil)
    }

    private static func material(red: CGFloat, green: CGFloat, blue: CGFloat, roughness: Float,
                                 clearcoat: Float) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: red, green: green, blue: blue, alpha: 1))
        m.roughness = .init(floatLiteral: roughness)
        m.clearcoat = .init(floatLiteral: clearcoat)
        m.clearcoatRoughness = .init(floatLiteral: 0.2)
        return m
    }
}

/// One tile: green back, ivory top and face decal, with a collision box for taps.
@MainActor
private final class TileEntity: Entity {
    let index: Int
    private let top: ModelEntity
    var restingPosition: SIMD3<Float> = .zero {
        didSet { position = restingPosition }
    }

    init(index: Int, boneMesh: MeshResource, bone: PhysicallyBasedMaterial, backMesh: MeshResource,
         back: PhysicallyBasedMaterial, faceMesh: MeshResource, face: UnlitMaterial) {
        self.index = index
        top = ModelEntity(mesh: boneMesh, materials: [bone])
        super.init()
        let t = RealityBoard.thickness
        let backPart = ModelEntity(mesh: backMesh, materials: [back])
        backPart.position.y = -t * 0.28
        top.position.y = t * 0.21
        let decal = ModelEntity(mesh: faceMesh, materials: [face])
        decal.position.y = t * 0.5 + 0.002
        addChild(backPart)
        addChild(top)
        addChild(decal)
        components.set(CollisionComponent(shapes: [
            .generateBox(width: RealityBoard.width, height: t, depth: RealityBoard.length),
        ]))
        components.set(InputTargetComponent())
    }

    @MainActor required init() {
        fatalError("not used")
    }

    func setTopMaterial(_ material: PhysicallyBasedMaterial) {
        top.model?.materials = [material]
    }

    func setPresent(_ present: Bool, animated: Bool) {
        guard animated else {
            isEnabled = present
            position = restingPosition
            return
        }
        if present {
            position = restingPosition + [0, RealityBoard.thickness, 0]
            isEnabled = true
            move(to: Transform(translation: restingPosition), relativeTo: parent, duration: 0.15)
        } else {
            move(to: Transform(scale: .init(repeating: 0.92), translation: restingPosition + [0, RealityBoard.thickness, 0]),
                 relativeTo: parent, duration: 0.15)
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard let self else { return }
                self.isEnabled = false
                self.transform = Transform(translation: self.restingPosition)
            }
        }
    }

    func shake() {
        let d: Float = 0.06
        Task { [weak self] in
            for dx in [d, -d, d / 2, 0] {
                guard let self else { return }
                self.move(to: Transform(translation: self.restingPosition + [dx, 0, 0]), relativeTo: self.parent,
                          duration: 0.04)
                try? await Task.sleep(for: .milliseconds(45))
            }
        }
    }
}
