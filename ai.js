'use strict';
/* Momentum / Dopa — KI-Helfer. Läuft ausschließlich serverseitig; Keys
   verlassen den Server nie. Ohne konfigurierten Anbieter sind alle Funktionen
   inaktiv und die Clients blenden die Buttons aus.

   Anbieter-Kette (der erste, der antwortet, gewinnt):
     1. OpenAI-kompatibel (z. B. IONOS AI Model Hub): AI_BASE_URL + AI_API_KEY + AI_MODEL
     2. Lokal per Ollama:                             OLLAMA_MODEL (+ OLLAMA_URL)
     3. Anthropic:                                    ANTHROPIC_API_KEY
*/

const Anthropic = require('@anthropic-ai/sdk');

const ANTHROPIC_MODEL = 'claude-opus-5';
const TIMEOUT_MS = 90_000;

function providers() {
  const list = [];
  if (process.env.AI_BASE_URL && process.env.AI_API_KEY && process.env.AI_MODEL) list.push('openai');
  if (process.env.OLLAMA_MODEL) list.push('ollama');
  if (process.env.ANTHROPIC_API_KEY) list.push('anthropic');
  return list;
}
const enabled = () => providers().length > 0;

/** Kurzbeschreibung für Statusanzeigen, z. B. „IONOS · Qwen3.5-9B (Ersatz: lokal · qwen2.5:3b)“. */
function describe() {
  const names = providers().map(p => ({
    openai: `${process.env.AI_LABEL || 'API'} · ${process.env.AI_MODEL}`,
    ollama: `lokal · ${process.env.OLLAMA_MODEL}`,
    anthropic: `Claude · ${ANTHROPIC_MODEL}`
  })[p]);
  if (!names.length) return null;
  return names.length > 1 ? `${names[0]} (Ersatz: ${names.slice(1).join(', ')})` : names[0];
}

let anthropic = null;
const getAnthropic = () => anthropic || (anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY }));

/* Haltung des Assistenten. Bewusst nicht der übliche Produktivitäts-Ton:
   kein Anfeuern, kein Erklären, warum etwas wichtig ist — nur der nächste Griff. */
// Wer die App nutzt (Alter, Alltag …) steht nur auf dem Server in .env (DOPA_PERSON) – das Repo ist öffentlich.
const PERSON = (process.env.DOPA_PERSON || 'eine Person mit ADHS').trim();
const MONEY_PERSON = (process.env.DOPA_MONEY_PERSON || 'einer Person mit ADHS, wenig Geld, neigt zu Spontankäufen und kleinen Ratenzahlungen').trim();

const VOICE = `Du hilfst einer Person mit ADHS in einer deutschen ADHS-App.

Wie du schreibst:
- Direkt und warm. Wie ein Kumpel, der die Sache schon hundertmal gemacht hat.
- Keine Motivationssprüche, kein "Du schaffst das!", keine Emojis am Satzanfang.
- Keine Belehrungen darüber, warum eine Aufgabe wichtig ist. Das weiß die Person.
- Duzen. Kurze Sätze. Konkrete Substantive statt abstrakter Verben.

Was du über ADHS mitdenkst:
- Der Einstieg ist die Hürde, nicht die Aufgabe. Der erste Schritt muss so klein
  sein, dass er sich albern anfühlt.
- "Sachen zusammensuchen" ist ein eigener Schritt. Aufräumen danach auch.
- Termine ausmachen, Anrufe und alles mit Wartezeit sind eigene Schritte.
- Zeitschätzungen realistisch halten, nicht optimistisch. Lieber großzügig.
- Nie moralisieren, wenn etwas liegen geblieben ist.`;

/* Antworttext → JSON. Kleine Modelle packen gern Codezäune oder <think>-Blöcke drumherum. */
function parseJSON(text) {
  const cleaned = String(text || '')
    .replace(/<think>[\s\S]*?<\/think>/g, '')
    .replace(/^\s*```(?:json)?\s*/i, '').replace(/\s*```\s*$/, '')
    .trim();
  try { return JSON.parse(cleaned); } catch {}
  const start = cleaned.indexOf('{'), end = cleaned.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try { return JSON.parse(cleaned.slice(start, end + 1)); } catch {}
  }
  throw Object.assign(new Error('Unerwartete Antwort der KI'), { code: 'parse' });
}

async function postJSON(url, body, headers = {}) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(TIMEOUT_MS)
  });
  const text = await res.text();
  if (!res.ok) throw Object.assign(new Error(`HTTP ${res.status}: ${text.slice(0, 200)}`), { status: res.status });
  return JSON.parse(text);
}

const schemaHint = schema =>
  `\n\nAntworte AUSSCHLIESSLICH mit einem JSON-Objekt nach diesem Schema, ohne weiteren Text:\n${JSON.stringify(schema)}`;

const sleep = ms => new Promise(r => setTimeout(r, ms));

/* OpenAI-kompatibel (Gemini, IONOS u. a.). Probiert erst das gewünschte Modell, dann
   AI_MODEL – so landet ein überlastetes großes Modell beim kleinen desselben Anbieters
   statt beim viel schwächeren lokalen. Überlastung (429/5xx) bekommt einen zweiten Versuch. */
async function askOpenAI(args) {
  const models = [...new Set([args.model, process.env.AI_MODEL].filter(Boolean))];
  let lastError;
  for (const model of models) {
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        return await askOpenAIModel({ ...args, model });
      } catch (e) {
        lastError = e;
        const busy = e.status === 429 || (e.status >= 500 && e.status < 600);
        if (!busy || attempt === 1) break;
        await sleep(800);
      }
    }
  }
  throw lastError;
}

/* Ein Modell. Erst echtes JSON-Schema; kennt der Anbieter das nicht (400/422),
   nochmal mit json_object und dem Schema im Prompt. */
async function askOpenAIModel({ system, user, schema, maxTokens, model, media }) {
  const url = process.env.AI_BASE_URL.replace(/\/+$/, '') + '/chat/completions';
  const headers = { Authorization: `Bearer ${process.env.AI_API_KEY}` };
  // Bilder als data-URL, Ton als input_audio (so versteht es Geminis OpenAI-Schnittstelle)
  const content = media?.length
    ? [{ type: 'text', text: user }, ...media.map(m => m.kind === 'audio'
        ? { type: 'input_audio', input_audio: { data: m.data, format: m.format || 'wav' } }
        : { type: 'image_url', image_url: { url: `data:${m.mime || 'image/jpeg'};base64,${m.data}` } })]
    : user;
  const base = {
    model,
    max_tokens: maxTokens,
    temperature: 0.3,
    messages: [{ role: 'system', content: system }, { role: 'user', content }]
  };
  let res;
  try {
    res = await postJSON(url, { ...base, response_format: { type: 'json_schema', json_schema: { name: 'antwort', schema, strict: true } } }, headers);
  } catch (e) {
    if (e.status !== 400 && e.status !== 422) throw e;
    res = await postJSON(url, {
      ...base,
      messages: [{ role: 'system', content: system + schemaHint(schema) }, base.messages[1]],
      response_format: { type: 'json_object' }
    }, headers);
  }
  return { data: parseJSON(res.choices?.[0]?.message?.content), usage: res.usage, provider: 'openai' };
}

/* Lokal per Ollama: das Schema wird als Grammatik erzwungen. */
async function askOllama({ system, user, schema, maxTokens }) {
  const url = (process.env.OLLAMA_URL || 'http://127.0.0.1:11434').replace(/\/+$/, '') + '/api/chat';
  const res = await postJSON(url, {
    model: process.env.OLLAMA_MODEL,
    stream: false,
    format: schema,
    keep_alive: '5m',
    options: { temperature: 0.2, num_ctx: 4096, num_predict: maxTokens },
    messages: [{ role: 'system', content: system + '\n\nAntworte nur auf Deutsch.' }, { role: 'user', content: user }]
  });
  return { data: parseJSON(res.message?.content), usage: { output_tokens: res.eval_count }, provider: 'ollama' };
}

async function askAnthropic({ system, user, schema, effort, maxTokens }) {
  const res = await getAnthropic().messages.create({
    model: ANTHROPIC_MODEL,
    max_tokens: maxTokens,
    system: [{ type: 'text', text: system, cache_control: { type: 'ephemeral' } }],
    messages: [{ role: 'user', content: user }],
    output_config: { effort, format: { type: 'json_schema', schema } }
  });
  const text = res.content.filter(b => b.type === 'text').map(b => b.text).join('');
  return { data: parseJSON(text), usage: res.usage, provider: 'anthropic' };
}

/* Ein Aufruf über die Anbieter-Kette. `big: true` nimmt – falls gesetzt – AI_MODEL_BIG. */
async function ask({ system, user, schema, effort = 'low', maxTokens = 2000, big = false, media }) {
  // Bilder/Ton (Fotos, Screenshots, Sprache) kann nur der OpenAI-kompatible Anbieter (Gemini)
  const chain = media?.length ? providers().filter(p => p === 'openai') : providers();
  if (!chain.length) throw Object.assign(new Error(media?.length ? 'Fotos und Sprache brauchen Gemini' : 'KI ist nicht konfiguriert'), { code: 'no_key' });
  const full = VOICE + '\n\n' + system;
  let lastError;
  for (const p of chain) {
    try {
      if (p === 'openai') return await askOpenAI({ system: full, user, schema, maxTokens, media, model: big ? process.env.AI_MODEL_BIG : undefined });
      if (p === 'ollama') return await askOllama({ system: full, user, schema, maxTokens });
      if (p === 'anthropic') return await askAnthropic({ system: full, user, schema, effort, maxTokens });
    } catch (e) {
      lastError = e;
      console.error(`[ai:${p}]`, e.message);
    }
  }
  throw lastError;
}

const obj = (props, required) => ({
  type: 'object', properties: props, required: required || Object.keys(props), additionalProperties: false
});

/* ---------------------------------------------------------------
   1. Zerlegen — „Magic ToDo" in eigener Auslegung.
   Statt Schärfegraden eine Auflösung: wie nah zoomt man ran?
   --------------------------------------------------------------- */
const RESOLUTION = {
  1: 'Grobe Etappen. 3-4 Schritte, jeder darf ein halber Nachmittag sein.',
  2: 'Normale Schritte. 4-6 Stück, jeder in einem Rutsch machbar.',
  3: 'Kleine Schritte. 5-8 Stück, keiner länger als 20 Minuten.',
  4: 'Sehr kleine Schritte. 6-10 Stück, jeder unter 10 Minuten, Vorbereitung einzeln.',
  5: 'Winzige Schritte. 8-14 Stück. Jeder einzelne Handgriff steht da — aufstehen, Ordner holen, Deckel auf. Der erste Schritt darf lächerlich klein sein.'
};

const stepsSchema = obj({
  steps: {
    type: 'array', minItems: 2, maxItems: 14,
    items: obj({
      title: { type: 'string', description: 'Der Schritt als Handlung, max. 80 Zeichen' },
      est_min: { type: 'integer', minimum: 1, maximum: 240 }
    })
  },
  opener: { type: 'string', description: 'Ein Satz: womit man in den nächsten 60 Sekunden anfängt' }
});

async function breakdown({ title, notes, resolution = 3, energy = 'med' }) {
  const level = RESOLUTION[Math.min(5, Math.max(1, resolution))] || RESOLUTION[3];
  const energyHint = { low: 'Die Person hat gerade wenig Energie — die ersten Schritte müssen besonders anspruchslos sein.',
    med: '', high: 'Die Person hat gerade viel Energie — die ersten Schritte dürfen direkt zur Sache gehen.' }[energy] || '';

  return ask({
    system: `Du zerlegst eine Aufgabe in Schritte.

Auflösung: ${level}
${energyHint}

Regeln:
- Jeder Schritt beginnt mit einem Verb und beschreibt eine sichtbare Handlung.
- Kein Schritt heißt "anfangen", "sich kümmern", "organisieren" oder "planen" —
  das sind keine Handlungen, sondern Wünsche.
- Wenn etwas Warten beinhaltet (Post, Rückruf, Termin), ist das Losschicken ein
  Schritt und das Nachfassen ein zweiter.
- Reihenfolge so, dass der erste Schritt der leichteste ist.
- est_min großzügig schätzen. Lieber zu viel.
- "opener" ist ein einziger Satz, der die allererste körperliche Handlung nennt.`,
    user: `Aufgabe: ${title}${notes ? `\n\nNotizen dazu: ${notes}` : ''}`,
    schema: stepsSchema,
    effort: 'medium'
  });
}

/* ---------------------------------------------------------------
   2. Schätzen — realistische Dauer statt Wunschdenken
   --------------------------------------------------------------- */
async function estimate({ title, notes }) {
  return ask({
    system: `Schätze, wie lange die Aufgabe wirklich dauert — inklusive Suchen,
Anlaufen und Aufräumen. Menschen mit ADHS unterschätzen systematisch, also rechne
den Puffer schon ein. "note" ist ein kurzer Satz, was in der Schätzung mit drinsteckt.`,
    user: `Aufgabe: ${title}${notes ? `\n\nNotizen: ${notes}` : ''}`,
    schema: obj({
      est_min: { type: 'integer', minimum: 1, maximum: 480 },
      note: { type: 'string' }
    })
  });
}

/* ---------------------------------------------------------------
   3. Sortieren — Brain-Dump-Chaos wird Struktur
   --------------------------------------------------------------- */
async function compile({ text }) {
  return ask({
    system: `Du bekommst einen ungeordneten Gedanken-Dump und machst daraus Aufgaben.

Regeln:
- Was keine Aufgabe ist (Gefühle, Feststellungen, Ideen ohne Handlung), kommt
  nach "notes" und wird NICHT zur Aufgabe.
- Zusammengehörendes zusammenfassen: "Kabel bestellen und Halterung" ist eine
  Aufgabe mit zwei Unterschritten, nicht zwei Aufgaben.
- energy: wie anstrengend die Aufgabe für jemanden mit ADHS ist. Telefonate,
  Behörden und alles Ungewisse sind "high", auch wenn sie kurz sind.
- Titel in der Sprache und dem Ton des Dumps lassen, nur aufgeräumt.
- Höchstens 12 Aufgaben. Lieber bündeln als aufsplitten.`,
    user: text,
    schema: obj({
      tasks: {
        type: 'array', maxItems: 12,
        items: obj({
          title: { type: 'string' },
          energy: { type: 'string', enum: ['low', 'med', 'high'] },
          est_min: { type: 'integer', minimum: 1, maximum: 480 },
          subs: { type: 'array', maxItems: 6, items: { type: 'string' } }
        })
      },
      notes: { type: 'string', description: 'Was kein Task war, in einem Satz zusammengefasst. Leer wenn nichts.' }
    }),
    effort: 'medium'
  });
}

/* ---------------------------------------------------------------
   4. Umschreiben — für Nachrichten, die seit Tagen liegen
   --------------------------------------------------------------- */
const MODES = {
  formell: 'Formell und geschäftlich, ohne steif zu klingen.',
  locker: 'Locker und freundlich, wie unter Kollegen.',
  kurz: 'So kurz wie möglich. Jeder Satz, der weg kann, kommt weg.',
  klar: 'Klarer strukturieren. Die Bitte oder Frage muss im ersten Satz stehen.',
  sanft: 'Weicher formulieren, ohne die Aussage zu ändern. Nimm Schärfe raus.',
  bestimmt: 'Bestimmter formulieren. Weg mit "vielleicht", "eigentlich", "nur kurz", "sorry".',
  absage: 'Als freundliche Absage. Kein ausufernder Rechtfertigungsteil.',
  entschuldigung: 'Als Entschuldigung für etwas Liegengebliebenes. Sachlich, ohne Selbstgeißelung.'
};

async function rewrite({ text, mode }) {
  const instruction = MODES[mode] || MODES.klar;
  return ask({
    system: `Schreibe den Text der Person um. Zielrichtung: ${instruction}

Regeln:
- Die Aussage bleibt. Du erfindest keine Fakten, Termine oder Zusagen dazu.
- Kein Kommentar, keine Erklärung — nur der neue Text in "result".
- Gleiche Sprache wie das Original.
- "changed" nennt in einem Halbsatz, was du gedreht hast.`,
    user: text,
    schema: obj({ result: { type: 'string' }, changed: { type: 'string' } })
  });
}

/* ---------------------------------------------------------------
   5. Einordnen — gegen das Kopfkino bei empfangenen Nachrichten
   --------------------------------------------------------------- */
async function interpret({ text }) {
  return ask({
    system: `Die Person hat diese Nachricht bekommen und ist unsicher, wie sie
gemeint ist. Das ist bei ADHS häufig — Zurückweisung wird schneller gelesen als
sie dasteht.

Deine Aufgabe:
- "literal": was da wörtlich steht, nüchtern zusammengefasst.
- "tone": der wahrscheinlichste Tonfall. Sei ehrlich — wenn jemand genervt ist,
  sag das. Beschönigen hilft nicht.
- "temperature": 1 = ausgesprochen freundlich, 3 = neutral/sachlich, 5 = deutlich verärgert.
- "overthinking": was die Person hineinlesen könnte, das objektiv nicht dasteht.
  Leer lassen, wenn die Nachricht wirklich negativ ist — dann nichts weglügen.
- "reply": ein knapper Antwortvorschlag, den man abschicken kann.`,
    user: text,
    schema: obj({
      literal: { type: 'string' },
      tone: { type: 'string' },
      temperature: { type: 'integer', minimum: 1, maximum: 5 },
      overthinking: { type: 'string' },
      reply: { type: 'string' }
    }),
    effort: 'medium'
  });
}

/* ---------------------------------------------------------------
   6. Was jetzt? — Auswahl nach Zustand, nicht nach Reihenfolge
   --------------------------------------------------------------- */
async function whatNow({ tasks, mood, focusToday, hour }) {
  const list = tasks.map(t =>
    `#${t.id} | ${t.title} | Energie ${t.energy} | ca. ${t.est_min}min${t.starred ? ' | markiert' : ''}${t.parentTitle ? ` | Schritt von: ${t.parentTitle}` : ''}`
  ).join('\n');

  const state = [
    `Uhrzeit: ${hour}:00`,
    mood ? `Letzter Check-in — Stimmung ${mood.mood}/5, Energie ${mood.energy}/5, Fokus ${mood.focus}/5` : 'Heute noch kein Check-in',
    focusToday ? `Heute schon ${Math.round(focusToday / 60)} Minuten fokussiert gearbeitet` : 'Heute noch keine Fokuszeit'
  ].join('\n');

  return ask({
    system: `Wähle aus der Liste GENAU EINE Aufgabe, die jetzt dran ist.

Wonach du entscheidest:
- Zustand schlägt Wichtigkeit. Bei niedriger Energie eine kleine Aufgabe, auch
  wenn eine große dringender wäre. Ein erledigter Kleinkram ist mehr wert als
  eine große Aufgabe, die wieder nicht angefasst wird.
- Spät am Abend nichts Anstrengendes mehr vorschlagen.
- Wer heute noch gar nichts geschafft hat, braucht einen leichten Einstieg.
- Wer schon lange fokussiert war, darf etwas Leichtes bekommen.

- "task_id" ist die Zahl hinter dem #.
- "why" ist EIN Satz, warum gerade die. Sprich die Person direkt an. Keine Floskeln.
- "first_move" ist die allererste körperliche Handlung, in unter 10 Wörtern.
- "minutes" ist ein realistischer Fokus-Block dafür (5, 10, 15, 25 oder 45).`,
    user: `Zustand:\n${state}\n\nOffene Aufgaben:\n${list}`,
    schema: obj({
      task_id: { type: 'integer' },
      why: { type: 'string' },
      first_move: { type: 'string' },
      minutes: { type: 'integer', enum: [5, 10, 15, 25, 45] }
    }),
    effort: 'medium'
  });
}

/* ---------------------------------------------------------------
   7. Wiedereinstieg — nach Abbruch zurück in die Aufgabe
   --------------------------------------------------------------- */
async function reentry({ title, notes, doneSteps, openSteps, minutesAgo }) {
  return ask({
    system: `Die Person war an dieser Aufgabe dran, ist rausgeflogen und kommt jetzt
zurück. Der Wiedereinstieg ist die eigentliche Hürde — nicht die Aufgabe.

- "where": wo sie vermutlich stand, in einem Satz. Kein Vorwurf, keine Wertung.
- "reentry": drei winzige Handgriffe, um wieder reinzukommen. Der erste darf
  reines Aufwärmen sein (Datei öffnen, hinsetzen, Zettel rausholen).
- "next": der eine Schritt, der danach dran ist.`,
    user: `Aufgabe: ${title}${notes ? `\nNotizen: ${notes}` : ''}
Vor ${minutesAgo} Minuten unterbrochen.
Schon erledigt: ${doneSteps.length ? doneSteps.join(', ') : 'nichts'}
Noch offen: ${openSteps.length ? openSteps.join(', ') : 'keine Teilschritte angelegt'}`,
    schema: obj({
      where: { type: 'string' },
      reentry: { type: 'array', minItems: 3, maxItems: 3, items: { type: 'string' } },
      next: { type: 'string' }
    })
  });
}

/* ---------------------------------------------------------------
   Dopa (iOS): zustandslos – die App schickt Text, bekommt Struktur zurück.
   Mit Beispielen im Prompt, damit auch kleine Modelle brauchbar antworten.
   --------------------------------------------------------------- */
const STEP_EXAMPLES = `Beispiele:
Aufgabe: Wäsche waschen → {"step":"Nur die Wäsche in einen Korb werfen"}
Aufgabe: Steuererklärung → {"step":"Nur den Ordner mit den Belegen hinlegen"}
Aufgabe: Oma anrufen → {"step":"Nur die Nummer im Handy öffnen"}
Aufgabe: Arzttermin machen → {"step":"Nur die Website der Praxis öffnen"}
Aufgabe: Präsentation vorbereiten → {"step":"Nur eine leere Folie mit dem Titel anlegen"}`;

async function firstStep({ title }) {
  return ask({
    system: `Gib für die Aufgabe den winzigsten ersten Schritt: EINE sichtbare Handlung,
höchstens 9 Wörter, beginnt mit "Nur". Der Schritt darf nie die ganze Aufgabe sein —
"Nur Termin machen" ist falsch, "Nur die Website der Praxis öffnen" ist richtig.

${STEP_EXAMPLES}`,
    user: `Aufgabe: ${title}`,
    schema: obj({ step: { type: 'string' } }),
    maxTokens: 120
  });
}

/* Smart Dump: „ich muss X, um Y zu machen“ → Plan mit Reihenfolge. */
const PLAN_SCOPES = {
  task: 'Es geht um EINE Aufgabe: zerlege sie in 3–6 Schritte (jeder Schritt ist ein Eintrag in "tasks").',
  day: 'Mach einen realistischen Plan für HEUTE: höchstens 6 Aufgaben, mit Puffer, Wichtiges zuerst.',
  week: 'Mach einen Wochenplan: höchstens 8 Aufgaben, verteilt auf die Woche, mit freien Puffern. Beginne jeden Titel mit dem Wochentag ("Mo:", "Di:" …).'
};

async function plan({ text, scope }) {
  const scopeHint = PLAN_SCOPES[scope] || '';
  return ask({
    system: `Die Person schreibt oder erzählt ungeordnet, was sie vorhat oder was ansteht — oft mit
Abhängigkeiten ("ich muss X, um Y zu machen"). Mach daraus einen Plan.
${scopeHint}

Regeln:
- "tasks": die Aufgaben in der Reihenfolge, in der man sie machen muss
  (Voraussetzungen zuerst). Höchstens 8. Lieber bündeln als zersplittern.
- Jede Aufgabe: "title" kurz (max. 6 Wörter, beginnt nicht mit "ich"),
  "step" = winzigster erster Schritt (beginnt mit "Nur", max. 9 Wörter),
  "minutes" = realistische Dauer mit Puffer.
- Was keine Aufgabe ist (Gefühle, Feststellungen), kommt in "note" (ein Satz, sonst leer).
- "summary": ein kurzer Satz, was der Plan erreicht.

Beispiel:
Text: "muss bewerbung schicken aber dafür erst lebenslauf updaten und foto machen lassen, bin voll gestresst"
→ {"summary":"Bewerbung raus, mit neuem Lebenslauf und Foto.","tasks":[
{"title":"Bewerbungsfoto machen lassen","step":"Nur ein Fotostudio in der Nähe suchen","minutes":45},
{"title":"Lebenslauf aktualisieren","step":"Nur die alte Lebenslauf-Datei öffnen","minutes":40},
{"title":"Bewerbung abschicken","step":"Nur die Stellenanzeige nochmal öffnen","minutes":30}],
"note":"Stress ist okay – der Plan nimmt dir die Reihenfolge ab."}`,
    user: `Text: ${text}`,
    schema: obj({
      summary: { type: 'string' },
      tasks: {
        type: 'array', minItems: 1, maxItems: 8,
        items: obj({
          title: { type: 'string' },
          step: { type: 'string' },
          minutes: { type: 'integer', minimum: 1, maximum: 480 }
        })
      },
      note: { type: 'string' }
    }),
    maxTokens: 1200,
    big: true,
    effort: 'medium'
  });
}

/* Smart Dump: alles Erzählte automatisch einsortieren – Aufgaben (mit Tag),
   Erinnerungen (mit Uhrzeit), Einkauf, Merken. Tage als Abstand zu heute. */
const DUMP_RULES = `Sortiere ALLES ein:

- "tasks": Dinge, die sie tun muss. "title" kurz (max. 6 Wörter, nicht mit "ich" anfangen),
  "step" = winzigster erster Schritt (beginnt mit "Nur", max. 9 Wörter), "minutes" realistisch,
  "day" = an welchem Tag: 0 = heute, 1 = morgen, 2 = übermorgen … bis 13. Wird ein Wochentag
  genannt, rechne den Abstand von heute aus. Ohne Tagesangabe: -1.
  Reihenfolge: Voraussetzungen zuerst ("um Y zu machen, muss ich erst X" → X vor Y).
- "reminders": nur wenn eine konkrete UHRZEIT genannt wird ("um 8", "18 Uhr").
  "title" kurz, "time" als "HH:MM", "day" wie oben (ohne Tag: 0).
- "shopping": Sachen zum Einkaufen, einzeln, ohne Mengenwörter ("Milch", "Brot").
- "notes": Dinge zum Merken, keine Handlung: wo etwas liegt, was jemand gesagt hat,
  was schon erledigt ist. Als kurzer Satz.
- "schedule": NUR wenn die Person ausdrücklich um einen Zeitplan bittet ("plane meinen Morgen",
  "mach mir einen Plan für heute", "wann mach ich was"). Dann ein Ablauf mit Uhrzeiten:
  "start" als "HH:MM", "minutes" realistisch MIT Puffer (Menschen mit ADHS unterschätzen Zeit:
  rechne 30–50 % drauf), kurze Pausen als eigene Blöcke bei mehr als 90 Minuten am Stück,
  "title", "step" (winziger erster Schritt, beginnt mit "Nur"), "day" wie oben.
  Start: genannte Uhrzeit, sonst der nächste sinnvolle Zeitpunkt (heute frühestens jetzt + 10 Min,
  "morgen früh" ab 8:00). Feste Termine, die genannt werden ("um 14 Uhr Arbeit"), kommen als
  eigener Block rein, davor ein Block "Losgehen" mit Puffer für den Weg; plane nichts darüber hinaus.
  Was im Zeitplan steht, NICHT zusätzlich in "tasks" oder "reminders".
- "summary": ein kurzer Satz, was du einsortiert hast.

Aufträge von anderen sind Aufgaben für die Person: "Frau M. sagt, ich soll bis Freitag 20 Kopien machen",
"Lehrerin will das Plakat fertig", "Chef: Liste bis Montag" → task mit Frist als "day"; wer es wollte, kurz in den
title ("Kopien für Frau M."). Umgangssprache, Tippfehler und Abkürzungen wohlwollend verstehen (zhs = zu Hause,
Kl. 3b = Klasse 3b, AB = Arbeitsblatt, AG, Elternbrief …). Bei Unklarem lieber eine schlichte Aufgabe mit den
eigenen Worten der Person als gar nichts.

Nichts erfinden. Was in keine Kategorie passt (Gefühle, Gelaber), weglassen.
Dasselbe nicht doppelt: eine Aufgabe mit Uhrzeit ist eine Erinnerung, keine Aufgabe.`;

const DUMP_SCHEMA = obj({
      summary: { type: 'string' },
      tasks: {
        type: 'array', maxItems: 12,
        items: obj({
          title: { type: 'string' }, step: { type: 'string' },
          minutes: { type: 'integer', minimum: 1, maximum: 480 },
          day: { type: 'integer', minimum: -1, maximum: 13 }
        })
      },
      reminders: {
        type: 'array', maxItems: 8,
        items: obj({ title: { type: 'string' }, time: { type: 'string' }, day: { type: 'integer', minimum: 0, maximum: 13 } })
      },
      shopping: { type: 'array', maxItems: 20, items: { type: 'string' } },
      notes: { type: 'array', maxItems: 8, items: { type: 'string' } },
      schedule: {
        type: 'array', maxItems: 14,
        items: obj({
          start: { type: 'string' }, title: { type: 'string' }, step: { type: 'string' },
          minutes: { type: 'integer', minimum: 5, maximum: 240 },
          day: { type: 'integer', minimum: 0, maximum: 13 }
        })
      }
    });

async function dump({ text, todayLabel }) {
  return ask({
    system: `Die Person hat frei erzählt oder getippt, was ansteht. ${DUMP_RULES}`,
    user: `Heute ist ${todayLabel}.\n\nText: ${text}`,
    schema: DUMP_SCHEMA,
    maxTokens: 2400,
    big: true,
    effort: 'medium'
  });
}

/* Foto statt Tippen: Zettel, Brief, Kühlschrank, Whiteboard → dieselben Kategorien wie der Smart Dump. */
async function photoDump({ image, mime, todayLabel, hint }) {
  return ask({
    system: `Die Person hat ein Foto gemacht statt zu tippen – z. B. einen Einkaufszettel, einen Brief mit Frist,
einen Stundenplan, ein Whiteboard, einen offenen Kühlschrank oder ein leeres Regal.
Lies ab, was darauf steht oder was fehlt, und ${DUMP_RULES}
Bei einem Kühlschrank/Regal: nur offensichtlich Fehlendes oder fast Leeres als "shopping".
Bei einem Brief mit Frist: eine Aufgabe mit passendem "day".`,
    user: `Heute ist ${todayLabel}.${hint ? `\nHinweis der Person: ${hint}` : ''}\n\nWas ist auf dem Foto zu tun, zu kaufen oder zu merken?`,
    schema: DUMP_SCHEMA,
    media: [{ kind: 'image', mime, data: image }],
    maxTokens: 2400,
    big: true
  });
}

/* Notiz-Foto: kurzer Satz, was drauf ist – spart das Tippen. */
async function photoCaption({ image, mime, todayLabel }) {
  return ask({
    system: `Beschreibe das Foto für eine Merk-Notiz in EINEM kurzen deutschen Satz (max. 12 Wörter),
so dass man es später per Suche findet. Wenn ein Gegenstand irgendwo liegt: "Schlüssel liegt auf der Kommode".
Wenn etwas erledigt aussieht (Herd aus, Tür zu): "Herd ist aus". Steht Text drauf (Zettel, Tafel, Arbeitsblatt,
Handschrift): lies ihn genau und fasse das Wichtigste zusammen.
"kind": place (wo etwas liegt), done (etwas ist erledigt/aus/zu), agreement (Absprache/Auftrag/Zettel von jemandem), note (sonst).
"task": Steht drauf, dass die Person etwas TUN soll (Auftrag einer Lehrkraft oder vom Chef, Frist, „bitte bis …“,
Arbeitsblatt kopieren, Material vorbereiten), dann die Aufgabe kurz (max. 6 Wörter, wer es will darf rein:
"Kopien für Frau M."). Sonst "". "day": Frist als Tage ab heute (0 heute, 1 morgen … 13), ohne Frist -1.`,
    user: `Heute ist ${todayLabel}. Was ist auf dem Foto?`,
    schema: obj({
      caption: { type: 'string' },
      kind: { type: 'string', enum: ['place', 'done', 'agreement', 'note'] },
      task: { type: 'string' },
      day: { type: 'integer' }
    }),
    media: [{ kind: 'image', mime, data: image }],
    maxTokens: 260
  });
}

/* Screenshot aus Banking- oder Klarna-App: Zahlungen und offene Raten herauslesen, kurz einordnen. */
async function moneyScan({ image, mime, todayLabel, known }) {
  return ask({
    system: `Auf dem Screenshot ist eine Banking-App, PayPal oder Klarna. Lies die Zahlungen heraus.
- "entries": einzelne Buchungen. "title" = Händler/Person kurz (z. B. "Lidl", "Spotify", "Oma"),
  "amount" positiv in Euro, "income" true bei Geldeingang, "date" als YYYY-MM-DD (fehlt das Jahr: aktuelles Jahr).
- "debts": NUR offene, noch nicht bezahlte Rechnungen oder Raten (Klarna "fällig am", "noch X Raten").
  "title" z. B. "Klarna – Zalando", "amount" = Betrag pro Zahlung, "due" = nächste Fälligkeit YYYY-MM-DD,
  "remaining" = wie viele Zahlungen noch (einmalig = 1).
- "tips": höchstens 3 kurze, konkrete Hinweise zu dem, was du siehst (z. B. "3× Lieferando diese Woche – 42 €").
  Kein Moralisieren, keine Schuld. Wenn nichts auffällt: leere Liste.
- "balance": der aktuelle KONTOSTAND, falls zu sehen – bei der Sparkasse die große (meist grüne, bei Minus rote)
  Zahl oben unter dem Kontonamen, sonst „Kontostand“/„Saldo“/„verfügbar“. Minus als negative Zahl.
  "hasBalance" = true nur dann, sonst false und balance 0. "account" = Kontoname kurz ("Sparkasse Girokonto"), sonst "".
  Der Kontostand ist KEINE Buchung – nicht in "entries".
Nichts erfinden. Kontonummern, IBAN und Namen von Fremden NICHT übernehmen.`,
    user: `Heute ist ${todayLabel}.${known ? `\nSchon eingetragen (nicht als neu melden, trotzdem aufführen): ${known}` : ''}`,
    schema: obj({
      entries: {
        type: 'array', maxItems: 40,
        items: obj({ title: { type: 'string' }, amount: { type: 'number' }, income: { type: 'boolean' }, date: { type: 'string' } })
      },
      debts: {
        type: 'array', maxItems: 12,
        items: obj({ title: { type: 'string' }, amount: { type: 'number' }, due: { type: 'string' }, remaining: { type: 'integer' } })
      },
      tips: { type: 'array', maxItems: 3, items: { type: 'string' } },
      balance: { type: 'number' },
      hasBalance: { type: 'boolean' },
      account: { type: 'string' }
    }),
    media: [{ kind: 'image', mime, data: image }],
    maxTokens: 2400,
    big: true
  });
}

/* Geld-Tipps aus dem Tagebuch: worauf die Person achten könnte – ohne Moral. */
async function moneyTips({ summary }) {
  return ask({
    system: `Du schaust auf das Geld-Tagebuch von ${MONEY_PERSON}.
Gib höchstens 3 kurze, konkrete Tipps (je max. 140 Zeichen), was ihr diesen Monat
am meisten hilft. Beziehe dich auf echte Zahlen aus der Übersicht. Kein Moralisieren, keine Schuld, kein "du solltest".
Gut: "Lieferando war 4× dabei (48 €). Einmal die Woche vorkochen spart grob 30 €."`,
    user: summary,
    schema: obj({ tips: { type: 'array', maxItems: 3, items: { type: 'string' } } }),
    maxTokens: 400
  });
}

/* Sprache: Gemini hört die Aufnahme selbst – versteht schnelles, durcheinander Gesprochenes
   viel besser als die Diktat-Erkennung. Nur abschreiben, nichts zusammenfassen. */
async function transcribe({ audio, format, hints }) {
  return ask({
    system: `Schreibe die Sprachaufnahme wörtlich auf Deutsch ab. Satzzeichen setzen, Füllwörter (äh, ähm) weglassen,
sonst NICHTS ändern, nichts zusammenfassen, nichts ergänzen. Zahlen und Uhrzeiten als Ziffern ("um 8", "14:30").
Wenn nichts Verständliches drauf ist: leerer Text.`,
    user: hints ? `Wörter, die vorkommen könnten: ${hints}` : 'Bitte abschreiben.',
    schema: obj({ transcript: { type: 'string' } }),
    media: [{ kind: 'audio', format, data: audio }],
    maxTokens: 3000
  });
}

/* Dot: der kleine Assistent in Dopa. Kurz, konkret, nie belehrend. */
async function dotAnswer({ question, name, level, context }) {
  return ask({
    system: `Du bist ${name || 'Dot'}, der kleine Assistent in der App Dopa (Level ${level || 1}).
Du begleitest ${PERSON}.

So antwortest du:
- Höchstens 4 kurze Sätze. Lieber eine konkrete nächste Handlung als eine Erklärung.
- Wenn es um Anfangen geht: der winzigste erste Schritt, beginnt mit "Nur".
- Kein Therapeuten-Ton, keine Diagnosen, keine Motivationssprüche.
- Bei Kritik oder Streit: erst ernst nehmen, dann sachlich sortieren.
- Wenn es ernst klingt (Selbstverletzung, Krise): ruhig an die Telefonseelsorge 0800 111 0 111 verweisen.
- Du kennst die offenen Aufgaben (unten) und darfst darauf Bezug nehmen.`,
    user: `${context ? `Kontext:\n${context}\n\n` : ''}Frage: ${question}`,
    schema: obj({ answer: { type: 'string' } }),
    maxTokens: 400
  });
}

/* Dot im Gespräch: kennt den Verlauf und den Tag, schlägt Dinge zum Antippen vor
   (die App legt nichts ohne Tipp an) und bietet passende Antworten als Knöpfe an. */
async function dotChat({ name, level, context, history, message, media }) {
  const me = name || 'Dot';
  const talk = history.map(m => `${m.fromDot ? me : 'Ich'}: ${m.text}`).join('\n');
  return ask({
    system: `Du bist ${me}, der kleine Begleiter in der App Dopa (Level ${level || 1}).
Du sprichst mit ${PERSON}. Deutsch, du-Form.

So denkst du:
- Du bist ein schlauer Assistent, kein Motivations-Automat. Versteh zuerst, was die Person WILL, und beantworte
  genau das. Fragt sie etwas, antworte darauf. Will sie etwas an der App ändern, mach einen Vorschlag dafür.
- Denk die Situation zu Ende, mit echten Uhrzeiten (siehe „Jetzt“). Beispiel: „Ich hab 30 Minuten Pause, danach
  Theorieblock“ → die 30 Minuten SIND Pause: schlag vor, wie sie sich gut anfühlt (essen, trinken, raus, kurz
  hinlegen, Handy weg) – gern mit Zeiten, z. B. „bis 10:20 essen und raus, 10:25 zurück und Sachen hinlegen“.
  Plane nicht in die Pause hinein Arbeit, und keine sinnlosen Mini-Befehle wie „Schlag das Buch nur auf“.
- Mini-Schritte („Nur …“) NUR, wenn die Person sagt, dass sie nicht anfangen kann oder festhängt. Sonst normal reden.
- Wenn alles zu viel ist: EINE Sache auswählen, den Rest ausdrücklich liegen lassen dürfen.

Bei Ärger, Wut, Frust:
- Nicht anfeuern, nicht „lass die Wut raus“, nicht „mach weiter so“, kein Witz, nichts, was ironisch klingen kann.
- Kurz und echt zeigen, dass du es verstanden hast („Klingt echt nervig.“), dann fragen, was gerade hilft,
  oder einen konkreten, ruhigen Vorschlag machen. Wut nie bestärken, nie bewerten.

So antwortest du ("answer"):
- Kurz: meist 1–3 Sätze, höchstens 5. Kein Listen-Roman.
- Nutze den Kontext (Aufgaben, Termine, Notizen, Einkauf, Check-in) wie jemand, der den Tag kennt –
  aber zitiere ihn nicht stumpf. Wenn nach einem Ort gefragt wird ("wo ist …"), schau in die Notizen.
- Erfinde keine Termine, Orte oder Fakten. Wenn du etwas nicht weißt, sag es in einem halben Satz.
- Steht im Kontext eine „Apple Watch“-Zeile (Schlaf, Schritte, Bewegung): danach strukturieren, ohne zu werten.
  Kurze Nacht → weniger und kleinere Schritte, Schweres eher später oder morgen, Pausen. Wenig Schritte und
  langes Sitzen → eine kurze Bewegungspause (5 Min raus) zwischen zwei Aufgaben. Zahlen nicht vorhalten.
- Kein Therapeuten-Ton, keine Diagnosen, keine Motivationssprüche, keine Schuld, kein Emoji.
- Bei Kritik oder Streit: erst ernst nehmen, dann sachlich sortieren.
- Wenn es ernst klingt (Selbstverletzung, Krise): ruhig und klar an die Telefonseelsorge 0800 111 0 111 verweisen.

Vorschläge zum Antippen ("actions", höchstens 4, oft keine):
- Nur wenn es wirklich hilft oder gewünscht ist ("erinner mich", "muss noch Milch kaufen", "schreib auf", "lass uns anfangen").
- kind: task = neue Aufgabe (title, step = winziger erster Schritt mit "Nur"), reminder = Erinnerung (title, time "HH:MM" Pflicht),
  shop = Einkaufsartikel (title = nur der Artikel), memo = Notiz zum Merken (title = der Satz), focus = Timer jetzt starten
  (title = woran, step = erster Schritt, minutes 5–25), done = offene Aufgabe abhaken, tomorrow = offene Aufgabe auf
  morgen schieben (bei done/tomorrow: title = GENAU der Titel aus der Aufgabenliste, nur bestehende Aufgaben).
- done nur, wenn die Person sagt, dass es erledigt ist. tomorrow, wenn heute zu viel ist oder sie es verschieben will –
  ohne Schuld, Verschieben ist völlig okay.
- steps = Schritte an eine BESTEHENDE Aufgabe hängen (title = GENAU der Titel aus der Aufgabenliste,
  items = die neuen Schritte, je ein kurzer Handgriff, max. 12). Schritte, die schon dastehen, nicht doppelt.
- task darf auch items (Schritte) haben und eine Uhrzeit (time "HH:MM" = Erinnerung an dem Tag).
- Uhrzeiten an den Morgen anpassen: Steht im Kontext, wann die Person aufsteht und los muss, leg Dinge davor
  so, dass sie zwischen Aufstehen und Losgehen passen (nicht in die letzten 10 Minuten). Abends nichts nach der Bettzeit.
- Beispiel: Aufgabe „Koffer packen“ ist offen, die Person sagt „rein müssen Medikamente, Kleidung Mo–Fr, Sportsachen,
  Ladekabel – das Kabel aber erst morgen“ → steps an „Koffer packen“ mit allem außer dem Kabel, plus task „Rest packen“
  für day 1 mit items ["Ladekabel"] und time kurz nach dem Aufstehen bzw. rechtzeitig vor dem Losgehen.
- place (bei task): Soll die Aufgabe kommen, wenn die Person an einem Ort ankommt („erinner mich zuhause/zhs …“,
  „wenn ich bei Lidl bin …“), dann place = Name des Ortes aus „Deine Orte“ (zhs/daheim = Zuhause). Ohne Uhrzeit.
  Gibt es den Ort noch nicht, trotzdem place setzen und kurz sagen: „Leg den Ort unter Profil → Orte an.“
- setting = die App einstellen, wenn die Person das will („diese Woche kein Morgen-Check“, „keine Stupser mehr“,
  „Abendroutine wieder an“). title = einer von: morning (Morgen-Check), evening (Abendroutine), nudges (Stupser),
  meals (Essens-Erinnerung), briefing (Morgen-Überblick), review (Tagesrückblick), countdown (Losgeh-Countdown),
  halfway (Timer-Halbzeit). step = "off" oder "on". Bei morning/evening + off: day = wie viele Tage Pause
  („diese Woche“ = bis nächsten Montag, aus „Jetzt“ ausrechnen; ohne Angabe 7). Den aktuellen Stand siehst du
  unter „Einstellungen“ – nichts vorschlagen, was schon so ist.
- edit = die App anpassen (alles, was unter „Morgen-Check“, „Abendroutine“, „Essens-Erinnerung“, „Gewohnheiten“,
  „Eigene Erinnerungen“, „Farbe“ im Kontext steht, plus Aufgaben und Einkaufsliste). key = einer von:
  morning.leave (time) · morning.days (items Wochentage: "Mo","Di"… oder "werktags"/"täglich") · morning.add (step = Schritt,
  minutes) · morning.remove (step = Schritt) · evening.bed (time) · evening.days · evening.add · evening.remove ·
  meals.times (items ["12:30","18:00"]) · nudges.window (items [von, bis], minutes = alle X Min) ·
  reminder.time (title = Erinnerung, time) · reminder.delete (title) · habit.add (step = Name, time optional, minutes = pro Tag) ·
  habit.remove (title) · habit.time (title, time; "" = ohne Erinnerung) · task.rename (title = alt, step = neu) ·
  task.delete (title) · task.plan (title, day; -1 = irgendwann) · task.time (title, time, day) · shop.remove (title) ·
  timer.presets (items ["5","15","25"]) · snooze (minutes) · theme (step = Name einer freien Farbe) · dot.name (step) ·
  Löschen auf Wunsch: memo.delete (title = Text der Notiz aus „Letzte Notizen“) · chat.clear (unser Gespräch leeren) ·
  shop.clear (ganze Einkaufsliste leeren). Löschen nur, wenn die Person es ausdrücklich will.
  Bei title immer GENAU den Namen aus dem Kontext. Mehrere Änderungen = mehrere edit-Vorschläge (max. 4).
  Zum An-/Ausschalten und Pausieren weiter „setting“ nehmen.
- schedule = mehrere Termine auf einmal eintragen (z. B. Wochenplan vom Foto): title = kurzer Name ("Seminarwoche"),
  entries = je Termin {title, day, time "HH:MM", minutes Dauer}. day = Tage ab heute (siehe „Jetzt“ mit Wochentag) –
  „nächste Woche Montag“ also richtig ausrechnen, max. 13. Nur Termine mit Uhrzeit, nichts erfinden.
- Fotos: Liegt ein Bild bei, lies es genau. Wochen-/Stundenplan → EIN schedule mit allen Terminen.
  Packliste/Einkaufszettel → steps an die passende offene Aufgabe (z. B. „Koffer packen“) bzw. task mit items, oder shop.
  Ist etwas unleserlich, sag es kurz statt zu raten.
- day: 0 = heute, 1 = morgen usw. Nicht genutzte Felder: "" bzw. 0 bzw. [].
- Keine Aufgabe vorschlagen, die schon offen ist – dafür lieber focus oder steps.
- Die Person muss jeden Vorschlag selbst antippen. Schreib also NICHT "hab ich eingetragen", sondern z. B. "Tipp unten drauf".

Antworten zum Antippen ("suggestions", 0–3): kurze Sätze aus Sicht der Person (max. 40 Zeichen),
die sie als Nächstes sagen könnte, z. B. "Noch kleiner bitte", "Okay, ich fang an", "Was danach?".`,
    user: `${context ? `So sieht der Tag aus:\n${context}\n\n` : ''}${talk ? `Bisheriges Gespräch:\n${talk}\n\n` : ''}Neue Nachricht: ${message}`,
    schema: obj({
      answer: { type: 'string' },
      actions: {
        type: 'array', maxItems: 4,
        items: obj({
          kind: { type: 'string', enum: ['task', 'reminder', 'shop', 'memo', 'focus', 'done', 'tomorrow', 'steps', 'schedule', 'setting', 'edit'] },
          key: { type: 'string' },
          title: { type: 'string' },
          step: { type: 'string' },
          time: { type: 'string' },
          day: { type: 'integer' },
          minutes: { type: 'integer' },
          items: { type: 'array', maxItems: 12, items: { type: 'string' } },
          place: { type: 'string' },
          entries: {
            type: 'array', maxItems: 30,
            items: obj({ title: { type: 'string' }, day: { type: 'integer' }, time: { type: 'string' }, minutes: { type: 'integer' } })
          }
        })
      },
      suggestions: { type: 'array', maxItems: 3, items: { type: 'string' } }
    }),
    media,                                  // Foto (nur Gemini kann Bilder)
    maxTokens: media ? 2400 : 1000,         // ein Wochenplan braucht Platz
    big: !!media                            // Fotos lieber mit dem großen Modell lesen
  });
}

/* Einkauf: unbekannte Sachen dem richtigen Gang zuordnen. */
const AISLES = {
  produce: 'Obst & Gemüse', bakery: 'Brot & Backwaren', dairy: 'Kühlregal (Milch, Käse, Eier, Joghurt)',
  meat: 'Fleisch & Fisch', frozen: 'Tiefkühl', pantry: 'Vorrat (Nudeln, Konserven, Gewürze, Öl, Müsli)',
  snacks: 'Snacks & Süßes', drinks: 'Getränke', household: 'Drogerie & Haushalt', other: 'Sonstiges (kein Supermarkt-Gang)'
};

async function categorize({ items }) {
  return ask({
    system: `Ordne jeden Einkaufs-Eintrag dem Gang in einem deutschen Supermarkt zu.
Gänge: ${Object.entries(AISLES).map(([k, v]) => `${k} = ${v}`).join('; ')}.
Gib für jeden Eintrag genau einen Gang zurück, in derselben Reihenfolge.
"other" nur, wenn es wirklich in keinen Gang passt (z. B. Geschenkpapier, Batterien gehören zu household).`,
    user: items.map((n, i) => `${i + 1}. ${n}`).join('\n'),
    schema: obj({
      aisles: { type: 'array', items: { type: 'string', enum: Object.keys(AISLES) } }
    }),
    maxTokens: 400
  });
}

/* Tagesbegleiter: Dot schreibt einmal am Tag alle Sätze, die er heute sagt.
   Uhrzeiten setzt die App selbst dazu – das Modell soll keine erfinden. */
async function companionDay({ name, level, context }) {
  const line = { type: 'string' };
  return ask({
    system: `Du bist ${name || 'Dot'}, der kleine Begleiter in der App Dopa (Level ${level || 1}).
Du begleitest ${PERSON} durch den Tag.
Schreib die Sätze, die du heute zu bestimmten Zeiten sagst. Deutsch, du-Form.

Regeln:
- Jeder Satz höchstens 110 Zeichen. Kein Emoji, keine Ausrufezeichen-Kaskaden.
- Kein Anfeuern, keine Motivationssprüche, keine Schuld, kein "du solltest". Trocken, warm, manchmal ein bisschen frech.
- Konkret: Beziehe dich ab und zu auf echte Dinge aus dem Kontext (Termin, das Eine, eine Aufgabe) – aber nicht in jedem Satz.
- Nenne KEINE Uhrzeiten und keine Zahlen, die nicht im Kontext stehen. Die App ergänzt Zeiten selbst.
- Bei schlechter Stimmung: sanfter, kleinere Schritte.
- Steht eine „Apple Watch“-Zeile im Kontext: nach kurzer Nacht sanfter und mit Pausen; bei wenig Bewegung
  in nudges/afternoon ab und zu ein kurzer Gang nach draußen. Nie werten, keine Zahlen nennen.

Felder:
briefing = Morgen, beim Aufwachen. midday = Mittag. afternoon = Nachmittag. evening = Abend, beim Runterfahren.
night = spät, wenn es Zeit zum Schlafen wäre. nudges = 5 kurze Stupser für zwischendurch (Körper, Wasser, kurz hochschauen).
meals = 2 Essens-Erinnerungen.`,
    user: context,
    schema: obj({
      briefing: line, midday: line, afternoon: line, evening: line, night: line,
      nudges: { type: 'array', items: line },
      meals: { type: 'array', items: line }
    }),
    maxTokens: 700
  });
}

/* Einkauf: ungefährer Preis pro Eintrag (deutscher Discounter/Supermarkt), nur zur Orientierung. */
async function prices({ items, known }) {
  return ask({
    system: `Schätze für jeden Einkaufs-Eintrag den üblichen Preis in Euro in einem deutschen Supermarkt
(Discounter-Niveau wie Lidl/Aldi, Stand heute). Mengenangaben im Eintrag beachten ("2x Milch" = zwei Packungen).
Ohne Mengenangabe: eine übliche Packung. Nur eine Zahl pro Eintrag, in derselben Reihenfolge.
Wenn es kein Supermarkt-Artikel ist oder du es nicht weißt: 0.
Stehen unten Preise, die die Person selbst bezahlt hat: daran orientieren (ihr Laden, ihr Preisniveau) –
ähnliche Sachen ähnlich teuer schätzen.`,
    user: (known ? `Selbst bezahlt (pro Stück): ${known}\n\n` : '') + items.map((n, i) => `${i + 1}. ${n}`).join('\n'),
    schema: obj({
      prices: { type: 'array', items: { type: 'number' } }
    }),
    maxTokens: 300
  });
}

/* „Was jetzt?“ für Dopa: Auswahl nach Zustand, nicht nach Reihenfolge. Indizes statt IDs,
   damit das Modell nichts abtippen muss. */
async function dopaNext({ tasks, hour, energy, focusToday }) {
  const list = tasks.map((t, i) =>
    `${i + 1}. ${t.title}${t.step ? ` (erster Schritt: ${t.step})` : ''} – liegt seit ${t.age_days} Tag(en)`
  ).join('\n');
  const energyText = { low: 'wenig Energie', med: 'mittlere Energie', high: 'viel Energie' }[energy] || 'unbekannte Energie';
  return ask({
    system: `Wähle aus der Liste GENAU EINE Aufgabe, die jetzt dran ist.

Wonach du entscheidest:
- Zustand schlägt Wichtigkeit. Bei wenig Energie etwas Kleines, auch wenn Größeres drängt.
- Spät abends nichts Anstrengendes mehr. Früh am Tag darf es mehr sein.
- Was schon lange liegt, bekommt einen kleinen Bonus – aber nur, wenn es zur Energie passt.
- Wer heute noch keine Fokuszeit hatte, braucht einen leichten Einstieg.

- "index": die Nummer aus der Liste.
- "why": EIN kurzer Satz, warum gerade die. Direkt ansprechen, keine Floskeln.
- "first_move": die allererste körperliche Handlung, beginnt mit "Nur", max. 9 Wörter.
- "minutes": 5, 10, 15 oder 25.`,
    user: `Uhrzeit: ${hour} Uhr. Gerade ${energyText}. Heute schon ${focusToday} Minuten fokussiert.\n\nOffene Aufgaben:\n${list}`,
    schema: obj({
      index: { type: 'integer', minimum: 1, maximum: Math.max(1, tasks.length) },
      why: { type: 'string' },
      first_move: { type: 'string' },
      minutes: { type: 'integer', enum: [5, 10, 15, 25] }
    }),
    maxTokens: 300
  });
}

/* Feedback aus der App bündeln, bevor Claude es liest. */
async function summarizeFeedback({ items }) {
  return ask({
    system: `Du bekommst Feedback zu einer selbst gebauten iPhone-App (Dopa, ADHS-Helfer).
Fasse es für den Entwickler zusammen: gleiche Wünsche bündeln, Bugs von Wünschen trennen.
- "themes": je Thema ein kurzer Titel, Typ (bug, wunsch, design, frage), die Nummern der
  zugehörigen Einträge und ein konkreter nächster Schritt für den Entwickler.
- Sortiere nach Dringlichkeit: Bugs zuerst.
- Nichts dazuerfinden, was nicht im Feedback steht.`,
    user: items.map(i => `#${i.id} [${i.screen || '?'}] ${i.text}`).join('\n'),
    schema: obj({
      themes: {
        type: 'array',
        items: obj({
          title: { type: 'string' },
          kind: { type: 'string', enum: ['bug', 'wunsch', 'design', 'frage'] },
          ids: { type: 'array', items: { type: 'integer' } },
          next: { type: 'string' }
        })
      }
    }),
    maxTokens: 1500,
    big: true
  });
}

/* Prospekt (Foto/Screenshot, z. B. aus der kaufDA-App): Angebote mit Preis und Gültigkeit herauslesen. */
async function flyerScan({ image, mime, todayLabel }) {
  return ask({
    system: `Auf dem Bild ist ein Supermarkt- oder Drogerie-Prospekt (Papier, Foto oder Screenshot einer Prospekt-App).
Lies ALLE Angebote heraus:
- "store": Händler ("Lidl", "Rewe", "dm" …), "" wenn nicht erkennbar.
- "validFrom"/"validTo": Gültigkeit als YYYY-MM-DD („gültig ab Mo. 13.10.“, „bis Samstag“ – aus „heute“ ausrechnen,
  fehlt das Jahr: aktuelles bzw. nächstes passendes). Nicht erkennbar: "".
- "offers": je Angebot "name" (Produkt kurz und suchbar, z. B. "Milka Alpenmilch Schokolade"), "price" in Euro
  (Angebotspreis, 0 wenn keiner), "unit" (z. B. "100 g", "6 x 1,5 l", "" sonst), "note" (z. B. "-30 %", "nur mit App", "").
Nichts erfinden. Unleserliches weglassen.`,
    user: `Heute ist ${todayLabel}. Welche Angebote stehen im Prospekt?`,
    schema: obj({
      store: { type: 'string' },
      validFrom: { type: 'string' },
      validTo: { type: 'string' },
      offers: {
        type: 'array', maxItems: 80,
        items: obj({ name: { type: 'string' }, price: { type: 'number' }, unit: { type: 'string' }, note: { type: 'string' } })
      }
    }),
    media: [{ kind: 'image', mime, data: image }],
    maxTokens: 4000,
    big: true
  });
}

/* Barcode → Produktname aus Open Food Facts (frei, ohne Key). Kein KI-Aufruf, liegt hier, damit Tests es ersetzen können. */
async function productLookup(code) {
  const url = `https://world.openfoodfacts.org/api/v2/product/${code}.json?fields=product_name,product_name_de,brands,quantity`;
  const res = await fetch(url, {
    headers: { 'User-Agent': 'Dopa/1.0 (https://dopa.taubey.com)' },
    signal: AbortSignal.timeout(6000)
  });
  if (!res.ok) return null;
  const data = await res.json();
  const p = data?.product;
  if (data?.status !== 1 || !p) return null;
  const name = String(p.product_name_de || p.product_name || '').trim();
  if (!name) return null;
  const brand = String(p.brands || '').split(',')[0].trim();
  return { name, brand, quantity: String(p.quantity || '').trim() };
}

module.exports = {
  flyerScan, productLookup,
  enabled, describe, providers, ask, parseJSON, AISLES,
  breakdown, estimate, compile, rewrite, interpret, whatNow, reentry, firstStep, plan,
  categorize, prices, companionDay, photoDump, photoCaption, moneyScan, moneyTips, transcribe, dopaNext, summarizeFeedback, dump, dotAnswer, dotChat,
  MODES, RESOLUTION, MODEL: ANTHROPIC_MODEL
};
