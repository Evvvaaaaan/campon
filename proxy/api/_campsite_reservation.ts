export type CampsiteReservation = {
  title: string;
  url: string;
};

export type CampsiteReservationSearchResult = {
  query: string;
  source: 'naver';
  reservation: CampsiteReservation | null;
};

type FetchLike = (
  input: string | URL,
  init?: RequestInit,
) => Promise<Pick<Response, 'ok' | 'status' | 'text'>>;

type SearchOptions = {
  clientId?: string;
  clientSecret?: string;
  fetcher?: FetchLike;
};

const endpoint = 'https://naverapihub.apigw.ntruss.com/search/v1/local';
const cacheTtlMs = 24 * 60 * 60 * 1000;
const cache = new Map<
  string,
  { expiresAt: number; value: CampsiteReservationSearchResult }
>();

export function buildCampsiteReservationQuery(name: string): string {
  return `${name.trim()} 예약`;
}

export function parseNaverReservation(
  value: unknown,
): CampsiteReservation | null {
  if (!value || typeof value !== 'object') return null;
  const items = (value as { items?: unknown }).items;
  if (!Array.isArray(items)) return null;

  for (const item of items) {
    if (!item || typeof item !== 'object') continue;
    const raw = item as Record<string, unknown>;
    const url = webUrl(raw.link);
    if (!url) continue;
    return {
      title: stripHtml(typeof raw.title === 'string' ? raw.title : ''),
      url,
    };
  }
  return null;
}

export async function searchCampsiteReservation(
  name: string,
  options: SearchOptions = {},
): Promise<CampsiteReservationSearchResult> {
  if (!name.trim()) throw new Error('campsite name is required');
  const query = buildCampsiteReservationQuery(name);
  const cached = cache.get(query);
  if (cached && cached.expiresAt > Date.now()) return cached.value;

  const clientId = options.clientId ?? process.env.NAVER_API_HUB_CLIENT_ID;
  const clientSecret =
    options.clientSecret ?? process.env.NAVER_API_HUB_CLIENT_SECRET;
  if (!clientId || !clientSecret) {
    throw new Error('NAVER API HUB credentials are not configured');
  }

  const url = new URL(endpoint);
  url.searchParams.set('query', query);
  url.searchParams.set('display', '5');
  url.searchParams.set('start', '1');
  url.searchParams.set('sort', 'random');
  url.searchParams.set('format', 'json');

  const response = await (options.fetcher ?? fetch)(url, {
    headers: {
      'X-NCP-APIGW-API-KEY-ID': clientId,
      'X-NCP-APIGW-API-KEY': clientSecret,
    },
    signal: AbortSignal.timeout(8_000),
  });
  const body = await response.text();
  if (!response.ok) {
    throw new Error(`NAVER local search failed with HTTP ${response.status}`);
  }

  const result: CampsiteReservationSearchResult = {
    query,
    source: 'naver',
    reservation: parseNaverReservation(JSON.parse(body)),
  };
  cache.set(query, { expiresAt: Date.now() + cacheTtlMs, value: result });
  return result;
}

function webUrl(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' || url.protocol === 'http:'
      ? url.toString()
      : null;
  } catch {
    return null;
  }
}

function stripHtml(value: string): string {
  return value.replace(/<[^>]*>/g, '').trim();
}
