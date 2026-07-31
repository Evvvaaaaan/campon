import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildFallbackPreview,
  buildPreviewPrompt,
  coercePreview,
  type PreviewRequest,
} from './_preview_core.ts';

const req = (over: Partial<PreviewRequest['weather']> = {}, moonInterferencePct = 3): PreviewRequest => ({
  place: '홍천 별빛캠핑장',
  date: '2026-08-15',
  people: 2,
  experience: '초보',
  weather: {
    cloudPct: 4, precipPct: 0, windMs: 1.2, nightLowC: 14, myTempC: 30, ...over,
  },
  sky: { moonIlluminationPct: 4, moonInterferencePct, score: 91, grade: 'milkyWay' },
});

test('프롬프트에 실제 수치와 제약이 들어간다', () => {
  const prompt = buildPreviewPrompt(req());
  assert.match(prompt, /홍천 별빛캠핑장/);
  assert.match(prompt, /구름 4%/);
  assert.match(prompt, /바람 1.2m\/s/);
  assert.match(prompt, /사실상 달이 없는 밤/);
  assert.match(prompt, /lines는 정확히 5줄/);
});

test('모르는 수치는 "모름"으로 넘겨 지어내지 않게 한다', () => {
  const prompt = buildPreviewPrompt(req({ cloudPct: null, windMs: null, nightLowC: null }));
  assert.match(prompt, /구름 모름/);
  assert.match(prompt, /바람 모름/);
  assert.match(prompt, /밤 최저기온 모름/);
});

test('달빛이 밝으면 "달이 없는 밤"이라고 알려주지 않는다', () => {
  const prompt = buildPreviewPrompt(req({}, 70));
  assert.doesNotMatch(prompt, /사실상 달이 없는 밤/);
});

test('폴백 장면은 5줄이고 제목에 날짜와 장소가 들어간다', () => {
  const preview = buildFallbackPreview(req());
  assert.equal(preview.lines.length, 5);
  assert.equal(preview.title, '8월 15일 밤, 홍천 별빛캠핑장');
  assert.ok(preview.closing.length > 0);
});

test('폴백 장면은 수치에 따라 달라진다', () => {
  const cold = buildFallbackPreview(req({ nightLowC: 2 }));
  const warm = buildFallbackPreview(req({ nightLowC: 24 }));
  assert.notEqual(cold.lines[0], warm.lines[0]);

  const cloudy = buildFallbackPreview(req({ cloudPct: 90 }));
  assert.match(cloudy.lines[2], /불빛/);

  const moonlit = buildFallbackPreview(req({}, 70));
  assert.match(moonlit.lines[2], /4%/);
});

test('모델 응답이 정상이면 그대로 쓴다', () => {
  const preview = coercePreview(
    { title: 'AI 제목', lines: ['한 줄', '두 줄', '세 줄', '네 줄', '다섯 줄'], closing: 'AI 마무리' },
    req(),
  );
  assert.equal(preview.title, 'AI 제목');
  assert.equal(preview.lines.length, 5);
  assert.equal(preview.closing, 'AI 마무리');
});

test('줄이 모자란 응답은 통째로 폴백한다', () => {
  const preview = coercePreview({ title: '제목', lines: ['한 줄'] }, req());
  assert.equal(preview.lines.length, 5);
  assert.equal(preview.title, '8월 15일 밤, 홍천 별빛캠핑장');
});

test('응답이 아예 없거나 깨져도 장면이 나온다', () => {
  for (const raw of [null, undefined, 'not json', { lines: 'x' }]) {
    const preview = coercePreview(raw, req());
    assert.equal(preview.lines.length, 5);
  }
});

test('제목만 빠지면 폴백 제목으로 채운다', () => {
  const preview = coercePreview({ lines: ['a', 'b', 'c'] }, req());
  assert.equal(preview.title, '8월 15일 밤, 홍천 별빛캠핑장');
  assert.equal(preview.lines.length, 3);
});
