import SwiftUI

// Design-System nach dem eigenen Entwurf (Figma-Export, Oktober 2026):
// fast schwarz, ein Lila als Akzent, Haarlinien statt Karten, keine Emojis, keine Verläufe.

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum DS {
    static let background = Color(hex: 0x08090B)
    static let surface = Color(hex: 0x101114)
    static let raised = Color(hex: 0x18191E)
    static let panel = Color(hex: 0x19171D)
    static let panelBorder = Color(hex: 0x302B38)
    static let field = Color(hex: 0x121317)
    static let fieldBorder = Color(hex: 0x3A3140)
    static let line = Color(hex: 0x292A30)
    static let ink = Color(hex: 0xF2F2F4)
    static let muted = Color(hex: 0x96969F)
    static let faint = Color(hex: 0x716A76)
    static let purpleSoft = Color(hex: 0x211A2C)
    static let purpleMuted = Color(hex: 0xA78BFA)
    static let chipBorder = Color(hex: 0x3B3340)
}

// MARK: - Bildschirm-Gerüst

/// Scrollende Seite im Dopa-Look: Kopf mit Level-Abzeichen, Datum, großer Titel.
/// Knopf rechts oben in der Kopfzeile.
struct HeaderAccessory {
    let symbol: String
    let label: String
    let action: () -> Void
}

/// Seite im Dopa-Look mit echter iOS-Navigation: großer Titel, der beim Scrollen in die Leiste
/// wandert, oben rechts Dot als Avatar (Profil & Einstellungen), darunter das Datum.
struct DopaScreen<Content: View>: View {
    let eyebrow: String
    let title: String
    var accessory: HeaderAccessory?
    var tab: AppTab?
    @ViewBuilder let content: Content
    @ObservedObject private var router = Router.shared
    @State private var showFeedback = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(eyebrow)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.muted)
                    .padding(.bottom, 18)
                content.enterAnimation(delay: 0.05)
            }
            .padding(.horizontal, 20)
            .padding(.top, 2)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: TabBarSpace.height) }
        .scrollDismissesKeyboard(.interactively)
        .background(DS.surface.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if let accessory {
                    Button(action: accessory.action) {
                        Image(systemName: accessory.symbol).font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel(accessory.label)
                }
                AvatarButton()
            }
        }
        // Handy schütteln: Feedback-Fenster geht von der sichtbaren Seite aus auf
        .sheet(isPresented: $showFeedback) {
            FeedbackSheet(screen: router.tabName).environmentObject(Store.shared)
        }
        .onChange(of: router.feedbackRequest) { _ in
            if let tab, router.tab == tab { showFeedback = true }
        }
    }
}

/// Dot oben rechts: kleiner Avatar mit Level-Ring – führt zu Profil & Einstellungen.
struct AvatarButton: View {
    @ObservedObject private var store = Store.shared

    var body: some View {
        let progress = Level.progress(store.data.game.xp)
        NavigationLink {
            ProfilePage()
        } label: {
            ZStack {
                Circle().stroke(Color(hex: 0x3A3042), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: CGFloat(progress.have) / CGFloat(max(1, progress.need)))
                    .stroke(store.theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress.have)
                DotView(level: store.level, size: 26, animated: false)
            }
            .frame(width: 34, height: 34)
            .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Profil und Einstellungen, Level \(store.level)")
    }
}

/// Ruhige Karte mit kleiner Kopfzeile – das Grundraster von „Heute“.
struct Card<Trailing: View, Content: View>: View {
    let title: String
    var symbol: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.purpleMuted)
                }
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Color(hex: 0xA59DAB))
                Spacer(minLength: 0)
                trailing
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(DS.line.opacity(0.8)))
    }
}

extension Card where Trailing == EmptyView {
    init(title: String, symbol: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, trailing: { EmptyView() }, content: content)
    }
}

/// Zeile wie in den iOS-Einstellungen: farbige Kachel mit Symbol, Titel, Wert rechts.
struct SettingsRow: View {
    let icon: String
    let color: Color
    let title: String
    var value: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(title).foregroundStyle(DS.ink)
            Spacer(minLength: 8)
            if let value {
                Text(value).foregroundStyle(DS.muted).lineLimit(1)
            }
        }
        .padding(.vertical, 1)
    }
}

/// Abschnittskopf: Titel links, Zahl oder Plus rechts.
struct SectionHeading<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 20, weight: .bold, design: .rounded)).tracking(-0.3).foregroundStyle(DS.ink)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(DS.muted)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.top, 32)
        .padding(.bottom, 12)
    }
}

extension SectionHeading where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Zahl rechts im Abschnittskopf („2/5“, „3 offen“).
struct HeadingCount: View {
    let text: String
    var body: some View { RollingText(text: text).font(.system(size: 12)).foregroundStyle(DS.muted).monospacedDigit() }
}

// MARK: - Zeilen

/// Liste mit Haarlinien: Linie oben, jede Zeile mit Linie unten.
struct HairlineList<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .overlay(alignment: .top) { Rectangle().fill(DS.line).frame(height: 1) }
    }
}

extension View {
    /// Eine Zeile in einer HairlineList.
    func hairlineRow(minHeight: CGFloat = 62) -> some View {
        frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(DS.line).frame(height: 1) }
    }
}

/// Eckiges Häkchen-Kästchen wie im Entwurf. Beim Abhaken: Kästchen füllt sich, Haken zeichnet sich,
/// kurzes Plopp und ein Ring läuft nach außen.
struct CheckBox: View {
    let done: Bool
    @ObservedObject private var store = Store.shared

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(done ? store.theme.accent : .clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(done ? store.theme.accent : Color(hex: 0x5C5361), lineWidth: 1.5))
            .overlay {
                CheckShape()
                    .trim(from: 0, to: done ? 1 : 0)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .frame(width: 12, height: 9)
                    .animation(done ? .easeOut(duration: 0.22).delay(0.06) : .easeOut(duration: 0.1), value: done)
            }
            .frame(width: 26, height: 26)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: done)
            .popOnChange(of: done, scale: 1.12, when: { $0 })
    }
}

/// Runder Haken für Checklisten (Morgen): füllt sich und ploppt.
struct RoundCheck: View {
    let done: Bool
    var color: Color = .green

    var body: some View {
        ZStack {
            Circle().stroke(done ? color : Color.secondary, lineWidth: 1.8)
            Circle().fill(color).scaleEffect(done ? 1 : 0.2).opacity(done ? 1 : 0)
            CheckShape()
                .trim(from: 0, to: done ? 1 : 0)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .frame(width: 11, height: 8)
                .animation(done ? .easeOut(duration: 0.22).delay(0.08) : .easeOut(duration: 0.1), value: done)
        }
        .frame(width: 26, height: 26)
        .animation(.spring(response: 0.28, dampingFraction: 0.65), value: done)
        .popOnChange(of: done, scale: 1.12, when: { $0 })
    }
}

/// Eingabefeld mit Plus-Knopf (Merken, Einkauf, Aufgaben).
struct CaptureField: View {
    let placeholder: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding?
    let onSubmit: () -> Void
    @ObservedObject private var store = Store.shared

    private var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: 8) {
            field
                .font(.system(size: 16))
                .foregroundStyle(DS.ink)
                .submitLabel(.done)
                .onSubmit(onSubmit)
            Button(action: onSubmit) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(store.theme.accent.opacity(empty ? 0.45 : 1),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .scaleEffect(empty ? 0.9 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: empty)
            }
            .buttonStyle(PressStyle())
            .disabled(empty)
        }
        .padding(.leading, 15)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .background(DS.field, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(DS.fieldBorder))
    }

    @ViewBuilder private var field: some View {
        let tf = TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Color(hex: 0x756D7A)))
        if let focus { tf.focused(focus) } else { tf }
    }
}

/// Voller Akzent-Knopf.
struct SolidButtonStyle: ButtonStyle {
    @ObservedObject private var store = Store.shared

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(store.theme.accent.opacity(configuration.isPressed ? 0.8 : 1),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(Motion.press(configuration.isPressed), value: configuration.isPressed)
    }
}

/// Kleiner Plus-Knopf im Abschnittskopf.
struct MiniAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.purpleMuted)
                .frame(width: 34, height: 34)
                .background(Color(hex: 0x2A1A34), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }
}

/// Umrandete Fläche (Was jetzt?, Budget, Dranbleiben).
struct Panel<Content: View>: View {
    var highlighted = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(highlighted ? Color(hex: 0x4A3A5C) : DS.line.opacity(0.8)))
    }
}

/// Dünner Fortschrittsbalken (Budget, Level).
struct Track: View {
    let fraction: Double
    @ObservedObject private var store = Store.shared

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: 0x352A3B))
                Capsule().fill(store.theme.accent)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
                    .animation(.spring(response: 0.6, dampingFraction: 0.85), value: fraction)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Listen-Ansichten (Sheets, Einstellungen) im selben Look

/// Platz für die schwebende Tab-Leiste. Muss direkt an der Scroll-Ansicht hängen –
/// außen um einen NavigationStack herum kommt der Abstand unter iOS 16 nicht an.
enum TabBarSpace {
    static let height: CGFloat = 90          // Leiste ist seit Build 63 etwas höher (leichter mit dem Daumen)
}

struct DopaBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: TabBarSpace.height) }
            .background(DS.surface.ignoresSafeArea())
    }
}

extension View {
    func dopaBackground() -> some View { modifier(DopaBackground()) }
    func dopaRow() -> some View { listRowBackground(RowBackground()) }
    /// Hervorgehobene Karte (Timer, Morgen) – ruhig, ohne Verlauf und Glow.
    func accentCard() -> some View { modifier(AccentCard()) }
}

struct RowBackground: View {
    var body: some View { Rectangle().fill(DS.raised) }
}

struct AccentCard: ViewModifier {
    @ObservedObject private var store = Store.shared

    func body(content: Content) -> some View {
        content
            .foregroundStyle(DS.ink)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x1E1524), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(alignment: .leading) {
                UnevenAccentBar(color: store.theme.accent)
            }
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color(hex: 0x3A2C42)))
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
    }
}

/// Lila Kante links – das „Jetzt“-Merkmal aus dem Entwurf.
private struct UnevenAccentBar: View {
    let color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3).padding(.vertical, 14)
    }
}

/// Freundlicher Leerzustand.
struct EmptyState: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink)
            Text(text).font(.system(size: 13)).foregroundStyle(DS.muted).lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
    }
}

// MARK: - Belohnungen

/// Kleine Einblendung oben: „+10 XP · Aufgabe erledigt“.
struct AwardToast: View {
    let award: Award
    @ObservedObject private var store = Store.shared

    var body: some View {
        HStack(spacing: 10) {
            Text("+\(award.amount)")
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(store.theme.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .popIn(delay: 0.08)
            VStack(alignment: .leading, spacing: 1) {
                Text(award.lucky ? "Glückstreffer" : award.quest != nil ? "Quest geschafft" : "XP")
                    .font(.system(size: 13, weight: .semibold))
                Text(award.quest ?? award.reason)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.muted)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(DS.ink)
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .background(DS.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.panelBorder))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        .padding(.top, 6)
    }
}

/// Level-Up: groß, kurz, ruhig.
struct LevelUpView: View {
    let level: Int
    let onClose: () -> Void
    @State private var appear = false
    @ObservedObject private var store = Store.shared

    private var unlocked: Theme? { Theme.all.first { $0.level == level } }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
                .onTapGesture(perform: onClose)
            VStack(spacing: 12) {
                Text("\(level)")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 84)
                    .background(DS.purpleSoft, in: Circle())
                    .overlay(Circle().stroke(store.theme.accent, lineWidth: 2))
                    .scaleEffect(appear ? 1 : 0.5)
                Text("LEVEL \(level)").font(.system(size: 11, weight: .heavy)).tracking(1).foregroundStyle(DS.muted)
                Text(Level.title(level)).font(.system(size: 34, weight: .bold)).tracking(-1).foregroundStyle(DS.ink)
                if let unlocked {
                    Text("Neue Farbe frei: \(unlocked.name)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.purpleMuted)
                }
            }
            .padding(32)
        }
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { appear = true }
        }
    }
}
