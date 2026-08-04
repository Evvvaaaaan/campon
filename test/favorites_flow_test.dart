import 'package:campon/campsites/favorites_store.dart';
import 'package:campon/main.dart';
import 'package:campon/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => CampColors.apply(CampPalette.light));

  testWidgets('홈 카드로 찜 목록에 들어간다', (tester) async {
    await tester.pumpWidget(
      CampOnApp(
        api: _StubApi(),
        favoritesStore: InMemoryFavoritesStore([_site(1, '저장된 캠핑장')]),
      ),
    );
    await tester.pumpAndSettle();
    await _skipTutorial(tester);

    await tester.scrollUntilVisible(find.text('1곳을 이 기기에 저장해 두었어요.'), 300);
    expect(find.text('1곳을 이 기기에 저장해 두었어요.'), findsOneWidget);

    await _openFavorites(tester);

    expect(find.text('찜한 캠핑장'), findsOneWidget);
    expect(find.text('저장된 캠핑장'), findsOneWidget);
  });

  testWidgets('네트워크 응답 없이도 저장된 목록이 보인다', (tester) async {
    await tester.pumpWidget(
      CampOnApp(
        api: _FailingApi(),
        favoritesStore: InMemoryFavoritesStore([_site(1, '오프라인 캠핑장')]),
      ),
    );
    await tester.pumpAndSettle();
    await _skipTutorial(tester);

    await _openFavorites(tester);

    expect(find.text('오프라인 캠핑장'), findsOneWidget);
  });

  testWidgets('찜이 없으면 빈 상태를 보여준다', (tester) async {
    await tester.pumpWidget(
      CampOnApp(api: _StubApi(), favoritesStore: InMemoryFavoritesStore()),
    );
    await tester.pumpAndSettle();
    await _skipTutorial(tester);

    await tester.scrollUntilVisible(find.text('마음에 드는 캠핑장에 하트를 눌러보세요.'), 300);
    expect(find.text('마음에 드는 캠핑장에 하트를 눌러보세요.'), findsOneWidget);

    await _openFavorites(tester);

    expect(find.text('아직 찜한 캠핑장이 없어요'), findsOneWidget);
  });

  testWidgets('상세에서 하트를 해제하면 목록에서 사라진다', (tester) async {
    final store = InMemoryFavoritesStore([_site(1, '저장된 캠핑장')]);
    await tester.pumpWidget(
      CampOnApp(api: _StubApi(), favoritesStore: store),
    );
    await tester.pumpAndSettle();
    await _skipTutorial(tester);

    await _openFavorites(tester);
    await tester.tap(find.text('저장된 캠핑장'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FavoriteHeartButton));
    await tester.pumpAndSettle();

    // 뒤로 가면 찜 목록으로 돌아오고, 해제한 캠핑장은 빠져 있어야 한다.
    // 이 앱은 Navigator가 아니라 _step으로 화면을 바꾸므로 pageBack()이 아니라
    // 상세 화면의 뒤로 버튼을 직접 누른다.
    await tester.tap(find.byType(BackCircleButton));
    await tester.pumpAndSettle();

    expect(find.text('아직 찜한 캠핑장이 없어요'), findsOneWidget);
    expect(await store.read(), isEmpty);
  });
}

Future<void> _skipTutorial(WidgetTester tester) async {
  await tester.tap(find.text('건너뛰기'));
  await tester.pumpAndSettle();
}

Future<void> _openFavorites(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('찜 목록 보기'), 300);
  await tester.tap(find.text('찜 목록 보기'));
  await tester.pumpAndSettle();
}

Campsite _site(int id, String name) => Campsite.fromJson({
  'campsiteId': id,
  'name': name,
  'lat': 37.8,
  'lon': 128.1,
  'facility': <String>[],
  'equipmentRental': <String>[],
});

class _StubApi extends CampOnApi {
  _StubApi() : super(sessionStore: _MemoryStore());

  @override
  Future<List<Campsite>> fetchNearby({
    required CampRegion region,
    required int page,
    required int size,
  }) async => [_site(1, '저장된 캠핑장')];

  @override
  Future<List<Campsite>> fetchAllNearby({required CampRegion region}) async =>
      [_site(1, '저장된 캠핑장')];
}

class _FailingApi extends CampOnApi {
  _FailingApi() : super(sessionStore: _MemoryStore());

  @override
  Future<List<Campsite>> fetchNearby({
    required CampRegion region,
    required int page,
    required int size,
  }) async => throw const CampOnApiException('네트워크 없음');

  @override
  Future<List<Campsite>> fetchAllNearby({required CampRegion region}) async =>
      throw const CampOnApiException('네트워크 없음');
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
