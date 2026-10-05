import 'dart:convert';

import 'package:campon/campsites/campsite_image_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('캠핑장명과 지역을 Oracle fallback API에 전달한다', () async {
    Uri? requested;
    final service = CampsiteImageService(
      baseUrl: 'https://images.campon.example',
      fetcher: (url) async {
        requested = url;
        return jsonEncode({
          'images': [
            {
              'title': '난지캠핑장',
              'imageUrl': 'https://images.example/camp.jpg',
              'thumbnailUrl': 'https://thumb.example/camp.jpg',
              'sourceUrl': 'https://images.example/camp.jpg',
            },
          ],
        });
      },
    );

    final images = await service.search(name: '난지캠핑장', region: '서울');

    expect(requested?.path, '/api/campsite-image');
    expect(requested?.queryParameters, {'name': '난지캠핑장', 'region': '서울'});
    expect(images.single.imageUrl, 'https://images.example/camp.jpg');
  });

  test('설정이 없거나 응답 URL이 HTTPS가 아니면 빈 결과를 반환한다', () async {
    final unconfigured = CampsiteImageService(baseUrl: '');
    expect(await unconfigured.search(name: '난지캠핑장'), isEmpty);

    final service = CampsiteImageService(
      baseUrl: 'https://images.campon.example',
      fetcher: (_) async => jsonEncode({
        'images': [
          {
            'imageUrl': 'http://images.example/camp.jpg',
            'thumbnailUrl': 'http://thumb.example/camp.jpg',
          },
        ],
      }),
    );
    expect(await service.search(name: '난지캠핑장'), isEmpty);
  });

  test('같은 캠핑장 검색은 앱 실행 중 한 번만 요청한다', () async {
    var calls = 0;
    final service = CampsiteImageService(
      baseUrl: 'https://images.campon.example',
      fetcher: (_) async {
        calls++;
        return '{"images":[]}';
      },
    );

    await service.search(name: '난지캠핑장');
    await service.search(name: '난지캠핑장');

    expect(calls, 1);
  });
}
