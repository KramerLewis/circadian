import CoreGraphics
import CoreText
import Foundation
import ImageIO
import SunCore
import SwiftUI

/// Draws the wadokei's kanji and zodiac animals (mirrors web/src/render/wadokei.ts).
///
/// In the molten style each one is a hole cut through the dial: looking in, you see its
/// inner walls (the band left where the floor, set back by a depth, no longer covers the
/// opening), the floor, an inner shadow where walls meet floor, a dark lip along the top
/// edge and a lit lip along the bottom. Idle holes are shallow and dark; the active one
/// has molten rock on the floor lighting the walls and glowing out of the opening.
/// Plain, silver and gold are printed on the dial instead, glowing when active, with a
/// highlight sweeping across the metals.
///
/// The kanji are a subset of Yuji Syuku (SunClockWadokei.ttf); the animals are masks
/// baked from shared/assets/zodiac by web/scripts/zodiac-masks.mjs (Zodiac-<animal>.png).
enum WadokeiRenderer {
    /// What a hole or print is made of.
    enum Ink {
        case kanji(String)
        case art(Image)

        var isText: Bool { if case .kanji = self { true } else { false } }
    }

    // MARK: Resources

    private static let fontName = "SunClockWadokei"

    /// Registered for this process on first use; falls back to the system's mincho.
    private static let fontRegistered: Bool = {
        guard let url = Bundle.main.url(forResource: "SunClockWadokei", withExtension: "ttf") else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    private static func font(size: CGFloat) -> Font {
        _ = fontRegistered
        return .custom(fontName, fixedSize: size)
    }

    private static let animals: [String: Image] = {
        var images: [String: Image] = [:]
        for kanji in ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"] {
            guard
                let animal = Wadokei.animal(for: kanji)?.lowercased(),
                let url = Bundle.main.url(forResource: "Zodiac-\(animal)", withExtension: "png"),
                let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { continue }
            images[kanji] = Image(decorative: image, scale: 1)
        }
        return images
    }()

    /// The hour's animal, white on clear.
    static func art(for kanji: String) -> Image? { animals[kanji] }

    // MARK: Drawing

    /// One kanji or animal, centered at `p`, `size` across.
    static func draw(_ ink: Ink, in context: inout GraphicsContext, at p: CGPoint, size: CGFloat,
                     style: KanjiStyle, active: Bool, time: Double?, dark: Bool) {
        if style == .molten {
            hole(ink, in: &context, at: p, size: size, time: time, molten: active, dark: dark)
        } else {
            flat(ink, in: &context, at: p, size: size, style: style, active: active, time: time, dark: dark)
        }
    }

    /// The ink in white, for clipping to.
    private static func mask(_ ink: Ink, in context: inout GraphicsContext, at p: CGPoint, size: CGFloat) {
        switch ink {
        case .kanji(let kanji):
            context.draw(Text(kanji).font(font(size: size)).foregroundStyle(.white), at: p)
        case .art(let image):
            context.draw(image, in: CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size))
        }
    }

    private static func box(_ ink: Ink, at p: CGPoint, size: CGFloat) -> CGRect {
        let side = size * (ink.isText ? 1.4 : 1.1)
        return CGRect(x: p.x - side / 2, y: p.y - side / 2, width: side, height: side)
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255).opacity(a)
    }

    private static func hole(_ ink: Ink, in context: inout GraphicsContext, at p: CGPoint, size: CGFloat,
                             time: Double?, molten: Bool, dark: Bool) {
        let text = ink.isText
        let rect = box(ink, at: p, size: size)
        // Art's lines are finer than a kanji's strokes at the same size, so its hole is shallower.
        let depth = max(1.2, size * (text ? (molten ? 0.045 : 0.035) : 0.012))
        let floorAt = CGPoint(x: p.x, y: p.y + depth)

        // A dark lip along the top edges and a lit lip along the bottom edges of the opening.
        context.drawLayer { lip in
            lip.opacity = dark ? 0.9 : 0.5
            lip.clipToLayer { mask(ink, in: &$0, at: CGPoint(x: p.x, y: p.y - 1), size: size) }
            lip.fill(Path(rect), with: .color(.black))
        }
        context.drawLayer { lip in
            lip.clipToLayer { mask(ink, in: &$0, at: CGPoint(x: p.x, y: p.y + 1), size: size) }
            let lit = molten ? rgb(255, 196, 120, 0.75) : dark ? rgb(255, 240, 225, 0.45) : rgb(255, 255, 255, 0.9)
            lip.fill(Path(rect), with: .color(lit))
        }

        context.drawLayer { glow in
            if molten {
                // Heat glowing out of the opening, flickering.
                let s = time ?? 0
                let flicker = 1 + 0.05 * sin(s * 2.3) * sin(s * 1.3 + 1)
                glow.addFilter(.shadow(color: rgb(255, 130, 40, min(1, 0.95 * flicker)),
                                       radius: size * (text ? 0.28 : 0.06) * flicker))
            }
            glow.drawLayer { hollow in
                hollow.clipToLayer { mask(ink, in: &$0, at: p, size: size) }
                // Walls: dark at the surface; in a molten hole, lit orange near the floor.
                let wall = molten
                    ? [rgb(70, 18, 6), rgb(230, 96, 30)]
                    : dark ? [rgb(22, 20, 19), rgb(58, 52, 48)] : [rgb(40, 32, 28), rgb(90, 76, 66)]
                hollow.fill(Path(rect), with: .linearGradient(Gradient(colors: wall),
                                                              startPoint: CGPoint(x: p.x, y: rect.minY),
                                                              endPoint: CGPoint(x: p.x, y: rect.maxY)))
                // The floor: the opening moved back by the depth, seen through the opening.
                hollow.drawLayer { floor in
                    floor.clipToLayer { mask(ink, in: &$0, at: floorAt, size: size) }
                    if molten {
                        paintMolten(in: &floor, rect: rect, time: time ?? 0)
                    } else {
                        floor.fill(Path(rect), with: .color(dark ? rgb(40, 36, 33) : rgb(62, 52, 46)))
                    }
                    // Inner shadow where walls meet the floor: the shadows of everything
                    // outside the floor (outside the opening, and outside the floor's own shape).
                    let shade = molten ? rgb(60, 10, 0, 0.6) : rgb(0, 0, 0, 0.7)
                    for at in [p, floorAt] {
                        floor.drawLayer { outside in
                            outside.addFilter(.shadow(color: shade, radius: size * (molten ? 0.025 : 0.02)))
                            outside.drawLayer { shape in
                                shape.fill(Path(rect.insetBy(dx: -rect.width, dy: -rect.height)), with: .color(.black))
                                shape.blendMode = .destinationOut
                                mask(ink, in: &shape, at: at, size: size)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Molten rock: a hot core, drifting dark crust, and bright cracks between.
    private static func paintMolten(in c: inout GraphicsContext, rect: CGRect, time s: Double) {
        let px = rect.width
        func at(_ fx: Double, _ fy: Double) -> CGPoint { CGPoint(x: rect.minX + px * fx, y: rect.minY + px * fy) }
        let core = Gradient(stops: [
            .init(color: rgb(255, 238, 170), location: 0),
            .init(color: rgb(255, 150, 40), location: 0.4),
            .init(color: rgb(196, 54, 12), location: 1),
        ])
        c.fill(Path(rect), with: .radialGradient(core, center: at(0.5, 0.53), startRadius: 0, endRadius: px * 0.6))
        for k in 0..<7 {
            let kd = Double(k)
            let center = at(0.5 + 0.38 * sin(s * (0.11 + kd * 0.023) + kd * 2.1), 0.5 + 0.38 * cos(s * (0.09 + kd * 0.019) + kd * 1.3))
            let r = px * (0.12 + 0.015 * sin(s * 0.4 + kd))
            let crust = Gradient(stops: [
                .init(color: rgb(70, 14, 4, 0.75), location: 0),
                .init(color: rgb(110, 24, 6, 0.4), location: 0.7),
                .init(color: rgb(110, 24, 6, 0), location: 1),
            ])
            c.fill(Path(rect), with: .radialGradient(crust, center: center, startRadius: 0, endRadius: r))
        }
        for k in 0..<5 {
            let kd = Double(k)
            let center = at(0.5 + 0.34 * sin(s * (0.37 + kd * 0.05) + kd * 0.9), 0.5 + 0.34 * cos(s * (0.31 + kd * 0.04) + kd * 2.6))
            let r = px * (0.09 + 0.01 * sin(s * 0.8 + kd))
            let vent = Gradient(colors: [rgb(255, 252, 220, 0.65 + 0.1 * sin(s * 1.2 + kd)), rgb(255, 220, 140, 0)])
            c.fill(Path(rect), with: .radialGradient(vent, center: center, startRadius: 0, endRadius: r))
        }
    }

    /// Plain, silver and gold: printed on the dial rather than cut through it. Idle ones
    /// are quiet; the active one is emboldened and glows, and the metals catch a slow
    /// highlight that sweeps across them.
    private static func flat(_ ink: Ink, in context: inout GraphicsContext, at p: CGPoint, size: CGFloat,
                             style: KanjiStyle, active: Bool, time: Double?, dark: Bool) {
        let rect = box(ink, at: p, size: size)
        let fill: GraphicsContext.Shading
        let glow: Color
        if style == .plain {
            fill = .color(dark ? rgb(245, 245, 248) : rgb(18, 18, 22))
            glow = dark ? rgb(255, 255, 255, 0.75) : rgb(0, 0, 0, 0.35)
        } else {
            // A metal: dark, bright and dark again from corner to corner, with a highlight
            // band that sweeps across (every four seconds) when active. Deeper tones on
            // light backgrounds, so the metal still reads.
            let tones = style == .gold
                ? dark
                    ? [rgb(140, 92, 20), rgb(255, 226, 140), rgb(196, 140, 40), rgb(255, 246, 200)]
                    : [rgb(110, 70, 8), rgb(206, 150, 40), rgb(140, 92, 16), rgb(255, 232, 150)]
                : dark
                    ? [rgb(110, 114, 124), rgb(238, 240, 246), rgb(150, 154, 164), rgb(255, 255, 255)]
                    : [rgb(62, 66, 76), rgb(150, 156, 170), rgb(88, 92, 104), rgb(230, 236, 248)]
            var stops: [Gradient.Stop] = [.init(color: tones[0], location: 0), .init(color: tones[1], location: 0.45), .init(color: tones[2], location: 1)]
            if active, let time {
                let t = (time / 4).truncatingRemainder(dividingBy: 1)
                let clamp = { (k: Double) in min(1, max(0, k)) }
                stops += [.init(color: tones[1], location: clamp(t - 0.08)), .init(color: tones[3], location: clamp(t)),
                          .init(color: tones[1], location: clamp(t + 0.08))]
            }
            stops.sort { $0.location < $1.location }
            let half = size / 2
            fill = .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: p.x - half, y: p.y - half),
                                   endPoint: CGPoint(x: p.x + half, y: p.y + half))
            glow = style == .gold
                ? dark ? rgb(255, 200, 80, 0.8) : rgb(200, 140, 20, 0.55)
                : dark ? rgb(220, 232, 255, 0.8) : rgb(70, 90, 130, 0.45)
        }
        context.drawLayer { outer in
            outer.opacity = active ? 1 : style == .plain ? 0.45 : 0.6
            if active { outer.addFilter(.shadow(color: glow, radius: size * (ink.isText ? 0.17 : 0.04))) }
            outer.drawLayer { printed in
                printed.clipToLayer { m in
                    mask(ink, in: &m, at: p, size: size)
                    // Embolden the active kanji: the glyph again, nudged each way.
                    if active, ink.isText {
                        let w = max(0.5, size * 0.022)
                        let nudges: [(CGFloat, CGFloat)] = [(w, 0), (-w, 0), (0, w), (0, -w)]
                        for (dx, dy) in nudges {
                            mask(ink, in: &m, at: CGPoint(x: p.x + dx, y: p.y + dy), size: size)
                        }
                    }
                }
                printed.fill(Path(rect), with: fill)
            }
        }
    }
}

/// The wadokei over a dial: the twelve kanji around the ring (when there's room), and
/// the current hour's animal in the middle with its kanji beneath. The idle kanji are
/// drawn once; only the active ones animate (about 30 fps), and not with Reduce Motion.
struct WadokeiLayer: View {
    struct Layout {
        /// The center of the dial.
        var center: CGPoint
        /// Where the kanji ring sits, or nil to show only the middle.
        var ringRadius: CGFloat?
        var kanjiSize: CGFloat
        /// The radius of the open middle of the dial.
        var centerRadius: CGFloat
    }

    let hours: [Wadokei.RingHour]
    /// The current hour's kanji.
    let active: String?
    /// Degrees the dial is turned clockwise.
    let rotation: Double
    let style: KanjiStyle
    var animate = true
    let layout: (CGSize) -> Layout
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Canvas { context, size in
                let l = layout(size)
                guard let radius = l.ringRadius else { return }
                for hour in hours where !hour.isActive {
                    WadokeiRenderer.draw(.kanji(hour.kanji), in: &context, at: point(l, radius, hour.angle), size: l.kanjiSize,
                                         style: style, active: false, time: nil, dark: colorScheme == .dark)
                }
            }
            if style.animates, animate, !reduceMotion {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    activeLayer(time: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                activeLayer(time: nil)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func point(_ l: Layout, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
        let t = (degrees + rotation) * .pi / 180
        return CGPoint(x: l.center.x + radius * sin(t), y: l.center.y - radius * cos(t))
    }

    private func activeLayer(time: Double?) -> some View {
        Canvas { context, size in
            let l = layout(size)
            let dark = colorScheme == .dark
            if let radius = l.ringRadius, let hour = hours.first(where: \.isActive) {
                WadokeiRenderer.draw(.kanji(hour.kanji), in: &context, at: point(l, radius, hour.angle), size: l.kanjiSize * 1.25,
                                     style: style, active: true, time: time, dark: dark)
            }
            guard let active else { return }
            let r = l.centerRadius, c = l.center
            // The animal, with the kanji small beneath it; without the art, the kanji alone.
            if let art = WadokeiRenderer.art(for: active) {
                WadokeiRenderer.draw(.art(art), in: &context, at: CGPoint(x: c.x, y: c.y - r * 0.12), size: r * 1.2,
                                     style: style, active: true, time: time, dark: dark)
                WadokeiRenderer.draw(.kanji(active), in: &context, at: CGPoint(x: c.x, y: c.y + r * 0.66), size: r * 0.3,
                                     style: style, active: true, time: time, dark: dark)
            } else {
                WadokeiRenderer.draw(.kanji(active), in: &context, at: CGPoint(x: c.x, y: c.y - r * 0.12), size: r * 0.95,
                                     style: style, active: true, time: time, dark: dark)
            }
        }
    }
}
