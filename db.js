'use strict';
const path = require('path');
const Database = require('better-sqlite3');

const DB_PATH = process.env.DB_PATH || path.join(__dirname, 'momentum.db');
const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

db.exec(`
CREATE TABLE IF NOT EXISTS users (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  email       TEXT UNIQUE NOT NULL,
  pass_hash   TEXT NOT NULL,
  name        TEXT NOT NULL DEFAULT '',
  tz          TEXT NOT NULL DEFAULT 'Europe/Berlin',
  settings    TEXT NOT NULL DEFAULT '{}',
  created_at  INTEGER NOT NULL
);

-- Tasks: parent_id != NULL  =>  Mini-Schritt eines Tasks
CREATE TABLE IF NOT EXISTS tasks (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  parent_id    INTEGER REFERENCES tasks(id) ON DELETE CASCADE,
  title        TEXT NOT NULL,
  notes        TEXT NOT NULL DEFAULT '',
  status       TEXT NOT NULL DEFAULT 'todo',      -- todo | done
  energy       TEXT NOT NULL DEFAULT 'med',       -- low | med | high
  est_min      INTEGER NOT NULL DEFAULT 15,
  due_at       INTEGER,                            -- ms epoch
  starred      INTEGER NOT NULL DEFAULT 0,         -- "heute wichtig"
  sort         REAL NOT NULL DEFAULT 0,
  created_at   INTEGER NOT NULL,
  completed_at INTEGER
);
CREATE INDEX IF NOT EXISTS idx_tasks_user   ON tasks(user_id, status);
CREATE INDEX IF NOT EXISTS idx_tasks_parent ON tasks(parent_id);

-- Fokus-Sessions (Pomodoro / Timebox / Body-Double)
CREATE TABLE IF NOT EXISTS focus_sessions (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  task_id     INTEGER REFERENCES tasks(id) ON DELETE SET NULL,
  label       TEXT NOT NULL DEFAULT '',
  mode        TEXT NOT NULL DEFAULT 'focus',      -- focus | break
  planned_sec INTEGER NOT NULL DEFAULT 1500,
  actual_sec  INTEGER NOT NULL DEFAULT 0,
  started_at  INTEGER NOT NULL,
  ended_at    INTEGER,
  completed   INTEGER NOT NULL DEFAULT 0,
  day         TEXT NOT NULL                        -- YYYY-MM-DD (lokal)
);
CREATE INDEX IF NOT EXISTS idx_focus_user ON focus_sessions(user_id, day);

-- Routinen (Morgen/Abend/…) mit Schritten
CREATE TABLE IF NOT EXISTS routines (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id  INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name     TEXT NOT NULL,
  icon     TEXT NOT NULL DEFAULT '☀️',
  when_at  TEXT NOT NULL DEFAULT '',              -- "07:30" (optional)
  active   INTEGER NOT NULL DEFAULT 1,
  sort     REAL NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS routine_steps (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  routine_id INTEGER NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
  title      TEXT NOT NULL,
  est_min    INTEGER NOT NULL DEFAULT 2,
  sort       REAL NOT NULL DEFAULT 0
);
-- pro Tag + Schritt ein Häkchen
CREATE TABLE IF NOT EXISTS routine_checks (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  step_id INTEGER NOT NULL REFERENCES routine_steps(id) ON DELETE CASCADE,
  day     TEXT NOT NULL,
  done_at INTEGER NOT NULL,
  PRIMARY KEY (step_id, day)
);

-- Habits / Meds
CREATE TABLE IF NOT EXISTS habits (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  icon        TEXT NOT NULL DEFAULT '✅',
  color       TEXT NOT NULL DEFAULT '#7c9cff',
  target_day  INTEGER NOT NULL DEFAULT 1,          -- wie oft pro Tag
  remind_at   TEXT NOT NULL DEFAULT '',            -- "08:00"
  active      INTEGER NOT NULL DEFAULT 1,
  sort        REAL NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS habit_logs (
  habit_id INTEGER NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
  user_id  INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day      TEXT NOT NULL,
  count    INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (habit_id, day)
);

-- Brain Dump / Inbox
CREATE TABLE IF NOT EXISTS inbox (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  text       TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  archived   INTEGER NOT NULL DEFAULT 0,
  task_id    INTEGER REFERENCES tasks(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_inbox_user ON inbox(user_id, archived);

-- Stimmung / Energie
CREATE TABLE IF NOT EXISTS moods (
  id      INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ts      INTEGER NOT NULL,
  day     TEXT NOT NULL,
  mood    INTEGER NOT NULL,                        -- 1..5
  energy  INTEGER NOT NULL,                        -- 1..5
  focus   INTEGER NOT NULL,                        -- 1..5
  note    TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_moods_user ON moods(user_id, day);

-- Dopa (iOS): Feedback aus der App – Claude liest es per tools/feedback.js
CREATE TABLE IF NOT EXISTS feedback (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  client_id   TEXT NOT NULL,                       -- UUID aus der App, gegen Doppelte beim Nachsenden
  text        TEXT NOT NULL,
  screen      TEXT NOT NULL DEFAULT '',
  app_version TEXT NOT NULL DEFAULT '',
  created_at  INTEGER NOT NULL,                    -- wann in der App geschrieben
  received_at INTEGER NOT NULL,
  done_at     INTEGER,
  done_note   TEXT NOT NULL DEFAULT '',
  UNIQUE (user_id, client_id)
);

-- Dopa (iOS): komplette App-Daten als JSON, eine Zeile pro Nutzer
CREATE TABLE IF NOT EXISTS dopa_backups (
  user_id    INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  data       TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
`);

module.exports = db;
