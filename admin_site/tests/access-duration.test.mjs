import test from 'node:test';
import assert from 'node:assert/strict';
import { durationExpiry } from '../access-duration.mjs';

test('one day grants exactly 24 hours', () => {
  const now = new Date('2026-09-08T03:12:00Z');
  assert.equal(durationExpiry('days', 1, '', now), '2026-09-09T03:12:00.000Z');
});
test('calendar months clamp month-end instead of overflowing', () => {
  const now = new Date(2028, 0, 31, 10, 30);
  const end = new Date(durationExpiry('months', 1, '', now));
  assert.equal(end.getMonth(), 1);
  assert.equal(end.getDate(), 29);
  assert.equal(end.getHours(), 10);
});
test('specific date preserves the chosen instant', () => {
  assert.equal(durationExpiry('date', 1, '2027-02-03T09:00:00+09:00', new Date('2026-01-01Z')), '2027-02-03T00:00:00.000Z');
});
test('rejects zero, fractional, negative, invalid, or elapsed periods', () => {
  for (const count of [0, -1, 1.5, 'bad']) assert.throws(() => durationExpiry('days', count, ''), /positive whole number/);
  assert.throws(() => durationExpiry('date', 1, '2000-01-01T00:00:00Z'), /future/);
  assert.equal(durationExpiry('none', 0, ''), '');
});
