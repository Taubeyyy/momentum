import SwiftUI

/// Einkaufsmodus (Feedback #9/#10): Laden wählen, dann Karte für Karte in der Gang-Reihenfolge
/// dieses Ladens – rechts wischen = im Wagen, links = gibt's nicht. Oder klassisch als Liste.
/// Abgehakt wird sofort echt (bleibt also, wenn du zwischendurch schließt).
struct ShopModeView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var placeID: UUID?
    @State private var listMode = false
    @State private var skipped: [UUID] = []                 // „gibt's nicht“ – bleibt auf der Liste
    @State private var history: [UUID] = []                 // für „Zurück“ (Wagen oder übersprungen)
    @State private var tickOrder: [ShopCategory] = []       // Listen-Modus: in welcher Gang-Folge du abhakst
    @State private var editingPlace: ShopPlace?
    @State private var addingPlace = false
    @State private var newPlaceName = ""
    @State private var finishing = false

    private var place: ShopPlace? { store.data.shopPlaces.first { $0.id == placeID } ?? store.currentPlace }
    private var open: [ShopItem] { store.shopOpen(for: place) }
    private var deck: [ShopItem] { open.filter { !skipped.contains($0.id) } }
    private var cart: [ShopItem] { store.shopInCart }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                placeBar
                status.padding(.horizontal, 20).padding(.top, 14)
                if finishing || (!listMode && deck.isEmpty && !(open.isEmpty && cart.isEmpty)) {
                    ShopFinishView(place: place, skipped: skipped, tickOrder: tickOrder,
                                   canGoBack: listMode || !deck.isEmpty,
                                   onBack: { finishing = false },
                                   onDone: { dismiss() })
                } else if open.isEmpty && cart.isEmpty {
                    Spacer()
                    EmptyState(symbol: "", title: "Liste ist leer",
                               text: "Erst etwas auf die Liste setzen – dann geht's hier los.")
                        .padding(.horizontal, 20)
                    Spacer()
                } else if listMode {
                    list
                } else {
                    cards
                }
            }
            .background(DS.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $listMode) {
                        Text("Karten").tag(false)
                        Text("Liste").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { finishing = true }.disabled(finishing)
                }
            }
            .sheet(item: $editingPlace) { place in
                PlaceEditor(place: place).environmentObject(store)
            }
            .alert("Neuer Laden", isPresented: $addingPlace) {
                TextField("z. B. Penny am Bahnhof", text: $newPlaceName)
                Button("Anlegen") {
                    let name = newPlaceName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    let place = ShopPlace(name: name)
                    store.savePlace(place)
                    choose(place.id)
                    newPlaceName = ""
                }
                Button("Abbrechen", role: .cancel) { newPlaceName = "" }
            }
            .onAppear { placeID = store.currentPlace?.id }
        }
    }

    // MARK: Laden

    private var placeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.data.shopPlaces) { p in
                    let selected = p.id == place?.id
                    Button { choose(p.id) } label: {
                        Text(p.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selected ? .white : Color(hex: 0xB9B0BF))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(selected ? store.theme.accent : DS.field, in: Capsule())
                            .overlay(Capsule().stroke(selected ? .clear : DS.chipBorder))
                    }
                    .buttonStyle(PressStyle())
                }
                Button { addingPlace = true } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.purpleMuted)
                        .frame(width: 34, height: 34)
                        .background(DS.field, in: Capsule())
                }
                .buttonStyle(PressStyle())
                if let place {
                    Button { editingPlace = place } label: {
                        Label("Gänge", systemImage: "arrow.up.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.purpleMuted)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Color(hex: 0x2A1A34), in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 8)
    }

    private func choose(_ id: UUID) {
        UISelectionFeedbackGenerator().selectionChanged()
        placeID = id
        store.choosePlace(id)
    }

    // MARK: Fortschritt

    private var status: some View {
        let total = open.count + cart.count
        let cartPrice = store.shopTotal(cart).sum
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(cart.count) von \(total) im Wagen")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.ink)
                Spacer()
                if cartPrice > 0 {
                    Text("ca. \(MoneyMath.euro(cartPrice))")
                        .font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(DS.purpleMuted)
                }
            }
            Track(fraction: total == 0 ? 0 : Double(cart.count) / Double(total))
        }
    }

    // MARK: Karten

    private var cards: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            ZStack {
                if deck.count > 1 {
                    let second = deck[1]
                    CardFace(item: second, price: store.shopPrice(second), next: [])
                        .scaleEffect(0.94)
                        .offset(y: 14)
                        .opacity(0.6)
                        .allowsHitTesting(false)
                }
                if let top = deck.first {
                    SwipeCard(item: top, price: store.shopPrice(top), next: sameAisle(after: top),
                              onCart: { cartItem(top) }, onSkip: { skip(top) })
                        .id(top.id)
                        .transition(.asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity), removal: .identity))
                }
            }
            .padding(.horizontal, 20)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: deck.first?.id)

            Text("Rechts wischen = im Wagen · links = gibt's nicht")
                .font(.system(size: 12)).foregroundStyle(DS.faint)
                .padding(.top, 22)

            HStack(spacing: 22) {
                roundButton("xmark", label: "Gibt's nicht", color: Color(hex: 0xF5B94A)) { if let top = deck.first { skip(top) } }
                roundButton("arrow.uturn.backward", label: "Zurück", color: DS.muted, small: true) { undo() }
                    .disabled(history.isEmpty)
                    .opacity(history.isEmpty ? 0.35 : 1)
                roundButton("checkmark", label: "Im Wagen", color: store.theme.accent) { if let top = deck.first { cartItem(top) } }
            }
            .padding(.top, 14)
            .padding(.bottom, 26)
            Spacer(minLength: 0)
        }
    }

    /// Was im selben Gang gleich danach kommt – damit du alles auf einmal greifst.
    private func sameAisle(after item: ShopItem) -> [ShopItem] {
        Array(deck.dropFirst().prefix { $0.category == item.category }.prefix(3))
    }

    private func roundButton(_ symbol: String, label: String, color: Color, small: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: small ? 16 : 22, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: small ? 50 : 66, height: small ? 50 : 66)
                    .background(DS.raised, in: Circle())
                    .overlay(Circle().stroke(DS.line))
                Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.muted)
            }
        }
        .buttonStyle(PressStyle())
    }

    private func cartItem(_ item: ShopItem) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            store.toggleBought(item.id)
            history.append(item.id)
        }
    }

    private func skip(_ item: ShopItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            skipped.append(item.id)
            history.append(item.id)
        }
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if let i = skipped.lastIndex(of: last) {
                skipped.remove(at: i)
            } else if store.data.shopItems.first(where: { $0.id == last })?.boughtAt != nil {
                store.toggleBought(last)
            }
        }
    }

    // MARK: Liste

    private var list: some View {
        let order = place?.fullOrder ?? ShopCategory.allCases
        let items = open + cart
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(order) { category in
                    let inAisle = items.filter { $0.category == category }
                    if !inAisle.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(category.label.uppercased())
                                .font(.system(size: 10, weight: .heavy)).tracking(0.7).foregroundStyle(DS.faint)
                            HairlineList {
                                ForEach(inAisle) { item in
                                    ShopLine(item: item, done: item.boughtAt != nil, price: store.shopPrice(item)) {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        if item.boughtAt == nil { tickOrder.append(item.category) }
                                        withAnimation(.easeOut(duration: 0.15)) { store.toggleBought(item.id) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
    }
}

/// Die Karte selbst (auch als Vorschau dahinter).
private struct CardFace: View {
    let item: ShopItem
    let price: Double?
    let next: [ShopItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.category.label.uppercased())
                .font(.system(size: 11, weight: .heavy)).tracking(0.8).foregroundStyle(DS.purpleMuted)
            Text(item.name)
                .font(.system(size: 34, weight: .bold)).tracking(-1)
                .foregroundStyle(DS.ink)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
            if let price {
                Text("ca. \(MoneyMath.euro(price))")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.muted)
            }
            Spacer(minLength: 0)
            if !next.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GLEICH DANEBEN").font(.system(size: 10, weight: .heavy)).tracking(0.7).foregroundStyle(DS.faint)
                    Text(next.map(\.name).joined(separator: " · "))
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Color(hex: 0xC5BDCA)).lineLimit(2)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 320, maxHeight: 360, alignment: .topLeading)
        .background(DS.raised, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(DS.panelBorder))
    }
}

/// Wischbare Karte: Stempel zeigt, was beim Loslassen passiert.
private struct SwipeCard: View {
    let item: ShopItem
    let price: Double?
    let next: [ShopItem]
    let onCart: () -> Void
    let onSkip: () -> Void
    @State private var offset: CGSize = .zero
    @State private var crossed = false

    private let threshold: CGFloat = 110

    var body: some View {
        let x = offset.width
        CardFace(item: item, price: price, next: next)
            .overlay {
                ZStack {
                    stamp("IM WAGEN", color: Color(hex: 0x4ADE80))
                        .rotationEffect(.degrees(-12))
                        .opacity(x > 0 ? Double(min(1, x / threshold)) : 0)
                    stamp("GIBT'S NICHT", color: Color(hex: 0xF5B94A))
                        .rotationEffect(.degrees(12))
                        .opacity(x < 0 ? Double(min(1, -x / threshold)) : 0)
                }
            }
            .offset(x: x, y: offset.height * 0.2)
            .rotationEffect(.degrees(Double(x) / 22))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = value.translation
                        let over = abs(value.translation.width) > threshold
                        if over != crossed {
                            crossed = over
                            if over { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                        }
                    }
                    .onEnded { value in
                        let w = value.translation.width
                        let flung = value.predictedEndTranslation.width
                        if w > threshold || flung > 300 {
                            fly(1)
                        } else if w < -threshold || flung < -300 {
                            fly(-1)
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { offset = .zero }
                        }
                    })
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: "Im Wagen", onCart)
            .accessibilityAction(named: "Gibt's nicht", onSkip)
    }

    private func fly(_ direction: CGFloat) {
        withAnimation(.easeIn(duration: 0.18)) { offset = CGSize(width: direction * 650, height: offset.height) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            if direction > 0 { onCart() } else { onSkip() }
        }
    }

    private func stamp(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 24, weight: .heavy)).tracking(1)
            .foregroundStyle(color)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 3))
    }
}

/// Abschluss: was fehlt noch, was hast du bezahlt, Gang-Reihenfolge merken.
struct ShopFinishView: View {
    let place: ShopPlace?
    let skipped: [UUID]
    let tickOrder: [ShopCategory]
    var canGoBack = true
    let onBack: () -> Void
    let onDone: () -> Void
    @EnvironmentObject private var store: Store
    @State private var paid = ""
    @State private var learn = true
    @FocusState private var paidFocused: Bool

    private var cart: [ShopItem] { store.shopInCart }
    private var missing: [ShopItem] { store.shopOpen.filter { skipped.contains($0.id) } }
    private var stillOpen: [ShopItem] { store.shopOpen.filter { !skipped.contains($0.id) } }
    private var estimate: Double { store.shopTotal(cart).sum }

    private var learned: [ShopCategory]? {
        guard let place, !tickOrder.isEmpty else { return nil }
        let order = ShopText.learnOrder(current: place.fullOrder, seen: tickOrder)
        return order == place.fullOrder ? nil : order
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(stillOpen.isEmpty ? "Alles durch" : "Fertig?")
                    .font(.system(size: 30, weight: .bold)).tracking(-1).foregroundStyle(DS.ink)
                Text("\(cart.count) \(cart.count == 1 ? "Sache" : "Sachen") im Wagen")
                    .font(.system(size: 14)).foregroundStyle(DS.muted).padding(.top, 4)

                if !missing.isEmpty {
                    info("NICHT BEKOMMEN – BLEIBT AUF DER LISTE", missing.map(\.name).joined(separator: ", "))
                }
                if !stillOpen.isEmpty {
                    info("NOCH OFFEN", stillOpen.map(\.name).joined(separator: ", "))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("WAS HAST DU BEZAHLT?").font(.system(size: 10, weight: .heavy)).tracking(0.7).foregroundStyle(DS.purpleMuted)
                    HStack {
                        TextField(estimate > 0 ? "ca. \(MoneyMath.euro(estimate))" : "Betrag", text: $paid)
                            .keyboardType(.decimalPad)
                            .focused($paidFocused)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(DS.ink)
                        Text("€").foregroundStyle(DS.muted)
                    }
                    .padding(14)
                    .background(DS.field, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(DS.fieldBorder))
                    Text("Landet im Geld-Tagebuch unter Einkauf. Leer lassen geht auch.")
                        .font(.system(size: 12)).foregroundStyle(DS.muted)
                }
                .padding(.top, 24)

                if let place, learned != nil {
                    Toggle(isOn: $learn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Gang-Reihenfolge für \(place.name) merken").font(.system(size: 15, weight: .semibold))
                            Text("So wie du heute abgehakt hast.").font(.system(size: 12)).foregroundStyle(DS.muted)
                        }
                    }
                    .tint(store.theme.accent)
                    .padding(.top, 20)
                }

                Button("Einkauf abschließen") {
                    paidFocused = false
                    store.finishShopping(place: place, paid: MoneyMath.parse(paid), learnedOrder: learn ? learned : nil)
                    onDone()
                }
                .buttonStyle(SolidButtonStyle())
                .padding(.top, 26)

                if canGoBack {
                    Button("Weiter einkaufen", action: onBack)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.purpleMuted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .buttonStyle(PressStyle())
                        .padding(.top, 6)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func info(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10, weight: .heavy)).tracking(0.7).foregroundStyle(DS.faint)
            Text(text).font(.system(size: 14)).foregroundStyle(DS.ink)
        }
        .padding(.top, 18)
    }
}

/// Laden bearbeiten: Name und Gang-Reihenfolge (ziehen).
struct PlaceEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var place: ShopPlace
    @State private var order: [ShopCategory] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Name", text: $place.name)
                }
                .dopaRow()

                Section {
                    ForEach(order) { category in
                        HStack(spacing: 12) {
                            Text("\((order.firstIndex(of: category) ?? 0) + 1)")
                                .font(.system(size: 12, weight: .bold)).monospacedDigit()
                                .foregroundStyle(DS.purpleMuted).frame(width: 20)
                            Text(category.label)
                        }
                    }
                    .onMove { order.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("Gänge in Lauf-Reihenfolge")
                } footer: {
                    Text("Zieh die Gänge so, wie du durch \(place.name.isEmpty ? "den Laden" : place.name) läufst. Im Listen-Modus lernt Dopa das auch vom Abhaken.")
                }
                .dopaRow()

                if store.data.shopPlaces.count > 1 {
                    Section {
                        Button("Laden löschen", role: .destructive) {
                            store.deletePlace(place.id)
                            dismiss()
                        }
                    }
                    .dopaRow()
                }
            }
            .environment(\.editMode, .constant(.active))
            .dopaBackground()
            .navigationTitle(place.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        place.name = place.name.trimmingCharacters(in: .whitespaces)
                        if place.name.isEmpty { place.name = "Laden" }
                        place.order = order
                        store.savePlace(place)
                        dismiss()
                    }
                }
            }
            .onAppear { order = place.fullOrder }
        }
    }
}
