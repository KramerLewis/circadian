import SunCore
import SwiftUI

/// Under the dial in the sun periods and wadokei displays: where you are in the section,
/// how long it lasts today, and what comes next (mirrors the web app's details panel).
struct PeriodDetailsView: View {
    let display: TimeDisplay
    let coordinate: Coordinate
    let now: Date

    var body: some View {
        let lines = self.lines
        if !lines.isEmpty {
            VStack(spacing: 4) {
                ForEach(lines, id: \.self) { Text($0) }
            }
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)
        }
    }

    private var lines: [String] {
        switch display {
        case .periods: periodLines
        case .wadokei: wadokeiLines
        default: []
        }
    }

    private func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
    private func duration(_ from: Date, _ to: Date) -> String { SolarFormat.duration(to.timeIntervalSince(from)) }
    private func name(_ letter: String) -> String { SunPeriods.milestoneNames[letter] ?? letter }

    private var periodLines: [String] {
        var lines: [String] = []
        if let p = SunPeriods.sun(at: now, coordinate: coordinate) {
            let next = SunPeriods.sun(at: p.end.addingTimeInterval(1), coordinate: coordinate)
            lines.append("\(duration(p.from.date, now)) after \(name(p.from.letter)) · \(duration(now, p.to.date)) before \(name(p.to.letter))")
            lines.append("\(p.code) until \(time(p.end))\(next.map { ", then \($0.code)" } ?? "") · \(duration(p.start, p.end)) today")
        }
        if let m = SunPeriods.moon(at: now, coordinate: coordinate) {
            lines.append("Moon \(m.code) · \(SunPeriods.phrase(m))")
        }
        return lines
    }

    private var wadokeiLines: [String] {
        let hours = Wadokei.hours(around: now, at: coordinate)
        guard let i = hours.firstIndex(where: { $0.start <= now && now < $0.end }) else { return [] }
        let h = hours[i]
        var lines = [
            "\(h.kanji) \(h.animal) hour (\(h.countName)) · \(h.isDaylight ? "daylight" : "night")",
            "\(time(h.start)) – \(time(h.end)) · \(duration(h.start, h.end)) long today",
        ]
        if hours.indices.contains(i + 1) {
            let next = hours[i + 1]
            lines.append("Next: \(next.kanji) \(next.animal) at \(time(next.start))")
        }
        return lines
    }
}
