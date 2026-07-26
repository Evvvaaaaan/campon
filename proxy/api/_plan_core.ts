import type { WeatherSummary } from './_weather.ts';

export type PlanContext = {
  date: string; people: number; hasCar: boolean; experience: string;
  region: string; preferences: string[]; equipment: string[];
};
export type Candidate = { name: string; facility: string[]; equipmentRental: string[] };
export type PlanRequest = {
  query: string; context: PlanContext; coords: { lat: number; lon: number }; candidates: Candidate[];
};
export type Plan = {
  summary: { title: string; mood: string; oneLiner: string };
  weather: WeatherSummary;
  campsites: { name: string; reason: string }[];
  checklist: { category: string; items: string[] }[];
  timeline: { time: string; title: string; detail: string }[];
};

const str = (v: unknown, d = ''): string => (typeof v === 'string' && v.trim() ? v : d);
const arr = <T,>(v: unknown): T[] => (Array.isArray(v) ? (v as T[]) : []);

export function buildFallbackPlan(req: PlanRequest, weather: WeatherSummary): Plan {
  const c = req.context;
  const names = req.candidates.slice(0, 3);
  return {
    summary: {
      title: `${c.region} ${c.hasCar ? '오토' : ''}캠핑`.trim(),
      mood: c.experience.includes('초보') ? '편안하고 안전하게' : '자유롭게',
      oneLiner: `${c.date} ${c.people}명, ${c.region} 캠핑 플랜입니다.`,
    },
    weather,
    campsites: names.length
      ? names.map((s) => ({ name: s.name, reason: `${c.region} 지역, 접근성과 시설이 무난해요.` }))
      : [{ name: `${c.region} 인근 캠핑장`, reason: '지역 조건에 맞춘 추천입니다.' }],
    checklist: [
      { category: '텐트·취침', items: ['텐트', '그라운드시트', weather.nightLowC <= 5 ? '동계 침낭' : '침낭', '매트'] },
      { category: '취사', items: ['버너', '코펠', '식수', '아이스박스'] },
      { category: '의류', items: [weather.diurnalRangeC >= 12 ? '보온 겉옷' : '여벌옷', '양말', '모자'] },
      { category: '안전', items: ['구급킷', '헤드랜턴', '보조배터리', weather.precipPct >= 30 ? '우비·타프' : '비상 우비'] },
    ],
    timeline: [
      { time: '14:00', title: '도착·설치', detail: '입실 후 텐트와 타프를 설치해요.' },
      { time: '17:00', title: '저녁 준비', detail: '해지기 전 취사와 식사를 마쳐요.' },
      { time: '19:30', title: '캠프파이어', detail: '불멍과 휴식 시간.' },
      { time: '22:00', title: '취침', detail: `야간 최저 ${weather.nightLowC}도, 보온에 유의해요.` },
      { time: '10:00', title: '철수', detail: '장비를 말리고 정리 후 퇴실해요.' },
    ],
  };
}

export function coercePlan(raw: unknown, req: PlanRequest, weather: WeatherSummary): Plan {
  const fb = buildFallbackPlan(req, weather);
  const r = (raw ?? {}) as any;
  const summary = r.summary ?? {};
  const campsites = arr<any>(r.campsites)
    .map((x) => ({ name: str(x?.name), reason: str(x?.reason) }))
    .filter((x) => x.name);
  const checklist = arr<any>(r.checklist)
    .map((x) => ({ category: str(x?.category), items: arr<string>(x?.items).map((i) => str(i)).filter(Boolean) }))
    .filter((x) => x.category && x.items.length);
  const timeline = arr<any>(r.timeline)
    .map((x) => ({ time: str(x?.time), title: str(x?.title), detail: str(x?.detail) }))
    .filter((x) => x.time && x.title);
  return {
    summary: {
      title: str(summary.title, fb.summary.title),
      mood: str(summary.mood, fb.summary.mood),
      oneLiner: str(summary.oneLiner, fb.summary.oneLiner),
    },
    weather,
    campsites: campsites.length ? campsites.slice(0, 3) : fb.campsites,
    checklist: checklist.length ? checklist : fb.checklist,
    timeline: timeline.length >= 3 ? timeline : fb.timeline,
  };
}

export function buildPrompt(req: PlanRequest, weather: WeatherSummary): string {
  const c = req.context;
  const cand = req.candidates.slice(0, 5).map((s) =>
    `- ${s.name} (시설: ${s.facility.join(', ') || '정보없음'}; 대여: ${s.equipmentRental.join(', ') || '없음'})`).join('\n');
  return [
    '너는 한국 캠핑 플래너다. 아래 정보로 캠핑 플랜을 JSON으로만 작성한다.',
    `요청: ${req.query}`,
    `날짜:${c.date} 인원:${c.people} 차량:${c.hasCar ? '있음' : '없음'} 숙련도:${c.experience} 지역:${c.region}`,
    `선호:${c.preferences.join(',') || '없음'} 보유장비:${c.equipment.join(',') || '없음'}`,
    `날씨: 등급=${weather.grade} 야간최저=${weather.nightLowC}도 강수확률=${weather.precipPct}% 풍속=${weather.windMs}m/s 일교차=${weather.diurnalRangeC}도`,
    '후보 캠핑장(이 목록에서만 골라 이름을 그대로 쓸 것):',
    cand || '- (후보 없음: 지역 기반 일반 추천)',
    '규칙: campsites는 후보 중 최대 3곳, 각 reason은 요청/날씨/숙련도에 맞춰 1문장.',
    'checklist는 날씨와 숙련도를 반영. timeline은 도착~철수 최소 5단계.',
    'JSON 스키마: {"summary":{"title","mood","oneLiner"},"campsites":[{"name","reason"}],',
    '"checklist":[{"category","items":[]}],"timeline":[{"time","title","detail"}]}',
    '모든 문장은 한국어.',
  ].join('\n');
}
