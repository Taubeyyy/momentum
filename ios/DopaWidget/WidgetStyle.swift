import SwiftUI
import WidgetKit

/// Home-Bildschirm-Widgets im Dopa-Look (dunkles Lila wie das Icon).
/// Sperrbildschirm-Widgets bleiben neutral – dort färbt iOS selbst.
struct WidgetCard: ViewModifier {
    @Environment(\.widgetFamily) private var family

    private var isHomeScreen: Bool {
        family == .systemSmall || family == .systemMedium || family == .systemLarge
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if isHomeScreen {
            content
                .foregroundStyle(.white)
                .environment(\.colorScheme, .dark)
                .background(
                    LinearGradient(colors: [Color(red: 0.26, green: 0.11, blue: 0.48),
                                            Color(red: 0.07, green: 0.02, blue: 0.15)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        } else {
            content
        }
    }
}

extension View {
    func widgetCard() -> some View { modifier(WidgetCard()) }
}
