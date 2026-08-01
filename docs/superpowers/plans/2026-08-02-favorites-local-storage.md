# 찜한 캠핑장 로컬 저장 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 하트를 누른 캠핑장을 id가 아닌 정보 전체로 기기에 저장하고, 홈에서 들어가는 "찜한 캠핑장" 목록 화면에서 다시 볼 수 있게 한다.

**Architecture:** `FavoritesStore`의 계약을 `Set<int>`에서 `List<Campsite>`로 바꾸고, `Campsite.toJson()`을 추가해 shared_preferences에 JSON 문자열 목록으로 저장한다. 셸의 즐겨찾기 상태는 `Map<int, Campsite>`가 되어 찜한 순서를 유지한다. 화면은 `FavoritesScreen`을 새로 만들고 홈 카드에서 진입한다.

**Tech Stack:** Flutter (Dart 3.11), shared_preferences, flutter_test. 새 패키지는 추가하지 않는다.

**설계 문서:** `docs/superpowers/specs/2026-08-02-favorites-local-storage-design.md`

## Global Constraints

- 새 pub 패키지를 추가하지 않는다. 저장은 이미 있는 `shared_preferences`만 쓴다.
- shared_preferences 키는 `favorite_campsites`. 예전 키 `favorite_campsite_ids`는 **읽지도 지우지도 않는다.**
- 사용자에게 보이는 문구는 한국어, 코드·커밋 메시지는 영어.
- 기존 코드 스타일을 따른다: 위젯은 `lib/main.dart`에 두고, 주석은 "왜"를 한국어로 적는다.
- 저장 실패는 화면을 막지 않는다(`unawaited` 유지).
- 서버 동기화·계정별 분리·로그아웃 시 삭제는 이번 범위 밖이다.

## 시작 전 기준선

- [ ] `flutter test` 전체를 돌려 **변경 전 통과 상태를 눈으로 확인**한다. 이미 실패하는 테스트가 있으면 그 목록을 적어두고, 이번 작업의 실패와 구분한다.

---

### Task 1: `Campsite.toJson()`

**Files:**
- Modify: `lib/main.dart` (`class Campsite`, 6000행 부근 — `factory Campsite.fromJson` 바로 아래)
- Test: `test/favorites_persistence_test.dart`

**Interfaces:**
- Consumes: 없음
- Produces: `Map<String, dynamic> Campsite.toJson()` — `Campsite.fromJson`이 읽는 키와 정확히 같은 이름으로 값을 담는다. `score`가 `null`이면 `'score'` 키를 넣지 않는다.

- [ ] **Step 1: Write the failing test**

`test/favorites_persistence_test.dart`의 `void main() { ... }` 안, 맨 위에 group을 추가한다.

```dart
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
```

같은 파일 맨 위 import에 `dart:convert`를 추가한다.

```dart
import 'dart:convert';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/favorites_persistence_test.dart`
Expected: 컴파일 실패. `The method 'toJson' isn't defined for the type 'Campsite'`.

- [ ] **Step 3: Write minimal implementation**

`lib/main.dart`의 `factory Campsite.fromJson(...) { ... }` 블록이 끝난 바로 다음 줄에 넣는다(필드 선언 `final int id;` 위).

```dart
  /// 로컬 즐겨찾기 저장용. `fromJson`이 읽는 키와 이름을 정확히 맞춰
  /// 저장한 값을 그대로 되돌릴 수 있게 한다.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'campsiteId': id,
    // fromJson이 containsKey로 판정하므로, 점수가 없으면 키 자체를 넣지 않는다.
    if (score != null) 'score': score,
    'name': name,
    'lineIntro': lineIntro,
    'description': description,
    'lat': lat,
    'lon': lon,
    'distance': distance,
    'zipcode': zipcode,
    'tel': tel,
    'resveUrl': reservationUrl,
    'facility': facility,
    'thumbnailUrl': thumbnailUrl,
    'trailerAccompanyAt': trailerAccompanyAt,
    'caravanAccompanyAt': caravanAccompanyAt,
    'toiletCount': toiletCount,
    'showerRoomCount': showerRoomCount,
    'sinkCount': sinkCount,
    'equipmentRental': equipmentRental,
  };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/favorites_persistence_test.dart`
Expected: PASS. 기존 6개 + 새 3개 = 9개 통과.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart test/favorites_persistence_test.dart
git commit -m "feat: serialize a campsite back to the JSON shape it was parsed from"
```

---

### Task 2: 저장소와 셸 상태를 캠핑장 전체로 전환

**Files:**
- Modify: `lib/campsites/favorites_store.dart` (전체 재작성)
- Modify: `lib/main.dart` — `_favorites` 선언(257행 부근), `_restoreFavorites`(284행 부근), `_addFavorite`(634행 부근), `_toggleFavorite`(642행 부근), `_persistFavorites`(652행 부근), 추천 덱의 `isFavorite`(798행 부근), 상세 화면의 `isFavorite`(810행 부근)
- Test: `test/favorites_persistence_test.dart`

**Interfaces:**
- Consumes: Task 1의 `Campsite.toJson()`
- Produces:
  - `abstract class FavoritesStore { Future<List<Campsite>> read(); Future<void> write(Iterable<Campsite> sites); }`
  - `SharedPrefsFavoritesStore()` — const 생성자 유지, 키는 `favorite_campsites`
  - `InMemoryFavoritesStore([Iterable<Campsite>? initial])`
  - 셸 상태 `final Map<int, Campsite> _favorites`

- [ ] **Step 1: Write the failing test**

`test/favorites_persistence_test.dart`의 기존 `group('SharedPrefsFavoritesStore', ...)` 전체와, 그 아래 위젯 테스트 3개 중 저장소를 직접 보는 부분을 아래로 **교체**한다. Task 1에서 추가한 `Campsite.toJson` group은 그대로 둔다.

```dart
  group('SharedPrefsFavoritesStore', () {
    test('저장한 캠핑장을 정보까지 그대로 돌려준다', () async {
      SharedPreferences.setMockInitialValues({});
      const store = SharedPrefsFavoritesStore();

      await store.write([_site(1, '첫째 캠핑장'), _site(2, '둘째 캠핑장')]);

      final restored = await store.read();
      expect(restored.map((site) => site.id), [1, 2]);
      expect(restored.first.name, '첫째 캠핑장');
      expect(restored.first.thumbnailUrl, 'https://example.com/1.jpg');
    });

    test('저장한 적이 없으면 빈 목록이다', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await const SharedPrefsFavoritesStore().read(), isEmpty);
    });

    test('깨진 값은 버리고 읽을 수 있는 것만 남긴다', () async {
      SharedPreferences.setMockInitialValues({
        'favorite_campsites': [
          '{"campsiteId":1,"name":"살아남는 곳"}',
          'oops',
          '[1,2,3]',
        ],
      });

      final restored = await const SharedPrefsFavoritesStore().read();
      expect(restored.map((site) => site.id), [1]);
      expect(restored.single.name, '살아남는 곳');
    });

    test('예전 id 목록 키는 읽지 않는다', () async {
      SharedPreferences.setMockInitialValues({
        'favorite_campsite_ids': ['1', '2'],
      });

      expect(await const SharedPrefsFavoritesStore().read(), isEmpty);
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

    final saved = await store.read();
    expect(saved.map((site) => site.id), [1]);
    expect(saved.single.name, '테스트 캠핑장');
  });

  testWidgets('다시 누르면 저장소에서도 빠진다', (tester) async {
    final store = InMemoryFavoritesStore([_site(1, '테스트 캠핑장')]);
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
    final store = InMemoryFavoritesStore([_site(1, '테스트 캠핑장')]);
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
```

파일 아래쪽 헬퍼 영역(`Future<void> _skipTutorial` 위)에 캠핑장 생성 헬퍼를 추가한다.

```dart
Campsite _site(int id, String name) => Campsite.fromJson({
  'campsiteId': id,
  'name': name,
  'lat': 37.8,
  'lon': 128.1,
  'thumbnailUrl': 'https://example.com/$id.jpg',
  'facility': <String>[],
  'equipmentRental': <String>[],
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/favorites_persistence_test.dart`
Expected: 컴파일 실패. `InMemoryFavoritesStore`가 `Set<int>`를 받으므로 `The argument type 'List<Campsite>' can't be assigned to the parameter type 'Set<int>'`.

- [ ] **Step 3: Write minimal implementation — 저장소**

`lib/campsites/favorites_store.dart`를 통째로 아래 내용으로 바꾼다.

```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show Campsite;

/// 하트를 누른 캠핑장을 보관한다.
///
/// 서버에 즐겨찾기 API도, 캠핑장 단건 조회 API도 없다. id만 저장하면 목록을
/// 다시 그릴 수 없어서 캠핑장 정보를 통째로 저장한다. 기기 로컬에만 남으므로
/// 다른 기기로 옮기거나 앱을 지웠다 깔면 목록은 비어 있는 상태로 시작한다.
abstract class FavoritesStore {
  Future<List<Campsite>> read();

  Future<void> write(Iterable<Campsite> sites);
}

class SharedPrefsFavoritesStore implements FavoritesStore {
  const SharedPrefsFavoritesStore();

  static const _key = 'favorite_campsites';

  @override
  Future<List<Campsite>> read() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_key);
    if (stored == null) return <Campsite>[];

    // 저장 뒤 형식이 바뀌거나 값이 깨져도 즐겨찾기 때문에 앱이 죽으면 안 된다.
    // 읽을 수 없는 항목은 조용히 버린다.
    final sites = <Campsite>[];
    for (final entry in stored) {
      try {
        final decoded = jsonDecode(entry);
        if (decoded is Map<String, dynamic>) {
          sites.add(Campsite.fromJson(decoded));
        }
      } on FormatException {
        continue;
      }
    }
    return sites;
  }

  @override
  Future<void> write(Iterable<Campsite> sites) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      sites.map((site) => jsonEncode(site.toJson())).toList(growable: false),
    );
  }
}

/// 테스트와 미리보기에서 쓰는 메모리 구현.
class InMemoryFavoritesStore implements FavoritesStore {
  InMemoryFavoritesStore([Iterable<Campsite>? initial])
    : _sites = <Campsite>[...?initial];

  final List<Campsite> _sites;

  @override
  Future<List<Campsite>> read() async => <Campsite>[..._sites];

  @override
  Future<void> write(Iterable<Campsite> sites) async {
    _sites
      ..clear()
      ..addAll(sites);
  }
}
```

- [ ] **Step 4: Write minimal implementation — 셸 상태**

`lib/main.dart`에서 다섯 군데를 바꾼다.

1. 필드 선언(257행 부근):

```dart
  // 하트를 누른 캠핑장. 추천 덱과 상세 화면이 같은 값을 본다.
  // 단건 조회 API가 없어 목록 복원을 위해 캠핑장 정보를 통째로 들고 있는다.
  final Map<int, Campsite> _favorites = <int, Campsite>{};
```

2. `_restoreFavorites`:

```dart
  Future<void> _restoreFavorites() async {
    final stored = await _favoritesStore.read();
    if (!mounted || stored.isEmpty) {
      return;
    }
    setState(() {
      for (final site in stored) {
        _favorites[site.id] = site;
      }
    });
  }
```

3. `_addFavorite` / `_toggleFavorite` / `_persistFavorites`:

```dart
  void _addFavorite(Campsite site) {
    if (_favorites.containsKey(site.id)) {
      return;
    }
    setState(() => _favorites[site.id] = site);
    _persistFavorites();
  }

  void _toggleFavorite(Campsite site) {
    setState(() {
      if (_favorites.remove(site.id) == null) {
        _favorites[site.id] = site;
      }
    });
    _persistFavorites();
  }

  /// 저장 실패가 화면을 막지는 않는다. 다음 토글에서 다시 기록된다.
  void _persistFavorites() {
    unawaited(_favoritesStore.write(_favorites.values));
  }
```

4. 추천 덱(798행 부근): `isFavorite: (site) => _favorites.contains(site.id),`
   → `isFavorite: (site) => _favorites.containsKey(site.id),`

5. 상세 화면(810행 부근):

```dart
          isFavorite:
              _selectedSite != null && _favorites.containsKey(_selectedSite!.id),
```

- [ ] **Step 5: Run tests and analyzer**

Run: `flutter test test/favorites_persistence_test.dart && flutter analyze`
Expected: 테스트 10개 통과, analyzer `No issues found!`.

- [ ] **Step 6: Run the whole suite**

Run: `flutter test`
Expected: 기준선과 같은 결과(새 실패 없음).

- [ ] **Step 7: Commit**

```bash
git add lib/campsites/favorites_store.dart lib/main.dart test/favorites_persistence_test.dart
git commit -m "feat: store favorited campsites in full so the list survives a restart"
```

---

### Task 3: `FavoritesScreen` 위젯

**Files:**
- Modify: `lib/main.dart` — `class CampsiteListScreen` 바로 아래에 `FavoritesScreen` 추가
- Test: `test/favorites_screen_test.dart` (신규)

**Interfaces:**
- Consumes: `Campsite`, `CampsiteCard`, `CampCard`, `CampButton`, `CampText`, `CampColors`, `SettingsIcon`
- Produces: `FavoritesScreen({required List<Campsite> sites, required ValueChanged<Campsite> onSelect, required VoidCallback onStartRecommend})`

- [ ] **Step 1: Write the failing test**

`test/favorites_screen_test.dart`를 새로 만든다.

```dart
import 'package:campon/main.dart';
import 'package:campon/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => CampColors.apply(CampPalette.light));

  testWidgets('찜한 캠핑장을 순서대로 보여준다', (tester) async {
    await tester.pumpWidget(_host(_sites(2)));
    await tester.pumpAndSettle();

    expect(find.text('찜한 캠핑장'), findsOneWidget);
    expect(find.text('캠핑장 1'), findsOneWidget);
    expect(find.text('캠핑장 2'), findsOneWidget);
    expect(find.byType(CampsiteCard), findsNWidgets(2));
  });

  testWidgets('카드를 누르면 상세로 넘긴다', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      _host(_sites(2), onSelect: (site) => opened.add(site.name)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('캠핑장 2'));
    await tester.pumpAndSettle();

    expect(opened, ['캠핑장 2']);
  });

  testWidgets('비어 있으면 안내와 추천 시작 버튼이 나온다', (tester) async {
    var started = 0;
    await tester.pumpWidget(
      _host(const <Campsite>[], onStartRecommend: () => started++),
    );
    await tester.pumpAndSettle();

    expect(find.text('아직 찜한 캠핑장이 없어요'), findsOneWidget);
    expect(find.byType(CampsiteCard), findsNothing);

    await tester.tap(find.text('추천 시작'));
    await tester.pumpAndSettle();

    expect(started, 1);
  });

  testWidgets('찜 목록에서는 점수를 보여주지 않는다', (tester) async {
    await tester.pumpWidget(_host(_sites(1)));
    await tester.pumpAndSettle();

    final card = tester.widget<CampsiteCard>(find.byType(CampsiteCard));
    expect(card.showScore, isFalse);
  });
}

List<Campsite> _sites(int count) => [
  for (var i = 1; i <= count; i++)
    Campsite.fromJson({
      'campsiteId': i,
      'name': '캠핑장 $i',
      'score': 90,
      'lat': 37.8,
      'lon': 128.1,
      'distance': 4000 * i,
      'facility': <String>[],
      'equipmentRental': <String>[],
    }),
];

Widget _host(
  List<Campsite> sites, {
  ValueChanged<Campsite>? onSelect,
  VoidCallback? onStartRecommend,
}) {
  return MaterialApp(
    home: Scaffold(
      body: FavoritesScreen(
        sites: sites,
        onSelect: onSelect ?? (_) {},
        onStartRecommend: onStartRecommend ?? () {},
      ),
    ),
  );
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/favorites_screen_test.dart`
Expected: 컴파일 실패. `Undefined name 'FavoritesScreen'`.

- [ ] **Step 3: Write minimal implementation**

`lib/main.dart`의 `class CampsiteListScreen`이 끝나는 `}` 다음에 추가한다.

```dart
/// 하트를 눌러 저장해 둔 캠핑장 목록. 저장된 값을 그대로 그리므로
/// 네트워크 없이도 보인다.
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({
    required this.sites,
    required this.onSelect,
    required this.onStartRecommend,
    super.key,
  });

  final List<Campsite> sites;
  final ValueChanged<Campsite> onSelect;
  final VoidCallback onStartRecommend;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text('찜한 캠핑장', style: CampText.displaySmall),
        const SizedBox(height: 4),
        Text(
          '하트를 누른 캠핑장은 이 기기에 저장됩니다.',
          style: CampText.body.copyWith(color: CampColors.inkMuted80),
        ),
        const SizedBox(height: 12),
        if (sites.isEmpty)
          CampCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '아직 찜한 캠핑장이 없어요',
                  style: CampText.sectionTitle.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 8),
                Text(
                  '추천 카드나 상세 화면에서 하트를 누르면 여기에 모입니다.',
                  style: CampText.caption.copyWith(
                    color: CampColors.inkMuted80,
                  ),
                ),
                const SizedBox(height: 16),
                CampButton(
                  label: '추천 시작',
                  icon: LucideIcons.sparkles,
                  background: CampColors.forest,
                  onPressed: onStartRecommend,
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < sites.length; i++) ...[
            CampsiteCard(
              site: sites[i],
              // 추천에서 온 캠핑장만 점수가 있어 목록 안에서 들쭉날쭉해진다.
              showScore: false,
              onTap: () => onSelect(sites[i]),
            )
                .animate()
                .fadeIn(duration: 320.ms, delay: (60 * i).ms)
                .slideY(
                  begin: 0.1,
                  end: 0,
                  duration: 320.ms,
                  delay: (60 * i).ms,
                  curve: Curves.easeOutCubic,
                ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/favorites_screen_test.dart && flutter analyze`
Expected: 테스트 4개 통과, analyzer `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart test/favorites_screen_test.dart
git commit -m "feat: add a screen that lists favorited campsites"
```

---

### Task 4: 홈 카드와 화면 연결

**Files:**
- Modify: `lib/main.dart` — `enum AppStep`(208행 부근), `enum DetailEntry`(225행 부근), `_showTabs`(309행 부근), `_back`(427행 부근), `_buildStep`의 `case AppStep.home:`(735행 부근), `CampTabBar`(4643행 부근), `HomeScreen`(1382행 부근)
- Test: `test/favorites_flow_test.dart` (신규)

**Interfaces:**
- Consumes: Task 3의 `FavoritesScreen`, Task 2의 `Map<int, Campsite> _favorites`
- Produces: `AppStep.favorites`, `DetailEntry.favorites`, `HomeScreen`의 새 인자 `favoriteCount`(`int`)와 `onFavorites`(`VoidCallback`), 셸 메서드 `_goFavorites()`

- [ ] **Step 1: Write the failing test**

`test/favorites_flow_test.dart`를 새로 만든다.

```dart
import 'package:campon/campsites/favorites_store.dart';
import 'package:campon/main.dart';
import 'package:campon/theme.dart';
import 'package:flutter/material.dart';
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/favorites_flow_test.dart`
Expected: FAIL. `찜 목록 보기` 텍스트가 없어 `scrollUntilVisible`이 목록 끝까지 훑고 실패한다.

- [ ] **Step 3: Add the enum values and navigation**

`lib/main.dart`에서:

1. `enum AppStep`에 `favorites`를 추가한다(`browse` 다음 줄).

```dart
  browse,
  favorites,
```

2. `enum DetailEntry`:

```dart
enum DetailEntry { recommendations, browse, favorites }
```

3. `_showTabs` 집합에 `AppStep.favorites`를 추가한다.

```dart
  bool get _showTabs => const {
    AppStep.home,
    AppStep.browse,
    AppStep.favorites,
    AppStep.recommendations,
    AppStep.checklist,
    AppStep.settings,
  }.contains(_step);
```

4. `_goHome` 아래에 이동 메서드를 추가한다.

```dart
  void _goFavorites() {
    setState(() => _step = AppStep.favorites);
  }
```

5. `_back`의 `case AppStep.details:` 분기를 찜 목록까지 다루도록 바꾼다.

```dart
        case AppStep.details:
          _step = switch (_detailEntry) {
            DetailEntry.browse => AppStep.browse,
            DetailEntry.favorites => AppStep.favorites,
            DetailEntry.recommendations => AppStep.recommendations,
          };
```

그리고 같은 `switch`의 홈 복귀 묶음에 `case AppStep.favorites:`를 추가한다(`case AppStep.browse:` 옆).

```dart
        case AppStep.browse:
        case AppStep.favorites:
```

- [ ] **Step 4: Wire the screen and the home card**

1. `_buildStep`의 `case AppStep.browse:` 앞에 분기를 추가한다.

```dart
      case AppStep.favorites:
        return FavoritesScreen(
          sites: _favorites.values.toList(growable: false),
          onSelect: (site) => _selectSite(site, DetailEntry.favorites),
          onStartRecommend: _startOnboarding,
        );
```

2. `case AppStep.home:`의 `HomeScreen(...)` 호출에 두 인자를 넘긴다.

```dart
        return HomeScreen(
          onStart: _startOnboarding,
          onBrowse: _goBrowse,
          onPlanner: _goPlanner,
          onFavorites: _goFavorites,
          favoriteCount: _favorites.length,
          tonightCard: TonightCard(
```

(나머지 `tonightCard` 인자는 그대로 둔다.)

3. `HomeScreen`에 인자를 추가한다.

```dart
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.onStart,
    required this.onBrowse,
    required this.onPlanner,
    required this.onFavorites,
    required this.favoriteCount,
    required this.tonightCard,
    super.key,
  });

  final VoidCallback onStart;
  final VoidCallback onBrowse;
  final VoidCallback onPlanner;
  final VoidCallback onFavorites;
  final int favoriteCount;
```

4. `HomeScreen`의 `ListView` 마지막 카드('캠핑장 둘러보기') 뒤에 찜 카드를 추가한다. 기존 마지막 `CampCard(...)` 를 닫는 `),` 다음에 넣는다.

```dart
        const SizedBox(height: 14),
        CampCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SettingsIcon(icon: LucideIcons.heart, size: 40),
                  const SizedBox(width: 12),
                  Text(
                    '찜한 캠핑장',
                    style: CampText.sectionTitle.copyWith(fontSize: 19),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                favoriteCount == 0
                    ? '마음에 드는 캠핑장에 하트를 눌러보세요.'
                    : '$favoriteCount곳을 이 기기에 저장해 두었어요.',
                style: CampText.caption.copyWith(color: CampColors.inkMuted80),
              ),
              const SizedBox(height: 16),
              CampButton.secondary(
                label: '찜 목록 보기',
                foreground: CampColors.forest,
                borderColor: CampColors.forest,
                onPressed: onFavorites,
              ),
            ],
          ),
        ),
```

5. `CampTabBar`의 '홈' 항목이 찜 화면에서도 선택으로 보이게 한다.

```dart
            TabItem(
              icon: LucideIcons.home,
              label: '홈',
              selected:
                  currentStep == AppStep.home ||
                  currentStep == AppStep.favorites,
              onTap: onHome,
            ),
```

- [ ] **Step 5: Run the new tests**

Run: `flutter test test/favorites_flow_test.dart`
Expected: 4개 통과.

- [ ] **Step 6: Run the analyzer and the whole suite**

Run: `flutter analyze && flutter test`
Expected: analyzer `No issues found!`, 전체 테스트가 기준선 대비 새 실패 없이 통과.

`HomeScreen`에 필수 인자를 추가했으므로 다른 테스트가 `HomeScreen`을 직접 만들고 있으면 컴파일이 깨진다. 깨지면 그 테스트에도 `onFavorites: () {}, favoriteCount: 0,`을 넣어 고친다.

- [ ] **Step 7: Commit**

```bash
git add lib/main.dart test/favorites_flow_test.dart
git commit -m "feat: open the favorites list from a home card"
```

---

### Task 5: 문서 갱신

**Files:**
- Modify: `DEVELOPMENT_NOTES.md`

- [ ] **Step 1: 구현 결정에 한 줄 추가**

`## 구현 결정` 목록 끝에 추가한다.

```markdown
- 즐겨찾기는 서버 API가 없어 기기 로컬(shared_preferences 키 `favorite_campsites`)에만 저장합니다. 캠핑장 단건 조회 API도 없어 id가 아니라 캠핑장 정보 전체를 JSON으로 저장하고, 홈의 "찜한 캠핑장" 카드에서 목록을 봅니다.
```

- [ ] **Step 2: Commit**

```bash
git add DEVELOPMENT_NOTES.md
git commit -m "docs: record how favorites are stored locally"
```
