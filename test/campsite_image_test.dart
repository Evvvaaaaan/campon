import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campon/main.dart';
import 'package:campon/campsites/campsite_image_service.dart';

Campsite _site({String? thumbnailUrl, List<String>? imageUrls}) =>
    Campsite.fromJson(<String, dynamic>{
      'campsiteId': 1,
      'name': '캠핑장 1',
      'lat': 37.4,
      'lon': 128.5,
      'thumbnailUrl': ?thumbnailUrl,
      'imageUrls': ?imageUrls,
    });

void main() {
  group('Campsite 썸네일 대체', () {
    test('thumbnailUrl이 없으면 imageUrls의 첫 이미지를 쓴다', () {
      final site = _site(
        imageUrls: ['https://example.com/a.jpg', 'https://example.com/b.jpg'],
      );

      expect(site.validThumbnailUrl, 'https://example.com/a.jpg');
    });

    test('thumbnailUrl이 있으면 그대로 쓴다', () {
      final site = _site(
        thumbnailUrl: 'https://example.com/thumb.jpg',
        imageUrls: ['https://example.com/a.jpg'],
      );

      expect(site.validThumbnailUrl, 'https://example.com/thumb.jpg');
    });

    test('thumbnailUrl과 imageUrls가 모두 없으면 null이다', () {
      expect(_site().validThumbnailUrl, isNull);
    });

    test('validImageUrls는 http/https가 아닌 값을 걸러낸다', () {
      final site = _site(imageUrls: ['https://example.com/a.jpg', 'not-a-url']);

      expect(site.validImageUrls, ['https://example.com/a.jpg']);
    });
  });

  group('CampsiteHeroImage', () {
    testWidgets('이미지가 없으면 플레이스홀더를 보여준다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CampsiteHeroImage(site: _site())),
        ),
      );
      await tester.pump();

      expect(find.byType(CampImagePlaceholder), findsOneWidget);
      expect(find.byType(PageView), findsNothing);
    });

    testWidgets('이미지가 하나면 점 인디케이터를 보여주지 않는다', (tester) async {
      final site = _site(imageUrls: ['https://example.com/a.jpg']);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CampsiteHeroImage(site: site)),
        ),
      );
      await tester.pump();

      expect(find.byType(PageView), findsOneWidget);
      expect(_dotIndicators(), findsNothing);
    });

    testWidgets('이미지가 여러 장이면 imageUrls 개수만큼 점 인디케이터를 보여준다', (tester) async {
      final site = _site(
        imageUrls: [
          'https://example.com/a.jpg',
          'https://example.com/b.jpg',
          'https://example.com/c.jpg',
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CampsiteHeroImage(site: site)),
        ),
      );
      await tester.pump();

      expect(find.byType(PageView), findsOneWidget);
      expect(_dotIndicators(), findsNWidgets(3));
    });

    testWidgets('thumbnailUrl만 있고 imageUrls가 없으면 단일 이미지 슬라이드로 보여준다', (
      tester,
    ) async {
      final site = _site(thumbnailUrl: 'https://example.com/thumb.jpg');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CampsiteHeroImage(site: site)),
        ),
      );
      await tester.pump();

      expect(find.byType(PageView), findsOneWidget);
      expect(_dotIndicators(), findsNothing);
    });

    testWidgets('기존 이미지가 있으면 fallback API를 호출하지 않는다', (tester) async {
      var calls = 0;
      final service = CampsiteImageService(
        baseUrl: 'https://images.campon.example',
        fetcher: (_) async {
          calls++;
          return '{"images":[]}';
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CampsiteHeroImage(
              site: _site(thumbnailUrl: 'https://example.com/thumb.jpg'),
              imageService: service,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(calls, 0);
    });

    testWidgets('기존 이미지가 없으면 검색 이미지와 출처를 보여준다', (tester) async {
      final service = CampsiteImageService(
        baseUrl: 'https://images.campon.example',
        fetcher: (_) async => '''
          {"images":[{
            "title":"캠핑장 1",
            "imageUrl":"https://images.example/camp.jpg",
            "thumbnailUrl":"https://thumb.example/camp.jpg",
            "sourceUrl":"https://images.example/camp.jpg"
          }]}
        ''',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CampsiteHeroImage(site: _site(), imageService: service),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PageView), findsOneWidget);
      expect(find.text('NAVER 검색 이미지 · 원본'), findsOneWidget);
    });
  });
}

Finder _dotIndicators() => find.byWidgetPredicate(
  (widget) =>
      widget is Container &&
      widget.decoration is BoxDecoration &&
      (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
);
