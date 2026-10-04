import SwiftUI
import WidgetKit

/// „Als Nächstes“: die oberste offene Aufgabe mit ihrem winzigen ersten Schritt.
/// Antippen öffnet direkt „Hilf mir anfangen“ für genau diese Aufgabe.
struct NextEntry: TimelineEntry {
    let date: Date
    var task: TaskItem?
    var more = 0
}

struct NextProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextEntry {
        NextEntry(date: .now, task: TaskItem(title: "Zimmer aufräumen", firstStep: "Nur 5 Sachen an ihren Platz legen",
                                            showStep: true), more: 2)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .never))   // App lädt bei Änderungen neu
    }

    private func current() -> NextEntry {
        let open = (Shared.loadData()?.tasks ?? []).filter { $0.doneAt == nil }
        return NextEntry(date: .now, task: open.first, more: max(0, open.count - 1))
    }
}

struct NextWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextEntry

    var body: some View {
        if let task = entry.task {
            content(task)
                .widgetURL(URL(string: "dopa://anfangen/\(task.id.uuidString)"))
        } else {
            empty
                .widgetURL(URL(string: "dopa://jetzt"))
        }
    }

    @ViewBuilder
    private func content(_ task: TaskItem) -> some View {
        switch family {
        case .accessoryInline:
            Text("⚡ \(task.title)")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("⚡ \(task.title)").font(.headline).lineLimit(1)
                if task.showStep {
                    Text(task.firstStep).font(.caption).lineLimit(2)
                } else if let at = task.remindAt {
                    Text("um \(Timing.clock(at))").font(.caption)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text("Als Nächstes").font(.caption).foregroundStyle(.secondary)
                Text(task.title).font(.headline).lineLimit(2)
                if let at = task.remindAt {
                    Text("um \(Timing.clock(at))").font(.caption).foregroundStyle(.secondary)
                }
                if task.showStep && !task.firstStep.isEmpty {
                    Text("→ \(task.firstStep)").font(.caption).lineLimit(family == .systemSmall ? 3 : 2)
                }
                Spacer(minLength: 0)
                if entry.more > 0 {
                    Text("+ \(entry.more) weitere").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
        }
    }

    @ViewBuilder
    private var empty: some View {
        switch family {
        case .accessoryInline:
            Text("⚡ Nichts offen")
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("⚡ Als Nächstes").font(.headline)
                Text("Nichts offen").font(.caption)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text("Als Nächstes").font(.caption).foregroundStyle(.secondary)
                Text("Nichts offen 🎉").font(.headline)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
        }
    }
}

struct NextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextWidget", provider: NextProvider()) { entry in
            NextWidgetView(entry: entry)
                .widgetCard()
        }
        .configurationDisplayName("Als Nächstes")
        .description("Die nächste Aufgabe mit ihrem ersten Schritt. Antippen = anfangen.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryRectangular])
    }
}

/// Morgen-Checkliste auf dem Sperrbildschirm: Fortschritt und Abfahrt.
struct MorningEntry: TimelineEntry {
    let date: Date
    let morning: Morning
}

struct MorningProvider: TimelineProvider {
    func placeholder(in context: Context) -> MorningEntry {
        var m = Morning()
        m.checked = Array(m.steps.prefix(2).map(\.id))
        m.startedAt = .now
        m.day = .now
        return MorningEntry(date: .now, morning: m)
    }

    func getSnapshot(in context: Context, completion: @escaping (MorningEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : MorningEntry(date: .now, morning: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MorningEntry>) -> Void) {
        // Um Mitternacht springen die Häkchen zurück
        let midnight = Calendar.current.startOfDay(for: .now).addingTimeInterval(24 * 3600 + 60)
        completion(Timeline(entries: [MorningEntry(date: .now, morning: load())], policy: .after(midnight)))
    }

    private func load() -> Morning {
        (Shared.loadData()?.morning ?? Morning()).forToday()
    }
}

struct MorningWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MorningEntry

    private var m: Morning { entry.morning }
    private var progress: String { "\(m.checked.count)/\(m.steps.count)" }
    private var running: Bool { m.startedAt != nil && !m.isDone }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: Double(m.checked.count), in: 0...Double(max(1, m.steps.count))) {
                    Text("☀️")
                } currentValueLabel: {
                    Text(progress)
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryInline:
                Text(running ? "☀️ \(progress) · los \(ClockTime.string(m.leaveAt))" : "☀️ Los um \(ClockTime.string(m.leaveAt))")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.isDone ? "☀️ Morgen erledigt" : "☀️ Morgen \(progress)").font(.headline)
                    if running {
                        Text(timerInterval: entry.date...max(entry.date, m.leaveDate(entry.date)), countsDown: true)
                            .font(.title3.bold()).monospacedDigit()
                    } else {
                        Text("Los um \(ClockTime.string(m.leaveAt))").font(.caption)
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Text("☀️ Morgen").font(.caption).foregroundStyle(.secondary)
                    Text(m.isDone ? "Erledigt" : progress).font(.largeTitle.bold())
                    Text("Los um \(ClockTime.string(m.leaveAt))").font(.caption)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding()
            }
        }
        .widgetURL(URL(string: "dopa://morgen"))
    }
}

struct MorningWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MorningWidget", provider: MorningProvider()) { entry in
            MorningWidgetView(entry: entry)
                .widgetCard()
        }
        .configurationDisplayName("Morgen")
        .description("Fortschritt der Morgen-Checkliste und Zeit bis zur Abfahrt.")
        .supportedFamilies([.systemSmall, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}
