import Foundation

/// Gemeinsamer Speicher von App und Widget (App Group).
enum Shared {
    static let groupID = "group.com.taubey.dopa"
    static let widgetTextKey = "widgetText"

    // laufender Fokus-Timer (für das Sperrbildschirm-Widget)
    static let focusStepKey = "focusStep"
    static let focusStartKey = "focusStartedAt"
    static let focusEndKey = "focusEndsAt"

    static var defaults: UserDefaults? { UserDefaults(suiteName: groupID) }

    /// nil, wenn das App-Group-Entitlement nicht greift (z. B. falsch signiert).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    /// Die App-Daten (dopa.json) – Widgets lesen sie direkt mit.
    static var dataURL: URL? { containerURL?.appendingPathComponent("dopa.json") }

    static func loadData() -> AppData? {
        guard let url = dataURL, let raw = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppData.self, from: raw)
    }
}
