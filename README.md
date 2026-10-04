# Momentum — ADHS-App

PWA (Handy + Desktop) mit Node/Express/SQLite-Backend. Gleicher Stack wie Rigged/AimForge,
läuft also 1:1 mit pm2 + nginx-Subdomain auf dem VPS.

## Was drin ist

| Bereich | Funktion |
|---|---|
| **Heute** | „Jetzt dran"-Karte (genau *eine* Aufgabe), Tages-Stats, Top 3, Routinen-Fortschritt, Habits |
| **Tasks** | Quick-Add, Zerlegen in Mini-Schritte (2 Ebenen), Energie-Filter (🌱/⚡/🔥), Zeitschätzung, Top-3-Stern |
| **Fokus** | Timer 5–90 min mit Ring (Zeitwahrnehmung), läuft über Reload/Tab-Wechsel weiter, Sound + Notification, 14-Tage-Historie |
| **Routinen** | Morgen-/Abendroutine mit Schritten, tägliches Reset, Fortschrittsbalken |
| **Habits/Meds** | Zähler pro Tag (z.B. 8× Wasser), 7-Tage-Punkte, Erinnerungszeit |
| **Brain Dump** | Sofort-Inbox, ein Klick → Aufgabe |
| **Check-in** | Stimmung / Energie / Fokus (1–5) + Notiz |

## Designregeln

Vier Regeln in `style.css`, aus denen alles andere folgt:

1. **Genau eine Sache darf laut sein.** Der Hero („Jetzt dran") ist überproportional groß und hat
   Schatten, Verlauf und Glow. Alles darunter läuft als `.card.quiet` mit reduziertem Kontrast.
   Wo alles gleich laut ist, wandert der Blick — und bei ADHS wandert er dann weg.
2. **Die Aktionsfarbe ist immer dieselbe.** Jeder auslösende Knopf ist Indigo, überall. Man muss nie
   raten, was der Knopf ist.
3. **Bereichsfarbe ist nur Orientierung, nie Aktion.** Heute violett, Tasks mint, Fokus orange,
   Routinen himmelblau, Dump lila, Worte amber — als `--sect` an Nav, Überschriftspunkt und Ring.
   Beantwortet „wo bin ich" vorsprachlich.
4. **Bewegung ist optional.** `prefers-reduced-motion` wird respektiert, zusätzlich gibt es einen
   eigenen Schalter. Alle Übergänge rechnen mit `calc(… * var(--speed))`, `--speed: 0` schaltet sie ab.

Weitere ADHS-Entscheidungen:

- **Timerleiste bleibt sichtbar** — in jedem Tab, mit Restzeit, Aufgabe und Pause. Ein laufender
  Timer, der beim Tabwechsel verschwindet, ist für das Arbeitsgedächtnis wertlos.
- **Tagesfortschritt** als dünner Balken (7–23 Uhr). Zeitgefühl ist das erste, was fehlt.
- **Nullen klagen nicht an** — unerreichte Tageswerte werden ausgegraut statt fett gesetzt.
- **Lange Listen werden abgeschnitten** (6 Einträge, Rest auf Knopfdruck). Vollständigkeit lähmt.
- **Abhaken dauert kurz sichtbar** (260 ms) statt sofort zu verschwinden — die Belohnung soll ankommen.
- **Löschen neben Checkboxen ist still** und wird erst beim Hover deutlich (Fehlklickschutz).
- **Textgröße** in drei Stufen, alles in `em` — keine feste Pixelgröße im ganzen Projekt.
- Energie- statt Prioritäts-Sortierung, „↻ anderes" gegen Entscheidungslähmung, Haptik,
  kein Streak-Druck (der Streak zählt Fokus-Tage und bricht nicht sichtbar).
- Tap-Ziele mindestens 44 px, Kontrast im Hell-Modus 16,7:1 (Text) bzw. 5,4:1 (sekundär).

## KI-Helfer (optional)

Sieben Funktionen über Claude (`claude-opus-5`), alle serverseitig — der API-Key verlässt den Server nie.
**Ohne `ANTHROPIC_API_KEY` sind sie komplett unsichtbar**: keine toten Buttons, kein Worte-Tab, die App
funktioniert vollständig ohne.

| Funktion | Wo | Was sie macht |
|---|---|---|
| **Zerlegen** | Zerlegen-Sheet | Auflösung 🔭 Etappen … 🧬 Winzig wählen, Schritte landen direkt als Unteraufgaben. Dazu ein „opener": die allererste körperliche Handlung |
| **Schätzen** | Task-Sheet | Realistische Dauer inkl. Suchen und Aufräumen — mit Puffer, nicht optimistisch |
| **Sortieren** | Brain Dump | Kompletter Dump → gebündelte Aufgaben mit Unterschritten. Was keine Aufgabe war, wird gesagt statt still verworfen |
| **Was jetzt?** | Heute | Wählt *eine* Aufgabe nach Energie, Uhrzeit und heutiger Fokuszeit — nicht nach Reihenfolge. Zustand schlägt Wichtigkeit |
| **Wiedereinstieg** | Heute | Nach Unterbrechung: wo du warst, drei winzige Handgriffe zurück, dann der nächste Schritt |
| **Umschreiben** | Worte | 8 Richtungen: klarer, kürzer, formeller, lockerer, sanfter, bestimmter, Absage, Entschuldigung |
| **Einordnen** | Worte | Empfangene Nachricht: was dasteht, welcher Ton, Temperatur 1–5, was du reinliest das nicht dasteht, Antwortvorschlag |

Der Ton ist bewusst gesetzt (`VOICE` in `ai.js`): kein Anfeuern, keine Motivationssprüche, keine
Erklärungen warum etwas wichtig ist. Nur der nächste Griff. Kein Schritt darf „sich kümmern" oder
„organisieren" heißen — das sind Wünsche, keine Handlungen.

**Key eintragen** — auf [console.anthropic.com](https://console.anthropic.com) unter *API Keys* erzeugen, dann:

```bash
echo "ANTHROPIC_API_KEY=sk-ant-dein-key" >> .env
```

Server neu starten, fertig. Kosten: ein Zerlegen-Aufruf sind grob 500 Input- und 300 Output-Tokens,
also rund **1 Cent**. Eingebaut ist ein Limit von 60 KI-Aufrufen pro Stunde und Nutzer gegen Ausreißer.

## Tests

```bash
npm test
```

Fährt einen zweiten Server auf Port 3061 hoch, ersetzt die Modellantworten durch feste Werte und prüft
die Verdrahtung: Auth, Validierung, was in der Datenbank landet, Rate-Limit. Kostet nichts und braucht
keinen API-Key.

## Lokal starten

```bash
cd momentum && npm install && npm start
```

→ http://localhost:3060

## Deploy auf den VPS (194.164.205.65)

```bash
rsync -av --exclude node_modules --exclude '*.db*' --exclude .env ./momentum/ root@194.164.205.65:/root/momentum/
```

Dann auf dem Server:

```bash
cd /root/momentum && npm install --omit=dev && printf 'PORT=3060\nJWT_SECRET=%s\nNODE_ENV=production\nANTHROPIC_API_KEY=sk-ant-dein-key\n' "$(openssl rand -hex 32)" > .env && pm2 start server.js --name momentum && pm2 save
```

nginx (z.B. `focus.taubey.com`) — analog zu den anderen Projekten:

```nginx
server {
  server_name focus.taubey.com;
  location / {
    proxy_pass http://127.0.0.1:3060;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
```

Danach `certbot --nginx -d focus.taubey.com`. **HTTPS ist Pflicht** — sonst kein Service Worker,
keine Installation als App und keine Notifications.

## API (Cookie-Auth, JWT `mo_token`)

```
POST   /api/auth/register|login|logout      GET /api/me      PATCH /api/me
GET    /api/tasks         POST /api/tasks   PATCH/DELETE /api/tasks/:id
POST   /api/focus         GET  /api/focus/stats?days=14
GET    /api/routines      POST /api/routines   PATCH/DELETE /api/routines/:id
POST   /api/routines/:id/steps   DELETE /api/steps/:id   POST /api/steps/:id/check
GET    /api/habits        POST /api/habits  PATCH/DELETE /api/habits/:id  POST /api/habits/:id/log
GET    /api/inbox         POST /api/inbox   POST /api/inbox/:id/convert   DELETE /api/inbox/:id
GET    /api/moods         POST /api/moods
GET    /api/today

KI (nur mit ANTHROPIC_API_KEY, sonst 503):
POST   /api/ai/breakdown {task_id, resolution:1-5}   POST /api/ai/estimate {task_id}
POST   /api/ai/compile {text?, use_inbox?}           POST /api/ai/rewrite {text, mode}
POST   /api/ai/interpret {text}                      POST /api/ai/next
POST   /api/ai/reentry {task_id?}                    GET  /api/ai/status
```

## Dateien

```
server.js      REST-API + statisches Hosting
ai.js          KI-Funktionen: Prompts, Schemas, Anthropic-SDK
db.js          SQLite-Schema (WAL)
public/        index.html · app.js · style.css · sw.js · manifest.webmanifest
tools/         gen-icons.js (PNG-Icons ohne Abhängigkeiten) · test-ai.js
```

## Nächste Schritte

1. **Desktop-App** — Tauri/Electron-Wrapper um dieselbe URL, plus globaler Hotkey für Quick-Capture
   und Tray-Timer.
2. **Native Mobile** — Expo-App gegen dieselbe API; erst dann gibt es echte Push-Notifications und
   Homescreen-Widgets (die PWA erinnert nur, solange sie offen ist).
3. Offline-Queue (Schreibzugriffe puffern statt zu verlieren).
