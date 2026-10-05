# CampOn App Store 출시 체크리스트

최종 검증: 2026-08-08. 아래 상태는 모두 이 날짜에 실제로 실행하거나 파일을 열어 확인한 결과다.
추측으로 적은 항목은 없다. 다시 확인할 때는 각 항목의 "확인 방법"을 그대로 실행한다.
(2026-08-01 판 이후 변경분: 즐겨찾기·커뮤니티 신고/차단 기능이 추가로 커밋됐고, 백엔드가
`PostResponseDto`에 `authorId`를 추가했다. 아래에 반영했다.)

---

## A. 제출을 막는 블로커

이 네 가지가 해결되기 전에는 App Store Connect 업로드 자체가 불가능하거나, 업로드해도 심사에서
리젝된다.

### A-1. 앱 아이콘 — 해결됨 (2026-08-01)

기존에는 파란 Flutter 기본 로고가 그대로 들어 있었다. 플레이스홀더 아이콘은 Guideline 2.3.8
리젝 사유이고, 애초에 Flutter의 상표라 배포할 수 없었다.

`scripts/generate_app_icon.py`로 브랜드 아이콘을 만들어 15개 사이즈 전부 교체했다. 밤 숲
그라데이션 위에 앰버색 A형 텐트와 별을 얹은 그림이고, 색은 `lib/theme.dart`의 `CampColors`
계열을 쓴다. 알파 채널이 없고 모서리를 직접 깎지 않았다(iOS가 자동으로 처리한다).

- [x] 확인함: `sips -g hasAlpha -g pixelWidth .../Icon-App-1024x1024@1x.png` → `hasAlpha: no`, `pixelWidth: 1024`
- [ ] **디자이너 검토는 아직 받지 않았다.** 그림을 바꾸려면 스크립트의 좌표·색만 고치고 다시 실행하면 15개 사이즈가 함께 갱신된다.

### A-2. Bundle ID — `com.seohamin.camp.dev`로 결정됨 (2026-08-01)

`com.seohamin.camping`으로 전환하지 않고 현재 값 `com.seohamin.camp.dev`로 출시하기로 했다.
Kakao 등록도 이 ID에 맞춘다.

App Store는 bundle ID 문자열에 규칙이 없으므로 `.dev`가 들어가도 심사에서 막히지 않는다. 다만
**App Store Connect에 앱 레코드를 만드는 순간 이 값은 영구 고정된다.** 나중에 바꾸려면 완전히 새
앱으로 다시 출시해야 하고 사용자·리뷰·순위를 모두 잃는다. 레코드를 만들기 전이 마지막 되돌릴
기회다.

프로젝트 쪽은 정리를 마쳤다. RunnerTests 타깃만 `com.seohamin.camping.RunnerTests`로 남아 있어
자동 서명이 소유하지 않은 네임스페이스를 등록하려 드는 상태였는데, `com.seohamin.camp.dev.RunnerTests`로
맞췄다. 이제 `ios/` 아래에 `com.seohamin.camping` 참조가 없다.

콘솔과 서버에서 이 ID로 맞춰야 하는 것들:

- [ ] **Apple Developer의 명시적 App ID `com.seohamin.camp.dev`.** Sign in with Apple을 활성화하고
      이 App ID 기준 Distribution provisioning profile을 만든다. 와일드카드 `*` 프로파일은
      Sign in with Apple을 지원하지 않으므로 쓸 수 없다.
- [ ] **백엔드의 Apple 토큰 audience.** 네이티브 iOS 로그인에서 Apple이 주는 토큰의 `aud` 클레임은
      bundle ID 그 자체다. 서버가 `com.seohamin.camping`만 허용하고 있으면 **Apple 로그인이 전부
      거부된다.** 코드의 `APPLE_SERVICE_ID` 기본값이 `com.seohamin.camping`인 것으로 보아 그렇게
      설정돼 있을 가능성이 높으니 반드시 확인한다.
- [x] **Google OAuth iOS client** — 이미 `com.seohamin.camp.dev`로 등록돼 있다 (2026-08-01 확인).
      저장소 설정도 일관된 것을 `Info.plist` 파싱으로 확인했다. `GIDClientID`가 `GIDServerClientID`와
      구분돼 있고(iOS 전용 client가 발급됨), reversed URL scheme이 `GIDClientID`와 일치한다.
- [ ] **Kakao Developers의 iOS bundle ID**를 `com.seohamin.camp.dev`로 등록한다.
- [x] 확인함: `grep -rn "com.seohamin.camping" ios/` 결과가 비어 있다.

알아둘 점: Android `applicationId`는 여전히 `com.seohamin.camping`이라 두 플랫폼의 식별자가
갈라진다. 기술적으로 문제는 없지만(Kakao/Google 모두 플랫폼별로 따로 등록한다) 설정할 곳마다
어느 쪽인지 확인해야 한다. Play 출시 때 Android를 어느 쪽으로 갈지 별도로 정한다.

### A-3. Team `Q5U58YNG6X`가 유료 Apple Developer Program 계정인지 확인

A-2에서 `com.seohamin.camp.dev`로 가기로 하면서, 남의 팀 소유인 `com.seohamin.camping`에
접근할 필요는 없어졌다. 대신 **현재 팀 `Q5U58YNG6X`로 실제 배포가 가능한지**가 남는다.

`docs/ios-device-runbook.md` 4절에 기록된 빌드 실패를 다시 보면 두 번째 줄이 걸린다.

```text
Failed Registering Bundle Identifier: com.seohamin.camping
Provisioning profile "iOS Team Provisioning Profile: *" doesn't support the Sign in with Apple capability.
```

첫 줄은 남의 네임스페이스라 그렇다 치더라도, **두 번째 줄은 무료 개인 팀에서도 똑같이 난다.**
무료 Apple ID 팀은 기기에 직접 설치하는 개발 빌드까지만 되고, App Store 배포도 Sign in with Apple
capability도 쓸 수 없다. 이 앱은 소셜 로그인을 제공하므로 Guideline 4.8에 따라 Sign in with Apple이
**필수**라, 무료 팀이면 출시 자체가 불가능하다.

- [x] **`Q5U58YNG6X`는 유료 Apple Developer Program 계정이다** (2026-08-01 확인). 따라서 배포와
      Sign in with Apple 모두 가능하다. 위 오류의 두 번째 줄은 와일드카드 프로파일을 썼기 때문이며,
      아래처럼 명시적 App ID로 프로파일을 만들면 해소된다.
- [ ] `Identifiers`에서 `com.seohamin.camp.dev` App ID에 Sign in with Apple을 활성화한다.
- [ ] 이 명시적 App ID 기준 Distribution provisioning profile을 만든다 (와일드카드 금지).
- [ ] 확인 방법: `flutter build ipa`가 서명 오류 없이 끝난다.

참고: 이 문서 이전 판에는 Team `SNPYTZYZF4`가 적혀 있었으나 근거가 없어 폐기한다. 실제 프로젝트
설정값은 `Q5U58YNG6X`이고(`project.pbxproj` 3곳), 이 팀으로 출시한다.

### A-4. 개인정보 처리방침과 이용약관 — 앱 내 열람은 가능, 공개 URL은 필요

로그인 화면에는 "로그인하면 CampOn 이용약관과 개인정보 처리방침에 동의하는 것으로 간주됩니다"라는
문구가 있는데, 이전에는 **탭할 수 없는 순수 텍스트**였다. 동의를 받는다면서 읽을 수단이 없어
Guideline 5.1.1 리젝 사유였다.

이제 로그인 화면과 설정 화면 양쪽에서 이용약관과 개인정보 처리방침을 열 수 있다. 공개 URL이
주입되지 않은 빌드는 앱 안의 문서를 열고, `PRIVACY_POLICY_URL` 또는 `TERMS_OF_SERVICE_URL`이
주입된 릴리스 빌드는 공개 문서를 연다 (`lib/main.dart`의 `LegalLinkRow`).

- [x] **개인정보 처리방침 공개 URL 확보함 (2026-08-08).**
      `https://agreeable-canary-131.notion.site/3a7214c948c380d68380f982437ddd7d` —
      Notion에서 이미 작성·게시(Publish to web)되어 있는 것을 확인했고, 쿠키 없는 `curl`로
      로그인 없이 열리는 것도 확인했다(`http=200`). 릴리스 빌드의 `PRIVACY_POLICY_URL`로 이
      값을 쓰면 된다.
- [x] **Notion 게시본과 저장소 문서의 담당자 정보 불일치를 해소함.** 이전에는 담당자
      이메일이 Notion `shm040806@gmail.com`과 `docs/privacy-policy.md`/앱 설정
      `vmfhrmfoald36@gmail.com`으로 서로 달랐다. Notion 게시본(서하민 /
      shm040806@gmail.com / 010-4864-1548)을 최종본으로 확정해, `docs/privacy-policy.md`,
      `lib/main.dart`의 개인정보 처리방침 본문, `docs/terms-of-service.md`,
      `LegalConfig.contactEmail` 기본값(`LEGAL_CONTACT_EMAIL`)을 모두 이 정보로 맞췄다.
- [ ] 이용약관도 같은 방식으로 실제 URL에 게시한다. 게시 원문은 `docs/terms-of-service.md`다.
      (이번에 확보한 건 개인정보 처리방침뿐이고, 이용약관 공개 URL은 아직 없다.)
- [ ] **Gemini API 등급을 확인한다.** 무료 등급이면 Google이 입력 내용을 품질 개선에 활용할 수
      있어 처리방침 문구와 App Privacy 답변이 달라질 수 있다. 실제 사용 등급과 Google의 데이터
      취급 조건을 확인해 공개 문서에 반영한다.
- [ ] 제출 빌드에 두 값을 넣는다:
      `--dart-define=PRIVACY_POLICY_URL=... --dart-define=TERMS_OF_SERVICE_URL=...`
      `--dart-define=LEGAL_CONTACT_EMAIL=...`도 공개 문서의 문의 메일과 같게 넣는다. 아카이브 후
      로그인과 설정 화면에서 두 문서를 눈으로 확인한다.
- [ ] 지원(문의) URL 또는 이메일을 확정한다 — App Store Connect 필수.

확인 방법: `flutter test test/legal_documents_test.dart`

---

## B. 이미 처리되어 확인된 항목

다시 손댈 필요 없다. 괄호 안은 확인 근거다.

- [x] **정적 분석 통과** — `flutter analyze` → `No issues found! (ran in 2.9s)` (2026-08-08 재확인)
- [x] **테스트 통과** — `flutter test` → `148 tests, All tests passed!` (2026-08-08 재확인, 91 → 148은
      즐겨찾기·커뮤니티 신고/차단 테스트가 늘어난 것)
- [x] **회원탈퇴 기능** (Guideline 5.1.1(v) 필수) — 설정 화면에 확인 다이얼로그가 있고
      (`lib/main.dart:2827`) `DELETE /api/v1/users`를 호출한 뒤 제공자 로그아웃과 로컬 세션을
      정리한다 (`lib/main.dart:4494`).
- [x] **Privacy Manifest** — `ios/Runner/PrivacyInfo.xcprivacy` 존재. 추적 없음
      (`NSPrivacyTracking=false`), 필수 사유 API는 UserDefaults(CA92.1)와 FileTimestamp(C617.1)로
      선언되어 있다. 수집 항목은 이메일·이름·User ID·정밀 위치·이용자 콘텐츠를 앱 기능 목적·비추적으로
      선언한다.

      **2026-08-01에 정밀 위치를 추가했다.** 그전까지는 이메일·이름·User ID만 선언되어 있었는데,
      앱은 `Geolocator`로 받은 기기 좌표(정확도 100m)를 인증된 요청으로
      `GET /api/v1/directions`에 보내고 있었다(`lib/main.dart`의 `fetchDirections`,
      `lib/location/location_service.dart`). 즉 위치가 실제로 기기 밖으로 나가는데 매니페스트에는
      없었다. 선언이 실제 동작과 다르면 리젝 사유이므로 채웠다.

- [x] **수출 규정 응답** — `ITSAppUsesNonExemptEncryption=false` (Info.plist). 표준 HTTPS만 쓰므로
      맞는 값이다. 이게 있으면 업로드마다 묻는 절차를 건너뛴다.
- [x] **Sign in with Apple** (Guideline 4.8) — Google·Kakao 소셜 로그인을 제공하므로 필수인데,
      `Runner.entitlements`에 `com.apple.developer.applesignin`이 있고 구현도 되어 있다.
      단, A-3의 provisioning profile이 이 entitlement를 포함해야 실제로 동작한다.
- [x] **위치 권한 사용 설명** — `NSLocationWhenInUseUsageDescription`에 용도가 구체적으로 적혀 있고
      ("선택한 캠핑장까지의 거리와 이동 시간을 알려드리기 위해"), 코드도 WhenInUse만 요청한다
      (`lib/location/location_service.dart`). Always 권한은 쓰지 않으므로 추가 설명 불필요.
- [x] **앱 표시 이름** — `CFBundleDisplayName = CampOn`
- [x] **비밀 파일이 저장소에 없음** — `git ls-files`에 `.env`, keystore, `key.properties`,
      `GoogleService-Info.plist` 없음. `.example` 파일만 추적된다.
- [x] **iOS 최소 지원 버전** — 13.0 (Podfile과 pbxproj 일치)

---

## C. 심사는 통과하겠지만 고치는 편이 좋은 것

2026-08-01에 아래 네 개를 처리했다.

- [x] **설정 화면 앱 버전 하드코딩 제거.** `'1.0.0'` 문자열이 박혀 있어 `pubspec.yaml` 버전을
      올려도 화면이 따라오지 않았다. `package_info_plus`를 직접 의존성에 추가하고 번들에서
      `버전 (빌드번호)`를 읽어 표시한다(`AppVersionRow`).
- [x] **API 서버 호스트를 디버그 빌드로 한정.** `campon.seohamin.com`이 사용자에게 그대로
      보이던 행을 `kDebugMode`로 감쌌다.
- [x] **런치 스크린 교체.** `LaunchImage`가 68바이트짜리 기본 투명 이미지라 흰 화면만 떴다.
      아이콘과 같은 텐트 마크를 넣고 스토리보드 배경을 로그인 화면과 같은 숲 그린(`#1E3A2B`)으로
      바꿔, 실행 직후 흰 화면이 번쩍이지 않게 했다. 마크도 `generate_app_icon.py`가 함께 만든다.
- [x] **런북의 값 불일치 수정.** `docs/ios-device-runbook.md` 3절 표의 Bundle ID, Kakao URL
      scheme, Google client ID가 모두 실제 설정과 달랐다. 실제 값으로 고치고 확인 날짜를 적었다.

남은 것:

- [ ] **의존성 32개가 구버전이다.** `flutter_secure_storage 9.2.4`(10.3.1 있음) 등. 출시 직전
      메이저 업그레이드는 위험하니 출시 후에 처리한다.
- [x] **"주변 캠핑장" 지도 탭이 빈 화면으로 뜨던 문제를 고쳤다.** 2026-08-08 실기기(iPhone)에서
      최초 재현: 지도 탭을 열면 카카오맵이 전혀 렌더링되지 않았다. `nearby` API 자체는 정상
      응답하므로(직접 호출로 확인, `radius<=20000`에서 목록 정상 반환) 문제는 `kakao_map_plugin`의
      WebView 로딩 단계였다. 원인이 두 겹이라 두 번에 걸쳐 고쳤다.

      **1차 원인 (해결됨): `baseUrl`이 없어 origin이 opaque였다.** `AuthRepository.initialize`를
      `baseUrl` 없이 호출하면 iOS WKWebView가 HTML을 opaque origin으로 로드해서 카카오맵 JS
      SDK(`dapi.kakao.com/v2/maps/sdk.js`) 요청의 `Referer`가 문자열 `"null"`로 찍힌다. 카카오는
      이를 미등록 도메인으로 보고 401 `AccessDeniedError: domain mismatched! caller=null`을
      돌려준다. `AuthConfig.kakaoMapBaseUrl`(dart-define `KAKAO_MAP_BASE_URL`)을 추가해 해결했고,
      카카오 디벨로퍼스 콘솔의 "플랫폼 > Web" 등록도 완료되었다(2026-08-20 확인:
      `Referer: https://localhost/`와 `http://localhost/` 모두 200, 미등록 도메인은 여전히 401).

      **2차 원인 (해결됨): `baseUrl`이 `http`라 지도 엔진이 ATS에 막혔다.** 콘솔 등록이 끝난
      뒤에도 지도가 그대로 빈 화면이었다. `sdk.js`는 로더 스텁일 뿐이고, 그 안에서
      `s = "https:" == location.protocol ? "https:" : "http:"`로 실제 지도 엔진
      (`t1.daumcdn.net/mapjsapi/js/main/4.5.26/kakao.js`)과 타일(`mts.daumcdn.net`)의 주소를
      만든다. `baseUrl`이 `http://localhost`면 엔진을 평문 HTTP로 받으려 하는데 iOS ATS가
      이를 차단한다(`ios/Runner/Info.plist`에 `NSAppTransportSecurity` 예외 없음. 안드로이드도
      API 28+ 기본 cleartext 차단이라 동일). 그래서 `kakao.maps.load` 콜백이 끝내 호출되지 않고
      `window.kakao`만 정의된 채 지도가 그려지지 않는다.

      **재현/검증 (2026-08-20, iPhone 17 시뮬레이터):** 같은 페이지를 `baseUrl`만 바꿔 나란히
      띄우는 프로브 앱으로 A/B 확인 —
      `http://localhost` → `kakao.maps.load` 콜백이 10초 안에 호출되지 않음(빈 화면),
      `https://localhost` → `map created, center=(37.566…, 126.977…)`.
      서버 쪽은 http/https 둘 다 200이므로 차이는 순수하게 클라이언트의 평문 차단이다.

      **조치:** `AuthConfig.kakaoMapBaseUrl`의 기본값을 `https://localhost`로 바꾸고
      `dart_defines.json`도 맞췄다. `KAKAO_MAP_BASE_URL`을 덮어쓸 때도 **반드시 `https://`**를
      써야 하며, 그 도메인이 콘솔의 "플랫폼 > Web"에 등록되어 있어야 한다.
      확인 방법: `curl -s -o /dev/null -w "%{http_code}" -H "Referer: https://localhost/" "https://dapi.kakao.com/v2/maps/sdk.js?appkey=$KAKAO_JAVASCRIPT_KEY"` → 200이면 등록 완료.


---

## D. 제출 직전 실제로 해야 할 순서

A 블로커를 모두 해결한 뒤에 진행한다.

1. [ ] `pubspec.yaml`의 `version`을 확정한다 (현재 `1.0.0+1`). 재업로드할 때마다 빌드 번호를 올려야 한다.
2. [ ] 운영 dart-define 값을 확정한다. `AUTH_LOGIN_NOTES.md` 58행에 로그인 관련 목록이 있다.
       `KAKAO_NATIVE_APP_KEY`, `KAKAO_JAVASCRIPT_KEY`, `KAKAO_MAP_BASE_URL`(카카오 콘솔에
       이미 다른 도메인을 등록해 뒀다면 기본값 `https://localhost` 대신 그 값으로 맞춘다. 반드시
       `https://`여야 한다 — C절의 지도 빈 화면 항목 참고), `GOOGLE_CLIENT_ID`,
       `GOOGLE_SERVER_CLIENT_ID`, `APPLE_SERVICE_ID`, `APPLE_REDIRECT_URI`,
       `PRIVACY_POLICY_URL=https://agreeable-canary-131.notion.site/3a7214c948c380d68380f982437ddd7d`
       (A-4에서 확보함 — 단, 담당자 이메일·시행일 불일치를 먼저 정리한다), 그리고 아직 없는
       `TERMS_OF_SERVICE_URL`.
       **`SHOW_DEV_LOGIN`은 절대 넣지 않는다** — 넣으면 개발 계정 로그인 버튼이 심사자에게 노출된다.
       (릴리즈 빌드에서는 `kDebugMode`가 false라 기본적으로 숨겨진다. `lib/main.dart:91`)
3. [ ] `./scripts/bootstrap.sh`를 실행한다. 이 프로젝트는 iCloud 동기화 폴더 안에 있어
       `tmp_build` 심링크가 없으면 codesign이 실패한다.
4. [ ] `flutter build ipa --release --dart-define=...` 로 아카이브를 만든다.
5. [ ] AI 프록시의 실제 URL을 `PLAN_PROXY_URL`로 넣고 `/api/plan`, `/api/preview`를 실기기에서
       확인한다. 현재 기본값 `campon-ai-proxy.azurewebsites.net`은 DNS 해석에 실패하므로, 이 값을
       그대로 제출하면 AI 기능은 로컬 폴백만 표시한다.
6. [ ] TestFlight에 업로드하고 **실제 기기에서** 로그인 3종(Google/Apple/Kakao)의 성공과 취소를
       각각 확인한다. 시뮬레이터로는 검증되지 않는다.
7. [ ] 네트워크 실패, 토큰 만료, 빈 캠핑장 목록, 이미지 로딩 실패 상태를 확인한다.
       [ ] "주변 캠핑장" 지도 탭이 실제로 렌더링되는지 확인한다 (C절의 미해결 지도 버그 참고).
8. [ ] 작은 화면(iPhone SE)과 큰 화면에서 텍스트 잘림을 확인한다.

## E. App Store Connect에 입력할 것

앱 레코드를 만들면서 채운다.

- [ ] 앱 이름, 부제, 프로모션 텍스트, 설명, 키워드
- [x] 개인정보 처리방침 URL (필수) — 위 A-4에서 확보함:
      `https://agreeable-canary-131.notion.site/3a7214c948c380d68380f982437ddd7d`
- [ ] 지원 URL (필수)
- [ ] 스크린샷. 기존 `screenshots/`의 6장은 App Store 규격에 맞지 않는다(1206×2622px — 6.9인치
      1320×2868, 6.5인치 1284×2778 어디에도 해당하지 않음). 2026-08-08에 정확한 해상도의
      시뮬레이터(iPhone 17 Pro Max = 6.9인치, iPhone 12 Pro Max = 6.5인치)로 로그인 화면만
      새로 찍어 `screenshots/6.9-inch/01_login.png`(1320×2868), `screenshots/6.5-inch/01_login.png`
      (1284×2778)에 저장해 뒀다. **나머지 5장(홈/둘러보기/체크리스트/설정/추천)은 아직 못 찍었다** —
      시뮬레이터에서 화면을 넘기려면 이 기기의 손쉬운 사용(Accessibility) 권한이 있어야 하는데
      권한을 받지 못해 중단했다. 필요하면 이어서 진행한다.
      **App Store Connect 업로드는 아직 안 했다** — Apple ID 로그인(대개 2단계 인증 포함)이 필요해
      대신할 수 없다. 위 파일을 앱 레코드의 해당 사이즈 슬롯에 직접 올려야 한다.
- [ ] App Privacy 설문. `PrivacyInfo.xcprivacy`의 선언(이메일·이름·User ID·정확한 위치·이용자 콘텐츠,
      비추적)과 일치시키되,
      **백엔드가 실제로 저장하는 데이터 기준으로 다시 확인한다.** 앱 매니페스트와 서버 실제 동작이
      다르면 그쪽이 문제가 된다.
- [ ] 릴리스 빌드에 `PRIVACY_POLICY_URL`, `TERMS_OF_SERVICE_URL`, `LEGAL_CONTACT_EMAIL`을 설정한다.
      URL이 없을 때에도 앱 내 문서는 열리지만, App Store Connect에는 공개 HTTPS 개인정보 처리방침 URL이
      필요하다.
- [x] **커뮤니티 신고·차단** — 2026-08-08 확인. 게시글 더보기 메뉴에 신고(`POST
    /api/v1/posts/{id}/reports`)와 유저 차단(`POST /api/v1/blocks`)이 구현되어 있고, 차단한
      유저의 글은 목록에서 즉시 숨겨진다(`lib/main.dart`의 `postMenuActions`,
      `BlockManagementScreen`). 백엔드가 `PostResponseDto.authorId`를 실제로 내려주는 것을
      운영 서버에 직접 왕복 호출해 확인했다(`{"id":2,"authorId":1,...}`) — 이전 판에 있던
      "authorId가 없어 차단 메뉴가 안 뜬다"는 문제는 해소됐다. - [ ] 다만 이건 신고·차단 UI가 "존재"하고 "동작"한다는 것만 확인한 것이다. 신고가 접수된 뒤
      운영자가 실제로 검토·조치하는 프로세스(백엔드/운영 쪽)는 이 저장소 범위 밖이라 확인할
      수 없다. Guideline 1.2는 이 처리 프로세스까지 요구하므로 별도로 확인한다. - [ ] 서버가 작성자 닉네임(`authorNickname`)은 아직 내려주지 않아, 차단 관리 화면에는
      "유저 #7"처럼 번호로만 뜬다. 기능은 동작하지만 UX가 거칠다 —
      `docs/backend-request-post-author.md`에 요청해 둔 권장 사항 중 닉네임 항목만 남았다.
- [x] 연령 등급 설문
- [ ] 심사 메모: 심사자용 테스트 계정을 제공한다. 소셜 로그인만 있는 앱은 심사자가 로그인할 수단이
      없어 Guideline 2.1로 리젝되는 경우가 많다. **이 항목을 빠뜨리지 않는다.**

---

## F. Android (Play Store) — 참고

이번 App Store 출시 범위 밖이지만 기록해 둔다.

- Android `applicationId`는 `com.seohamin.camping`으로 이미 운영 값이다 (iOS와 달리 dev 접미사 없음).
- [ ] **release 빌드가 debug 키로 서명된다.** `android/app/build.gradle.kts:39`가
      `signingConfig = signingConfigs.getByName("debug")`다. 이대로는 Play 업로드가 불가능하다.
      release keystore와 `key.properties`를 만들어 교체해야 한다.
- [ ] Google OAuth에 Android package name과 SHA-1/SHA-256 지문을 등록한다.
- [ ] Kakao Developers에 Android package name과 key hash를 등록한다.
