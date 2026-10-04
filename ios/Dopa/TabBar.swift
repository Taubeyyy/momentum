import SwiftUI

// Aufteilung seit Build 57: Heute · Machen (Aufgaben + Plan) · Merken · Einkauf · Mehr (Bubble:
// Geld, Schlaf, Dot, Claude, Profil). `day` und `claude` gibt es als Ziele weiter – Router.go leitet um.

enum AppTab: Int, CaseIterable, Hashable {
    case today, tasks, day, memo, shop, claude, more

    /// Was unten in der Leiste steht.
    static let bar: [AppTab] = [.today, .tasks, .memo, .shop, .more]

    var title: String {
        switch self {
        case .today: "Heute"
        case .tasks: "Machen"
        case .day: "Plan"
        case .memo: "Merken"
        case .shop: "Einkauf"
        case .claude: "Claude"
        case .more: "Mehr"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .tasks: "checklist"
        case .day: "calendar"
        case .memo: "note.text"
        case .shop: "bag"
        case .claude: "sparkles"
        case .more: "square.grid.2x2"
        }
    }
}

/// Unter „Machen“: Aufgaben oder Plan.
enum DoSection: Hashable { case tasks, plan }

/// Was in der „Mehr“-Bubble steht.
enum MoreItem: Int, CaseIterable, Hashable {
    case money, sleep, dot, claude, profile

    var title: String {
        switch self {
        case .money: "Geld"
        case .sleep: "Schlaf"
        case .dot: "Dot"
        case .claude: "Claude"
        case .profile: "Profil"
        }
    }

    var symbol: String {
        switch self {
        case .money: "eurosign.circle.fill"
        case .sleep: "bed.double.fill"
        case .dot: "bubble.left.and.text.bubble.right.fill"
        case .claude: "sparkles"
        case .profile: "person.crop.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .money: Color(hex: 0x4ADE80)
        case .sleep: Color(hex: 0x6366F1)
        case .dot: Color(hex: 0x8B5CF6)
        case .claude: Color(hex: 0xF59E0B)
        case .profile: Color(hex: 0x94A3B8)
        }
    }
}

/// Schwebende Leiste unten; der Akzent-Hintergrund gleitet zum gewählten Tab. „Mehr“ öffnet die Bubble.
/// Daumen über die Leiste ziehen = Tab wählen (für eine Hand – Edwin ist Linkshänder): die Markierung fährt mit,
/// beim Loslassen geht der Tab auf.
struct DopaTabBar: View {
    @Binding var selection: AppTab
    var onMore: () -> Void = {}
    @Namespace private var namespace
    @ObservedObject private var store = Store.shared
    @State private var scrubbing: AppTab?       // beim Ziehen: unter dem Daumen
    @State private var barWidth: CGFloat = 0

    /// Welcher Tab beim Ziehen an Position x liegt.
    private func tab(at x: CGFloat) -> AppTab {
        let tabs = AppTab.bar
        guard barWidth > 0 else { return selection }
        let index = Int((x / barWidth) * CGFloat(tabs.count))
        return tabs[min(tabs.count - 1, max(0, index))]
    }

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let hovered = tab(at: value.location.x)
                guard hovered != scrubbing else { return }
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { scrubbing = hovered }
            }
            .onEnded { value in
                let target = tab(at: value.location.x)
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    scrubbing = nil
                    if target != .more { selection = target }
                }
                if target == .more { onMore() }
            }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.bar, id: \.self) { tab in
                let selected = tab == (scrubbing ?? selection)
                Button {
                    if tab == .more {
                        UISelectionFeedbackGenerator().selectionChanged()
                        onMore()
                        return
                    }
                    guard tab != selection else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { selection = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .symbolVariant(selected ? .fill : .none)
                            .font(.system(size: 20, weight: selected ? .semibold : .regular))
                            .scaleEffect(selected ? 1.06 : 1)
                            .offset(y: selected ? -1 : 0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selected)
                            .popOnChange(of: selected, scale: 1.2, when: { $0 })
                        Text(tab.title)
                            .font(.system(size: 11, weight: selected ? .bold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selected ? DS.ink : Color(hex: 0x8A8290))
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(store.theme.accent.opacity(0.28))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(store.theme.accent.opacity(0.45), lineWidth: 1))
                                .matchedGeometryEffect(id: "tab", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        // Breite merken, damit beim Ziehen klar ist, welcher Tab unter dem Daumen liegt
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { barWidth = geo.size.width }
                .onChange(of: geo.size.width) { barWidth = $0 }
        })
        .contentShape(Rectangle())
        .highPriorityGesture(scrub)          // Tippen geht weiter an die Knöpfe, Ziehen wählt
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(Color(hex: 0x141217, opacity: 0.55), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        .padding(.horizontal, 14)
    }
}

/// Umschalter innerhalb einer Seite (z. B. Einkauf: Liste · Geld) – die Markierung gleitet mit.
struct SegmentPills<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String, symbol: String)]
    @Namespace private var namespace
    @ObservedObject private var store = Store.shared

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let selected = option.value == selection
                Button {
                    guard !selected else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selection = option.value }
                } label: {
                    Label(option.title, systemImage: option.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selected ? .white : Color(hex: 0xA59DAB))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if selected {
                                Capsule().fill(store.theme.accent)
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(4)
        .background(DS.field, in: Capsule())
        .overlay(Capsule().stroke(DS.chipBorder))
    }
}

// MARK: - Einheitliche Knöpfe

/// Zweiter Knopf neben dem vollen: ruhig, gleiche Höhe.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(DS.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color(hex: 0x241F29).opacity(configuration.isPressed ? 0.75 : 1),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: 0x342C3A)))
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(Motion.press(configuration.isPressed), value: configuration.isPressed)
    }
}

/// Kleiner Knopf in Zeilen („Erledigt“, „Bezahlt“, „Gegessen“).
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    @ObservedObject private var store = Store.shared

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(prominent ? Color.white : Color(hex: 0xD8CFE0))
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(prominent ? store.theme.accent : Color(hex: 0x28222D), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.press(configuration.isPressed), value: configuration.isPressed)
    }
}
