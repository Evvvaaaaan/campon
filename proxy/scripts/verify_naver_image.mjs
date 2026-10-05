const clientId = process.env.NAVER_API_HUB_CLIENT_ID;
const clientSecret = process.env.NAVER_API_HUB_CLIENT_SECRET;

if (!clientId || !clientSecret) {
  console.error(
    'NAVER_API_HUB_CLIENT_ID와 NAVER_API_HUB_CLIENT_SECRET을 설정하세요.',
  );
  process.exit(2);
}

const name = process.argv[2] ?? '난지캠핑장';
const region = process.argv[3] ?? '서울';
const query = [name.trim(), region.trim(), '캠핑장'].filter(Boolean).join(' ');
const url = new URL(
  'https://naverapihub.apigw.ntruss.com/search/v1/image',
);
url.searchParams.set('query', query);
url.searchParams.set('display', '5');
url.searchParams.set('sort', 'sim');
url.searchParams.set('filter', 'large');
url.searchParams.set('format', 'json');

const searchResponse = await fetch(url, {
  headers: {
    'X-NCP-APIGW-API-KEY-ID': clientId,
    'X-NCP-APIGW-API-KEY': clientSecret,
  },
  signal: AbortSignal.timeout(10_000),
});
const body = await searchResponse.text();
console.log(`검색 응답: HTTP ${searchResponse.status}`);
if (!searchResponse.ok) {
  console.error(body);
  process.exit(1);
}

const parsed = JSON.parse(body);
const images = Array.isArray(parsed.items)
  ? parsed.items.filter((item) => {
      try {
        return new URL(item?.link).protocol === 'https:';
      } catch {
        return false;
      }
    })
  : [];
console.log(`HTTPS 이미지 결과: ${images.length}개`);
if (images.length === 0) process.exit(1);

const first = images[0];
const imageUrl = first.thumbnail || first.link;
const imageResponse = await fetch(imageUrl, {
  signal: AbortSignal.timeout(10_000),
});
const contentType = imageResponse.headers.get('content-type') ?? '';
const bytes = (await imageResponse.arrayBuffer()).byteLength;
console.log(`이미지 호스트: ${new URL(imageUrl).host}`);
console.log(`이미지 응답: HTTP ${imageResponse.status}`);
console.log(`이미지 형식: ${contentType || '알 수 없음'}`);
console.log(`이미지 크기: ${bytes} bytes`);

if (!imageResponse.ok || !contentType.startsWith('image/') || bytes === 0) {
  process.exit(1);
}
