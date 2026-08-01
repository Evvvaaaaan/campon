import 'package:campon/main.dart';
import 'package:campon/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => CampColors.apply(CampPalette.light));

  testWidgets('첫 진입에 코치마크가 홈 단계부터 뜬다', (tester) async {
    await tester.pumpWidget(CampOnApp(api: _StubApi()));
    await tester.pumpAndSettle();

    expect(find.text('환영해요, 캠퍼님 👋'), findsOneWidget);
    expect(find.text('1 / 5'), findsOneWidget);
    expect(find.text('다음'), findsOneWidget);
    expect(find.text('건너뛰기'), findsOneWidget);
  });

  testWidgets('다음을 누르면 단계와 탭이 함께 넘어간다', (tester) async {
    await tester.pumpWidget(CampOnApp(api: _StubApi()));
    await tester.pumpAndSettle();

    await tester.tap(_inOverlay('다음'));
    await tester.pumpAndSettle();

    expect(find.text('캠핑장을 둘러보세요'), findsOneWidget);
    expect(find.text('2 / 5'), findsOneWidget);
    // 탭도 실제로 캠핑장 화면으로 넘어가 있어야 한다.
    expect(find.text('주변 캠핑장'), findsOneWidget);
  });

  testWidgets('마지막 단계의 시작하기를 누르면 코치마크가 사라진다', (tester) async {
    await tester.pumpWidget(CampOnApp(api: _StubApi()));
    await tester.pumpAndSettle();

    for (var i = 0; i < 4; i++) {
      await tester.tap(_inOverlay('다음'));
      await tester.pumpAndSettle();
    }

    expect(find.text('나만의 환경으로'), findsOneWidget);
    expect(find.text('5 / 5'), findsOneWidget);

    await tester.tap(_inOverlay('시작하기'));
    await tester.pumpAndSettle();

    expect(find.byType(TutorialOverlay), findsNothing);
  });

  testWidgets('건너뛰기를 누르면 즉시 사라진다', (tester) async {
    await tester.pumpWidget(CampOnApp(api: _StubApi()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();

    expect(find.byType(TutorialOverlay), findsNothing);
    expect(find.text('환영해요, 캠퍼님 👋'), findsNothing);
  });
}

/// 뒤 화면에도 같은 글자가 있을 수 있으므로 코치마크 안으로 한정한다.
Finder _inOverlay(String text) => find.descendant(
  of: find.byType(TutorialOverlay),
  matching: find.text(text),
);

class _StubApi extends CampOnApi {
  _StubApi() : super(sessionStore: _MemoryStore());

  static final _sites = [
    Campsite.fromJson({
      'campsiteId': 1,
      'name': '테스트 캠핑장',
      'lat': 37.8,
      'lon': 128.1,
      'facility': ['ELECTRICITY'],
      'equipmentRental': [],
    }),
  ];

  @override
  Future<List<Campsite>> fetchNearby({
    required CampRegion region,
    required int page,
    required int size,
  }) async => _sites;

  @override
  Future<List<Campsite>> fetchAllNearby({required CampRegion region}) async =>
      _sites;
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
