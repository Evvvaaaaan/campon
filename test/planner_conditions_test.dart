import 'package:campon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 플래너 입력 화면까지 들어간다. 그 시점의 후보 조회 횟수는 1이다.
Future<_NearbyStubApi> _openPlanner(WidgetTester tester) async {
  final api = _NearbyStubApi(
    _MemoryAuthSessionStore(
      AuthSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        tokenType: 'Bearer',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        provider: AuthProvider.google,
      ),
    ),
  );

  await tester.pumpWidget(CampOnApp(api: api));
  await tester.pumpAndSettle();
  await tester.tap(find.text('캠핑 계획 만들기'));
  await tester.pumpAndSettle();

  expect(find.text('AI 플래너'), findsOneWidget);
  return api;
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('조건 수정'));
  await tester.pumpAndSettle();
  expect(find.text('이 조건으로 저장'), findsOneWidget);
}

/// 시트 본문은 스크롤되고 아래쪽 항목은 아직 만들어지지도 않았다.
/// 그래서 찾기 전에 시트 목록을 직접 굴려야 한다.
Future<void> _tapInSheet(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find.descendant(
      of: find.byType(PlanConditionSheet),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('조건 수정 시트에서 바꾼 인원이 칩에 반영된다', (tester) async {
    await _openPlanner(tester);
    expect(find.text('2명'), findsOneWidget);

    await _openSheet(tester);
    await _tapInSheet(tester, find.byTooltip('인원 늘리기'));
    await tester.tap(find.text('이 조건으로 저장'));
    await tester.pumpAndSettle();

    expect(find.text('3명'), findsOneWidget);
    expect(find.text('2명'), findsNothing);
  });

  testWidgets('저장하지 않고 닫으면 조건이 그대로다', (tester) async {
    await _openPlanner(tester);

    await _openSheet(tester);
    await _tapInSheet(tester, find.byTooltip('인원 늘리기'));
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();

    expect(find.text('2명'), findsOneWidget);
    expect(find.text('3명'), findsNothing);
  });

  testWidgets('지역을 바꾸면 그 지역 후보를 다시 받아온다', (tester) async {
    final api = await _openPlanner(tester);
    expect(api.nearbyCalls, 1);
    expect(api.lastRegion, '강원');

    await _openSheet(tester);
    await _tapInSheet(tester, find.text('경기'));
    await tester.tap(find.text('이 조건으로 저장'));
    await tester.pumpAndSettle();

    // 이전 지역 캠핑장이 플랜에 남지 않도록 새 지역으로 다시 조회한다.
    expect(api.nearbyCalls, 2);
    expect(api.lastRegion, '경기');
    expect(find.text('경기'), findsOneWidget);
  });

  testWidgets('차량과 숙련도도 시트에서 바꿀 수 있다', (tester) async {
    await _openPlanner(tester);
    expect(find.text('차량 있음'), findsOneWidget);

    await _openSheet(tester);
    await _tapInSheet(tester, find.text('차량 없음'));
    await _tapInSheet(tester, find.text('고급'));
    await tester.tap(find.text('이 조건으로 저장'));
    await tester.pumpAndSettle();

    expect(find.text('차량 없음'), findsOneWidget);
    expect(find.text('고급'), findsOneWidget);
  });
}

class _NearbyStubApi extends CampOnApi {
  _NearbyStubApi(this.store) : super(sessionStore: store);

  final _MemoryAuthSessionStore store;
  int nearbyCalls = 0;
  String? lastRegion;

  @override
  Future<List<Campsite>> fetchNearby({
    required CampRegion region,
    required int page,
    required int size,
  }) async {
    nearbyCalls++;
    lastRegion = region.name;
    return [
      Campsite.fromJson({
        'campsiteId': 1,
        'name': '${region.name} 테스트 캠핑장',
        'lat': region.lat,
        'lon': region.lon,
        'facility': ['ELECTRICITY'],
        'equipmentRental': <String>[],
      }),
    ];
  }
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
