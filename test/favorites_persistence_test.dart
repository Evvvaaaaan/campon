import 'dart:convert';

import 'package:campon/campsites/favorites_store.dart';
import 'package:campon/main.dart';
import 'package:campon/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() => CampColors.apply(CampPalette.light));

  group('Campsite.toJson', () {
    test('fromJson으로 되돌리면 모든 값이 그대로다', () {
      final site = Campsite.fromJson({
        'campsiteId': 7,
        'score': 88,
        'name': '별빛 캠핑장',
        'lineIntro': '한 줄 소개',
        'description': '자세한 설명',
        'lat': 37.5,
        'lon': 127.1,
        'distance': 4200,
        'zipcode': '12345',
        'tel': '02-000-0000',
        'resveUrl': 'https://example.com/reserve',
        'facility': ['SHOWER', 'WIFI'],
        'thumbnailUrl': 'https://example.com/a.jpg',
        'trailerAccompanyAt': true,
        'caravanAccompanyAt': false,
        'toiletCount': 3,
        'showerRoomCount': 2,
        'sinkCount': 1,
        'equipmentRental': ['TENT'],
      });

      final restored = Campsite.fromJson(site.toJson());

      expect(restored.id, 7);
      expect(restored.score, 88);
      expect(restored.name, '별빛 캠핑장');
      expect(restored.lineIntro, '한 줄 소개');
      expect(restored.description, '자세한 설명');
      expect(restored.lat, 37.5);
      expect(restored.lon, 127.1);
      expect(restored.distance, 4200);
      expect(restored.zipcode, '12345');
      expect(restored.tel, '02-000-0000');
      expect(restored.reservationUrl, 'https://example.com/reserve');
      expect(restored.facility, ['SHOWER', 'WIFI']);
      expect(restored.thumbnailUrl, 'https://example.com/a.jpg');
      expect(restored.trailerAccompanyAt, isTrue);
      expect(restored.caravanAccompanyAt, isFalse);
      expect(restored.toiletCount, 3);
      expect(restored.showerRoomCount, 2);
      expect(restored.sinkCount, 1);
      expect(restored.equipmentRental, ['TENT']);
    });

    test('점수가 없으면 왕복 후에도 null이다', () {
      final site = Campsite.fromJson({
        'campsiteId': 1,
        'name': '점수 없는 곳',
        'facility': <String>[],
        'equipmentRental': <String>[],
      });

      expect(site.score, isNull);
      expect(site.toJson().containsKey('score'), isFalse);
      expect(Campsite.fromJson(site.toJson()).score, isNull);
    });

    test('jsonEncode를 거쳐도 값이 유지된다', () {
      final site = Campsite.fromJson({
        'campsiteId': 2,
        'name': '인코딩 테스트',
        'lat': 37.1,
        'lon': 128.2,
        'facility': ['TOILET'],
        'equipmentRental': <String>[],
      });

      final decoded = jsonDecode(jsonEncode(site.toJson()));
      final restored = Campsite.fromJson(decoded as Map<String, dynamic>);

      expect(restored.name, '인코딩 테스트');
      expect(restored.lat, 37.1);
      expect(restored.facility, ['TOILET']);
    });
  });

  group('SharedPrefsFavoritesStore', () {
    test('저장한 id를 그대로 돌려준다', () async {
      SharedPreferences.setMockInitialValues({});
      const store = SharedPrefsFavoritesStore();

      await store.write({3, 1, 2});

      expect(await store.read(), {1, 2, 3});
    });

    test('저장한 적이 없으면 빈 집합이다', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await const SharedPrefsFavoritesStore().read(), isEmpty);
    });

    test('깨진 값은 버리고 읽을 수 있는 것만 남긴다', () async {
      SharedPreferences.setMockInitialValues({
        'favorite_campsite_ids': ['1', 'oops', '2'],
      });
      expect(await const SharedPrefsFavoritesStore().read(), {1, 2});
    });
  });

  testWidgets('상세에서 하트를 누르면 로컬 저장소에 기록된다', (tester) async {
    final store = InMemoryFavoritesStore();
    await tester.pumpWidget(
      CampOnApp(api: _StubApi(), favoritesStore: store),
    );
    await tester.pumpAndSettle();
    await _skipTutorial(tester);

    await _openFirstCampsite(tester);

    expect(await store.read(), isEmpty);

    await tester.tap(find.byType(FavoriteHeartButton));
    await tester.pumpAndSettle();

    expect(await store.read(), {1});
  });

  testWidgets('다시 누르면 저장소에서도 빠진다', (tester) async {
    final store = InMemoryFavoritesStore({1});
    await tester.pumpWidget(
      CampOnApp(api: _StubApi(), favoritesStore: store),
    );
    await tester.pumpAndSettle();
    await _skipTutorial(tester);

    await _openFirstCampsite(tester);

    await tester.tap(find.byType(FavoriteHeartButton));
    await tester.pumpAndSettle();

    expect(await store.read(), isEmpty);
  });

  testWidgets('앱을 다시 켜면 저장된 즐겨찾기가 복원된다', (tester) async {
    final store = InMemoryFavoritesStore({1});
    await tester.pumpWidget(
      CampOnApp(api: _StubApi(), favoritesStore: store),
    );
    await tester.pumpAndSettle();
    await _skipTutorial(tester);

    await _openFirstCampsite(tester);

    // 시작할 때 읽어 온 값이라 하트가 이미 켜져 있어야 한다.
    final heart = tester.widget<FavoriteHeartButton>(
      find.byType(FavoriteHeartButton),
    );
    expect(heart.isFavorite, isTrue);
  });
}

Future<void> _skipTutorial(WidgetTester tester) async {
  await tester.tap(find.text('건너뛰기'));
  await tester.pumpAndSettle();
}

Future<void> _openFirstCampsite(WidgetTester tester) async {
  await tester.tap(find.text('캠핑장'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('테스트 캠핑장').first);
  await tester.pumpAndSettle();
}

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
