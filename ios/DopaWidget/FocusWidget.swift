import SwiftUI
import WidgetKit

/// Fokus-Timer als normales Widget – läuft auch da, wo Live Activities nicht dürfen.
/// Der Countdown zählt per Text(timerInterval:) von selbst, ohne Timeline-Updates.
struct FocusEntry: TimelineEntry {
    let date: Date
    var step: String?
    var startedAt: Date?
    var endsAt: Date?

    var isRunning: Bool {
        guard let startedAt, let endsAt else { return false }
        return date >= startedAt && date < endsAt
    }
}

struct FocusProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusEntry {
        let now = Date()
        return FocusEntry(date: now, step: "Nur das Dokument öffnen", startedAt: now, endsAt: now.addingTimeInterval(300))
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entries().first!)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusEntry>) -> Void) {
        completion(Timeline(entries: entries(), policy: .never))
    }

    /// Jetzt-Eintrag plus einer zum Ablauf, damit das Widget danach auf „fertig" springt.
    private func entries() -> [FocusEntry] {
        let now = Date()
        let d = Shared.defaults
        guard let start = d?.object(forKey: Shared.focusStartKey) as? Date,
              let end = d?.object(forKey: Shared.focusEndKey) as? Date,
              end > now else { return [FocusEntry(date: now)] }
        let step = d?.string(forKey: Shared.focusStepKey)
        return [FocusEntry(date: now, step: step, startedAt: start, endsAt: end),
                FocusEntry(date: end)]
    }
}

struct FocusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FocusEntry

    var body: some View {
        if entry.isRunning, let start = entry.startedAt, let end = entry.endsAt {
            running(start...end)
        } else {
            idle
        }
    }

    @ViewBuilder
    private func running(_ range: ClosedRange<Date>) -> some View {
        switch family {
        case .accessoryCircular:
            ProgressView(timerInterval: range, countsDown: true) {
                Text("🎯")
            } currentValueLabel: {
                Text(timerInterval: range, countsDown: true).monospacedDigit()
            }
            .progressViewStyle(.circular)
        case .accessoryInline:
            Text("🎯 \(Text(timerInterval: range, countsDown: true))")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.step ?? "Fokus").font(.caption).lineLimit(1)
                Text(timerInterval: range, countsDown: true)
                    .font(.title2.bold()).monospacedDigit()
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text("🎯 Fokus").font(.caption).foregroundStyle(.secondary)
                Text(timerInterval: range, countsDown: true)
                    .font(.largeTitle.bold()).monospacedDigit()
                Text(entry.step ?? "").font(.caption).lineLimit(2)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
        }
    }

    @ViewBuilder
    private var idle: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Text("🎯")
            }
        case .accessoryInline:
            Text("🎯 Kein Timer")
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("🎯 Fokus").font(.caption)
                Text("Kein Timer").font(.headline)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text("🎯 Fokus").font(.caption).foregroundStyle(.secondary)
                Text("Kein Timer").font(.headline)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
        }
    }
}

struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FocusWidget", provider: FocusProvider()) { entry in
            FocusWidgetView(entry: entry)
                .widgetCard()
                .widgetURL(URL(string: "dopa://timer"))
        }
        .configurationDisplayName("Fokus-Timer")
        .description("Zeigt den laufenden Timer – auch auf dem Sperrbildschirm.")
        .supportedFamilies([.systemSmall, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}
