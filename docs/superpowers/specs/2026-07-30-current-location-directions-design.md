# CampOn — 현재 위치 기준 캠핑장 거리 안내 설계

날짜: 2026-07-30
목적: 캠핑장 상세 화면에서 **기기의 실제 현재 위치**부터 해당 캠핑장까지의 거리·예상 이동 시간을
길찾기 API로 확인할 수 있게 한다.

## 1. 배경 / 현재 상태

- 상세 화면(`CampsiteDetailScreen`)에는 이미 "길찾기" 섹션과 `DirectionsCard`(`lib/main.dart:1632`)가 있고,
  `CampOnApi.fetchDirections`(`lib/main.dart:4027`)가 백엔드 `/api/v1/directions`를 호출해
  `distance`(m) / `duration`(s)를 받아 표시한다.
- 문제: 출발지가 실제 위치가 아니라 사용자가 온보딩에서 고른 **지역 중심 좌표**(`CampRegion`,
  예: 강원 `37.8228 / 128.1555`)다. 같은 지역 안에서는 누가 조회하든 값이 동일하다.
- `pubspec.yaml`에 위치 관련 패키지가 없고, `ios/Runner/Info.plist`에 위치 사용 목적 문자열이 없으며,
  `android/app/src/main/AndroidManifest.xml`에는 `INTERNET` 권한만 선언돼 있다.

따라서 실제 작업은 "길찾기 API 연동"이 아니라 **디바이스 GPS를 출발지로 연결하고 권한 흐름을 처리하는 것**이다.

## 2. 결정 사항

| 항목 | 결정 | 이유 |
|---|---|---|
| 표시 범위 | 상세 화면의 길찾기 카드만 | 캠핑장 1건당 길찾기 API 1회로 끝남. 목록 전체에 붙이면 N회 호출 |
| 권한 거부 시 | 지역 중심 폴백 없이 **설정 앱으로 유도** | 부정확한 추정 거리를 사실처럼 보여주지 않음 |
| 조회 시점 | "경로 확인" 버튼 탭 시 | 앱 진입 직후 권한 팝업이 뜨지 않아 거부율이 낮음 |
| 패키지 | `geolocator` | 권한 요청·서비스 활성 확인·설정 화면 열기를 한 패키지로 해결 |

## 3. 구성 요소

### 3.1 신규 `lib/location/location_service.dart`

`plan_service.dart`와 같은 주입 가능 패턴. geolocator 플랫폼 호출을 인터페이스 뒤에 감춰
위젯 테스트에서 플랫폼 채널 없이 대체할 수 있게 한다.

```dart
enum LocationBlockReason { serviceDisabled, denied, deniedForever, failed }

class LocationPoint { final double lat; final double lon; }

class LocationBlockedException implements Exception {
  final LocationBlockReason reason;
  final String message;
}

abstract interface class LocationProvider {
  Future<LocationPoint> current();
  Future<void> openSettings(LocationBlockReason reason);
}

class GeolocatorLocationProvider implements LocationProvider { ... }
```

`current()` 순서:

1. `isLocationServiceEnabled()` — false면 `serviceDisabled`
2. `checkPermission()` → `denied`면 `requestPermission()`
3. 요청 후에도 `denied`면 `denied`, `deniedForever`면 `deniedForever`
4. `getCurrentPosition(accuracy: medium, timeLimit: 10s)` — 예외·타임아웃이면 `failed`

`openSettings(reason)`은 `serviceDisabled`면 `openLocationSettings()`(기기 위치 OFF),
그 외에는 `openAppSettings()`(앱 권한)를 호출한다. 사용자가 가야 할 화면이 다르기 때문이다.

### 3.2 `DirectionsCard` 변경 (`lib/main.dart:1632`)

- 파라미터를 `api` / `origin`(CampRegion) → `fetchDirections`(함수 참조) + `location`(LocationProvider)로 좁힌다.
  카드가 실제로 쓰는 것은 `api.fetchDirections` 하나뿐이라 인터페이스를 좁히면 위젯 테스트에서
  네트워크 없이 검증할 수 있다. 폴백을 쓰지 않기로 했으므로 `origin`은 미사용이 되어 제거한다.
- `_load()`는 `location.current()`로 좌표를 먼저 얻고, 그 좌표를 `originX`(lon) / `originY`(lat)로
  넘겨 `fetchDirections`를 호출한다.
- 안내 문구: "강원 지역 기준 출발지에서 …" → "현재 위치에서 {캠핑장}까지 경로를 확인해요."

### 3.3 상태별 UI

기존 `FutureBuilder<DirectionResult>`는 **명시적 상태**(`_loading` / `_result` / `_error`)로 교체했다.
이유: 위치 예외는 네트워크 오류와 달리 거의 즉시 완료되어, `FutureBuilder`가 리스너를 붙이기 전에
Future가 error로 완료되면 Dart가 unhandled async error로 보고한다(테스트 3건이 실제로 이 문제로 실패).
`try`/`catch` + `setState`는 이 타이밍 의존을 없앤다.

| 상황 | 문구 | 버튼 |
|---|---|---|
| 위치 서비스 OFF | 기기 위치 서비스가 꺼져 있어요 | 위치 설정 열기 |
| 권한 거부(일시) | 현재 위치를 쓰려면 위치 권한이 필요해요 | 권한 다시 요청 |
| 권한 영구 거부 | 설정에서 위치 권한을 허용해주세요 | 설정 열기 |
| GPS 타임아웃·실패 | 현재 위치를 확인하지 못했어요 | 다시 시도 |
| 길찾기 API 실패 | (기존 문구 유지) | 다시 시도 |

설정 화면으로 보내는 두 케이스(`serviceDisabled`, `deniedForever`)에는 "다시 시도" 텍스트 버튼을
함께 둔다. 설정에서 권한을 켜고 돌아왔을 때 재조회 수단이 없으면 상세 화면을 나갔다 다시 들어와야 하는
막다른 흐름이 되기 때문이다.

## 4. 플랫폼 설정

- `pubspec.yaml`: `geolocator` 추가
- `ios/Runner/Info.plist`: `NSLocationWhenInUseUsageDescription`
  = "선택한 캠핑장까지의 거리와 이동 시간을 알려드리기 위해 현재 위치를 사용합니다."
- `android/app/src/main/AndroidManifest.xml`: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`

## 5. 검증

1. 변경 전 베이스라인 확보 — `flutter test` 16개 통과, `flutter analyze` 이슈 없음 (2026-07-30 확인)
2. 신규 `test/directions_card_test.dart` — 가짜 `LocationProvider` + 가짜 fetcher로 3케이스:
   - 성공 → 거리·예상 시간 표시, fetchDirections가 GPS 좌표를 출발지로 받음
   - 영구 거부 → "설정 열기" 노출
   - 위치 서비스 OFF → "위치 설정 열기" 노출
3. `flutter analyze` clean + 전체 테스트 통과 → 2026-07-30 결과: 테스트 19개 통과, analyze 이슈 없음
4. `flutter build ios --simulator --debug` 성공 (geolocator 네이티브 플러그인 pod 통합 확인)

**자동 검증 한계:** 실제 GPS 값이 붙는지는 권한 팝업 때문에 CI/테스트로 확인할 수 없다.
실기기 확인은 `docs/ios-device-runbook.md` 절차로 사람이 한 번 수행해야 한다.
