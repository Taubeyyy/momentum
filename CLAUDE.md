# Dopa (Repo „momentum“)

ADHS-App für den Eigentümer (Edwin). Zwei Teile in diesem Repo:

- **iOS-App „Dopa“** in `ios/` – SwiftUI, per TrollStore auf einem iPhone 13 (iOS **16.4.1**). XcodeGen (`ios/project.yml`),
  Targets `Dopa`, `DopaWidget` (Widgets + Live Activity), `DopaUITests`. Gemeinsamer Code in `ios/Shared/`.
- **Server** (Node/Express/better-sqlite3): `server.js`, `ai.js`, `db.js`, `tools/`. Live unter https://dopa.taubey.com
  (`/var/www/momentum`, pm2 „momentum“, Port 3065). KI-Kette in `ai.js`: Gemini (OpenAI-kompatibel) → Ollama → Anthropic.

Edwin schreibt Deutsch, locker, oft vom Handy. Antworten kurz und auf Deutsch.

## „Mach die Updates“ / „arbeite das Feedback ab“

Edwin schüttelt in der App das Handy oder tippt im Profil auf „Feedback an Claude“ – das landet in der Server-Datenbank.

1. `git pull --rebase` (vom PC aus wird auch gepusht).
2. `sudo dopa-feedback` – offene Einträge (`--all` inkl. erledigte). Diagnose-Einträge („Technik-Diagnose“) enthalten Protokolle aus der App.
3. Alles umsetzen, in **einem** Durchgang. Nur nachfragen, wenn etwas wirklich nicht zu erraten ist –
   dann eine kurze Frage mit Vorschlag, nicht fünf.
4. Server geändert → `npm test` muss grün sein (Tests stubben die KI, kosten nichts).
5. Committen und `git push`. **Die Commit-Nachricht ist der Update-Text in der App** („Build N ist da – …“):
   deutsch, kurz, aus Edwins Sicht („Profil geht wieder auf, Einkauf merkt sich den Laden“), keine Dateinamen.
6. Wenn `ios/**` oder `.github/workflows/ios.yml` geändert wurde, baut GitHub Actions die App (~8–15 Min):
   `dopa-ci --wait` (als Hintergrundbefehl oder mit langem Timeout; gibt nach 9 Min auf → nochmal mit der genannten Nummer).
   Fehler stehen mit Auszug in der Ausgabe, ganze Protokolle in `/var/www/momentum/releases/ci-<Lauf>-build.log` / `-ui.log`.
   Bei Fehler: reparieren, neu pushen, wieder warten. Erst fertig melden, wenn Build **und** Simulator-Rundgang OK sind.
7. Server geändert → `sudo dopa-deploy` (testet, sichert, kopiert, startet neu, prüft; startet die neue Version nicht,
   geht es automatisch zurück). Notfall: `sudo dopa-deploy --rollback`. Server-Fehler ansehen: `sudo dopa-logs 100`.
8. Feedback abhaken: `sudo dopa-feedback --done <id> "Build <N>: was umgesetzt wurde"`.
9. Edwin kurz Bescheid geben: was drin ist, Build-Nummer, „in der App auf Update tippen“. Offene Punkte ehrlich nennen.

Aufträge kommen meist aus Edwins eigener **Claude-App** (`ios/ClaudeApp`, Target `ClaudeRemote`, Server-Teil `hub.js`):
dann läufst du headless per `tools/server/dopa-claude-run` (systemd-run, max. 60 Min, feste Werkzeug-Liste) und
Edwin sieht deine Texte und Werkzeug-Aufrufe live. Nachfragen geht dort nicht – Fragen ans Ende.
Die Claude-App betreut mehrere Projekte: Dopa (dieses Repo, `/home/claude/momentum`) und die Fakester-iOS-App
(`/home/claude/fakester-ios`, eigene CLAUDE.md). Sie baut im selben CI-Lauf mit (Job `claude-app`); wer `hub.js`
oder die App ändert, hält beide Seiten passend.

**GitHub-Actions-Minuten sind knapp** (4.10.: Build 67 blieb hängen – Kontingent leer; macOS-Minuten zählen 10-fach,
jeder Push unter `ios/**` = Build + Simulator-Rundgang). Edwin will auf einen eigenen Runner umstellen. Bis dahin:
iOS-Änderungen bündeln, nicht für Kleinigkeiten einzeln pushen; reine Server-/Doku-Commits lösen keinen Build aus.

Auf dem Server gibt es kein Xcode und kein `gh` – Swift wird nur im CI gebaut. Deshalb vorsichtig und kompilierbar schreiben
(Typen ausschreiben, wo der Compiler raten müsste; keine riesigen View-Ausdrücke).

## iOS – Fallen, die schon Zeit gekostet haben

- Deployment-Target **iOS 16.2**, Swift 5: kein `@Observable`, kein SwiftData, kein `onChange(of:) { old, new in }`
  (nur die Ein-Parameter-Form), keine interaktiven Widgets, kein `ContentUnavailableView`, kein `.containerBackground` ohne `if #available`.
- Muster: `Store.shared` (@MainActor ObservableObject, speichert `dopa.json` in der App Group `group.com.taubey.dopa`),
  `Router.shared` (Tabs, Routen, `feedbackRequest`), `Toaster.shared`.
- Neue Felder in Models **immer tolerant decodieren** (`c.value(.feld, or: default)`), sonst ist Edwins Datei nach dem Update leer.
- Logik, die in `ios/Shared/` + `Dopa/Game.swift` liegt, wird im CI per `swiftc` mit `ios/Tests/main.swift` getestet –
  neue reine Logik dort hinlegen und testen.
- Endlos-Animationen nie per `withAnimation(.repeatForever)` in `onAppear` (dann schwingt die ganze Seite mit) –
  nur `.animation(_:value:)` direkt am Element.
- `.safeAreaInset` außen um einen NavigationStack kommt unter iOS 16 nicht an → Platz für die Tab-Leiste hängt an
  `DopaScreen` / `.dopaBackground()` (`TabBarSpace.height`).
- Fenster (sheets) an der App-Wurzel und `.photosPicker` in immer lebenden Seiten gingen auf iOS 16.4 nicht auf →
  Seiten per NavigationLink pushen, Fotoauswahl über `LibraryPicker`/`.photoSource`.
- Keine eigenen Dropdowns/Scrollbalken; native Bausteine (Menu, Picker, List) bevorzugen.
- Der Simulator-Rundgang (`ios/UITests/DopaUITests.swift`) sucht Knöpfe über ihre Beschriftungen
  (Tab-Namen, „Mehr“-Bubble, „Profil und Einstellungen“, „Routinen und Einstellungen“, Navigationstitel „Profil“,
  „Plan einstellen“) – wer die umbenennt, passt den Test mit an.
- Aufteilung seit Build 57: Leiste = Heute · Machen (Aufgaben/Plan per `Router.doSection`, beide geladen in `DoPage`) ·
  Merken · Einkauf · Mehr (Bubble → `Router.moreItem`: Geld = `ShopView(mode: .money)`, Schlaf, Dot, Claude, Profil).
  `AppTab.day`/`.claude` gibt es nur noch als Sprungziele – `Router.go` leitet um.
- Kein swiftc auf dem Server und neue Skripte brauchen Freigabe → Klammern nach größeren Umbauten von Hand prüfen.
- **Live Activity läuft seit 3.10. abends (Build 51)** – „plötzlich“, ohne Code-Änderung, nach den Tests unten
  (TrollStore-Registrierung auf User umgestellt, Widget-Galerie geöffnet; Edwin: „eigentlich nur neue Version installiert“).
  Dopa in TrollStore auf **User** lassen. Geht sie wieder weg:
  genau diese Schritte wiederholen, dann Technik-Diagnose. Verlauf der Suche:
- Live Activity (Feedback #8/#17) war unter TrollStore lange kaputt; Diagnose über Profil → Technik.
  Stand Build 49: Activity startet und ist in derselben Sekunde „dismissed“, Erweiterung wird nie aufgerufen
  (früher im iPhone-Log: chronod `_LSPluginFindWithPlatformInfo -10814`). Dopa ist bei TrollStore als **System**
  registriert – Verdacht: deshalb findet chronod die Ansicht nicht. Nächster Test: in TrollStore auf „User“ umstellen.
  Build 49: Umstellung kam nicht an (#36 weiter „System“). „Erweiterung geladen“ steht seit Einbau der Sonde (12:24-Build,
  Live Activity in DopaWidget gezogen) auf 11:29 – nie wieder. Build 50: Technik zeigt platzierte Widgets + Test A
  (Widget-Galerie öffnen → startet die Erweiterung überhaupt?) und Test B (User-Registrierung).
  Ergebnis #37: Erweiterung startet (Widgets ok), auch mit **User**-Registrierung sofort „dismissed“ → nicht TrollStore.
  Build 51: CI durchleuchtet jede IPA (`ci-<N>-ipa.log`, mit Read lesbar) – Info.plists, Plattform 2/minos 16.2/SDK 18.5,
  Entitlements, Signatur-IDs, ActivityConfiguration im Binary: alles unauffällig. Nächster Schritt: iPhone-Systemprotokoll
  (chronod/ActivityKit) beim Test – nur das sagt, warum iOS beendet.
  Fertige IPA durchleuchten: `python3 tools/ipa-check.py <ipa>` (Info.plists, Plattform, Entitlements, Signatur-ID).

## ADHS-Regeln

- Anfangen ist die Hürde → wenige Tipps pro Aktion, ein klarer nächster Schritt, Minuten statt Pflichten.
- Kein Schuld-Ton, keine Streaks, die reißen, keine roten Fehlerzähler, keine Motivationssprüche.
- Die App kommt zum Menschen (Widgets, Mitteilungen) und nutzt sich nicht ab (wechselnde Texte von Dot, Überraschungen).
- Sauber und ruhig: eine Sache darf laut sein, Rest leise. Dunkles Design, Akzent Lila (`DS.*` in `Style.swift`).
- Persönliches über den Nutzer steht nur auf dem Server in `CLAUDE.local.md` (nicht im Repo – das Repo ist öffentlich).

## Sicherheit

- Nie API-Keys, Passwörter oder `.env`-Inhalte anfassen, ausgeben oder committen. Braucht etwas einen Key,
  Edwin eine Zeile geben, die er selbst ausführt.
- Gesundheitsdetails aus Feedback/Profil nicht nach außen tragen – und nie ins Repo schreiben, es ist öffentlich.
