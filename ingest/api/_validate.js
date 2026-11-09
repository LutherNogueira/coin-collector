// Validation for the batches the game sends. It is the only gate between the open internet and the storage,
// so it is strict about shape and size and says nothing about game rules: those are the silver layer's job
// (a well-formed but nonsensical event is stored raw and quarantined later, like any other).

export const MAX_BODY_BYTES = 64 * 1024;
export const MAX_EVENTS = 100;
export const MAX_EVENT_BYTES = 2048;
export const SCHEMA_VERSIONS = [4];

export const EVENT_NAMES = new Set([
  'session_start', 'session_end', 'round_start', 'round_end', 'coin_spawn', 'coin_collect',
  'player_jump', 'player_land', 'player_death', 'player_respawn', 'player_position',
]);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;

const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

/**
 * Checks a raw request body. Returns {ok: true, lines: [...]} with the events re-serialised as JSON Lines
 * (only the six known fields are kept), or {ok: false, error}.
 */
export function validateBatch(rawBody) {
  if (typeof rawBody !== 'string' || rawBody.length === 0) return fail('empty body');
  if (Buffer.byteLength(rawBody, 'utf8') > MAX_BODY_BYTES) return fail('body too large');

  let parsed;
  try {
    parsed = JSON.parse(rawBody);
  } catch {
    return fail('body is not valid JSON');
  }
  if (!isObject(parsed) || !Array.isArray(parsed.events)) return fail('expected {"events": [...]}');
  const events = parsed.events;
  if (events.length === 0) return fail('no events');
  if (events.length > MAX_EVENTS) return fail('too many events');

  const lines = [];
  let session = null;
  for (const [i, e] of events.entries()) {
    const problem = checkEvent(e);
    if (problem) return fail(`event ${i}: ${problem}`);
    session ??= e.session_id;
    if (e.session_id !== session) return fail(`event ${i}: a batch holds one session only`);
    const line = JSON.stringify({
      timestamp: e.timestamp,
      evento: e.evento,
      valor: e.valor,
      session_id: e.session_id,
      round_id: e.round_id,
      schema_version: e.schema_version,
    });
    if (Buffer.byteLength(line, 'utf8') > MAX_EVENT_BYTES) return fail(`event ${i}: too large`);
    lines.push(line);
  }
  return { ok: true, lines, session };
}

function checkEvent(e) {
  if (!isObject(e)) return 'not an object';
  if (typeof e.timestamp !== 'string' || !TIMESTAMP.test(e.timestamp)) return 'bad timestamp';
  if (typeof e.evento !== 'string' || !EVENT_NAMES.has(e.evento)) return 'unknown event';
  if (!isObject(e.valor)) return 'valor must be an object';
  if (typeof e.session_id !== 'string' || !UUID.test(e.session_id)) return 'bad session_id';
  if (e.round_id !== null && (typeof e.round_id !== 'string' || !UUID.test(e.round_id))) return 'bad round_id';
  if (!SCHEMA_VERSIONS.includes(e.schema_version)) return 'unsupported schema_version';
  return null;
}

function fail(error) {
  return { ok: false, error };
}
