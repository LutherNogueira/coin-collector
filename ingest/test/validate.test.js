import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MAX_EVENTS, validateBatch } from '../api/_validate.js';

const SESSION = '2603a440-1727-4d12-af64-1bf5a603eef5';
const ROUND = 'b59f7bc6-b304-4fc5-9c41-3178ab504bfe';

const event = (over = {}) => ({
  timestamp: '2026-11-09T18:27:10.539Z',
  evento: 'coin_collect',
  valor: { x: 10, y: 20 },
  session_id: SESSION,
  round_id: ROUND,
  schema_version: 4,
  ...over,
});
const batch = (events) => JSON.stringify({ events });

test('a well-formed batch becomes one JSON line per event', () => {
  const r = validateBatch(batch([event(), event({ evento: 'player_jump', round_id: null })]));
  assert.equal(r.ok, true);
  assert.equal(r.lines.length, 2);
  assert.equal(r.session, SESSION);
  assert.deepEqual(JSON.parse(r.lines[1]).round_id, null);
});

test('unknown top-level fields are dropped, valor is kept as sent', () => {
  const r = validateBatch(batch([event({ extra: 'x', valor: { a: 1 } })]));
  assert.equal(r.ok, true);
  const stored = JSON.parse(r.lines[0]);
  assert.equal('extra' in stored, false);
  assert.deepEqual(stored.valor, { a: 1 });
});

for (const [name, body] of [
  ['an empty body', ''],
  ['text that is not JSON', 'not json'],
  ['JSON that is not an object', '[1,2]'],
  ['a batch without events', '{"events": []}'],
  ['events that are not an array', '{"events": {}}'],
  ['an event that is not an object', batch([5])],
  ['an unknown event name', batch([event({ evento: 'drop_table' })])],
  ['a malformed timestamp', batch([event({ timestamp: 'yesterday' })])],
  ['a valor that is not an object', batch([event({ valor: 'x' })])],
  ['a bad session id', batch([event({ session_id: 'abc' })])],
  ['a bad round id', batch([event({ round_id: 'abc' })])],
  ['a schema version the endpoint does not take', batch([event({ schema_version: 3 })])],
  ['two sessions in one batch', batch([event(), event({ session_id: ROUND })])],
]) {
  test(`rejects ${name}`, () => {
    assert.equal(validateBatch(body).ok, false);
  });
}

test('rejects too many events', () => {
  assert.equal(validateBatch(batch(Array.from({ length: MAX_EVENTS + 1 }, () => event()))).ok, false);
});

test('rejects an oversized event and an oversized body', () => {
  assert.equal(validateBatch(batch([event({ valor: { blob: 'x'.repeat(3000) } })])).ok, false);
  assert.equal(validateBatch('x'.repeat(70 * 1024)).ok, false);
});
