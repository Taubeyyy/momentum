import SwiftUI

/// Schlaf von der Apple Watch: die letzte Nacht mit Phasen (Grafik + kurze Erklärung) und 7 Nächte.
/// Ruhig und ohne Wertung – „üblich“ statt „schlecht“. Daten bleiben auf dem Handy.
struct SleepPage: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var health = Health.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !store.data.reminders.sleepOn {
                    enableCard
                } else if let night = health.lastNight {
                    header(night)
                    Card(title: "Phasen", symbol: "waveform.path.ecg") { SleepChart(night: night) }
                    Card(title: "Was die Phasen bedeuten", symbol: "lightbulb") { phases(night) }
                } else {
                    Card(title: "Letzte Nacht", symbol: "bed.double") {
                        Text("Noch keine Daten. Mit der Uhr schlafen – morgen früh steht hier deine Nacht.")
                            .font(.system(size: 14)).foregroundStyle(DS.muted)
                    }
                }
                if store.data.reminders.sleepOn && health.week.contains(where: { $0.seconds > 0 }) {
                    Card(title: "Letzte 7 Nächte", symbol: "chart.bar") { SleepWeekBars(week: health.week) }
                }
                Text("Aus Health (Apple Watch). Bleibt auf dem Handy – Dot sieht nur die Stunden.")
                    .font(.system(size: 12)).foregroundStyle(DS.faint)
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: TabBarSpace.height) }
        .background(DS.surface.ignoresSafeArea())
        .navigationTitle("Schlaf")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.refreshHealth() }
    }

    private func header(_ night: SleepNight) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LETZTE NACHT")
                .font(.system(size: 11, weight: .heavy)).tracking(0.8).foregroundStyle(DS.purpleMuted)
            Text(Timing.hoursText(night.asleep))
                .font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(DS.ink)
            Text("\(Timing.clock(night.start)) – \(Timing.clock(night.end)) · \(night.summary)")
                .font(.system(size: 14)).foregroundStyle(DS.muted).lineSpacing(2)
        }
        .padding(.bottom, 4)
    }

    private func phases(_ night: SleepNight) -> some View {
        let order: [SleepStage] = night.hasStages ? [.deep, .rem, .core, .awake] : [.unspecified, .awake]
        let shown: [SleepStage] = order.filter { (night.totals[$0] ?? 0) > 0 }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element) { i, stage in
                if i > 0 { Divider().overlay(DS.line) }
                PhaseRow(stage: stage, night: night)
            }
        }
    }

    /// Ausgeschaltet: einmal erklären, mit einem Tipp einschalten.
    private var enableCard: some View {
        Card(title: "Schlaf von der Uhr", symbol: "applewatch") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Dopa liest deinen Schlaf aus Health – mit Phasen, wenn du mit der Uhr schläfst. Nach kurzen Nächten plant Dot sanfter.")
                    .font(.system(size: 14)).foregroundStyle(DS.muted).lineSpacing(2)
                Button("Einschalten") {
                    var s = store.data.reminders
                    s.sleepOn = true
                    store.updateReminders(s)
                    Task { @MainActor in
                        _ = await Health.shared.requestAccess()
                        await store.refreshHealth()
                    }
                }
                .buttonStyle(SolidButtonStyle())
            }
        }
    }
}

/// Morgens in „Heute“: die letzte Nacht in einer Zeile, antippen = Schlaf-Seite.
struct SleepMiniCard: View {
    let night: SleepNight

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SleepStage.deep.color)
                .frame(width: 36, height: 36)
                .background(SleepStage.deep.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Timing.hoursText(night.asleep)) geschlafen")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink)
                Text(night.summary)
                    .font(.system(size: 12)).foregroundStyle(DS.muted).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.faint)
        }
        .padding(14)
        .background(DS.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(DS.line.opacity(0.8)))
    }
}

/// Farben der Phasen – ruhig, im Lila-Look; Wach als einziger warmer Ton.
extension SleepStage {
    var color: Color {
        switch self {
        case .deep: Color(hex: 0x4F46E5)
        case .core: Color(hex: 0x8B5CF6)
        case .rem: Color(hex: 0x5EC8E5)
        case .awake: Color(hex: 0xF5B94A)
        case .unspecified: DS.purpleMuted
        }
    }

    /// Zeile in der Grafik: oben wach, unten tief.
    var chartRow: Int {
        switch self {
        case .awake: 0
        case .rem: 1
        case .core, .unspecified: 2
        case .deep: 3
        }
    }
}

/// Eine Phase: Farbe, Name, Dauer und Anteil, darunter die Erklärung und die Einordnung.
private struct PhaseRow: View {
    let stage: SleepStage
    let night: SleepNight

    var body: some View {
        let seconds = night.totals[stage] ?? 0
        let percent = Int((night.share(stage) * 100).rounded())
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Circle().fill(stage.color).frame(width: 9, height: 9)
                Text(stage.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink)
                Spacer(minLength: 0)
                Text(stage.isAsleep ? "\(Timing.hoursText(seconds)) · \(percent) %" : Timing.hoursText(seconds))
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(DS.muted)
            }
            Text(stage.explanation)
                .font(.system(size: 13)).foregroundStyle(DS.muted).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if let note = night.note(stage) {
                let label: String = note.prefix(1).uppercased() + String(note.dropFirst())
                Text(label)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.purpleMuted)
            }
        }
        .padding(.vertical, 10)
    }
}

/// Phasen-Grafik wie in Health: vier Zeilen (Wach, REM, Kern, Tief), Abschnitte nach Uhrzeit.
struct SleepChart: View {
    let night: SleepNight
    @State private var shown = false

    private let rows: [SleepStage] = [.awake, .rem, .core, .deep]
    private let rowHeight: CGFloat = 26
    private let labelWidth: CGFloat = 70

    var body: some View {
        let total = max(60, night.end.timeIntervalSince(night.start))
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let width = max(1, geo.size.width - labelWidth)
                ZStack(alignment: .topLeading) {
                    ForEach(rows, id: \.self) { stage in
                        Text(stage == .core ? "Kern" : stage == .deep ? "Tief" : stage.name)
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.faint)
                            .frame(width: labelWidth, height: rowHeight, alignment: .leading)
                            .offset(y: CGFloat(stage.chartRow) * rowHeight)
                        Rectangle().fill(DS.line.opacity(0.5))
                            .frame(width: width, height: 1)
                            .offset(x: labelWidth, y: CGFloat(stage.chartRow) * rowHeight + rowHeight / 2)
                    }
                    ForEach(night.segments, id: \.self) { segment in
                        let x = CGFloat(segment.start.timeIntervalSince(night.start) / total) * width
                        let w = max(2, CGFloat(segment.duration / total) * width)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(segment.stage.color)
                            .frame(width: w, height: rowHeight - 8)
                            .offset(x: labelWidth + x, y: CGFloat(segment.stage.chartRow) * rowHeight + 4)
                    }
                    .opacity(shown ? 1 : 0)
                    .scaleEffect(x: shown ? 1 : 0.4, y: 1, anchor: .leading)
                    .animation(.spring(response: 0.7, dampingFraction: 0.85), value: shown)
                }
            }
            .frame(height: rowHeight * 4)
            HStack {
                Text(Timing.clock(night.start))
                Spacer()
                Text(Timing.clock(night.end))
            }
            .font(.system(size: 11)).monospacedDigit().foregroundStyle(DS.faint)
            .padding(.leading, labelWidth)
        }
        .onAppear { shown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schlafphasen von \(Timing.clock(night.start)) bis \(Timing.clock(night.end))")
    }
}

/// 7 Nächte als Balken; die Linie zeigt 8 Stunden.
struct SleepWeekBars: View {
    let week: [(day: Date, seconds: TimeInterval)]
    @ObservedObject private var store = Store.shared
    @State private var grown = false

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEEEE"
        return f
    }()

    var body: some View {
        let top = max(9 * 3600, week.map(\.seconds).max() ?? 0)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(week.enumerated()), id: \.offset) { i, night in
                VStack(spacing: 5) {
                    Text(night.seconds > 0 ? String(format: "%.1f", night.seconds / 3600).replacingOccurrences(of: ".", with: ",") : "–")
                        .font(.system(size: 9, weight: .semibold)).monospacedDigit().foregroundStyle(DS.muted)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Timing.shortNight(night.seconds) ? Color(hex: 0x3A3042) : store.theme.accent.opacity(0.85))
                        .frame(height: grown ? max(4, CGFloat(night.seconds / top) * 80) : 4)
                        .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(Double(i) * 0.04), value: grown)
                    Text(Self.weekday.string(from: night.day))
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(DS.faint)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 120, alignment: .bottom)
        .onAppear { grown = true }
    }
}
