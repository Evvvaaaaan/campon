# App Store Connect App Privacy 입력 기준

작성일: 2026년 8월 3일

이 문서는 현재 Flutter 앱 코드와 프록시 구현을 기준으로 만든 제출용 점검표입니다. 서버의 실제
저장·로그 정책이 다르면 서버의 실제 동작에 맞춰 수정해야 합니다.

## 추적 여부

- **Data Used to Track You: 없음**
- 광고 SDK, IDFA, 제3자 광고 식별자 결합을 사용하지 않습니다.

## 수집 데이터

| App Store Connect 분류 | 연결됨 | 추적 | 목적 | 코드 근거 |
| --- | --- | --- | --- | --- |
| Contact Info > Email Address | 예 | 아니오 | App Functionality | 소셜 로그인·계정 |
| Contact Info > Name | 예 | 아니오 | App Functionality | 소셜 로그인·계정 |
| Identifiers > User ID | 예 | 아니오 | App Functionality | 소셜 로그인 제공자 식별자·계정 |
| Location > Precise Location | 예 | 아니오 | App Functionality | 길찾기, 주변·날씨 기능 |
| User Content > Other User Content | 예 | 아니오 | App Functionality | 커뮤니티 글, 플래너 질문 |

즐겨찾기와 일부 앱 설정은 기기에만 저장합니다. 단, 외부 SDK의 실제 데이터 처리와 백엔드 로그
정책은 제출 직전에 각 제공자 문서와 서버 담당자에게 다시 확인해야 합니다.

## 제출 전 필수 확인

1. `docs/privacy-policy.md`와 `docs/terms-of-service.md`를 공개 HTTPS 주소에 게시합니다.
2. 개인정보 처리방침 URL, 지원 URL, 심사 연락처를 App Store Connect에 입력합니다.
3. 릴리스 빌드에 `PRIVACY_POLICY_URL`, `TERMS_OF_SERVICE_URL`, `LEGAL_CONTACT_EMAIL`을 넣습니다.
4. 커뮤니티를 출시한다면 신고, 차단, 부적절한 콘텐츠 필터링·검토, 운영자 연락처를 실제로 제공합니다.
5. 계정 기반 앱이므로 심사용 계정 또는 전체 기능을 볼 수 있는 데모 흐름을 심사 메모에 제공합니다.
