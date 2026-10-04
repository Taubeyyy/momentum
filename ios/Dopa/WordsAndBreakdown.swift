import SwiftUI
import UIKit

/// „Worte“: Wie ist das gemeint? (empfangene Nachricht) und Umschreiben (eigene Nachricht).
struct WordsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0                  // 0 = Wie ist das gemeint?, 1 = Umschreiben
    @State private var text = ""
    @State private var style = "sanft"
    @State private var interpretation: Server.Interpretation?
    @State private var rewrite: Server.Rewrite?
    @State private var busy = false
    @State private var error: String?

    private let styles: [(id: String, label: String)] = [
        ("sanft", "Sanfter"), ("kurz", "Kürzer"), ("klar", "Klarer"), ("formell", "Formeller"),
        ("locker", "Lockerer"), ("bestimmt", "Bestimmter"), ("absage", "Absage"), ("entschuldigung", "Entschuldigung"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Picker("", selection: $mode) {
                        Text("Wie ist das gemeint?").tag(0)
                        Text("Umschreiben").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 16)

                    Text(mode == 0
                         ? "Füg eine Nachricht ein, die du bekommen hast. Dopa sagt dir ehrlich, was drinsteht – und was du vielleicht reinliest."
                         : "Schreib, was du sagen willst. Dopa formuliert es um, ohne den Inhalt zu ändern.")
                        .font(.system(size: 13)).foregroundStyle(DS.muted).lineSpacing(2).padding(.bottom, 12)

                    TextField("", text: $text,
                              prompt: Text(mode == 0 ? "z. B. „Wir müssen heute Abend über deine Noten reden.“" : "z. B. „sorry kann morgen doch nicht“")
                                .foregroundColor(Color(hex: 0x68606D)),
                              axis: .vertical)
                        .lineLimit(4...10)
                        .font(.system(size: 16))
                        .foregroundStyle(DS.ink)
                        .padding(14)
                        .background(Color(hex: 0x0F0D11), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color(hex: 0x39323E)))

                    if mode == 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(styles.indices, id: \.self) { i in
                                    let s = styles[i]
                                    Button(s.label) { style = s.id }
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(style == s.id ? .white : Color(hex: 0xB9B0BF))
                                        .padding(.horizontal, 12)
                                        .frame(height: 34)
                                        .background(style == s.id ? Color(hex: 0x211B2B) : DS.field, in: Capsule())
                                        .overlay(Capsule().stroke(style == s.id ? DS.purpleMuted : DS.chipBorder))
                                        .buttonStyle(PressStyle())
                                }
                            }
                        }
                        .padding(.top, 10)
                    }

                    Button(action: run) {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(.white) }
                            Text(mode == 0 ? "Einordnen" : "Umschreiben")
                        }
                    }
                    .buttonStyle(SolidButtonStyle())
                    .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                    .padding(.top, 14)

                    if let error {
                        Text(error).font(.system(size: 12)).foregroundStyle(DS.muted).padding(.top, 10)
                    }

                    if mode == 0, let i = interpretation { interpretationView(i) }
                    if mode == 1, let r = rewrite { rewriteView(r) }
                }
                .padding(.horizontal, 19)
                .padding(.top, 16)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DS.raised.ignoresSafeArea())
            .navigationTitle("Worte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }

    private func interpretationView(_ i: Server.Interpretation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "So ist es wohl gemeint")
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { n in
                    Capsule().fill(n <= i.temperature ? temperatureColor(i.temperature) : Color(hex: 0x352A3B))
                        .frame(height: 6)
                }
            }
            Text(["", "Sehr freundlich", "Freundlich", "Neutral", "Angespannt", "Verärgert"][min(max(i.temperature, 1), 5)])
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.muted).padding(.top, 6)
            block("Was dasteht", i.literal)
            block("Ton", i.tone)
            if !i.overthinking.isEmpty { block("Was du vielleicht reinliest", i.overthinking) }
            block("Antwortvorschlag", i.reply, copy: true)
        }
    }

    private func rewriteView(_ r: Server.Rewrite) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            block("Umgeschrieben", r.result, copy: true)
            if !r.changed.isEmpty {
                Text(r.changed).font(.system(size: 12)).foregroundStyle(DS.muted).padding(.top, 6)
            }
        }
    }

    private func block(_ title: String, _ text: String, copy: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.uppercased()).font(.system(size: 10, weight: .heavy)).tracking(0.7).foregroundStyle(DS.purpleMuted)
                Spacer()
                if copy {
                    Button {
                        UIPasteboard.general.string = text
                        Toaster.shared.show("Kopiert")
                    } label: {
                        Label("Kopieren", systemImage: "doc.on.doc").font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(PressStyle())
                    .foregroundStyle(DS.purpleMuted)
                }
            }
            Text(text).font(.system(size: 15)).foregroundStyle(DS.ink).lineSpacing(3).textSelection(.enabled)
        }
        .padding(.top, 18)
    }

    private func temperatureColor(_ t: Int) -> Color {
        switch t {
        case 1, 2: Color(hex: 0x4ADE80)
        case 3: DS.purpleMuted
        case 4: Color(hex: 0xF5B94A)
        default: Color(hex: 0xEF6B6B)
        }
    }

    private func run() {
        busy = true
        error = nil
        let input = text
        let selected = style
        Task {
            do {
                if mode == 0 {
                    interpretation = try await Server.shared.interpret(input)
                } else {
                    rewrite = try await Server.shared.rewrite(input, mode: selected)
                }
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

/// „Zerlegen mit Schärfegrad“ (wie Magic ToDo): grob bis winzig, Schritte zum Abhaken.
struct BreakdownSheet: View {
    let task: TaskItem
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var resolution = 3.0
    @State private var steps: [SubStep] = []
    @State private var opener = ""
    @State private var busy = false
    @State private var error: String?

    private let labels = ["Grob", "Normal", "Klein", "Sehr klein", "Winzig"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(task.title).font(.system(size: 24, weight: .bold)).tracking(-0.7).foregroundStyle(DS.ink)
                    Text("Wie klein sollen die Schritte sein?").font(.system(size: 13)).foregroundStyle(DS.muted).padding(.top, 6)

                    HStack {
                        Text(labels[Int(resolution) - 1]).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.purpleMuted)
                        Spacer()
                        Text("Schärfe \(Int(resolution))/5").font(.system(size: 12)).foregroundStyle(DS.muted)
                    }
                    .padding(.top, 18)
                    Slider(value: $resolution, in: 1...5, step: 1)

                    Button(action: run) {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(.white) }
                            Text(steps.isEmpty ? "Zerlegen" : "Nochmal zerlegen")
                        }
                    }
                    .buttonStyle(SolidButtonStyle())
                    .disabled(busy)
                    .padding(.top, 12)

                    if let error {
                        Text(error).font(.system(size: 12)).foregroundStyle(DS.muted).padding(.top, 10)
                    }

                    if !steps.isEmpty {
                        if !opener.isEmpty {
                            Text(opener).font(.system(size: 14, weight: .medium)).foregroundStyle(Color(hex: 0xC5BDCA))
                                .padding(.top, 18)
                        }
                        SectionHeading(title: "Schritte") {
                            HeadingCount(text: "ca. \(steps.reduce(0) { $0 + $1.minutes }) Min")
                        }
                        HairlineList {
                            ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                                HStack(spacing: 12) {
                                    Text("\(i + 1)").font(.system(size: 12, weight: .bold)).foregroundStyle(DS.purpleMuted)
                                        .frame(width: 18)
                                    Text(step.title).font(.system(size: 15)).foregroundStyle(DS.ink)
                                    Spacer(minLength: 0)
                                    Text("\(step.minutes) Min").font(.system(size: 12)).foregroundStyle(DS.muted)
                                }
                                .padding(.vertical, 8)
                                .hairlineRow(minHeight: 50)
                            }
                        }
                        Button("Als Schritte übernehmen") {
                            store.setSteps(task.id, steps)
                            Toaster.shared.show("\(steps.count) Schritte angelegt")
                            dismiss()
                        }
                        .buttonStyle(SolidButtonStyle())
                        .padding(.top, 18)
                    }
                }
                .padding(.horizontal, 19)
                .padding(.top, 16)
                .padding(.bottom, 30)
            }
            .background(DS.raised.ignoresSafeArea())
            .navigationTitle("Zerlegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
            .onAppear {
                if !task.steps.isEmpty { steps = task.steps }
            }
        }
    }

    private func run() {
        busy = true
        error = nil
        let level = Int(resolution)
        Task {
            do {
                let result = try await Server.shared.breakdown(task.title, resolution: level)
                steps = result.steps.map { SubStep(title: $0.title, minutes: $0.minutes) }
                opener = result.opener
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
