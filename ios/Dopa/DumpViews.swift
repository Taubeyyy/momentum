import SwiftUI

/// Kennungen der Einträge eines Smart-Dump-Ergebnisses (für die Häkchen).
enum DumpKey {
    static func block(_ i: Int) -> String { "b\(i)" }
    static func task(_ i: Int) -> String { "t\(i)" }
    static func reminder(_ i: Int) -> String { "r\(i)" }
    static func shop(_ i: Int) -> String { "s\(i)" }
    static func note(_ i: Int) -> String { "n\(i)" }

    static func all(_ d: Server.Dump) -> Set<String> {
        Set(d.schedule.indices.map(block) + d.tasks.indices.map(task) + d.reminders.indices.map(reminder)
            + d.shopping.indices.map(shop) + d.notes.indices.map(note))
    }
}

/// Tag-Abstand → „Heute“, „Morgen“, „Montag“.
enum DayLabel {
    static func text(_ offset: Int) -> String {
        switch offset {
        case ..<0: return "Ohne Tag"
        case 0: return "Heute"
        case 1: return "Morgen"
        default:
            let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
            let f = DateFormatter()
            f.locale = Locale(identifier: "de_DE")
            f.dateFormat = "EEEE"
            return f.string(from: date)
        }
    }

    static func text(for date: Date) -> String {
        let today = Calendar.current.startOfDay(for: Date())
        let days = Calendar.current.dateComponents([.day], from: today, to: Calendar.current.startOfDay(for: date)).day ?? 0
        return text(days)
    }
}

/// Ergebnis eines Smart Dumps: alles nach Art sortiert, jeder Eintrag abhakbar.
struct DumpResultView: View {
    let dump: Server.Dump
    @Binding var picked: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !dump.summary.isEmpty {
                Text(dump.summary).font(.system(size: 13)).foregroundStyle(DS.muted).padding(.top, 18)
            }

            if !dump.schedule.isEmpty {
                SectionHeading(title: "Zeitplan · \(DayLabel.text(dump.schedule.first?.day ?? 0))",
                               subtitle: "Zu jedem Schritt kommt eine Erinnerung")
                HairlineList {
                    ForEach(Array(dump.schedule.enumerated()), id: \.offset) { i, block in
                        row(key: DumpKey.block(i), leading: block.start,
                            title: block.title, detail: "\(block.minutes) Min · \(block.step)")
                    }
                }
            }
            if !dump.tasks.isEmpty {
                SectionHeading(title: "Aufgaben")
                HairlineList {
                    ForEach(Array(dump.tasks.enumerated()), id: \.offset) { i, task in
                        row(key: DumpKey.task(i), leading: nil, title: task.title,
                            detail: "\(DayLabel.text(task.day)) · \(task.step)")
                    }
                }
            }
            if !dump.reminders.isEmpty {
                SectionHeading(title: "Erinnerungen")
                HairlineList {
                    ForEach(Array(dump.reminders.enumerated()), id: \.offset) { i, r in
                        row(key: DumpKey.reminder(i), leading: r.time, title: r.title, detail: DayLabel.text(r.day))
                    }
                }
            }
            if !dump.shopping.isEmpty {
                SectionHeading(title: "Einkauf")
                HairlineList {
                    ForEach(Array(dump.shopping.enumerated()), id: \.offset) { i, item in
                        row(key: DumpKey.shop(i), leading: nil, title: item, detail: nil)
                    }
                }
            }
            if !dump.notes.isEmpty {
                SectionHeading(title: "Notizen")
                HairlineList {
                    ForEach(Array(dump.notes.enumerated()), id: \.offset) { i, note in
                        row(key: DumpKey.note(i), leading: nil, title: note, detail: nil)
                    }
                }
            }
            if DumpKey.all(dump).isEmpty {
                EmptyState(symbol: "", title: "Nichts gefunden",
                           text: "Daraus ließ sich nichts Konkretes machen. Erzähl ruhig genauer, was ansteht.")
            }
        }
    }

    private func row(key: String, leading: String?, title: String, detail: String?) -> some View {
        Button {
            if picked.contains(key) { picked.remove(key) } else { picked.insert(key) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                CheckBox(done: picked.contains(key))
                if let leading {
                    Text(leading).font(.system(size: 12, weight: .bold)).monospacedDigit()
                        .foregroundStyle(DS.purpleMuted).frame(width: 42, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.system(size: 12)).foregroundStyle(DS.muted).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .hairlineRow(minHeight: 58)
        }
        .buttonStyle(.plain)
    }
}

/// „Plan aus Text“: dasselbe wie der Audio-Dump, nur getippt.
struct PlanSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var dump: Server.Dump?
    @State private var picked: Set<String> = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Plan aus Text").font(.system(size: 13, weight: .medium)).foregroundStyle(DS.muted).padding(.bottom, 7)
                    Text("Alles einfach reinschreiben.").font(.system(size: 24, weight: .bold)).tracking(-0.7).foregroundStyle(DS.ink)
                    Text("Dopa sortiert selbst: Aufgaben, Termine, Einkauf, Merken. „Plane meinen Morgen …“ macht einen Zeitplan mit Erinnerungen.")
                        .font(.system(size: 13)).foregroundStyle(DS.muted).padding(.top, 8).padding(.bottom, 16)

                    TextField("", text: $text,
                              prompt: Text("Plane meinen Morgen, damit ich die Bewerbung schaffe. Milch fehlt …").foregroundColor(Color(hex: 0x68606D)),
                              axis: .vertical)
                        .lineLimit(5...12)
                        .font(.system(size: 14))
                        .foregroundStyle(DS.ink)
                        .padding(14)
                        .background(Color(hex: 0x0F0D11), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color(hex: 0x39323E)))

                    if let error {
                        Text(error).font(.system(size: 12)).foregroundStyle(DS.muted).padding(.top, 10)
                    }

                    Button(action: run) {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(.white) }
                            Text(dump == nil ? "Einsortieren" : "Nochmal")
                        }
                    }
                    .buttonStyle(SolidButtonStyle())
                    .disabled(busy || text.trimmingCharacters(in: .whitespaces).count < 5)
                    .padding(.top, 14)

                    if let dump {
                        DumpResultView(dump: dump, picked: $picked)
                        Button("\(picked.count) übernehmen") {
                            store.applyDump(dump, picked: picked)
                            dismiss()
                        }
                        .buttonStyle(SolidButtonStyle())
                        .disabled(picked.isEmpty)
                        .padding(.top, 18)
                    }
                }
                .padding(.horizontal, 19)
                .padding(.top, 20)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DS.raised.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
    }

    private func run() {
        busy = true
        error = nil
        Task {
            do {
                let result = try await Server.shared.dump(text)
                dump = result
                picked = DumpKey.all(result)
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
