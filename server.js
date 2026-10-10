'use strict';
const path = require('path');
const fs = require('fs');
require('dotenv').config({ path: path.join(__dirname, '.env') });
const express = require('express');
const cookieParser = require('cookie-parser');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const db = require('./db');
const ai = require('./ai');

const PORT = process.env.PORT || 3060;
const JWT_SECRET = process.env.JWT_SECRET || 'momentum-dev-secret-change-me';
const COOKIE = 'mo_token';
const PROD = process.env.NODE_ENV === 'production';

const app = express();
app.set('trust proxy', 1);
app.use(cookieParser());
// Dopa-Backup: ganze App-Daten, darf größer sein als normale Anfragen – deshalb vor dem allgemeinen Parser
app.put('/api/dopa/backup', express.json({ limit: '8mb' }), (req, res, next) => auth(req, res, next), (req, res) => {
  if (!req.body || typeof req.body !== 'object' || Array.isArray(req.body)) return res.status(400).json({ error: 'kein JSON-Objekt' });
  const t = now();
  db.prepare(`INSERT INTO dopa_backups (user_id,data,updated_at) VALUES (?,?,?)
    ON CONFLICT(user_id) DO UPDATE SET data=excluded.data, updated_at=excluded.updated_at`)
    .run(req.user.id, JSON.stringify(req.body), t);
  res.json({ ok: true, updated_at: t });
});
/* ---------- Updates (Feedback #32): CI legt jede neue .ipa hier ab, die App fragt nach ---------- */
const RELEASE_DIR = process.env.RELEASE_DIR || path.join(__dirname, 'releases');
// Zwei Apps aus diesem Repo: Dopa (Standard) und die Claude-App
const RELEASE_APPS = { dopa: { prefix: 'Dopa', latest: 'latest.json' }, claude: { prefix: 'Claude', latest: 'latest-claude.json' } };
const releaseApp = id => RELEASE_APPS[id || 'dopa'] || null;
app.put('/api/dopa/release', express.raw({ type: '*/*', limit: '9mb' }), (req, res) => {
  const secret = process.env.DOPA_RELEASE_SECRET;
  if (!secret || req.get('x-release-secret') !== secret) return res.status(403).json({ error: 'nein' });
  const build = parseInt(req.query.build, 10);
  const rel = releaseApp(req.query.app);
  if (!rel) return res.status(400).json({ error: 'unbekannte App' });
  if (!Number.isInteger(build) || build < 1 || !Buffer.isBuffer(req.body) || req.body.length < 100_000) {
    return res.status(400).json({ error: 'keine gültige ipa' });
  }
  let notes = '';
  try { notes = decodeURIComponent(req.get('x-release-notes') || '').slice(0, 300); } catch {}
  fs.mkdirSync(RELEASE_DIR, { recursive: true });
  fs.writeFileSync(path.join(RELEASE_DIR, `${rel.prefix}-${build}.ipa`), req.body);
  fs.writeFileSync(path.join(RELEASE_DIR, rel.latest), JSON.stringify({ build, notes, at: Date.now() }));
  // nur die letzten drei Builds behalten
  const re = new RegExp('^' + rel.prefix + '-(\\d+)\\.ipa$');
  const old = fs.readdirSync(RELEASE_DIR).map(f => re.exec(f)).filter(Boolean)
    .map(m => Number(m[1])).sort((a, b) => b - a).slice(3);
  for (const n of old) fs.rmSync(path.join(RELEASE_DIR, `${rel.prefix}-${n}.ipa`), { force: true });
  res.json({ ok: true, build });
});

// CI-Protokolle: damit Claude auf dem Server Build-Fehler lesen kann (ohne GitHub-Login)
app.put('/api/dopa/ci-log', express.text({ type: '*/*', limit: '2mb' }), (req, res) => {
  const secret = process.env.DOPA_RELEASE_SECRET;
  if (!secret || req.get('x-release-secret') !== secret) return res.status(403).json({ error: 'nein' });
  const run = parseInt(req.query.run, 10);
  const job = ['build', 'ui', 'ipa'].includes(req.query.job) ? req.query.job : null;   // ipa = tools/ipa-check.py
  if (!Number.isInteger(run) || run < 1 || !job || typeof req.body !== 'string') return res.status(400).json({ error: 'kaputt' });
  const ok = req.query.ok === '1';
  fs.mkdirSync(RELEASE_DIR, { recursive: true });
  fs.writeFileSync(path.join(RELEASE_DIR, `ci-${run}-${job}.log`), req.body.slice(0, 2_000_000));
  fs.writeFileSync(path.join(RELEASE_DIR, `ci-latest-${job}.json`), JSON.stringify({ run, job, ok, at: Date.now() }));
  // nur die letzten 10 Protokolle behalten
  const logs = fs.readdirSync(RELEASE_DIR).map(f => /^ci-(\d+)-(build|ui|ipa)\.log$/.exec(f)).filter(Boolean)
    .sort((a, b) => Number(b[1]) - Number(a[1]));
  for (const m of logs.slice(10)) fs.rmSync(path.join(RELEASE_DIR, m[0]), { force: true });
  res.json({ ok: true });
});

app.get('/api/dopa/latest', (req, res) => {
  const rel = releaseApp(req.query.app) || releaseApp('dopa');
  let latest = { build: 0, notes: '', at: 0 };
  try { latest = JSON.parse(fs.readFileSync(path.join(RELEASE_DIR, rel.latest), 'utf8')); } catch {}
  const token = process.env.DOPA_DL_TOKEN;
  const host = process.env.PUBLIC_HOST || 'dopa.taubey.com';
  res.json({
    build: latest.build, notes: latest.notes || '', at: latest.at,
    url: token && latest.build ? `https://${host}/dl/${token}/${rel.prefix}-${latest.build}.ipa` : null,
    page: 'https://github.com/Taubeyyy/momentum/releases/latest'
  });
});

// Direkter Download für TrollStore (apple-magnifier://install?url=…) – geheimer Pfad statt Login
app.get('/dl/:token/:file', (req, res) => {
  const token = process.env.DOPA_DL_TOKEN;
  if (!token || req.params.token !== token || !/^(Dopa|Claude)-\d+\.ipa$/.test(req.params.file)) return res.status(404).end();
  const file = path.join(RELEASE_DIR, req.params.file);
  if (!fs.existsSync(file)) return res.status(404).end();
  res.setHeader('Content-Type', 'application/octet-stream');
  res.sendFile(file);
});

// Fotos, Screenshots und Sprache sind größer als normale Anfragen (nginx lässt 10 MB durch)
const smallJSON = express.json({ limit: '256kb' });
const mediaJSON = express.json({ limit: '10mb' });
const MEDIA_PATHS = new Set(['/api/dopa/photo/dump', '/api/dopa/photo/caption', '/api/dopa/money/scan', '/api/dopa/voice',
  '/api/dopa/chat', '/api/dopa/flyer']);   // Dot darf Fotos sehen (Wochenplan, Packliste), Prospekte
app.use((req, res, next) => (MEDIA_PATHS.has(req.path) ? mediaJSON : smallJSON)(req, res, next));

/* ---------- helpers ---------- */
const now = () => Date.now();
const clamp = (n, a, b) => Math.max(a, Math.min(b, Number(n) || 0));
const str = (v, max = 500) => String(v ?? '').slice(0, max);

function dayKey(ms, tz) {
  // lokales Datum YYYY-MM-DD in der User-Zeitzone
  try {
    return new Intl.DateTimeFormat('en-CA', { timeZone: tz || 'Europe/Berlin' }).format(new Date(ms));
  } catch { return new Date(ms).toISOString().slice(0, 10); }
}

function sign(res, user) {
  const token = jwt.sign({ uid: user.id }, JWT_SECRET, { expiresIn: '180d' });
  res.cookie(COOKIE, token, {
    httpOnly: true, sameSite: 'lax', secure: PROD,
    maxAge: 180 * 24 * 3600 * 1000, path: '/'
  });
  return token;
}

// Browser (PWA): Cookie. App (Dopa): Authorization: Bearer <token>
function auth(req, res, next) {
  const bearer = /^Bearer\s+(.+)$/i.exec(req.get('authorization') || '')?.[1];
  const t = bearer || req.cookies?.[COOKIE];
  if (!t) return res.status(401).json({ error: 'auth' });
  try {
    const { uid } = jwt.verify(t, JWT_SECRET);
    const u = db.prepare('SELECT * FROM users WHERE id=?').get(uid);
    if (!u) return res.status(401).json({ error: 'auth' });
    req.user = u;
    req.day = dayKey(now(), u.tz);
    next();
  } catch { res.status(401).json({ error: 'auth' }); }
}

const publicUser = (u) => ({
  id: u.id, email: u.email, name: u.name, tz: u.tz,
  settings: JSON.parse(u.settings || '{}')
});

/* ---------- auth ---------- */
app.post('/api/auth/register', (req, res) => {
  // Nach dem eigenen Account zumachen: REGISTRATION=closed in .env
  if (process.env.REGISTRATION === 'closed') return res.status(403).json({ error: 'Registrierung ist geschlossen' });
  const email = str(req.body?.email, 190).trim().toLowerCase();
  const pass = String(req.body?.password ?? '');
  const name = str(req.body?.name, 60).trim();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return res.status(400).json({ error: 'E-Mail ungültig' });
  if (pass.length < 8) return res.status(400).json({ error: 'Passwort braucht min. 8 Zeichen' });
  if (db.prepare('SELECT 1 FROM users WHERE email=?').get(email)) return res.status(409).json({ error: 'E-Mail existiert schon' });

  const info = db.prepare('INSERT INTO users (email,pass_hash,name,created_at) VALUES (?,?,?,?)')
    .run(email, bcrypt.hashSync(pass, 10), name || email.split('@')[0], now());
  const user = db.prepare('SELECT * FROM users WHERE id=?').get(info.lastInsertRowid);
  seedDefaults(user);
  const token = sign(res, user);
  res.json({ user: publicUser(user), token });
});

app.post('/api/auth/login', (req, res) => {
  const email = str(req.body?.email, 190).trim().toLowerCase();
  const pass = String(req.body?.password ?? '');
  const u = db.prepare('SELECT * FROM users WHERE email=?').get(email);
  if (!u || !bcrypt.compareSync(pass, u.pass_hash)) return res.status(401).json({ error: 'E-Mail oder Passwort falsch' });
  const token = sign(res, u);
  res.json({ user: publicUser(u), token });
});

app.post('/api/auth/logout', (req, res) => { res.clearCookie(COOKIE, { path: '/' }); res.json({ ok: true }); });

app.get('/api/me', auth, (req, res) => res.json({ user: publicUser(req.user), day: req.day, ai: ai.enabled(), ai_label: ai.describe() }));

app.patch('/api/me', auth, (req, res) => {
  const b = req.body || {};
  if (b.name !== undefined) db.prepare('UPDATE users SET name=? WHERE id=?').run(str(b.name, 60), req.user.id);
  if (b.tz !== undefined) db.prepare('UPDATE users SET tz=? WHERE id=?').run(str(b.tz, 60), req.user.id);
  if (b.settings !== undefined) db.prepare('UPDATE users SET settings=? WHERE id=?').run(JSON.stringify(b.settings).slice(0, 20000), req.user.id);
  const u = db.prepare('SELECT * FROM users WHERE id=?').get(req.user.id);
  res.json({ user: publicUser(u) });
});

/* ---------- Startpaket für neue Accounts ---------- */
function seedDefaults(user) {
  const t = now();
  const r = db.prepare('INSERT INTO routines (user_id,name,icon,when_at,sort) VALUES (?,?,?,?,?)')
    .run(user.id, 'Morgenroutine', '☀️', '07:30', 0);
  const ins = db.prepare('INSERT INTO routine_steps (routine_id,title,est_min,sort) VALUES (?,?,?,?)');
  [['Wasser trinken', 1], ['Meds nehmen', 1], ['Anziehen', 5], ['Kurz aufräumen', 5], ['Top-3 für heute festlegen', 3]]
    .forEach((s, i) => ins.run(r.lastInsertRowid, s[0], s[1], i));

  const r2 = db.prepare('INSERT INTO routines (user_id,name,icon,when_at,sort) VALUES (?,?,?,?,?)')
    .run(user.id, 'Abendroutine', '🌙', '22:00', 1);
  [['Handy weglegen', 1], ['Sachen für morgen rauslegen', 5], ['Inbox leeren', 5]]
    .forEach((s, i) => ins.run(r2.lastInsertRowid, s[0], s[1], i));

  const ih = db.prepare('INSERT INTO habits (user_id,name,icon,color,target_day,remind_at,sort,created_at) VALUES (?,?,?,?,?,?,?,?)');
  ih.run(user.id, 'Medikamente', '💊', '#ff8fa3', 1, '08:00', 0, t);
  ih.run(user.id, 'Wasser (8 Gläser)', '💧', '#6ee7ff', 8, '', 1, t);
  ih.run(user.id, 'Bewegung', '🏃', '#8ef0a8', 1, '', 2, t);
}

/* ---------- Tasks ---------- */
function taskTree(userId) {
  const rows = db.prepare('SELECT * FROM tasks WHERE user_id=? ORDER BY sort ASC, id ASC').all(userId);
  const byId = new Map(rows.map(r => [r.id, { ...r, starred: !!r.starred, subs: [] }]));
  const roots = [];
  for (const r of byId.values()) {
    if (r.parent_id && byId.has(r.parent_id)) byId.get(r.parent_id).subs.push(r);
    else if (!r.parent_id) roots.push(r);
  }
  return roots;
}

app.get('/api/tasks', auth, (req, res) => res.json({ tasks: taskTree(req.user.id) }));

app.post('/api/tasks', auth, (req, res) => {
  const b = req.body || {};
  const title = str(b.title, 300).trim();
  if (!title) return res.status(400).json({ error: 'Titel fehlt' });
  let parent = null;
  if (b.parent_id) {
    const p = db.prepare('SELECT id,parent_id FROM tasks WHERE id=? AND user_id=?').get(b.parent_id, req.user.id);
    if (!p) return res.status(404).json({ error: 'Parent nicht gefunden' });
    parent = p.parent_id ? p.parent_id : p.id; // max. 2 Ebenen
  }
  const sort = (db.prepare('SELECT COALESCE(MAX(sort),0)+1 s FROM tasks WHERE user_id=? AND parent_id IS ?').get(req.user.id, parent) || {}).s || 0;
  const info = db.prepare(`INSERT INTO tasks (user_id,parent_id,title,notes,energy,est_min,due_at,starred,sort,created_at)
    VALUES (?,?,?,?,?,?,?,?,?,?)`).run(
    req.user.id, parent, title, str(b.notes, 4000),
    ['low', 'med', 'high'].includes(b.energy) ? b.energy : 'med',
    clamp(b.est_min ?? 15, 1, 600), b.due_at ? Number(b.due_at) : null,
    b.starred ? 1 : 0, sort, now());
  res.json({ task: db.prepare('SELECT * FROM tasks WHERE id=?').get(info.lastInsertRowid) });
});

app.patch('/api/tasks/:id', auth, (req, res) => {
  const t = db.prepare('SELECT * FROM tasks WHERE id=? AND user_id=?').get(req.params.id, req.user.id);
  if (!t) return res.status(404).json({ error: 'not found' });
  const b = req.body || {};
  const set = [], val = [];
  const put = (col, v) => { set.push(col + '=?'); val.push(v); };
  if (b.title !== undefined) put('title', str(b.title, 300));
  if (b.notes !== undefined) put('notes', str(b.notes, 4000));
  if (b.energy !== undefined && ['low', 'med', 'high'].includes(b.energy)) put('energy', b.energy);
  if (b.est_min !== undefined) put('est_min', clamp(b.est_min, 1, 600));
  if (b.due_at !== undefined) put('due_at', b.due_at ? Number(b.due_at) : null);
  if (b.starred !== undefined) put('starred', b.starred ? 1 : 0);
  if (b.sort !== undefined) put('sort', Number(b.sort) || 0);
  if (b.status !== undefined) {
    const done = b.status === 'done';
    put('status', done ? 'done' : 'todo');
    put('completed_at', done ? now() : null);
    if (done) db.prepare("UPDATE tasks SET status='done', completed_at=? WHERE parent_id=? AND status!='done'").run(now(), t.id);
  }
  if (set.length) { val.push(t.id); db.prepare('UPDATE tasks SET ' + set.join(',') + ' WHERE id=?').run(...val); }
  res.json({ task: db.prepare('SELECT * FROM tasks WHERE id=?').get(t.id) });
});

app.delete('/api/tasks/:id', auth, (req, res) => {
  db.prepare('DELETE FROM tasks WHERE id=? AND user_id=?').run(req.params.id, req.user.id);
  res.json({ ok: true });
});

/* ---------- Fokus-Sessions ---------- */
app.post('/api/focus', auth, (req, res) => {
  const b = req.body || {};
  const started = Number(b.started_at) || now();
  const info = db.prepare(`INSERT INTO focus_sessions (user_id,task_id,label,mode,planned_sec,actual_sec,started_at,ended_at,completed,day)
    VALUES (?,?,?,?,?,?,?,?,?,?)`).run(
    req.user.id, b.task_id || null, str(b.label, 200),
    b.mode === 'break' ? 'break' : 'focus',
    clamp(b.planned_sec ?? 1500, 30, 4 * 3600),
    clamp(b.actual_sec ?? 0, 0, 8 * 3600),
    started, now(), b.completed ? 1 : 0, dayKey(started, req.user.tz));
  res.json({ id: info.lastInsertRowid });
});

app.get('/api/focus/stats', auth, (req, res) => {
  const days = clamp(req.query.days || 14, 1, 90);
  const rows = db.prepare(`SELECT day, SUM(actual_sec) sec, COUNT(*) n
     FROM focus_sessions WHERE user_id=? AND mode='focus' GROUP BY day ORDER BY day DESC LIMIT ?`)
    .all(req.user.id, days);
  const today = rows.find(r => r.day === req.day) || { day: req.day, sec: 0, n: 0 };
  res.json({ days: rows.reverse(), today });
});

/* ---------- Routinen ---------- */
app.get('/api/routines', auth, (req, res) => {
  const rs = db.prepare('SELECT * FROM routines WHERE user_id=? ORDER BY sort,id').all(req.user.id);
  const stepStmt = db.prepare('SELECT * FROM routine_steps WHERE routine_id=? ORDER BY sort,id');
  const checked = new Set(db.prepare('SELECT step_id FROM routine_checks WHERE user_id=? AND day=?')
    .all(req.user.id, req.day).map(r => r.step_id));
  res.json({
    routines: rs.map(r => ({
      ...r, active: !!r.active,
      steps: stepStmt.all(r.id).map(s => ({ ...s, done: checked.has(s.id) }))
    }))
  });
});

app.post('/api/routines', auth, (req, res) => {
  const b = req.body || {};
  const info = db.prepare('INSERT INTO routines (user_id,name,icon,when_at,sort) VALUES (?,?,?,?,?)')
    .run(req.user.id, str(b.name, 80) || 'Routine', str(b.icon, 8) || '✨', str(b.when_at, 5), Number(b.sort) || 0);
  res.json({ id: info.lastInsertRowid });
});

app.patch('/api/routines/:id', auth, (req, res) => {
  const r = db.prepare('SELECT * FROM routines WHERE id=? AND user_id=?').get(req.params.id, req.user.id);
  if (!r) return res.status(404).json({ error: 'not found' });
  const b = req.body || {};
  db.prepare('UPDATE routines SET name=?, icon=?, when_at=?, active=? WHERE id=?').run(
    b.name !== undefined ? str(b.name, 80) : r.name,
    b.icon !== undefined ? str(b.icon, 8) : r.icon,
    b.when_at !== undefined ? str(b.when_at, 5) : r.when_at,
    b.active !== undefined ? (b.active ? 1 : 0) : r.active, r.id);
  res.json({ ok: true });
});

app.delete('/api/routines/:id', auth, (req, res) => {
  db.prepare('DELETE FROM routines WHERE id=? AND user_id=?').run(req.params.id, req.user.id);
  res.json({ ok: true });
});

app.post('/api/routines/:id/steps', auth, (req, res) => {
  const r = db.prepare('SELECT id FROM routines WHERE id=? AND user_id=?').get(req.params.id, req.user.id);
  if (!r) return res.status(404).json({ error: 'not found' });
  const sort = (db.prepare('SELECT COALESCE(MAX(sort),0)+1 s FROM routine_steps WHERE routine_id=?').get(r.id) || {}).s || 0;
  const info = db.prepare('INSERT INTO routine_steps (routine_id,title,est_min,sort) VALUES (?,?,?,?)')
    .run(r.id, str(req.body?.title, 200) || 'Schritt', clamp(req.body?.est_min ?? 2, 1, 240), sort);
  res.json({ id: info.lastInsertRowid });
});

app.delete('/api/steps/:id', auth, (req, res) => {
  db.prepare('DELETE FROM routine_steps WHERE id=? AND routine_id IN (SELECT id FROM routines WHERE user_id=?)')
    .run(req.params.id, req.user.id);
  res.json({ ok: true });
});

app.post('/api/steps/:id/check', auth, (req, res) => {
  const s = db.prepare(`SELECT s.id FROM routine_steps s JOIN routines r ON r.id=s.routine_id
    WHERE s.id=? AND r.user_id=?`).get(req.params.id, req.user.id);
  if (!s) return res.status(404).json({ error: 'not found' });
  if (req.body?.done === false) db.prepare('DELETE FROM routine_checks WHERE step_id=? AND day=?').run(s.id, req.day);
  else db.prepare('INSERT OR REPLACE INTO routine_checks (user_id,step_id,day,done_at) VALUES (?,?,?,?)')
    .run(req.user.id, s.id, req.day, now());
  res.json({ ok: true });
});

/* ---------- Habits ---------- */
app.get('/api/habits', auth, (req, res) => {
  const hs = db.prepare('SELECT * FROM habits WHERE user_id=? AND active=1 ORDER BY sort,id').all(req.user.id);
  const logStmt = db.prepare('SELECT day,count FROM habit_logs WHERE habit_id=? ORDER BY day DESC LIMIT 30');
  const todayStmt = db.prepare('SELECT count FROM habit_logs WHERE habit_id=? AND day=?');
  res.json({
    habits: hs.map(h => ({
      ...h, active: !!h.active,
      today: (todayStmt.get(h.id, req.day) || { count: 0 }).count,
      history: logStmt.all(h.id)
    })), day: req.day
  });
});

app.post('/api/habits', auth, (req, res) => {
  const b = req.body || {};
  const info = db.prepare(`INSERT INTO habits (user_id,name,icon,color,target_day,remind_at,sort,created_at)
    VALUES (?,?,?,?,?,?,?,?)`).run(req.user.id, str(b.name, 80) || 'Habit', str(b.icon, 8) || '✅',
    str(b.color, 16) || '#7c9cff', clamp(b.target_day ?? 1, 1, 30), str(b.remind_at, 5),
    Number(b.sort) || 0, now());
  res.json({ id: info.lastInsertRowid });
});

app.patch('/api/habits/:id', auth, (req, res) => {
  const h = db.prepare('SELECT * FROM habits WHERE id=? AND user_id=?').get(req.params.id, req.user.id);
  if (!h) return res.status(404).json({ error: 'not found' });
  const b = req.body || {};
  db.prepare('UPDATE habits SET name=?, icon=?, color=?, target_day=?, remind_at=?, active=? WHERE id=?').run(
    b.name !== undefined ? str(b.name, 80) : h.name,
    b.icon !== undefined ? str(b.icon, 8) : h.icon,
    b.color !== undefined ? str(b.color, 16) : h.color,
    b.target_day !== undefined ? clamp(b.target_day, 1, 30) : h.target_day,
    b.remind_at !== undefined ? str(b.remind_at, 5) : h.remind_at,
    b.active !== undefined ? (b.active ? 1 : 0) : h.active, h.id);
  res.json({ ok: true });
});

app.delete('/api/habits/:id', auth, (req, res) => {
  db.prepare('DELETE FROM habits WHERE id=? AND user_id=?').run(req.params.id, req.user.id);
  res.json({ ok: true });
});

app.post('/api/habits/:id/log', auth, (req, res) => {
  const h = db.prepare('SELECT * FROM habits WHERE id=? AND user_id=?').get(req.params.id, req.user.id);
  if (!h) return res.status(404).json({ error: 'not found' });
  const delta = clamp(req.body?.delta ?? 1, -30, 30);
  const cur = (db.prepare('SELECT count FROM habit_logs WHERE habit_id=? AND day=?').get(h.id, req.day) || { count: 0 }).count;
  const next = Math.max(0, Math.min(99, cur + delta));
  db.prepare('INSERT OR REPLACE INTO habit_logs (habit_id,user_id,day,count) VALUES (?,?,?,?)')
    .run(h.id, req.user.id, req.day, next);
  res.json({ count: next });
});

/* ---------- Inbox / Brain Dump ---------- */
app.get('/api/inbox', auth, (req, res) => {
  res.json({ items: db.prepare('SELECT * FROM inbox WHERE user_id=? AND archived=0 ORDER BY id DESC LIMIT 300').all(req.user.id) });
});

app.post('/api/inbox', auth, (req, res) => {
  const text = str(req.body?.text, 2000).trim();
  if (!text) return res.status(400).json({ error: 'leer' });
  const info = db.prepare('INSERT INTO inbox (user_id,text,created_at) VALUES (?,?,?)').run(req.user.id, text, now());
  res.json({ item: db.prepare('SELECT * FROM inbox WHERE id=?').get(info.lastInsertRowid) });
});

app.post('/api/inbox/:id/convert', auth, (req, res) => {
  const it = db.prepare('SELECT * FROM inbox WHERE id=? AND user_id=? AND archived=0').get(req.params.id, req.user.id);
  if (!it) return res.status(404).json({ error: 'not found' });
  const sort = (db.prepare('SELECT COALESCE(MAX(sort),0)+1 s FROM tasks WHERE user_id=? AND parent_id IS NULL').get(req.user.id) || {}).s || 0;
  const info = db.prepare('INSERT INTO tasks (user_id,title,sort,created_at) VALUES (?,?,?,?)')
    .run(req.user.id, it.text.slice(0, 300), sort, now());
  db.prepare('UPDATE inbox SET archived=1, task_id=? WHERE id=?').run(info.lastInsertRowid, it.id);
  res.json({ task_id: info.lastInsertRowid });
});

app.delete('/api/inbox/:id', auth, (req, res) => {
  db.prepare('UPDATE inbox SET archived=1 WHERE id=? AND user_id=?').run(req.params.id, req.user.id);
  res.json({ ok: true });
});

/* ---------- Mood ---------- */
app.get('/api/moods', auth, (req, res) => {
  const days = clamp(req.query.days || 30, 1, 180);
  res.json({ moods: db.prepare('SELECT * FROM moods WHERE user_id=? ORDER BY ts DESC LIMIT ?').all(req.user.id, days * 4) });
});

app.post('/api/moods', auth, (req, res) => {
  const b = req.body || {};
  const info = db.prepare('INSERT INTO moods (user_id,ts,day,mood,energy,focus,note) VALUES (?,?,?,?,?,?,?)')
    .run(req.user.id, now(), req.day, clamp(b.mood ?? 3, 1, 5), clamp(b.energy ?? 3, 1, 5), clamp(b.focus ?? 3, 1, 5), str(b.note, 500));
  res.json({ id: info.lastInsertRowid });
});

/* ---------- Tagesübersicht ---------- */
app.get('/api/today', auth, (req, res) => {
  const uid = req.user.id, day = req.day;
  const focus = db.prepare("SELECT COALESCE(SUM(actual_sec),0) sec, COUNT(*) n FROM focus_sessions WHERE user_id=? AND day=? AND mode='focus'").get(uid, day);
  const dayStart = new Date(day + 'T00:00:00').getTime();
  const done = db.prepare("SELECT COUNT(*) n FROM tasks WHERE user_id=? AND status='done' AND completed_at>=?").get(uid, dayStart);
  const steps = db.prepare('SELECT COUNT(*) n FROM routine_checks WHERE user_id=? AND day=?').get(uid, day);
  const mood = db.prepare('SELECT * FROM moods WHERE user_id=? AND day=? ORDER BY ts DESC LIMIT 1').get(uid, day) || null;
  res.json({ day, focus_sec: focus.sec, focus_n: focus.n, tasks_done: done.n, routine_steps: steps.n, mood });
});

/* ================= KI-Helfer =================
   Alle Aufrufe laufen serverseitig, der API-Key bleibt hier.
   Ohne Key antworten die Endpunkte mit 503 und der Client versteckt die Buttons. */

// Einfache Bremse gegen Endlosschleifen und Kostenausreißer: 60 Aufrufe/Stunde/User
const aiHits = new Map();
const AI_DAILY_LIMIT = Number(process.env.AI_DAILY_LIMIT || 400);
let aiDay = '', aiDayCount = 0;
function aiLimit(req, res, next) {
  if (!ai.enabled()) return res.status(503).json({ error: 'no_key', message: 'KI ist auf diesem Server nicht eingerichtet.' });
  const today = new Date().toISOString().slice(0, 10);
  if (today !== aiDay) { aiDay = today; aiDayCount = 0; }
  if (++aiDayCount > AI_DAILY_LIMIT) return res.status(429).json({ error: 'rate', message: 'Für heute sind die KI-Anfragen aufgebraucht.' });
  const hour = Math.floor(Date.now() / 3600000);
  const key = req.user.id + ':' + hour;
  const n = (aiHits.get(key) || 0) + 1;
  aiHits.set(key, n);
  if (aiHits.size > 500) for (const k of aiHits.keys()) if (!k.endsWith(':' + hour)) aiHits.delete(k);
  if (n > 60) return res.status(429).json({ error: 'rate', message: 'Viele KI-Anfragen in kurzer Zeit — probier es in einer Stunde nochmal.' });
  next();
}

function aiFail(res, e) {
  if (e.code === 'no_key') return res.status(503).json({ error: 'no_key', message: 'KI ist nicht eingerichtet.' });
  console.error('[ai]', e.message);
  res.status(502).json({ error: 'ai', message: 'Die KI hat gerade nicht geantwortet. Nochmal versuchen?' });
}

const getTask = (id, uid) => db.prepare('SELECT * FROM tasks WHERE id=? AND user_id=?').get(id, uid);

// 1. Aufgabe zerlegen — legt die Schritte direkt als Unteraufgaben an
app.post('/api/ai/breakdown', auth, aiLimit, async (req, res) => {
  const t = getTask(req.body?.task_id, req.user.id);
  if (!t) return res.status(404).json({ error: 'not found' });
  const parent = t.parent_id || t.id;
  try {
    const { data } = await ai.breakdown({
      title: t.title, notes: t.notes,
      resolution: clamp(req.body?.resolution ?? 3, 1, 5), energy: t.energy
    });
    const ins = db.prepare('INSERT INTO tasks (user_id,parent_id,title,est_min,sort,created_at) VALUES (?,?,?,?,?,?)');
    let sort = (db.prepare('SELECT COALESCE(MAX(sort),0) s FROM tasks WHERE parent_id=?').get(parent) || {}).s || 0;
    const created = db.transaction(steps => steps.map(s =>
      ins.run(req.user.id, parent, str(s.title, 300), clamp(s.est_min ?? 5, 1, 240), ++sort, now()).lastInsertRowid
    ))(data.steps);
    res.json({ opener: data.opener, count: created.length });
  } catch (e) { aiFail(res, e); }
});

// 2. Dauer schätzen
app.post('/api/ai/estimate', auth, aiLimit, async (req, res) => {
  const t = getTask(req.body?.task_id, req.user.id);
  if (!t) return res.status(404).json({ error: 'not found' });
  try {
    const { data } = await ai.estimate({ title: t.title, notes: t.notes });
    db.prepare('UPDATE tasks SET est_min=? WHERE id=?').run(data.est_min, t.id);
    res.json(data);
  } catch (e) { aiFail(res, e); }
});

// 3. Brain Dump sortieren — optional gleich die ganze Inbox
app.post('/api/ai/compile', auth, aiLimit, async (req, res) => {
  let text = str(req.body?.text, 6000).trim();
  let items = [];
  if (req.body?.use_inbox) {
    items = db.prepare('SELECT * FROM inbox WHERE user_id=? AND archived=0 ORDER BY id').all(req.user.id);
    text = [text, ...items.map(i => i.text)].filter(Boolean).join('\n');
  }
  if (!text) return res.status(400).json({ error: 'leer' });
  try {
    const { data } = await ai.compile({ text });
    const insT = db.prepare('INSERT INTO tasks (user_id,title,energy,est_min,sort,created_at) VALUES (?,?,?,?,?,?)');
    const insS = db.prepare('INSERT INTO tasks (user_id,parent_id,title,est_min,sort,created_at) VALUES (?,?,?,?,?,?)');
    let sort = (db.prepare('SELECT COALESCE(MAX(sort),0) s FROM tasks WHERE user_id=? AND parent_id IS NULL').get(req.user.id) || {}).s || 0;
    const made = db.transaction(tasks => {
      const out = [];
      for (const t of tasks) {
        const id = insT.run(req.user.id, str(t.title, 300),
          ['low', 'med', 'high'].includes(t.energy) ? t.energy : 'med',
          clamp(t.est_min ?? 15, 1, 480), ++sort, now()).lastInsertRowid;
        (t.subs || []).forEach((s, i) => insS.run(req.user.id, id, str(s, 300), 5, i, now()));
        out.push(id);
      }
      if (items.length) {
        const arch = db.prepare('UPDATE inbox SET archived=1 WHERE id=?');
        items.forEach(i => arch.run(i.id));
      }
      return out;
    })(data.tasks);
    res.json({ count: made.length, notes: data.notes || '' });
  } catch (e) { aiFail(res, e); }
});

// 4. Text umschreiben
app.post('/api/ai/rewrite', auth, aiLimit, async (req, res) => {
  const text = str(req.body?.text, 6000).trim();
  if (!text) return res.status(400).json({ error: 'leer' });
  try {
    const { data } = await ai.rewrite({ text, mode: str(req.body?.mode, 30) });
    res.json(data);
  } catch (e) { aiFail(res, e); }
});

// 5. Empfangene Nachricht einordnen
app.post('/api/ai/interpret', auth, aiLimit, async (req, res) => {
  const text = str(req.body?.text, 6000).trim();
  if (!text) return res.status(400).json({ error: 'leer' });
  try {
    const { data } = await ai.interpret({ text });
    res.json(data);
  } catch (e) { aiFail(res, e); }
});

// 6. Was jetzt? — Auswahl passend zum aktuellen Zustand
app.post('/api/ai/next', auth, aiLimit, async (req, res) => {
  const rows = db.prepare("SELECT * FROM tasks WHERE user_id=? AND status='todo'").all(req.user.id);
  const byId = new Map(rows.map(r => [r.id, r]));
  const hasOpenSub = new Set(rows.filter(r => r.parent_id).map(r => r.parent_id));
  const pool = rows.filter(r => !hasOpenSub.has(r.id))
    .map(r => ({ ...r, parentTitle: r.parent_id ? byId.get(r.parent_id)?.title : null }))
    .slice(0, 60);
  if (!pool.length) return res.json({ empty: true });

  const mood = db.prepare('SELECT * FROM moods WHERE user_id=? AND day=? ORDER BY ts DESC LIMIT 1').get(req.user.id, req.day);
  const fs = db.prepare("SELECT COALESCE(SUM(actual_sec),0) s FROM focus_sessions WHERE user_id=? AND day=? AND mode='focus'").get(req.user.id, req.day);
  try {
    const { data } = await ai.whatNow({
      tasks: pool, mood, focusToday: fs.s,
      hour: new Date().toLocaleString('de-DE', { timeZone: req.user.tz, hour: '2-digit', hour12: false })
    });
    const picked = pool.find(t => t.id === data.task_id) || pool[0];
    res.json({ ...data, task_id: picked.id, title: picked.title });
  } catch (e) { aiFail(res, e); }
});

// 7. Wiedereinstieg nach Unterbrechung
app.post('/api/ai/reentry', auth, aiLimit, async (req, res) => {
  let t = getTask(req.body?.task_id, req.user.id);
  if (!t) {
    const last = db.prepare(`SELECT task_id FROM focus_sessions WHERE user_id=? AND task_id IS NOT NULL
      ORDER BY id DESC LIMIT 1`).get(req.user.id);
    if (last) t = getTask(last.task_id, req.user.id);
  }
  if (!t) return res.status(404).json({ error: 'not found' });

  const root = t.parent_id ? getTask(t.parent_id, req.user.id) : t;
  const subs = db.prepare('SELECT * FROM tasks WHERE parent_id=?').all(root.id);
  const lastSession = db.prepare('SELECT ended_at FROM focus_sessions WHERE user_id=? AND task_id IN (?,?) ORDER BY id DESC LIMIT 1')
    .get(req.user.id, t.id, root.id);
  try {
    const { data } = await ai.reentry({
      title: root.title, notes: root.notes,
      doneSteps: subs.filter(s => s.status === 'done').map(s => s.title),
      openSteps: subs.filter(s => s.status !== 'done').map(s => s.title),
      minutesAgo: lastSession ? Math.round((now() - lastSession.ended_at) / 60000) : 0
    });
    res.json({ ...data, task_id: root.id, title: root.title });
  } catch (e) { aiFail(res, e); }
});

// Womit der Client arbeiten kann
app.get('/api/ai/status', auth, (req, res) => res.json({
  enabled: ai.enabled(), modes: Object.keys(ai.MODES), resolutions: ai.RESOLUTION
}));

/* ================= Dopa (iOS) =================
   Zustandslos: die App schickt Text, bekommt Struktur. Daten bleiben in der App,
   der Server hält nur Feedback und das Backup. */

// ---------- Claude auf dem Server: Projekte, Feedback, Aufträge, Limits (für die Claude-App) – siehe hub.js
require('./hub')(app, { db, auth, express, str, clamp, RELEASE_DIR });

app.get('/api/dopa/status', auth, (req, res) => {
  const b = db.prepare('SELECT updated_at FROM dopa_backups WHERE user_id=?').get(req.user.id);
  res.json({ ai: ai.enabled(), ai_label: ai.describe(), backup_at: b?.updated_at ?? null, user: publicUser(req.user) });
});

app.post('/api/dopa/step', auth, aiLimit, async (req, res) => {
  const title = str(req.body?.title, 300).trim();
  if (!title) return res.status(400).json({ error: 'leer' });
  try {
    const { data, provider } = await ai.firstStep({ title });
    res.json({ step: str(data.step, 200), provider });
  } catch (e) { aiFail(res, e); }
});

app.post('/api/dopa/plan', auth, aiLimit, async (req, res) => {
  const text = str(req.body?.text, 4000).trim();
  if (!text) return res.status(400).json({ error: 'leer' });
  try {
    const scope = ['task', 'day', 'week'].includes(req.body?.scope) ? req.body.scope : 'auto';
    const { data, provider } = await ai.plan({ text, scope });
    const tasks = (data.tasks || []).slice(0, 8).map(t => ({
      title: str(t.title, 120), step: str(t.step, 200), minutes: clamp(t.minutes ?? 15, 1, 480)
    })).filter(t => t.title);
    res.json({ summary: str(data.summary, 300), tasks, note: str(data.note, 300), provider });
  } catch (e) { aiFail(res, e); }
});

app.post('/api/dopa/breakdown', auth, aiLimit, async (req, res) => {
  const title = str(req.body?.title, 300).trim();
  if (!title) return res.status(400).json({ error: 'leer' });
  try {
    const { data, provider } = await ai.breakdown({ title, resolution: clamp(req.body?.resolution ?? 4, 1, 5) });
    res.json({ steps: (data.steps || []).map(s => ({ title: str(s.title, 200), minutes: clamp(s.est_min ?? 5, 1, 240) })),
      opener: str(data.opener, 300), provider });
  } catch (e) { aiFail(res, e); }
});

// Worte: „Wie ist das gemeint?“ für empfangene Nachrichten
app.post('/api/dopa/interpret', auth, aiLimit, async (req, res) => {
  const text = str(req.body?.text, 4000).trim();
  if (!text) return res.status(400).json({ error: 'leer' });
  try {
    const { data, provider } = await ai.interpret({ text });
    res.json({
      literal: str(data.literal, 600), tone: str(data.tone, 200), temperature: clamp(data.temperature ?? 3, 1, 5),
      overthinking: str(data.overthinking, 600), reply: str(data.reply, 800), provider
    });
  } catch (e) { aiFail(res, e); }
});

// Worte: eigene Nachricht umschreiben
app.post('/api/dopa/rewrite', auth, aiLimit, async (req, res) => {
  const text = str(req.body?.text, 4000).trim();
  const mode = str(req.body?.mode, 30);
  if (!text) return res.status(400).json({ error: 'leer' });
  try {
    const { data, provider } = await ai.rewrite({ text, mode });
    res.json({ result: str(data.result, 4000), changed: str(data.changed, 300), provider });
  } catch (e) { aiFail(res, e); }
});

// Dot: kurze Antwort vom Assistenten, mit den offenen Aufgaben als Kontext
app.post('/api/dopa/ask', auth, aiLimit, async (req, res) => {
  const question = str(req.body?.question, 1500).trim();
  if (!question) return res.status(400).json({ error: 'leer' });
  const tasks = (Array.isArray(req.body?.tasks) ? req.body.tasks : []).slice(0, 15).map(t => str(t, 120)).filter(Boolean);
  const mood = str(req.body?.mood, 40);
  const context = [
    tasks.length ? `Offene Aufgaben: ${tasks.join('; ')}` : 'Keine offenen Aufgaben.',
    mood ? `Check-in heute: ${mood}` : '',
    `Uhrzeit: ${new Date().toLocaleTimeString('de-DE', { timeZone: 'Europe/Berlin', hour: '2-digit', minute: '2-digit' })}`
  ].filter(Boolean).join('\n');
  try {
    const { data, provider } = await ai.dotAnswer({
      question, name: str(req.body?.name, 30), level: clamp(req.body?.level ?? 1, 1, 99), context
    });
    res.json({ answer: str(data.answer, 1200), provider });
  } catch (e) { aiFail(res, e); }
});

// Dot im Gespräch: Verlauf + Tageskontext aus der App, Antwort mit Vorschlägen zum Antippen
app.post('/api/dopa/chat', auth, aiLimit, async (req, res) => {
  const message = str(req.body?.message, 1500).trim();
  if (!message) return res.status(400).json({ error: 'leer' });
  const history = (Array.isArray(req.body?.history) ? req.body.history : []).slice(-12)
    .map(m => ({ fromDot: !!m?.fromDot, text: str(m?.text, 800).trim() })).filter(m => m.text);
  const now = berlinLabel();
  const context = [`Jetzt: ${now}`, str(req.body?.context, 5000).trim()].filter(Boolean).join('\n');
  // optional ein Foto (Wochenplan, Packliste …) – nur Gemini kann Bilder
  const photo = req.body?.image ? mediaImage(req.body) : null;
  if (req.body?.image && !photo) return res.status(400).json({ error: 'Foto kaputt' });
  const media = photo ? [{ kind: 'image', mime: photo.mime, data: photo.image }] : undefined;
  try {
    const { data, provider } = await ai.dotChat({
      name: str(req.body?.name, 30), level: clamp(req.body?.level ?? 1, 1, 99), context, history, message, media
    });
    res.json({ ...cleanDotChat(data), provider });
  } catch (e) { aiFail(res, e); }
});

const DOT_KINDS = ['task', 'reminder', 'shop', 'memo', 'focus', 'done', 'tomorrow', 'steps', 'schedule', 'setting', 'edit'];
// Was Dot an der App ändern darf (kind „edit“, Feld key) – gleiche Liste wie DotEdit in der App
const DOT_EDITS = ['morning.leave', 'morning.days', 'morning.add', 'morning.remove', 'evening.bed', 'evening.days',
  'evening.add', 'evening.remove', 'meals.times', 'nudges.window', 'reminder.time', 'reminder.delete', 'habit.add',
  'habit.remove', 'habit.time', 'task.rename', 'task.delete', 'task.plan', 'task.time', 'shop.remove',
  'timer.presets', 'snooze', 'theme', 'dot.name', 'memo.delete', 'chat.clear', 'shop.clear'];
// Was Dot in der App einstellen darf (kind „setting“): title = einer davon, step = on/off
const DOT_SETTINGS = ['morning', 'evening', 'nudges', 'meals', 'briefing', 'review', 'countdown', 'halfway'];

function cleanDotChat(data) {
  const time = t => /^([01]?\d|2[0-3]):[0-5]\d$/.test(String(t || '').trim()) ? String(t).trim().padStart(5, '0') : '';
  // Termine eines Plans (z. B. Seminar-Woche vom Foto): Titel, Tag 0–13, Uhrzeit Pflicht
  const entries = list => (Array.isArray(list) ? list : []).map(e => ({
    title: str(e?.title, 120).trim(),
    day: clamp(Number.isInteger(e?.day) ? e.day : 0, 0, 13),
    time: time(e?.time),
    minutes: clamp(Number.isInteger(e?.minutes) && e.minutes > 0 ? e.minutes : 60, 5, 600)
  })).filter(e => e.title && e.time).slice(0, 30);
  const actions = (Array.isArray(data?.actions) ? data.actions : []).slice(0, 10).map(a => ({
    kind: DOT_KINDS.includes(a?.kind) ? a.kind : '',
    title: str(a?.title, 120).trim(),
    step: str(a?.step, 200).trim(),
    time: time(a?.time),
    day: clamp(Number.isInteger(a?.day) ? a.day : 0, 0, 13),
    minutes: clamp(Number.isInteger(a?.minutes) && a.minutes > 0 ? a.minutes : 10, 1, 90),
    items: (Array.isArray(a?.items) ? a.items : []).map(s => str(s, 80).trim()).filter(Boolean).slice(0, 15),
    entries: entries(a?.entries),
    place: str(a?.place, 60).trim(),      // Ort: Aufgabe meldet sich beim Ankommen
    key: str(a?.key, 40).trim()           // edit: was geändert wird
  })).filter(a => a.kind && (a.title || a.kind === 'edit') && (a.kind !== 'reminder' || a.time) && (a.kind !== 'steps' || a.items.length)
    && (a.kind !== 'schedule' || a.entries.length)
    && (a.kind !== 'setting' || (DOT_SETTINGS.includes(a.title) && ['on', 'off'].includes(a.step)))
    && (a.kind !== 'edit' || DOT_EDITS.includes(a.key)))
    .slice(0, 4);
  const suggestions = (Array.isArray(data?.suggestions) ? data.suggestions : [])
    .map(s => str(s, 60).trim()).filter(Boolean).slice(0, 3);
  return { answer: str(data?.answer, 1500).trim(), actions, suggestions };
}

// Smart Dump: Erzähltes automatisch in Aufgaben / Erinnerungen / Einkauf / Merken sortieren
app.post('/api/dopa/dump', auth, aiLimit, async (req, res) => {
  const text = str(req.body?.text, 6000).trim();
  if (!text) return res.status(400).json({ error: 'leer' });
  const todayLabel = berlinLabel();
  try {
    const { data, provider } = await ai.dump({ text, todayLabel });
    res.json(cleanDump(data, provider));
  } catch (e) { aiFail(res, e); }
});

function berlinLabel() {
  return new Date().toLocaleString('de-DE', {
    timeZone: 'Europe/Berlin', weekday: 'long', day: 'numeric', month: 'long', year: 'numeric',
    hour: '2-digit', minute: '2-digit'
  }) + ' Uhr';
}

function cleanDump(data, provider) {
    const day = (d, fallback) => Number.isInteger(d) && d >= -1 && d <= 13 ? d : fallback;
    const time = t => /^([01]?\d|2[0-3]):[0-5]\d$/.test(String(t || '').trim()) ? String(t).trim().padStart(5, '0') : null;
    return {
      summary: str(data.summary, 300),
      tasks: (data.tasks || []).map(t => ({
        title: str(t.title, 120), step: str(t.step, 200), minutes: clamp(t.minutes ?? 15, 1, 480), day: day(t.day, -1)
      })).filter(t => t.title),
      reminders: (data.reminders || []).map(r => ({ title: str(r.title, 120), time: time(r.time), day: day(r.day, 0) }))
        .filter(r => r.title && r.time),
      shopping: (data.shopping || []).map(s => str(s, 80).trim()).filter(Boolean),
      notes: (data.notes || []).map(n => str(n, 300).trim()).filter(Boolean),
      schedule: (data.schedule || []).map(b => ({
        start: time(b.start), title: str(b.title, 120), step: str(b.step, 200),
        minutes: clamp(b.minutes ?? 15, 5, 240), day: day(b.day, 0)
      })).filter(b => b.title && b.start),
      provider
    };
}

/* Bild aus der App: Base64-JPEG/PNG, nichts anderes. */
function mediaImage(body) {
  const image = String(body?.image || '');
  const mime = ['image/jpeg', 'image/png'].includes(body?.mime) ? body.mime : 'image/jpeg';
  if (image.length < 100 || image.length > 9_500_000 || !/^[A-Za-z0-9+/=]+$/.test(image.slice(0, 200))) return null;
  return { image, mime };
}

// Foto statt Tippen: Zettel, Brief, Kühlschrank → wie Smart Dump
app.post('/api/dopa/photo/dump', auth, aiLimit, async (req, res) => {
  const media = mediaImage(req.body);
  if (!media) return res.status(400).json({ error: 'kein Bild' });
  try {
    const { data, provider } = await ai.photoDump({ ...media, todayLabel: berlinLabel(), hint: str(req.body?.hint, 200) });
    res.json(cleanDump(data, provider));
  } catch (e) { aiFail(res, e); }
});

// Notiz-Foto: kurzer Satz, was drauf ist
app.post('/api/dopa/photo/caption', auth, aiLimit, async (req, res) => {
  const media = mediaImage(req.body);
  if (!media) return res.status(400).json({ error: 'kein Bild' });
  try {
    const { data, provider } = await ai.photoCaption({ ...media, todayLabel: berlinLabel() });
    const kind = ['place', 'done', 'agreement', 'note'].includes(data.kind) ? data.kind : 'note';
    // Auftrag auf dem Foto (z. B. Zettel einer Lehrkraft) → Vorschlag „Auch als Aufgabe?“
    const day = Number.isInteger(data.day) ? clamp(data.day, -1, 13) : -1;
    res.json({ caption: str(data.caption, 140).trim(), kind, task: str(data.task, 80).trim(), day, provider });
  } catch (e) { aiFail(res, e); }
});

// Screenshot aus Bank/Klarna → Buchungen, offene Raten, Tipps
app.post('/api/dopa/money/scan', auth, aiLimit, async (req, res) => {
  const media = mediaImage(req.body);
  if (!media) return res.status(400).json({ error: 'kein Bild' });
  const isDate = d => /^\d{4}-\d{2}-\d{2}$/.test(String(d || '')) && !isNaN(Date.parse(d));
  const today = dayKey(now());
  const money = v => { const n = Math.round(Math.abs(Number(v)) * 100) / 100; return Number.isFinite(n) && n > 0 && n <= 100000 ? n : null; };
  try {
    const { data, provider } = await ai.moneyScan({ ...media, todayLabel: berlinLabel(), known: str(req.body?.known, 1500) });
    res.json({
      entries: (data.entries || []).map(e => ({
        title: str(e.title, 80).trim(), amount: money(e.amount), income: e.income === true, date: isDate(e.date) ? e.date : today
      })).filter(e => e.title && e.amount),
      debts: (data.debts || []).map(d => ({
        title: str(d.title, 80).trim(), amount: money(d.amount), due: isDate(d.due) ? d.due : today,
        remaining: clamp(d.remaining ?? 1, 1, 36)
      })).filter(d => d.title && d.amount),
      tips: (data.tips || []).map(t => str(t, 200).trim()).filter(Boolean).slice(0, 3),
      // Kontostand (z. B. Sparkasse: die große Zahl oben) – darf auch negativ sein
      balance: data.hasBalance === true && Number.isFinite(Number(data.balance)) && Math.abs(Number(data.balance)) <= 1000000
        ? Math.sign(Number(data.balance)) * Math.round(Math.abs(Number(data.balance)) * 100) / 100 : null,
      account: str(data.account, 60).trim(),
      provider
    });
  } catch (e) { aiFail(res, e); }
});

// Geld-Tipps aus dem Tagebuch dieses Monats
// Prospekt-Foto → Angebote mit Preis und Gültigkeit
app.post('/api/dopa/flyer', auth, aiLimit, async (req, res) => {
  const media = mediaImage(req.body);
  if (!media) return res.status(400).json({ error: 'kein Bild' });
  const isDate = d => /^\d{4}-\d{2}-\d{2}$/.test(String(d || '')) && !isNaN(Date.parse(d));
  try {
    const { data, provider } = await ai.flyerScan({ ...media, todayLabel: berlinLabel() });
    const price = v => { const n = Math.round(Number(v) * 100) / 100; return Number.isFinite(n) && n > 0 && n < 10000 ? n : 0; };
    res.json({
      store: str(data.store, 40).trim(),
      validFrom: isDate(data.validFrom) ? data.validFrom : '',
      validTo: isDate(data.validTo) ? data.validTo : '',
      offers: (data.offers || []).map(o => ({
        name: str(o.name, 80).trim(), price: price(o.price), unit: str(o.unit, 30).trim(), note: str(o.note, 40).trim()
      })).filter(o => o.name).slice(0, 80),
      provider
    });
  } catch (e) { aiFail(res, e); }
});

// Barcode (EAN) → Produktname (Open Food Facts), kurz zwischengespeichert
const productCache = new Map();
app.post('/api/dopa/barcode', auth, async (req, res) => {
  const code = String(req.body?.code || '').trim();
  if (!/^\d{8,14}$/.test(code)) return res.status(400).json({ error: 'kein Barcode' });
  try {
    if (!productCache.has(code)) {
      productCache.set(code, await ai.productLookup(code));
      if (productCache.size > 500) productCache.delete(productCache.keys().next().value);
    }
    const p = productCache.get(code);
    if (!p) return res.json({ found: false });
    const name = str(p.brand && !p.name.toLowerCase().includes(p.brand.toLowerCase()) ? `${p.brand} ${p.name}` : p.name, 80).trim();
    res.json({ found: true, name, quantity: str(p.quantity, 30) });
  } catch (e) {
    productCache.delete(code);
    res.json({ found: false });
  }
});

app.post('/api/dopa/money/tips', auth, aiLimit, async (req, res) => {
  const summary = str(req.body?.summary, 3000).trim();
  if (!summary) return res.status(400).json({ error: 'leer' });
  try {
    const { data, provider } = await ai.moneyTips({ summary });
    res.json({ tips: (data.tips || []).map(t => str(t, 200).trim()).filter(Boolean).slice(0, 3), provider });
  } catch (e) { aiFail(res, e); }
});

// Sprache: Gemini schreibt die Aufnahme ab (WAV, Base64)
app.post('/api/dopa/voice', auth, aiLimit, async (req, res) => {
  const audio = String(req.body?.audio || '');
  if (audio.length < 1000 || audio.length > 9_800_000) return res.status(400).json({ error: 'keine Aufnahme' });
  const format = ['wav', 'mp3', 'aac', 'flac', 'ogg'].includes(req.body?.format) ? req.body.format : 'wav';
  const hints = (Array.isArray(req.body?.hints) ? req.body.hints : []).map(h => str(h, 60)).filter(Boolean).slice(0, 40).join(', ');
  try {
    const { data, provider } = await ai.transcribe({ audio, format, hints });
    res.json({ transcript: str(data.transcript, 8000).trim(), provider });
  } catch (e) { aiFail(res, e); }
});

// Einkauf: unbekannte Einträge einem Gang zuordnen (die App merkt sich das Ergebnis)
app.post('/api/dopa/categorize', auth, aiLimit, async (req, res) => {
  const items = (Array.isArray(req.body?.items) ? req.body.items : []).map(i => str(i, 80).trim()).filter(Boolean).slice(0, 30);
  if (!items.length) return res.status(400).json({ error: 'leer' });
  try {
    const { data, provider } = await ai.categorize({ items });
    const valid = Object.keys(ai.AISLES);
    const result = {};
    items.forEach((name, i) => { const a = data.aisles?.[i]; result[name] = valid.includes(a) ? a : 'other'; });
    res.json({ aisles: result, provider });
  } catch (e) { aiFail(res, e); }
});

// Tagesbegleiter: Dots Sätze für heute – zu lange oder leere fallen raus, die App hat Ersatz
app.post('/api/dopa/day', auth, aiLimit, async (req, res) => {
  const lines = (Array.isArray(req.body?.context) ? req.body.context : []).map(l => str(l, 300)).filter(Boolean).slice(0, 20);
  const todayLabel = new Date().toLocaleString('de-DE', { timeZone: 'Europe/Berlin', weekday: 'long', day: 'numeric', month: 'long' });
  const context = [`Heute: ${todayLabel}`, ...lines].join('\n');
  const clean = v => { const t = str(v, 200).trim(); return t.length >= 3 && t.length <= 160 ? t : ''; };
  const list = (v, n) => (Array.isArray(v) ? v : []).map(clean).filter(Boolean).slice(0, n);
  try {
    const { data, provider } = await ai.companionDay({
      name: str(req.body?.name, 30), level: clamp(req.body?.level ?? 1, 1, 99), context
    });
    res.json({
      briefing: clean(data.briefing), midday: clean(data.midday), afternoon: clean(data.afternoon),
      evening: clean(data.evening), night: clean(data.night),
      nudges: list(data.nudges, 6), meals: list(data.meals, 3), provider
    });
  } catch (e) { aiFail(res, e); }
});

// Einkauf: ungefähre Preise – unbrauchbare Schätzungen fallen raus statt Unsinn anzuzeigen
app.post('/api/dopa/prices', auth, aiLimit, async (req, res) => {
  const items = (Array.isArray(req.body?.items) ? req.body.items : []).map(i => str(i, 80).trim()).filter(Boolean).slice(0, 40);
  if (!items.length) return res.status(400).json({ error: 'leer' });
  try {
    const { data, provider } = await ai.prices({ items });
    const result = {};
    items.forEach((name, i) => {
      const euro = Number(data.prices?.[i]);
      if (Number.isFinite(euro) && euro > 0 && euro <= 300) result[name] = Math.round(euro * 100) / 100;
    });
    res.json({ prices: result, provider });
  } catch (e) { aiFail(res, e); }
});

// „Was jetzt?“ – die App schickt ihre offenen Aufgaben, bekommt eine zurück
app.post('/api/dopa/next', auth, aiLimit, async (req, res) => {
  const tasks = (Array.isArray(req.body?.tasks) ? req.body.tasks : []).slice(0, 40).map(t => ({
    id: str(t.id, 64), title: str(t.title, 200), step: str(t.step, 200), age_days: clamp(t.age_days, 0, 999)
  })).filter(t => t.id && t.title);
  if (!tasks.length) return res.status(400).json({ error: 'leer' });
  const energy = ['low', 'med', 'high'].includes(req.body?.energy) ? req.body.energy : 'med';
  const hour = new Date().toLocaleString('de-DE', { timeZone: 'Europe/Berlin', hour: '2-digit', hour12: false });
  try {
    const { data, provider } = await ai.dopaNext({ tasks, hour, energy, focusToday: clamp(req.body?.focus_today, 0, 1440) });
    const picked = tasks[clamp(data.index, 1, tasks.length) - 1];
    res.json({ id: picked.id, title: picked.title, why: str(data.why, 300), first_move: str(data.first_move, 200),
      minutes: [5, 10, 15, 25].includes(data.minutes) ? data.minutes : 10, provider });
  } catch (e) { aiFail(res, e); }
});

// Feedback: die App schickt gesammelt, auch nachträglich – client_id verhindert Doppelte
app.post('/api/dopa/feedback', auth, (req, res) => {
  const items = Array.isArray(req.body?.items) ? req.body.items.slice(0, 50) : [];
  const ins = db.prepare(`INSERT OR IGNORE INTO feedback (user_id,client_id,text,screen,app_version,created_at,received_at)
    VALUES (?,?,?,?,?,?,?)`);
  const accepted = [];
  db.transaction(() => {
    for (const it of items) {
      const id = str(it.id, 64), text = str(it.text, 4000).trim();
      if (!id || !text) continue;
      ins.run(req.user.id, id, text, str(it.screen, 60), str(it.app_version, 30),
        Number(it.created_at) || now(), now());
      accepted.push(id);
    }
  })();
  res.json({ accepted });
});

app.get('/api/dopa/feedback', auth, (req, res) => {
  const rows = db.prepare('SELECT client_id id, text, created_at, done_at, done_note FROM feedback WHERE user_id=? ORDER BY created_at DESC LIMIT 100')
    .all(req.user.id);
  res.json({ items: rows });
});

app.get('/api/dopa/backup', auth, (req, res) => {
  const b = db.prepare('SELECT data, updated_at FROM dopa_backups WHERE user_id=?').get(req.user.id);
  if (!b) return res.status(404).json({ error: 'kein Backup' });
  res.type('application/json').send(`{"updated_at":${b.updated_at},"data":${b.data}}`);
});

/* ---------- static ---------- */
app.use(express.static(path.join(__dirname, 'public'), { maxAge: PROD ? '1h' : 0 }));
app.get('*', (req, res) => {
  if (req.path.startsWith('/api/')) return res.status(404).json({ error: 'not found' });
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(PORT, '127.0.0.1', () => console.log('Momentum läuft auf http://localhost:' + PORT + (ai.enabled() ? ' · KI: ' + ai.describe() : ' · ohne KI')));
