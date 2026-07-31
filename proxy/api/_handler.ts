import { callGemini } from './_gemini.ts';
import { fetchWeather } from './_weather.ts';
import {
  buildFallbackPlan,
  buildPrompt,
  coercePlan,
  type Plan,
  type PlanRequest,
} from './_plan_core.ts';
import {
  buildFallbackPreview,
  buildPreviewPrompt,
  coercePreview,
  type Preview,
  type PreviewRequest,
} from './_preview_core.ts';

export async function generatePlan(
  body: PlanRequest,
): Promise<{ plan: Plan; source: 'llm' | 'fallback' }> {
  const weather = await fetchWeather(body.coords.lat, body.coords.lon, body.context.date);
  const raw = await callGemini(buildPrompt(body, weather));
  const plan = raw ? coercePlan(raw, body, weather) : buildFallbackPlan(body, weather);
  return { plan, source: raw ? 'llm' : 'fallback' };
}

export async function generatePreview(
  body: PreviewRequest,
): Promise<{ preview: Preview; source: 'llm' | 'fallback' }> {
  // 날씨는 앱이 이미 계산해서 보내온다. 여기서 다시 조회하지 않는다.
  const raw = await callGemini(buildPreviewPrompt(body), 0.95);
  const preview = raw ? coercePreview(raw, body) : buildFallbackPreview(body);
  return { preview, source: raw ? 'llm' : 'fallback' };
}
