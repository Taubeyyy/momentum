import SwiftUI

/// „Einkauf“: oben umschaltbar – Liste (nach Gängen, lernt deinen Rhythmus) oder Geld
/// (Spaß-Budget, Tagebuch, Kauf-Parkplatz, Raten).
struct ShopView: View {
    /// Seit Build 57 zwei getrennte Seiten: Einkauf (`.list`, eigener Tab) und Geld (`.money`, unter „Mehr“).
    var mode: ShopSection = .list
    @EnvironmentObject private var store: Store
    @State private var input = ""
    @State private var showBudget = false
    @State private var showPark = false
    @State private var shopping = false
    @State private var editingPlace: ShopPlace?
    @State private var choosingPhoto = false
    @State private var photo: PickedImage?
    @State private var addingPlace = false
    @State private var newPlaceName = ""
    @State private var finishing = false
    @State private var pricing: ShopItem?
    @State private var priceText = ""
    @State private var choosingFlyer = false      // Prospekt-Foto einlesen
    @State private var readingFlyer = false
    @State private var offerQuery = ""
    @State private var scanningBarcode = false
    @ObservedObject private var router = Router.shared
    @ObservedObject private var server = Server.shared
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            DopaScreen(eyebrow: mode == .list ? "Was fehlt, sortiert nach Gängen" : "Budget, Tagebuch, Wünsche",
                       title: mode == .list ? "Einkauf" : "Geld", tab: mode == .list ? .shop : .more) {
                if mode == .list {
                    VStack(alignment: .leading, spacing: 0) { listSection }
                } else {
                    VStack(alignment: .leading, spacing: 0) { moneySection }
                }
            }
            .sheet(isPresented: $showBudget) { BudgetSheet().environmentObject(store) }
            .sheet(isPresented: $showPark) { ParkSheet().environmentObject(store) }
            .fullScreenCover(isPresented: $shopping) { ShopModeView().environmentObject(store) }
            .sheet(isPresented: $finishing) {
                NavigationStack {
                    ShopFinishView(place: store.currentPlace, skipped: [], tickOrder: [], canGoBack: false,
                                   onBack: {}, onDone: { finishing = false })
                        .background(DS.surface.ignoresSafeArea())
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { finishing = false } }
                        }
                }
                .environmentObject(store)
                .presentationDetents([.medium, .large])
            }
            .alert(pricing.map { "Preis für \($0.name)" } ?? "Preis", isPresented: Binding(
                get: { pricing != nil }, set: { if !$0 { pricing = nil } })) {
                TextField("z. B. 1,29", text: $priceText).keyboardType(.decimalPad)
                Button("Sichern") {
                    if let item = pricing { store.setShopPrice(item, MoneyMath.parse(priceText)) }
                    pricing = nil
                }
                Button("Abbrechen", role: .cancel) { pricing = nil }
            } message: {
                Text("Preis für die ganze Menge. Dopa merkt sich den Stückpreis und nimmt ihn nächstes Mal statt zu schätzen. Leer lassen = wieder schätzen.")
            }
        }
    }

    @ViewBuilder
    private var listSection: some View {
        HStack(spacing: 8) {
            CaptureField(placeholder: "Auf die Liste – „Milch Brot Eier“ geht auch",
                         text: $input, focus: $focused, onSubmit: addInput)
            if server.isConnected && server.aiAvailable {
                Button { choosingPhoto = true } label: {
                    Image(systemName: "camera")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DS.purpleMuted)
                        .frame(width: 56, height: 56)
                        .background(DS.field, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(DS.fieldBorder))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Foto vom Zettel oder Kühlschrank")
            }
            if server.isConnected {
                Button { scanningBarcode = true } label: {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DS.purpleMuted)
                        .frame(width: 56, height: 56)
                        .background(DS.field, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(DS.fieldBorder))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Barcode scannen")
            }
        }
        .sheet(isPresented: $scanningBarcode) {
            BarcodeSheet { code in
                scanningBarcode = false
                lookup(code)
            }
        }
        .photoSource(isPresented: $choosingPhoto, title: "Zettel oder Kühlschrank") { photo = PickedImage(image: $0) }
        .sheet(item: $photo) { picked in
            PhotoDumpSheet(image: picked.image, hint: "Einkaufsliste").environmentObject(store)
        }

        if !store.shopOpen.isEmpty {
            Button { shopping = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "cart")
                    Text("Einkaufen gehen")
                    Text("· \(store.shopOpen.count)").opacity(0.75)
                }
            }
            .buttonStyle(SolidButtonStyle())
            .padding(.top, 12)
        }

        // Erst die Liste, dann der Wagen – Angebote und Vorschläge ruhig darunter
        list
        cart
        offersSection
        suggestions
    }

    /// Preis-Eingabe öffnen (vorausgefüllt mit dem aktuellen Preis).
    private func editPrice(_ item: ShopItem) {
        priceText = store.shopPrice(item).map { String(format: "%.2f", $0).replacingOccurrences(of: ".", with: ",") } ?? ""
        pricing = item
    }

    /// Passendes Angebot aus einem gültigen Prospekt für einen Listen-Eintrag.
    private func dealText(for item: ShopItem) -> String? {
        let now = Date()
        return Offers.best(for: item.name, in: store.activeFlyers, now: now).map { Offers.dealText($0, now: now) }
    }

    // MARK: Prospekte

    @ViewBuilder
    private var offersSection: some View {
        let flyers = store.activeFlyers
        let count = flyers.reduce(0) { $0 + $1.offers.count }
        SectionHeading(title: "Angebote",
                       subtitle: flyers.isEmpty ? "Aus deinen Prospekten" : "\(count) Angebote aus \(flyers.count) Prospekt\(flyers.count == 1 ? "" : "en")") {
            if server.isConnected && server.aiAvailable {
                MiniAddButton { choosingFlyer = true }
                    .accessibilityLabel("Prospekt einlesen")
            }
        }
        .photoSource(isPresented: $choosingFlyer, title: "Prospekt (Foto oder Screenshot)") { scanFlyer($0) }

        if readingFlyer {
            HStack(spacing: 8) {
                ProgressView()
                Text("\(store.dotName) liest den Prospekt …").font(.system(size: 13)).foregroundStyle(DS.muted)
            }
            .padding(.bottom, 10)
        }

        if flyers.isEmpty {
            EmptyState(symbol: "", title: "Noch kein Prospekt",
                       text: "Plus oben: Prospekt fotografieren oder Screenshot aus der kaufDA-App. Dopa liest Angebote, Preise und bis wann sie gelten – und zeigt sie bei deiner Liste.")
        } else {
            SearchField(text: $offerQuery, prompt: "Im Prospekt suchen, z. B. Butter")
                .padding(.bottom, 8)
            let query = offerQuery.trimmingCharacters(in: .whitespaces)
            if query.isEmpty {
                HairlineList {
                    ForEach(flyers) { flyer in
                        HStack(spacing: 12) {
                            Image(systemName: "newspaper.fill").foregroundStyle(DS.purpleMuted)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(flyer.storeName).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink)
                                let valid = Offers.validText(flyer, now: Date())
                                Text("\(flyer.offers.count) Angebote" + (valid.isEmpty ? "" : " · \(valid)"))
                                    .font(.system(size: 12)).foregroundStyle(DS.muted)
                            }
                            Spacer(minLength: 0)
                        }
                        .hairlineRow(minHeight: 56)
                        .contextMenu {
                            Button(role: .destructive) { store.deleteFlyer(flyer.id) } label: {
                                Label("Prospekt löschen", systemImage: "trash")
                            }
                        }
                    }
                }
            } else {
                let hits = Offers.search(query, in: flyers, now: Date())
                if hits.isEmpty {
                    Text("Nichts gefunden – anders schreiben oder weniger Wörter.").font(.system(size: 13)).foregroundStyle(DS.muted)
                } else {
                    HairlineList {
                        ForEach(Array(hits.prefix(30).enumerated()), id: \.offset) { _, hit in
                            offerRow(hit)
                        }
                    }
                }
            }
        }
    }

    private func offerRow(_ hit: (offer: Offer, flyer: Flyer)) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(hit.offer.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink).lineLimit(2)
                let extra: String = [hit.offer.unit, hit.offer.note].filter { !$0.isEmpty }.joined(separator: " · ")
                let valid = Offers.validText(hit.flyer, now: Date())
                Text(hit.flyer.storeName + (extra.isEmpty ? "" : " · \(extra)") + (valid.isEmpty ? "" : " · \(valid)"))
                    .font(.system(size: 12)).foregroundStyle(DS.muted).lineLimit(2)
            }
            Spacer(minLength: 0)
            if hit.offer.price > 0 {
                Text(MoneyMath.euro(hit.offer.price))
                    .font(.system(size: 15, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Color(hex: 0x4ADE80))
            }
            MiniAddButton {
                store.addShopItem(hit.offer.name)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Toaster.shared.show("\(hit.offer.name) steht auf der Liste")
            }
            .accessibilityLabel("Auf die Einkaufsliste")
        }
        .padding(.vertical, 8)
        .hairlineRow(minHeight: 60)
    }

    private func scanFlyer(_ image: UIImage) {
        guard let encoded = MediaUpload.jpegBase64(image, maxSide: 2000, quality: 0.75) else { return }
        readingFlyer = true
        Task {
            do {
                let scan = try await server.flyer(encoded)
                if scan.offers.isEmpty {
                    Toaster.shared.show("Keine Angebote erkannt – schärferes Foto?")
                } else {
                    let flyer = store.addFlyer(scan)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    Toaster.shared.show("\(flyer.storeName): \(flyer.offers.count) Angebote")
                }
            } catch {
                Toaster.shared.show("Prospekt ließ sich gerade nicht lesen")
            }
            readingFlyer = false
        }
    }

    /// Barcode → Produkt (Open Food Facts) → auf die Liste. Unbekannt: Eingabefeld zum Tippen.
    private func lookup(_ code: String) {
        Task {
            let product = try? await server.product(barcode: code)
            if let product, product.found, let name = product.name, !name.isEmpty {
                store.addShopItem(name)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                Toaster.shared.show("\(name) steht auf der Liste")
            } else {
                Toaster.shared.show("Produkt nicht gefunden – kurz eintippen")
                focused = true
            }
        }
    }

    @ViewBuilder
    private var moneySection: some View {
        MoneyContent(onBudget: { showBudget = true })
        parking.padding(.top, 14)
    }

    private func addInput() {
        store.addShop(input)
        input = ""
    }

    // MARK: Vorschläge

    @ViewBuilder
    private var suggestions: some View {
        let due = store.shopDue
        if !due.isEmpty {
            SectionHeading(title: "Bald fällig", subtitle: "Nach deinem eigenen Kauf-Rhythmus")
            HairlineList {
                ForEach(due) { s in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink)
                            Text(s.reason).font(.system(size: 12)).foregroundStyle(DS.muted)
                        }
                        Spacer(minLength: 0)
                        MiniAddButton { store.addShop(s.name) }
                    }
                    .padding(.vertical, 8)
                    .hairlineRow(minHeight: 56)
                }
            }
        }

        let chips = store.shopFrequent + store.snackHints
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { name in
                        Button { store.addShop(name) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                                Text(name).font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(Color(hex: 0xB9B0BF))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(DS.field, in: Capsule())
                            .overlay(Capsule().stroke(DS.chipBorder))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 14)
        }
    }

    // MARK: Liste nach Gängen

    @ViewBuilder
    private var list: some View {
        let open = store.shopOpen
        let total = store.shopTotal(open)
        SectionHeading(title: "Einkaufsliste",
                       subtitle: total.sum > 0 ? "\(open.count) offen · ca. \(MoneyMath.euro(total.sum))" : "\(open.count) offen") {
            placeMenu
        }
        if open.isEmpty {
            EmptyState(symbol: "", title: store.shopInCart.isEmpty ? "Liste ist leer" : "Alles im Wagen",
                       text: store.shopInCart.isEmpty
                           ? "Oben reinschreiben. Was du regelmäßig kaufst, schlägt Dopa bald selbst vor."
                           : "Unten auf „Einkauf fertig“, wenn du bezahlt hast.")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(store.currentPlace?.fullOrder ?? ShopCategory.allCases) { category in
                    let items = open.filter { $0.category == category }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(category.label.uppercased())
                                .font(.system(size: 10, weight: .heavy)).tracking(0.7)
                                .foregroundStyle(DS.faint)
                            HairlineList {
                                ForEach(items) { item in
                                    ShopLine(item: item, done: checking.contains(item.id), price: store.shopPrice(item),
                                             own: store.isOwnPrice(item), deal: dealText(for: item),
                                             onPrice: { editPrice(item) }) { toggle(item) }
                                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                                removal: .opacity))
                                        .contextMenu {
                                            Button { editPrice(item) } label: { Label("Preis eintragen", systemImage: "eurosign") }
                                            Menu("In anderen Gang") {
                                                ForEach(ShopCategory.allCases.filter { $0 != item.category }) { other in
                                                    Button(other.label) { store.setCategory(item.id, other) }
                                                }
                                            }
                                            Button(role: .destructive) { store.removeShop(item.id) } label: {
                                                Label("Löschen", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
                .animation(Motion.list, value: open.map(\.id))
                if server.isConnected && server.aiAvailable {
                    Button(store.data.shopPricesOn ? "Preise sind grobe Schätzungen · ausblenden" : "Preise schätzen lassen") {
                        store.setShopPricesOn(!store.data.shopPricesOn)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(DS.faint)
                    .buttonStyle(PressStyle())
                }
            }
        }
    }

    /// Laden wechseln (sortiert die Liste nach dessen Gängen), Gänge sortieren, neuer Laden.
    private var placeMenu: some View {
        Menu {
            ForEach(store.data.shopPlaces) { place in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { store.choosePlace(place.id) }
                } label: {
                    if place.id == store.currentPlace?.id {
                        Label(place.name, systemImage: "checkmark")
                    } else {
                        Text(place.name)
                    }
                }
            }
            Divider()
            if let place = store.currentPlace {
                Button { editingPlace = place } label: { Label("Gänge für \(place.name) sortieren", systemImage: "arrow.up.arrow.down") }
            }
            Button { addingPlace = true } label: { Label("Neuer Laden", systemImage: "plus") }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "storefront").font(.system(size: 12, weight: .semibold))
                Text(store.currentPlace?.name ?? "Laden").font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(DS.purpleMuted)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color(hex: 0x2A1A34), in: Capsule())
        }
        .sheet(item: $editingPlace) { place in
            PlaceEditor(place: place).environmentObject(store)
        }
        .alert("Neuer Laden", isPresented: $addingPlace) {
            TextField("z. B. Penny am Bahnhof", text: $newPlaceName)
            Button("Anlegen") {
                let name = newPlaceName.trimmingCharacters(in: .whitespaces)
                newPlaceName = ""
                guard !name.isEmpty else { return }
                let place = ShopPlace(name: name)
                store.savePlace(place)
                store.choosePlace(place.id)
            }
            Button("Abbrechen", role: .cancel) { newPlaceName = "" }
        }
    }

    @ViewBuilder
    private var cart: some View {
        let cart = store.shopInCart
        if !cart.isEmpty {
            SectionHeading(title: "Im Wagen") { HeadingCount(text: "\(cart.count)") }
            HairlineList {
                ForEach(cart) { item in
                    ShopLine(item: item, done: true, price: store.shopPrice(item)) { toggle(item) }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(Motion.list, value: cart.map(\.id))
            Button("Einkauf abschließen") { finishing = true }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.purpleMuted)
                .padding(.top, 12)
                .buttonStyle(.plain)
        }
    }

    @State private var checking: Set<UUID> = []     // gerade abgehakt, rutscht gleich in den Wagen

    /// Häkchen sofort zeigen, erst kurz danach in den Wagen gleiten – wie bei Aufgaben.
    private func toggle(_ item: ShopItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard item.boughtAt == nil else {
            withAnimation(Motion.list) { store.toggleBought(item.id) }
            return
        }
        guard !checking.contains(item.id) else { return }
        checking.insert(item.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(Motion.list) { store.toggleBought(item.id) }
            checking.remove(item.id)
        }
    }

    // MARK: Kauf-Parkplatz

    @ViewBuilder
    private var parking: some View {
        let open = store.data.parked.filter { $0.decision == nil }
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        let recent = store.data.parked.filter { $0.decision != nil && ($0.decidedAt ?? .distantPast) > weekAgo }

        Card(title: "Kauf-Parkplatz", symbol: "parkingsign.circle.fill") {
            MiniAddButton { showPark = true }
        } content: {
            if open.isEmpty && recent.isEmpty {
                Text("Spontan was gesehen? Hier parken – nach 48 Stunden fragt Dopa, ob du es noch willst.")
                    .font(.system(size: 13)).foregroundStyle(DS.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(open) { wish in
                        WishLine(wish: wish)
                            .contextMenu {
                                Button(role: .destructive) { store.removeWish(wish.id) } label: { Label("Löschen", systemImage: "trash") }
                            }
                    }
                    ForEach(recent) { wish in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(wish.name).font(.system(size: 15, weight: .semibold)).strikethrough(wish.decision == .drop)
                                Text(wish.decision == .drop ? "Nicht gekauft" : "Freigegeben")
                                    .font(.system(size: 12)).foregroundStyle(DS.muted)
                            }
                            Spacer()
                            if let price = wish.price {
                                Text(price.formatted(.currency(code: "EUR"))).font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color(hex: 0xC7BECB))
                            }
                        }
                        .foregroundStyle(DS.ink)
                        .opacity(0.55)
                        .frame(minHeight: 54)
                    }
                }
            }
            if !store.droppedWishes.isEmpty {
                Text(savedText).font(.system(size: 12)).foregroundStyle(DS.muted)
            }
        }
    }

    private var savedText: String {
        let n = store.droppedWishes.count
        var text = "Nicht gekauft: \(n) \(n == 1 ? "Sache" : "Sachen")"
        if store.savedMoney > 0 { text += " · \(store.savedMoney.formatted(.currency(code: "EUR"))) gespart" }
        return text
    }
}

struct ShopLine: View {
    let item: ShopItem
    let done: Bool
    var price: Double?
    var own = false                 // selbst eingetragener Preis (ohne „~“)
    var deal: String?               // „Lidl 0,99 € · bis Sa“ – passendes Angebot aus einem Prospekt
    var onPrice: (() -> Void)?      // Preis antippen = selbst eintragen
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                HStack(spacing: 13) {
                    CheckBox(done: done)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.system(size: 15, weight: .semibold))
                            .strikethrough(done)
                            .foregroundStyle(DS.ink)
                            .animation(.easeOut(duration: 0.2), value: done)
                        if let deal, !done {
                            Label(deal, systemImage: "tag.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x4ADE80))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            priceView
        }
        .hairlineRow(minHeight: 54)
        .opacity(done ? 0.48 : 1)
    }

    /// Eigener Preis normal, Schätzung mit „~“; ohne Preis ein leises „€“ zum Eintragen.
    @ViewBuilder
    private var priceView: some View {
        let label: Text = price.map { own ? Text(MoneyMath.euro($0)) : Text("~\(MoneyMath.euro($0))") } ?? Text("€ +")
        let styled = label
            .font(.system(size: own ? 13 : 12, weight: own ? .semibold : .regular)).monospacedDigit()
            .foregroundStyle(own ? Color(hex: 0xC7BECB) : DS.faint)
        if let onPrice, !done {
            Button(action: onPrice) {
                styled
                    .padding(.vertical, 8).padding(.leading, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(price == nil ? "Preis eintragen" : "Preis ändern")
        } else if price != nil {
            styled
        }
    }
}

/// Geparkter Wunsch: Countdown, danach „Will ich noch“ / „Doch nicht“.
struct WishLine: View {
    @EnvironmentObject private var store: Store
    let wish: ParkedWish

    var body: some View {
        let waiting = wish.decideAfter > .now
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(wish.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink)
                    Text(waiting ? "Noch \(Int(ceil(wish.decideAfter.timeIntervalSinceNow / 3600))) Std." : "Bereit zum Prüfen")
                        .font(.system(size: 12))
                        .foregroundStyle(waiting ? DS.muted : DS.purpleMuted)
                }
                Spacer()
                Text(wish.price.map { $0.formatted(.currency(code: "EUR")) } ?? "–")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xC7BECB))
            }
            if !waiting, let price = wish.price, store.budgetMonthly > 0 {
                let left = store.budgetLeft
                Text(price <= left
                     ? "Passt ins Spaß-Budget – danach noch \(MoneyMath.euro(left - price)) frei."
                     : "Wären \(MoneyMath.euro(price - left)) mehr, als gerade freigespielt ist.")
                    .font(.system(size: 12))
                    .foregroundStyle(price <= left ? DS.muted : Color(hex: 0xF5B94A))
            }
            if !waiting {
                HStack(spacing: 8) {
                    Button("Will ich noch") { store.decide(wish.id, .keep) }
                        .buttonStyle(SolidButtonStyle())
                    Button("Doch nicht") { store.decide(wish.id, .drop) }
                        .buttonStyle(SoftButtonStyle())
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    }
}

// MARK: - Spaß-Budget

struct BudgetCard: View {
    let action: () -> Void
    @ObservedObject private var store = Store.shared

    private var monthName: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "LLLL"
        return f.string(from: Date())
    }

    var body: some View {
        Button(action: action) {
            Panel {
                if store.budgetMonthly <= 0 {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Spaß-Budget").font(.system(size: 16, weight: .semibold)).foregroundStyle(DS.ink)
                            Text(store.budgetSqueezed ? "Nach Fixkosten und Raten bleibt diesen Monat nichts übrig"
                                 : "Punkte schalten Geld für Spontankäufe frei")
                                .font(.system(size: 12)).foregroundStyle(DS.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(DS.faint)
                    }
                    .padding(17)
                } else {
                    let unlocked = store.budgetUnlocked
                    let fraction = unlocked / store.budgetMonthly
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("Spaß-Budget · \(monthName)")
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: 0xAAA4AE))
                                HStack(alignment: .firstTextBaseline, spacing: 5) {
                                    Text(unlocked.formatted(.currency(code: "EUR")))
                                        .font(.system(size: 20, weight: .bold)).foregroundStyle(DS.ink)
                                    Text("von \(store.budgetMonthly.formatted(.currency(code: "EUR"))) freigespielt")
                                        .font(.system(size: 12)).foregroundStyle(Color(hex: 0xB3AAB8))
                                }
                            }
                            Spacer()
                            Text("\(Int((fraction * 100).rounded())) %")
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(DS.purpleMuted)
                        }
                        Track(fraction: fraction).padding(.top, 16).padding(.bottom, 9)
                        Text(store.budgetSpent > 0
                             ? "Noch \(store.budgetLeft.formatted(.currency(code: "EUR"))) frei · \(store.budgetSpent.formatted(.currency(code: "EUR"))) ausgegeben"
                             : "Noch \(store.budgetLeft.formatted(.currency(code: "EUR"))) für Dinge, die einfach Freude machen.")
                            .font(.system(size: 12)).foregroundStyle(DS.muted)
                    }
                    .padding(17)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Budget einstellen und Ausgaben eintragen.
struct BudgetSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var monthly = ""
    @State private var targetXP = 1500
    @State private var linked = false
    @State private var share = 0.3
    @State private var spendTitle = ""
    @State private var spendAmount = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("An Geld-Überblick koppeln", isOn: $linked)
                        .disabled(store.moneyMonth.income <= 0 && !linked)
                    if linked {
                        VStack(alignment: .leading, spacing: 6) {
                            Slider(value: $share, in: 0.1...0.5, step: 0.05)
                            Text("\(Int((share * 100).rounded())) % vom Freien = \(MoneyMath.euro(MoneyMath.linkedBudget(free: store.moneyMonth.free, share: share))) im Monat")
                                .font(.footnote).foregroundStyle(DS.muted)
                        }
                    } else {
                        HStack {
                            Text("Pro Monat")
                            Spacer()
                            TextField("30", text: $monthly)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("€").foregroundStyle(DS.muted)
                        }
                    }
                    Stepper("Ganz frei ab \(targetXP) XP", value: $targetXP, in: 300...6000, step: 100)
                } header: {
                    Text("Einstellung")
                } footer: {
                    Text(budgetFooter)
                }
                .dopaRow()

                Section {
                    TextField("Wofür?", text: $spendTitle)
                    HStack {
                        TextField("Betrag", text: $spendAmount).keyboardType(.decimalPad)
                        Button("Eintragen") {
                            store.addSpend(spendTitle, amount: Self.parse(spendAmount))
                            spendTitle = ""
                            spendAmount = ""
                        }
                        .disabled(Self.parse(spendAmount) <= 0)
                    }
                    ForEach(store.spendsThisMonth) { spend in
                        HStack {
                            Text(spend.title)
                            Spacer()
                            Text(spend.amount.formatted(.currency(code: "EUR"))).foregroundStyle(DS.muted)
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { store.spendsThisMonth[$0].id }
                        for id in ids { store.deleteSpend(id) }
                    }
                } header: {
                    Text("Ausgaben diesen Monat")
                } footer: {
                    Text("„Will ich noch“ im Kauf-Parkplatz trägt den Preis automatisch ein.")
                }
                .dopaRow()
            }
            .dopaBackground()
            .navigationTitle("Spaß-Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { save(); dismiss() }
                }
            }
            .onAppear {
                let b = store.data.budget
                monthly = b.monthly > 0 ? String(format: "%g", b.monthly) : "0"
                targetXP = b.targetXP
                linked = b.linked
                share = b.share
            }
        }
    }

    private func save() {
        var settings = store.data.budget
        settings.monthly = max(0, Self.parse(monthly))
        settings.targetXP = targetXP
        settings.linked = linked
        settings.share = share
        store.updateBudget(settings)
    }

    private var budgetFooter: String {
        let xp = "Diesen Monat hast du \(store.monthXP) XP. Jedes XP schaltet einen Teil des Budgets frei."
        if store.moneyMonth.income <= 0 && !linked {
            return xp + " Koppeln geht, sobald im Geld-Überblick steht, was reinkommt."
        }
        if linked {
            return xp + " Gerechnet wird mit dem, was nach Fixkosten und Raten übrig ist (\(MoneyMath.euro(store.moneyMonth.free)))."
        }
        return xp + " 0 € schaltet das Budget aus."
    }

    static func parse(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) ?? 0
    }
}

/// Wunsch parken.
struct ParkSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var price = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Was willst du haben?", text: $name)
                    TextField("Preis in € (optional)", text: $price).keyboardType(.decimalPad)
                } footer: {
                    Text("In 48 Stunden fragt Dopa nach. Willst du es dann noch, kauf es – ohne schlechtes Gewissen.")
                }
                .dopaRow()
            }
            .dopaBackground()
            .navigationTitle("Parken")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Parken") {
                        let p = BudgetSheet.parse(price)
                        store.park(name, price: p > 0 ? p : nil)
                        Toaster.shared.show("Geparkt – in 48 Std. fragt Dopa nach")
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
