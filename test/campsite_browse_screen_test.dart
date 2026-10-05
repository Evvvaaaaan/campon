import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campon/main.dart';

Campsite _site(int id) => Campsite.fromJson(<String, dynamic>{
  'campsiteId': id,
  'name': '캠핑장 $id',
  'lat': 37.4,
  'lon': 128.5,
});

void main() {
  testWidgets('기본은 리스트, 지도 세그먼트를 탭하면 지도 빌더가 렌더링된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CampsiteBrowseScreen(
            title: '주변 캠핑장',
            subtitle: '테스트 부제',
            future: Future.value([_site(1), _site(2)]),
            emptyText: '결과 없음',
            onRetry: () {},
            onSelect: (_) {},
            mapViewBuilder: (sites, onSelect) =>
                Text('지도 뷰 · ${sites.length}곳'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('캠핑장 1'), findsOneWidget);
    expect(find.textContaining('지도 뷰'), findsNothing);

    await tester.tap(find.text('지도'));
    await tester.pumpAndSettle();

    expect(find.textContaining('지도 뷰 · 2곳'), findsOneWidget);
    expect(find.textContaining('캠핑장 1'), findsNothing);
  });

  testWidgets('CampsiteCard는 거리를 배지 한 곳에만, 우편번호 없이 보여준다', (
    tester,
  ) async {
    final site = Campsite.fromJson(<String, dynamic>{
      'campsiteId': 1,
      'name': '캠핑장 1',
      'lat': 37.4,
      'lon': 128.5,
      'distance': 4000,
      'zipcode': '24004',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CampsiteCard(site: site, showScore: false, onTap: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('4.0km'), findsOneWidget);
    expect(find.textContaining('우편번호'), findsNothing);
  });
}
