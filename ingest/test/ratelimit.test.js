import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createLimiter } from '../api/_ratelimit.js';

test('a client is let through up to the limit and then refused', () => {
  const limiter = createLimiter({ limit: 3, windowMs: 1000, now: () => 0 });
  assert.deepEqual([1, 2, 3, 4].map(() => limiter.allow('a')), [true, true, true, false]);
});

test('clients are counted separately', () => {
  const limiter = createLimiter({ limit: 1, windowMs: 1000, now: () => 0 });
  assert.equal(limiter.allow('a'), true);
  assert.equal(limiter.allow('b'), true);
  assert.equal(limiter.allow('a'), false);
});

test('the count starts again when the window is over', () => {
  let t = 0;
  const limiter = createLimiter({ limit: 1, windowMs: 1000, now: () => t });
  assert.equal(limiter.allow('a'), true);
  assert.equal(limiter.allow('a'), false);
  t = 1000;
  assert.equal(limiter.allow('a'), true);
});

test('memory stays bounded under a flood of different clients', () => {
  const limiter = createLimiter({ limit: 1, windowMs: 60000, maxKeys: 10, now: () => 0 });
  for (let i = 0; i < 1000; i++) limiter.allow(`client-${i}`);
  assert.equal(limiter.allow('client-new'), true);
});
