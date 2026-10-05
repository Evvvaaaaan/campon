import { test } from 'node:test';
import assert from 'node:assert/strict';
import { callGemini, GEMINI_MODEL } from './_gemini.ts';

test('uses the supported Gemini model with low thinking', async () => {
  const originalFetch = globalThis.fetch;
  const originalKey = process.env.GEMINI_API_KEY;
  let requestedUrl = '';
  let requestedBody: any;

  process.env.GEMINI_API_KEY = 'test-key';
  globalThis.fetch = (async (input, init) => {
    requestedUrl = String(input);
    requestedBody = JSON.parse(String(init?.body));
    return new Response(JSON.stringify({
      candidates: [{ content: { parts: [{ text: '{"ok":true}' }] } }],
    }));
  }) as typeof fetch;

  try {
    assert.deepEqual(await callGemini('test prompt'), { ok: true });
    assert.equal(GEMINI_MODEL, 'gemini-3.6-flash');
    assert.ok(requestedUrl.includes(`/models/${GEMINI_MODEL}:generateContent`));
    assert.equal(requestedBody.generationConfig.responseMimeType, 'application/json');
    assert.equal(requestedBody.generationConfig.maxOutputTokens, 4096);
    assert.equal(requestedBody.generationConfig.thinkingConfig.thinkingLevel, 'low');
  } finally {
    globalThis.fetch = originalFetch;
    if (originalKey === undefined) delete process.env.GEMINI_API_KEY;
    else process.env.GEMINI_API_KEY = originalKey;
  }
});
