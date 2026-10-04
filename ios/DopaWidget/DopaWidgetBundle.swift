import SwiftUI
import WidgetKit

@main
struct DopaWidgetBundle: WidgetBundle {
    init() {
        // Lebenszeichen für die Technik-Seite: iOS hat diese Erweiterung gestartet
        LiveProbe.mark(LiveProbe.loadedKey, "Widget-Erweiterung geladen")
    }

    var body: some Widget {
        DotWidget()
        NextWidget()
        NoteWidget()
        FocusWidget()
        MorningWidget()
        ShopWidget()
        // Live Activity wieder hier (Build 36): diese Erweiterung startet iOS nachweislich,
        // die eigene DopaTimer-Erweiterung wurde nie geladen
        TimerLiveActivity()
    }
}
