import 'package:campon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('보유 장비는 체크리스트에 미리 체크되고, 해제하면 부족한 장비로 돌아온다', (tester) async {
    await tester.pumpWidget(CampOnApp(api: _StubApi()));
    await tester.pumpAndSettle();

    // 온보딩: 날짜 → 이동수단/숙련도 → 보유 장비(텐트)
    // 홈 상단에 "오늘 밤" 카드가 있어 추천 카드는 스크롤해야 보인다.
    await tester.dragUntilVisible(
      find.text('추천 시작'),
      find.byType(ListView),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('추천 시작'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('날짜를 선택해주세요'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('차량 있음'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('초보'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('텐트'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('캠핑장 추천받기'));
    await tester.pumpAndSettle();

    // 체크리스트 탭으로 이동하면 보유 장비가 이미 체크되어 있다.
    await tester.tap(find.text('체크리스트'));
    await tester.pumpAndSettle();

    expect(find.text('준비 체크리스트'), findsOneWidget);
    expect(find.textContaining('텐트가 없으면'), findsNothing);

    // 체크리스트에서 텐트를 해제하면 부족한 장비로 다시 올라온다.
    await tester.scrollUntilVisible(
      find.text('텐트'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('텐트'));
    await tester.pumpAndSettle();

    expect(find.textContaining('텐트가 없으면'), findsOneWidget);
  });
}

class _StubApi extends CampOnApi {
  _StubApi() : super(sessionStore: _MemoryAuthSessionStore());

  @override
  Future<bool> restoreSession() async => true;

  @override
  Future<List<Campsite>> fetchRecommendations({
    required CampRegion region,
    required DateTime date,
    required int people,
    required bool hasCar,
    required List<String> equipment,
    required List<String> preferences,
    required int page,
    required int size,
  }) async => const <Campsite>[];
}

class _MemoryAuthSessionStore implements AuthSessionStore {
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
