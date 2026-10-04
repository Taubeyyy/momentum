import SwiftUI

/// Mit Dot reden: Gespräch mit Gedächtnis. Dot kennt den Tag (Aufgaben, Termine, Notizen, Einkauf)
/// und schlägt Dinge zum Antippen vor – angelegt wird erst beim Tipp. Erreichbar über „Heute“ und das Profil.
struct DotChatPage: View {
    @EnvironmentObject private var store: Store
    @State private var draft = ""
    @State private var photo: UIImage?          // Foto für Dot (Wochenplan, Packliste …)
    @State private var choosingPhoto = false
    @State private var keyboard: CGFloat = 0
    @State private var confirmClear = false
    @FocusState private var focused: Bool

    private let bottomID = "dot-bottom"

    /// Dot oben reagiert: denkt beim Warten, hört zu beim Tippen.
    private var mood: DotExpression {
        if store.dotThinking { return .thinking }
        if focused && !empty { return .listening }
        return .auto
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.data.dotChat.isEmpty {
                        intro
                            .transition(.opacity)
                    } else {
                        ForEach(store.data.dotChat) { message in
                            DotBubble(message: message, isLast: message.id == store.data.dotChat.last?.id,
                                      onSuggestion: { send($0) },
                                      onGrow: { proxy.scrollTo(bottomID, anchor: .bottom) })
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity))
                        }
                    }
                    if store.dotThinking {
                        thinking
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    Color.clear.frame(height: 1).id(bottomID)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .animation(.spring(response: 0.42, dampingFraction: 0.84), value: store.data.dotChat.count)
                .animation(.easeOut(duration: 0.22), value: store.dotThinking)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
            .onAppear { scrollDown(proxy, animated: false) }
            .onChange(of: store.data.dotChat.count) { _ in scrollDown(proxy, animated: true) }
            .onChange(of: store.dotThinking) { _ in scrollDown(proxy, animated: true) }
            .onChange(of: keyboard) { _ in scrollDown(proxy, animated: true) }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .photoSource(isPresented: $choosingPhoto, title: "Foto für \(store.dotName)") { picked in
            photo = picked
            focused = true
        }
        .background(backdrop)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 7) {
                    DotView(level: store.level, size: 30, expression: mood)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(store.dotName).font(.system(size: 16, weight: .semibold)).foregroundStyle(DS.ink)
                        Text(store.dotThinking ? "denkt nach …" : focused && !empty ? "hört zu …" : "kennt deinen Tag")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.muted)
                            .animation(.easeOut(duration: 0.2), value: mood)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if !store.data.dotChat.isEmpty {
                    Button { confirmClear = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Neues Gespräch")
                }
            }
        }
        .confirmationDialog("Gespräch löschen und neu anfangen?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Neu anfangen", role: .destructive) { store.clearDotChat() }
            Button("Abbrechen", role: .cancel) {}
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            keyboard = max(0, UIScreen.main.bounds.height - frame.minY)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboard = 0
        }
    }

    /// Ruhiger Hintergrund mit einem Hauch Akzent oben – Dot „leuchtet“ in den Raum.
    private var backdrop: some View {
        ZStack {
            DS.surface
            RadialGradient(colors: [store.theme.accent.opacity(0.13), .clear],
                           center: .top, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }

    // MARK: Leerer Zustand

    private var intro: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let starters = DotChat.starters(hour: hour, mood: store.todayCheckIn?.mood,
                                        openTasks: store.todayTasks.count, focusRunning: store.data.focus != nil)
        return VStack(spacing: 18) {
            DotHeader(expression: mood)
            Text("Erzähl, was los ist, frag was oder sag „erinner mich …“. Ich kenne deinen Tag und trag Sachen ein, wenn du drauf tippst.")
                .font(.system(size: 14))
                .foregroundStyle(DS.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 12)
            VStack(spacing: 8) {
                ForEach(Array(starters.enumerated()), id: \.element) { index, text in
                    StarterButton(text: text, delay: Double(index) * 0.07) {
                        if text.contains("…") {
                            draft = "Wo hab ich "
                            focused = true
                        } else {
                            send(text)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var thinking: some View {
        HStack(alignment: .center, spacing: 10) {
            DotView(level: store.level, size: 30, expression: .thinking)
            TypingDots(color: DS.purpleMuted)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(DS.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(DS.line))
            Spacer(minLength: 0)
        }
        .accessibilityLabel("\(store.dotName) denkt nach")
    }

    // MARK: Eingabe

    private var empty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var bottomSafe: CGFloat {
        let scenes: [UIWindowScene] = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first?.windows.first?.safeAreaInsets.bottom ?? 0
    }

    private var inputBar: some View {
        let lift: CGFloat = keyboard > 0 ? max(8, keyboard - bottomSafe + 8) : TabBarSpace.height
        let ready = (!empty || photo != nil) && !store.dotThinking
        return VStack(alignment: .leading, spacing: 6) {
            if let photo { photoChip(photo) }
            inputRow(ready: ready)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, lift)
        .background(
            LinearGradient(colors: [DS.surface.opacity(0), DS.surface.opacity(0.96), DS.surface],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea())
        .animation(.easeOut(duration: 0.22), value: keyboard)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: photo != nil)
    }

    /// Gewähltes Foto als kleine Vorschau über dem Eingabefeld – x nimmt es wieder weg.
    private func photoChip(_ image: UIImage) -> some View {
        HStack(spacing: 8) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("Foto für \(store.dotName)").font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.muted)
            Button {
                photo = nil
            } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(DS.faint)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Foto entfernen")
        }
        .padding(6)
        .padding(.trailing, 4)
        .background(DS.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
    }

    private func inputRow(ready: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 4) {
            Button { choosingPhoto = true } label: {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.purpleMuted)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(PressStyle())
            .padding(.leading, 5)
            .padding(.bottom, 4)
            .accessibilityLabel("Foto schicken")
            TextField("", text: $draft, prompt: Text(photo == nil ? "Schreib \(store.dotName) …" : "Was soll ich damit machen?")
                        .foregroundColor(Color(hex: 0x756D7A)),
                      axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .font(.system(size: 16))
                .foregroundStyle(DS.ink)
                .padding(.vertical, 11)
            Button { send(draft) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(store.theme.accent.opacity(ready ? 1 : 0.35), in: Circle())
                    .scaleEffect(ready ? 1 : 0.86)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: ready)
            }
            .buttonStyle(PressStyle())
            .disabled(!ready)
            .padding(.trailing, 5)
            .padding(.bottom, 4)
            .accessibilityLabel("Schicken")
        }
        .background(DS.field, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(focused ? store.theme.accent.opacity(0.6) : DS.fieldBorder))
        .animation(.easeOut(duration: 0.2), value: focused)
    }

    private func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || photo != nil, !store.dotThinking else { return }
        // Foto verkleinert als JPEG – Dot (Gemini) liest Wochenpläne, Packlisten, Zettel
        let encoded: String? = photo.flatMap { MediaUpload.jpegBase64($0) }
        draft = ""
        photo = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { await store.sendToDot(text, photo: encoded) }
    }

    private func scrollDown(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(bottomID, anchor: .bottom) }
        } else {
            proxy.scrollTo(bottomID, anchor: .bottom)
        }
    }
}

/// Einstieg im leeren Gespräch – erscheint leicht versetzt nacheinander.
private struct StarterButton: View {
    let text: String
    let delay: Double
    let action: () -> Void
    @State private var shown = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.ink)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.faint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(DS.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DS.line))
        }
        .buttonStyle(PressStyle())
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 10)
        .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(delay), value: shown)
        .onAppear { shown = true }
    }
}

/// Eine Nachricht. Frische Antworten von Dot tippen sich kurz ein; danach erscheinen Vorschläge
/// (anlegen per Tipp) und – bei der letzten Nachricht – Antworten zum Antippen.
struct DotBubble: View {
    let message: DotMessage
    let isLast: Bool
    let onSuggestion: (String) -> Void
    let onGrow: () -> Void
    @EnvironmentObject private var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Int?          // nil = ganzer Text

    init(message: DotMessage, isLast: Bool, onSuggestion: @escaping (String) -> Void, onGrow: @escaping () -> Void) {
        self.message = message
        self.isLast = isLast
        self.onSuggestion = onSuggestion
        self.onGrow = onGrow
        let fresh = message.fromDot && !message.failed && Date().timeIntervalSince(message.at) < 3
        _shown = State(initialValue: fresh ? 0 : nil)
    }

    private var typing: Bool { shown != nil }

    var body: some View {
        if message.fromDot {
            dotSide
                .task { await typeIn() }
        } else {
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 4) {
                    if message.hasPhoto {
                        Label("mit Foto", systemImage: "photo")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.purpleMuted)
                    }
                    Text(message.text)
                        .font(.system(size: 15))
                        .foregroundStyle(DS.ink)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(store.theme.accent.opacity(0.28), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    /// Text in kleinen Stücken zeigen – höchstens gut eine Sekunde, egal wie lang.
    @MainActor private func typeIn() async {
        guard shown != nil else { return }
        if reduceMotion { shown = nil; return }
        let total = message.text.count
        let chunk = max(1, total / 50)
        var n = 0
        var step = 0
        while n < total && !Task.isCancelled {
            n = min(total, n + chunk)
            shown = n
            step += 1
            if step % 6 == 0 { onGrow() }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        shown = nil
        onGrow()
    }

    private var dotSide: some View {
        let text = shown.map { String(message.text.prefix($0)) } ?? message.text
        return HStack(alignment: .top, spacing: 10) {
            DotView(level: store.level, size: 30, animated: false)
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(message.failed ? DS.muted : DS.ink)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(DS.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(DS.line))

                if !typing {
                    ForEach(message.actions) { action in
                        DotActionButton(action: action) {
                            store.applyDotAction(message: message.id, action: action.id)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    if message.failed && isLast {
                        Button("Nochmal versuchen") { Task { await store.retryDot() } }
                            .buttonStyle(PillButtonStyle())
                    }

                    if isLast && !message.failed && !message.suggestions.isEmpty && !store.dotThinking {
                        suggestions
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.85), value: typing)
            Spacer(minLength: 24)
        }
    }

    private var suggestions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(message.suggestions, id: \.self) { text in
                    Button(text) { onSuggestion(text) }
                        .buttonStyle(PillButtonStyle())
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

/// Vorschlag zum Antippen. Nach dem Tipp springt ein Haken rein.
private struct DotActionButton: View {
    let action: DotAction
    let onTap: () -> Void
    @ObservedObject private var store = Store.shared

    var body: some View {
        Button {
            onTap()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    if action.done {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(store.theme.accent)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    } else {
                        Image(systemName: action.symbol)
                            .foregroundStyle(store.theme.accent)
                            .transition(.opacity)
                    }
                }
                .font(.system(size: 14, weight: .bold))
                .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.done ? action.doneLabel : action.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(action.done ? DS.muted : DS.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    // welche Schritte genau dazukommen – vor dem Antippen sichtbar
                    if !action.done && !action.items.isEmpty {
                        ForEach(Array(action.items.prefix(8).enumerated()), id: \.offset) { _, item in
                            Text("· \(item)")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.muted)
                                .lineLimit(1)
                        }
                        if action.items.count > 8 {
                            Text("· und \(action.items.count - 8) weitere")
                                .font(.system(size: 12)).foregroundStyle(DS.faint)
                        }
                    }
                    // Termine eines Plans: Tag, Uhrzeit, Titel
                    if !action.done && !action.entries.isEmpty {
                        ForEach(Array(action.entries.prefix(10).enumerated()), id: \.offset) { _, entry in
                            Text("· \(DotChat.dayLabel(entry.day, from: Date())) \(DotChat.clock(entry.time)) · \(entry.title)")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.muted)
                                .lineLimit(1)
                        }
                        if action.entries.count > 10 {
                            Text("· und \(action.entries.count - 10) weitere")
                                .font(.system(size: 12)).foregroundStyle(DS.faint)
                        }
                    }
                }
                Spacer(minLength: 0)
                if !action.done {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(store.theme.accent, in: Circle())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(action.done ? DS.field : DS.purpleSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(action.done ? DS.line : store.theme.accent.opacity(0.45)))
            .animation(.spring(response: 0.32, dampingFraction: 0.6), value: action.done)
        }
        .buttonStyle(PressStyle())
        .disabled(action.done)
    }
}
