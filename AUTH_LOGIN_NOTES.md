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
- Kakao: Flutter SDK 로그인은 연결했지만 2026-07-10 Swagger에는 Kakao JWT 교환 엔드포인트가 없습니다. 서버에 엔드포인트가 추가되면 `KAKAO_BACKEND_AUTH_PATH`로 경로를 주입합니다.
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

- Kakao는 현재 Swagger에 서버 교환 API가 없어서 CampOn JWT 발급까지 완료할 수 없습니다.
- Google/Apple은 provider 콘솔 설정값과 실제 기기 로그인 계정이 있어야 서버 JWT 발급까지 검증할 수 있습니다.
- 운영 로그인으로 전환하려면 OAuth provider 설정값, redirect URI, iOS bundle identifier, Android package name, Apple Sign in capability 설정이 필요합니다.
