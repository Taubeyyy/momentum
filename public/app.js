/* Momentum — Client. Vanilla JS, kein Build-Step. */
'use strict';

/* ================= API ================= */
async function api(method, path, body) {
  const r = await fetch('/api' + path, {
    method,
    headers: body ? { 'Content-Type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined,
    credentials: 'same-origin'
  });
  if (r.status === 401) { showAuth(); throw new Error('auth'); }
  const data = await r.json().catch(() => ({}));
  // Server schickt bei erklärungsbedürftigen Fällen ein "message" mit Klartext
  if (!r.ok) throw new Error(data.message || data.error || 'Fehler');
  return data;
}
const GET = p => api('GET', p);
const POST = (p, b) => api('POST', p, b);
const PATCH = (p, b) => api('PATCH', p, b);
const DEL = p => api('DELETE', p);

/* ================= Helpers ================= */
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const mmss = s => Math.floor(s / 60) + ':' + String(Math.floor(s % 60)).padStart(2, '0');
const humanMin = sec => sec >= 3600 ? (sec / 3600).toFixed(1) + 'h' : Math.round(sec / 60) + 'm';

let toastT;
function toast(msg) {
  const t = $('#toast'); t.textContent = msg; t.classList.add('on');
  clearTimeout(toastT); toastT = setTimeout(() => t.classList.remove('on'), 2200);
}
function buzz(ms = 12) { try { navigator.vibrate?.(ms); } catch {} }

const ENERGY = { low: { icon: '🌱', label: 'wenig' }, med: { icon: '⚡', label: 'normal' }, high: { icon: '🔥', label: 'viel' } };

/* ================= State ================= */
const S = {
  user: null, tasks: [], routines: [], habits: [], inbox: [], today: null,
  filter: 'all', showDone: false, view: 'today', focusStats: null, ai: false, taskLimit: 6
};

/* ================= Auth ================= */
let authMode = 'login';
function showAuth() { $('#auth').classList.remove('hide'); $('#app').classList.remove('on'); }
function showApp() { $('#auth').classList.add('hide'); $('#app').classList.add('on'); }

$('#tabLogin').onclick = () => setAuthMode('login');
$('#tabReg').onclick = () => setAuthMode('register');
function setAuthMode(m) {
  authMode = m;
  $('#tabLogin').classList.toggle('on', m === 'login');
  $('#tabReg').classList.toggle('on', m === 'register');
  $('#fName').hidden = m === 'login';
  $('#aPass').autocomplete = m === 'login' ? 'current-password' : 'new-password';
  $('#aGo').textContent = m === 'login' ? 'Anmelden' : 'Account anlegen';
  $('#aErr').textContent = '';
}
$('#aGo').onclick = doAuth;
['aMail', 'aPass', 'aName'].forEach(id => $('#' + id).addEventListener('keydown', e => { if (e.key === 'Enter') doAuth(); }));

async function doAuth() {
  const btn = $('#aGo'); btn.disabled = true;
  $('#aErr').textContent = '';
  try {
    const body = { email: $('#aMail').value.trim(), password: $('#aPass').value };
    if (authMode === 'register') body.name = $('#aName').value.trim();
    const { user } = await POST('/auth/' + authMode, body);
    S.user = user;
    showApp(); await loadAll();
    if (authMode === 'register') toast('Willkommen! Ich hab dir ein paar Routinen vorbereitet.');
  } catch (e) {
    $('#aErr').textContent = e.message === 'auth' ? 'E-Mail oder Passwort falsch' : e.message;
  } finally { btn.disabled = false; }
}

/* ================= Navigation ================= */
$$('nav.tabs button').forEach(b => b.onclick = () => go(b.dataset.go));
function go(view) {
  S.view = view;
  $$('.view').forEach(v => v.classList.toggle('on', v.dataset.view === view));
  $$('nav.tabs button').forEach(b => b.classList.toggle('on', b.dataset.go === view));
  // Bereichsfarbe: beantwortet "wo bin ich" vorsprachlich, bevor man den Titel liest
  document.documentElement.dataset.sect = view;
  window.scrollTo(0, 0);
  buzz(8);
  if (view === 'focus') renderFocusStats();
}

/* ================= Laden ================= */
async function loadAll() {
  const [me, t, r, h, i, today, fs] = await Promise.all([
    GET('/me'), GET('/tasks'), GET('/routines'), GET('/habits'), GET('/inbox'), GET('/today'), GET('/focus/stats?days=14')
  ]);
  S.user = me.user; S.ai = !!me.ai; S.tasks = t.tasks; S.routines = r.routines;
  S.habits = h.habits; S.inbox = i.items; S.today = today; S.focusStats = fs;
  applySettings();
  renderAll();
}
function renderAll() {
  applyAiVisibility(); offerReentry();
  renderToday(); renderTasks(); renderRoutines(); renderHabits(); renderDump(); renderFocusStats();
}

/* ================= HEUTE ================= */
function flatOpen() {
  const out = [];
  for (const t of S.tasks) {
    if (t.status === 'done') continue;
    const openSubs = t.subs.filter(s => s.status !== 'done');
    if (openSubs.length) openSubs.forEach(s => out.push({ ...s, parentTitle: t.title, starred: t.starred }));
    else out.push(t);
  }
  return out;
}
let nowIndex = 0;
function pickNow() {
  const open = flatOpen();
  if (!open.length) return null;
  const starred = open.filter(t => t.starred);
  const pool = starred.length ? starred : open;
  return pool[nowIndex % pool.length];
}

function renderToday() {
  const h = new Date().getHours();
  const gr = h < 5 ? 'Noch wach' : h < 11 ? 'Guten Morgen' : h < 18 ? 'Hi' : h < 22 ? 'Guten Abend' : 'Späte Stunde';
  $('#greet').textContent = `${gr}, ${S.user?.name || ''}`.trim();
  $('#dateLine').textContent = new Date().toLocaleDateString('de-DE', { weekday: 'long', day: 'numeric', month: 'long' });

  const t = pickNow();
  if (t) {
    $('#nowTitle').textContent = t.title;
    $('#nowMeta').textContent = [
      t.parentTitle ? '↳ ' + t.parentTitle : null,
      `${ENERGY[t.energy].icon} ${ENERGY[t.energy].label} Energie`,
      `≈ ${t.est_min} min`
    ].filter(Boolean).join(' · ');
    $('#nowStart').textContent = `▶ ${Math.min(t.est_min, 45)} min Fokus`;
    $('#nowStart').dataset.min = Math.min(t.est_min, 45);
    $('#nowStart').dataset.task = t.id;
    $('#nowSplit').classList.toggle('hide', !!t.parentTitle);
  } else {
    $('#nowTitle').textContent = 'Nichts offen 🎉';
    $('#nowMeta').textContent = 'Ernsthaft: du darfst jetzt Pause machen.';
    $('#nowStart').dataset.task = '';
    $('#nowStart').textContent = '▶ 25 min Fokus';
    $('#nowStart').dataset.min = 25;
  }

  // Tagesfortschritt — Zeitgefühl ist bei ADHS das erste, was fehlt.
  // Bezug ist der wache Tag (7-23 Uhr), nicht Mitternacht bis Mitternacht.
  const mins = new Date().getHours() * 60 + new Date().getMinutes();
  $('#dayProgress').style.width = Math.max(0, Math.min(100, ((mins - 420) / (16 * 60)) * 100)) + '%';

  const st = S.today || {};
  const glance = [
    ['#glFocus', humanMin(st.focus_sec || 0), !st.focus_sec],
    ['#glTasks', st.tasks_done || 0, !st.tasks_done],
    ['#glSteps', st.routine_steps || 0, !st.routine_steps],
    ['#glStreak', calcStreak(), !calcStreak()]
  ];
  for (const [sel, val, isZero] of glance) {
    const el = $(sel);
    el.querySelector('b').textContent = val;
    el.classList.toggle('zero', isZero);   // Nullen treten zurück statt anzuklagen
  }

  // Top 3
  const stars = S.tasks.filter(t => t.starred && t.status !== 'done').slice(0, 3);
  $('#top3').innerHTML = stars.length
    ? stars.map(t => taskRow(t, false)).join('')
    : '<div class="empty">Noch nichts markiert. Was sind heute die 3 Dinge, die zählen?</div>';

  // Routinen kompakt
  $('#routineTodayList').innerHTML = S.routines.filter(r => r.active).map(r => {
    const done = r.steps.filter(s => s.done).length, tot = r.steps.length || 1;
    return `<div style="margin-bottom:12px">
      <div class="row"><b>${r.icon} ${esc(r.name)}</b><span class="spacer"></span>
        <span class="dim">${done}/${r.steps.length}</span></div>
      <div class="progbar"><i style="width:${(done / tot) * 100}%"></i></div>
    </div>`;
  }).join('') || '<div class="empty">Keine Routinen aktiv</div>';

  // Habits kompakt
  $('#habitsQuick').innerHTML = S.habits.map(habitRow).join('') || '<div class="empty">Keine Habits</div>';
  bindHabits();
}

function calcStreak() {
  const days = (S.focusStats?.days || []).filter(d => d.sec > 60).map(d => d.day);
  if (!days.length) return 0;
  const set = new Set(days);
  let streak = 0;
  const d = new Date();
  for (let i = 0; i < 90; i++) {
    const key = new Date(d.getTime() - i * 86400000).toLocaleDateString('en-CA');
    if (set.has(key)) streak++;
    else if (i > 0) break;
  }
  return streak;
}

$('#nowStart').onclick = e => {
  const min = +e.currentTarget.dataset.min || 25;
  const id = e.currentTarget.dataset.task;
  const t = flatOpen().find(x => String(x.id) === id);
  go('focus'); setPreset(min); startTimer(t || null);
};
$('#nowSkip').onclick = () => { nowIndex++; renderToday(); buzz(); };
$('#nowSplit').onclick = () => {
  const t = pickNow(); if (!t) return toast('Nichts zu zerlegen');
  openSplitSheet(t);
};
$('#pickTop3').onclick = () => go('tasks');

/* ================= TASKS ================= */
function taskRow(t, allowSubs = true) {
  const subs = allowSubs && t.subs ? t.subs : [];
  const open = subs.filter(s => s.status !== 'done').length;
  return `
  <div class="task ${t.status === 'done' ? 'done' : ''}" data-id="${t.id}">
    <button class="tick" data-act="toggle">✓</button>
    <div class="body">
      <div class="t-title">${esc(t.title)}</div>
      <div class="t-meta">
        <span class="tag ${t.energy}">${ENERGY[t.energy].icon} ${ENERGY[t.energy].label}</span>
        <span>≈${t.est_min}m</span>
        ${subs.length ? `<span>· ${subs.length - open}/${subs.length} Schritte</span>` : ''}
      </div>
    </div>
    <div class="t-actions">
      <button class="star" data-act="star" title="Top 3">${t.starred ? '⭐' : '☆'}</button>
      <button data-act="focus" title="Fokus starten">▶</button>
      <button data-act="menu" title="Mehr">⋯</button>
    </div>
  </div>` + subs.map(s => `
  <div class="task sub ${s.status === 'done' ? 'done' : ''}" data-id="${s.id}">
    <button class="tick" data-act="toggle">✓</button>
    <div class="body"><div class="t-title">${esc(s.title)}</div></div>
    <div class="t-actions">
      <button data-act="focus">▶</button>
      <button data-act="del">✕</button>
    </div>
  </div>`).join('');
}

/* Lange Listen lähmen. Darum erstmal nur ein Ausschnitt — der Rest auf Wunsch. */
const TASK_CHUNK = 6;

function renderTasks() {
  let list = S.tasks;
  if (!S.showDone) list = list.filter(t => t.status !== 'done');
  if (S.filter !== 'all') list = list.filter(t => t.energy === S.filter);
  const openCount = S.tasks.filter(t => t.status !== 'done').length;
  $('#taskCount').textContent = openCount ? `${openCount} offen` : 'alles erledigt ✨';

  if (!list.length) {
    $('#taskList').innerHTML = `<div class="empty">${S.filter === 'all'
      ? 'Nichts hier. Schreib oben rein, was dich beschäftigt —<br>egal wie unfertig der Gedanke ist.'
      : 'Nichts mit dieser Energie. Probier einen anderen Filter.'}</div>`;
    return;
  }

  const shown = list.slice(0, S.taskLimit);
  const rest = list.length - shown.length;
  $('#taskList').innerHTML = shown.map(t => taskRow(t)).join('')
    + (rest > 0 ? `<button class="more-btn" id="showMore">↓ ${rest} weitere zeigen</button>` : '');
  const more = $('#showMore');
  if (more) more.onclick = () => { S.taskLimit += TASK_CHUNK * 2; renderTasks(); };
}

$('#taskList').addEventListener('click', onTaskClick);
$('#top3').addEventListener('click', onTaskClick);

async function onTaskClick(e) {
  const btn = e.target.closest('[data-act]'); if (!btn) return;
  const el = btn.closest('.task'); const id = +el.dataset.id;
  const all = S.tasks.flatMap(t => [t, ...t.subs]);
  const t = all.find(x => x.id === id); if (!t) return;

  if (btn.dataset.act === 'toggle') {
    buzz(15);
    const next = t.status === 'done' ? 'todo' : 'done';
    el.classList.toggle('done', next === 'done');
    await PATCH('/tasks/' + id, { status: next });
    if (next === 'done') {
      toast(['Erledigt 💪', 'Sauber!', 'Eins weniger ✨', 'Läuft.', 'Weg damit.'][Math.floor(Math.random() * 5)]);
      // kurz stehen lassen: das Abhaken soll man sehen, nicht nur auslösen
      el.classList.add('going');
      await new Promise(r => setTimeout(r, 260));
    }
    await refresh(['tasks', 'today']);
  }
  if (btn.dataset.act === 'star') { await PATCH('/tasks/' + id, { starred: !t.starred }); await refresh(['tasks', 'today']); }
  if (btn.dataset.act === 'focus') { go('focus'); setPreset(Math.min(t.est_min || 25, 45)); startTimer(t); }
  if (btn.dataset.act === 'del') { await DEL('/tasks/' + id); await refresh(['tasks', 'today']); }
  if (btn.dataset.act === 'menu') openTaskSheet(t);
}

$('#qaAdd').onclick = addQuickTask;
$('#qaTask').addEventListener('keydown', e => { if (e.key === 'Enter') addQuickTask(); });
async function addQuickTask() {
  const inp = $('#qaTask'); const title = inp.value.trim(); if (!title) return;
  inp.value = ''; buzz();
  await POST('/tasks', { title });
  await refresh(['tasks', 'today']);
}

$$('[data-energy]').forEach(b => b.onclick = () => {
  S.filter = b.dataset.energy; S.taskLimit = TASK_CHUNK;
  $$('[data-energy]').forEach(x => x.classList.toggle('on', x === b));
  renderTasks();
});
$('#toggleDone').onclick = e => { S.showDone = !S.showDone; e.currentTarget.classList.toggle('on', S.showDone); renderTasks(); };
$('#btnFilter').onclick = () => go('tasks');

/* ---------- Task-Sheet ---------- */
function openTaskSheet(t) {
  sheet(`
    <h3>${esc(t.title)}</h3>
    <div class="field"><label>Titel</label><input type="text" id="sTitle" value="${esc(t.title)}"></div>
    <div class="field"><label>Notizen</label><textarea id="sNotes" placeholder="Kontext, Links, erster Satz…">${esc(t.notes || '')}</textarea></div>
    <div class="field"><label>Wie viel Energie braucht das?</label>
      <div class="row" style="gap:6px">
        ${['low', 'med', 'high'].map(k => `<button class="chip ${t.energy === k ? 'on' : ''}" data-e="${k}">${ENERGY[k].icon} ${ENERGY[k].label}</button>`).join('')}
      </div>
    </div>
    <div class="field"><label>Geschätzte Dauer (Minuten)</label>
      <div class="row" style="gap:8px">
        <input type="number" id="sEst" value="${t.est_min}" min="1" max="600">
        ${S.ai ? '<button class="btn" id="sGuess" style="flex:none">✨ Schätzen</button>' : ''}
      </div>
      <p class="dim" id="sGuessNote" style="margin:7px 0 0"></p></div>
    <div class="row" style="gap:8px;margin-top:16px">
      <button class="btn primary" id="sSave">Speichern</button>
      ${t.parent_id ? '' : '<button class="btn" id="sSplit">✂️ Zerlegen</button>'}
      <span class="spacer"></span>
      <button class="btn danger ghost" id="sDel">Löschen</button>
    </div>`, host => {
    let energy = t.energy;
    $$('[data-e]', host).forEach(b => b.onclick = () => {
      energy = b.dataset.e; $$('[data-e]', host).forEach(x => x.classList.toggle('on', x === b));
    });
    $('#sSave', host).onclick = async () => {
      await PATCH('/tasks/' + t.id, {
        title: $('#sTitle', host).value.trim() || t.title,
        notes: $('#sNotes', host).value, energy,
        est_min: +$('#sEst', host).value || 15
      });
      closeSheet(); await refresh(['tasks', 'today']); toast('Gespeichert');
    };
    $('#sDel', host).onclick = async () => { await DEL('/tasks/' + t.id); closeSheet(); await refresh(['tasks', 'today']); };
    const sp = $('#sSplit', host); if (sp) sp.onclick = () => { closeSheet(); openSplitSheet(t); };
    const guess = $('#sGuess', host);
    if (guess) guess.onclick = async e => {
      let r;
      try { r = await aiCall('estimate', { task_id: t.id }, e.currentTarget); } catch { return; }
      $('#sEst', host).value = r.est_min;
      $('#sGuessNote', host).textContent = r.note;
    };
  });
}

/* ---------- Zerlegen ---------- */
const SPLIT_HINTS = [
  'Material/Unterlagen zusammensuchen',
  'Ersten Satz / erste Zeile schreiben',
  '5 Minuten anfangen, dann neu entscheiden',
  'Jemandem Bescheid geben / Termin machen',
  'Aufräumen danach'
];
/* Auflösung statt Schärfegrad: wie nah zoomt man an die Aufgabe ran? */
const RESOLUTIONS = [
  [1, '🔭', 'Etappen'], [2, '👁️', 'Normal'], [3, '🔍', 'Klein'],
  [4, '🔬', 'Sehr klein'], [5, '🧬', 'Winzig']
];

function openSplitSheet(t) {
  const existing = (S.tasks.find(x => x.id === (t.parent_id || t.id))?.subs || []);
  sheet(`
    <h3>✂️ ${esc(t.title)}</h3>
    <p class="dim" style="margin-top:-6px">Was ist der allerkleinste erste Schritt? Zu klein gibt's nicht.</p>

    ${S.ai ? `<div class="card" style="background:var(--card-2);margin:14px 0">
      <div class="dim" style="margin-bottom:9px">Wie klein sollen die Schritte sein?</div>
      <div class="row" style="gap:5px;margin-bottom:12px" id="resPick">
        ${RESOLUTIONS.map(([v, ic, lab]) => `<button class="chip ${v === 3 ? 'on' : ''}" data-res="${v}"
          style="flex:1;text-align:center;padding:8px 2px"><div style="font-size:1.08em">${ic}</div>
          <div style="font-size:10.5px;margin-top:2px">${lab}</div></button>`).join('')}
      </div>
      <button class="btn primary" id="aiSplit" style="width:100%">✨ Zerlegen lassen</button>
    </div>` : ''}

    <div id="subList" style="margin:12px 0">
      ${existing.map(s => `<div class="step"><span class="s-title">${esc(s.title)}</span></div>`).join('')}
    </div>
    <div class="quickadd">
      <input type="text" id="subInput" placeholder="z.B. „Ordner auf dem Schreibtisch öffnen“" enterkeyhint="enter">
      <button class="btn primary" id="subAdd">＋</button>
    </div>
    <p class="dim" style="margin-top:14px">Ideen zum Antippen:</p>
    <div class="row wrap" style="gap:6px;margin-top:6px">
      ${SPLIT_HINTS.map(h => `<button class="chip" data-hint="${esc(h)}">${esc(h)}</button>`).join('')}
    </div>
    <button class="btn primary big" id="subDone" style="width:100%;margin-top:18px">Fertig</button>`, host => {
    const parentId = t.parent_id || t.id;
    const add = async (title) => {
      if (!title.trim()) return;
      await POST('/tasks', { title: title.trim(), parent_id: parentId, est_min: 5 });
      $('#subList', host).insertAdjacentHTML('beforeend', `<div class="step"><span class="s-title">${esc(title)}</span></div>`);
      $('#subInput', host).value = ''; buzz();
    };
    $('#subAdd', host).onclick = () => add($('#subInput', host).value);
    $('#subInput', host).addEventListener('keydown', e => { if (e.key === 'Enter') add($('#subInput', host).value); });
    $$('[data-hint]', host).forEach(b => b.onclick = () => add(b.dataset.hint));
    $('#subDone', host).onclick = async () => { closeSheet(); await refresh(['tasks', 'today']); };

    // KI-Zerlegung
    let res = 3;
    $$('[data-res]', host).forEach(b => b.onclick = () => {
      res = +b.dataset.res; $$('[data-res]', host).forEach(x => x.classList.toggle('on', x === b));
    });
    const split = $('#aiSplit', host);
    if (split) split.onclick = async e => {
      let r;
      try { r = await aiCall('breakdown', { task_id: parentId, resolution: res }, e.currentTarget); } catch { return; }
      await refresh(['tasks', 'today']);
      closeSheet();
      sheet(`<h3>✨ ${r.count} Schritte</h3>
        <div class="card" style="background:var(--card-2)">
          <div class="dim" style="margin-bottom:5px">Fang damit an</div>
          <b style="font-size:1.02em;font-weight:550">${esc(r.opener)}</b>
        </div>
        <button class="btn primary big" id="okSplit" style="width:100%;margin-top:14px">Zeig mir die Liste</button>`,
        h2 => { $('#okSplit', h2).onclick = () => { closeSheet(); go('tasks'); }; });
    };
  });
}

/* ================= FOKUS-TIMER ================= */
const T = { running: false, endAt: 0, planned: 300, left: 300, task: null, startedAt: 0, tick: null };
const RING = 2 * Math.PI * 88;

function setPreset(min) {
  if (T.running) return;
  T.planned = min * 60; T.left = T.planned;
  $$('#presets .chip').forEach(c => c.classList.toggle('on', +c.dataset.min === min));
  paintTimer();
}
$$('#presets .chip').forEach(c => c.onclick = () => setPreset(+c.dataset.min));

function paintTimer() {
  const left = Math.max(0, T.left);
  $('#tTime').textContent = mmss(left);
  $('#tState').textContent = T.running ? 'läuft' : (T.left < T.planned ? 'pausiert' : 'bereit');
  const frac = T.planned ? left / T.planned : 0;
  $('#ringProg').style.strokeDasharray = RING;
  $('#ringProg').style.strokeDashoffset = RING * (1 - frac);
  $('#tStart').textContent = T.running ? '⏸ Pause' : (T.left < T.planned ? '▶ Weiter' : '▶ Start');
  $('#focusTask').innerHTML = T.task ? `Fokus auf: <b>${esc(T.task.title)}</b>` : 'Kein Task gewählt — geht auch ohne.';
  document.title = T.running ? `${mmss(left)} · Momentum` : 'Momentum';

  // Leiste am oberen Rand: sichtbar, sobald ein Block angefangen hat —
  // in jedem Tab, damit man den laufenden Timer nicht "verliert".
  const active = T.running || T.left < T.planned;
  document.body.classList.toggle('timer-on', active);
  if (active) {
    const bar = $('#timerBar');
    bar.classList.toggle('paused', !T.running);
    $('#tbTime').textContent = mmss(left);
    $('#tbTask').textContent = T.task ? T.task.title : (T.running ? 'Fokus läuft' : 'Pausiert');
    $('#tbToggle').textContent = T.running ? '⏸' : '▶';
    $('#tbProg').style.width = ((1 - frac) * 100) + '%';
  }
}

$('#tbToggle').onclick = () => startTimer();
$('#tbOpen').onclick = () => go('focus');

function startTimer(task) {
  if (task !== undefined) T.task = task;
  if (T.running) return pauseTimer();
  T.running = true;
  T.endAt = Date.now() + T.left * 1000;
  if (!T.startedAt) T.startedAt = Date.now();
  saveTimer();
  clearInterval(T.tick);
  T.tick = setInterval(tickTimer, 250);
  paintTimer(); buzz(20);
  if ('Notification' in window && Notification.permission === 'default') Notification.requestPermission();
}
function pauseTimer() {
  T.running = false; clearInterval(T.tick);
  T.left = Math.max(0, Math.round((T.endAt - Date.now()) / 1000));
  saveTimer(); paintTimer();
}
function tickTimer() {
  T.left = Math.max(0, Math.round((T.endAt - Date.now()) / 1000));
  paintTimer();
  if (T.left <= 0) finishTimer(true);
}
async function finishTimer(completed) {
  clearInterval(T.tick);
  const actual = Math.min(T.planned, Math.round((Date.now() - (T.startedAt || Date.now())) / 1000));
  const wasRunning = T.running || T.left < T.planned;
  T.running = false;
  if (wasRunning && actual > 5) {
    try {
      await POST('/focus', {
        task_id: T.task?.id || null, label: T.task?.title || '',
        planned_sec: T.planned, actual_sec: actual, started_at: T.startedAt, completed: completed ? 1 : 0
      });
    } catch {}
  }
  if (completed) {
    notify('Zeit ist um 🎉', T.task ? T.task.title : 'Fokus-Block geschafft');
    ping(); buzz([60, 40, 60]);
    toast('Block geschafft! Kurz aufstehen?');
  }
  T.left = T.planned; T.startedAt = 0;
  localStorage.removeItem('mo_timer');
  paintTimer();
  await refresh(['today', 'focus']);
}
$('#tStart').onclick = () => startTimer();
$('#tStop').onclick = () => { if (T.startedAt) finishTimer(false); else { T.left = T.planned; paintTimer(); } };

document.addEventListener('keydown', e => {
  if (e.target.matches('input,textarea')) return;
  if (e.code === 'Space' && S.view === 'focus') { e.preventDefault(); startTimer(); }
});

function saveTimer() {
  localStorage.setItem('mo_timer', JSON.stringify({
    running: T.running, endAt: T.endAt, planned: T.planned, left: T.left,
    startedAt: T.startedAt, task: T.task ? { id: T.task.id, title: T.task.title } : null
  }));
}
function restoreTimer() {
  try {
    const s = JSON.parse(localStorage.getItem('mo_timer') || 'null'); if (!s) return;
    T.planned = s.planned; T.startedAt = s.startedAt; T.task = s.task;
    if (s.running) {
      T.left = Math.max(0, Math.round((s.endAt - Date.now()) / 1000));
      if (T.left > 0) { T.endAt = s.endAt; T.running = true; T.tick = setInterval(tickTimer, 250); }
      else { T.left = 0; finishTimer(true); }
    } else T.left = s.left;
    $$('#presets .chip').forEach(c => c.classList.toggle('on', +c.dataset.min === Math.round(T.planned / 60)));
    paintTimer();
  } catch {}
}

function notify(title, body) {
  try { if (Notification?.permission === 'granted') new Notification(title, { body, icon: '/icons/icon-192.png' }); } catch {}
}
function ping() {
  try {
    const ac = new (window.AudioContext || window.webkitAudioContext)();
    [880, 1174].forEach((f, i) => {
      const o = ac.createOscillator(), g = ac.createGain();
      o.frequency.value = f; o.type = 'sine'; o.connect(g); g.connect(ac.destination);
      const t0 = ac.currentTime + i * 0.18;
      g.gain.setValueAtTime(0.0001, t0);
      g.gain.exponentialRampToValueAtTime(0.25, t0 + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, t0 + 0.5);
      o.start(t0); o.stop(t0 + 0.55);
    });
  } catch {}
}

function renderFocusStats() {
  const rec = S.focusStats?.days || [];
  // immer 14 Slots zeichnen — leere Tage sind Teil der Info
  const slots = [...Array(14)].map((_, i) => {
    const day = new Date(Date.now() - (13 - i) * 86400000).toLocaleDateString('en-CA');
    return { day, sec: rec.find(x => x.day === day)?.sec || 0 };
  });
  const max = Math.max(600, ...slots.map(x => x.sec));
  $('#focusBars').innerHTML = slots.map(x =>
    `<div style="height:${Math.max(2, (x.sec / max) * 100)}%;opacity:${x.sec ? .85 : .18}"
          title="${x.day}: ${humanMin(x.sec)}"></div>`).join('');
  const total = slots.reduce((a, b) => a + b.sec, 0);
  const active = slots.filter(s => s.sec > 0).length;
  $('#focusTotal').textContent = total
    ? `${humanMin(total)} in 14 Tagen · an ${active} Tag${active === 1 ? '' : 'en'}`
    : 'Noch keine Fokus-Zeit — der erste Block darf 5 Minuten sein.';
}

/* ================= ROUTINEN ================= */
function renderRoutines() {
  $('#routineList').innerHTML = S.routines.map(r => {
    const done = r.steps.filter(s => s.done).length, tot = r.steps.length || 1;
    return `<div class="card" data-routine="${r.id}">
      <div class="row" style="margin-bottom:6px">
        <h3 style="margin:0;color:var(--text);font-size:1.02em;text-transform:none;letter-spacing:0">${r.icon} ${esc(r.name)}</h3>
        <span class="spacer"></span>
        <span class="dim">${r.when_at || ''} · ${done}/${r.steps.length}</span>
        <button class="rowx" data-ract="del" title="Routine löschen">✕</button>
      </div>
      <div class="progbar"><i style="width:${(done / tot) * 100}%"></i></div>
      ${r.steps.map(s => `
        <div class="step ${s.done ? 'done' : ''}" data-step="${s.id}">
          <button class="tick" data-sact="check">✓</button>
          <span class="s-title">${esc(s.title)}</span>
          <span class="dim" style="flex:none">${s.est_min}m</span>
          <button class="rowx" data-sact="del" title="Schritt löschen">✕</button>
        </div>`).join('')}
      <div class="quickadd" style="margin-top:11px">
        <input type="text" placeholder="Schritt hinzufügen…" data-radd="${r.id}">
      </div>
    </div>`;
  }).join('') || '<div class="empty">Noch keine Routine. Tipp oben auf ＋</div>';

  $('#routineList').onclick = async e => {
    const b = e.target.closest('[data-sact],[data-ract]'); if (!b) return;
    if (b.dataset.ract === 'del') {
      const id = b.closest('[data-routine]').dataset.routine;
      if (!confirm('Routine löschen?')) return;
      await DEL('/routines/' + id); await refresh(['routines', 'today']); return;
    }
    const stepEl = b.closest('[data-step]'); const sid = stepEl.dataset.step;
    if (b.dataset.sact === 'check') {
      const nowDone = !stepEl.classList.contains('done');
      buzz(15);
      await POST(`/steps/${sid}/check`, { done: nowDone });
      await refresh(['routines', 'today']);
    }
    if (b.dataset.sact === 'del') { await DEL('/steps/' + sid); await refresh(['routines']); }
  };
  $$('[data-radd]').forEach(inp => inp.addEventListener('keydown', async e => {
    if (e.key !== 'Enter' || !inp.value.trim()) return;
    await POST(`/routines/${inp.dataset.radd}/steps`, { title: inp.value.trim() });
    inp.value = ''; await refresh(['routines', 'today']);
  }));
}

$('#addRoutine').onclick = () => sheet(`
  <h3>Neue Routine</h3>
  <div class="field"><label>Name</label><input type="text" id="rName" placeholder="z.B. Feierabend-Runterfahren"></div>
  <div class="field"><label>Icon</label><input type="text" id="rIcon" value="✨" maxlength="4"></div>
  <div class="field"><label>Uhrzeit (optional)</label><input type="time" id="rWhen"></div>
  <button class="btn primary big" id="rSave" style="width:100%">Anlegen</button>`, host => {
  $('#rSave', host).onclick = async () => {
    await POST('/routines', {
      name: $('#rName', host).value.trim() || 'Routine',
      icon: $('#rIcon', host).value || '✨', when_at: $('#rWhen', host).value
    });
    closeSheet(); await refresh(['routines', 'today']);
  };
});

/* ================= HABITS ================= */
function habitRow(h) {
  const pct = Math.min(1, h.today / h.target_day);
  const last7 = [...Array(7)].map((_, i) => {
    const day = new Date(Date.now() - (6 - i) * 86400000).toLocaleDateString('en-CA');
    const rec = h.history.find(x => x.day === day);
    return `<i class="${rec && rec.count >= h.target_day ? 'on' : ''}"></i>`;
  }).join('');
  return `<div class="habit" data-habit="${h.id}">
    <div class="hicon" style="background:${h.color}22;color:${h.color}">${h.icon}</div>
    <div class="body" style="flex:1;min-width:0">
      <div class="row"><b style="font-weight:550">${esc(h.name)}</b></div>
      <div class="dots">${last7}</div>
    </div>
    <div class="hcount">
      <button class="btn sm" data-hact="minus">−</button>
      <b style="color:${pct >= 1 ? 'var(--good)' : 'var(--text)'}">${h.today}/${h.target_day}</b>
      <button class="btn sm" data-hact="plus">＋</button>
    </div>
  </div>`;
}
function renderHabits() {
  $('#habitList').innerHTML = S.habits.map(habitRow).join('') || '<div class="empty">Keine Habits</div>';
  bindHabits();
}
function bindHabits() {
  $$('[data-habit]').forEach(el => {
    el.onclick = async e => {
      const b = e.target.closest('[data-hact]'); if (!b) return;
      const id = el.dataset.habit;
      buzz(12);
      const { count } = await POST(`/habits/${id}/log`, { delta: b.dataset.hact === 'plus' ? 1 : -1 });
      const h = S.habits.find(x => String(x.id) === id);
      if (h) { const was = h.today; h.today = count; if (count >= h.target_day && was < h.target_day) toast(`${h.icon} ${h.name} ✓`); }
      renderHabits(); renderToday();
    };
  });
}
$('#addHabit').onclick = () => sheet(`
  <h3>Neuer Habit</h3>
  <div class="field"><label>Name</label><input type="text" id="hName" placeholder="z.B. Vitamin D"></div>
  <div class="field"><label>Icon</label><input type="text" id="hIcon" value="✅" maxlength="4"></div>
  <div class="field"><label>Wie oft pro Tag?</label><input type="number" id="hTarget" value="1" min="1" max="30"></div>
  <div class="field"><label>Farbe</label>
    <div class="row wrap" style="gap:7px">
      ${['#7c9cff', '#ff8fa3', '#6ee7ff', '#8ef0a8', '#ffcb6b', '#a78bfa'].map((c, i) =>
        `<button class="chip ${i === 0 ? 'on' : ''}" data-color="${c}" style="background:${c}33;border-color:${c}">&nbsp;&nbsp;&nbsp;</button>`).join('')}
    </div></div>
  <button class="btn primary big" id="hSave" style="width:100%">Anlegen</button>`, host => {
  let color = '#7c9cff';
  $$('[data-color]', host).forEach(b => b.onclick = () => {
    color = b.dataset.color; $$('[data-color]', host).forEach(x => x.classList.toggle('on', x === b));
  });
  $('#hSave', host).onclick = async () => {
    await POST('/habits', {
      name: $('#hName', host).value.trim() || 'Habit', icon: $('#hIcon', host).value || '✅',
      target_day: +$('#hTarget', host).value || 1, color
    });
    closeSheet(); await refresh(['habits', 'today']);
  };
});

/* ================= DUMP ================= */
function renderDump() {
  $('#dumpCount').textContent = S.inbox.length ? `${S.inbox.length} im Kopf-Zwischenspeicher` : '';
  $('#dumpList').innerHTML = S.inbox.map(i => `
    <div class="dump-item" data-inbox="${i.id}">
      <p>${esc(i.text)}</p>
      <button class="btn sm" data-iact="task" title="Zu Aufgabe machen">→ Task</button>
      <button class="btn sm ghost" data-iact="del">✕</button>
    </div>`).join('') || '<div class="empty">Leer im Zwischenspeicher 🧘</div>';

  $('#dumpList').onclick = async e => {
    const b = e.target.closest('[data-iact]'); if (!b) return;
    const id = b.closest('[data-inbox]').dataset.inbox;
    if (b.dataset.iact === 'task') { await POST(`/inbox/${id}/convert`); toast('Als Aufgabe angelegt'); }
    else await DEL('/inbox/' + id);
    await refresh(['inbox', 'tasks', 'today']);
  };
}
$('#dumpSave').onclick = saveDump;
$('#dumpText').addEventListener('keydown', e => { if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) saveDump(); });
async function saveDump() {
  const ta = $('#dumpText'); const text = ta.value.trim(); if (!text) return;
  ta.value = ''; buzz();
  await POST('/inbox', { text });
  await refresh(['inbox']);
  toast('Raus aus dem Kopf ✍️');
}

/* ================= MOOD ================= */
$('#btnMood').onclick = () => {
  const scale = (id, icons) => `<div class="scale" data-scale="${id}">
    ${icons.map((ic, i) => `<button data-v="${i + 1}" class="${i === 2 ? 'on' : ''}">${ic}</button>`).join('')}</div>`;
  sheet(`
    <h3>Kurzer Check-in</h3>
    <div class="mood-row"><label>Stimmung</label>${scale('mood', ['😞', '🙁', '😐', '🙂', '😄'])}</div>
    <div class="mood-row"><label>Energie</label>${scale('energy', ['🪫', '🔋', '🔋', '⚡', '⚡'])}</div>
    <div class="mood-row"><label>Fokus</label>${scale('focus', ['🌪️', '🌫️', '☁️', '🔍', '🎯'])}</div>
    <div class="field"><label>Notiz (optional)</label><input type="text" id="mNote" placeholder="Was ist gerade los?"></div>
    <button class="btn primary big" id="mSave" style="width:100%">Speichern</button>`, host => {
    const vals = { mood: 3, energy: 3, focus: 3 };
    $$('[data-scale]', host).forEach(sc => sc.onclick = e => {
      const b = e.target.closest('[data-v]'); if (!b) return;
      vals[sc.dataset.scale] = +b.dataset.v;
      $$('button', sc).forEach(x => x.classList.toggle('on', x === b));
      buzz();
    });
    $('#mSave', host).onclick = async () => {
      await POST('/moods', { ...vals, note: $('#mNote', host).value });
      closeSheet(); await refresh(['today']); toast('Notiert 🫧');
    };
  });
};

/* ================= SETTINGS ================= */
$('#btnSettings').onclick = () => {
  const st = S.user.settings || {};
  sheet(`
    <h3>Einstellungen</h3>
    <div class="field"><label>Name</label><input type="text" id="setName" value="${esc(S.user.name)}"></div>
    <div class="field"><label>Design</label>
      <div class="row wrap" style="gap:6px">
        <button class="chip ${st.theme !== 'light' ? 'on' : ''}" data-theme="dark">🌙 Dunkel</button>
        <button class="chip ${st.theme === 'light' ? 'on' : ''}" data-theme="light">☀️ Hell</button>
      </div></div>
    <div class="field"><label>Textgröße</label>
      <div class="row wrap" style="gap:6px">
        ${[['1', 'Normal'], ['1.12', 'Groß'], ['1.25', 'Sehr groß']].map(([v, l]) =>
          `<button class="chip ${String(st.scale || '1') === v ? 'on' : ''}" data-scale="${v}">${l}</button>`).join('')}
      </div></div>
    <div class="field"><label>Reize runterfahren</label>
      <div class="row wrap" style="gap:6px">
        <button class="chip ${st.calm === 'on' ? 'on' : ''}" data-opt="calm">🎚️ Farben dämpfen</button>
        <button class="chip ${st.motion === 'off' ? 'on' : ''}" data-opt="motion">🐢 Bewegung aus</button>
      </div>
      <p class="dim" style="margin:8px 0 0">Bewegung ist automatisch aus, wenn dein System das so eingestellt hat.</p></div>
    <div class="field"><label>Benachrichtigungen</label>
      <button class="btn sm" id="setNotif">Erlauben</button>
      <span class="dim" id="notifState"></span></div>
    <button class="btn primary big" id="setSave" style="width:100%;margin-top:6px">Speichern</button>
    <button class="btn ghost" id="setOut" style="width:100%;margin-top:9px">Abmelden</button>
    <p class="dim" style="text-align:center;margin-top:16px">Momentum · v0.1</p>`, host => {
    // Änderungen greifen sofort — man soll sehen, was man wählt, nicht es sich vorstellen
    const draft = { theme: st.theme || 'dark', scale: st.scale || '1', calm: st.calm || 'off', motion: st.motion || 'on' };
    const live = () => applySettings({ ...st, ...draft });

    $$('[data-theme]', host).forEach(b => b.onclick = () => {
      draft.theme = b.dataset.theme;
      $$('[data-theme]', host).forEach(x => x.classList.toggle('on', x === b));
      live();
    });
    $$('[data-scale]', host).forEach(b => b.onclick = () => {
      draft.scale = b.dataset.scale;
      $$('[data-scale]', host).forEach(x => x.classList.toggle('on', x === b));
      live();
    });
    $('[data-opt="calm"]', host).onclick = e => {
      draft.calm = draft.calm === 'on' ? 'off' : 'on';
      e.currentTarget.classList.toggle('on', draft.calm === 'on');
      live();
    };
    $('[data-opt="motion"]', host).onclick = e => {
      draft.motion = draft.motion === 'off' ? 'on' : 'off';
      e.currentTarget.classList.toggle('on', draft.motion === 'off');
      live();
    };
    $('#notifState', host).textContent = 'Notification' in window ? Notification.permission : 'nicht unterstützt';
    $('#setNotif', host).onclick = async () => {
      const p = await Notification.requestPermission(); $('#notifState', host).textContent = p;
    };
    $('#setSave', host).onclick = async () => {
      const { user } = await PATCH('/me', {
        name: $('#setName', host).value.trim(),
        tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
        settings: { ...st, ...draft }
      });
      S.user = user; applySettings(); closeSheet(); renderToday(); toast('Gespeichert');
    };
    // Abbruch über Escape/Hintergrund: gespeicherten Stand wiederherstellen
    $('.sheet-bg').addEventListener('click', ev => { if (ev.target.classList.contains('sheet-bg')) applySettings(); });
    $('#setOut', host).onclick = async () => { await POST('/auth/logout'); location.reload(); };
  });
};

function applySettings(override) {
  const st = override || S.user?.settings || {};
  const root = document.documentElement;
  root.dataset.theme = st.theme === 'light' ? 'light' : 'dark';
  root.dataset.calm = st.calm === 'on' ? 'on' : 'off';
  root.dataset.motion = st.motion === 'off' ? 'off' : 'on';
  root.style.setProperty('--scale', st.scale || '1');
  $('meta[name=theme-color]').content = st.theme === 'light' ? '#f2f4f9' : '#0d0f14';
}

/* ================= KI-Helfer =================
   Jeder Aufruf kann dauern und Geld kosten — deshalb: Button sperren,
   Zustand zeigen, Fehler im Klartext, nie stumm scheitern. */

async function aiCall(path, body, btn) {
  const label = btn?.textContent;
  if (btn) { btn.disabled = true; btn.textContent = '✨ denkt nach…'; }
  try {
    return await POST('/ai/' + path, body);
  } catch (e) {
    toast(e.message === 'auth' ? 'Bitte neu anmelden' : e.message);
    throw e;
  } finally {
    if (btn) { btn.disabled = false; btn.textContent = label; }
  }
}

function applyAiVisibility() {
  $$('.ai-only').forEach(el => el.classList.toggle('hide', !S.ai));
  const hint = $('#worteHint');
  if (hint) hint.textContent = S.ai ? 'Läuft über Claude auf deinem Server. Nichts davon wird gespeichert.' : '';
}

/* ---------- Was jetzt? ---------- */
$('#nowAsk').onclick = async e => {
  let r;
  try { r = await aiCall('next', {}, e.currentTarget); } catch { return; }
  if (r.empty) return toast('Nichts offen — Pause ist erlaubt.');
  sheet(`
    <h3>✨ ${esc(r.title)}</h3>
    <p style="margin:0 0 16px;font-size:15.5px">${esc(r.why)}</p>
    <div class="card" style="background:var(--card-2);margin-bottom:16px">
      <div class="dim" style="margin-bottom:5px">Erster Handgriff</div>
      <b style="font-size:1.02em;font-weight:550">${esc(r.first_move)}</b>
    </div>
    <button class="btn primary big" id="aGoFocus" style="width:100%">▶ ${r.minutes} min dafür</button>
    <button class="btn ghost" id="aNope" style="width:100%;margin-top:9px">Nee, was anderes</button>`, host => {
    $('#aGoFocus', host).onclick = () => {
      const t = S.tasks.flatMap(x => [x, ...x.subs]).find(x => x.id === r.task_id);
      closeSheet(); go('focus'); setPreset(r.minutes); startTimer(t || { id: r.task_id, title: r.title });
    };
    $('#aNope', host).onclick = () => { closeSheet(); nowIndex++; renderToday(); };
  });
};

/* ---------- Wiedereinstieg ---------- */
async function offerReentry() {
  const card = $('#reentryCard');
  if (!S.ai || !card) return;
  // nur anbieten, wenn heute ein Fokus-Block lief und noch was offen ist
  const stale = (S.today?.focus_n || 0) > 0 && flatOpen().length > 0;
  card.hidden = !stale;
  if (!stale) return;
  $('#reentryBody').innerHTML = `
    <p class="dim" style="margin:0 0 10px">Du warst heute schon dran. Zurückfinden ist der schwere Teil.</p>
    <button class="btn" id="reGo">✨ Wo war ich?</button>`;
  $('#reGo').onclick = async e => {
    let r;
    try { r = await aiCall('reentry', {}, e.currentTarget); } catch { return; }
    $('#reentryBody').innerHTML = `
      <div class="dim" style="margin-bottom:4px">${esc(r.title)}</div>
      <p style="margin:0 0 13px">${esc(r.where)}</p>
      <div class="progbar" style="background:none;height:auto;margin:0 0 13px">
        ${r.reentry.map((s, i) => `<div class="step"><span class="hicon" style="width:26px;height:26px;font-size:.82em">${i + 1}</span><span class="s-title">${esc(s)}</span></div>`).join('')}
      </div>
      <p class="dim" style="margin:0 0 12px">Danach: ${esc(r.next)}</p>
      <button class="btn primary" id="reFocus">▶ 15 min</button>`;
    $('#reFocus').onclick = () => {
      const t = S.tasks.flatMap(x => [x, ...x.subs]).find(x => x.id === r.task_id);
      go('focus'); setPreset(15); startTimer(t || null);
    };
  };
}

/* ---------- Dump sortieren ---------- */
$('#dumpCompile').onclick = async e => {
  const extra = $('#dumpText').value.trim();
  if (!extra && !S.inbox.length) return toast('Nichts zu sortieren');
  let r;
  try { r = await aiCall('compile', { text: extra, use_inbox: true }, e.currentTarget); } catch { return; }
  $('#dumpText').value = '';
  await refresh(['inbox', 'tasks', 'today']);
  toast(`${r.count} Aufgabe${r.count === 1 ? '' : 'n'} angelegt`);
  if (r.notes) sheet(`<h3>Sortiert</h3>
    <p>${r.count} Aufgaben sind jetzt in deiner Liste.</p>
    <p class="dim">Das hier war keine Aufgabe, ich hab's trotzdem behalten:<br>${esc(r.notes)}</p>
    <button class="btn primary big" id="okBtn" style="width:100%;margin-top:12px">Alles klar</button>`,
    host => { $('#okBtn', host).onclick = closeSheet; });
};

/* ---------- Worte: Umschreiben & Verstehen ---------- */
const WORTE_MODES = [
  ['klar', '🎯 Klarer'], ['kurz', '✂️ Kürzer'], ['formell', '👔 Formeller'],
  ['locker', '🙂 Lockerer'], ['sanft', '🕊️ Sanfter'], ['bestimmt', '💪 Bestimmter'],
  ['absage', '🙅 Absage'], ['entschuldigung', '🫣 Entschuldigung']
];
let worteMode = 'klar';

$('#wModes').innerHTML = WORTE_MODES.map(([k, l]) =>
  `<button class="chip ${k === 'klar' ? 'on' : ''}" data-wmode="${k}">${l}</button>`).join('');
$('#wModes').onclick = e => {
  const b = e.target.closest('[data-wmode]'); if (!b) return;
  worteMode = b.dataset.wmode;
  $$('[data-wmode]').forEach(x => x.classList.toggle('on', x === b));
};

$$('[data-worte]').forEach(b => b.onclick = () => {
  $$('[data-worte]').forEach(x => x.classList.toggle('on', x === b));
  $('#worteWrite').classList.toggle('hide', b.dataset.worte !== 'write');
  $('#worteRead').classList.toggle('hide', b.dataset.worte !== 'read');
});

$('#wGo').onclick = async e => {
  const text = $('#wText').value.trim();
  if (!text) return toast('Schreib erst was rein');
  let r;
  try { r = await aiCall('rewrite', { text, mode: worteMode }, e.currentTarget); } catch { return; }
  $('#wOut').innerHTML = `
    <div class="card">
      <h3>Vorschlag</h3>
      <p style="white-space:pre-wrap;margin:0 0 12px">${esc(r.result)}</p>
      <div class="row" style="gap:8px">
        <button class="btn primary" id="wCopy">Kopieren</button>
        <button class="btn ghost" id="wBack">Übernehmen & weiter</button>
      </div>
      <p class="dim" style="margin:11px 0 0">${esc(r.changed)}</p>
    </div>`;
  $('#wCopy').onclick = async () => {
    try { await navigator.clipboard.writeText(r.result); toast('Kopiert'); }
    catch { toast('Kopieren ging nicht — markier den Text'); }
  };
  $('#wBack').onclick = () => { $('#wText').value = r.result; $('#wOut').innerHTML = ''; window.scrollTo(0, 0); };
};

$('#rGo').onclick = async e => {
  const text = $('#rText').value.trim();
  if (!text) return toast('Nachricht einfügen');
  let r;
  try { r = await aiCall('interpret', { text }, e.currentTarget); } catch { return; }
  const temp = ['', 'sehr freundlich', 'freundlich', 'neutral', 'angespannt', 'verärgert'][r.temperature];
  const col = ['', 'var(--good)', 'var(--good)', 'var(--muted)', 'var(--warn)', 'var(--hot)'][r.temperature];
  $('#rOut').innerHTML = `
    <div class="card">
      <div class="row" style="margin-bottom:12px">
        <b style="color:${col}">${temp}</b>
        <span class="spacer"></span>
        <div class="dots">${[1, 2, 3, 4, 5].map(i =>
          `<i class="${i <= r.temperature ? 'on' : ''}" style="${i <= r.temperature ? 'background:' + col : ''}"></i>`).join('')}</div>
      </div>
      <div class="dim" style="margin-bottom:3px">Da steht</div>
      <p style="margin:0 0 13px">${esc(r.literal)}</p>
      <div class="dim" style="margin-bottom:3px">Tonfall</div>
      <p style="margin:0 0 13px">${esc(r.tone)}</p>
      ${r.overthinking ? `<div class="dim" style="margin-bottom:3px">Was du reinliest, aber nicht dasteht</div>
        <p style="margin:0 0 13px">${esc(r.overthinking)}</p>` : ''}
      <div class="dim" style="margin-bottom:3px">Antwortvorschlag</div>
      <p style="margin:0 0 12px;white-space:pre-wrap">${esc(r.reply)}</p>
      <button class="btn primary" id="rCopy">Antwort kopieren</button>
    </div>`;
  $('#rCopy').onclick = async () => {
    try { await navigator.clipboard.writeText(r.reply); toast('Kopiert'); }
    catch { toast('Kopieren ging nicht'); }
  };
};

/* ================= Sheet ================= */
function sheet(html, onMount) {
  const bg = document.createElement('div');
  bg.className = 'sheet-bg';
  bg.innerHTML = `<div class="sheet">${html}</div>`;
  bg.onclick = e => { if (e.target === bg) closeSheet(); };
  $('#sheetHost').appendChild(bg);
  onMount?.($('.sheet', bg));
  const first = $('input,textarea', bg); if (first && window.innerWidth > 640) first.focus();
}
function closeSheet() { $('#sheetHost').innerHTML = ''; }
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeSheet(); });

/* ================= Refresh ================= */
async function refresh(parts) {
  const jobs = [];
  if (parts.includes('tasks')) jobs.push(GET('/tasks').then(d => S.tasks = d.tasks));
  if (parts.includes('routines')) jobs.push(GET('/routines').then(d => S.routines = d.routines));
  if (parts.includes('habits')) jobs.push(GET('/habits').then(d => S.habits = d.habits));
  if (parts.includes('inbox')) jobs.push(GET('/inbox').then(d => S.inbox = d.items));
  if (parts.includes('today')) jobs.push(GET('/today').then(d => S.today = d));
  if (parts.includes('focus')) jobs.push(GET('/focus/stats?days=14').then(d => S.focusStats = d));
  await Promise.all(jobs);
  if (parts.includes('tasks')) renderTasks();
  if (parts.includes('routines')) renderRoutines();
  if (parts.includes('habits')) renderHabits();
  if (parts.includes('inbox')) renderDump();
  if (parts.includes('focus')) renderFocusStats();
  renderToday();
}

/* ================= Reminder (lokal, solange App offen) ================= */
setInterval(() => {
  const hm = new Date().toTimeString().slice(0, 5);
  const key = 'mo_rem_' + new Date().toLocaleDateString('en-CA') + '_' + hm;
  if (localStorage.getItem(key)) return;
  const due = [
    ...S.habits.filter(h => h.remind_at === hm && h.today < h.target_day).map(h => `${h.icon} ${h.name}`),
    ...S.routines.filter(r => r.active && r.when_at === hm && r.steps.some(s => !s.done)).map(r => `${r.icon} ${r.name}`)
  ];
  if (due.length) { localStorage.setItem(key, '1'); notify('Momentum', due.join(' · ')); ping(); }
}, 30000);

/* ================= Boot ================= */
(async function boot() {
  setAuthMode('login');
  try {
    const me = await GET('/me');
    S.user = me.user; showApp();
    await loadAll(); restoreTimer();
    const want = new URLSearchParams(location.search).get('go');   // App-Shortcuts
    if (want && $(`nav.tabs [data-go="${want}"]`)) { go(want); history.replaceState({}, '', '/'); }
  } catch { showAuth(); }
  if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => {});
})();

document.addEventListener('visibilitychange', () => {
  if (!document.hidden) { paintTimer(); refresh(['today']).catch(() => {}); }
});
