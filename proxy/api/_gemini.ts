const MODEL = 'gemini-2.0-flash';

/// 키가 없거나 모델이 실패하면 null. 호출하는 쪽이 폴백을 쓴다.
export async function callGemini(
  prompt: string,
  temperature = 0.7,
): Promise<unknown> {
  const key = process.env.GEMINI_API_KEY;
  if (!key) return null;
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${key}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    signal: AbortSignal.timeout(25000),
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { temperature, responseMimeType: 'application/json' },
    }),
  });
  if (!res.ok) return null;
  const j: any = await res.json();
  const text = j?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof text !== 'string') return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}
