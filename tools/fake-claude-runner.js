// Test-Ersatz für tools/server/dopa-claude-run: schreibt sofort eine stream-json-Ausgabe wie `claude -p`.
// Enthält der Auftrag „langsam“, bleibt er „läuft“ (bis --stop).
const fs = require('fs');
const path = require('path');
const args = process.argv.slice(2);
if (args[0] === '--stop') { fs.writeFileSync(path.join(args[1], 'stopped'), ''); process.exit(0); }
const dir = args[0];
const prompt = fs.readFileSync(path.join(dir, 'prompt.txt'), 'utf8');
const sid = '11111111-2222-3333-4444-555555555555';
const lines = [{ type: 'system', subtype: 'init', session_id: sid, model: 'claude-sonnet' }];
if (!prompt.includes('langsam')) {
  lines.push({ type: 'assistant', session_id: sid, message: { content: [
    { type: 'text', text: 'Schau ins Feedback.' },
    { type: 'tool_use', name: 'Bash', input: { command: 'sudo dopa-feedback', description: 'Feedback lesen' } },
    { type: 'tool_use', name: 'Edit', input: { file_path: '/home/claude/momentum/server.js' } }] } });
  lines.push({ type: 'result', subtype: 'success', is_error: false, session_id: sid, result: 'Fertig.', duration_ms: 120000 });
  fs.writeFileSync(path.join(dir, 'exit'), '0');
}
fs.writeFileSync(path.join(dir, 'out.jsonl'), lines.map(l => JSON.stringify(l)).join('\n') + '\n');
