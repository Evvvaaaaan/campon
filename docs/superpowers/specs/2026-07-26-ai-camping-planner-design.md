# CampOn — AI 캠핑 플래너 & 전면 모션 리디자인 설계

날짜: 2026-07-26
목적: 대회 실제 시연 심사에서 창의성·독창성·트렌드(디자인)·편의성·기능성 전 항목 고득점.

## 1. 배경 / 현재 상태

- CampOn은 Flutter 단일 파일 앱(`lib/main.dart`, ~4660줄). 디자인 토큰(`CampColors`/`CampText`),
  API 레이어(`CampOnApi`), 화면 흐름(`AppStep` enum)이 한 파일 안에 정리돼 있음.
- 팔레트: Wood Amber(`#C1702F`) + Deep Forest Green(`#1E3A2B`) + Cream(`#F5EFE1`).
- 폰트: Black Han Sans(제목), Noto Sans KR(본문).
- 기존 흐름: 로그인 → 온보딩(기본→숙련도→선호) → 추천, 둘러보기, 상세, 체크리스트, 커뮤니티, 설정.
- 백엔드 `https://campon.seohamin.com` (Spring, JWT). 캠핑장 API는 JWT 필요.
  날씨/후기/커뮤니티 일부는 명세에 없음.
- 홈 화면이 이미 "추천부터 준비까지 한 흐름"을 카피로 약속하고 있으나, 실제로는 여러 화면을 수동으로 오가야 함.

## 2. 목표 (심사 기준 매핑)

| 심사 기준 | 승부처 |
|---|---|
| 창의성·독창성 | AI 캠핑 플래너 — 자연어 한 줄 → 캠핑장+날씨경보+준비물+타임라인 한 번에 생성 |
| 트렌드(디자인) | 기존 팔레트 유지 + 전면 모션·마이크로인터랙션·AI 스트리밍 리빌 |
| 편의성 | "한 흐름" 실현 — 온보딩 컨텍스트 자동 연결, 결과가 체크리스트로 바로 이어짐 |
| 기능성 | 실데이터 — 백엔드 캠핑장 API + 무료 Open-Meteo 날씨 + LLM 프록시 |

## 3. 결정 사항

- 킬러 기능: **AI 캠핑 플래너** (홈의 기존 "한 흐름" 약속을 실제 실현).
- LLM: **Google Gemini 2.0 Flash** (무료 티어, 한국어 품질, 구조화 JSON 출력). 프록시가 추상화하여
  추후 Groq 등으로 스왑 가능.
- 배포: **별도 경량 프록시**(Vercel 서버리스 함수) — 메인 백엔드 미수정, API 키는 프록시 환경변수에만.
- 날씨: **Open-Meteo**(무료·키 불필요).
- 리디자인: 기존 Amber/Forest 팔레트·폰트 유지 + **전면 모션 + 플래너 신규 화면**.

## 4. AI 플래너 화면 흐름

```
홈 "AI 플래너" CTA
  → 입력 화면 (자연어 한 줄 + 온보딩 컨텍스트 자동 채움)
  → 스트리밍 리빌 (섹션이 순차 등장)
     ① 캠핑 요약 카드 (한 줄 요약 + 무드)
     ② 추천 캠핑장 Top 3 (백엔드 데이터 + AI "왜 이곳인지" 설명)
     ③ 캠핑 날씨 리스크 (Open-Meteo → 야간최저·강수확률·풍속·일교차 → 안전등급 배지 + 조언)
     ④ 스마트 준비물 체크리스트 (AI 생성, 카테고리별)
     ⑤ 하루 타임라인 (도착→설치→저녁→취침→철수)
  → 액션: "체크리스트로 보내기"(기존 ChecklistScreen) / "캠핑장 상세"(기존 CampsiteDetailScreen)
```

## 5. 데이터 흐름

```
앱: 기존 fetchRecommendations/fetchNearby로 후보 캠핑장 확보 (JWT는 앱이 보유)
  → 프록시 POST /api/plan: { query(자연어), context(온보딩), coords(lat/lon), candidates[] }
프록시: Open-Meteo에서 좌표·날짜 날씨 조회
      → Gemini 2.0 Flash 호출 (구조화 JSON 출력, 후보/컨텍스트/날씨를 프롬프트에 주입)
      → 플랜 JSON 반환
```

- 프록시는 **무상태 + 백엔드 인증 불필요**. 후보 캠핑장은 앱이 넘겨줌.
- 프록시 실패/키 미설정 시 앱은 결정론적 폴백 플랜(로컬 규칙 기반)으로 화면을 채워 데모가 끊기지 않게 함.

### 플랜 JSON 계약

```json
{
  "summary": { "title": "string", "mood": "string", "oneLiner": "string" },
  "weather": {
    "grade": "good|caution|risk",
    "nightLowC": 12, "precipPct": 20, "windMs": 3.5, "diurnalRangeC": 14,
    "advice": "string"
  },
  "campsites": [ { "name": "string", "reason": "string" } ],
  "checklist": [ { "category": "string", "items": ["string"] } ],
  "timeline": [ { "time": "14:00", "title": "string", "detail": "string" } ]
}
```

입력 컨텍스트에 활용 가능한 필드: `CampRegion.lat/lon`, `Campsite.name/lat/lon/facility/equipmentRental/
trailerAccompanyAt/caravanAccompanyAt`, 온보딩의 날짜·인원·이동수단(hasCar)·숙련도·선호·장비.

## 6. 전면 모션 리디자인

- 모션: 페이지 전환, 리스트 staggered 등장, 버튼 press 피드백, AI 스트리밍 섹션 리빌,
  날씨 등급 배지 애니메이션, 캠핑장 상세 히어로 패럴럭스.
- 로딩/빈 상태: shimmer 스켈레톤(현 `LoadingPanel` 대체).
- 구현: `flutter_animate` 패키지 + Flutter 내장 애니메이션. 팔레트/폰트 불변.

## 7. Claude Design 활용 (시각 점수)

- 앱 아이콘·스플래시 리프레시, 빈 상태/날씨 아이콘·히어로 일러스트를 SVG 에셋으로 제작.
- (선택) 심사위원용 1페이지 소개 자료.

## 8. 코드 구조 정리 (최소 범위)

- 신규 플래너는 별도 파일(`lib/planner/`).
- 그 과정에서 `theme.dart`(토큰), `api.dart`(API+모델)만 분리.
- 기존 화면 로직은 건드리지 않음 — 위험 최소화.

## 9. 리스크 / 확인 필요

- 라이브 AI에는 Gemini API 키 + Vercel 배포가 필요. 키 미설정 상태에서도 폴백 플랜으로 앱은 완전 동작.
- 프로젝트가 아직 git 저장소가 아님(`.git` 없음). 커밋이 필요하면 `git init` 여부를 사용자와 확인.
- Open-Meteo는 미래 날짜 예보 범위(약 16일) 내에서만 정확. 그 밖이면 계절 평년값/폴백 처리.

## 10. 성공 기준

- 자연어 입력 → 5개 섹션이 실데이터로 채워진 플랜이 스트리밍 리빌로 표시.
- "체크리스트로 보내기"가 기존 ChecklistScreen에 항목을 실제로 채움.
- 전 화면에 모션 적용, 로딩은 shimmer.
- Gemini 키 없이도 폴백으로 데모 무중단.
