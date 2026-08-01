import 'package:campon/main.dart';
import 'package:campon/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => CampColors.apply(CampPalette.light));

  testWidgets('찜한 캠핑장을 순서대로 보여준다', (tester) async {
    await tester.pumpWidget(_host(_sites(2)));
    await tester.pumpAndSettle();

    expect(find.text('찜한 캠핑장'), findsOneWidget);
    expect(find.text('캠핑장 1'), findsOneWidget);
    expect(find.text('캠핑장 2'), findsOneWidget);
    expect(find.byType(CampsiteCard), findsNWidgets(2));
  });

  testWidgets('카드를 누르면 상세로 넘긴다', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      _host(_sites(2), onSelect: (site) => opened.add(site.name)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('캠핑장 2'));
    await tester.pumpAndSettle();

    expect(opened, ['캠핑장 2']);
  });

  testWidgets('비어 있으면 안내와 추천 시작 버튼이 나온다', (tester) async {
    var started = 0;
    await tester.pumpWidget(
      _host(const <Campsite>[], onStartRecommend: () => started++),
    );
    await tester.pumpAndSettle();

    expect(find.text('아직 찜한 캠핑장이 없어요'), findsOneWidget);
    expect(find.byType(CampsiteCard), findsNothing);

    await tester.tap(find.text('추천 시작'));
    await tester.pumpAndSettle();

    expect(started, 1);
  });

  testWidgets('찜 목록에서는 점수를 보여주지 않는다', (tester) async {
    await tester.pumpWidget(_host(_sites(1)));
    await tester.pumpAndSettle();

    final card = tester.widget<CampsiteCard>(find.byType(CampsiteCard));
    expect(card.showScore, isFalse);
  });

  testWidgets('찜 목록에서는 저장 당시의 거리를 보여주지 않는다', (tester) async {
    // 찜한 캠핑장의 거리는 저장 당시 검색 지역 기준이라 갱신되지 않으므로,
    // 다른 지역으로 옮겨도 오래된 거리가 남지 않도록 화면에서 숨긴다.
    await tester.pumpWidget(_host(_sites(2)));
    await tester.pumpAndSettle();

    expect(find.text('4.0km'), findsNothing);
    expect(find.text('8.0km'), findsNothing);
  });
}

List<Campsite> _sites(int count) => [
  for (var i = 1; i <= count; i++)
    Campsite.fromJson({
      'campsiteId': i,
      'name': '캠핑장 $i',
      'score': 90,
      'lat': 37.8,
      'lon': 128.1,
      'distance': 4000 * i,
      'facility': <String>[],
      'equipmentRental': <String>[],
    }),
];

Widget _host(
  List<Campsite> sites, {
  ValueChanged<Campsite>? onSelect,
  VoidCallback? onStartRecommend,
}) {
  return MaterialApp(
    home: Scaffold(
      body: FavoritesScreen(
        sites: sites,
        onSelect: onSelect ?? (_) {},
        onStartRecommend: onStartRecommend ?? () {},
      ),
    ),
  );
}
