import { fetchWeather } from './_weather.ts';
import { buildPrompt, coercePlan, buildFallbackPlan, type PlanRequest } from './_plan_core.ts';

const MODEL = 'gemini-2.0-flash';

async function callGemini(prompt: string): Promise<unknown> {
  const key = process.env.GEMINI_API_KEY;
  if (!key) return null;
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${key}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    signal: AbortSignal.timeout(25000),
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { temperature: 0.7, responseMimeType: 'application/json' },
    }),
  });
  if (!res.ok) return null;
  const j: any = await res.json();
  const text = j?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof text !== 'string') return null;
  try { return JSON.parse(text); } catch { return null; }
}

export default async function handler(req: any, res: any) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'content-type');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method' });
  try {
    const body: PlanRequest = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
    const weather = await fetchWeather(body.coords.lat, body.coords.lon, body.context.date);
    const raw = await callGemini(buildPrompt(body, weather));
    const plan = raw ? coercePlan(raw, body, weather) : buildFallbackPlan(body, weather);
    return res.status(200).json({ plan, source: raw ? 'llm' : 'fallback' });
  } catch (e) {
    return res.status(200).json({ plan: null, error: String(e) });
  }
}
