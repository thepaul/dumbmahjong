import MahjongCore
import UIKit

/// A set of face images built by `tools/build_tileset.py` into
/// Tilesets.xcassets, namespaced by tileset ID.
struct Tileset: Sendable {
    struct Info: Decodable, Sendable {
        let id: String
        let name: String
        /// Width over height of the face art.
        let faceAspect: Double
        let credits: String
    }

    let info: Info

    static let available: [Tileset] = ["commons"].compactMap(Tileset.init(id:))
    static let standard = available[0]

    init?(id: String) {
        guard let asset = NSDataAsset(name: "\(id)/tileset"),
              let info = try? JSONDecoder().decode(Info.self, from: asset.data) else {
            return nil
        }
        self.info = info
    }

    func image(for face: Face) -> UIImage {
        guard let image = UIImage(named: "\(info.id)/\(face.rawValue)") else {
            fatalError("Tileset \(info.id) is missing \(face.rawValue)")
        }
        return image
    }
}
