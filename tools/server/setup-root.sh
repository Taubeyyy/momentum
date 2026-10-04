#!/bin/bash
# Einmalig als root ausführen (Edwin): gibt dem Benutzer claude genau die Dopa-Befehle frei
# und richtet den Autostart von Claude Remote Control ein.
set -euo pipefail
cat > /tmp/claude-dopa <<'RULE'
# Benutzer claude (Claude Code per Remote Control) darf genau diese Dopa-Befehle als root starten
claude ALL=(root) NOPASSWD: /usr/local/bin/dopa-deploy, /usr/local/bin/dopa-feedback, /usr/local/bin/dopa-logs
RULE
visudo -cf /tmp/claude-dopa
install -o root -g root -m 440 /tmp/claude-dopa /etc/sudoers.d/claude-dopa
rm /tmp/claude-dopa
install -o root -g root -m 644 /home/claude/momentum/tools/server/dopa-claude.service /etc/systemd/system/dopa-claude.service
systemctl daemon-reload
systemctl enable dopa-claude >/dev/null 2>&1
echo "Fertig. Jetzt: sudo -iu claude  →  claude  (einloggen, Ordner vertrauen)"
