import CoreGraphics
import Foundation
import ImageIO
import SunCore

/// Renders the moon as it looks now: NASA's LRO albedo map (MoonTexture.png, made by
/// ios/tools/make_moon_texture.py) lit for the current phase.
///
/// Lighting is Lommel-Seeliger, the usual model for the moon's regolith: it gives a
/// soft terminator and, unlike a matte (Lambert) sphere, an evenly bright full moon.
/// The dark side gets faint bluish earthshine. Images are cached per phase and size,
/// since the phase changes by under 1% an hour.
enum MoonRenderer {
    private struct Texture {
        let width: Int
        let height: Int
        /// Premultiplied RGBA.
        let pixels: [UInt8]
    }

    private struct Key: Hashable {
        let illumination: Int // per mille
        let waxing: Bool
        let southern: Bool
        let pixels: Int
        let monochrome: Bool
        /// Umbral coverage during a lunar eclipse, in twentieths.
        let shadow: Int
    }

    private static let texture: Texture? = loadTexture()
    private static var cache: [Key: CGImage] = [:]

    /// A `pixels` × `pixels` image of the moon disc with transparent corners.
    /// `shadow` (0...1) is how far the moon is inside Earth's umbra during a lunar
    /// eclipse: it darkens and reddens, as it does in the real sky.
    static func image(phase: LunarCalculator.Phase, southern: Bool, pixels: Int, monochrome: Bool = false, shadow: Double = 0) -> CGImage? {
        let key = Key(
            illumination: Int((phase.illumination * 1000).rounded()),
            waxing: phase.isWaxing,
            southern: southern,
            pixels: max(pixels, 8),
            monochrome: monochrome,
            shadow: Int((min(max(shadow, 0), 1) * 20).rounded())
        )
        if let cached = cache[key] { return cached }
        guard let image = render(key) else { return nil }
        if cache.count > 24 { cache.removeAll() }
        cache[key] = image
        return image
    }

    private static func render(_ key: Key) -> CGImage? {
        let n = key.pixels
        var out = [UInt8](repeating: 0, count: n * n * 4)
        // Sun direction in view space (x right, y up, z toward the viewer). From the
        // northern hemisphere a waxing moon is lit on the right.
        let k = Double(key.illumination) / 1000
        let elongation = acos(min(max(1 - 2 * k, -1), 1))
        let side: Double = (key.waxing != key.southern) ? 1 : -1
        let sunX = side * sin(elongation), sunZ = -cos(elongation)
        let half = Double(n) / 2

        for row in 0..<n {
            for col in 0..<n {
                let x = (Double(col) + 0.5 - half) / half
                let y = (half - Double(row) - 0.5) / half
                let r2 = x * x + y * y
                guard r2 < 1.0 + 2 / half else { continue }
                let alpha = min(max((1 - r2.squareRoot()) * half, 0), 1)
                guard alpha > 0 else { continue }
                let z = max(1 - r2, 0).squareRoot()

                let mu0 = x * sunX + z * sunZ
                let lit = mu0 > 0 ? min(2 * mu0 / (mu0 + z + 1e-6), 1) : 0

                // From the southern hemisphere the moon appears rotated 180 degrees.
                var (red, green, blue) = sampleTexture(key.southern ? -x : x, key.southern ? -y : y)
                if key.monochrome {
                    let gray = 0.3 * red + 0.59 * green + 0.11 * blue
                    (red, green, blue) = (gray, gray, gray)
                }
                let earthshine = 0.07 * (1 - lit)
                var rOut = min(red * 1.15 * lit + red * earthshine * 0.6, 1)
                var gOut = min(green * 1.15 * lit + green * earthshine * 0.7, 1)
                var bOut = min(blue * 1.15 * lit + blue * earthshine * 1.0, 1)
                if key.shadow > 0 {
                    // Sunlight bent through Earth's atmosphere: a dim copper-red moon.
                    let s = Double(key.shadow) / 20
                    let gray = 0.3 * rOut + 0.59 * gOut + 0.11 * bOut
                    rOut = rOut * (1 - s) + gray * 0.85 * s
                    gOut = gOut * (1 - s) + gray * 0.22 * s
                    bOut = bOut * (1 - s) + gray * 0.10 * s
                }

                // Like the real moon in a lit sky, the unlit part is mostly see-through:
                // just a hint of the disc (with its earthshine) over whatever is behind.
                let a = alpha * (0.18 + 0.82 * min(lit * 2, 1))
                let i = (row * n + col) * 4
                out[i] = UInt8(rOut * a * 255)
                out[i + 1] = UInt8(gOut * a * 255)
                out[i + 2] = UInt8(bOut * a * 255)
                out[i + 3] = UInt8(a * 255)
            }
        }

        guard
            let provider = CGDataProvider(data: Data(out) as CFData),
            let image = CGImage(
                width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
            )
        else { return nil }
        return image
    }

    /// Bilinear sample of the albedo texture at disc coordinates (-1...1, y up).
    /// Without the texture, a plain moon-gray.
    private static func sampleTexture(_ x: Double, _ y: Double) -> (Double, Double, Double) {
        guard let t = texture else { return (0.78, 0.77, 0.74) }
        let u = min(max((x + 1) / 2 * Double(t.width - 1), 0), Double(t.width - 1))
        let v = min(max((1 - y) / 2 * Double(t.height - 1), 0), Double(t.height - 1))
        let u0 = Int(u), v0 = Int(v)
        let u1 = min(u0 + 1, t.width - 1), v1 = min(v0 + 1, t.height - 1)
        let fu = u - Double(u0), fv = v - Double(v0)
        func px(_ cu: Int, _ cv: Int) -> (Double, Double, Double) {
            let i = (cv * t.width + cu) * 4
            let a = Double(t.pixels[i + 3]) / 255
            guard a > 0 else { return (0.78, 0.77, 0.74) }
            return (Double(t.pixels[i]) / 255 / a, Double(t.pixels[i + 1]) / 255 / a, Double(t.pixels[i + 2]) / 255 / a)
        }
        let p00 = px(u0, v0), p10 = px(u1, v0), p01 = px(u0, v1), p11 = px(u1, v1)
        func mix(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
            (a * (1 - fu) + b * fu) * (1 - fv) + (c * (1 - fu) + d * fu) * fv
        }
        return (mix(p00.0, p10.0, p01.0, p11.0), mix(p00.1, p10.1, p01.1, p11.1), mix(p00.2, p10.2, p01.2, p11.2))
    }

    private static func loadTexture() -> Texture? {
        guard
            let url = Bundle.main.url(forResource: "MoonTexture", withExtension: "png"),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? Texture(width: width, height: height, pixels: pixels) : nil
    }
}
