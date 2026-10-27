import SunCore
import SwiftUI

/// The full-screen dial: sun ring, moon ring inside it, and the center readout.
/// Turn the Digital Crown to move through time (sun and moon slide round their rings);
/// a few seconds after letting go it snaps back to now.
struct WatchDialView: View {
    let place: SharedStore.StoredPlace
    @Environment(WatchModel.self) private var model
    @Environment(\.isLuminanceReduced) private var dimmed

    /// Minutes from now, set by the Digital Crown.
    @State private var offset: Double = DemoConfig.current?.scrub ?? 0
    @State private var snapBack: Task<Void, Never>?

    static let snapBackDelay: Duration = .seconds(3)

    var body: some View {
        TimelineView(.periodic(from: .now, by: dimmed ? 60 : 15)) { context in
            let now = DemoConfig.current?.date ?? context.date
            let moment = now.addingTimeInterval(offset * 60)
            dial(at: moment, scrubbing: abs(offset) >= 1)
        }
        .focusable()
        .digitalCrownRotation(
            $offset, from: -24 * 60, through: 24 * 60, by: 5,
            sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true
        )
        .onChange(of: offset) { scheduleSnapBack() }
        .navigationTitle(place.name)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    WatchEventsView(place: place, date: .now)
                } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("Today's events")
            }
        }
    }

    private func dial(at moment: Date, scrubbing: Bool) -> some View {
        let coordinate = place.coordinate
        let day = SolarCalculator.solarDay(containing: moment, at: coordinate)
        let model = DialModel(day: day, now: moment)
        let moon = MoonDialModel(now: moment, coordinate: coordinate)
        let readout = SolarReadout(at: moment, coordinate: coordinate)
        let solarMinutes = SolarCalculator.apparentSolarMinutes(at: moment, longitude: coordinate.longitude)
        let center = scrubbing
            ? scrubText(moment, readout: readout)
            : DialCenterText.make(now: moment, solarMinutes: solarMinutes, readout: readout, display: self.model.timeDisplay,
                                  coordinate: coordinate)
        // The wadokei's animal and kanji fill the middle (there's no room for the ring of
        // kanji outside the dial); while scrubbing, the time readout takes over.
        let wadokei = self.model.timeDisplay == .wadokei && !scrubbing

        return ZStack {
            Canvas { context, size in
                let outer = min(size.width, size.height) / 2 - 2
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                // With "now at top" the whole dial turns, so scrubbing spins the day under the sun.
                let rotation = self.model.dialOrientation.rotation(nowAngle: model.nowAngle)
                let sun = SkyRingRenderer.Ring(center: c, inner: outer * 0.8, outer: outer, rotation: rotation)
                let moonRing = SkyRingRenderer.Ring(center: c, inner: outer * 0.8 - 4 - outer * 0.1, outer: outer * 0.8 - 4, rotation: rotation)
                SkyRingRenderer.drawSky(in: &context, ring: sun, model: model, dark: true, monochrome: false)
                let special = SpecialDayText.today(at: coordinate, on: moment)?.style
                if special == .solstice {
                    SkyRingRenderer.drawSpecialDay(.solstice, in: &context, ring: sun, innerRadius: moonRing.inner, dark: true)
                }
                SkyRingRenderer.drawMoonRing(in: &context, ring: moonRing, moon: moon, dark: true, special: special,
                                             eclipseShadow: special == .lunarEclipse ? EclipseCalculator.umbralCoverage(at: moment) : 0,
                                             placement: self.model.moonPlacement)
                if let special, special == .equinox || special == .newMoon {
                    SkyRingRenderer.drawSpecialDay(special, in: &context, ring: sun, innerRadius: moonRing.inner, dark: true)
                }
                let overlay = special == .solarEclipse ? EclipseCalculator.solarCoverage(at: moment, coordinate: coordinate) : nil
                SkyRingRenderer.drawSun(in: &context, ring: sun, angle: model.nowAngle,
                                        altitude: model.altitude(atAngle: model.nowAngle), monochrome: false,
                                        eclipse: overlay.map { ($0.offset, $0.moonScale) })
            }
            .opacity(dimmed ? 0.55 : 1)

            if wadokei {
                WadokeiLayer(hours: [], active: Wadokei.hour(at: moment, coordinate: coordinate)?.kanji, rotation: 0,
                             style: self.model.kanjiStyle, animate: !dimmed) { size in
                    let outer = min(size.width, size.height) / 2 - 2
                    return WadokeiLayer.Layout(center: CGPoint(x: size.width / 2, y: size.height / 2), ringRadius: nil,
                                               kanjiSize: 0, centerRadius: outer * 0.8 - 4 - outer * 0.1)
                }
                .environment(\.colorScheme, .dark)
                .opacity(dimmed ? 0.55 : 1)
            }

            if let special = SpecialDayText.today(at: coordinate, on: moment) {
                VStack {
                    Spacer()
                    Label(special.short, systemImage: special.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        // A backing keeps it readable when the moon or the ring passes under it.
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.65), in: .capsule)
                        .padding(.bottom, 2)
                }
            }

            VStack(spacing: 0) {
                Text(center.primary)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                Text(center.secondary)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(scrubbing ? .orange : .secondary)
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: 104)
            .contentTransition(.numericText())
            .opacity(wadokei ? 0 : 1)
        }
        .contentShape(.rect)
        .onTapGesture { if !scrubbing { self.model.cycleTimeDisplay() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Solar dial")
        .accessibilityValue("\(center.primary) \(center.secondary)")
        .accessibilityHint("Turn the Digital Crown to look ahead or back in time.")
    }

    /// While scrubbing: the clock time at that moment, and how far from now.
    private func scrubText(_ moment: Date, readout: SolarReadout) -> (primary: String, secondary: String) {
        let minutes = Int(offset.rounded())
        let sign = minutes < 0 ? "−" : "+"
        let amount = SolarFormat.duration(Double(abs(minutes)) * 60)
        return (moment.formatted(date: .omitted, time: .shortened), "\(sign)\(amount) from now")
    }

    private func scheduleSnapBack() {
        snapBack?.cancel()
        guard offset != 0, DemoConfig.current?.scrub == nil else { return }
        snapBack = Task {
            try? await Task.sleep(for: Self.snapBackDelay)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.6)) { offset = 0 }
        }
    }
}
