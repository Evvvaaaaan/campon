import { test } from 'node:test';
import assert from 'node:assert/strict';
import { gradeWeather } from './_weather.ts';

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
