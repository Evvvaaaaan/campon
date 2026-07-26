import 'package:campon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home CTA routes into the planner with prefilled context',
      (tester) async {
    final store = _MemoryAuthSessionStore(
      AuthSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        tokenType: 'Bearer',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        provider: AuthProvider.google,
      ),
    );
    final api = _NearbyStubApi(store);

    await tester.pumpWidget(CampOnApp(api: api));
    await tester.pumpAndSettle();

    // Lands on home with the AI planner hero CTA.
    expect(find.text('AI로 캠핑 플랜 짜기'), findsOneWidget);

    await tester.tap(find.text('AI로 캠핑 플랜 짜기'));
    await tester.pumpAndSettle();

    // Planner input screen shows with prefilled context chips.
    expect(find.text('AI 플래너'), findsOneWidget);
    expect(find.text('플랜 생성'), findsOneWidget);
    expect(find.text('강원'), findsOneWidget); // default region
    expect(api.nearbyCalls, greaterThanOrEqualTo(1));
  });
}

class _NearbyStubApi extends CampOnApi {
  _NearbyStubApi(this.store) : super(sessionStore: store);

  final _MemoryAuthSessionStore store;
  int nearbyCalls = 0;

  @override
  Future<List<Campsite>> fetchNearby({
    required CampRegion region,
    required int page,
    required int size,
  }) async {
    nearbyCalls++;
    return [
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
