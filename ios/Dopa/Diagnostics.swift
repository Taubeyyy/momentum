import Foundation

/// Fragt über die private LaunchServices-API ab, wie iOS die App registriert hat.
/// Nur zur Fehlersuche unter TrollStore: Kennt das System die Widget-Erweiterung?
/// Läuft nur auf Knopfdruck, damit ein Fehler hier nie den App-Start blockiert.
enum Diagnostics {
    struct Info {
        var registration = "?"     // "System" / "User"
        var plugins: [String] = [] // Bundle-IDs der registrierten Erweiterungen
    }

    static func read() -> Info {
        var info = Info()
        guard let id = Bundle.main.bundleIdentifier,
              let proxyClass = NSClassFromString("LSApplicationProxy") else { return info }
        // Bridging liefert das echte ObjC-Klassenobjekt; Aufrufe laufen über AnyObject-Dispatch.
        // (unsafeBitCast auf den Swift-Metatyp trifft bei reinen ObjC-Klassen einen Wrapper → Crash)
        let cls = proxyClass as AnyObject
        let factory = NSSelectorFromString("applicationProxyForIdentifier:")
        guard cls.responds(to: factory) == true,
              let proxy = cls.perform(factory, with: id)?.takeUnretainedValue() as? NSObject else { return info }

        // value(forKey:) wirft bei unbekannten Keys eine ObjC-Exception → vorher prüfen
        if proxy.responds(to: NSSelectorFromString("applicationType")) {
            info.registration = proxy.value(forKey: "applicationType") as? String ?? "?"
        }
        if proxy.responds(to: NSSelectorFromString("plugInKitPlugins")),
           let plugins = proxy.value(forKey: "plugInKitPlugins") as? [NSObject] {
            info.plugins = plugins.compactMap { plugin in
                plugin.responds(to: NSSelectorFromString("bundleIdentifier"))
                    ? plugin.value(forKey: "bundleIdentifier") as? String : nil
            }
        }
        return info
    }
}
