# CampOn — 찜한 캠핑장 로컬 저장과 목록 화면 설계

날짜: 2026-08-02
목적: 하트를 누른 캠핑장을 id만이 아니라 캠핑장 정보 전체로 기기에 저장하고, 저장된 목록을
"찜한 캠핑장" 화면에서 다시 볼 수 있게 한다.

## 1. 배경 / 현재 상태

- 하트 저장 자체는 이미 동작한다. `lib/campsites/favorites_store.dart`의
  `SharedPrefsFavoritesStore`가 shared_preferences 키 `favorite_campsite_ids`에
  **캠핑장 id 문자열 목록**을 저장하고, 셸이 `initState`에서 복원한다
  (`_restoreFavorites`, `lib/main.dart:284`). 토글은 `_addFavorite`(`lib/main.dart:634`),
  `_toggleFavorite`(`lib/main.dart:642`), 저장은 `_persistFavorites`(`lib/main.dart:652`)다.
  `test/favorites_persistence_test.dart`의 6개 테스트가 통과한다(2026-08-02 확인).
- 저장된 id는 하트 아이콘의 on/off 표시에만 쓰인다. 찜한 목록을 보여주는 화면은 없다.
- **id만으로는 목록을 복원할 수 없다.** 스웨거(`https://campon.seohamin.com/api/swagger-ui/v3/api-docs`,
  2026-08-01 확인)에 캠핑장 단건 조회 API가 없다. 캠핑장 관련 엔드포인트는
  `GET /api/v1/campsites/nearby`, `GET /api/v1/campsites/recommend`,
  `POST /api/v1/campsites/recommend/ai` 세 개뿐이며 모두 좌표+반경 기준이다.
  따라서 찜한 곳이 현재 조회 반경 밖이면 id로 되살릴 방법이 없다.
- 즐겨찾기 서버 API도 없다. 저장은 기기 로컬 전용이고, 기기를 옮기거나 앱을 지우면 사라진다
  (`favorites_store.dart` 주석에 이미 명시).
- 하단 탭바(`CampTabBar`, `lib/main.dart:4643`)는 홈/캠핑장/추천/체크리스트/설정 5개로 차 있다.
- 홈 화면(`HomeScreen`, `lib/main.dart:1382`)은 카드를 세로로 쌓은 `ListView`이고,
  '맞춤 추천'·'캠핑장 둘러보기' 카드가 같은 형식(`CampCard` + 아이콘 + 설명 + 버튼)으로 있다.

## 2. 결정 사항

| 항목 | 결정 | 이유 |
|---|---|---|
| 저장 내용 | id가 아닌 `Campsite` 전체를 JSON으로 저장 | 단건 조회 API가 없어 id만으로는 목록 복원이 불가능 |
| 저장 위치 | shared_preferences 새 키 `favorite_campsites` | 기존 저장 방식과 동일한 의존성, 추가 패키지 불필요 |
| 예전 키(`favorite_campsite_ids`) | 읽지 않고 무시 | 아직 커밋·출시 전 기능이라 실사용자 데이터가 없음. 두 형식을 동시에 다루는 코드를 만들지 않는다 |
| 셸 상태 | `Set<int>` → `Map<int, Campsite>` | 하트 판정은 `containsKey`로 그대로, 삽입 순서가 유지돼 찜한 순서대로 목록에 나옴 |
| 진입점 | 홈 화면에 "찜한 캠핑장" 카드 추가 | 탭 6개는 좁은 화면에서 라벨이 붙음. 기존 홈 카드 패턴과 일치 |
| 목록 화면 | `FavoritesScreen` 신규, `CampsiteCard` 재사용 | `CampsiteListScreen`은 `Future` 기반이라 이미 메모리에 있는 목록에 맞지 않음 |
| 저장 실패 처리 | 지금처럼 `unawaited`로 조용히 진행 | 즐겨찾기 저장 실패가 화면을 막을 이유가 없음. 기존 동작 유지 |

## 3. 구성 요소

### 3.1 `Campsite.toJson()` — 신규 (`lib/main.dart:5966`)

`Campsite.fromJson`(`lib/main.dart:5989`)과 정확히 대칭인 맵을 만든다. 서버 응답 필드명을
그대로 쓰기 때문에 저장한 JSON을 그대로 `fromJson`에 되돌릴 수 있다.

```dart
Map<String, dynamic> toJson() => <String, dynamic>{
      'campsiteId': id,
      if (score != null) 'score': score,
      'name': name,
      'lineIntro': lineIntro,
      // … fromJson이 읽는 모든 키를 같은 이름으로
      'resveUrl': reservationUrl,
    };
```

`score`는 추천 응답에만 있어 `null`일 수 있다. `fromJson`이 `containsKey('score')`로 판정하므로,
`null`일 때는 키 자체를 넣지 않아 왕복 후에도 `null`로 남게 한다.

### 3.2 `FavoritesStore` — 계약 변경 (`lib/campsites/favorites_store.dart`)

```dart
abstract class FavoritesStore {
  Future<List<Campsite>> read();
  Future<void> write(Iterable<Campsite> sites);
}
```

`SharedPrefsFavoritesStore`는 키를 `favorite_campsites`로 바꾸고, 각 항목을
`jsonEncode(site.toJson())` 문자열로 저장한다. 읽을 때는 항목별로 디코딩하며,
**깨졌거나 형식이 다른 항목은 지금처럼 조용히 버린다**(잘못된 JSON, 맵이 아닌 값 모두 해당).
`InMemoryFavoritesStore`도 같은 계약으로 맞춘다.

`Campsite`가 `lib/main.dart`에 있어 이 파일이 `main.dart`를 import하게 된다. 이미
`main.dart`가 `favorites_store.dart`를 import하고 있으므로 순환 참조가 되지만, Dart는
순환 import를 허용하고 프로젝트의 다른 파일(`lib/campsites/campsite_map_view.dart` 등)도
같은 형태를 쓰고 있어 기존 구조를 따른다.

### 3.3 셸 상태 (`lib/main.dart`)

- `final Set<int> _favorites` → `final Map<int, Campsite> _favorites`
- `_restoreFavorites`: 읽어온 목록을 `{for (final s in stored) s.id: s}`로 넣는다.
- `_addFavorite` / `_toggleFavorite`: `add`/`remove` → `putIfAbsent`/`remove`.
  하트 판정부(`isFavorite`)는 `_favorites.containsKey(site.id)`로 바꾼다.
- `_persistFavorites`: `_favoritesStore.write(_favorites.values)`.

### 3.4 `FavoritesScreen` — 신규 (`lib/main.dart`)

```dart
class FavoritesScreen extends StatelessWidget {
  final List<Campsite> sites;
  final ValueChanged<Campsite> onSelect;
  final VoidCallback onStartRecommend;  // 빈 상태 버튼
}
```

`CampsiteListScreen`과 같은 헤더(제목 + 설명) 뒤에 `CampsiteCard`(`lib/main.dart:4365`)를
쌓는다. `showScore`는 `false`로 고정한다 — 저장된 캠핑장 중 추천에서 온 것만 점수가 있어
목록 안에서 표시가 들쭉날쭉해지기 때문이다.

비어 있으면 "아직 찜한 캠핑장이 없어요" 안내와 '추천 시작' 버튼을 보여준다.
기존 `EmptyPanel`(`lib/main.dart:4805`)은 재시도 콜백을 받는 형태라 여기서는 쓰지 않고
카드 하나로 직접 그린다.

### 3.5 화면 연결

- `AppStep`에 `favorites` 추가. `_buildBody`의 `switch`에 분기를 넣고,
  뒤로가기(`lib/main.dart:448` 부근의 `case AppStep.browse:` 패턴)와 같은 방식으로 홈 복귀를 처리한다.
- `DetailEntry`(`lib/main.dart:225`)에 `favorites` 추가. `DetailEntry`는 상세에서 뒤로 갈 때
  어느 화면으로 돌아갈지만 정한다(`lib/main.dart:435`의 분기). 여기에 찜 목록 분기를 추가해
  찜 목록에서 연 상세는 찜 목록으로 돌아오게 한다.
- `HomeScreen`에 `onFavorites` 콜백과 찜 개수(`favoriteCount`)를 넘겨 "찜한 캠핑장" 카드를
  '캠핑장 둘러보기' 카드 아래에 추가한다. 개수가 0이면 카드는 그대로 두되 설명 문구만
  "마음에 드는 캠핑장에 하트를 눌러보세요"로 바꾼다.
- 하단 탭바는 변경하지 않는다. 찜 화면에서는 '홈' 탭이 선택된 상태로 둔다.

## 4. 데이터 흐름

1. 추천 덱이나 상세에서 하트를 누른다 → `_addFavorite`/`_toggleFavorite`가
   `_favorites`(메모리)를 갱신하고 `_persistFavorites`가 전체를 shared_preferences에 다시 쓴다.
2. 앱을 다시 켠다 → `initState`의 `_restoreFavorites`가 저장된 JSON을 `Campsite`로 복원한다.
   네트워크가 없어도 목록이 그대로 나온다.
3. 홈의 "찜한 캠핑장" 카드 → `FavoritesScreen`이 `_favorites.values`를 그린다.
4. 목록에서 캠핑장을 누르면 상세로 가고, 거기서 하트를 해제하면 `_favorites`에서 빠져
   뒤로 갔을 때 목록에서도 사라진다.

## 5. 오류 처리

| 상황 | 동작 |
|---|---|
| 저장된 JSON이 깨짐 | 해당 항목만 버리고 나머지는 복원 |
| shared_preferences 읽기 실패 | 기존과 동일하게 빈 목록으로 시작(앱은 계속 동작) |
| 저장 실패 | `unawaited`로 무시. 메모리 상태는 유지되므로 그 세션에서는 정상 동작 |
| 찜 목록이 빔 | 안내 문구 + '추천 시작' 버튼 |

## 6. 테스트

`test/favorites_persistence_test.dart`를 확장한다.

- `Campsite.toJson()` → `fromJson()` 왕복 시 모든 필드가 보존된다(`score`가 `null`인 경우 포함).
- `SharedPrefsFavoritesStore`가 캠핑장 전체(이름·좌표·썸네일)를 저장하고 그대로 돌려준다.
- 깨진 JSON 항목은 버리고 나머지만 읽는다.
- 위젯: 홈의 "찜한 캠핑장" 카드로 목록에 들어간다.
- 위젯: 찜이 없으면 빈 상태 안내가 보인다.
- 위젯: 목록 → 상세에서 하트를 해제하면 목록에서 사라진다.
- 위젯: 저장소에 캠핑장이 있는 상태로 앱을 켜면 이름까지 복원된 목록이 보인다(네트워크 호출 없음).

기존 테스트 중 `Set<int>` 계약에 의존하는 부분은 새 계약에 맞춰 고친다.

## 7. 범위 밖

- 서버 동기화. 즐겨찾기 API가 없어 기기 로컬로만 남는다.
- 계정별 분리. 같은 기기에서 계정을 바꿔 로그인해도 찜 목록은 공유되고, 로그아웃·탈퇴 시에도
  지워지지 않는다(현재 동작 유지).
- 저장 개수 제한과 정렬 옵션. 필요해지면 그때 넣는다.
