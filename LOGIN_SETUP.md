# CampOn 로그인 설정 및 운영 가이드

이 문서는 CampOn 앱의 Google, Apple, Kakao 로그인과 서버 JWT 인증을 처음부터 활성화하기 위해 **프로젝트 담당자가 반드시 수행해야 하는 작업**을 정리합니다. 앱 코드는 로그인 토큰을 iOS Keychain과 Android Keystore 기반 암호화 저장소에 보관하고, 앱 재실행 시 자동으로 복원합니다.

## 1. 구현 범위

- Google, Apple, Kakao 네이티브 로그인 후 서버 JWT 발급
- access token 만료 1분 전 refresh token을 통한 자동 갱신
- 앱 재시작 시 저장 세션 복원
- 토큰 갱신 실패 또는 보호 API의 401/403 응답 시 세션 삭제 후 로그인 화면 전환
- 로그아웃 시 CampOn 토큰 삭제 및 Google/Kakao 로컬 세션 해제

Apple은 Apple 계정의 기기 수준 세션을 앱이 강제로 해제할 수 없습니다. CampOn 서버 세션과 보안 저장소의 토큰은 로그아웃 시 삭제됩니다.

## 2. 시작 전 확정할 값

아래 값은 Android, iOS, OAuth 공급자 콘솔, 서버에서 모두 동일해야 합니다.

| 항목 | 현재 앱 값 | 반드시 확인할 작업 |
| --- | --- | --- |
| Android application ID | `com.seohamin.camping` | Google/Kakao 콘솔에 정확히 등록 |
| iOS bundle identifier | Xcode Runner의 `PRODUCT_BUNDLE_IDENTIFIER` | Google/Kakao/Apple의 iOS 식별자로 정확히 등록 |
| API 호스트 | `https://campon.seohamin.com` | 운영 API 주소와 TLS 인증서 확인 |
| Kakao URL scheme | `kakao{KAKAO_NATIVE_APP_KEY}` | Android manifest, iOS Info.plist, Kakao 콘솔 값을 일치 |
| Google iOS URL scheme | reversed iOS client ID | iOS client ID 기준으로 Info.plist에 등록 |
| Apple Android redirect URI | HTTPS callback URL | Apple Service ID와 서버 callback 허용 목록에 일치하게 등록 |

## 3. 서버 담당자 필수 작업

앱은 다음 계약을 전제로 동작합니다. 배포 전에 Swagger 또는 실제 서버로 모두 확인해야 합니다.

| 목적 | HTTP 요청 | 필수 응답 |
| --- | --- | --- |
| Google JWT 교환 | `POST /api/v1/auth/oauth2/google` body: `code`, `name` | `accessToken`, `refreshToken`, `tokenType`, `exprTime` |
| Apple JWT 교환 | `POST /api/v1/auth/oauth2/apple` body: `code`, `name` | 위와 동일 |
| Kakao JWT 교환 | `POST /api/v1/auth/oauth2/kakao` body: `code`, `name` | 위와 동일 |
| access token 갱신 | `POST /api/v1/auth/token/refresh` body: `refreshToken` | 위와 동일 |
| 개발 계정 | `POST /api/v1/auth/dev/user`, `GET /api/v1/auth/dev/token?userId=1` | 개발 환경에서만 JWT 발급 |

필수 보안 조건:

- OAuth `code`를 서버에서 해당 공급자의 token endpoint로 교환하고, 서명·audience·issuer·redirect URI를 검증합니다. 앱이 보낸 이름이나 Kakao access token만 신뢰해 계정을 만들면 안 됩니다.
- refresh token은 서버에서 해시하여 저장하고, 회전(rotation), 만료, 재사용 탐지, 사용자별 폐기를 구현합니다.
- 보호 API는 잘못되었거나 만료된 access token에 `401` 또는 `403`을 반환해야 합니다. 앱은 이 응답을 받으면 로그인 화면으로 이동합니다.
- Kakao 교환 endpoint가 없으면 앱에서 `KAKAO_BACKEND_AUTH_PATH`를 전달하지 마세요. 버튼은 "준비 중"으로 비활성화됩니다.
- 운영 서버는 HTTPS만 사용하고, `exprTime`을 초 단위 숫자로 반환합니다.

## 4. Google Cloud 설정

1. Google Cloud Console에서 OAuth 동의 화면을 만들고, 앱 이름·지원 이메일·개인정보 처리방침 URL을 입력합니다.
2. **Android OAuth client**를 만들고 package name `com.seohamin.camping`과 배포 서명 인증서의 SHA-1/SHA-256을 등록합니다. 디버그와 릴리즈 서명은 서로 다릅니다.
3. **iOS OAuth client**를 만들고 실제 iOS bundle identifier를 등록합니다.
4. 서버용 **Web application OAuth client**를 만들고 client ID를 보관합니다. 이것이 `GOOGLE_SERVER_CLIENT_ID`입니다.
5. iOS client ID와 reversed client ID를 iOS 설정에 반영합니다.
   - `ios/Runner/Info.plist`의 `GIDClientID`를 iOS client ID로 변경합니다.
   - 같은 파일의 `com.googleusercontent.apps...` URL scheme을 그 iOS client ID의 reversed 값으로 변경합니다.
6. Google 로그인 후 앱에서 서버 auth code가 전달되고 서버 JWT가 발급되는지 실제 Android와 iOS 기기에서 각각 확인합니다.

현재 `Info.plist`의 Google 값은 서버 Web client ID와 같으므로, iOS 전용 client ID를 만든 뒤 5단계를 반드시 수행해야 합니다.

## 5. Apple 설정

1. Apple Developer의 Identifiers에서 iOS App ID를 만들고 **Sign in with Apple** capability를 켭니다.
2. Xcode에서 Runner target의 Signing & Capabilities에 **Sign in with Apple**을 추가합니다. `ios/Runner/Runner.entitlements`에는 이미 entitlement가 있습니다.
3. Android에서도 Apple 로그인할 경우 Apple Developer에서 Service ID와 HTTPS return URL을 등록합니다.
4. 서버는 Apple authorization code를 Apple 서버에 교환하고 `id_token`의 서명, issuer, audience, nonce를 검증해야 합니다.
5. Apple은 이름과 이메일을 최초 승인 때만 제공할 수 있으므로, 서버는 첫 로그인에서 프로필을 저장하고 이후 빈 값에도 기존 계정을 찾아야 합니다.

## 6. Kakao Developers 설정

1. Kakao Developers에서 앱을 만들고 Android package name, iOS bundle ID를 등록합니다.
2. 플랫폼별 키 해시와 iOS bundle ID를 추가합니다.
3. Native App Key를 확인합니다. Native App Key는 공개 식별자이지만 Admin Key는 절대 앱이나 저장소에 넣지 않습니다.
4. Android `android/app/build.gradle.kts`와 iOS `Info.plist`의 Kakao URL scheme을 `kakao{Native App Key}`로 맞춥니다.
5. 서버에 Kakao JWT 교환 endpoint를 배포한 후에만 `KAKAO_BACKEND_AUTH_PATH=/api/v1/auth/oauth2/kakao`를 실행 인수로 전달합니다.

## 7. 실행 환경 설정

비밀 값은 커밋하지 말고 CI/CD의 secret 또는 로컬 전용 `--dart-define`으로 주입합니다. Native App Key와 OAuth client ID는 일반적으로 비밀은 아니지만, 환경별 값 혼선을 막기 위해 같은 방식으로 관리하는 것을 권장합니다.

```sh
flutter run \
  --dart-define=KAKAO_NATIVE_APP_KEY=YOUR_KAKAO_NATIVE_APP_KEY \
  --dart-define=KAKAO_BACKEND_AUTH_PATH=/api/v1/auth/oauth2/kakao \
  --dart-define=GOOGLE_CLIENT_ID=YOUR_IOS_CLIENT_ID \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_GOOGLE_WEB_CLIENT_ID \
  --dart-define=APPLE_SERVICE_ID=YOUR_APPLE_SERVICE_ID \
  --dart-define=APPLE_REDIRECT_URI=https://YOUR_DOMAIN/auth/apple/callback
```

- iOS에서 `GOOGLE_CLIENT_ID`는 iOS OAuth client ID입니다.
- `GOOGLE_SERVER_CLIENT_ID`는 서버용 Web OAuth client ID입니다.
- Android Apple 로그인에만 `APPLE_SERVICE_ID`와 `APPLE_REDIRECT_URI`가 필요합니다. iOS Apple 로그인은 네이티브 capability를 사용합니다.
- Kakao 서버 endpoint가 미배포 상태라면 `KAKAO_BACKEND_AUTH_PATH`를 빼고 실행합니다.

## 8. 플랫폼 보안 설정

- `flutter_secure_storage`를 사용합니다. iOS는 Keychain, Android는 Keystore로 토큰을 암호화합니다.
- Android manifest에는 `android:allowBackup="false"`가 설정되어 있습니다. 암호화 키와 백업 데이터가 어긋나 발생하는 복호화 오류를 막기 위해 제거하지 마세요.
- Android `minSdk`는 18 이상이어야 합니다. 현재 Flutter 기본값이 이를 충족하는지 `android/app/build.gradle.kts`에서 확인합니다.
- iOS 앱을 다른 Apple 개발팀으로 이전하거나 bundle identifier를 바꾸면 Keychain 접근 범위가 달라질 수 있으므로, 기존 사용자는 다시 로그인하도록 안내합니다.

## 9. 배포 전 필수 검증 체크리스트

- [ ] `scripts/bootstrap.sh`를 실행해 의존성을 설치합니다. 이 프로젝트는 빌드 출력 경로 `tmp_build`를 `/private/tmp`에 연결합니다.
- [ ] `flutter analyze`와 `flutter test`가 통과합니다.
- [ ] Android 실기기에서 Google 로그인, 앱 종료 후 재실행, 로그아웃을 확인합니다.
- [ ] iOS 실기기에서 Google 로그인, Apple 로그인, 앱 종료 후 재실행, 로그아웃을 확인합니다.
- [ ] Kakao 서버 endpoint 배포 후 Android와 iOS에서 Kakao 로그인과 JWT 교환을 확인합니다.
- [ ] access token을 짧게 발급해 refresh token 갱신을 확인합니다.
- [ ] refresh token을 서버에서 폐기한 뒤 보호 API가 401/403을 반환하고 앱이 로그인 화면으로 이동하는지 확인합니다.
- [ ] 네트워크 단절, OAuth 취소, 서버 4xx/5xx에서 사용자에게 토큰이나 원문 오류가 노출되지 않는지 확인합니다.
- [ ] 릴리즈 서명 SHA-1/SHA-256, iOS bundle ID, redirect URI가 각 공급자 콘솔의 운영 값과 일치하는지 재확인합니다.

## 10. 개발 계정 사용 원칙

`개발 계정으로 시작`은 디버그 빌드 또는 `--dart-define=SHOW_DEV_LOGIN=true`에서만 노출됩니다. 운영 릴리즈에서는 개발 계정 endpoint를 비활성화하거나 네트워크 레벨에서 차단해야 합니다.
