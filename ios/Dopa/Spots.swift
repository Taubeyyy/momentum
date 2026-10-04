import CoreLocation
import MapKit
import SwiftUI

/// Standort nur auf Knopfdruck: einmal „Ich bin gerade hier“ oder eine Adresse suchen.
/// Erinnerungen beim Ankommen übernimmt iOS selbst (UNLocationNotificationTrigger) – Dopa verfolgt nichts.
@MainActor
final class Locator: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = Locator()

    private let manager: CLLocationManager
    @Published private(set) var status: CLAuthorizationStatus
    private var waiting: CheckedContinuation<CLLocation?, Never>?
    private var authWaiting: CheckedContinuation<Void, Never>?

    override init() {
        let m = CLLocationManager()
        manager = m
        status = m.authorizationStatus
        super.init()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    var allowed: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }
    var denied: Bool { status == .denied || status == .restricted }

    /// Einmal fragen („Beim Verwenden der App“) – wartet auf die Antwort.
    func requestAuthorization() async {
        guard status == .notDetermined else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            authWaiting = cont
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Aktueller Standort, einmalig.
    func current() async -> CLLocation? {
        await requestAuthorization()
        guard allowed, waiting == nil else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<CLLocation?, Never>) in
            waiting = cont
            manager.requestLocation()
        }
    }

    /// Adresse → Koordinate und ein lesbarer Name („Hauptstraße 5, Berlin“).
    func search(_ address: String) async -> (CLLocationCoordinate2D, String)? {
        guard let marks = try? await CLGeocoder().geocodeAddressString(address),
              let mark = marks.first, let location = mark.location else { return nil }
        let parts: [String] = [mark.name, mark.locality].compactMap { $0 }
        return (location.coordinate, parts.joined(separator: ", "))
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            self.status = s
            if s != .notDetermined {
                self.authWaiting?.resume()
                self.authWaiting = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in
            self.waiting?.resume(returning: last)
            self.waiting = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.waiting?.resume(returning: nil)
            self.waiting = nil
        }
    }
}

/// Orte (Profil → Einstellungen → Orte): Zuhause, Läden, Uni … Aufgaben können sich beim Ankommen melden.
struct SpotsPage: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var locator = Locator.shared

    var body: some View {
        List {
            Section {
                ForEach(store.data.spots) { spot in
                    NavigationLink { SpotEditor(spot: spot) } label: {
                        SettingsRow(icon: spot.symbol, color: Color(hex: 0x6366F1), title: spot.name,
                                    value: spot.shopHint ? "mit Einkaufsliste" : "\(Int(spot.radius)) m")
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { store.data.spots[$0].id }
                    for id in ids { store.deleteSpot(id) }
                }
                NavigationLink { SpotEditor(spot: nil) } label: {
                    Label("Ort hinzufügen", systemImage: "plus.circle.fill")
                }
            } footer: {
                Text("Gib einer Aufgabe einen Ort („Wo?“) – kommst du dort an, meldet sich Dopa, auch auf der Uhr. Oder sag Dot: „Erinner mich zu Hause an …“.")
            }
            .dopaRow()

            if locator.denied {
                Section {
                    Text("Standort ist für Dopa aus. Einstellungen → Dopa → Standort → „Beim Verwenden der App“, sonst kann iOS das Ankommen nicht melden.")
                        .font(.system(size: 13)).foregroundStyle(DS.muted)
                }
                .dopaRow()
            }
        }
        .dopaBackground()
        .navigationTitle("Orte")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Einen Ort anlegen oder ändern: Name, Symbol, wo (hier oder Adresse), Umkreis, Einkaufsliste.
struct SpotEditor: View {
    let spot: Spot?
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = "house.fill"
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var address = ""
    @State private var found = ""
    @State private var radius = 150.0
    @State private var shopHint = false
    @State private var busy = false
    @State private var problem: String?

    private struct Pin: Identifiable {
        let id = 0
        let coordinate: CLLocationCoordinate2D
    }

    var body: some View {
        Form {
            Section {
                TextField("Name, z. B. Zuhause, Lidl, Uni", text: $name)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Spot.symbols, id: \.self) { s in
                            Button { symbol = s } label: {
                                Image(systemName: s)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(symbol == s ? .white : DS.purpleMuted)
                                    .frame(width: 42, height: 42)
                                    .background(symbol == s ? store.theme.accent : DS.field,
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .dopaRow()

            Section {
                if let coordinate {
                    Map(coordinateRegion: .constant(MKCoordinateRegion(center: coordinate, latitudinalMeters: max(400, radius * 5),
                                                                       longitudinalMeters: max(400, radius * 5))),
                        interactionModes: [],
                        annotationItems: [Pin(coordinate: coordinate)]) { pin in
                        MapMarker(coordinate: pin.coordinate, tint: .purple)
                    }
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    if !found.isEmpty {
                        Text(found).font(.system(size: 13)).foregroundStyle(DS.muted)
                    }
                }
                Button { Task { await useHere() } } label: {
                    HStack {
                        Label("Ich bin gerade hier", systemImage: "location.fill")
                        if busy { Spacer(); ProgressView() }
                    }
                }
                .disabled(busy)
                HStack {
                    TextField("oder Adresse eingeben", text: $address)
                        .submitLabel(.search)
                        .onSubmit { Task { await searchAddress() } }
                    Button("Suchen") { Task { await searchAddress() } }
                        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }
                if let problem {
                    Text(problem).font(.system(size: 13)).foregroundStyle(Color(hex: 0xF5B94A))
                }
            } header: {
                Text("Wo?")
            }
            .dopaRow()

            Section {
                Picker("Umkreis", selection: $radius) {
                    Text("100 m").tag(100.0)
                    Text("150 m").tag(150.0)
                    Text("300 m").tag(300.0)
                    Text("500 m").tag(500.0)
                }
                Toggle("Einkaufsliste zeigen, wenn ich hier bin", isOn: $shopHint)
                    .tint(store.theme.accent)
            } footer: {
                Text("Ein größerer Umkreis meldet sich früher – praktisch bei großen Läden oder wenn GPS ungenau ist.")
            }
            .dopaRow()

            if let spot {
                Section {
                    Button("Ort löschen", role: .destructive) {
                        store.deleteSpot(spot.id)
                        dismiss()
                    }
                }
                .dopaRow()
            }
        }
        .dopaBackground()
        .navigationTitle(spot == nil ? "Neuer Ort" : spot?.name ?? "Ort")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || coordinate == nil)
            }
        }
        .onAppear {
            guard let spot else { return }
            name = spot.name
            symbol = spot.symbol
            coordinate = CLLocationCoordinate2D(latitude: spot.lat, longitude: spot.lon)
            radius = spot.radius
            shopHint = spot.shopHint
        }
    }

    private func useHere() async {
        busy = true
        problem = nil
        if let location = await Locator.shared.current() {
            coordinate = location.coordinate
            found = "Aktueller Standort (± \(Int(location.horizontalAccuracy)) m)"
        } else {
            problem = Locator.shared.denied
                ? "Standort ist aus – in den Einstellungen für Dopa erlauben."
                : "Standort gerade nicht gefunden. Nochmal versuchen oder Adresse eingeben."
        }
        busy = false
    }

    private func searchAddress() async {
        let text = address.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        busy = true
        problem = nil
        if let result = await Locator.shared.search(text) {
            coordinate = result.0
            found = result.1
        } else {
            problem = "Adresse nicht gefunden. Mit Ort probieren, z. B. „Hauptstraße 5, Berlin“."
        }
        busy = false
        await Locator.shared.requestAuthorization()     // sonst kann iOS das Ankommen nicht melden
    }

    private func save() {
        guard let coordinate else { return }
        var saved = spot ?? Spot(name: "", lat: 0, lon: 0)
        saved.name = name.trimmingCharacters(in: .whitespaces)
        saved.symbol = symbol
        saved.lat = coordinate.latitude
        saved.lon = coordinate.longitude
        saved.radius = radius
        saved.shopHint = shopHint
        store.saveSpot(saved)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
