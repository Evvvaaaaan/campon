# CampOn — "캠핑장" 탭 지도/리스트 뷰 설계

날짜: 2026-07-30
목적: "캠핑장" 탭(`AppStep.browse`)이 화면 제목("모든 캠핑장")과 달리 실제로는 반경 10km 이내
가까운 20곳만 페이지네이션해서 보여주는 문제를 고치고, 지도 뷰와 리스트 뷰를 나눠 카카오맵에서
위치를 직접 확인할 수 있게 한다.

## 1. 배경 / 현재 상태

- 하단 탭 "캠핑장"(`lib/main.dart:3284` 라벨) → `AppStep.browse` → `CampsiteListScreen`
  (`lib/main.dart:1476`)이 `CampOnApi.fetchNearby`(`lib/main.dart:4059`)를 `page: 0, size: 20`
  고정으로 한 번만 호출한 결과를 리스트로만 보여준다. 화면 제목은 "모든 캠핑장"이지만 실제로는
  최초 페이지 20건이 전부이며, 그 이상을 보여줄 UI(더 보기/지도)가 없다.
- 서버 API(`/api/v1/campsites/nearby`, `/api/v1/campsites/recommend`)를 직접 호출해 확인한
  하드 제약:
  - `radius`는 **20,000(m) 초과 시 400 에러** (좌표 기준 반경 검증이 서버에 있음).
  - `size`는 **100 초과 시 400 에러**.
  - "지역 전체" 또는 "전국"을 한 번에 반환하는 별도 엔드포인트는 없음. 좌표+반경 기반
    페이지네이션(`hasNext`)만 존재.
  - 따라서 "경기" 같은 지역(반경 20km보다 훨씬 넓음) 전체를 문자 그대로 가져올 방법은 없고,
    **지역 중심 좌표 기준 반경 20km 이내**가 이번 작업에서 낼 수 있는 "전체"의 실질적 범위다.
    (사용자 승인 완료 — 다른 범위 정의 아님)
- `Campsite` 모델(`lib/main.dart:4507`)에 `lat`/`lon`이 이미 있어 마커 좌표로 바로 쓸 수 있다.
- 지도 SDK는 프로젝트에 전혀 없음. `pubspec.yaml`의 `kakao_flutter_sdk_user`는 카카오 로그인
  전용이며 지도 기능이 없다. 로그인용 Native App Key(`AuthConfig.kakaoNativeAppKey`,
  `lib/main.dart:52`, `KakaoSdk.init` 호출부 `lib/main.dart:37`)와 지도 SDK가 요구하는
  **JavaScript 키는 카카오 디벨로퍼스 콘솔에서 별도로 발급/활성화해야 하는 다른 키**다.

## 2. 결정 사항

| 항목 | 결정 | 이유 |
|---|---|---|
| "전체" 표시 범위 | 선택 지역 중심 좌표 기준 **반경 20km**, `hasNext:false`까지 전 페이지 집계 | 서버가 허용하는 최댓값. 이 이상은 백엔드 변경 없이 불가능 |
| 지도 SDK | `kakao_map_plugin` (네이티브 플러그인) | 클러스터링 내장, 스크롤/줌 반응성이 웹뷰 방식보다 좋음 |
| 마커 밀집 처리 | 플러그인 `Clusterer`로 클러스터링 | 반경 20km 안에 캠핑장이 수십 개가 될 수 있어 핀 중첩 방지 |
| 뷰 전환 UI | 화면 상단 세그먼트 버튼 `[리스트 \| 지도]` | 같은 데이터를 표현 방식만 바꿔 보여주는 것이므로 탭 전환이 자연스러움 |
| 기본 진입 탭 | 리스트 | 기존 사용자 경험을 그대로 유지, 지도는 필요할 때 전환 |
| 마커 탭 동작 | 하단 미리보기 카드 → 한 번 더 탭 시 상세화면 | 지도를 보며 여러 곳을 빠르게 훑어보되, 오탭으로 바로 상세 이동하는 것을 방지 |
| "추천" 탭 | 이번 작업과 무관, 변경 없음 | 사용자가 조건을 입력해 받는 개인화 추천이라 "전체 표시"와 성격이 다름 |

## 3. 구성 요소

### 3.1 `CampOnApi` — 페이지 집계

`_fetchCampsites`(`lib/main.dart:4104`)는 현재 `decoded['items']`만 꺼내고 `hasNext`를 버린다.
이를 페이지 1건의 결과를 그대로 반환하는 내부 헬퍼로 바꾸고, 기존 `fetchNearby`/
`fetchRecommendations`는 이 헬퍼의 `items`만 꺼내 써서 공개 시그니처를 그대로 유지한다.

```dart
Future<({List<Campsite> items, bool hasNext})> _fetchCampsitesPage(Uri uri) async {
  // 기존 _fetchCampsites 본문 + decoded['hasNext'] == true 를 함께 반환
}

Future<List<Campsite>> _fetchCampsites(Uri uri) async {
  final page = await _fetchCampsitesPage(uri);
  return page.items;
}
```

신규 `fetchAllNearby`는 반경을 서버 최댓값(20,000)으로 고정하고, `hasNext`가 꺼질 때까지
`page`를 늘려가며 반복 호출해 결과를 병합한다. 무한 루프 방지를 위해 최대 페이지 수 캡을 둔다.

```dart
static const _maxRegionRadius = 20000;
static const _regionPageSize = 100;
static const _maxAggregatePages = 10; // 안전장치, 최대 1000곳

Future<List<Campsite>> fetchAllNearby({required CampRegion region}) async {
  final all = <Campsite>[];
  for (var page = 0; page < _maxAggregatePages; page++) {
    final uri = _buildUri('/api/v1/campsites/nearby', <String, String>{
      'lat': region.lat.toString(),
      'lon': region.lon.toString(),
      'radius': '$_maxRegionRadius',
      'size': '$_regionPageSize',
      'page': '$page',
    });
    final result = await _fetchCampsitesPage(uri);
    all.addAll(result.items);
    if (!result.hasNext) break;
  }
  return all;
}
```

`AppStep.browse`의 `_browseFuture`(`lib/main.dart:203`, `619` 부근)가 `fetchNearby` 대신
`fetchAllNearby`를 호출하도록 교체한다.

### 3.2 지도 SDK 연동

- `pubspec.yaml`에 `kakao_map_plugin` 추가.
- `AuthConfig`(`lib/main.dart:52` 부근)에 `kakaoJavascriptKey`를
  `String.fromEnvironment('KAKAO_JAVASCRIPT_KEY')`로 추가하고, `main()`에서 기존
  `KakaoSdk.init` 옆에 `AuthRepository.initialize(appKey: AuthConfig.kakaoJavascriptKey)` 호출 추가.
- **사전 준비(코드 밖, 사용자 작업)**: 카카오 디벨로퍼스 콘솔의 해당 앱에서 "Maps" 제품을
  활성화하고 JavaScript 키를 발급받아야 함. 이 키를 `--dart-define=KAKAO_JAVASCRIPT_KEY=...`
  로 빌드/실행 시 전달.
- Android(`android/app/src/main/AndroidManifest.xml`): `INTERNET` 권한, `usesCleartextTraffic="true"`.
- iOS(`ios/Runner/Info.plist`): `NSAppTransportSecurity` 설정, `io.flutter.embedded_views_preview` true.

### 3.3 화면 구조

`AppStep.browse` 케이스(`lib/main.dart:624` 부근)가 `CampsiteListScreen`을 직접 반환하는 대신,
신규 `CampsiteBrowseScreen`을 반환하도록 교체한다.

- `CampsiteBrowseScreen`
  - 제목/부제 표시(부제는 "가까운 캠핑장을 보여드려요" → "반경 20km 이내 캠핑장 N곳"으로 변경).
  - 상단 세그먼트 버튼 `[리스트 | 지도]`, 내부 상태로 현재 탭 관리, 기본값 리스트.
  - 리스트 선택 시: 기존 `CampsiteListScreen`의 리스트 렌더링 부분(`CampsiteCard` 반복,
    `lib/main.dart:2971`)을 그대로 재사용.
  - 지도 선택 시: 신규 `CampsiteMapView(sites, onSelect)` 렌더링.
- `CampsiteMapView`
  - `KakaoMap`을 지역 중심 좌표로 초기화, 반경 20km 전체가 보이는 줌 레벨로 설정.
  - `sites` 각각을 마커로 변환, 플러그인 `Clusterer`로 클러스터링.
  - 마커 탭 → 하단에 작은 미리보기 카드(이름/썸네일/거리) 표시.
  - 미리보기 카드 탭 → 기존 `_selectSite(site, DetailEntry.browse)` 호출, 이후 흐름은
    기존 리스트 카드 탭과 동일(`CampsiteDetailScreen`으로 이동).

### 3.4 에러 / 빈 상태

- 집계 중 어느 페이지든 실패하면 전체 실패로 처리 → 기존 `ErrorPanel` + 재시도(0페이지부터
  재집계).
- 결과 0건이면 리스트/지도 어느 탭이든 기존 `EmptyPanel` 표시(빈 지도를 보여주지 않음).
- 로딩은 전체 집계가 끝날 때까지 기존 `LoadingPanel` 유지(부분 표시 없음).

## 4. 테스트

- 유닛 테스트: `fetchAllNearby` — `hasNext: true, true, false` 3페이지 mock 응답을 주고
  병합 결과·호출 횟수·안전 캡(`_maxAggregatePages`) 동작 검증.
- 위젯 테스트: 세그먼트 버튼 전환 시 리스트/지도 위젯이 올바르게 바뀌는지 확인.
- 지도 렌더링 자체의 시각적 확인은 실제 `KAKAO_JAVASCRIPT_KEY`와 기기/시뮬레이터가 필요해
  자동화된 이 환경에서는 검증할 수 없음 — 실행 시 수동 확인 필요.

## 5. 범위 밖 (참고용 메모, 이번 작업에서 다루지 않음)

- `nearby`/`recommend` 응답의 `facility` 값이 서로 다른 표현(영문 enum vs 한글 원문)으로
  오는 것을 확인했으나, 화면 표시에는 문제가 없어(코드가 매핑 실패 시 원문을 그대로 보여줌)
  이번 작업 범위에 포함하지 않음.
