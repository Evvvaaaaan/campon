import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildFallbackPlan, coercePlan, type PlanRequest } from './_plan_core.ts';
import type { WeatherSummary } from './_weather.ts';

const req: PlanRequest = {
  query: '이번 주말 2명 강원도 초보 오토캠핑',
  context: { date: '2026-08-01', people: 2, hasCar: true, experience: '초보',
             region: '강원', preferences: [], equipment: [] },
  coords: { lat: 37.8, lon: 128.9 },
  candidates: [{ name: '가리왕산 캠핑장', facility: ['전기'], equipmentRental: [] }],
};
const weather: WeatherSummary = { grade: 'caution', nightLowC: 6, precipPct: 40,
  windMs: 4, diurnalRangeC: 12, advice: '대비하세요.' };

test('fallback plan is fully shaped', () => {
  const p = buildFallbackPlan(req, weather);
  assert.ok(p.summary.oneLiner.length > 0);
  assert.equal(p.weather.grade, 'caution');
  assert.ok(p.campsites.length >= 1);
  assert.ok(p.checklist.length >= 1);
  assert.ok(p.timeline.length >= 3);
});

test('coercePlan repairs missing fields from LLM output', () => {
  const raw = { summary: { title: '강원 오토캠핑', oneLiner: '좋아요' } };
  const p = coercePlan(raw, req, weather);
  assert.equal(p.summary.title, '강원 오토캠핑');
  assert.ok(typeof p.summary.mood === 'string');
  assert.ok(p.campsites.length >= 1);
  assert.ok(p.timeline.length >= 3);
  assert.equal(p.weather.grade, 'caution');
});
