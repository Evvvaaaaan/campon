import 'package:campon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

void main() {
  test('valid persisted session is restored and logout clears it', () async {
    final store = _MemoryAuthSessionStore(
      AuthSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        tokenType: 'Bearer',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        provider: AuthProvider.google,
      ),
    );
    final api = CampOnApi(sessionStore: store);

    expect(await api.restoreSession(), isTrue);

    await api.signOut();

    expect(store.session, isNull);
    expect(await api.restoreSession(), isFalse);
  });

  test('Kakao native app key matches the registered URL scheme', () {
    expect(AuthConfig.kakaoNativeAppKey, '0ecef49f91608f40010f59053f36fa9a');
  });

  testWidgets('login screen is the app entry point', (tester) async {
    await tester.pumpWidget(_appWithEmptySession());
    await tester.pumpAndSettle();

    expect(find.text('캠핑을 시작할\n계정을 선택해주세요'), findsOneWidget);
    // 디버그(테스트) 빌드에서는 개발 계정 로그인이 자동 노출된다.
    expect(find.text('개발 계정으로 시작'), findsOneWidget);
    expect(find.text('카카오로 계속하기'), findsOneWidget);
    expect(find.text('Google로 계속하기'), findsOneWidget);
    expect(find.text('Apple로 계속하기'), findsOneWidget);
    expect(find.byIcon(Icons.apple), findsOneWidget);
  });

  testWidgets('kakao login button is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(_appWithEmptySession());
    await tester.pumpAndSettle();

    expect(find.text('카카오로 계속하기'), findsOneWidget);

    final kakaoButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('카카오로 계속하기'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(kakaoButton.onPressed, isNotNull);
  });

  testWidgets('카카오 로그인 선택 창을 닫으면 오류를 표시하지 않는다', (tester) async {
    final api = _FailingNativeLoginApi(
      _MemoryAuthSessionStore(null),
      KakaoClientException(ClientErrorCause.cancelled, 'User Cancelled'),
    );
    await tester.pumpWidget(CampOnApp(api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('카카오로 계속하기'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('JWT 발급을 마친 소셜 로그인은 홈 화면으로 이동한다', (tester) async {
    final store = _MemoryAuthSessionStore(null);
    final api = _JwtIssuingApi(store);
    await tester.pumpWidget(CampOnApp(api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Google로 계속하기'));
    await tester.pumpAndSettle();

    expect(api.provider, AuthProvider.google);
    expect(store.session?.accessToken, 'issued-access-token');
    expect(find.text('오늘의 캠핑을\n정리해볼까요?'), findsOneWidget);
  });
}

CampOnApp _appWithEmptySession() {
  return CampOnApp(api: CampOnApi(sessionStore: _MemoryAuthSessionStore(null)));
}

class _MemoryAuthSessionStore implements AuthSessionStore {
  _MemoryAuthSessionStore(this.session);

  AuthSession? session;

  @override
  Future<void> clear() async {
    session = null;
  }

  @override
  Future<AuthSession?> read() async => session;

  @override
  Future<void> write(AuthSession value) async {
    session = value;
  }
}

class _FailingNativeLoginApi extends CampOnApi {
  _FailingNativeLoginApi(_MemoryAuthSessionStore store, this.error)
    : super(sessionStore: store);

  final Object error;

  @override
  Future<void> signInWithNativeProvider({
    required AuthProvider provider,
    required BuildContext context,
  }) async {
    throw error;
  }
}

class _JwtIssuingApi extends CampOnApi {
  _JwtIssuingApi(this.store) : super(sessionStore: store);

  final _MemoryAuthSessionStore store;
  AuthProvider? provider;

  @override
  Future<void> signInWithNativeProvider({
    required AuthProvider provider,
    required BuildContext context,
  }) async {
    this.provider = provider;
    await store.write(
      AuthSession(
        accessToken: 'issued-access-token',
        refreshToken: 'issued-refresh-token',
        tokenType: 'Bearer',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        provider: provider,
      ),
    );
  }
}
