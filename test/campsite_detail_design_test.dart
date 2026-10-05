import 'package:campon/main.dart';
import 'package:campon/campsites/campsite_reservation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('상세 상단은 전폭 사진 안에 이름과 탐색 버튼을 함께 보여준다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pump();

    final hero = find.byKey(const Key('campsite-detail-hero'));
    final heroRect = tester.getRect(hero);
    final title = find.descendant(of: hero, matching: find.text('숲속 캠핑장'));

    expect(heroRect.left, 0);
    expect(heroRect.width, 390);
    expect(heroRect.height, greaterThan(300));
    expect(title, findsOneWidget);
    expect(heroRect.contains(tester.getCenter(title)), isTrue);
    expect(
      find.descendant(of: hero, matching: find.textContaining('경기')),
      findsNothing,
    );
    expect(
      find.descendant(of: hero, matching: find.textContaining('우편번호')),
      findsNothing,
    );
    expect(
      find.descendant(of: hero, matching: find.byType(BackCircleButton)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: hero, matching: find.byType(FavoriteHeartButton)),
      findsOneWidget,
    );
  });

  testWidgets('상세 상단 사진을 밀면 다음 사진으로 넘어간다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _host(
        imageUrls: const [
          'https://example.com/first.jpg',
          'https://example.com/second.jpg',
        ],
      ),
    );
    await tester.pump();

    final hero = find.byKey(const Key('campsite-detail-hero'));
    final pageView = find.descendant(of: hero, matching: find.byType(PageView));
    expect(pageView, findsOneWidget);
    expect(tester.widget<PageView>(pageView).controller!.page, 0);

    await tester.drag(pageView, const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(tester.widget<PageView>(pageView).controller!.page, 1);
  });

  testWidgets('사진 다음에는 의사결정용 요약 정보를 먼저 보여준다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pump();

    final summary = find.byKey(const Key('campsite-detail-summary'));
    expect(summary, findsOneWidget);
    expect(
      find.descendant(of: summary, matching: find.text('예약 정보')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('예약하기')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('추천 점수')),
      findsNothing,
    );
    expect(
      find.descendant(of: summary, matching: find.text('88점')),
      findsNothing,
    );
    expect(
      find.descendant(of: summary, matching: find.text('거리')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('4.0km')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('시설 점수')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('4.0 / 5')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.textContaining('개')),
      findsNothing,
    );
  });

  testWidgets('예약 URL이 없으면 네이버에서 찾은 링크를 연다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Uri? openedUrl;

    await tester.pumpWidget(
      _host(
        reservationUrl: '',
        reservationService: CampsiteReservationService(
          baseUrl: 'https://proxy.example',
          fetcher: (_) async =>
              '{"reservation":{"url":"https://naver.example/camp"}}',
        ),
        openUrl: (url) async {
          openedUrl = url;
          return true;
        },
      ),
    );
    await tester.pump();

    expect(find.text('네이버 찾기'), findsOneWidget);
    await tester.tap(find.text('네이버 찾기'));
    await tester.pumpAndSettle();

    expect(openedUrl, Uri.parse('https://naver.example/camp'));
  });

  testWidgets('네이버 업체 링크가 없어도 네이버 예약 검색을 연다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Uri? openedUrl;

    await tester.pumpWidget(
      _host(
        reservationUrl: '',
        reservationService: CampsiteReservationService(baseUrl: ''),
        openUrl: (url) async {
          openedUrl = url;
          return true;
        },
      ),
    );
    await tester.pump();

    await tester.tap(find.text('네이버 찾기'));
    await tester.pumpAndSettle();

    expect(openedUrl?.host, 'search.naver.com');
    expect(openedUrl?.queryParameters['query'], '숲속 캠핑장 예약');
  });

  testWidgets('편의시설은 API 시설 정보로 계산한 항목별 점수를 보여준다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pump();

    final facilities = find.byKey(const Key('campsite-detail-facilities'));
    await tester.scrollUntilVisible(facilities, 300);

    expect(
      find.descendant(of: facilities, matching: find.text('5 / 5')),
      findsNWidgets(3),
    );
    expect(
      find.descendant(of: facilities, matching: find.text('1 / 5')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: facilities,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Text && RegExp(r'^\d+개$').hasMatch(widget.data ?? ''),
        ),
      ),
      findsNothing,
    );
  });
}

Widget _host({
  List<String> imageUrls = const [],
  String reservationUrl = 'https://example.com/reservation',
  CampsiteReservationService? reservationService,
  Future<bool> Function(Uri)? openUrl,
}) => MaterialApp(
  home: Scaffold(
    body: CampsiteDetailScreen(
      api: _StubApi(),
      site: Campsite.fromJson({
        'campsiteId': 1,
        'name': '숲속 캠핑장',
        'lineIntro': '나무 사이에서 쉬어가는 조용한 캠핑장',
        'description': '숲과 가까워 여유롭게 머물기 좋은 곳입니다.',
        'score': 88,
        'lat': 37.8,
        'lon': 128.1,
        'distance': 4000,
        'zipcode': '12345',
        'resveUrl': reservationUrl,
        'imageUrls': imageUrls,
        'facility': <String>['TOILET', 'SHOWER', 'ELECTRICITY'],
        'equipmentRental': <String>[],
      }),
      region: CampData.regions.first,
      hasCar: true,
      onBack: () {},
      onCommunity: () {},
      onPrepare: () {},
      isFavorite: false,
      onToggleFavorite: () {},
      reservationService: reservationService,
      openUrl: openUrl,
    ),
  ),
);

class _StubApi extends CampOnApi {}
