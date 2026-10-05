import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  buildCampsiteImageQuery,
  parseNaverImageItems,
  searchCampsiteImages,
} from './_campsite_image.ts';

test('캠핑장명과 지역으로 검색어를 만든다', () => {
  assert.equal(
    buildCampsiteImageQuery(' 난지캠핑장 ', ' 서울 마포구 '),
    '난지캠핑장 서울 마포구 캠핑장',
  );
});

test('HTTPS 이미지 결과만 순서를 유지해 반환한다', () => {
  assert.deepEqual(
    parseNaverImageItems({
      items: [
        {
          title: '<b>난지</b>캠핑장 전경',
          link: 'https://images.example/a.jpg',
          thumbnail: 'https://thumb.example/a.jpg',
        },
        { title: '평문 이미지', link: 'http://images.example/b.jpg' },
      ],
    }),
    [
      {
        title: '난지캠핑장 전경',
        imageUrl: 'https://images.example/a.jpg',
        thumbnailUrl: 'https://thumb.example/a.jpg',
        sourceUrl: 'https://images.example/a.jpg',
      },
    ],
  );
});

test('API HUB 주소와 인증 헤더로 이미지 검색을 호출한다', async () => {
  let requestedUrl = '';
  let requestedHeaders: HeadersInit | undefined;
  const result = await searchCampsiteImages('테스트 야영장', '강원', {
    clientId: 'client-id',
    clientSecret: 'client-secret',
    fetcher: async (input, init) => {
      requestedUrl = String(input);
      requestedHeaders = init?.headers;
      return {
        ok: true,
        status: 200,
        text: async () =>
          JSON.stringify({
            items: [{ link: 'https://images.example/camp.jpg' }],
          }),
      };
    },
  });

  const url = new URL(requestedUrl);
  assert.equal(url.origin, 'https://naverapihub.apigw.ntruss.com');
  assert.equal(url.pathname, '/search/v1/image');
  assert.equal(url.searchParams.get('query'), '테스트 야영장 강원 캠핑장');
  assert.equal(url.searchParams.get('filter'), 'large');
  assert.deepEqual(requestedHeaders, {
    'X-NCP-APIGW-API-KEY-ID': 'client-id',
    'X-NCP-APIGW-API-KEY': 'client-secret',
  });
  assert.equal(result.images[0]?.imageUrl, 'https://images.example/camp.jpg');
});
