# CampOn Development Notes

## 확인한 API

- Swagger UI: `https://campon.seohamin.com/api/swagger`
- OpenAPI JSON: `https://campon.seohamin.com/api/swagger-ui/v3/api-docs`
- 앱 구현 base URL: `https://campon.seohamin.com`
- 사용 중인 엔드포인트:
  - `GET /api/v1/auth/dev/token`
  - `GET /api/v1/campsites/nearby`
  - `GET /api/v1/campsites/recommend`
- Swagger에 추가 확인된 엔드포인트:
  - `GET/PUT/DELETE /api/v1/users`
  - `POST /api/v1/auth/oauth2/google`
  - `POST /api/v1/auth/oauth2/apple`
  - `POST /api/v1/auth/token/refresh`
  - `POST /api/v1/auth/dev/user`
  - `GET /api/v1/auth/dev/tourApiTest`

## 구현 결정

- Flutter 외부 패키지를 추가하지 않고 `dart:io`의 `HttpClient`로 API를 호출했습니다.
- OpenAPI의 server URL은 현재 `https://campon.seohamin.com`로 표시됩니다.
- Swagger 전역 보안 스키마가 `jwtAuth`이고 캠핑장 API는 JWT 없이 `403`을 반환하므로, 개발 빌드에서는 `GET /api/v1/auth/dev/token?userId=1`로 받은 토큰을 `Authorization: Bearer ...` 헤더로 보냅니다.
- 앱 시작 화면에 로그인 페이지를 추가했습니다. 빈 OAuth code 요청은 서버에서 `400 INVALID_REQUEST`가 발생하므로 앱에서 먼저 차단합니다.
- Google/Apple 로그인은 native SDK에서 받은 authorization code를 서버 OAuth 엔드포인트로 전송합니다.
- Kakao native SDK 로그인은 클라이언트에 연결했지만, 2026-07-10 Swagger에는 Kakao JWT 교환 엔드포인트가 없습니다.
- `GET /api/v1/campsites/nearby`는 `radius=70000`에서 `400 INVALID_REQUEST`가 재현되어 앱 조회 반경을 `10000`으로 낮췄습니다.
- 추천 API의 배열 쿼리는 반복 파라미터 형식으로 보냅니다. 선택값이 없을 때는 `preferredConditions=&equipments=`를 보냅니다.
- 전체 캠핑장 목록 API가 명세에 없어, "모든 캠핑장" 화면은 선택 지역 중심의 `nearby` API로 구현했습니다.

## 확인 필요

- 날씨 리스크, 이용 후기, 커뮤니티 게시글 API는 2026-07-10 Swagger 명세에 없습니다. 앱에는 디자인 흐름을 유지하기 위한 안내/샘플 텍스트를 넣었습니다.
- 캠핑 숙련도와 가족 동반 여부는 2026-07-10 기준 추천 API 파라미터에 없습니다. UI에는 반영했지만 서버 추천에는 직접 전달하지 못합니다.
- 전국 전체 목록 API는 2026-07-10 Swagger 명세에 없습니다. 필요하면 별도 엔드포인트가 필요하고, 없으면 현재처럼 지역 중심 `nearby`를 유지하면 됩니다.
- 사용자 선호 저장은 `GET/PUT/DELETE /api/v1/users`가 명세에 있으나 현재 앱 온보딩은 로컬 상태만 사용합니다. 로그인/사용자 저장 흐름을 붙일 때 이 API로 연결하면 됩니다.
