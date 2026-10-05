export type Grade = 'good' | 'caution' | 'risk' | 'unavailable';
export type WeatherSummary = {
  grade: Grade; nightLowC: number | null; precipPct: number | null;
  windMs: number | null; diurnalRangeC: number | null; advice: string;
};

type Metrics = { nightLowC: number; precipPct: number; windMs: number; diurnalRangeC: number };

export function gradeWeather(m: Metrics): { grade: Grade; advice: string } {
  const risk = m.precipPct >= 60 || m.windMs >= 9 || m.nightLowC <= 0;
  const caution = m.precipPct >= 30 || m.windMs >= 6 || m.nightLowC <= 5 || m.diurnalRangeC >= 15;
  const tips: string[] = [];
  if (m.precipPct >= 30) tips.push('비 예보가 있어 타프와 방수 대비가 필요해요');
  if (m.windMs >= 6) tips.push('바람이 강해 팩을 단단히 고정하세요');
  if (m.nightLowC <= 5) tips.push('야간 기온이 낮아 동계 침낭과 매트가 필요해요');
  if (m.diurnalRangeC >= 15) tips.push('일교차가 커 겉옷을 꼭 챙기세요');
  const grade: Grade = risk ? 'risk' : caution ? 'caution' : 'good';
  const advice = tips.length ? tips.join('. ') + '.' :
    '날씨가 안정적이에요. 편안한 캠핑이 예상됩니다.';
  return { grade, advice };
}

function unavailableWeather(advice: string): WeatherSummary {
  return {
    grade: 'unavailable',
    nightLowC: null,
    precipPct: null,
    windMs: null,
    diurnalRangeC: null,
    advice,
  };
}

function forecastDateInRange(date: string, now = new Date()): boolean {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
  if (match == null) return false;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const requestedDay = Date.UTC(year, month - 1, day);
  const validated = new Date(requestedDay);
  if (
    validated.getUTCFullYear() !== year ||
    validated.getUTCMonth() !== month - 1 ||
    validated.getUTCDate() !== day
  ) return false;

  const todayKst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  const today = Date.UTC(
    todayKst.getUTCFullYear(),
    todayKst.getUTCMonth(),
    todayKst.getUTCDate(),
  );
  const daysAhead = Math.round((requestedDay - today) / 86_400_000);
  return daysAhead >= 0 && daysAhead < 16;
}

export async function fetchWeather(lat: number, lon: number, date: string): Promise<WeatherSummary> {
  if (!forecastDateInRange(date)) {
    return unavailableWeather('선택한 날짜는 단기 예보 범위 밖이에요. 출발 전에 최신 예보를 확인해주세요.');
  }

  const url = new URL('https://api.open-meteo.com/v1/forecast');
  url.searchParams.set('latitude', String(lat));
  url.searchParams.set('longitude', String(lon));
  url.searchParams.set('daily',
    'temperature_2m_min,temperature_2m_max,precipitation_probability_max,wind_speed_10m_max');
  url.searchParams.set('timezone', 'Asia/Seoul');
  url.searchParams.set('start_date', date);
  url.searchParams.set('end_date', date);
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
    if (!res.ok) {
      return unavailableWeather('날씨 예보를 불러오지 못했어요. 출발 전에 최신 예보를 확인해주세요.');
    }
    const j: any = await res.json();
    const min = j?.daily?.temperature_2m_min?.[0];
    const max = j?.daily?.temperature_2m_max?.[0];
    const precip = j?.daily?.precipitation_probability_max?.[0];
    const windKmh = j?.daily?.wind_speed_10m_max?.[0];
    if (
      typeof min !== 'number' ||
      typeof max !== 'number' ||
      typeof precip !== 'number' ||
      typeof windKmh !== 'number'
    ) {
      return unavailableWeather('날씨 예보가 완전하지 않아요. 출발 전에 최신 예보를 확인해주세요.');
    }
    const metrics: Metrics = {
      nightLowC: Math.round(min),
      precipPct: precip,
      windMs: Math.round((windKmh / 3.6) * 10) / 10,
      diurnalRangeC: Math.round(max - min),
    };
    const { grade, advice } = gradeWeather(metrics);
    return { grade, ...metrics, advice };
  } catch {
    return unavailableWeather('날씨 예보를 불러오지 못했어요. 출발 전에 최신 예보를 확인해주세요.');
  }
}
