import { test } from 'node:test';
import assert from 'node:assert/strict';
import handler from './plan.ts';

function mockRes() {
  const res: any = {
    statusCode: 0,
    headers: {} as Record<string, string>,
    body: null as unknown,
    setHeader(k: string, v: string) { this.headers[k] = v; },
    status(code: number) { this.statusCode = code; return this; },
    json(payload: unknown) { this.body = payload; return this; },
    end() { return this; },
  };
  return res;
}

test('handler returns a fully shaped plan (fallback path, no GEMINI key)', async () => {
  delete process.env.GEMINI_API_KEY;
  const req: any = {
    method: 'POST',
    body: {
      query: '주말 2명 강원 초보 오토캠핑',
      context: { date: '2026-08-01', people: 2, hasCar: true, experience: '초보',
                 region: '강원', preferences: [], equipment: [] },
      coords: { lat: 37.8, lon: 128.9 },
      candidates: [{ name: '가리왕산 캠핑장', facility: ['전기'], equipmentRental: [] }],
    },
  };
  const res = mockRes();
  await handler(req, res);
  assert.equal(res.statusCode, 200);
  const out: any = res.body;
  assert.equal(out.source, 'fallback');
  assert.ok(out.plan.summary.oneLiner.length > 0);
  assert.ok(['good', 'caution', 'risk'].includes(out.plan.weather.grade));
  assert.ok(out.plan.campsites.length >= 1);
  assert.ok(out.plan.checklist.length >= 1);
  assert.ok(out.plan.timeline.length >= 3);
});
