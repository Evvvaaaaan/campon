/**
 * "그날 밤 미리보기" — 앱이 계산한 실제 수치로 그 밤의 장면을 쓴다.
 * 정보를 요약하는 글이 아니라, 거기 있는 자신을 상상하게 만드는 글이다.
 */

export type PreviewWeather = {
  cloudPct: number | null;
  precipPct: number | null;
  windMs: number | null;
  nightLowC: number | null;
  myTempC: number | null;
};

export type PreviewSky = {
  moonIlluminationPct: number;
  moonInterferencePct: number;
  score: number;
  grade: string;
};

export type PreviewRequest = {
  place: string;
  date: string;
  people: number;
  experience: string;
  weather: PreviewWeather;
  sky: PreviewSky;
};

export type Preview = { title: string; lines: string[]; closing: string };

const str = (v: unknown, d = ''): string =>
  typeof v === 'string' && v.trim() ? v.trim() : d;

const known = (v: number | null | undefined, unit: string): string =>
  typeof v === 'number' ? `${v}${unit}` : '모름';

function monthDay(date: string): string {
  const [, month, day] = date.split('-');
  if (!month || !day) return date;
  return `${Number(month)}월 ${Number(day)}일`;
}

export function buildPreviewPrompt(req: PreviewRequest): string {
  const w = req.weather;
  const s = req.sky;
  const moonless = s.moonInterferencePct <= 15;
  return [
    '너는 캠핑 장면을 쓰는 한국어 작가다. 아래 실제 관측/예보 수치만으로',
    '그날 밤 그 캠핑장에 있는 사람의 시점에서 짧은 장면을 JSON으로만 쓴다.',
    `장소: ${req.place}`,
    `날짜: ${req.date} (밤 9시부터 새벽까지)`,
    `동행: ${req.people}명, 캠핑 숙련도 ${req.experience}`,
    `구름 ${known(w.cloudPct, '%')}, 강수확률 ${known(w.precipPct, '%')}, ` +
      `바람 ${known(w.windMs, 'm/s')}, 밤 최저기온 ${known(w.nightLowC, '도')}`,
    `달 조도 ${s.moonIlluminationPct}%, 달빛 방해 ${s.moonInterferencePct}%` +
      `${moonless ? ' (사실상 달이 없는 밤)' : ''}`,
    `밤하늘 점수 ${s.score}/100`,
    '',
    '규칙:',
    '- lines는 정확히 5줄. 각 줄은 한 문장 또는 두 문장, 40자 이내를 지향한다.',
    '- 시간 순서로 쓴다: 도착한 저녁 → 불 → 하늘 → 정적 → 잠들기 직전.',
    '- 위 수치와 어긋나는 묘사를 하지 않는다. 비 예보가 없으면 비를 쓰지 않고,',
    '  달빛 방해가 높으면 "달이 없다"고 쓰지 않는다.',
    '- 광고 문구, 권유, 느낌표, 이모지를 쓰지 않는다. 담담한 현재형으로 쓴다.',
    '- closing은 한 줄. 가고 싶게 만드는 조용한 마무리.',
    `- title은 "${monthDay(req.date)} 밤, ${req.place}" 형태로 쓴다.`,
    '',
    'JSON 스키마: {"title":"", "lines":["","","","",""], "closing":""}',
  ].join('\n');
}

export function buildFallbackPreview(req: PreviewRequest): Preview {
  const w = req.weather;
  const s = req.sky;
  const lines = [
    openingLine(w.nightLowC),
    windLine(w.windMs),
    skyLine(w.cloudPct, s),
    '장작이 한 번 크게 튀고 다시 조용해진다. 아무도 말하지 않아도 어색하지 않은 시간이다.',
    sleepLine(w.nightLowC),
  ];
  return {
    title: `${monthDay(req.date)} 밤, ${req.place}`,
    lines,
    closing: '이 밤은 아직 아무도 예약하지 않았다.',
  };
}

function openingLine(nightLowC: number | null): string {
  if (nightLowC === null) {
    return '밤 9시. 도시에서는 들어본 적 없는 조용함이 먼저 도착한다.';
  }
  if (nightLowC >= 20) {
    return '밤 9시. 낮의 열기가 아직 땅에 남아 있다. 반팔 위에 얇은 셔츠 하나면 딱 좋은 온도다.';
  }
  if (nightLowC >= 12) {
    return '밤 9시. 공기가 한 겹 서늘해졌다. 낮에 벗어둔 겉옷을 다시 걸친다.';
  }
  return '밤 9시. 입김이 옅게 보인다. 침낭 속이 벌써 그리워지는 온도다.';
}

function windLine(windMs: number | null): string {
  if (windMs === null) return '불을 붙이자 주변이 한 뼘씩 밝아진다.';
  if (windMs <= 2) return '바람이 거의 없다. 불꽃이 흔들리지 않고 똑바로 올라간다.';
  if (windMs <= 5) return '이따금 바람이 지나간다. 타프 자락이 한 번씩 살짝 부푼다.';
  return '바람이 제법 분다. 팩을 한 번 더 확인하고 자리에 앉는다.';
}

function skyLine(cloudPct: number | null, sky: PreviewSky): string {
  if (cloudPct !== null && cloudPct > 60) {
    return '하늘은 두껍다. 오늘은 별 대신 불빛만 보기로 한다.';
  }
  if (cloudPct !== null && cloudPct > 20) {
    return '구름이 천천히 지나간다. 사이가 벌어질 때마다 별이 몇 개씩 나타났다 사라진다.';
  }
  if (sky.moonInterferencePct <= 15) {
    return '고개를 들면 달이 없어서 별이 평소의 두 배쯤 많다. 눈이 어둠에 익을수록 없던 별이 계속 생긴다.';
  }
  return `달이 ${sky.moonIlluminationPct}% 차 있다. 밝은 별부터 차례로 눈에 들어온다.`;
}

function sleepLine(nightLowC: number | null): string {
  if (nightLowC !== null && nightLowC <= 8) {
    return '텐트에 들어가면 바닥부터 차다. 매트 한 장이 오늘의 승부다.';
  }
  return '텐트 지퍼를 반쯤 열어두고 눕는다. 풀벌레 소리가 천천히 볼륨을 낮춘다.';
}

export function coercePreview(raw: unknown, req: PreviewRequest): Preview {
  const fb = buildFallbackPreview(req);
  const r = (raw ?? {}) as any;
  const lines = Array.isArray(r.lines)
    ? r.lines.map((l: unknown) => str(l)).filter(Boolean)
    : [];
  // 줄이 모자라면 모델이 형식을 지키지 못한 것으로 보고 통째로 폴백한다.
  if (lines.length < 3) return fb;
  return {
    title: str(r.title, fb.title),
    lines: lines.slice(0, 6),
    closing: str(r.closing, fb.closing),
  };
}
