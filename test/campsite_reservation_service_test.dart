import 'package:campon/campsites/campsite_reservation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('프록시에서 네이버 캠핑장 링크를 읽는다', () async {
    late Uri requestedUrl;
    final service = CampsiteReservationService(
      baseUrl: 'https://proxy.example/base/',
      fetcher: (url) async {
        requestedUrl = url;
        return '''
          {"reservation":{"title":"숲속 캠핑장","url":"https://booking.example/camp"}}
        ''';
      },
    );

    final result = await service.lookup(name: '숲속 캠핑장');

    expect(requestedUrl.path, '/base/api/campsite-reservation');
    expect(requestedUrl.queryParameters['name'], '숲속 캠핑장');
    expect(result, Uri.parse('https://booking.example/camp'));
  });

  test('프록시 검색이 실패하면 null을 준다', () async {
    final service = CampsiteReservationService(
      baseUrl: 'https://proxy.example',
      fetcher: (_) async => throw const FormatException(),
    );

    expect(await service.lookup(name: '숲속 캠핑장'), isNull);
  });

  test('네이버 예약 검색 URL에 캠핑장명을 넣는다', () {
    final uri = naverReservationSearchUri('숲속 캠핑장');

    expect(uri.host, 'search.naver.com');
    expect(uri.queryParameters['query'], '숲속 캠핑장 예약');
  });
}
