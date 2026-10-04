import ActivityKit
import Foundation

/// Live Activity für den Fokus-Timer – neu gebaut in Build 32 (neuer Typname, neue Erweiterung),
/// damit nichts von den alten Versuchen im System hängen bleibt.
struct DopaTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var step: String
        var start: Date
        var end: Date
    }

    var title: String
}

/// Lebenszeichen der Timer-Erweiterung (App-Group): wurde sie geladen, hat sie gezeichnet?
/// Die App zeigt das unter Technik – so sieht man, ob iOS die Erweiterung überhaupt aufruft.
enum LiveProbe {
    static let loadedKey = "liveExtensionLoaded"
    static let renderedKey = "liveExtensionRendered"

    static func mark(_ key: String, _ what: String) {
        let c = Calendar.current.dateComponents([.day, .month, .hour, .minute, .second], from: Date())
        let stamp = String(format: "%d.%d. %02d:%02d:%02d", c.day ?? 0, c.month ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        Shared.defaults?.set("\(stamp) · \(what)", forKey: key)
    }

    static var loaded: String? { Shared.defaults?.string(forKey: loadedKey) }
    static var rendered: String? { Shared.defaults?.string(forKey: renderedKey) }
}
