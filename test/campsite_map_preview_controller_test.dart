import 'package:campon/campsites/campsite_map_view.dart';
import 'package:campon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Campsite _site({String? thumbnailUrl}) => Campsite.fromJson(<String, dynamic>{
  'campsiteId': 1,
  'score': 87,
  'name': '테스트 캠핑장',
  'lat': 37.4,
  'lon': 128.5,
  'distance': 4200,
  'facility': ['TOILET', 'ELECTRICITY', 'SHOWER'],
  'thumbnailUrl': ?thumbnailUrl,
});

void main() {
  test('select()는 미리보기 대상을 설정하고 clear()는 비운다', () {
    final controller = MapPreviewController();
    expect(controller.value, isNull);

    final site = _site();
    controller.select(site);
    expect(controller.value, site);

    controller.clear();
    expect(controller.value, isNull);
  });

  testWidgets('미리보기 카드는 썸네일과 캠핑장 핵심 정보를 보여준다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CampsiteMapPreviewCard(
            site: _site(thumbnailUrl: 'https://example.com/camp.jpg'),
            onTap: () {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('campsite-map-preview-thumbnail')),
      findsOneWidget,
    );
    expect(find.text('테스트 캠핑장'), findsOneWidget);
    expect(find.text('4.2km'), findsOneWidget);
    expect(find.text('추천 87점'), findsOneWidget);
    expect(find.text('화장실'), findsOneWidget);
    expect(find.text('전기 사용 가능'), findsOneWidget);
    expect(find.text('샤워실'), findsNothing);
  });

  testWidgets('미리보기 카드를 누르면 선택 콜백을 호출한다', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CampsiteMapPreviewCard(
            site: _site(),
            onTap: () => tapped = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('campsite-map-preview-card')));

    expect(tapped, isTrue);
  });
}
