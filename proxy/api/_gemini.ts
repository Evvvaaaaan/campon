export const GEMINI_MODEL = 'gemini-3.6-flash';

/// 키가 없거나 모델이 실패하면 null. 호출하는 쪽이 폴백을 쓴다.
export async function callGemini(
  prompt: string,
  temperature = 0.7,
): Promise<unknown> {
  const key = process.env.GEMINI_API_KEY;
  if (!key) return null;
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${key}`;
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      signal: AbortSignal.timeout(60000),
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          temperature,
          responseMimeType: 'application/json',
          maxOutputTokens: 4096,
          thinkingConfig: { thinkingLevel: 'low' },
        },
      }),
    });
    if (!res.ok) {
      console.error(`[callGemini] Gemini API ${res.status}: ${(await res.text()).slice(0, 500)}`);
      return null;
    }
    const j: any = await res.json();
    const usage = j?.usageMetadata;
    if (usage) {
      console.info(
        `[callGemini] model=${GEMINI_MODEL} promptTokens=${usage.promptTokenCount ?? 0} ` +
        `outputTokens=${usage.candidatesTokenCount ?? 0} thoughtsTokens=${usage.thoughtsTokenCount ?? 0} ` +
        `totalTokens=${usage.totalTokenCount ?? 0}`,
      );
    }
    const text = j?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (typeof text !== 'string') {
      console.error(`[callGemini] unexpected response shape: ${JSON.stringify(j).slice(0, 500)}`);
      return null;
    }
    try {
      return JSON.parse(text);
    } catch (e) {
      console.error(`[callGemini] JSON.parse failed on model text: ${String(e)}; text=${text.slice(0, 500)}`);
      return null;
    }
  } catch (e) {
    console.error(`[callGemini] request failed: ${String(e)}`);
    return null;
  }
}
