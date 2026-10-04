/* Feedback aus der Dopa-App lesen und abhaken – für Claude per SSH.
     node tools/feedback.js                 offene Einträge
     node tools/feedback.js --all           alle, inkl. erledigte
     node tools/feedback.js --done 12 "Text, was umgesetzt wurde"
     node tools/feedback.js --summary       offenes Feedback per KI gebündelt   */
'use strict';
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const db = require('../db');

const args = process.argv.slice(2);

if (args[0] === '--done') {
  const id = Number(args[1]);
  const note = args.slice(2).join(' ');
  const r = db.prepare('UPDATE feedback SET done_at=?, done_note=? WHERE id=?').run(Date.now(), note, id);
  console.log(r.changes ? `#${id} erledigt` : `#${id} nicht gefunden`);
  process.exit(0);
}

if (args[0] === '--summary') {
  const ai = require('../ai');
  const open = db.prepare('SELECT id, text, screen FROM feedback WHERE done_at IS NULL ORDER BY created_at').all();
  if (!open.length) { console.log('Kein offenes Feedback.'); process.exit(0); }
  ai.summarizeFeedback({ items: open }).then(({ data, provider }) => {
    console.log(`${open.length} offene Einträge, gebündelt (${provider}):\n`);
    for (const t of data.themes || []) {
      console.log(`[${t.kind}] ${t.title}  (#${(t.ids || []).join(', #')})\n   → ${t.next}\n`);
    }
    process.exit(0);
  }).catch(e => { console.error('KI-Fehler:', e.message); process.exit(1); });
  return;
}

const all = args[0] === '--all';
const rows = db.prepare(`SELECT f.*, u.email FROM feedback f JOIN users u ON u.id = f.user_id
  ${all ? '' : 'WHERE f.done_at IS NULL'} ORDER BY f.created_at`).all();

if (!rows.length) {
  console.log(all ? 'Noch kein Feedback.' : 'Kein offenes Feedback.');
  process.exit(0);
}
const fmt = ms => new Date(ms).toLocaleString('de-DE', { timeZone: 'Europe/Berlin' });
for (const r of rows) {
  const meta = [fmt(r.created_at), r.screen && `Bildschirm: ${r.screen}`, r.app_version && `v${r.app_version}`]
    .filter(Boolean).join(' · ');
  console.log(`#${r.id}${r.done_at ? ' ✓' : ''}  ${meta}\n   ${r.text.replace(/\n/g, '\n   ')}`);
  if (r.done_at) console.log(`   → ${r.done_note || 'erledigt'} (${fmt(r.done_at)})`);
  console.log();
}
