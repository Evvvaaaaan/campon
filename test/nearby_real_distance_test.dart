import 'package:campon/location/location_service.dart';
import 'package:campon/main.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLocationProvider implements LocationProvider {
  _FakeLocationProvider(this._point);

  final LocationPoint _point;

  @override
  Future<LocationPoint> current() async => _point;

  @override
  Future<void> openSettings(LocationBlockReason reason) async {}
}

class _BlockedLocationProvider implements LocationProvider {
  LocationBlockReason? openedFor;

  @override
  Future<LocationPoint> current() async => throw const LocationBlockedException(
    LocationBlockReason.deniedForever,
    '설정에서 위치 권한을 허용해주세요.',
  );

  @override
  Future<void> openSettings(LocationBlockReason reason) async {
    openedFor = reason;
  }
}

class _StubApi extends CampOnApi {
  _StubApi() : super(sessionStore: _MemoryStore());

  // 서버는 조회 좌표 중심 기준의 거리를 준다. 실제 사용자 위치와는 무관한 값.
  @override
  Future<List<Campsite>> fetchAllNearbyAt({
    required double lat,
    required double lon,
  }) async => [_site(1, '동해 캠핑장', lat: 37.5665, lon: 129.1000, distance: 999000)];
}

Campsite _site(
  int id,
  String name, {
  required double lat,
  required double lon,
  required int distance,
}) => Campsite.fromJson({
  'campsiteId': id,
  'name': name,
  'lat': lat,
  'lon': lon,
  'distance': distance,
  'facility': <String>[],
  'equipmentRental': <String>[],
});

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
  Future<void> write(AuthSession session) async => _session = session;
}

Future<void> _skipTutorialAndGoBrowse(WidgetTester tester) async {
  await tester.pumpWidget(
    CampOnApp(
      api: _StubApi(),
      location: _FakeLocationProvider(
        // 서울(도심)에서 출발 — 동해 캠핑장까지의 실제 직선거리는 999km가 아니라
        // 대략 160km대다.
        const LocationPoint(lat: 37.5665, lon: 126.9780),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('건너뛰기'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('캠핑장'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('주변 캠핑장 거리는 서버 값이 아니라 실제 사용자 위치 기준으로 바뀐다', (
    tester,
  ) async {
    await _skipTutorialAndGoBrowse(tester);

    expect(find.text('999km'), findsNothing);
    expect(find.textContaining('km'), findsWidgets);
  });

  testWidgets('위치를 못 얻으면 추천 지역 기준 목록 대신 위치 권한 안내를 보여준다', (
    tester,
  ) async {
    await tester.pumpWidget(
      CampOnApp(api: _StubApi(), location: _BlockedLocationProvider()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('캠핑장'));
    await tester.pumpAndSettle();

    expect(find.text('동해 캠핑장'), findsNothing);
    expect(find.text('현재 위치를 사용할 수 없어요.'), findsOneWidget);
  });
}
