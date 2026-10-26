import CoreGraphics
import Foundation
import ImageIO
import SunCore

/// Renders the sun's disc for its altitude: colored by `SkyGradient.sunColor`, with
/// limb darkening (stronger in blue, so the edge is warmer), a faint granulation, and a
/// center that stays brighter than any sky until the sun has set. The corona glow is
/// drawn separately by `SkyRingRenderer`. Cached per half degree and size.
///
/// The disc also carries real sunspots from NASA SDO's flattened HMI intensitygram
/// (SunSpots.jpg, from shared/tools/nasa_sources.json). It's bundled, so it updates only
/// with an app release, which is fine: it's texture, not data the app relies on.
enum SunRenderer {
    /// Brightness relative to the quiet sun, the disc filling the square.
    private struct Spots {
        let size: Int
        let values: [Float]
    }

    private static let spots: Spots? = loadSpots()

    private static func loadSpots() -> Spots? {
        guard
            let url = Bundle.main.url(forResource: "SunSpots", withExtension: "jpg"),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let size = min(image.width, image.height)
        var gray = [UInt8](repeating: 0, count: size * size)
        let drawn = gray.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn else { return nil }
        // Normalize to the median inside the disc, so the quiet sun is 1 and spots are below.
        var inside: [UInt8] = []
        for (i, v) in gray.enumerated() where i % 7 == 0 {
            let x = Double(i % size) / Double(size) - 0.5, y = Double(i / size) / Double(size) - 0.5
            if x * x + y * y < 0.16 { inside.append(v) }
        }
        inside.sort()
        let median = Float(max(inside.isEmpty ? 1 : inside[inside.count / 2], 1))
        return Spots(size: size, values: gray.map { min(1.05, Float($0) / median) })
    }

    /// At disc coordinates (-1...1, y up).
    private static func spot(_ x: Double, _ y: Double) -> Double {
        guard let spots else { return 1 }
        let px = min(spots.size - 1, max(0, Int((x + 1) / 2 * Double(spots.size))))
        let py = min(spots.size - 1, max(0, Int((1 - y) / 2 * Double(spots.size))))
        return max(0.25, Double(spots.values[py * spots.size + px]))
    }

    private struct Key: Hashable {
        let halfDegrees: Int
        let pixels: Int
        let monochrome: Bool
    }

    private static var cache: [Key: CGImage] = [:]

    static func image(altitude: Double, pixels: Int, monochrome: Bool = false) -> CGImage? {
        let key = Key(halfDegrees: Int((min(max(altitude, -20), 90) * 2).rounded()), pixels: max(pixels, 8), monochrome: monochrome)
        if let cached = cache[key] { return cached }
        guard let image = render(key) else { return nil }
        if cache.count > 32 { cache.removeAll() }
        cache[key] = image
        return image
    }

    private static func render(_ key: Key) -> CGImage? {
        let n = key.pixels
        let altitude = Double(key.halfDegrees) / 2
        let core = SkyGradient.sunColor(altitude: altitude).core
        let strength = altitude >= -0.833 ? 1 : max(0.3, 1 + (altitude + 0.833) / 25)
        // How much the center washes out toward pale yellow; none once the sun is down.
        let wash = 0.55 * min(max((altitude + 2) / 3, 0), 1)
        let limb = (red: 0.28, green: 0.40, blue: 0.55)
        let half = Double(n) / 2
        var out = [UInt8](repeating: 0, count: n * n * 4)

        for row in 0..<n {
            for col in 0..<n {
                let x = (Double(col) + 0.5 - half) / half
                let y = (half - Double(row) - 0.5) / half
                let d = (x * x + y * y).squareRoot()
                let alpha = min(max((1 - d) * half, 0), 1)
                guard alpha > 0 else { continue }
                let mu = max(1 - d * d, 0).squareRoot()

                let hot = pow(min(mu * 1.2, 1), 1.5) * wash
                // Real sunspots where the map has them, plus a faint granulation.
                let texture = (1 + 0.025 * granulation(x, y) * mu) * (d < 0.97 ? spot(x, y) : 1)
                func channel(_ base: Double, _ hotValue: Double, _ u: Double) -> Double {
                    let color = base * (1 - hot) + hotValue * hot
                    return min(color * (1 - u * (1 - mu)) * texture * 1.18, 1) * strength
                }
                var r = channel(core.red, 1.0, limb.red)
                var g = channel(core.green, 0.97, limb.green)
                var b = channel(core.blue, 0.86, limb.blue)
                if key.monochrome {
                    let gray = 0.3 * r + 0.59 * g + 0.11 * b
                    (r, g, b) = (gray, gray, gray)
                }
                let i = (row * n + col) * 4
                out[i] = UInt8(r * alpha * 255)
                out[i + 1] = UInt8(g * alpha * 255)
                out[i + 2] = UInt8(b * alpha * 255)
                out[i + 3] = UInt8(alpha * 255)
            }
        }

        guard let provider = CGDataProvider(data: Data(out) as CFData) else { return nil }
        return CGImage(
            width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    /// Fine, roughly cellular value noise in about -1...1: about 12 cells across the disc.
    private static func granulation(_ x: Double, _ y: Double) -> Double {
        let fx = (x + 1) * 6, fy = (y + 1) * 6
        let ix = floor(fx), iy = floor(fy)
        let tx = fx - ix, ty = fy - iy
        let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
        func hash(_ a: Double, _ b: Double) -> Double {
            let h = sin(a * 127.1 + b * 311.7) * 43_758.5453
            return (h - floor(h)) * 2 - 1
        }
        let top = hash(ix, iy) * (1 - sx) + hash(ix + 1, iy) * sx
        let bottom = hash(ix, iy + 1) * (1 - sx) + hash(ix + 1, iy + 1) * sx
        return top * (1 - sy) + bottom * sy
    }
}
