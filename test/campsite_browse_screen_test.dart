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

  testWidgets('CampsiteCard는 기본적으로 거리를 보여준다', (tester) async {
    final site = Campsite.fromJson(<String, dynamic>{
      'campsiteId': 1,
      'name': '캠핑장 1',
      'lat': 37.4,
      'lon': 128.5,
      'distance': 4000,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CampsiteCard(site: site, showScore: false, onTap: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 배지와 캡션 줄 모두에 거리가 나오므로(우편번호가 없는 픽스처라 캡션도
    // 거리만 표시), 최소 한 곳에는 있는지만 확인한다.
    expect(find.text('4.0km'), findsWidgets);
  });
}
