import SwiftUI
import PhotosUI

/// „Notizen“: das zweite Gedächtnis – tippen, Enter, fertig. Die Art (Ort, Erledigt,
/// Absprache, Notiz) wird erkannt; wiederfinden per Suche („Wo ist mein Schlüssel?“).
struct MemoView: View {
    @EnvironmentObject private var store: Store
    let focusRequest: Int                       // ändert sich → Eingabefeld fokussieren
    @State private var handledRequest = 0
    @State private var text = ""
    @State private var chosenKind: MemoKind?    // nil = automatisch erkannt
    @State private var search = ""
    @State private var pendingPhoto: UIImage?
    @State private var suggesting = false
    @State private var choosingSource = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var taskIdea: TaskIdea?      // „Auch als Aufgabe?“ – Auftrag aus Notiz oder Foto
    @FocusState private var inputFocused: Bool

    private struct TaskIdea: Equatable {
        let title: String
        let day: Int                            // Tage ab heute, -1 = ohne Frist
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var currentKind: MemoKind { chosenKind ?? MemoKind.detect(trimmed) }

    private var shown: [Memo] {
        let words = Smart.searchWords(search)
        guard !words.isEmpty else { return store.data.memos }
        return store.data.memos.filter { memo in words.allSatisfy { memo.text.localizedStandardContains($0) } }
    }

    var body: some View {
        NavigationStack {
            DopaScreen(eyebrow: "Wo was liegt, was erledigt ist, was jemand gesagt hat", title: "Notizen", tab: .memo) {
                if let pendingPhoto {
                    PendingPhotoCard(image: pendingPhoto, suggesting: suggesting,
                                     onSave: save,
                                     onDiscard: { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { self.pendingPhoto = nil } })
                        .padding(.bottom, 10)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }

                HStack(spacing: 8) {
                    CaptureField(placeholder: pendingPhoto == nil ? "Was darf aus deinem Kopf?" : "Was ist drauf? z. B. Schlüssel im Flur",
                                 text: $text, focus: $inputFocused, onSubmit: save)
                    Button { choosingSource = true } label: {
                        Image(systemName: "camera")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(DS.purpleMuted)
                            .frame(width: 56, height: 56)
                            .background(DS.field, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(DS.fieldBorder))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Foto merken")
                }
                .confirmationDialog("Foto merken", isPresented: $choosingSource, titleVisibility: .hidden) {
                    if CameraPicker.available {
                        Button("Foto aufnehmen") { showCamera = true }
                    }
                    Button("Aus Fotos wählen") { showLibrary = true }
                }
                .fullScreenCover(isPresented: $showCamera) {
                    CameraPicker { image in setPhoto(image) }.ignoresSafeArea()
                }
                .sheet(isPresented: $showLibrary) {
                    LibraryPicker { image in setPhoto(image) }.ignoresSafeArea()
                }

                if let idea = taskIdea {
                    taskIdeaCard(idea)
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if !trimmed.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(MemoKind.allCases) { kind in
                                KindChip(kind: kind, selected: kind == currentKind) { chosenKind = kind }
                            }
                        }
                    }
                    .padding(.top, 10)
                }

                if store.data.memos.count > 3 {
                    SearchField(text: $search)
                        .padding(.top, 14)
                }

                if !search.isEmpty, let best = shown.first {
                    SectionHeading(title: "Zuletzt")
                    MemoLine(memo: best, large: true) { store.deleteMemo(best.id) }
                }

                SectionHeading(title: search.isEmpty ? "Gemerkte Dinge" : "Treffer") {
                    HeadingCount(text: "\(shown.count)")
                }
                if shown.isEmpty {
                    EmptyState(symbol: "",
                               title: search.isEmpty ? "Noch nichts gemerkt" : "Nichts gefunden",
                               text: search.isEmpty
                                   ? "Zum Beispiel „Schlüssel liegt auf der Kommode“ oder „Herd ist aus“."
                                   : "Die Suche findet einzelne Wörter – vielleicht anders formuliert?")
                } else {
                    HairlineList {
                        ForEach(shown) { memo in
                            MemoLine(memo: memo) { store.deleteMemo(memo.id) }
                                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                        removal: .opacity))
                        }
                    }
                    .animation(Motion.list, value: shown.map(\.id))
                }
            }
            .onAppear(perform: handleFocusRequest)
            .onChange(of: focusRequest) { _ in handleFocusRequest() }
        }
    }

    private func handleFocusRequest() {
        guard focusRequest != handledRequest else { return }
        handledRequest = focusRequest
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { inputFocused = true }
    }

    /// Vorschlag unter dem Eingabefeld: Auftrag (z. B. von einer Lehrkraft) gleich als Aufgabe mit Frist anlegen.
    private func taskIdeaCard(_ idea: TaskIdea) -> some View {
        let when: String = idea.day < 0 ? "" : idea.day == 0 ? " · heute" : idea.day == 1 ? " · morgen"
            : " · " + DotChat.dayLabel(idea.day, from: Date())
        return HStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(store.theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("AUCH ALS AUFGABE?").font(.system(size: 10, weight: .heavy)).tracking(0.7).foregroundStyle(DS.purpleMuted)
                Text(idea.title + when).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button("Übernehmen") {
                store.addTask(idea.title, day: idea.day)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                Toaster.shared.show("Aufgabe angelegt")
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { taskIdea = nil }
            }
            .buttonStyle(PillButtonStyle(prominent: true))
            Button {
                withAnimation(.easeOut(duration: 0.2)) { taskIdea = nil }
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(DS.faint)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Kein Auftrag")
        }
        .padding(12)
        .background(DS.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(store.theme.accent.opacity(0.4)))
    }

    /// Getippte Notiz klingt nach Auftrag → KI (Smart Dump) fragen, ob und bis wann eine Aufgabe daraus wird.
    private func suggestTask(from text: String) {
        guard Smart.looksLikeAssignment(text), Server.shared.isConnected, Server.shared.aiAvailable else { return }
        Task {
            guard let result = try? await Server.shared.dump(text), let first = result.tasks.first else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                taskIdea = TaskIdea(title: first.title, day: first.day)
            }
        }
    }

    private func save() {
        if let photo = pendingPhoto {
            // Foto geht auch ohne Text – dann ist es meistens ein Ort
            guard let name = MemoPhotos.save(photo) else {
                Toaster.shared.show("Foto ließ sich nicht speichern")
                return
            }
            store.addMemo(trimmed.isEmpty ? "Foto" : trimmed, kind: chosenKind ?? (trimmed.isEmpty ? .place : nil), photo: name)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { pendingPhoto = nil }
        } else {
            guard !trimmed.isEmpty else { return }
            store.addMemo(trimmed, kind: chosenKind)
            withAnimation(.easeOut(duration: 0.2)) { taskIdea = nil }   // alter Vorschlag weg, ggf. kommt ein neuer
            suggestTask(from: trimmed)
        }
        text = ""
        chosenKind = nil
        inputFocused = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Toaster.shared.show("Gemerkt")
    }

    private func setPhoto(_ image: UIImage) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            pendingPhoto = image
            taskIdea = nil
        }
        // Gemini schlägt vor, was drauf ist – du musst nur noch „Merken“ tippen
        guard Server.shared.isConnected, Server.shared.aiAvailable,
              let encoded = MediaUpload.jpegBase64(image, maxSide: 1600, quality: 0.75) else {   // groß genug für Handschrift
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { inputFocused = true }
            return
        }
        suggesting = true
        Task {
            if let result = try? await Server.shared.photoCaption(encoded), pendingPhoto != nil {
                if text.trimmingCharacters(in: .whitespaces).isEmpty {
                    withAnimation(.easeOut(duration: 0.2)) {
                        text = result.caption
                        chosenKind = MemoKind(rawValue: result.kind)
                    }
                }
                // Auftrag auf dem Foto (Zettel einer Lehrkraft …) → „Auch als Aufgabe?“
                if let task = result.task, !task.isEmpty {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        taskIdea = TaskIdea(title: task, day: result.day ?? -1)
                    }
                }
            }
            suggesting = false
        }
    }
}

extension MemoKind {
    /// Punktfarbe in der Liste – ruhig, nur zur Orientierung.
    var dot: Color {
        switch self {
        case .place: Color(hex: 0x8B5CF6)
        case .done: Color(hex: 0x4ADE80)
        case .agreement: Color(hex: 0xF5B94A)
        case .note: Color(hex: 0x6F6674)
        }
    }
}

struct MemoLine: View {
    let memo: Memo
    var large = false
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let photo = memo.photo {
                MemoThumbnail(name: photo, size: large ? 72 : 52)
            } else {
                Circle().fill(memo.kind.dot).frame(width: 7, height: 7)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(memo.text)
                    .font(.system(size: large ? 18 : 15, weight: .semibold))
                    .foregroundStyle(DS.ink)
                TimelineView(.everyMinute) { context in
                    Text("\(memo.kind.label) · \(MemoLine.when(memo.createdAt, now: context.date))")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.muted)
                }
            }
            Spacer(minLength: 0)
            Button(action: onDelete) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0x68606D))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Löschen")
        }
        .padding(.vertical, 10)
        .hairlineRow()
    }

    /// „vor 5 Minuten · 14:32“ bzw. mit Datum, wenn es nicht von heute ist.
    static func when(_ date: Date, now: Date = .now) -> String {
        let today = Calendar.current.isDate(date, inSameDayAs: now)
        let exact = date.formatted(date: today ? .omitted : .abbreviated, time: .shortened)
        guard now.timeIntervalSince(date) >= 60 else { return "gerade eben · \(exact)" }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        return "\(relative.localizedString(for: date, relativeTo: now)) · \(exact)"
    }
}

private struct KindChip: View {
    let kind: MemoKind
    let selected: Bool
    let action: () -> Void
    @ObservedObject private var store = Store.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(kind.dot).frame(width: 6, height: 6)
                Text(kind.label).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(selected ? .white : Color(hex: 0xB9B0BF))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(selected ? Color(hex: 0x211B2B) : DS.field, in: Capsule())
            .overlay(Capsule().stroke(selected ? store.theme.accent : DS.chipBorder))
        }
        .buttonStyle(.plain)
    }
}

/// Gerade gewähltes Foto: Vorschau, „Merken“ (geht auch ohne Text) und Verwerfen.
private struct PendingPhotoCard: View {
    let image: UIImage
    var suggesting = false
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                if suggesting {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.8)
                        Text("Dot schaut, was drauf ist …").font(.system(size: 12)).foregroundStyle(DS.muted)
                    }
                } else {
                    Text("Text unten passt? Dann einfach „Merken“. Die Suche findet es über den Text.")
                        .font(.system(size: 12)).foregroundStyle(DS.muted).lineSpacing(2)
                }
                HStack(spacing: 8) {
                    Button("Merken", action: onSave).buttonStyle(PillButtonStyle(prominent: true))
                    Button("Verwerfen", action: onDiscard).buttonStyle(PillButtonStyle())
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(DS.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(DS.line))
    }
}

/// Schlichtes Suchfeld im Dopa-Look.
struct SearchField: View {
    @Binding var text: String
    var prompt = "Wo ist mein Schlüssel?"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(DS.faint)
            TextField("", text: $text, prompt: Text(prompt).foregroundColor(Color(hex: 0x756D7A)))
                .font(.system(size: 15))
                .foregroundStyle(DS.ink)
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(DS.faint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(DS.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DS.line))
    }
}
