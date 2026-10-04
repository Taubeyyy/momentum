import XCTest

/// Tippt Dopa im Simulator durch und legt von jedem Bildschirm ein Foto ab (SHOT_DIR, im CI hochgeladen).
/// Prüft dabei, dass Profil/Einstellungen und die Plan-Einstellungen aufgehen.
final class DopaUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-uitest"]
        addUIInterruptionMonitor(withDescription: "System-Fragen") { alert in
            for label in ["Erlauben", "Allow", "Zulassen", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()
    }

    func testTour() {
        sleep(3)
        app.swipeUp()            // löst den Monitor für Systemfragen aus
        app.swipeDown()
        sleep(1)
        shot("01-heute")
        app.swipeUp()
        sleep(1)
        shot("02-heute-unten")
        app.swipeDown()

        for (i, tab) in ["Machen", "Merken", "Einkauf"].enumerated() {
            let button = app.buttons[tab].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), "Tab \(tab) fehlt")
            button.tap()
            sleep(1)
            shot(String(format: "%02d-%@", i + 3, tab))
        }

        // „Mehr“-Bubble: Claude und Geld
        for (i, item) in ["Claude", "Geld", "Schlaf"].enumerated() {
            let more = app.buttons["Mehr"].firstMatch
            XCTAssertTrue(more.waitForExistence(timeout: 5), "Mehr-Knopf fehlt")
            more.tap()
            let entry = app.buttons[item].firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 4), "\(item) fehlt in der Mehr-Bubble")
            entry.tap()
            sleep(1)
            shot(String(format: "%02d-mehr-%@", i + 6, item))
        }

        // Profil & Einstellungen über Dot oben rechts
        app.buttons["Heute"].firstMatch.tap()
        sleep(1)
        let avatar = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Profil und Einstellungen")).firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 5), "Dot-Knopf fehlt")
        avatar.tap()
        let profileOpened = app.navigationBars["Profil"].waitForExistence(timeout: 6)
        shot("09-profil")
        XCTAssertTrue(profileOpened, "Profil öffnet nicht")
        if profileOpened {
            // Feedback-Fenster aus dem Profil
            let feedback = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Feedback an Claude")).firstMatch
            if feedback.waitForExistence(timeout: 3) {
                feedback.tap()
                XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 4) || app.textFields.firstMatch.waitForExistence(timeout: 1),
                              "Feedback-Fenster öffnet nicht")
                shot("10-feedback")
                app.swipeDown(velocity: .fast)
                sleep(1)
            }
            app.swipeUp()
            sleep(1)
            shot("10-profil-unten")
            app.navigationBars.buttons.element(boundBy: 0).tap()     // zurück
            sleep(1)
        }

        // Machen → Plan → Zahnrad
        app.buttons["Machen"].firstMatch.tap()
        sleep(1)
        app.buttons["Plan"].firstMatch.tap()
        sleep(1)
        let gear = app.buttons["Routinen und Einstellungen"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 5), "Zahnrad im Plan fehlt")
        gear.tap()
        let planSettings = app.navigationBars["Plan einstellen"].waitForExistence(timeout: 6)
        shot("11-plan-einstellungen")
        XCTAssertTrue(planSettings, "Plan-Einstellungen öffnen nicht")
    }

    private func shot(_ name: String) {
        let image = app.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            try? image.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }
}
