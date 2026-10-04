import SwiftUI
import WidgetKit

struct NoteEntry: TimelineEntry {
    let date: Date
    let text: String
    let groupOK: Bool
}

struct NoteProvider: TimelineProvider {
    func placeholder(in context: Context) -> NoteEntry {
        NoteEntry(date: .now, text: "Schlüssel liegt auf der Kommode", groupOK: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (NoteEntry) -> Void) {
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NoteEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .never))
    }

    private func current() -> NoteEntry {
        let text = Shared.defaults?.string(forKey: Shared.widgetTextKey) ?? ""
        return NoteEntry(date: .now, text: text.isEmpty ? "Noch nichts gemerkt" : text,
                         groupOK: Shared.containerURL != nil)
    }
}

struct NoteWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NoteEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("🧠 \(entry.text)")
        case .accessoryCircular:
            Image(systemName: entry.groupOK ? "brain.head.profile" : "exclamationmark.triangle")
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("Gemerkt").font(.caption2).foregroundStyle(.secondary)
                Text(entry.text).font(.caption).lineLimit(2)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text("🧠 Gemerkt").font(.caption).foregroundStyle(.secondary)
                Text(entry.text).font(.headline).lineLimit(4)
                Spacer(minLength: 0)
                if !entry.groupOK {
                    Text("App Group fehlt").font(.caption2).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
        }
    }
}

struct NoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NoteWidget", provider: NoteProvider()) { entry in
            NoteWidgetView(entry: entry)
                .widgetCard()
                .widgetURL(URL(string: "dopa://merken"))
        }
        .configurationDisplayName("Gemerkt")
        .description("Zeigt, was du dir zuletzt gemerkt hast.")
        .supportedFamilies([.systemSmall, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}
