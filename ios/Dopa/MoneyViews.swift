import SwiftUI

/// Geld (Feedback #28): klar getrennte Karten statt einer langen Seite –
/// Diesen Monat · Spaß-Budget · Tagebuch (mit Screenshot) · Offene Zahlungen · Jeden Monat · Tipps.
struct MoneyContent: View {
    var onBudget: (() -> Void)?
    @EnvironmentObject private var store: Store
    @ObservedObject private var server = Server.shared
    @State private var editing: MoneyItem?
    @State private var entry = ""
    @State private var entryHint: String?
    @State private var choosingScan = false
    @State private var scanImage: PickedImage?
    @State private var tips: [String] = []
    @State private var loadingTips = false
    @FocusState private var entryFocused: Bool

    private var monthName: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "LLLL"
        return f.string(from: Date())
    }

    private var aiReady: Bool { server.isConnected && server.aiAvailable }

    var body: some View {
        VStack(spacing: 14) {
            monthCard
            if let onBudget { BudgetCard(action: onBudget) }
            ledgerCard
            debtsCard
            monthlyCard
            if aiReady { tipsCard }
        }
        .padding(.top, 2)
        .sheet(item: $editing) { item in
            MoneyEditor(item: item).environmentObject(store)
        }
        .sheet(item: $scanImage) { picked in
            ScanSheet(image: picked.image).environmentObject(store)
        }
        .photoSource(isPresented: $choosingScan, title: "Screenshot") { scanImage = PickedImage(image: $0) }
    }

    // MARK: Diesen Monat

    private var monthCard: some View {
        let month = store.moneyMonth
        return Card(title: "Diesen \(monthName)", symbol: "chart.bar.fill") {
            VStack(alignment: .leading, spacing: 0) {
                // Kontostand vom letzten Banking-Screenshot (Sparkasse: die große Zahl oben)
                if let bank = store.data.bank {
                    HStack(spacing: 6) {
                        Image(systemName: "building.columns.fill").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.purpleMuted)
                        Text("Konto \(MoneyMath.euro(bank.amount))")
                            .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(bank.amount < 0 ? Color(hex: 0xF5B94A) : DS.ink)
                        Text("· Stand \(DayLabel.text(for: bank.at))")
                            .font(.system(size: 12)).foregroundStyle(DS.muted)
                    }
                    .padding(.bottom, 10)
                }
                Text(month.income > 0 ? "noch frei" : "ausgegeben")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.muted)
                RollingText(text: MoneyMath.euro(month.income > 0 ? month.left : month.spent))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(month.income > 0 && month.left < 0 ? Color(hex: 0xF5B94A) : DS.ink)
                if month.income > 0 {
                    Track(fraction: month.free > 0 ? min(1, month.spent / month.free) : 1).padding(.top, 10)
                    HStack(spacing: 0) {
                        figure("Rein", month.income + month.extra)
                        figure("Fest", -month.fixed)
                        figure("Raten", -month.debts)
                        figure("Ausgaben", -month.spent)
                    }
                    .padding(.top, 12)
                    if month.left < 0 {
                        Text("Mehr raus als rein. Kein Drama – diesen Monat lieber nichts Neues parken.")
                            .font(.system(size: 12)).foregroundStyle(DS.muted).padding(.top, 8)
                    }
                } else {
                    Text("Unten bei „Jeden Monat“ eintragen, was reinkommt – dann rechnet Dopa aus, was frei ist.")
                        .font(.system(size: 13)).foregroundStyle(DS.muted).padding(.top, 6)
                }
            }
        }
    }

    private func figure(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(DS.faint)
            RollingText(text: MoneyMath.euro(value)).font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.ink)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Tagebuch

    private var ledgerCard: some View {
        let entries = store.entriesThisMonth
        return Card(title: "Tagebuch · heute \(MoneyMath.euro(store.spentToday))", symbol: "book.fill") {
            if aiReady {
                Button { choosingScan = true } label: {
                    Label("Screenshot", systemImage: "camera.viewfinder")
                }
                .buttonStyle(PillButtonStyle())
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                CaptureField(placeholder: "z. B. 4,50 Döner · +20 Oma", text: $entry, focus: $entryFocused, onSubmit: addEntry)
                if let entryHint {
                    Text(entryHint).font(.system(size: 12)).foregroundStyle(Color(hex: 0xF5B94A))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                frequentChips
                WeekBars(values: MoneyMath.week(store.data.spends, weekStart: Self.monday()))
                kindChips
                if !entries.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(entries.prefix(5).enumerated()), id: \.element.id) { i, e in
                            if i > 0 { Divider().overlay(DS.line) }
                            EntryRow(entry: e)
                                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                        removal: .opacity))
                        }
                    }
                    .animation(Motion.list, value: entries.prefix(5).map(\.id))
                    if entries.count > 5 {
                        NavigationLink {
                            LedgerPage()
                        } label: {
                            HStack {
                                Text("Alle \(entries.count) Einträge diesen Monat")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.purpleMuted)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var frequentChips: some View {
        let frequent = store.frequentEntries
        if !frequent.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(frequent) { e in
                        Button { store.repeatEntry(e) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                                Text("\(e.title) \(MoneyMath.euro(e.amount))").font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(Color(hex: 0xB9B0BF))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(DS.field, in: Capsule())
                            .overlay(Capsule().stroke(DS.chipBorder))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var kindChips: some View {
        let kinds = MoneyMath.byKind(store.entriesThisMonth)
        if !kinds.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(kinds.indices, id: \.self) { i in
                        let k = kinds[i]
                        HStack(spacing: 5) {
                            Image(systemName: k.kind.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.purpleMuted)
                            Text("\(k.kind.label) \(MoneyMath.euro(k.amount))").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(hex: 0xC5BDCA))
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(DS.field, in: Capsule())
                    }
                }
            }
        }
    }

    /// Mehrere auf einmal („12 Bahn, 3 Kaffee“); Tastatur bleibt offen für den nächsten.
    private func addEntry() {
        let parts = MoneyMath.splitEntries(entry)
        guard !parts.isEmpty else {
            entryFocused = false
            return
        }
        let failed = parts.filter { !store.addEntry($0) }
        entry = failed.joined(separator: ", ")
        withAnimation(.easeOut(duration: 0.2)) {
            entryHint = failed.isEmpty ? nil : "Da fehlt ein Betrag – z. B. „4,50 Döner“."
        }
        if failed.isEmpty { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        DispatchQueue.main.async { entryFocused = true }
    }

    static func monday(_ now: Date = Date()) -> Date {
        Calendar(identifier: .iso8601).dateInterval(of: .weekOfYear, for: now)?.start
            ?? Calendar.current.startOfDay(for: now)
    }

    // MARK: Offene Zahlungen

    private var debtsCard: some View {
        let debts = store.debts
        return Card(title: "Offene Zahlungen", symbol: "creditcard.fill") {
            MiniAddButton { editing = newItem(.debt) }
        } content: {
            if debts.isEmpty {
                Text("Nichts offen. Klarna, Raten oder eine Rechnung? Plus oben – Dopa erinnert 2 Tage vorher und am Tag.")
                    .font(.system(size: 13)).foregroundStyle(DS.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(debts.enumerated()), id: \.element.id) { i, item in
                        if i > 0 { Divider().overlay(DS.line) }
                        DebtLine(item: item) { editing = item }
                            .transition(.asymmetric(insertion: .opacity,
                                                    removal: .move(edge: .trailing).combined(with: .opacity)))
                    }
                }
                .animation(Motion.list, value: debts.map(\.id))
                Text("Insgesamt noch offen: \(MoneyMath.euro(MoneyMath.openTotal(debts)))")
                    .font(.system(size: 12)).foregroundStyle(DS.muted)
            }
        }
    }

    // MARK: Jeden Monat

    private var monthlyCard: some View {
        let income = store.data.money.filter { $0.kind == .income }.sorted { $0.dayOfMonth < $1.dayOfMonth }
        let fixed = store.data.money.filter { $0.kind == .fixed }.sorted { $0.dayOfMonth < $1.dayOfMonth }
        return Card(title: "Jeden Monat", symbol: "repeat") {
            HStack(spacing: 6) {
                Button("+ Rein") { editing = newItem(.income) }.buttonStyle(PillButtonStyle())
                Button("+ Fest") { editing = newItem(.fixed) }.buttonStyle(PillButtonStyle())
            }
        } content: {
            if income.isEmpty && fixed.isEmpty {
                Text("Was jeden Monat reinkommt (z. B. FSJ-Geld) und fest abgeht (Handy, Abos).")
                    .font(.system(size: 13)).foregroundStyle(DS.muted)
            } else {
                VStack(spacing: 0) {
                    let all = income + fixed
                    ForEach(Array(all.enumerated()), id: \.element.id) { i, item in
                        if i > 0 { Divider().overlay(DS.line) }
                        monthlyRow(item)
                    }
                }
            }
        }
    }

    private func monthlyRow(_ item: MoneyItem) -> some View {
        let isIncome = item.kind == .income
        return HStack(spacing: 12) {
            Image(systemName: isIncome ? "arrow.down.left" : "arrow.up.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isIncome ? Color(hex: 0x4ADE80) : DS.purpleMuted)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink)
                Text("am \(item.dayOfMonth).\(item.remind ? " · Erinnerung" : "")")
                    .font(.system(size: 12)).foregroundStyle(DS.muted)
            }
            Spacer(minLength: 0)
            Text(MoneyMath.euro(isIncome ? item.amount : -item.amount))
                .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                .foregroundStyle(isIncome ? Color(hex: 0x4ADE80) : Color(hex: 0xC7BECB))
        }
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        .onTapGesture { editing = item }
        .contextMenu {
            Button(role: .destructive) { store.deleteMoney(item.id) } label: { Label("Löschen", systemImage: "trash") }
        }
    }

    // MARK: Tipps von Dot

    private var tipsCard: some View {
        Card(title: "Tipps von \(store.dotName)", symbol: "lightbulb.fill") {
            if !tips.isEmpty {
                Button("Neu") { loadTips() }.buttonStyle(PillButtonStyle())
            }
        } content: {
            if tips.isEmpty {
                Text("\(store.dotName) schaut auf deinen Monat und sagt, was am meisten bringt – ohne Moral.")
                    .font(.system(size: 13)).foregroundStyle(DS.muted)
                Button { loadTips() } label: {
                    HStack(spacing: 8) {
                        if loadingTips { ProgressView() }
                        Text("Tipps holen")
                    }
                }
                .buttonStyle(SoftButtonStyle())
                .disabled(loadingTips || store.entriesThisMonth.isEmpty)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(tips.enumerated()), id: \.element) { i, tip in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(store.theme.accent).frame(width: 6, height: 6)
                            Text(tip).font(.system(size: 14)).foregroundStyle(DS.ink).fixedSize(horizontal: false, vertical: true)
                        }
                        .enterAnimation(delay: Double(i) * 0.1)
                    }
                }
            }
        }
    }

    private func loadTips() {
        loadingTips = true
        Task {
            if let result = try? await server.moneyTips(store.moneySummaryForTips()) {
                withAnimation(.easeOut(duration: 0.25)) { tips = result }
            }
            loadingTips = false
        }
    }

    private func newItem(_ kind: MoneyItem.Kind) -> MoneyItem {
        MoneyItem(title: "", amount: 0, kind: kind,
                  dayOfMonth: Calendar.current.component(.day, from: Date()),
                  due: kind == .debt ? Calendar.current.date(byAdding: .day, value: 14, to: Date()) : nil,
                  remind: kind == .debt)
    }
}

/// Ein Eintrag im Tagebuch (gedrückt halten: Art ändern, löschen).
struct EntryRow: View {
    let entry: Spend
    @EnvironmentObject private var store: Store

    var body: some View {
        let e = entry
        HStack(spacing: 12) {
            Image(systemName: e.income ? "arrow.down.left" : e.kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(e.income ? Color(hex: 0x4ADE80) : DS.purpleMuted)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(e.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink)
                Text("\(DayLabel.text(for: e.date)) · \(e.income ? "Einnahme" : e.kind.label)")
                    .font(.system(size: 12)).foregroundStyle(DS.muted)
            }
            Spacer(minLength: 0)
            Text((e.income ? "+" : "−") + MoneyMath.euro(e.amount))
                .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                .foregroundStyle(e.income ? Color(hex: 0x4ADE80) : Color(hex: 0xC7BECB))
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .contextMenu {
            if !e.income {
                Menu("Art ändern") {
                    ForEach(SpendKind.allCases) { kind in
                        Button(kind.label) { store.setSpendKind(e.id, kind) }
                    }
                }
            }
            Button(role: .destructive) { store.deleteSpend(e.id) } label: { Label("Löschen", systemImage: "trash") }
        }
    }
}

/// Alle Einträge des Monats; wischen löscht.
struct LedgerPage: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        List {
            Section {
                ForEach(store.entriesThisMonth) { e in EntryRow(entry: e) }
                    .onDelete { offsets in
                        let ids = offsets.map { store.entriesThisMonth[$0].id }
                        for id in ids { store.deleteSpend(id) }
                    }
            } footer: {
                Text("Gedrückt halten ändert die Art. Nach links wischen löscht.")
            }
            .dopaRow()
        }
        .dopaBackground()
        .navigationTitle("Tagebuch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

/// Screenshot aus Bank/Klarna/PayPal → Buchungen und offene Raten zum Abhaken, plus Tipps.
struct ScanSheet: View {
    let image: UIImage
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var scan: Server.Scan?
    @State private var pickedEntries: Set<Int> = []
    @State private var pickedDebts: Set<Int> = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if scan == nil {
                        Text("Der Screenshot geht zum Auslesen an Google Gemini (kostenloser Zugang – Google darf dort mitlesen). Schneide Kontonummer und IBAN vorher weg, wenn sie drauf sind.")
                            .font(.system(size: 13)).foregroundStyle(DS.muted).fixedSize(horizontal: false, vertical: true)
                        Button(action: run) {
                            HStack(spacing: 8) {
                                if busy { ProgressView().tint(.white) }
                                Text(busy ? "\(store.dotName) liest …" : "Einlesen")
                            }
                        }
                        .buttonStyle(SolidButtonStyle())
                        .disabled(busy)
                    }
                    if let error {
                        Text(error).font(.system(size: 13)).foregroundStyle(DS.muted)
                    }
                    if let scan { results(scan) }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(DS.surface.ignoresSafeArea())
            .navigationTitle("Screenshot einlesen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func results(_ scan: Server.Scan) -> some View {
        if let balance = scan.balance {
            Card(title: "Kontostand", symbol: "building.columns.fill") {
                VStack(alignment: .leading, spacing: 3) {
                    Text(MoneyMath.euro(balance))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(balance < 0 ? Color(hex: 0xF5B94A) : DS.ink)
                    Text((scan.account ?? "").isEmpty ? "Wird beim Übernehmen gemerkt." : "\(scan.account ?? "") · wird beim Übernehmen gemerkt.")
                        .font(.system(size: 12)).foregroundStyle(DS.muted)
                }
            }
        }
        if !scan.tips.isEmpty {
            Card(title: "\(store.dotName) sieht", symbol: "lightbulb.fill") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(scan.tips, id: \.self) { tip in
                        Text(tip).font(.system(size: 14)).foregroundStyle(DS.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        if !scan.entries.isEmpty {
            Card(title: "Buchungen", symbol: "list.bullet") {
                VStack(spacing: 0) {
                    ForEach(Array(scan.entries.enumerated()), id: \.offset) { i, e in
                        if i > 0 { Divider().overlay(DS.line) }
                        let known = store.isKnownEntry(e)
                        checkRow(selected: pickedEntries.contains(i),
                                 title: e.title,
                                 detail: "\(store.scanDateLabel(e.date))\(known ? " · schon eingetragen" : " · neu")",
                                 amount: (e.income ? "+" : "−") + MoneyMath.euro(e.amount),
                                 highlight: !known) {
                            if pickedEntries.contains(i) { pickedEntries.remove(i) } else { pickedEntries.insert(i) }
                        }
                    }
                }
            }
        }
        if !scan.debts.isEmpty {
            Card(title: "Offene Raten & Rechnungen", symbol: "creditcard.fill") {
                VStack(spacing: 0) {
                    ForEach(Array(scan.debts.enumerated()), id: \.offset) { i, d in
                        if i > 0 { Divider().overlay(DS.line) }
                        checkRow(selected: pickedDebts.contains(i),
                                 title: d.title,
                                 detail: "fällig \(store.scanDateLabel(d.due))\(d.remaining > 1 ? " · noch \(d.remaining)×" : "")",
                                 amount: MoneyMath.euro(d.amount),
                                 highlight: true) {
                            if pickedDebts.contains(i) { pickedDebts.remove(i) } else { pickedDebts.insert(i) }
                        }
                    }
                }
            }
        }
        if scan.entries.isEmpty && scan.debts.isEmpty && scan.balance == nil {
            Text("Auf dem Screenshot war nichts Lesbares. Am besten die Umsatzliste oder die Klarna-Übersicht.")
                .font(.system(size: 13)).foregroundStyle(DS.muted)
        } else {
            let count = pickedEntries.count + pickedDebts.count
            Button(count == 0 ? "Kontostand übernehmen" : "\(count) übernehmen") {
                store.importScan(entries: pickedEntries.sorted().map { scan.entries[$0] },
                                 debts: pickedDebts.sorted().map { scan.debts[$0] },
                                 balance: scan.balance, account: scan.account ?? "")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            }
            .buttonStyle(SolidButtonStyle())
            .disabled(count == 0 && scan.balance == nil)
        }
    }

    private func checkRow(selected: Bool, title: String, detail: String, amount: String, highlight: Bool,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CheckBox(done: selected)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink)
                    Text(detail).font(.system(size: 12)).foregroundStyle(highlight ? DS.purpleMuted : DS.muted)
                }
                Spacer(minLength: 0)
                Text(amount).font(.system(size: 14, weight: .semibold)).monospacedDigit().foregroundStyle(Color(hex: 0xC7BECB))
            }
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func run() {
        guard let encoded = MediaUpload.jpegBase64(image, maxSide: 2000, quality: 0.75) else { return }
        busy = true
        error = nil
        Task {
            do {
                let result = try await Server.shared.moneyScan(encoded, known: store.knownEntriesSummary())
                withAnimation(.easeOut(duration: 0.25)) {
                    scan = result
                    // neue Buchungen und alle offenen Raten vorausgewählt, schon eingetragene nicht
                    pickedEntries = Set(result.entries.indices.filter { !store.isKnownEntry(result.entries[$0]) })
                    pickedDebts = Set(result.debts.indices)
                }
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

/// Eine offene Zahlung: Betrag, Fälligkeit, „Bezahlt“ sobald sie näher rückt.
private struct DebtLine: View {
    let item: MoneyItem
    let onEdit: () -> Void
    @EnvironmentObject private var store: Store

    var body: some View {
        let days = item.due.map { MoneyMath.daysUntil($0) } ?? 99
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink)
                Text(line).font(.system(size: 12))
                    .foregroundStyle(days < 0 ? Color(hex: 0xF5B94A) : days <= 2 ? DS.purpleMuted : DS.muted)
            }
            Spacer(minLength: 0)
            if days <= 7 {
                Button("Bezahlt") {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(Motion.list) { store.markPaid(item.id) }
                }
                .buttonStyle(PillButtonStyle(prominent: days <= 0))
            } else {
                Text(MoneyMath.euro(item.amount)).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Color(hex: 0xC7BECB))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button { store.markPaid(item.id) } label: { Label("Bezahlt", systemImage: "checkmark") }
            Button(role: .destructive) { store.deleteMoney(item.id) } label: { Label("Löschen", systemImage: "trash") }
        }
    }

    private var line: String {
        var parts = [MoneyMath.euro(item.amount)]
        if let due = item.due { parts.append(MoneyMath.dueText(due)) }
        if item.remaining > 1 { parts.append("noch \(item.remaining)×") }
        return parts.joined(separator: " · ")
    }
}

/// Einnahme, feste Kosten oder offene Zahlung anlegen/ändern.
struct MoneyEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var item: MoneyItem
    @State private var amount = ""

    private var isNew: Bool { !store.data.money.contains { $0.id == item.id } }
    private var valid: Bool { !item.title.trimmingCharacters(in: .whitespaces).isEmpty && MoneyMath.parse(amount) > 0 }

    private var placeholder: String {
        switch item.kind {
        case .income: "z. B. FSJ-Taschengeld"
        case .fixed: "z. B. Handyvertrag, Spotify"
        case .debt: "z. B. Klarna – Zalando"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if isNew {
                    Section {
                        Picker("Art", selection: $item.kind) {
                            Text("Geld rein").tag(MoneyItem.Kind.income)
                            Text("Fest").tag(MoneyItem.Kind.fixed)
                            Text("Offen").tag(MoneyItem.Kind.debt)
                        }
                        .pickerStyle(.segmented)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    TextField(placeholder, text: $item.title)
                    HStack {
                        TextField(item.kind == .debt ? "Betrag pro Zahlung" : "Betrag", text: $amount)
                            .keyboardType(.decimalPad)
                        Text("€").foregroundStyle(DS.muted)
                    }
                }
                .dopaRow()

                if item.kind == .debt {
                    Section {
                        DatePicker("Fällig am", selection: Binding(
                            get: { item.due ?? Date() }, set: { item.due = $0 }), displayedComponents: .date)
                        Stepper(item.remaining == 1 ? "Einmalig" : "Noch \(item.remaining)× (monatlich)",
                                value: $item.remaining, in: 1...36)
                    } footer: {
                        Text("Klarna „in 30 Tagen“ = einmalig. „In 3 Raten“ = 3×, jeweils einen Monat später.")
                    }
                    .dopaRow()
                } else {
                    Section {
                        Picker("Am", selection: $item.dayOfMonth) {
                            ForEach(1...31, id: \.self) { Text("\($0). im Monat").tag($0) }
                        }
                    }
                    .dopaRow()
                }

                Section {
                    Toggle("Erinnern", isOn: $item.remind)
                } footer: {
                    Text(remindText)
                }
                .dopaRow()

                if !isNew {
                    Section {
                        Button("Löschen", role: .destructive) {
                            store.deleteMoney(item.id)
                            dismiss()
                        }
                    }
                    .dopaRow()
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .dopaBackground()
            .navigationTitle(isNew ? "Neu" : item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        item.title = item.title.trimmingCharacters(in: .whitespaces)
                        item.amount = MoneyMath.parse(amount)
                        if item.kind == .debt && item.due == nil { item.due = Date() }
                        store.saveMoney(item)
                        dismiss()
                    }
                    .disabled(!valid)
                }
            }
            .onAppear {
                if item.amount > 0 { amount = String(format: "%g", item.amount).replacingOccurrences(of: ".", with: ",") }
            }
            .onChange(of: item.kind) { kind in
                item.remind = kind == .debt
                if kind == .debt && item.due == nil {
                    item.due = Calendar.current.date(byAdding: .day, value: 14, to: Date())
                }
            }
        }
        .presentationDetents([.large])
    }

    private var remindText: String {
        switch item.kind {
        case .debt: "2 Tage vorher und am Tag selbst – mit „Bezahlt“ direkt in der Benachrichtigung."
        case .fixed: "Am Abbuchungstag morgens, damit es dich nicht überrascht."
        case .income: "Am Tag, an dem das Geld kommt."
        }
    }
}

/// Sieben Balken Mo–So, heute hervorgehoben – Ausgaben der Woche auf einen Blick.
struct WeekBars: View {
    let values: [Double]
    @ObservedObject private var store = Store.shared
    @State private var grown = false            // Balken wachsen beim Erscheinen nacheinander hoch

    private let labels = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    var body: some View {
        let maxValue = max(values.max() ?? 0, 1)
        let today = (Calendar(identifier: .iso8601).component(.weekday, from: Date()) + 5) % 7   // Mo = 0
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DIESE WOCHE").font(.system(size: 10, weight: .heavy)).tracking(0.7).foregroundStyle(DS.faint)
                Spacer()
                Text(MoneyMath.euro(values.reduce(0, +))).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(DS.muted)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { i in
                    let value = i < values.count ? values[i] : 0
                    VStack(spacing: 5) {
                        if value > 0 {
                            Text(MoneyMath.euro(value)).font(.system(size: 9, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(DS.muted).lineLimit(1).minimumScaleFactor(0.6)
                        }
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(i == today ? store.theme.accent : Color(hex: 0x3A3042))
                            .frame(height: grown ? max(4, CGFloat(value / maxValue) * 64) : 4)
                            .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(Double(i) * 0.04), value: grown)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: value)
                        Text(labels[i]).font(.system(size: 10, weight: i == today ? .bold : .medium))
                            .foregroundStyle(i == today ? DS.purpleMuted : DS.faint)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100, alignment: .bottom)
        }
        .onAppear { grown = true }
    }
}
