# CampOn Auth Login Notes

## 확인 일자

- 2026-07-10 (최초), 2026-07-12 (재검증)
- Swagger UI: `https://campon.seohamin.com/api/swagger`
- OpenAPI JSON: `https://campon.seohamin.com/api/swagger-ui/v3/api-docs`

## 2026-07-12 재검증 결과

- 서버 dev 로그인(`POST /api/v1/auth/dev/user` → `GET /api/v1/auth/dev/token?userId=1`),
  토큰 리프레시(`POST /api/v1/auth/token/refresh`), 보호 API(`GET /api/v1/campsites/nearby`) 모두 정상 (200).
- `POST /api/v1/auth/oauth2/kakao`는 여전히 서버에 없음 (404 Not Found 재확인).
  앱은 `KAKAO_BACKEND_AUTH_PATH`가 주입되기 전까지 카카오 버튼을 비활성화("준비 중")한다.
- 사용자가 로그인 창을 스스로 닫은 경우(Google/Apple/Kakao 취소)는 오류로 표시하지 않는다.
- 로그인 실패 시 서버가 주는 한국어 `message`를 우선 표시하고, 없으면 상태 코드 기반 한국어 메시지를 쓴다.
- 디버그 빌드에서는 `SHOW_DEV_LOGIN` 없이도 개발 계정 로그인이 자동 노출된다 (릴리즈에서는 기존과 동일하게 숨김).
- `integration_test/login_flow_test.dart`가 iOS 시뮬레이터에서 실서버 dev 로그인 → 홈 진입을 검증한다 (2026-07-12 통과).
- Google iOS 미해결 과제: `GIDClientID`가 현재 웹(server) client ID와 동일하다. iOS 전용 OAuth client를
  발급받아 `GIDClientID`와 reversed URL scheme을 교체해야 실기기 Google 로그인이 완성된다.
- iOS 빌드가 `resource fork, Finder information ... not allowed` CodeSign 오류로 실패하면
  `scripts/bootstrap.sh`를 실행한다. (`flutter clean`이 `tmp_build` 심링크를 지우면 재발함 — 원인은
  iCloud File Provider가 프로젝트 내부의 새 `.framework` 디렉터리에 FinderInfo를 붙이기 때문)

## 2026-07-31 Kakao 400 재검증 결과

- `POST /api/v1/auth/oauth2/kakao`는 이제 서버에 존재한다 (404 아님).
- Swagger의 `OauthRequestDto`는 `code`, `accessToken`, `name` 세 필드를 가진다.
- 실제 서버 응답으로 확인한 provider별 필수 필드:
  - Kakao → `accessToken` (`code`만 보내면 `400 INVALID_REQUEST`)
  - Google / Apple → `code` (`accessToken`만 보내면 `400 INVALID_REQUEST`)
- 앱은 Kakao 네이티브 SDK가 돌려준 access token을 `code` 필드로 보내고 있었기 때문에 400이 났다.
  `AuthProvider.credentialField`로 provider별 필드명을 나눠 전송하도록 수정했다.

## 2026-08-01 출시 준비 확인 결과

- **iOS Bundle ID를 `com.seohamin.camp.dev`로 확정했다.** 다른 팀이 소유한
  `com.seohamin.camping`으로 전환하지 않고 현재 값 그대로 출시한다. Kakao iOS 등록도 이 ID에
  맞춘다. 자세한 배경과 남은 작업은 `RELEASE_CHECKLIST.md` A-2에 있다.
- **Google iOS OAuth client는 이미 `com.seohamin.camp.dev`로 등록돼 있다** (2026-08-01 확인).
  위 2026-07-12 절의 "Google iOS 미해결 과제"는 해결된 상태다. `Info.plist`를 파싱해 확인한 결과:
  - `GIDClientID`(`...up1v7t1gn...`)가 `GIDServerClientID`(`...ncfo4v0ej...`)와 서로 다르다.
    즉 iOS 전용 client가 발급되어 들어가 있다.
  - reversed URL scheme `com.googleusercontent.apps.651935780618-up1v7t1gn...`이 `GIDClientID`와
    일치한다.
- **아직 남은 것:** Kakao Developers의 iOS bundle ID 등록, Apple App ID에 Sign in with Apple
  활성화, 그리고 백엔드가 Apple 토큰의 `aud`로 `com.seohamin.camp.dev`를 받아들이는지 확인.
  네이티브 iOS 로그인에서 `aud`는 bundle ID 그 자체라, 서버가 옛 ID만 허용하면 Apple 로그인이
  전부 거부된다.

## 400 원인

- `POST /api/v1/auth/oauth2/google`와 `POST /api/v1/auth/oauth2/apple`는 JSON body에 `code`, `name`을 받습니다.
- 빈 값으로 요청하면 서버가 `400 BAD_REQUEST`, `INVALID_REQUEST`, `요청 정보가 잘못되어 있습니다.`를 반환합니다.
- 앱에서는 OAuth code가 비어 있으면 서버 요청을 보내지 않고 화면에서 먼저 막도록 처리했습니다.
- 로그인 토큰이 있어도 `GET /api/v1/campsites/nearby`는 `radius=70000`에서 `400 BAD_REQUEST`를 반환했습니다.
- 같은 좌표에서 `radius=10000`과 `radius=1000`은 `200 OK`를 반환했습니다. 앱의 nearby 조회 반경은 `10000`으로 조정했습니다.

## 앱 로그인 흐름

- 앱 시작 화면은 로그인 화면입니다.
- `개발 계정으로 시작`은 `POST /api/v1/auth/dev/user` 호출 후 `GET /api/v1/auth/dev/token?userId=1`로 JWT를 발급받습니다.
- 소셜 로그인은 native SDK에서 provider 인증을 먼저 실행한 뒤, provider가 돌려준 code를 서버로 보냅니다.
  - Google: `POST /api/v1/auth/oauth2/google`
  - Apple: `POST /api/v1/auth/oauth2/apple`
  - Kakao: `POST /api/v1/auth/oauth2/kakao` — 단, Kakao만 authorization code가 아니라
    네이티브 SDK access token을 `accessToken` 필드로 보냅니다.
- 로그인 성공 후 캠핑장 API 요청에는 `Authorization: Bearer {accessToken}` 헤더를 붙입니다.
- access token 만료 1분 전부터는 `POST /api/v1/auth/token/refresh`로 갱신합니다.
- 전체 캠핑장 둘러보기는 `GET /api/v1/campsites/nearby`를 사용하며, 현재 서버 동작 기준 반경은 10km입니다.

## Native SDK 설정값

앱 실행 시 아래 값을 `--dart-define`으로 전달합니다.

```sh
flutter run \
  --dart-define=KAKAO_NATIVE_APP_KEY={kakao_native_app_key} \
  --dart-define=KAKAO_BACKEND_AUTH_PATH=/api/v1/auth/oauth2/kakao \
  --dart-define=GOOGLE_CLIENT_ID={ios_or_web_client_id_if_needed} \
  --dart-define=GOOGLE_SERVER_CLIENT_ID={google_web_server_client_id} \
  --dart-define=APPLE_SERVICE_ID={apple_service_id_for_android} \
  --dart-define=APPLE_REDIRECT_URI={apple_redirect_uri_for_android}
```

필수 플랫폼 설정:

- iOS `Info.plist`
  - `kakaoYOUR_KAKAO_NATIVE_APP_KEY`를 실제 `kakao{native_app_key}` URL scheme으로 교체합니다.
  - `com.googleusercontent.apps.YOUR_REVERSED_IOS_CLIENT_ID`를 Google iOS client의 reversed client ID로 교체합니다.
  - Apple 로그인은 Xcode Signing & Capabilities에서 `Sign in with Apple` capability가 필요합니다.
- Android
  - `android/app/build.gradle.kts`의 manifest placeholder 기본값 `kakaoYOUR_KAKAO_NATIVE_APP_KEY`를 실제 scheme으로 바꾸거나 `-PKAKAO_SCHEME=kakao{native_app_key}`로 전달합니다.
  - Google 로그인은 Google Cloud/Firebase에 Android package name과 SHA 인증서를 등록해야 합니다.
  - Android Apple 로그인은 `APPLE_SERVICE_ID`, `APPLE_REDIRECT_URI`, 서버 callback redirect가 필요합니다.

## 요청 예시

```json
{
  "code": "oauth-provider-code",
  "name": "사용자 이름"
}
```

## 응답 필드

- `accessToken`: 보호 API 호출에 사용하는 JWT
- `tokenType`: 현재 Swagger 응답 기준 `Bearer`
- `exprTime`: access token 유효 시간, 초 단위
- `refreshToken`: access token 갱신에 사용하는 토큰

## 남은 확인 사항

- Kakao 서버 교환 API는 추가되었고 필드명 수정도 끝났지만, 실기기에서 실제 카카오 계정으로
  CampOn JWT 발급까지 성공하는지는 아직 검증하지 못했습니다.
- Google/Apple은 provider 콘솔 설정값과 실제 기기 로그인 계정이 있어야 서버 JWT 발급까지 검증할 수 있습니다.
- 운영 로그인으로 전환하려면 OAuth provider 설정값, redirect URI, iOS bundle identifier, Android package name, Apple Sign in capability 설정이 필요합니다.
