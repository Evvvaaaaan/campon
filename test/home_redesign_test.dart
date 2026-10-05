import 'package:campon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('홈은 API 첫 캠핑장과 기존 로고 및 하단 메뉴를 함께 유지한다', (tester) async {
    final api = _WeeklyApi();
    await tester.pumpWidget(CampOnApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();

    expect(api.nearbyCalls, 1);
    expect(find.text('CampOn'), findsOneWidget);
    for (final label in ['홈', '캠핑장', '추천', '체크리스트', '설정']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.drag(
      find
          .descendant(
            of: find.byType(HomeScreen),
            matching: find.byType(ListView),
          )
          .first,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    expect(find.text('첫 번째 API 캠핑장'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('일정이 없으면 새 계획 CTA와 기존 로고를 보여준다', (tester) async {
    _usePhoneView(tester);
    await tester.pumpWidget(_home(weekly: Future.value(const <Campsite>[])));
    await tester.pumpAndSettle();

    expect(find.text('CampOn'), findsOneWidget);
    expect(find.text('어디로\n떠나볼까요?'), findsOneWidget);
    expect(find.text('캠핑 계획 만들기'), findsOneWidget);
    expect(find.text('D-3'), findsNothing);
  });

  testWidgets('API가 준 추천 순서를 한 장씩 넘겨 보여준다', (tester) async {
    _usePhoneView(tester);
    Campsite? opened;
    final sites = [_site(1, '첫 번째 캠핑장'), _site(2, '두 번째 캠핑장')];
    await tester.pumpWidget(
      _home(
        weekly: Future.value(sites),
        onOpenWeeklyRecommendation: (site) => opened = site,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('첫 번째 캠핑장'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.text('두 번째 캠핑장'));
    expect(opened?.id, 2);
  });

  testWidgets('추천 API 실패 시 다시 시도할 수 있다', (tester) async {
    _usePhoneView(tester);
    var retries = 0;
    final failing = Future<List<Campsite>>.error(
      const CampOnApiException('연결 실패'),
    );
    failing.ignore();
    await tester.pumpWidget(
      _home(weekly: failing, onRetryWeeklyRecommendations: () => retries++),
    );
    await tester.pumpAndSettle();

    expect(find.text('추천을 불러오지 못했어요'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    expect(retries, 1);
  });

  testWidgets('확정한 캠핑 일정은 실제 D-day와 체크리스트 진행률을 보여준다', (tester) async {
    _usePhoneView(tester);
    await tester.pumpWidget(
      _home(
        weekly: Future.value(const <Campsite>[]),
        tripDate: DateTime(2026, 9, 18),
        tripSite: _site(1, '솔바람 캠핑장'),
        now: DateTime(2026, 9, 15),
        checklistDone: 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('D-3'), findsOneWidget);
    expect(find.text('솔바람 캠핑장'), findsOneWidget);
    expect(find.text('2 / 10'), findsOneWidget);
    expect(find.text('어디로\n떠나볼까요?'), findsNothing);
  });

  testWidgets('홈 하단의 오늘 밤 하늘을 AI 플래너 진입 카드로 대체한다', (tester) async {
    _usePhoneView(tester);
    var plannerOpened = false;
    await tester.pumpWidget(
      _home(
        weekly: Future.value(const <Campsite>[]),
        tripDate: DateTime(2026, 9, 18),
        tripSite: _site(1, '솔바람 캠핑장'),
        onPlanner: () => plannerOpened = true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('오늘 밤 하늘'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('AI 플래너 시작하기'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(
      find
          .descendant(of: find.byType(HomeScreen), matching: find.byType(ListView))
          .first,
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI 플래너'), findsOneWidget);
    await tester.tap(find.text('AI 플래너 시작하기'));
    expect(plannerOpened, isTrue);
  });
}

void _usePhoneView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Widget _home({
  required Future<List<Campsite>> weekly,
  ValueChanged<Campsite>? onOpenWeeklyRecommendation,
  VoidCallback? onRetryWeeklyRecommendations,
  DateTime? tripDate,
  Campsite? tripSite,
  DateTime? now,
  int checklistDone = 0,
  VoidCallback? onPlanner,
}) {
  return MaterialApp(
    home: CampThemeScope(
      isDark: false,
      toggle: () {},
      child: Scaffold(
        body: HomeScreen(
          onStart: () {},
          onBrowse: () {},
          onRecommendations: () {},
          onPlanner: onPlanner ?? () {},
          onChecklist: () {},
          onFavorites: () {},
          favoriteCount: 0,
          weeklyRecommendations: weekly,
          onRetryWeeklyRecommendations: onRetryWeeklyRecommendations ?? () {},
          onOpenWeeklyRecommendation: onOpenWeeklyRecommendation ?? (_) {},
          tripDate: tripDate,
          region: CampData.regions[1],
          people: 2,
          tripSite: tripSite,
          checklistDone: checklistDone,
          checklistTotal: 10,
          hasRecommended: false,
          now: now,
        ),
      ),
    ),
  );
}

Campsite _site(int id, String name) => Campsite.fromJson({
  'campsiteId': id,
  'name': name,
  'lineIntro': '$name 소개',
  'lat': 37.8,
  'lon': 128.1,
  'facility': <String>['ELECTRICITY'],
  'equipmentRental': <String>[],
});

class _WeeklyApi extends CampOnApi {
  _WeeklyApi() : super(sessionStore: _MemoryStore());

  int nearbyCalls = 0;

  @override
  Future<List<Campsite>> fetchNearby({
    required CampRegion region,
    required int page,
    required int size,
  }) async {
    nearbyCalls++;
    return [_site(1, '첫 번째 API 캠핑장'), _site(2, '두 번째 API 캠핑장')];
  }
}

class _MemoryStore implements AuthSessionStore {
  AuthSession? _session = AuthSession(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    tokenType: 'Bearer',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    provider: AuthProvider.google,
  );

  @override
  Future<void> clear() async => _session = null;

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> write(AuthSession value) async => _session = value;
}
