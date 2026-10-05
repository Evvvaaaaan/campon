import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  buildCampsiteReservationQuery,
  parseNaverReservation,
  searchCampsiteReservation,
} from './_campsite_reservation.ts';

test('캠핑장명으로 예약 검색어를 만든다', () => {
  assert.equal(buildCampsiteReservationQuery(' 난지캠핑장 '), '난지캠핑장 예약');
});

test('네이버 지역 검색의 첫 웹 링크를 읽는다', () => {
  assert.deepEqual(
    parseNaverReservation({
      items: [
        { title: '링크 없음', link: '' },
        {
          title: '<b>난지</b>캠핑장',
          link: 'https://booking.example/camp',
        },
      ],
    }),
    { title: '난지캠핑장', url: 'https://booking.example/camp' },
  );
});

test('API HUB 지역 검색을 인증 헤더와 함께 호출한다', async () => {
  let requestedUrl = '';
  let requestedHeaders: HeadersInit | undefined;
  const result = await searchCampsiteReservation('테스트 야영장', {
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
            items: [{ title: '테스트', link: 'https://booking.example/test' }],
          }),
      };
    },
  });

  const url = new URL(requestedUrl);
  assert.equal(url.origin, 'https://naverapihub.apigw.ntruss.com');
  assert.equal(url.pathname, '/search/v1/local');
  assert.equal(url.searchParams.get('query'), '테스트 야영장 예약');
  assert.deepEqual(requestedHeaders, {
    'X-NCP-APIGW-API-KEY-ID': 'client-id',
    'X-NCP-APIGW-API-KEY': 'client-secret',
  });
  assert.equal(result.reservation?.url, 'https://booking.example/test');
});
