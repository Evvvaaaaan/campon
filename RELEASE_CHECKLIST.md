# CampOn Release Checklist

## 앱스토어 심사 필수 (2026-07-24 반영)

이번 작업에서 코드/설정으로 처리한 항목과, 여전히 팀 액션이 필요한 항목을 구분한다.

완료 (device release 빌드 산출물에서 확인함):

- [x] 회원탈퇴 기능 제공. 설정 화면에서 `DELETE /api/v1/users` 호출 (Guideline 5.1.1(v) 필수).
- [x] 앱 Privacy Manifest 추가. `ios/Runner/PrivacyInfo.xcprivacy`를 Runner 타깃 리소스로 연결했고 번들 포함을 확인했다.
      추적 없음(`NSPrivacyTracking=false`), 수집 데이터는 로그인용 이메일·이름·User ID(앱 기능 목적, 비추적),
      필수 사유 API는 UserDefaults(CA92.1)·FileTimestamp(C617.1)로 선언했다.
- [x] 수출 규정 응답 `ITSAppUsesNonExemptEncryption=false`를 `ios/Runner/Info.plist`에 추가했다 (표준 HTTPS만 사용).
- [x] `CFBundleDisplayName`을 `CampOn`으로 정리했다.
- [x] `pubspec.yaml` description을 실제 앱 설명으로 교체했다.

팀 액션 필요:

- [ ] **Bundle ID 확인.** 현재 프로젝트는 개발용 `com.seohamin.camp.dev`로 빌드된다. 운영 제출 전
      `com.seohamin.camping`으로 전환하되, Apple App ID·프로비저닝, Google/Kakao/Apple redirect,
      백엔드 식별자를 함께 맞춰야 한다. 로컬에서 값만 바꾸지 않는다.
- [ ] App Store Connect **App Privacy 설문**을 위 Privacy Manifest와 일치시키고, 백엔드가 실제 저장하는
      데이터 기준으로 재확인한다.
- [ ] 개인정보 처리방침 URL, 지원 URL을 확정해 App Store Connect에 등록한다 (계정 기반 앱 필수).

## 계정과 서명

- Xcode에 Apple Developer 계정을 추가한다.
- Team `SNPYTZYZF4`에 앱 배포 권한이 있는지 확인한다.
- Bundle ID `com.seohamin.camping`으로 iOS App ID와 provisioning profile을 생성한다.
- 현재 Xcode `PRODUCT_BUNDLE_IDENTIFIER`는 개발용 `com.seohamin.camp.dev`다. 운영 제출 전 위 운영 ID로 전환한다.
- Android release signing key와 `key.properties`를 준비한다.
- Google Play Console과 App Store Connect에 앱 레코드를 생성한다.

## 로그인

- Google OAuth에 Android package name `com.seohamin.camping`과 SHA-1/SHA-256을 등록한다.
- Google iOS client ID가 있다면 `ios/Runner/Info.plist`의 reversed client ID를 iOS client 기준으로 교체한다.
- Kakao Native App Key를 발급하고 Android/iOS URL scheme을 `kakao{native_app_key}`로 교체한다.
- Kakao Developers에 Android package name, key hash, iOS bundle ID를 등록한다.
- Apple Sign in capability를 Xcode에서 활성화한다.
- Android Apple 로그인까지 지원할 경우 `APPLE_SERVICE_ID`, `APPLE_REDIRECT_URI`를 확정한다.
- 운영 빌드에는 `SHOW_DEV_LOGIN=true`를 넣지 않는다.

## 서버

- Kakao JWT 교환 API 경로를 확정하고 `KAKAO_BACKEND_AUTH_PATH`에 반영한다.
- Google, Apple, Kakao 로그인 응답이 `accessToken`, `refreshToken`, `tokenType`, `exprTime`을 반환하는지 검증한다.
- refresh token API `/api/v1/auth/token/refresh`의 만료/오류 응답 정책을 확정한다.
- 캠핑장 추천 API와 근처 캠핑장 API의 radius 허용 범위를 운영 기준으로 확정한다.

## 앱 품질

- 실제 기기에서 Google, Apple, Kakao 로그인 성공과 취소 흐름을 각각 확인한다.
- 네트워크 실패, 토큰 만료, 빈 캠핑장 목록, 이미지 로딩 실패 상태를 확인한다.
- iPhone 작은 화면과 큰 화면, Android 주요 해상도에서 텍스트 잘림을 확인한다.
- 개인정보 처리방침, 이용약관, 고객 문의 채널을 앱 심사용 URL로 준비한다.
- 앱 아이콘, 스플래시 화면, 스토어 스크린샷, 앱 설명을 최종본으로 교체한다.

## 배포 빌드

- `flutter analyze`를 통과한다.
- `flutter test`를 통과한다.
- Android release build를 생성하고 설치 테스트를 완료한다.
- iOS archive를 생성하고 TestFlight 업로드를 완료한다.
