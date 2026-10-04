import SwiftUI

/// „Machen“: Aufgaben und Plan unter einem Tab. Beide bleiben geladen (der Plan reagiert auf
/// Morgen-/Abend-Anfragen aus Mitteilungen), sichtbar ist nur einer.
struct DoPage: View {
    let morningRequest: Int
    let eveningRequest: Int
    @ObservedObject private var router = Router.shared

    var body: some View {
        let plan = router.doSection == .plan
        ZStack {
            TasksView()
                .opacity(plan ? 0 : 1)
                .allowsHitTesting(!plan)
                .accessibilityHidden(plan)
            DayView(morningRequest: morningRequest, eveningRequest: eveningRequest)
                .opacity(plan ? 1 : 0)
                .allowsHitTesting(plan)
                .accessibilityHidden(!plan)
        }
        .animation(.easeOut(duration: 0.2), value: plan)
    }
}

/// Umschalter oben in „Machen“: Aufgaben · Plan.
struct DoSwitch: View {
    @ObservedObject private var router = Router.shared

    var body: some View {
        SegmentPills(selection: $router.doSection, options: [
            (value: DoSection.tasks, title: "Aufgaben", symbol: "checklist"),
            (value: DoSection.plan, title: "Plan", symbol: "calendar"),
        ])
        .padding(.bottom, 16)
    }
}

/// „Mehr“: was in der Bubble gewählt wurde – Geld, Schlaf, Dot oder Profil.
struct MorePage: View {
    @ObservedObject private var router = Router.shared

    var body: some View {
        switch router.moreItem {
        case .money:
            ShopView(mode: .money)              // hat eigene Navigation
        case .sleep:
            NavigationStack { SleepPage() }.id(MoreItem.sleep)
        case .dot:
            NavigationStack { DotChatPage() }.id(MoreItem.dot)
        case .profile:
            NavigationStack { ProfilePage() }.id(MoreItem.profile)
        }
    }
}

/// Kleine Bubble über „Mehr“: vier Ziele, ein Tipp. Daneben tippen schließt sie.
struct MoreBubble: View {
    let onPick: (MoreItem) -> Void
    let onClose: () -> Void
    @ObservedObject private var router = Router.shared
    @ObservedObject private var store = Store.shared
    @AppStorage("leftHanded") private var leftHanded = true     // Edwin ist Linkshänder

    var body: some View {
        let corner: UnitPoint = leftHanded ? .bottomLeading : .bottomTrailing
        ZStack(alignment: leftHanded ? .bottomLeading : .bottomTrailing) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(MoreItem.allCases, id: \.self) { item in
                    row(item)
                }
            }
            .padding(8)
            .frame(width: 240)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .background(Color(hex: 0x141217, opacity: 0.7), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.08)))
            .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
            .padding(leftHanded ? .leading : .trailing, 16)
            .padding(.bottom, 90)
            .transition(.scale(scale: 0.85, anchor: corner).combined(with: .opacity))
        }
    }

    private func row(_ item: MoreItem) -> some View {
        let current = router.tab == .more && router.moreItem == item
        return Button { onPick(item) } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(item.color.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(item == .dot ? store.dotName : item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.ink)
                Spacer(minLength: 0)
                if current {
                    Circle().fill(store.theme.accent).frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(item == .dot ? store.dotName : item.title)
    }
}
