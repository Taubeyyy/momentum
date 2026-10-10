import SwiftUI

/// „Was ist neu“ (Feedback #47): jeder Build mit seinem Update-Text, neuester oben, dein Build markiert.
/// Ruhig: eine Liste, kein Zähler, nichts Rotes.
struct ChangelogPage: View {
    @ObservedObject private var updates = Updates.shared
    @State private var builds: [Server.BuildNote] = []
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        List {
            if loading && builds.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if builds.isEmpty {
                Text(failed ? "Gerade keine Verbindung – später nochmal reinschauen." : "Noch nichts eingetragen.")
                    .font(.system(size: 14)).foregroundStyle(DS.muted)
                    .listRowBackground(Color.clear)
            }
            ForEach(builds) { note in
                ChangelogRow(note: note, current: note.build == updates.currentBuild,
                             fresh: note.build > updates.currentBuild)
                    .dopaRow()
            }
        }
        .animation(Motion.list, value: builds.count)
        .dopaBackground()
        .navigationTitle("Was ist neu")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            builds = try await Server.shared.changelog()
            failed = false
        } catch {
            failed = true
        }
        loading = false
    }
}

struct ChangelogRow: View {
    let note: Server.BuildNote
    let current: Bool
    let fresh: Bool

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EE d. MMM"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("Build \(note.build)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.ink)
                if current {
                    Tag(text: "deiner", color: DS.purpleMuted)
                } else if fresh {
                    Tag(text: "neu", color: .blue)
                }
                Spacer(minLength: 0)
                if let date = note.date {
                    Text(Self.dateFormat.string(from: date))
                        .font(.system(size: 12)).foregroundStyle(DS.muted)
                }
            }
            Text(note.notes)
                .font(.system(size: 13))
                .foregroundStyle(current || fresh ? DS.ink : DS.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private struct Tag: View {
        let text: String
        let color: Color
        var body: some View {
            Text(text)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(color.opacity(0.15), in: Capsule())
        }
    }
}
