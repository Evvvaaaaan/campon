import 'package:campon/campsites/campsite_spatial_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('사진이 없으면 미리보기 진입점을 숨긴다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CampsiteSpatialPreviewCard(
            campsiteName: '별빛 캠핑장',
            imageUrls: <String>[],
          ),
        ),
      ),
    );

    expect(find.text('입체로 둘러보기'), findsNothing);
  });

  testWidgets('카드를 누르면 사진 기반 입체 미리보기를 연다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CampsiteSpatialPreviewCard(
            campsiteName: '별빛 캠핑장',
            imageUrls: <String>[
              'https://example.com/one.jpg',
              'https://example.com/two.jpg',
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('입체로 둘러보기'));
    await tester.pumpAndSettle();

    expect(find.text('별빛 캠핑장'), findsOneWidget);
    expect(find.text('사진 기반 입체 미리보기'), findsOneWidget);
    expect(find.text('장면 1/2'), findsOneWidget);
    expect(find.byKey(const Key('spatial-preview-gesture')), findsOneWidget);
  });

  testWidgets('핫스팟을 누르면 다음 사진 장면으로 이동한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CampsiteSpatialPreviewScreen(
          campsiteName: '별빛 캠핑장',
          imageUrls: <String>[
            'https://example.com/one.jpg',
            'https://example.com/two.jpg',
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('장면 1/2'), findsOneWidget);

    final hotspot = find.byKey(const Key('spatial-preview-next'));
    expect(hotspot.hitTestable(), findsOneWidget);

    await tester.tap(hotspot);
    await tester.pumpAndSettle();

    expect(find.text('장면 2/2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('spatial-scene-https://example.com/two.jpg')),
      findsOneWidget,
    );
  });

  testWidgets('사진을 드래그하면 입체 시점 변환이 바뀐다', (tester) async {
    const imageUrl = 'https://example.com/one.jpg';
    const sceneKey = ValueKey('spatial-scene-$imageUrl');
    const gestureKey = Key('spatial-preview-gesture');
    await tester.pumpWidget(
      const MaterialApp(
        home: CampsiteSpatialPreviewScreen(
          campsiteName: '별빛 캠핑장',
          imageUrls: <String>[imageUrl],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final before = List<double>.of(
      tester.widget<Transform>(find.byKey(sceneKey)).transform.storage,
    );

    await tester.drag(find.byKey(gestureKey), const Offset(80, 30));
    await tester.pump();

    final after = tester
        .widget<Transform>(find.byKey(sceneKey))
        .transform
        .storage;
    expect(after, isNot(equals(before)));
  });
}
