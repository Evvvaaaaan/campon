export type CampsiteImage = {
  title: string;
  imageUrl: string;
  thumbnailUrl: string;
  sourceUrl: string;
};

export type CampsiteImageSearchResult = {
  query: string;
  source: 'naver';
  images: CampsiteImage[];
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

const endpoint = 'https://naverapihub.apigw.ntruss.com/search/v1/image';
const cacheTtlMs = 24 * 60 * 60 * 1000;
const cache = new Map<
  string,
  { expiresAt: number; value: CampsiteImageSearchResult }
>();

export function buildCampsiteImageQuery(name: string, region?: string): string {
  return [name.trim(), region?.trim(), '캠핑장'].filter(Boolean).join(' ');
}

export function parseNaverImageItems(value: unknown): CampsiteImage[] {
  if (!value || typeof value !== 'object') return [];
  const items = (value as { items?: unknown }).items;
  if (!Array.isArray(items)) return [];

  return items.flatMap((item) => {
    if (!item || typeof item !== 'object') return [];
    const raw = item as Record<string, unknown>;
    const imageUrl = httpsUrl(raw.link);
    if (!imageUrl) return [];
    const thumbnailUrl = httpsUrl(raw.thumbnail) ?? imageUrl;
    return [
      {
        title: stripHtml(typeof raw.title === 'string' ? raw.title : ''),
        imageUrl,
        thumbnailUrl,
        sourceUrl: imageUrl,
      },
    ];
  });
}

export async function searchCampsiteImages(
  name: string,
  region?: string,
  options: SearchOptions = {},
): Promise<CampsiteImageSearchResult> {
  const query = buildCampsiteImageQuery(name, region);
  if (!name.trim()) throw new Error('campsite name is required');

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
  url.searchParams.set('sort', 'sim');
  url.searchParams.set('filter', 'large');
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
    throw new Error(`NAVER image search failed with HTTP ${response.status}`);
  }

  const result: CampsiteImageSearchResult = {
    query,
    source: 'naver',
    images: parseNaverImageItems(JSON.parse(body)),
  };
  cache.set(query, { expiresAt: Date.now() + cacheTtlMs, value: result });
  return result;
}

function httpsUrl(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' ? url.toString() : null;
  } catch {
    return null;
  }
}

function stripHtml(value: string): string {
  return value.replace(/<[^>]*>/g, '').trim();
}
