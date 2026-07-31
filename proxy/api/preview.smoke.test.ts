import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generatePreview } from './_handler.ts';
import type { PreviewRequest } from './_preview_core.ts';

const req: PreviewRequest = {
  place: '가리왕산 캠핑장',
  date: '2026-08-15',
  people: 2,
  experience: '초보',
  weather: { cloudPct: 4, precipPct: 0, windMs: 1.2, nightLowC: 14, myTempC: 30 },
  sky: { moonIlluminationPct: 4, moonInterferencePct: 3, score: 91, grade: 'milkyWay' },
};

test('generatePreview returns a full scene on the fallback path (no GEMINI key)', async () => {
  delete process.env.GEMINI_API_KEY;
  const out = await generatePreview(req);
  assert.equal(out.source, 'fallback');
  assert.equal(out.preview.lines.length, 5);
  assert.ok(out.preview.title.includes('가리왕산 캠핑장'));
  assert.ok(out.preview.closing.length > 0);
});
