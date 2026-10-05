import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fetchWeather, gradeWeather } from './_weather.ts';

test('rain over 60% is risk', () => {
  const r = gradeWeather({ nightLowC: 12, precipPct: 70, windMs: 3, diurnalRangeC: 8 });
  assert.equal(r.grade, 'risk');
});
test('cold night at or below 5 is caution', () => {
  const r = gradeWeather({ nightLowC: 4, precipPct: 10, windMs: 3, diurnalRangeC: 8 });
  assert.equal(r.grade, 'caution');
});
test('mild dry calm is good', () => {
  const r = gradeWeather({ nightLowC: 15, precipPct: 5, windMs: 2, diurnalRangeC: 7 });
  assert.equal(r.grade, 'good');
});
test('freezing night is risk', () => {
  const r = gradeWeather({ nightLowC: -1, precipPct: 0, windMs: 2, diurnalRangeC: 6 });
  assert.equal(r.grade, 'risk');
});

test('forecast outside the 16-day range is unavailable without requesting it', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => { throw new Error('must not fetch'); };
  try {
    const r = await fetchWeather(37.8, 128.9, '2099-12-31');
    assert.equal(r.grade, 'unavailable');
    assert.equal(r.nightLowC, null);
    assert.match(r.advice, /예보 범위 밖/);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('network failure is unavailable instead of returning invented metrics', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => { throw new Error('offline'); };
  try {
    const todayKst = new Date(Date.now() + 9 * 60 * 60 * 1000);
    const date = [
      todayKst.getUTCFullYear(),
      String(todayKst.getUTCMonth() + 1).padStart(2, '0'),
      String(todayKst.getUTCDate()).padStart(2, '0'),
    ].join('-');
    const r = await fetchWeather(37.8, 128.9, date);
    assert.equal(r.grade, 'unavailable');
    assert.equal(r.nightLowC, null);
    assert.equal(r.precipPct, null);
    assert.match(r.advice, /불러오지 못했어요/);
    assert.doesNotMatch(r.advice, /안정적/);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
