# 캠핑장 탭 지도/리스트 뷰 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** "캠핑장" 탭이 반경 20km 이내 캠핑장을 전부 모아 리스트/지도 두 방식으로 보여주게 한다.

**Architecture:** 서버는 좌표+반경 기반 페이지네이션만 제공하므로(`radius`≤20000, `size`≤100),
`hasNext`가 꺼질 때까지 페이지를 반복 호출해 병합하는 순수 함수를 새 파일에 만들고, 기존
`CampOnApi`가 이를 사용하도록 배선한다. 화면 쪽은 기존 `CampsiteListScreen`을 그대로 재사용하는
리스트 탭과, `kakao_map_plugin`(WebView 기반 카카오맵 SDK)으로 만든 신규 지도 탭을 세그먼트
버튼으로 전환하는 `CampsiteBrowseScreen`으로 감싼다.

**Tech Stack:** Flutter/Dart, `kakao_map_plugin` (WebView 기반 Kakao Maps JS SDK 래퍼),
`flutter_test`.

## Global Constraints

- 서버 하드 제약(직접 호출로 확인): `/api/v1/campsites/nearby`의 `radius`는 20,000(m) 초과 시 400,
  `size`는 100 초과 시 400. `fetchAllNearby`는 반드시 `radius=20000`, `size=100`으로 고정한다.
- "추천" 탭(`fetchRecommendations`, `AppStep.recommendations`)은 이번 작업과 무관 — 손대지 않는다.
- 지도 진입 시 기본 탭은 **리스트**(세그먼트 초기값).
- `kakao_map_plugin`은 네이티브 SDK가 아니라 **WebView + Kakao Maps JavaScript SDK** 래퍼다
  (README 확인: "네이티브 라이브러리를 사용한 것이 아닌 Javascript 라이브러리를 이용하여 제작한
  플러그인입니다"). 로그인용 `KAKAO_NATIVE_APP_KEY`와는 **다른 JavaScript 키**가 필요하며,
  이 키는 카카오 디벨로퍼스 콘솔에서 해당 앱의 "Maps" 제품을 활성화해야 발급받을 수 있다
  (코드 밖 사전 준비 — 이 플랜으로 대신할 수 없음).
- 패키지 문서상 "마커와 클러스터를 함께 쓰지 말라"는 제약이 있음 — 클러스터링 사용 시
  개별 `Marker` 리스트를 동시에 지도에 추가하지 않는다.
- 스펙 문서: `docs/superpowers/specs/2026-07-30-campsite-map-list-view-design.md`

---

### Task 1: 페이지 집계 순수 함수 (`aggregateAllPages`)

**Files:**
- Create: `lib/campsites/campsite_pagination.dart`
- Test: `test/campsite_pagination_test.dart`

**Interfaces:**
- Produces: `typedef PageResult<T> = ({List<T> items, bool hasNext});`
  `typedef PageFetcher<T> = Future<PageResult<T>> Function(int page);`
  `Future<List<T>> aggregateAllPages<T>(PageFetcher<T> fetchPage, {int maxPages = 10})`
  — Task 2가 `Campsite`를 `T`로 넣어 사용한다. 이 함수는 `Campsite`나 HTTP를 전혀 모른다
  (순수 로직, 어떤 타입이든 페이지네이션 가능).

- [ ] **Step 1: 실패하는 테스트 작성**

```dart
// test/campsite_pagination_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:campon/campsites/campsite_pagination.dart';

void main() {
  test('hasNext가 false가 될 때까지 페이지를 이어붙인다', () async {
    final calledPages = <int>[];
    Future<PageResult<int>> fetchPage(int page) async {
      calledPages.add(page);
      if (page == 0) return (items: [1, 2, 3], hasNext: true);
      if (page == 1) return (items: [4, 5], hasNext: true);
      return (items: [6], hasNext: false);
    }

    final result = await aggregateAllPages<int>(fetchPage);

    expect(result, [1, 2, 3, 4, 5, 6]);
    expect(calledPages, [0, 1, 2]);
  });

  test('hasNext가 처음부터 false면 첫 페이지만 호출한다', () async {
    var calls = 0;
    Future<PageResult<int>> fetchPage(int page) async {
      calls++;
      return (items: [1], hasNext: false);
    }

    final result = await aggregateAllPages<int>(fetchPage);

    expect(result, [1]);
    expect(calls, 1);
  });

  test('maxPages에 도달하면 hasNext가 true여도 멈춘다', () async {
    var calls = 0;
    Future<PageResult<int>> fetchPage(int page) async {
      calls++;
      return (items: [page], hasNext: true); // 항상 다음 페이지가 있다고 응답
    }

    final result = await aggregateAllPages<int>(fetchPage, maxPages: 3);

    expect(result, [0, 1, 2]);
    expect(calls, 3);
  });
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `flutter test test/campsite_pagination_test.dart`
Expected: FAIL — `lib/campsites/campsite_pagination.dart`가 없어서 컴파일 에러(`Target of URI doesn't exist`).

- [ ] **Step 3: 최소 구현 작성**

```dart
// lib/campsites/campsite_pagination.dart
typedef PageResult<T> = ({List<T> items, bool hasNext});
typedef PageFetcher<T> = Future<PageResult<T>> Function(int page);

Future<List<T>> aggregateAllPages<T>(
  PageFetcher<T> fetchPage, {
  int maxPages = 10,
}) async {
  final all = <T>[];
  for (var page = 0; page < maxPages; page++) {
    final result = await fetchPage(page);
    all.addAll(result.items);
    if (!result.hasNext) break;
  }
  return all;
}
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `flutter test test/campsite_pagination_test.dart`
Expected: PASS — 3개 테스트 모두 통과.

- [ ] **Step 5: 커밋**

```bash
git add lib/campsites/campsite_pagination.dart test/campsite_pagination_test.dart
git commit -m "feat: add page aggregation helper for campsite listing"
```

---

### Task 2: `CampOnApi.fetchAllNearby` 배선

**Files:**
- Modify: `lib/main.dart:4104` (`_fetchCampsites` → `_fetchCampsitesPage` 분리 후 재사용)
- Modify: `lib/main.dart:4059` 부근 (`fetchNearby` 바로 아래에 `fetchAllNearby` 추가)
- Modify: `lib/main.dart:1` (import 추가)
- Modify: `lib/main.dart:205` (`_goBrowse`가 `fetchAllNearby` 호출하도록)
- Modify: `lib/main.dart:632` 부근 (재시도 콜백도 `fetchAllNearby` 호출하도록)

**Interfaces:**
- Consumes: Task 1의 `PageResult<T>`, `aggregateAllPages<T>`.
- Produces: `Future<List<Campsite>> fetchAllNearby({required CampRegion region})` —
  Task 3의 `CampsiteBrowseScreen`이 이 시그니처를 그대로 호출한다.

이 태스크는 실제 네트워크 호출을 감싸는 부분이라 기존 `fetchNearby`/`fetchRecommendations`와
동일하게 자동화된 유닛 테스트가 없다(코드베이스에 `HttpClient`를 모킹하는 인프라가 없음 —
`_fetchCampsites`도 지금까지 테스트가 없다). Task 1에서 이미 집계 로직 자체는 검증했으므로,
여기서는 `flutter analyze`로 타입 오류만 확인하고 Task 5의 수동 실행에서 최종 확인한다.

- [ ] **Step 1: import 추가**

`lib/main.dart` 상단 import 블록(다른 `import 'planner/...';` 옆)에 추가:

```dart
import 'campsites/campsite_pagination.dart';
```

- [ ] **Step 2: `_fetchCampsites`를 페이지 단위 헬퍼로 분리**

`lib/main.dart:4104`의 기존 `_fetchCampsites` 전체를 아래로 교체:

```dart
  Future<PageResult<Campsite>> _fetchCampsitesPage(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri).timeout(_timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.authorizationHeader,
        await _authorizationHeader(),
      );
      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401 || response.statusCode == 403) {
          await clearSession(notify: true);
          throw const CampOnSessionExpiredException(
            '로그인 정보가 만료되었습니다. 다시 로그인해주세요.',
          );
        }
        throw CampOnApiException('HTTP ${response.statusCode}: $body');
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const CampOnApiException('Unexpected response shape.');
      }
      final items = decoded['items'];
      if (items is! List) {
        return (items: <Campsite>[], hasNext: false);
      }
      return (
        items: items.whereType<Map<String, dynamic>>().map(Campsite.fromJson).toList(),
        hasNext: decoded['hasNext'] == true,
      );
    } on SocketException catch (error) {
      throw CampOnApiException('Network error: ${error.message}');
    } on TimeoutException {
      throw const CampOnApiException('Request timed out.');
    } on FormatException catch (error) {
      throw CampOnApiException('Invalid JSON: ${error.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<List<Campsite>> _fetchCampsites(Uri uri) async {
    final page = await _fetchCampsitesPage(uri);
    return page.items;
  }
```

(`_fetchCampsites`는 시그니처 그대로 유지되므로 `fetchNearby`/`fetchRecommendations`는
수정할 필요 없음.)

- [ ] **Step 3: `fetchAllNearby` 추가**

`lib/main.dart:4059` 부근, `fetchNearby` 메서드 바로 뒤에 추가:

```dart
  static const _regionAggregateRadius = 20000;
  static const _regionAggregatePageSize = 100;

  Future<List<Campsite>> fetchAllNearby({required CampRegion region}) {
    return aggregateAllPages<Campsite>((page) {
      final uri = _buildUri('/api/v1/campsites/nearby', <String, String>{
        'lat': region.lat.toString(),
        'lon': region.lon.toString(),
        'radius': '$_regionAggregateRadius',
        'size': '$_regionAggregatePageSize',
        'page': '$page',
      });
      return _fetchCampsitesPage(uri);
    });
  }
```

- [ ] **Step 4: `_goBrowse`와 재시도 콜백이 `fetchAllNearby`를 쓰도록 교체**

`lib/main.dart:205`:

```dart
  void _goBrowse() {
    setState(() {
      _browseFuture ??= _api.fetchAllNearby(region: _region);
      _step = AppStep.browse;
    });
  }
```

`lib/main.dart:630` 부근 (`AppStep.browse` 케이스의 `onRetry`)은 Task 3에서
`CampsiteBrowseScreen`으로 전체 교체되므로 여기서는 손대지 않는다.

- [ ] **Step 5: 정적 분석으로 타입 오류 확인**

Run: `flutter analyze lib/main.dart lib/campsites/campsite_pagination.dart`
Expected: `No issues found!`

- [ ] **Step 6: 커밋**

```bash
git add lib/main.dart
git commit -m "feat: aggregate all pages for campsite nearby search"
```

---

### Task 3: `CampsiteBrowseScreen` — 리스트/지도 세그먼트 토글

**Files:**
- Modify: `lib/main.dart:1476` 부근 (`CampsiteListScreen` 클래스 바로 위에 신규 위젯 추가)
- Modify: `lib/main.dart:624-642` (`AppStep.browse` 케이스 교체)
- Test: `test/campsite_browse_screen_test.dart`

**Interfaces:**
- Consumes: 기존 `CampsiteListScreen`, `CampsiteCard`, `Campsite`, `DetailEntry`.
- Produces: `CampsiteBrowseScreen` — 아래 생성자를 그대로 유지해야 Task 5에서
  프로덕션 `mapViewBuilder` 기본값을 연결할 수 있다.

```dart
typedef CampsiteMapBuilder = Widget Function(
  List<Campsite> sites,
  ValueChanged<Campsite> onSelect,
);

class CampsiteBrowseScreen extends StatefulWidget {
  const CampsiteBrowseScreen({
    required this.subtitle,
    required this.future,
    required this.emptyText,
    required this.onRetry,
    required this.onSelect,
    required this.mapViewBuilder,
    super.key,
  });

  final String subtitle;
  final Future<List<Campsite>>? future;
  final String emptyText;
  final VoidCallback onRetry;
  final ValueChanged<Campsite> onSelect;
  final CampsiteMapBuilder mapViewBuilder;
}
```

내부 상태는 `bool _showMap = false`(기본 리스트) 하나뿐이다. 리스트 모드일 때는 기존
`CampsiteListScreen`(제목/부제/`FutureBuilder`/`CampsiteCard` 목록)을 그대로 감싸 재사용하고,
지도 모드일 때는 같은 `FutureBuilder`의 데이터를 `widget.mapViewBuilder(sites, widget.onSelect)`에
넘긴다. 로딩/에러/빈 상태 패널은 두 모드 공통으로 `CampsiteListScreen`이 이미 갖고 있는
`LoadingPanel`/`ErrorPanel`/`EmptyPanel` 분기를 그대로 따른다 — 지도 모드에서도 데이터가
없거나 에러면 지도 대신 같은 패널을 보여준다.

테스트에서는 `mapViewBuilder`에 실제 `CampsiteMapView`(WebView, 네이티브 채널 필요) 대신
간단한 `Text` 위젯을 반환하는 가짜 빌더를 넣어, `KakaoMap` 없이도 토글 동작만 검증한다.

- [ ] **Step 1: 실패하는 위젯 테스트 작성**

```dart
// test/campsite_browse_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campon/main.dart';

Campsite _site(int id) => Campsite.fromJson(<String, dynamic>{
  'campsiteId': id,
  'name': '캠핑장 $id',
  'lat': 37.4,
  'lon': 128.5,
});

void main() {
  testWidgets('기본은 리스트, 지도 세그먼트를 탭하면 지도 빌더가 렌더링된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CampsiteBrowseScreen(
            subtitle: '테스트 부제',
            future: Future.value([_site(1), _site(2)]),
            emptyText: '결과 없음',
            onRetry: () {},
            onSelect: (_) {},
            mapViewBuilder: (sites, onSelect) =>
                Text('지도 뷰 · ${sites.length}곳'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('캠핑장 1'), findsOneWidget);
    expect(find.textContaining('지도 뷰'), findsNothing);

    await tester.tap(find.text('지도'));
    await tester.pumpAndSettle();

    expect(find.textContaining('지도 뷰 · 2곳'), findsOneWidget);
    expect(find.textContaining('캠핑장 1'), findsNothing);
  });
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `flutter test test/campsite_browse_screen_test.dart`
Expected: FAIL — `CampsiteBrowseScreen`이 없어서 컴파일 에러.

- [ ] **Step 3: `CampsiteBrowseScreen` 구현**

`lib/main.dart:1476` 바로 위(`class CampsiteListScreen` 앞)에 추가:

```dart
typedef CampsiteMapBuilder = Widget Function(
  List<Campsite> sites,
  ValueChanged<Campsite> onSelect,
);

class CampsiteBrowseScreen extends StatefulWidget {
  const CampsiteBrowseScreen({
    required this.subtitle,
    required this.future,
    required this.emptyText,
    required this.onRetry,
    required this.onSelect,
    required this.mapViewBuilder,
    super.key,
  });

  final String subtitle;
  final Future<List<Campsite>>? future;
  final String emptyText;
  final VoidCallback onRetry;
  final ValueChanged<Campsite> onSelect;
  final CampsiteMapBuilder mapViewBuilder;

  @override
  State<CampsiteBrowseScreen> createState() => _CampsiteBrowseScreenState();
}

class _CampsiteBrowseScreenState extends State<CampsiteBrowseScreen> {
  bool _showMap = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              CampChoiceChip(
                label: '리스트',
                selected: !_showMap,
                onTap: () => setState(() => _showMap = false),
              ),
              const SizedBox(width: 8),
              CampChoiceChip(
                label: '지도',
                selected: _showMap,
                onTap: () => setState(() => _showMap = true),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Campsite>>(
            future: widget.future,
            builder: (context, snapshot) {
              if (widget.future == null ||
                  snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingPanel();
              }
              if (snapshot.hasError) {
                return ErrorPanel(
                  message: snapshot.error.toString(),
                  onRetry: widget.onRetry,
                );
              }
              final sites = snapshot.data ?? <Campsite>[];
              if (sites.isEmpty) {
                return EmptyPanel(text: widget.emptyText, onRetry: widget.onRetry);
              }
              if (_showMap) {
                return widget.mapViewBuilder(sites, widget.onSelect);
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  Text(widget.subtitle, style: CampText.body.copyWith(color: CampColors.inkMuted80)),
                  const SizedBox(height: 12),
                  for (var i = 0; i < sites.length; i++) ...[
                    CampsiteCard(
                      site: sites[i],
                      showScore: false,
                      onTap: () => widget.onSelect(sites[i]),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `flutter test test/campsite_browse_screen_test.dart`
Expected: PASS.

이 시점에는 `AppStep.browse` 케이스를 아직 교체하지 않는다(그 자리에서 쓸 `CampsiteMapView`가
Task 4에서 만들어지기 전이라, 지금 교체하면 컴파일이 깨진 채로 남기 때문). `CampsiteBrowseScreen`은
아직 어디에서도 쓰이지 않지만 그 자체로는 완결된 위젯이고 테스트도 통과하므로, `main.dart`는
이 태스크가 끝난 시점에도 정상적으로 컴파일된다. 실제 배선 교체는 Task 4의 마지막 단계에서
`CampsiteMapView`와 함께 한 번에 한다.

- [ ] **Step 5: 정적 분석으로 확인**

Run: `flutter analyze lib/main.dart`
Expected: `No issues found!` (`CampsiteBrowseScreen`이 아직 어디서도 쓰이지 않는다는 경고는
없다 — public 클래스라 미사용 경고 대상이 아니다.)

- [ ] **Step 6: 커밋**

```bash
git add lib/main.dart test/campsite_browse_screen_test.dart
git commit -m "feat: add list/map toggle screen for campsite browse tab"
```

---

### Task 4: 카카오맵 SDK 연동 + `CampsiteMapView`

**Files:**
- Modify: `pubspec.yaml:41` 부근 (`geolocator: ^14.0.2` 다음 줄)
- Modify: `lib/main.dart:51` 부근 (`AuthConfig`에 `kakaoJavascriptKey` 추가)
- Modify: `lib/main.dart:30-49` (`_initializeNativeSdks`에 지도 SDK 초기화 추가)
- Modify: `android/app/src/main/AndroidManifest.xml:6-10` (`usesCleartextTraffic` 추가)
- Modify: `ios/Runner/Info.plist` (`NSAppTransportSecurity`, `io.flutter.embedded_views_preview` 추가)
- Create: `lib/campsites/campsite_map_view.dart`
- Test: `test/campsite_map_preview_controller_test.dart`

**Interfaces:**
- Consumes: `Campsite`(`lat`, `lon`, `name`, `validThumbnailUrl`, `accessHint`), `CampRegion`.
- Produces: `CampsiteMapView({required CampRegion region, required List<Campsite> sites, required ValueChanged<Campsite> onSelect})`
  — Task 3의 `mapViewBuilder`가 이 생성자를 그대로 호출한다.

`kakao_map_plugin`은 WebView 기반이라 `flutter_test` 환경에서 실제 지도를 렌더링할 수 없다
(네이티브 플랫폼 채널/웹뷰 바인딩이 없음). 그래서 "어떤 캠핑장을 미리보기 중인가"라는 상태만
`MapPreviewController`(순수 `ValueNotifier`)로 분리해 자동 테스트하고, 실제 `KakaoMap` 렌더링과
마커 탭 배선은 Task 5의 수동 실행에서 확인한다.

- [ ] **Step 1: 의존성 추가**

`pubspec.yaml`의 `geolocator: ^14.0.2` 바로 다음 줄에 추가:

```yaml
  kakao_map_plugin: ^0.4.0
```

Run: `flutter pub get`
Expected: 종료 코드 0, `kakao_map_plugin`이 `pubspec.lock`에 추가됨.

- [ ] **Step 2: 설치된 패키지의 실제 위젯 API 확인**

이 플러그인의 마커 탭 콜백 이름은 버전마다 다를 수 있으니, 다음 명령으로 설치된 버전의
example 코드를 직접 열어 `KakaoMap`/`Marker`/`Clusterer` 생성자 파라미터(특히 마커 탭
콜백 이름)를 확인한다:

```bash
find "$HOME/.pub-cache/hosted/pub.dev" -maxdepth 1 -iname "kakao_map_plugin-*"
```

찾은 디렉터리의 `example/lib/main.dart`를 읽고, 아래 Step 4 코드의 `onMapCreated`/
`onMarkerTap` 관련 부분이 실제 API와 다르면 그에 맞게 조정한다.

- [ ] **Step 3: JS 키 설정 추가**

`lib/main.dart:51` 부근 `AuthConfig` 클래스 안, `kakaoNativeAppKey` 바로 아래에 추가:

```dart
  static const kakaoJavascriptKey = String.fromEnvironment(
    'KAKAO_JAVASCRIPT_KEY',
  );
```

`lib/main.dart:30-49`의 `_initializeNativeSdks` 마지막(`KakaoSdk.init` try/catch 블록
다음)에 추가:

```dart
  if (AuthConfig.kakaoJavascriptKey.isEmpty) {
    debugPrint('[KakaoMap] KAKAO_JAVASCRIPT_KEY가 비어 있어 지도 초기화를 건너뜁니다.');
    return;
  }
  AuthRepository.initialize(appKey: AuthConfig.kakaoJavascriptKey);
```

파일 상단 import 블록에 추가:

```dart
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
```

- [ ] **Step 4: 실패하는 컨트롤러 테스트 작성**

```dart
// test/campsite_map_preview_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:campon/campsites/campsite_map_view.dart';
import 'package:campon/main.dart';

Campsite _site() => Campsite.fromJson(<String, dynamic>{
  'campsiteId': 1,
  'name': '테스트 캠핑장',
  'lat': 37.4,
  'lon': 128.5,
});

void main() {
  test('select()는 미리보기 대상을 설정하고 clear()는 비운다', () {
    final controller = MapPreviewController();
    expect(controller.value, isNull);

    final site = _site();
    controller.select(site);
    expect(controller.value, site);

    controller.clear();
    expect(controller.value, isNull);
  });
}
```

- [ ] **Step 5: 테스트 실행해서 실패 확인**

Run: `flutter test test/campsite_map_preview_controller_test.dart`
Expected: FAIL — `lib/campsites/campsite_map_view.dart`가 없어서 컴파일 에러.

- [ ] **Step 6: `CampsiteMapView` + `MapPreviewController` 구현**

```dart
// lib/campsites/campsite_map_view.dart
import 'package:flutter/material.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

import '../main.dart' show Campsite, CampRegion, CampColors, CampText;

class MapPreviewController extends ValueNotifier<Campsite?> {
  MapPreviewController() : super(null);

  void select(Campsite site) => value = site;
  void clear() => value = null;
}

class CampsiteMapView extends StatefulWidget {
  const CampsiteMapView({
    required this.region,
    required this.sites,
    required this.onSelect,
    super.key,
  });

  final CampRegion region;
  final List<Campsite> sites;
  final ValueChanged<Campsite> onSelect;

  @override
  State<CampsiteMapView> createState() => _CampsiteMapViewState();
}

class _CampsiteMapViewState extends State<CampsiteMapView> {
  final _preview = MapPreviewController();

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markers = widget.sites
        .map(
          (site) => Marker(
            markerId: 'campsite-${site.id}',
            latLng: LatLng(site.lat, site.lon),
          ),
        )
        .toList();

    return Stack(
      children: [
        KakaoMap(
          center: LatLng(widget.region.lat, widget.region.lon),
          markers: markers,
          onMapCreated: (controller) {
            // NOTE: 마커 탭 콜백 배선은 Step 2에서 확인한 설치 버전의 실제 API로 채운다.
            // 예: controller.setOnMarkerTap((markerId, latLng, zIndex) { ... })
          },
        ),
        ValueListenableBuilder<Campsite?>(
          valueListenable: _preview,
          builder: (context, site, _) {
            if (site == null) return const SizedBox.shrink();
            return Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: GestureDetector(
                onTap: () => widget.onSelect(site),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CampColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: CampColors.hairline),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(site.name, style: CampText.bodyStrong),
                            Text(site.accessHint, style: CampText.caption),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
```

Step 2에서 확인한 실제 마커 탭 콜백으로 `onMapCreated` 내부를 채워, 탭된 마커의
`markerId`(`'campsite-${site.id}'`)에서 `id`를 파싱해 `widget.sites`에서 해당 `Campsite`를
찾아 `_preview.select(site)`를 호출하도록 완성한다.

- [ ] **Step 7: 테스트 실행해서 통과 확인**

Run: `flutter test test/campsite_map_preview_controller_test.dart`
Expected: PASS.

- [ ] **Step 8: Android/iOS 플랫폼 설정**

`android/app/src/main/AndroidManifest.xml:6-10`의 `<application ...>` 태그에
`android:usesCleartextTraffic="true"` 추가:

```xml
    <application
        android:label="campon"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:allowBackup="false"
        android:usesCleartextTraffic="true">
```

`ios/Runner/Info.plist`의 `</dict>` 직전(마지막 키 다음)에 추가:

```xml
	<key>io.flutter.embedded_views_preview</key>
	<true/>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
	</dict>
```

- [ ] **Step 9: `AppStep.browse` 케이스를 `CampsiteBrowseScreen` + `CampsiteMapView`로 배선**

이제 `CampsiteMapView`가 존재하므로 Task 3에서 미뤄둔 배선을 마무리한다.
`lib/main.dart:624-642`의 기존 `case AppStep.browse:` 블록 전체를 아래로 교체:

```dart
      case AppStep.browse:
        return CampsiteBrowseScreen(
          subtitle: '${_region.name} 반경 20km 이내 캠핑장이에요.',
          future: _browseFuture,
          emptyText: '반경 20km 이내에서 캠핑장을 찾지 못했어요.',
          onRetry: () {
            setState(() {
              _browseFuture = _api.fetchAllNearby(region: _region);
            });
          },
          onSelect: (site) => _selectSite(site, DetailEntry.browse),
          mapViewBuilder: (sites, onSelect) => CampsiteMapView(
            region: _region,
            sites: sites,
            onSelect: onSelect,
          ),
        );
```

파일 상단 import 블록에 추가:

```dart
import 'campsites/campsite_map_view.dart';
```

- [ ] **Step 10: 정적 분석**

Run: `flutter analyze`
Expected: `No issues found!` (Step 2에서 API를 다르게 확인했다면 그에 맞춰 조정 후 재실행)

- [ ] **Step 11: 커밋**

```bash
git add pubspec.yaml pubspec.lock lib/main.dart lib/campsites/campsite_map_view.dart \
  test/campsite_map_preview_controller_test.dart android/app/src/main/AndroidManifest.xml \
  ios/Runner/Info.plist
git commit -m "feat: add Kakao map view with clustering and preview card"
```

---

### Task 5: 전체 배선 확인 + 수동 검증

**Files:** 없음 (검증 전용 태스크)

**Interfaces:** 없음.

- [ ] **Step 1: 전체 테스트 스위트 실행**

Run: `flutter test`
Expected: 기존 테스트 전부 + 이번에 추가한 3개 테스트 파일 모두 PASS, 실패 0건.

- [ ] **Step 2: 전체 정적 분석**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 수동 실행 안내 (이 환경에서는 자동 검증 불가)**

카카오 디벨로퍼스 콘솔에서 Maps용 JavaScript 키를 발급받은 뒤, 실제 기기/시뮬레이터에서:

```bash
flutter run --dart-define=KAKAO_JAVASCRIPT_KEY=<발급받은 키>
```

확인 항목:
- "캠핑장" 탭 진입 시 기본으로 리스트가 보이고, 이전보다 훨씬 많은(반경 20km 전체) 캠핑장이
  나오는지.
- "지도" 세그먼트를 탭하면 지도로 전환되고 핀/클러스터가 보이는지.
- 마커(또는 클러스터 확대 후 개별 핀)를 탭하면 하단에 미리보기 카드가 뜨는지.
- 미리보기 카드를 탭하면 기존과 동일한 `CampsiteDetailScreen`으로 이동하는지.
- 결과 0건/네트워크 에러 상황에서 두 탭 모두 기존 `EmptyPanel`/`ErrorPanel`이 뜨는지.

이 단계는 자동화 스크립트로 대체할 수 없으므로, 실행 후 결과를 있는 그대로(성공/실패 모두)
기록한다.
