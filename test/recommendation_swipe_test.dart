import 'package:campon/main.dart';
import 'package:campon/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => CampColors.apply(CampPalette.light));

  testWidgets('X를 누르면 다음 캠핑장으로 넘어간다', (tester) async {
    await tester.pumpWidget(_host(_sites(3)));
    await tester.pumpAndSettle();

    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('캠핑장 1'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('이 캠핑장 넘기기'));
    await tester.pumpAndSettle();

    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('캠핑장 1'), findsNothing);
  });

  testWidgets('하트를 누르면 저장하고 다음으로 넘어간다', (tester) async {
    final favorited = <int>[];
    await tester.pumpWidget(
      _host(_sites(2), onFavorite: (site) => favorited.add(site.id)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('이 캠핑장 저장하기'));
    await tester.pumpAndSettle();

    expect(favorited, [1]);
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('카드를 다 넘기면 종료 화면과 다시 보기가 나온다', (tester) async {
    await tester.pumpWidget(_host(_sites(2)));
    await tester.pumpAndSettle();

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.bySemanticsLabel('이 캠핑장 넘기기'));
      await tester.pumpAndSettle();
    }

    expect(find.text('모든 추천을 확인했어요!'), findsOneWidget);
    expect(find.bySemanticsLabel('이 캠핑장 넘기기'), findsNothing);

    await tester.tap(find.text('다시 보기'));
    await tester.pumpAndSettle();

    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('캠핑장 1'), findsOneWidget);
  });

  testWidgets('카드를 좌로 끌어도 다음으로 넘어간다', (tester) async {
    await tester.pumpWidget(_host(_sites(2)));
    await tester.pumpAndSettle();

    await tester.drag(find.text('캠핑장 1'), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('살짝만 끌면 제자리로 돌아온다', (tester) async {
    await tester.pumpWidget(_host(_sites(2)));
    await tester.pumpAndSettle();

    await tester.drag(find.text('캠핑장 1'), const Offset(-30, 0));
    await tester.pumpAndSettle();

    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('캠핑장 1'), findsOneWidget);
  });

  testWidgets('카드를 누르면 상세로 넘긴다', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      _host(_sites(2), onSelect: (site) => opened.add(site.name)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('캠핑장 1'));
    await tester.pumpAndSettle();

    expect(opened, ['캠핑장 1']);
  });
}

List<Campsite> _sites(int count) => [
  for (var i = 1; i <= count; i++)
    Campsite.fromJson({
      'campsiteId': i,
      'name': '캠핑장 $i',
      'lat': 37.8,
      'lon': 128.1,
      'distance': 4000 * i,
      'facility': ['ELECTRICITY'],
      'equipmentRental': [],
    }),
];

Widget _host(
  List<Campsite> sites, {
  ValueChanged<Campsite>? onFavorite,
  ValueChanged<Campsite>? onSelect,
}) {
  final favorites = <int>{};
  return MaterialApp(
    home: Scaffold(
      body: RecommendationSwipeScreen(
        title: '오늘의 추천',
        subtitle: '마음에 들면 하트, 아니면 X를 눌러 다음 캠핑장을 확인하세요.',
        future: Future<List<Campsite>>.value(sites),
        emptyText: '조건에 맞는 캠핑장을 찾지 못했어요.',
        onRetry: () {},
        onResetCondition: null,
        onSelect: onSelect ?? (_) {},
        onFavorite: (site) {
          favorites.add(site.id);
          onFavorite?.call(site);
        },
        isFavorite: (site) => favorites.contains(site.id),
      ),
    ),
  );
}
