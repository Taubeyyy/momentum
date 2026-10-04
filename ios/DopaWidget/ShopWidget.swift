import SwiftUI
import WidgetKit

/// Einkaufszettel auf dem Sperrbildschirm – im Laden nicht erst die App suchen.
struct ShopEntry: TimelineEntry {
    let date: Date
    let items: [String]
}

struct ShopProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShopEntry {
        ShopEntry(date: .now, items: ["Bananen", "Brot", "Milch", "Eier", "Nudeln", "Klopapier"])
    }

    func getSnapshot(in context: Context, completion: @escaping (ShopEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShopEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .never))   // App lädt bei Änderungen neu
    }

    /// Offene Einträge in der Gang-Reihenfolge des zuletzt gewählten Ladens.
    private func current() -> ShopEntry {
        let data = Shared.loadData()
        let place = data.flatMap { d in d.shopPlaces.first { $0.id == d.lastPlace } ?? d.shopPlaces.first }
        let order = place?.fullOrder ?? ShopCategory.allCases
        let open = (data?.shopItems ?? [])
            .filter { $0.boughtAt == nil }
            .sorted { (order.firstIndex(of: $0.category) ?? 99, $0.addedAt) < (order.firstIndex(of: $1.category) ?? 99, $1.addedAt) }
        return ShopEntry(date: .now, items: open.map(\.name))
    }
}

struct ShopWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ShopEntry

    private func more(after n: Int) -> String? {
        entry.items.count > n ? "+ \(entry.items.count - n) weitere" : nil
    }

    var body: some View {
        Group {
            if entry.items.isEmpty {
                empty
            } else {
                list
            }
        }
        .widgetURL(URL(string: "dopa://einkauf"))
    }

    @ViewBuilder
    private var list: some View {
        switch family {
        case .accessoryInline:
            Text("🛒 " + entry.items.prefix(3).joined(separator: ", "))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Text("🛒 Einkauf (\(entry.items.count))").font(.headline)
                Text(entry.items.prefix(4).joined(separator: ", ")).font(.caption).lineLimit(2)
            }
        case .systemMedium:
            let rows = Array(entry.items.prefix(10))
            VStack(alignment: .leading, spacing: 4) {
                Text("🛒 Einkauf").font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 16) {
                    column(Array(rows.prefix(5)))
                    column(Array(rows.dropFirst(5)))
                }
                Spacer(minLength: 0)
                if let more = more(after: 10) { Text(more).font(.caption2).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("🛒 Einkauf").font(.caption).foregroundStyle(.secondary)
                column(Array(entry.items.prefix(5)))
                Spacer(minLength: 0)
                if let more = more(after: 5) { Text(more).font(.caption2).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
        }
    }

    private func column(_ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(names, id: \.self) { name in
                Text("○ \(name)").font(.subheadline).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var empty: some View {
        switch family {
        case .accessoryInline:
            Text("🛒 Liste leer")
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("🛒 Einkauf").font(.headline)
                Text("Liste leer").font(.caption)
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("🛒 Einkauf").font(.caption).foregroundStyle(.secondary)
                Text("Liste leer").font(.headline)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
        }
    }
}

struct ShopWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShopWidget", provider: ShopProvider()) { entry in
            ShopWidgetView(entry: entry)
                .widgetCard()
        }
        .configurationDisplayName("Einkauf")
        .description("Deine Einkaufsliste, sortiert nach Gängen im Laden.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryRectangular])
    }
}
