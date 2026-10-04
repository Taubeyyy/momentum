# Claude auf dem Dopa-Server

Damit Edwin vom Handy aus Updates machen lassen kann (Claude-App → Code → Sitzung „Dopa-Server“),
läuft auf dem VPS `claude remote-control` als eigener Benutzer `claude` in `/home/claude/momentum`.

| Datei | installiert als | Aufruf |
|---|---|---|
| `dopa-deploy` | `/usr/local/bin/dopa-deploy` | `sudo dopa-deploy` / `sudo dopa-deploy --rollback` |
| `dopa-feedback` | `/usr/local/bin/dopa-feedback` | `sudo dopa-feedback [--all \| --done <id> "Notiz"]` |
| `dopa-logs` | `/usr/local/bin/dopa-logs` | `sudo dopa-logs [Zeilen]` |
| `dopa-ci` | `/usr/local/bin/dopa-ci` | `dopa-ci [--wait [Lauf]]` (ohne sudo) |
| `dopa-statusline` | `/usr/local/bin/dopa-statusline` | Statuszeile von Claude Code (`~claude/.claude/settings.json`), schreibt Limits nach `~claude/.claude/dopa-limits.json` |
| `dopa-claude-probe` | `/usr/local/bin/dopa-claude-probe` | „Aktualisieren“ im Claude-Tab: winzige Haiku-Anfrage, damit die Limits frisch sind |
| `dopa-claude-run` | `/usr/local/bin/dopa-claude-run` | Aufträge aus dem Claude-Tab in Dopa: `claude -p` per systemd-run als claude (überlebt pm2-Neustarts), Ordner `~claude/.dopa-jobs/<id>` |
| `dopa-claude.service` | `/etc/systemd/system/` | startet `claude remote-control` in tmux-Sitzung `dopa` |
| `setup-root.sh` | – | einmalig als root: sudo-Regel `/etc/sudoers.d/claude-dopa` + Autostart |

Die Kopien in `/usr/local/bin` gehören root (755) – Änderungen hier im Repo wirken erst, wenn sie vom PC aus
neu installiert werden. Der Benutzer `claude` kann `/var/www/momentum/.env` nicht lesen und `git push` nur
über den Deploy-Key dieses einen Repos.
