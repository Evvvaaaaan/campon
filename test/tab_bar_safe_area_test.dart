import 'package:campon/main.dart';
import 'package:campon/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 홈 인디케이터 영역까지 탭바와 같은 색으로 채워야 바가 떠 보이지 않는다.
void main() {
  tearDown(() => CampColors.apply(CampPalette.light));

  testWidgets('탭바 배경이 화면 맨 아래까지 이어진다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(CampOnApp(api: _StubApi()));
    await tester.pumpAndSettle();

    final background = find
        .descendant(
          of: find.byType(CampTabBar),
          matching: find.byType(DecoratedBox),
        )
        .first;
    final decoration =
        tester.widget<DecoratedBox>(background).decoration as BoxDecoration;

    expect(decoration.color, CampColors.surface);
    expect(tester.getRect(background).bottom, 800);
  });
}

class _StubApi extends CampOnApi {
  _StubApi() : super(sessionStore: _MemoryStore());
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
