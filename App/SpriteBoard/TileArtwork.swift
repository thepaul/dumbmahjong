import UIKit

/// Draws the shared tile images for the 2.5D board with Core Graphics: an
/// ivory top over a green back, extruded down-right, with a soft shadow.
@MainActor
struct TileArtwork {
    static let ivory = UIColor(red: 0.97, green: 0.94, blue: 0.86, alpha: 1)
    static let ivoryShade = UIColor(red: 0.90, green: 0.86, blue: 0.75, alpha: 1)
    static let ivorySide = UIColor(red: 0.84, green: 0.79, blue: 0.67, alpha: 1)
    static let back = UIColor(red: 0.10, green: 0.42, blue: 0.33, alpha: 1)
    static let backSide = UIColor(red: 0.07, green: 0.30, blue: 0.24, alpha: 1)

    let metrics: SpriteBoardScene.Metrics
    let scale: CGFloat

    private var w: CGFloat { metrics.tileWidth }
    private var h: CGFloat { metrics.tileHeight }
    private var d: CGFloat { metrics.depth }
    private var pad: CGFloat { metrics.tileWidth * SpriteBoardScene.Metrics.shadowRatio + 2 }
    private var radius: CGFloat { w * 0.1 }

    private var bodySize: CGSize { CGSize(width: w + d + 2 * pad, height: h + d + 2 * pad) }

    /// Anchor that puts the top face's top-left corner at the node origin.
    var bodyAnchor: CGPoint {
        CGPoint(x: pad / bodySize.width, y: 1 - pad / bodySize.height)
    }

    func faceSize(aspect: Double) -> CGSize {
        let box = CGSize(width: w * 0.86, height: h * 0.88)
        let a = CGFloat(aspect)
        return box.width / box.height > a
            ? CGSize(width: box.height * a, height: box.height)
            : CGSize(width: box.width, height: box.width / a)
    }

    var body: UIImage {
        renderer(size: bodySize).image { context in
            let cg = context.cgContext
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: d * 0.5, height: d * 0.6), blur: d * 1.4,
                         color: UIColor.black.withAlphaComponent(0.45).cgColor)
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            // Extrude by stamping the outline from the back forward.
            let step = 1 / scale
            var t = d
            while t > 0 {
                let color = t > d * 0.45 ? (t > d * 0.9 ? Self.backSide : Self.back) : Self.ivorySide
                color.setFill()
                rounded(CGRect(x: pad + t, y: pad + t, width: w, height: h)).fill()
                t -= step
            }
            // The light comes from the upper left, so the right side sits a
            // little deeper in shadow than the bottom. Blend softly across the
            // corner so there's no seam.
            cg.saveGState()
            cg.setBlendMode(.sourceAtop)
            let shade = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor.black.withAlphaComponent(0).cgColor,
                         UIColor.black.withAlphaComponent(0.14).cgColor] as CFArray,
                locations: [0, 1])!
            cg.drawLinearGradient(shade, start: CGPoint(x: pad + w - radius, y: 0),
                                  end: CGPoint(x: pad + w + d * 0.3, y: 0),
                                  options: [.drawsAfterEndLocation])
            cg.restoreGState()
            // Top face with a gentle top-left to bottom-right falloff.
            let top = rounded(CGRect(x: pad, y: pad, width: w, height: h))
            cg.saveGState()
            top.addClip()
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [Self.ivory.cgColor, Self.ivoryShade.cgColor] as CFArray, locations: [0.35, 1])!
            cg.drawLinearGradient(gradient, start: CGPoint(x: pad, y: pad),
                                  end: CGPoint(x: pad + w, y: pad + h), options: [])
            cg.restoreGState()
            cg.endTransparencyLayer()
            cg.restoreGState()
            // Crisp edges: a light inner rim and a darker outline.
            UIColor.white.withAlphaComponent(0.7).setStroke()
            let rim = rounded(CGRect(x: pad + 1, y: pad + 1, width: w - 2, height: h - 2), radius: radius - 1)
            rim.lineWidth = 1
            rim.stroke()
            Self.ivorySide.withAlphaComponent(0.9).setStroke()
            top.lineWidth = 0.75
            top.stroke()
        }
    }

    /// Warm tint and outline for the selected tile.
    var selection: UIImage {
        overlay(fill: UIColor(red: 1, green: 0.78, blue: 0.2, alpha: 0.38),
                stroke: UIColor(red: 0.85, green: 0.55, blue: 0.0, alpha: 0.9))
    }

    /// Cool glow for hinted tiles.
    var hint: UIImage {
        overlay(fill: UIColor(red: 0.55, green: 0.85, blue: 1, alpha: 0.4),
                stroke: UIColor(red: 0.1, green: 0.5, blue: 0.85, alpha: 0.9))
    }

    /// Brief flash on a blocked tile when motion is reduced (instead of a shake).
    var blockedFlash: UIImage {
        overlay(fill: UIColor(red: 0.85, green: 0.2, blue: 0.15, alpha: 0.25), stroke: nil)
    }

    /// Darkens blocked tiles in "dim blocked tiles" mode.
    var dim: UIImage {
        overlay(fill: UIColor(red: 0.1, green: 0.08, blue: 0.0, alpha: 0.3), stroke: nil)
    }

    /// An image covering the top face, for state overlays.
    private func overlay(fill: UIColor, stroke: UIColor?) -> UIImage {
        renderer(size: CGSize(width: w, height: h)).image { _ in
            fill.setFill()
            rounded(CGRect(x: 0, y: 0, width: w, height: h)).fill()
            if let stroke {
                stroke.setStroke()
                let outline = rounded(CGRect(x: 1, y: 1, width: w - 2, height: h - 2), radius: radius - 1)
                outline.lineWidth = 2
                outline.stroke()
            }
        }
    }

    private func rounded(_ rect: CGRect, radius r: CGFloat? = nil) -> UIBezierPath {
        UIBezierPath(roundedRect: rect, cornerRadius: r ?? radius)
    }

    private func renderer(size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format)
    }
}
