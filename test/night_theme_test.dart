import 'package:campon/main.dart';
import 'package:campon/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 야간 캠핑 테마를 켜면 실제로 화면 색이 바뀌는지 확인한다.
///
/// const 위젯은 리빌드에서 통째로 건너뛰므로, 토글 후에도 라이트 색이
/// 남아 있으면 어딘가 const가 덜 벗겨진 것이다. 이 테스트가 그걸 잡는다.
void main() {
  tearDown(() => CampColors.apply(CampPalette.light));

  testWidgets('홈 헤더 토글이 팔레트와 화면 색을 함께 바꾼다', (tester) async {
    await tester.pumpWidget(CampOnApp(api: _StubApi()));
    await tester.pumpAndSettle();
    await _skipTutorial(tester);

    expect(CampColors.isDark, isFalse);
    expect(_tabBarColor(tester), CampPalette.light.surface);

    await tester.tap(find.byType(NightThemeToggle));
    await tester.pumpAndSettle();

    expect(CampColors.isDark, isTrue);
    expect(_tabBarColor(tester), CampPalette.dark.surface);
  });

  testWidgets('설정의 야간 캠핑 테마 행도 같은 상태를 공유한다', (tester) async {
    await tester.pumpWidget(CampOnApp(api: _StubApi()));
    await tester.pumpAndSettle();
    await _skipTutorial(tester);

    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();

    // 설정은 ListView라 화면 밖 항목은 아직 만들어지지 않는다.
    await tester.scrollUntilVisible(
      find.text('야간 캠핑 테마'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    final toggle = find.ancestor(
      of: find.text('야간 캠핑 테마'),
      matching: find.byType(ToggleSettingCard),
    );
    expect(tester.widget<ToggleSettingCard>(toggle).value, isFalse);

    await tester.tap(find.text('야간 캠핑 테마'));
    await tester.pumpAndSettle();

    expect(CampColors.isDark, isTrue);
    expect(tester.widget<ToggleSettingCard>(toggle).value, isTrue);
  });

  testWidgets('다크 팔레트는 디자인의 야간 토큰 값을 쓴다', (tester) async {
    CampColors.apply(CampPalette.dark);

    expect(CampColors.canvas, const Color(0xFF0E1F17));
    expect(CampColors.surface, const Color(0xFF16281E));
    expect(CampColors.hairline, const Color(0xFF28402F));
    expect(CampColors.ink, const Color(0xFFF5EFE1));
    expect(CampColors.forestMid, const Color(0xFF8FD9AE));
    // 텍스트 스타일도 팔레트를 따라와야 한다.
    expect(CampText.body.color, const Color(0xFFF5EFE1));
  });
}

/// 첫 진입 코치마크는 헤더 위를 덮으므로 먼저 닫는다.
Future<void> _skipTutorial(WidgetTester tester) async {
  await tester.tap(find.text('건너뛰기'));
  await tester.pumpAndSettle();
}

Color? _tabBarColor(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byType(CampTabBar),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return (box.decoration as BoxDecoration).color;
}

class _StubApi extends CampOnApi {
  _StubApi() : super(sessionStore: _MemoryStore());

  @override
  Future<List<Campsite>> fetchNearby({
    required CampRegion region,
    required int page,
    required int size,
  }) async => [
    Campsite.fromJson({
      'campsiteId': 1,
      'name': '테스트 캠핑장',
      'lat': 37.8,
      'lon': 128.1,
      'facility': ['ELECTRICITY'],
      'equipmentRental': [],
    }),
  ];
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
