import SwiftUI
import UserNotifications
import BackgroundTasks

@main
struct DopaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = Store.shared

    init() {
        // Navigationsleiste wie in guten iOS-Apps: großer runder Titel, beim Scrollen Glas-Leiste
        let ink = UIColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1)
        func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
            return UIFont(descriptor: descriptor, size: size)
        }
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.largeTitleTextAttributes = [.foregroundColor: ink, .font: rounded(34, .bold)]
        edge.titleTextAttributes = [.foregroundColor: ink, .font: rounded(17, .semibold)]
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        standard.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        standard.backgroundColor = UIColor(red: 16 / 255, green: 17 / 255, blue: 20 / 255, alpha: 0.55)
        standard.shadowColor = UIColor(white: 1, alpha: 0.06)
        standard.largeTitleTextAttributes = edge.largeTitleTextAttributes
        standard.titleTextAttributes = edge.titleTextAttributes
        UINavigationBar.appearance().standardAppearance = standard
        UINavigationBar.appearance().compactAppearance = standard
        UINavigationBar.appearance().scrollEdgeAppearance = edge
    }

    static let backupTaskID = "com.taubey.dopa.backup"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
        // Feedback #15: ab und zu auch im Hintergrund sichern, ohne dass du die App öffnest
        .backgroundTask(.appRefresh(DopaApp.backupTaskID)) {
            await DopaApp.scheduleBackgroundBackup()
            await Store.shared.backupNow()
            // Dots neuer Tag kann schon geschrieben werden, bevor du die App öffnest
            await Store.shared.refreshCompanionIfNeeded()
        }
    }

    /// Nächste Hintergrund-Sicherung anmelden – iOS entscheidet selbst, wann genau.
    @MainActor
    static func scheduleBackgroundBackup() {
        let request = BGAppRefreshTaskRequest(identifier: backupTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(2 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}

enum ShopSection: Hashable { case list, money }

/// Wohin die App springen soll – von Widgets (URL) und Benachrichtigungen (AppDelegate).
@MainActor
final class Router: ObservableObject {
    static let shared = Router()

    @Published var tab = AppTab.today
    @Published var shopSection = ShopSection.list
    @Published var memoFocusRequest = 0     // hochzählen = Eingabefeld in „Merken“ fokussieren
    @Published var morningRequest = 0       // hochzählen = Morgen-Checkliste öffnen
    @Published var eveningRequest = 0       // hochzählen = Abendroutine öffnen
    @Published var startTask: UUID?         // „Hilf mir anfangen“ für diese Aufgabe öffnen
    @Published var feedbackRequest = 0      // hochzählen = Feedback-Fenster (Schütteln) auf der sichtbaren Seite
    @Published var doSection = DoSection.tasks     // „Machen“: Aufgaben oder Plan
    @Published var moreItem = MoreItem.money       // was unter „Mehr“ offen ist

    var tabName: String { tab == .more ? moreItem.title : tab == .tasks && doSection == .plan ? "Plan" : tab.title }

    /// Ist die Claude-Seite gerade sichtbar? (liegt jetzt unter „Mehr“)
    var claudeVisible: Bool { tab == .more && moreItem == .claude }

    /// Tab wechseln – mit derselben weichen Bewegung wie die Leiste.
    /// Plan liegt jetzt unter „Machen“, Claude unter „Mehr“ – alte Ziele werden umgeleitet.
    func go(_ tab: AppTab) {
        var target = tab
        switch tab {
        case .day:
            doSection = .plan
            target = .tasks
        case .claude:
            moreItem = .claude
            target = .more
        default:
            break
        }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { self.tab = target }
    }

    /// Etwas aus der „Mehr“-Bubble öffnen.
    func showMore(_ item: MoreItem) {
        moreItem = item
        go(.more)
    }

    func open(_ route: String?, id: String? = nil) {
        switch route {
        case "anfangen":
            doSection = .tasks
            go(.tasks)
            startTask = id.flatMap(UUID.init(uuidString:))
        case "aufgaben":
            doSection = .tasks
            go(.tasks)
        case "merken":
            go(.memo)
            memoFocusRequest += 1
        case "morgen":
            go(.day)
            morningRequest += 1
        case "einkauf":
            shopSection = .list
            go(.shop)
        case "claude":
            go(.claude)
        case "geld":
            showMore(.money)
        case "schlaf":
            showMore(.sleep)
        case "tag":
            go(.day)
        case "abend":
            go(.day)
            eveningRequest += 1
        default:
            go(.today)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Reminders.registerCategories()
        Task { @MainActor in Reminders.registerCategories(Store.shared.data.reminders) }   // eigene Snooze-Zeiten
        return true
    }

    /// Benachrichtigungen auch zeigen, während die App offen ist.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Aktionen direkt aus der Benachrichtigung – ohne die App öffnen zu müssen.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let typed = (response as? UNTextInputNotificationResponse)?.userText
        let info = response.notification.request.content.userInfo
        let route = info["route"] as? String
        let parkID = (info["park"] as? String).flatMap(UUID.init(uuidString:))
        let reminderID = info["reminder"] as? String
        let habitID = info["habit"] as? String
        let moneyID = (info["money"] as? String).flatMap(UUID.init(uuidString:))
        let eventKey = info["event"] as? String
        let taskID = info["task"] as? String
        let title = response.notification.request.content.title
        let category = response.notification.request.content.categoryIdentifier
        Task { @MainActor in
            switch action {
            case Reminders.Action.mealEaten:
                Store.shared.mealEaten()
            case Reminders.Action.mealSnooze:
                await Reminders.snoozeMeal(minutes: Store.shared.data.reminders.mealSnooze)
            case Reminders.Action.nudgeMemo:
                if let typed { Store.shared.addMemo(typed, kind: nil) }
            case Reminders.Action.parkKeep:
                if let parkID { Store.shared.decide(parkID, .keep) }
            case Reminders.Action.parkDrop:
                if let parkID { Store.shared.decide(parkID, .drop) }
            case Reminders.Action.taskDone:
                if let id = reminderID.flatMap(UUID.init(uuidString:)) { Store.shared.ackReminder(id) }
            case Reminders.Action.taskSnooze:
                if let reminderID {
                    await Reminders.snoozeTask(id: reminderID, title: title, minutes: Store.shared.data.reminders.snoozeMinutes)
                }
            case Reminders.Action.habitDone:
                if let id = habitID.flatMap(UUID.init(uuidString:)) { Store.shared.tickHabit(id, onlyIfOpen: true) }
            case Reminders.Action.habitSnooze:
                if let habitID {
                    await Reminders.snoozeHabit(id: habitID, title: title, category: category,
                                                minutes: Store.shared.data.reminders.snoozeMinutes)
                }
            case Reminders.Action.moneyPaid:
                if let moneyID { Store.shared.markPaid(moneyID) }
            case Reminders.Action.eventGone:
                if let eventKey { Store.shared.ackEvent(eventKey) }
            case Reminders.Action.reviewOne:
                if let typed { Store.shared.setTheOne(typed, for: Store.shared.reviewTargetDay) }
            case Reminders.Action.spendAdd:
                // „12 Bahn, 3 Kaffee“ → zwei Einträge
                for part in MoneyMath.splitEntries(typed ?? "") { Store.shared.addEntry(part) }
            case Reminders.Action.focusDone:
                Store.shared.stopFocus(completed: true)
            case Reminders.Action.focusMore:
                Store.shared.extendFocus(minutes: Store.shared.data.reminders.extendMinutes)
            case Reminders.Action.todoDone:
                if let id = taskID.flatMap(UUID.init(uuidString:)) { Store.shared.setDone(id, true) }
            case Reminders.Action.todoSnooze:
                if let taskID {
                    await Reminders.snoozeTodo(id: taskID, title: title, minutes: Store.shared.data.reminders.snoozeMinutes)
                }
            case UNNotificationDefaultActionIdentifier:
                Router.shared.open(route, id: taskID)
            default:
                break
            }
            completionHandler()
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var router = Router.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var toast: Award?
    @State private var levelUp: Int?
    @State private var splash = true
    @ObservedObject private var toaster = Toaster.shared

    @State private var keyboardVisible = false
    @State private var showMore = false         // „Mehr“-Bubble über der Leiste

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    let selected = router.tab == tab
                    page(tab)
                        .opacity(selected ? 1 : 0)
                        .scaleEffect(selected ? 1 : 0.985)
                        .offset(x: selected ? 0 : (tab.rawValue < router.tab.rawValue ? -22 : 22))
                        .allowsHitTesting(selected)
                        .accessibilityHidden(!selected)
                        .zIndex(selected ? 1 : 0)
                }
            }
            if showMore {
                MoreBubble(onPick: { item in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showMore = false }
                    router.showMore(item)
                }, onClose: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showMore = false }
                })
                .zIndex(2)
                .transition(.opacity)
            }
            if !keyboardVisible {
                DopaTabBar(selection: $router.tab, onMore: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { showMore.toggle() }
                })
                .padding(.bottom, 2)
                .zIndex(3)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(DS.surface.ignoresSafeArea())
        .animation(.easeOut(duration: 0.2), value: keyboardVisible)
        .onAppear {
            // Simulator-Rundgang im CI: Beispieldaten, kein Startbildschirm
            if CommandLine.arguments.contains("-uitest") {
                splash = false
                store.seedDemoIfEmpty()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .tint(store.theme.accent)
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            if let toast {
                AwardToast(award: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { self.toast = nil }
            }
        }
        .overlay(alignment: .bottom) {
            if let message = toaster.message {
                ConfirmToast(message: message)
                    .padding(.bottom, keyboardVisible ? 12 : 92)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if splash {
                SplashView { splash = false }
            }
        }
        .overlay {
            if let levelUp {
                LevelUpView(level: levelUp) { self.levelUp = nil }
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toast)
        .animation(.easeInOut(duration: 0.25), value: levelUp)
        .onChange(of: store.lastAward) { award in
            guard let award else { return }
            toast = award
            if let level = award.newLevel { levelUp = level }
            Task {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                if toast?.id == award.id { toast = nil }
            }
        }
        // dopa://merken, dopa://timer, dopa://morgen, dopa://einkauf, dopa://anfangen/<Aufgaben-ID>
        .onOpenURL { url in router.open(url.host, id: url.pathComponents.dropFirst().first) }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                // Termine neu lesen, Texte neu auslosen, Zeiten aktualisieren, wartendes Feedback losschicken
                Agenda.shared.refresh()
                store.rescheduleReminders()
                Task {
                    await Updates.shared.check()
                    await Server.shared.refreshStatus()
                    await store.syncFeedback()
                    await store.backupIfStale()
                    await store.refreshHealth()             // Schlaf/Schritte von der Uhr, vor Dots Tagestexten
                    await store.refreshCompanionIfNeeded()
                }
            case .background:
                DopaApp.scheduleBackgroundBackup()
                Task { await store.backupIfDue() }
            default:
                break
            }
        }
        // Handy schütteln = Feedback an Claude, egal wo man gerade ist (die sichtbare Seite öffnet es)
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in router.feedbackRequest += 1 }
    }

    @ViewBuilder
    private func page(_ tab: AppTab) -> some View {
        switch tab {
        case .today: TodayView()
        case .tasks: DoPage(morningRequest: router.morningRequest, eveningRequest: router.eveningRequest)
        case .day: EmptyView()          // liegt unter „Machen“
        case .memo: MemoView(focusRequest: router.memoFocusRequest)
        case .shop: ShopView(mode: .list)
        case .claude: EmptyView()       // liegt unter „Mehr“
        case .more: MorePage()
        }
    }
}
