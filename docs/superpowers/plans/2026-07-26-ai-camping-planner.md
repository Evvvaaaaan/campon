# AI 캠핑 플래너 & 전면 모션 리디자인 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CampOn에 자연어 입력 한 줄로 캠핑장·날씨경보·준비물·타임라인을 한 화면에 생성하는 AI 캠핑 플래너를 붙이고, 전면 모션 리디자인을 적용한다.

**Architecture:** Flutter 앱은 기존 백엔드에서 후보 캠핑장을 받아 별도 Vercel 프록시(`/api/plan`)로 넘긴다. 프록시는 Open-Meteo(무료·키불필요) 날씨를 합쳐 Gemini 2.0 Flash에 구조화 JSON 출력을 요청하고 플랜 JSON을 반환한다. 앱은 플랜을 5개 섹션으로 스트리밍 리빌한다. Gemini 키 미설정/오류 시 앱·프록시 모두 결정론적 폴백 플랜으로 무중단 동작한다.

**Tech Stack:** Flutter 3.41 / Dart, `dart:io HttpClient`(기존 패턴 유지), `flutter_animate`(모션), Vercel 서버리스(TypeScript), Google Gemini 2.0 Flash, Open-Meteo.

## Global Constraints

- 팔레트/폰트 불변: Wood Amber `#C1702F`, Deep Forest Green `#1E3A2B`, Cream `#F5EFE1`; Black Han Sans(제목)·Noto Sans KR(본문). 신규 UI도 `CampColors`/`CampText` 토큰만 사용.
- HTTP는 기존 패턴대로 `dart:io HttpClient` 사용(신규 http 패키지 추가 금지). 예외: 모션은 `flutter_animate` 1개만 추가 허용.
- 사용자 표시 문자열은 한국어. 코드·식별자·커밋 메시지는 영어.
- 프록시 URL은 `String.fromEnvironment('PLAN_PROXY_URL', defaultValue: 'https://campon-ai-proxy.vercel.app')`로 주입. 하드코딩 금지.
- Gemini 키는 프록시 환경변수 `GEMINI_API_KEY`에만. 앱·저장소에 키를 넣지 않는다.
- 각 Flutter 변경 후 검증 게이트: `flutter analyze`(0 error). 순수 로직은 `flutter test`. UI는 실제 실행 화면 확인.
- 이 프로젝트는 아직 git 저장소가 아니다. 커밋 단계는 `git init` 이후에만 동작한다(실행 시작 시 사용자 확인). 커밋이 불가하면 각 Task 종료 시 `flutter analyze`/`flutter test` 통과를 완료 기준으로 삼는다.
- Open-Meteo 예보는 약 16일 이내만 정확. 범위 밖 날짜는 프록시가 계절 평년값 폴백으로 처리.

---

### Task 0: 베이스라인 검증

**Files:** (없음 — 현재 상태 검증만)

**Interfaces:**
- Produces: 현재 앱이 analyze/build 통과함을 확인한 기준선.

- [ ] **Step 1: 의존성 복원 및 정적 분석**

Run: `cd /Users/evan/Desktop/02_project_dev/dev/campon && flutter pub get && flutter analyze`
Expected: analyze가 error 0으로 종료(기존 warning은 기록만).

- [ ] **Step 2: 기존 테스트 실행(기준선)**

Run: `flutter test`
Expected: 통과 혹은 기존 실패 목록 기록. 이후 내 변경이 새 실패를 냈는지 비교 기준.

- [ ] **Step 3: (선택) git 초기화**

사용자가 커밋을 원하면:
```bash
git init && git add -A && git commit -m "chore: baseline before AI planner work"
```

---

### Task 1: 디자인 토큰을 `lib/theme.dart`로 분리

**Files:**
- Create: `lib/theme.dart`
- Modify: `lib/main.dart` (해당 클래스 제거 + import 추가)

**Interfaces:**
- Produces: `CampColors`, `CampText`, `CampData`, 그리고 이들이 의존하는 순수 상수/헬퍼를 `package:campon/theme.dart`로 노출.

- [ ] **Step 1: 이동 대상 식별**

`lib/main.dart`에서 `class CampColors`(≈4501), `class CampText`(≈4519), `class CampData`(≈4426), `class FacilityBarData`(≈4419), `class CampOption`(≈4354)를 확인한다. 이들은 UI 위젯에 의존하지 않는 순수 토큰/데이터다.

- [ ] **Step 2: `lib/theme.dart` 생성**

파일 상단:
```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
```
위 클래스들을 `main.dart`에서 잘라내어 그대로 붙여넣는다(본문 변경 없음).

- [ ] **Step 3: `main.dart`에서 제거 및 import**

`lib/main.dart` 상단 import 목록에 추가:
```dart
import 'theme.dart';
```
잘라낸 클래스 정의는 `main.dart`에서 삭제한다.

- [ ] **Step 4: 검증**

Run: `flutter analyze`
Expected: error 0. (미해결 심볼이 있으면 해당 클래스도 theme.dart로 함께 이동)

- [ ] **Step 5: Commit**

```bash
git add lib/theme.dart lib/main.dart && git commit -m "refactor: extract design tokens to theme.dart"
```

---

### Task 2: API 레이어를 `lib/api.dart`로 분리

**Files:**
- Create: `lib/api.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `package:campon/theme.dart` (모델이 토큰을 참조하면).
- Produces: `CampOnApi`, `Campsite`, `CampRegion`, `CampPost`, `DirectionResult`, `AuthConfig`, `AuthSession`, `AuthSessionStore`, `SecureAuthSessionStore`, `CampOnApiException`, `CampOnSessionExpiredException`를 `package:campon/api.dart`로 노출.

- [ ] **Step 1: 이동 대상 식별**

`AuthConfig`, `AuthSession`, `AuthSessionStore`/`SecureAuthSessionStore`, `CampOnApi`, `CampOnApiException`, `CampOnSessionExpiredException`, 모델(`Campsite`, `CampRegion`, `CampPost`, `DirectionResult`)을 확인. 이들은 위젯 트리에 의존하지 않는다.

- [ ] **Step 2: `lib/api.dart` 생성**

파일 상단 import(기존 main.dart에서 이 코드가 쓰던 것과 동일):
```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
```
위 클래스들을 잘라내어 붙여넣는다. (실제 필요한 import만 남기도록 analyze로 정리)

- [ ] **Step 3: `main.dart`에서 제거 및 import**

```dart
import 'api.dart';
```
잘라낸 정의를 삭제한다.

- [ ] **Step 4: 검증**

Run: `flutter analyze`
Expected: error 0.

- [ ] **Step 5: 스모크 실행**

Run: `flutter test` (기존 테스트가 여전히 통과/동일 상태인지)
Expected: Task 0 대비 신규 실패 없음.

- [ ] **Step 6: Commit**

```bash
git add lib/api.dart lib/main.dart && git commit -m "refactor: extract API layer and models to api.dart"
```

---

### Task 3: Vercel 프록시 스캐폴드

**Files:**
- Create: `proxy/package.json`
- Create: `proxy/tsconfig.json`
- Create: `proxy/vercel.json`
- Create: `proxy/.gitignore`
- Create: `proxy/.env.example`

**Interfaces:**
- Produces: `proxy/` 안에서 `npm test`, `npx vercel dev`가 동작하는 TypeScript 서버리스 프로젝트 기반.

- [ ] **Step 1: `proxy/package.json`**

```json
{
  "name": "campon-ai-proxy",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "node --test",
    "dev": "vercel dev"
  },
  "devDependencies": {
    "@types/node": "^22.0.0",
    "typescript": "^5.5.0"
  }
}
```

- [ ] **Step 2: `proxy/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "types": ["node"]
  },
  "include": ["api/**/*.ts"]
}
```

- [ ] **Step 3: `proxy/vercel.json`**

```json
{ "functions": { "api/*.ts": { "maxDuration": 30 } } }
```

- [ ] **Step 4: `proxy/.env.example` 및 `.gitignore`**

`.env.example`:
```
GEMINI_API_KEY=your_key_here
```
`.gitignore`:
```
node_modules
.vercel
.env
```

- [ ] **Step 5: 설치 검증**

Run: `cd proxy && npm install`
Expected: 성공 종료.

- [ ] **Step 6: Commit**

```bash
git add proxy && git commit -m "chore(proxy): scaffold Vercel AI proxy"
```

---

### Task 4: 프록시 날씨 모듈 (Open-Meteo + 캠핑 등급)

**Files:**
- Create: `proxy/api/_weather.ts`
- Test: `proxy/api/_weather.test.ts`

**Interfaces:**
- Produces:
  - `type WeatherSummary = { grade: 'good'|'caution'|'risk'; nightLowC: number; precipPct: number; windMs: number; diurnalRangeC: number; advice: string }`
  - `function gradeWeather(input: { nightLowC:number; precipPct:number; windMs:number; diurnalRangeC:number }): { grade:'good'|'caution'|'risk'; advice:string }`
  - `async function fetchWeather(lat:number, lon:number, date:string): Promise<WeatherSummary>`

- [ ] **Step 1: 실패 테스트 작성 (`proxy/api/_weather.test.ts`)**

```ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { gradeWeather } from './_weather.ts';

test('rain over 60% is risk', () => {
  const r = gradeWeather({ nightLowC: 12, precipPct: 70, windMs: 3, diurnalRangeC: 8 });
  assert.equal(r.grade, 'risk');
});
test('cold night at or below 5 is caution', () => {
  const r = gradeWeather({ nightLowC: 4, precipPct: 10, windMs: 3, diurnalRangeC: 8 });
  assert.equal(r.grade, 'caution');
});
test('mild dry calm is good', () => {
  const r = gradeWeather({ nightLowC: 15, precipPct: 5, windMs: 2, diurnalRangeC: 7 });
  assert.equal(r.grade, 'good');
});
test('freezing night is risk', () => {
  const r = gradeWeather({ nightLowC: -1, precipPct: 0, windMs: 2, diurnalRangeC: 6 });
  assert.equal(r.grade, 'risk');
});
```

- [ ] **Step 2: 실패 확인**

Run: `cd proxy && node --test api/_weather.test.ts`
Expected: FAIL ("Cannot find module './_weather.ts'").

- [ ] **Step 3: 구현 (`proxy/api/_weather.ts`)**

```ts
export type Grade = 'good' | 'caution' | 'risk';
export type WeatherSummary = {
  grade: Grade; nightLowC: number; precipPct: number;
  windMs: number; diurnalRangeC: number; advice: string;
};

type Metrics = { nightLowC: number; precipPct: number; windMs: number; diurnalRangeC: number };

export function gradeWeather(m: Metrics): { grade: Grade; advice: string } {
  const risk = m.precipPct >= 60 || m.windMs >= 9 || m.nightLowC <= 0;
  const caution = m.precipPct >= 30 || m.windMs >= 6 || m.nightLowC <= 5 || m.diurnalRangeC >= 15;
  const tips: string[] = [];
  if (m.precipPct >= 30) tips.push('비 예보가 있어 타프와 방수 대비가 필요해요');
  if (m.windMs >= 6) tips.push('바람이 강해 팩을 단단히 고정하세요');
  if (m.nightLowC <= 5) tips.push('야간 기온이 낮아 동계 침낭과 매트가 필요해요');
  if (m.diurnalRangeC >= 15) tips.push('일교차가 커 겉옷을 꼭 챙기세요');
  const grade: Grade = risk ? 'risk' : caution ? 'caution' : 'good';
  const advice = tips.length ? tips.join('. ') + '.' :
    '날씨가 안정적이에요. 편안한 캠핑이 예상됩니다.';
  return { grade, advice };
}

export async function fetchWeather(lat: number, lon: number, date: string): Promise<WeatherSummary> {
  const url = new URL('https://api.open-meteo.com/v1/forecast');
  url.searchParams.set('latitude', String(lat));
  url.searchParams.set('longitude', String(lon));
  url.searchParams.set('daily',
    'temperature_2m_min,temperature_2m_max,precipitation_probability_max,wind_speed_10m_max');
  url.searchParams.set('timezone', 'Asia/Seoul');
  url.searchParams.set('start_date', date);
  url.searchParams.set('end_date', date);
  let metrics: Metrics = { nightLowC: 12, precipPct: 20, windMs: 3, diurnalRangeC: 9 };
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
    if (res.ok) {
      const j: any = await res.json();
      const min = j?.daily?.temperature_2m_min?.[0];
      const max = j?.daily?.temperature_2m_max?.[0];
      const precip = j?.daily?.precipitation_probability_max?.[0];
      const windKmh = j?.daily?.wind_speed_10m_max?.[0];
      if (typeof min === 'number' && typeof max === 'number') {
        metrics = {
          nightLowC: Math.round(min),
          precipPct: typeof precip === 'number' ? precip : 20,
          windMs: typeof windKmh === 'number' ? Math.round((windKmh / 3.6) * 10) / 10 : 3,
          diurnalRangeC: Math.round(max - min),
        };
      }
    }
  } catch { /* fall through to defaults */ }
  const { grade, advice } = gradeWeather(metrics);
  return { grade, ...metrics, advice };
}
```

- [ ] **Step 4: 통과 확인**

Run: `cd proxy && node --test api/_weather.test.ts`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add proxy/api/_weather.ts proxy/api/_weather.test.ts && git commit -m "feat(proxy): open-meteo weather with camping risk grading"
```

---

### Task 5: 프록시 플랜 핸들러 (`/api/plan`)

**Files:**
- Create: `proxy/api/plan.ts`
- Create: `proxy/api/_plan_core.ts`
- Test: `proxy/api/_plan_core.test.ts`

**Interfaces:**
- Consumes: `fetchWeather`, `WeatherSummary` from `./_weather.ts`.
- Produces:
  - `type PlanRequest = { query:string; context:PlanContext; coords:{lat:number;lon:number}; candidates:Candidate[] }`
  - `type PlanContext = { date:string; people:number; hasCar:boolean; experience:string; region:string; preferences:string[]; equipment:string[] }`
  - `type Candidate = { name:string; facility:string[]; equipmentRental:string[] }`
  - `type Plan = { summary:{title:string;mood:string;oneLiner:string}; weather:WeatherSummary; campsites:{name:string;reason:string}[]; checklist:{category:string;items:string[]}[]; timeline:{time:string;title:string;detail:string}[] }`
  - `function buildFallbackPlan(req: PlanRequest, weather: WeatherSummary): Plan`
  - `function coercePlan(raw: unknown, req: PlanRequest, weather: WeatherSummary): Plan` — LLM 출력 검증/보정, 실패 시 폴백 병합
  - `function buildPrompt(req: PlanRequest, weather: WeatherSummary): string`
  - default export `handler(req, res)` — Vercel 서버리스 진입점

- [ ] **Step 1: 실패 테스트 작성 (`proxy/api/_plan_core.test.ts`)**

```ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildFallbackPlan, coercePlan, type PlanRequest } from './_plan_core.ts';
import type { WeatherSummary } from './_weather.ts';

const req: PlanRequest = {
  query: '이번 주말 2명 강원도 초보 오토캠핑',
  context: { date: '2026-08-01', people: 2, hasCar: true, experience: '초보',
             region: '강원', preferences: [], equipment: [] },
  coords: { lat: 37.8, lon: 128.9 },
  candidates: [{ name: '가리왕산 캠핑장', facility: ['전기'], equipmentRental: [] }],
};
const weather: WeatherSummary = { grade: 'caution', nightLowC: 6, precipPct: 40,
  windMs: 4, diurnalRangeC: 12, advice: '대비하세요.' };

test('fallback plan is fully shaped', () => {
  const p = buildFallbackPlan(req, weather);
  assert.ok(p.summary.oneLiner.length > 0);
  assert.equal(p.weather.grade, 'caution');
  assert.ok(p.campsites.length >= 1);
  assert.ok(p.checklist.length >= 1);
  assert.ok(p.timeline.length >= 3);
});

test('coercePlan repairs missing fields from LLM output', () => {
  const raw = { summary: { title: '강원 오토캠핑', oneLiner: '좋아요' } }; // mood/campsites/... 누락
  const p = coercePlan(raw, req, weather);
  assert.equal(p.summary.title, '강원 오토캠핑');
  assert.ok(typeof p.summary.mood === 'string');
  assert.ok(p.campsites.length >= 1);
  assert.ok(p.timeline.length >= 3);
  assert.equal(p.weather.grade, 'caution'); // 날씨는 항상 서버 계산값 우선
});
```

- [ ] **Step 2: 실패 확인**

Run: `cd proxy && node --test api/_plan_core.test.ts`
Expected: FAIL (모듈 없음).

- [ ] **Step 3: 구현 (`proxy/api/_plan_core.ts`)**

```ts
import type { WeatherSummary } from './_weather.ts';

export type PlanContext = {
  date: string; people: number; hasCar: boolean; experience: string;
  region: string; preferences: string[]; equipment: string[];
};
export type Candidate = { name: string; facility: string[]; equipmentRental: string[] };
export type PlanRequest = {
  query: string; context: PlanContext; coords: { lat: number; lon: number }; candidates: Candidate[];
};
export type Plan = {
  summary: { title: string; mood: string; oneLiner: string };
  weather: WeatherSummary;
  campsites: { name: string; reason: string }[];
  checklist: { category: string; items: string[] }[];
  timeline: { time: string; title: string; detail: string }[];
};

const str = (v: unknown, d = ''): string => (typeof v === 'string' && v.trim() ? v : d);
const arr = <T,>(v: unknown): T[] => (Array.isArray(v) ? (v as T[]) : []);

export function buildFallbackPlan(req: PlanRequest, weather: WeatherSummary): Plan {
  const c = req.context;
  const names = req.candidates.slice(0, 3);
  return {
    summary: {
      title: `${c.region} ${c.hasCar ? '오토' : ''}캠핑`.trim(),
      mood: c.experience.includes('초보') ? '편안하고 안전하게' : '자유롭게',
      oneLiner: `${c.date} ${c.people}명, ${c.region} 캠핑 플랜입니다.`,
    },
    weather,
    campsites: names.length
      ? names.map((s) => ({ name: s.name, reason: `${c.region} 지역, 접근성과 시설이 무난해요.` }))
      : [{ name: `${c.region} 인근 캠핑장`, reason: '지역 조건에 맞춘 추천입니다.' }],
    checklist: [
      { category: '텐트·취침', items: ['텐트', '그라운드시트', weather.nightLowC <= 5 ? '동계 침낭' : '침낭', '매트'] },
      { category: '취사', items: ['버너', '코펠', '식수', '아이스박스'] },
      { category: '의류', items: [weather.diurnalRangeC >= 12 ? '보온 겉옷' : '여벌옷', '양말', '모자'] },
      { category: '안전', items: ['구급킷', '헤드랜턴', '보조배터리', weather.precipPct >= 30 ? '우비·타프' : '비상 우비'] },
    ],
    timeline: [
      { time: '14:00', title: '도착·설치', detail: '입실 후 텐트와 타프를 설치해요.' },
      { time: '17:00', title: '저녁 준비', detail: '해지기 전 취사와 식사를 마쳐요.' },
      { time: '19:30', title: '캠프파이어', detail: '불멍과 휴식 시간.' },
      { time: '22:00', title: '취침', detail: `야간 최저 ${weather.nightLowC}도, 보온에 유의해요.` },
      { time: '10:00', title: '철수', detail: '장비를 말리고 정리 후 퇴실해요.' },
    ],
  };
}

export function coercePlan(raw: unknown, req: PlanRequest, weather: WeatherSummary): Plan {
  const fb = buildFallbackPlan(req, weather);
  const r = (raw ?? {}) as any;
  const summary = r.summary ?? {};
  const campsites = arr<any>(r.campsites)
    .map((x) => ({ name: str(x?.name), reason: str(x?.reason) }))
    .filter((x) => x.name);
  const checklist = arr<any>(r.checklist)
    .map((x) => ({ category: str(x?.category), items: arr<string>(x?.items).map((i) => str(i)).filter(Boolean) }))
    .filter((x) => x.category && x.items.length);
  const timeline = arr<any>(r.timeline)
    .map((x) => ({ time: str(x?.time), title: str(x?.title), detail: str(x?.detail) }))
    .filter((x) => x.time && x.title);
  return {
    summary: {
      title: str(summary.title, fb.summary.title),
      mood: str(summary.mood, fb.summary.mood),
      oneLiner: str(summary.oneLiner, fb.summary.oneLiner),
    },
    weather, // 항상 서버 계산값
    campsites: campsites.length ? campsites.slice(0, 3) : fb.campsites,
    checklist: checklist.length ? checklist : fb.checklist,
    timeline: timeline.length >= 3 ? timeline : fb.timeline,
  };
}

export function buildPrompt(req: PlanRequest, weather: WeatherSummary): string {
  const c = req.context;
  const cand = req.candidates.slice(0, 5).map((s) =>
    `- ${s.name} (시설: ${s.facility.join(', ') || '정보없음'}; 대여: ${s.equipmentRental.join(', ') || '없음'})`).join('\n');
  return [
    '너는 한국 캠핑 플래너다. 아래 정보로 캠핑 플랜을 JSON으로만 작성한다.',
    `요청: ${req.query}`,
    `날짜:${c.date} 인원:${c.people} 차량:${c.hasCar ? '있음' : '없음'} 숙련도:${c.experience} 지역:${c.region}`,
    `선호:${c.preferences.join(',') || '없음'} 보유장비:${c.equipment.join(',') || '없음'}`,
    `날씨: 등급=${weather.grade} 야간최저=${weather.nightLowC}도 강수확률=${weather.precipPct}% 풍속=${weather.windMs}m/s 일교차=${weather.diurnalRangeC}도`,
    '후보 캠핑장(이 목록에서만 골라 이름을 그대로 쓸 것):',
    cand || '- (후보 없음: 지역 기반 일반 추천)',
    '규칙: campsites는 후보 중 최대 3곳, 각 reason은 요청/날씨/숙련도에 맞춰 1문장.',
    'checklist는 날씨와 숙련도를 반영. timeline은 도착~철수 최소 5단계.',
    '모든 문장은 한국어.',
  ].join('\n');
}
```

- [ ] **Step 4: 통과 확인**

Run: `cd proxy && node --test api/_plan_core.test.ts`
Expected: PASS (2 tests).

- [ ] **Step 5: 핸들러 구현 (`proxy/api/plan.ts`)**

```ts
import { fetchWeather } from './_weather.ts';
import { buildPrompt, coercePlan, buildFallbackPlan, type PlanRequest } from './_plan_core.ts';

const MODEL = 'gemini-2.0-flash';

async function callGemini(prompt: string): Promise<unknown> {
  const key = process.env.GEMINI_API_KEY;
  if (!key) return null;
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${key}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    signal: AbortSignal.timeout(25000),
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { temperature: 0.7, responseMimeType: 'application/json' },
    }),
  });
  if (!res.ok) return null;
  const j: any = await res.json();
  const text = j?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof text !== 'string') return null;
  try { return JSON.parse(text); } catch { return null; }
}

export default async function handler(req: any, res: any) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'content-type');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method' });
  try {
    const body: PlanRequest = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
    const weather = await fetchWeather(body.coords.lat, body.coords.lon, body.context.date);
    const raw = await callGemini(buildPrompt(body, weather));
    const plan = raw ? coercePlan(raw, body, weather) : buildFallbackPlan(body, weather);
    return res.status(200).json({ plan, source: raw ? 'llm' : 'fallback' });
  } catch (e) {
    return res.status(200).json({ plan: null, error: String(e) });
  }
}
```

- [ ] **Step 6: 로컬 실행 확인 (키 없이 폴백 경로)**

Run: `cd proxy && npx vercel dev --listen 3999` (백그라운드) 후 다른 셸에서:
```bash
curl -s -X POST http://localhost:3999/api/plan -H 'content-type: application/json' \
 -d '{"query":"주말 2명 강원 초보","context":{"date":"2026-08-01","people":2,"hasCar":true,"experience":"초보","region":"강원","preferences":[],"equipment":[]},"coords":{"lat":37.8,"lon":128.9},"candidates":[{"name":"가리왕산 캠핑장","facility":["전기"],"equipmentRental":[]}]}'
```
Expected: `"source":"fallback"`이고 plan의 5개 섹션이 채워진 JSON. (키 설정 시 `"source":"llm"`)

- [ ] **Step 7: Commit**

```bash
git add proxy/api/plan.ts proxy/api/_plan_core.ts proxy/api/_plan_core.test.ts && git commit -m "feat(proxy): /api/plan with gemini + deterministic fallback"
```

---

### Task 6: 앱 플랜 모델 `lib/planner/plan_models.dart`

**Files:**
- Create: `lib/planner/plan_models.dart`
- Test: `test/plan_models_test.dart`

**Interfaces:**
- Produces:
  - `enum WeatherGrade { good, caution, risk }` + `WeatherGrade weatherGradeFrom(String)`
  - `class PlanWeather { WeatherGrade grade; int nightLowC; int precipPct; double windMs; int diurnalRangeC; String advice; }`
  - `class PlanCampsite { String name; String reason; }`
  - `class PlanChecklistCategory { String category; List<String> items; }`
  - `class PlanTimelineItem { String time; String title; String detail; }`
  - `class PlanSummary { String title; String mood; String oneLiner; }`
  - `class CampPlan { PlanSummary summary; PlanWeather weather; List<PlanCampsite> campsites; List<PlanChecklistCategory> checklist; List<PlanTimelineItem> timeline; }`
  - `factory CampPlan.fromJson(Map<String,dynamic>)` — null-안전 파싱
  - `class PlanInput { String query; String date; int people; bool hasCar; String experience; String region; double lat; double lon; List<String> preferences; List<String> equipment; List<PlanCandidate> candidates; }`
  - `class PlanCandidate { String name; List<String> facility; List<String> equipmentRental; Map<String,dynamic> toJson(); }`
  - `CampPlan buildLocalFallbackPlan(PlanInput)` — 프록시조차 못 붙는 경우의 앱측 최종 폴백

- [ ] **Step 1: 실패 테스트 (`test/plan_models_test.dart`)**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:campon/planner/plan_models.dart';

void main() {
  test('CampPlan.fromJson parses full payload', () {
    final json = {
      'summary': {'title': '강원 오토캠핑', 'mood': '편안하게', 'oneLiner': '2명 강원 캠핑'},
      'weather': {'grade': 'caution', 'nightLowC': 6, 'precipPct': 40, 'windMs': 4.0,
                  'diurnalRangeC': 12, 'advice': '겉옷 챙기세요.'},
      'campsites': [{'name': '가리왕산', 'reason': '접근성 좋음'}],
      'checklist': [{'category': '취사', 'items': ['버너', '코펠']}],
      'timeline': [{'time': '14:00', 'title': '도착', 'detail': '설치'}],
    };
    final plan = CampPlan.fromJson(json);
    expect(plan.summary.title, '강원 오토캠핑');
    expect(plan.weather.grade, WeatherGrade.caution);
    expect(plan.campsites.first.name, '가리왕산');
    expect(plan.checklist.first.items.length, 2);
    expect(plan.timeline.first.time, '14:00');
  });

  test('local fallback fills all sections', () {
    final input = PlanInput(query: '주말 강원', date: '2026-08-01', people: 2, hasCar: true,
      experience: '초보', region: '강원', lat: 37.8, lon: 128.9,
      preferences: const [], equipment: const [], candidates: const []);
    final plan = buildLocalFallbackPlan(input);
    expect(plan.campsites, isNotEmpty);
    expect(plan.checklist, isNotEmpty);
    expect(plan.timeline.length, greaterThanOrEqualTo(3));
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/plan_models_test.dart`
Expected: FAIL (모듈 없음).

- [ ] **Step 3: 구현 (`lib/planner/plan_models.dart`)**

`fromJson`은 방어적으로 파싱한다(누락/타입불일치 시 기본값). `buildLocalFallbackPlan`은 프록시의 `buildFallbackPlan`과 동일한 규칙을 Dart로 옮긴다(날씨는 온화한 기본값 사용). 코드:

```dart
enum WeatherGrade { good, caution, risk }

WeatherGrade weatherGradeFrom(String? s) {
  switch (s) {
    case 'risk': return WeatherGrade.risk;
    case 'caution': return WeatherGrade.caution;
    default: return WeatherGrade.good;
  }
}

class PlanSummary {
  PlanSummary({required this.title, required this.mood, required this.oneLiner});
  final String title, mood, oneLiner;
}
class PlanWeather {
  PlanWeather({required this.grade, required this.nightLowC, required this.precipPct,
    required this.windMs, required this.diurnalRangeC, required this.advice});
  final WeatherGrade grade; final int nightLowC, precipPct, diurnalRangeC;
  final double windMs; final String advice;
}
class PlanCampsite { PlanCampsite({required this.name, required this.reason}); final String name, reason; }
class PlanChecklistCategory {
  PlanChecklistCategory({required this.category, required this.items});
  final String category; final List<String> items;
}
class PlanTimelineItem {
  PlanTimelineItem({required this.time, required this.title, required this.detail});
  final String time, title, detail;
}

String _s(dynamic v, [String d = '']) => v is String && v.trim().isNotEmpty ? v : d;
int _i(dynamic v, [int d = 0]) => v is num ? v.round() : d;
double _d(dynamic v, [double d = 0]) => v is num ? v.toDouble() : d;
List<String> _sl(dynamic v) => v is List ? v.map((e) => _s(e)).where((e) => e.isNotEmpty).toList() : <String>[];

class CampPlan {
  CampPlan({required this.summary, required this.weather, required this.campsites,
    required this.checklist, required this.timeline});
  final PlanSummary summary; final PlanWeather weather;
  final List<PlanCampsite> campsites; final List<PlanChecklistCategory> checklist;
  final List<PlanTimelineItem> timeline;

  factory CampPlan.fromJson(Map<String, dynamic> j) {
    final w = (j['weather'] as Map?)?.cast<String, dynamic>() ?? const {};
    final s = (j['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
    return CampPlan(
      summary: PlanSummary(title: _s(s['title'], '캠핑 플랜'), mood: _s(s['mood']),
        oneLiner: _s(s['oneLiner'])),
      weather: PlanWeather(grade: weatherGradeFrom(w['grade'] as String?),
        nightLowC: _i(w['nightLowC'], 12), precipPct: _i(w['precipPct'], 20),
        windMs: _d(w['windMs'], 3), diurnalRangeC: _i(w['diurnalRangeC'], 9),
        advice: _s(w['advice'], '날씨 정보를 확인하세요.')),
      campsites: (j['campsites'] as List? ?? const [])
        .map((e) => PlanCampsite(name: _s((e as Map)['name']), reason: _s(e['reason'])))
        .where((e) => e.name.isNotEmpty).toList(),
      checklist: (j['checklist'] as List? ?? const [])
        .map((e) => PlanChecklistCategory(category: _s((e as Map)['category']), items: _sl(e['items'])))
        .where((e) => e.category.isNotEmpty && e.items.isNotEmpty).toList(),
      timeline: (j['timeline'] as List? ?? const [])
        .map((e) => PlanTimelineItem(time: _s((e as Map)['time']), title: _s(e['title']),
          detail: _s(e['detail']))).where((e) => e.time.isNotEmpty).toList(),
    );
  }
}

class PlanCandidate {
  PlanCandidate({required this.name, required this.facility, required this.equipmentRental});
  final String name; final List<String> facility, equipmentRental;
  Map<String, dynamic> toJson() => {'name': name, 'facility': facility, 'equipmentRental': equipmentRental};
}

class PlanInput {
  PlanInput({required this.query, required this.date, required this.people, required this.hasCar,
    required this.experience, required this.region, required this.lat, required this.lon,
    required this.preferences, required this.equipment, required this.candidates});
  final String query, date, experience, region; final int people; final bool hasCar;
  final double lat, lon; final List<String> preferences, equipment; final List<PlanCandidate> candidates;

  Map<String, dynamic> toRequestJson() => {
    'query': query,
    'context': {'date': date, 'people': people, 'hasCar': hasCar, 'experience': experience,
      'region': region, 'preferences': preferences, 'equipment': equipment},
    'coords': {'lat': lat, 'lon': lon},
    'candidates': candidates.map((c) => c.toJson()).toList(),
  };
}

CampPlan buildLocalFallbackPlan(PlanInput input) {
  final names = input.candidates.take(3).toList();
  return CampPlan(
    summary: PlanSummary(
      title: '${input.region} ${input.hasCar ? "오토" : ""}캠핑'.trim(),
      mood: input.experience.contains('초보') ? '편안하고 안전하게' : '자유롭게',
      oneLiner: '${input.date} ${input.people}명, ${input.region} 캠핑 플랜입니다.'),
    weather: PlanWeather(grade: WeatherGrade.good, nightLowC: 14, precipPct: 15,
      windMs: 3, diurnalRangeC: 9, advice: '날씨가 안정적이에요. 편안한 캠핑이 예상됩니다.'),
    campsites: names.isNotEmpty
      ? names.map((s) => PlanCampsite(name: s.name, reason: '${input.region} 지역, 접근성과 시설이 무난해요.')).toList()
      : [PlanCampsite(name: '${input.region} 인근 캠핑장', reason: '지역 조건에 맞춘 추천입니다.')],
    checklist: [
      PlanChecklistCategory(category: '텐트·취침', items: ['텐트', '그라운드시트', '침낭', '매트']),
      PlanChecklistCategory(category: '취사', items: ['버너', '코펠', '식수', '아이스박스']),
      PlanChecklistCategory(category: '의류', items: ['여벌옷', '양말', '모자']),
      PlanChecklistCategory(category: '안전', items: ['구급킷', '헤드랜턴', '보조배터리', '비상 우비']),
    ],
    timeline: [
      PlanTimelineItem(time: '14:00', title: '도착·설치', detail: '입실 후 텐트와 타프를 설치해요.'),
      PlanTimelineItem(time: '17:00', title: '저녁 준비', detail: '해지기 전 취사와 식사를 마쳐요.'),
      PlanTimelineItem(time: '19:30', title: '캠프파이어', detail: '불멍과 휴식 시간.'),
      PlanTimelineItem(time: '22:00', title: '취침', detail: '보온에 유의해요.'),
      PlanTimelineItem(time: '10:00', title: '철수', detail: '장비를 말리고 정리 후 퇴실해요.'),
    ],
  );
}
```

- [ ] **Step 4: 통과 확인**

Run: `flutter test test/plan_models_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/planner/plan_models.dart test/plan_models_test.dart && git commit -m "feat(planner): plan models with defensive parsing and local fallback"
```

---

### Task 7: 플랜 서비스 `lib/planner/plan_service.dart`

**Files:**
- Create: `lib/planner/plan_service.dart`
- Test: `test/plan_service_test.dart`

**Interfaces:**
- Consumes: `CampPlan`, `PlanInput`, `buildLocalFallbackPlan` from `plan_models.dart`.
- Produces:
  - `typedef PlanFetcher = Future<String> Function(Uri url, String body)` (테스트 주입용)
  - `class PlanService { PlanService({PlanFetcher? fetcher, String? baseUrl}); Future<CampPlan> generate(PlanInput input); }`
  - `generate`는 프록시 호출 → `{plan: {...}}` 파싱 → 실패/빈응답 시 `buildLocalFallbackPlan(input)` 반환(예외 던지지 않음).

- [ ] **Step 1: 실패 테스트 (`test/plan_service_test.dart`)**

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:campon/planner/plan_models.dart';
import 'package:campon/planner/plan_service.dart';

PlanInput _input() => PlanInput(query: '주말 강원', date: '2026-08-01', people: 2, hasCar: true,
  experience: '초보', region: '강원', lat: 37.8, lon: 128.9,
  preferences: const [], equipment: const [], candidates: const []);

void main() {
  test('parses proxy plan payload', () async {
    final svc = PlanService(fetcher: (url, body) async => jsonEncode({
      'plan': {
        'summary': {'title': 'T', 'mood': 'M', 'oneLiner': 'O'},
        'weather': {'grade': 'risk', 'nightLowC': 2, 'precipPct': 80, 'windMs': 10.0,
                    'diurnalRangeC': 16, 'advice': 'A'},
        'campsites': [{'name': 'C', 'reason': 'R'}],
        'checklist': [{'category': 'K', 'items': ['a']}],
        'timeline': [{'time': '14:00', 'title': 'X', 'detail': 'Y'},
                     {'time': '17:00', 'title': 'X2', 'detail': 'Y2'},
                     {'time': '22:00', 'title': 'X3', 'detail': 'Y3'}],
      }
    }));
    final plan = await svc.generate(_input());
    expect(plan.summary.title, 'T');
    expect(plan.weather.grade, WeatherGrade.risk);
  });

  test('falls back locally on fetch error', () async {
    final svc = PlanService(fetcher: (url, body) async => throw Exception('network'));
    final plan = await svc.generate(_input());
    expect(plan.campsites, isNotEmpty); // 폴백이 채움
  });

  test('falls back on null plan', () async {
    final svc = PlanService(fetcher: (url, body) async => jsonEncode({'plan': null}));
    final plan = await svc.generate(_input());
    expect(plan.timeline.length, greaterThanOrEqualTo(3));
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/plan_service_test.dart`
Expected: FAIL.

- [ ] **Step 3: 구현 (`lib/planner/plan_service.dart`)**

기본 fetcher는 기존 코드베이스 패턴대로 `dart:io HttpClient` 사용:
```dart
import 'dart:convert';
import 'dart:io';
import 'plan_models.dart';

typedef PlanFetcher = Future<String> Function(Uri url, String body);

const _defaultBase = String.fromEnvironment('PLAN_PROXY_URL',
  defaultValue: 'https://campon-ai-proxy.vercel.app');

Future<String> _httpFetcher(Uri url, String body) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final req = await client.postUrl(url);
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    req.add(utf8.encode(body));
    final res = await req.close();
    return await res.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

class PlanService {
  PlanService({PlanFetcher? fetcher, String? baseUrl})
      : _fetcher = fetcher ?? _httpFetcher, _baseUrl = baseUrl ?? _defaultBase;
  final PlanFetcher _fetcher; final String _baseUrl;

  Future<CampPlan> generate(PlanInput input) async {
    try {
      final url = Uri.parse('$_baseUrl/api/plan');
      final raw = await _fetcher(url, jsonEncode(input.toRequestJson()));
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final plan = decoded['plan'];
      if (plan is Map<String, dynamic>) return CampPlan.fromJson(plan);
      return buildLocalFallbackPlan(input);
    } catch (_) {
      return buildLocalFallbackPlan(input);
    }
  }
}
```

- [ ] **Step 4: 통과 확인**

Run: `flutter test test/plan_service_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/planner/plan_service.dart test/plan_service_test.dart && git commit -m "feat(planner): plan service with proxy call and local fallback"
```

---

### Task 8: 모션 헬퍼 `lib/motion/motion.dart` + flutter_animate 추가

**Files:**
- Modify: `pubspec.yaml` (dependencies에 `flutter_animate` 추가)
- Create: `lib/motion/motion.dart`

**Interfaces:**
- Produces:
  - `Widget revealColumn({required List<Widget> children, Duration stagger, double spacing})` — 자식들을 fade+slide로 순차 등장
  - `class Shimmer extends StatelessWidget { Shimmer({required this.height, this.width}); }` — 로딩 스켈레톤 블록
  - `Widget pressable({required Widget child, required VoidCallback onTap})` — 탭 시 scale 축소 피드백

- [ ] **Step 1: 의존성 추가**

`pubspec.yaml`의 `dependencies:`에 추가:
```yaml
  flutter_animate: ^4.5.0
```
Run: `flutter pub get`
Expected: 성공.

- [ ] **Step 2: 구현 (`lib/motion/motion.dart`)**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme.dart';

Widget revealColumn({
  required List<Widget> children,
  Duration stagger = const Duration(milliseconds: 90),
  double spacing = 16,
}) {
  final items = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    items.add(
      children[i]
          .animate()
          .fadeIn(duration: 360.ms, delay: stagger * i)
          .slideY(begin: 0.12, end: 0, duration: 360.ms, delay: stagger * i, curve: Curves.easeOutCubic),
    );
    if (i != children.length - 1) items.add(SizedBox(height: spacing));
  }
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items);
}

class Shimmer extends StatelessWidget {
  const Shimmer({super.key, required this.height, this.width});
  final double height; final double? width;
  @override
  Widget build(BuildContext context) {
    return Container(
      height: height, width: width,
      decoration: BoxDecoration(color: CampColors.greenTint, borderRadius: BorderRadius.circular(12)),
    ).animate(onPlay: (c) => c.repeat()).shimmer(
      duration: 1200.ms, color: CampColors.surface.withValues(alpha: 0.6));
  }
}

class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap});
  final Widget child; final VoidCallback onTap;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  double _scale = 1;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.96),
      onTapUp: (_) => setState(() => _scale = 1),
      onTapCancel: () => setState(() => _scale = 1),
      onTap: widget.onTap,
      child: AnimatedScale(scale: _scale, duration: const Duration(milliseconds: 110), child: widget.child),
    );
  }
}
```

- [ ] **Step 3: 검증**

Run: `flutter analyze lib/motion/motion.dart`
Expected: error 0. (`withValues`가 미지원이면 `withOpacity`로 교체)

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/motion/motion.dart && git commit -m "feat(motion): add flutter_animate and reveal/shimmer/pressable helpers"
```

---

### Task 9: 플래너 결과 화면 `lib/planner/planner_result_screen.dart`

**Files:**
- Create: `lib/planner/planner_result_screen.dart`

**Interfaces:**
- Consumes: `CampPlan`, `PlanWeather`, `WeatherGrade` (plan_models), `revealColumn`/`Shimmer` (motion), `CampColors`/`CampText` (theme).
- Produces:
  - `class PlannerResultScreen extends StatelessWidget { PlannerResultScreen({required this.plan, required this.onSendToChecklist, required this.onBack}); }`
  - `final CampPlan plan; final void Function(List<String> items) onSendToChecklist; final VoidCallback onBack;`
  - 5개 섹션(요약/캠핑장/날씨/체크리스트/타임라인)을 `revealColumn`으로 순차 표시. 날씨 등급별 색: good=forest, caution=primary, risk=`#B23A2E`.

- [ ] **Step 1: 구현**

섹션 카드 위젯들과 등급 색 매핑을 포함해 구현한다. 핵심 색 매핑:
```dart
Color _gradeColor(WeatherGrade g) => switch (g) {
  WeatherGrade.good => CampColors.forest,
  WeatherGrade.caution => CampColors.primary,
  WeatherGrade.risk => const Color(0xFFB23A2E),
};
String _gradeLabel(WeatherGrade g) => switch (g) {
  WeatherGrade.good => '캠핑 좋음',
  WeatherGrade.caution => '주의',
  WeatherGrade.risk => '위험',
};
```
`onSendToChecklist`는 `plan.checklist.expand((c) => c.items).toList()`를 넘긴다. 화면은 `SingleChildScrollView` + `revealColumn([요약카드, 캠핑장카드, 날씨카드, 체크리스트카드, 타임라인카드])` 구성. 각 카드는 `CampColors.surface` 배경, 16 라운드, `CampText` 토큰 사용. 하단 고정 액션 바에 "체크리스트로 보내기"(primary) 버튼.

- [ ] **Step 2: 검증**

Run: `flutter analyze lib/planner/planner_result_screen.dart`
Expected: error 0.

- [ ] **Step 3: Commit**

```bash
git add lib/planner/planner_result_screen.dart && git commit -m "feat(planner): result screen with staggered section reveal"
```

---

### Task 10: 플래너 입력 화면 `lib/planner/planner_input_screen.dart`

**Files:**
- Create: `lib/planner/planner_input_screen.dart`

**Interfaces:**
- Consumes: `PlanInput`, `PlanService`, `CampPlan` (planner), theme, motion.
- Produces:
  - `class PlannerInputScreen extends StatefulWidget { PlannerInputScreen({required this.prefill, required this.onGenerated, required this.onBack}); }`
  - `final PlanInput prefill;` (온보딩 컨텍스트로 미리 채운 값; query는 빈 문자열)
  - `final void Function(CampPlan plan) onGenerated; final VoidCallback onBack;`
  - 자연어 `TextField`(prefill.query) + 컨텍스트 요약 칩(날짜/지역/인원/차량) 표시 + "플랜 생성" 버튼.
  - 생성 중에는 `Shimmer` 스켈레톤 표시. 완료 시 `onGenerated(plan)` 호출.

- [ ] **Step 1: 구현**

버튼 탭 시:
```dart
setState(() => _loading = true);
final input = PlanInput(
  query: _controller.text.trim().isEmpty ? _defaultQuery() : _controller.text.trim(),
  date: widget.prefill.date, people: widget.prefill.people, hasCar: widget.prefill.hasCar,
  experience: widget.prefill.experience, region: widget.prefill.region,
  lat: widget.prefill.lat, lon: widget.prefill.lon,
  preferences: widget.prefill.preferences, equipment: widget.prefill.equipment,
  candidates: widget.prefill.candidates,
);
final plan = await PlanService().generate(input);
if (mounted) widget.onGenerated(plan);
```
`_defaultQuery()`는 컨텍스트로 문장 구성(예: `'${region} ${people}명 ${experience} 캠핑'`).

- [ ] **Step 2: 검증**

Run: `flutter analyze lib/planner/planner_input_screen.dart`
Expected: error 0.

- [ ] **Step 3: Commit**

```bash
git add lib/planner/planner_input_screen.dart && git commit -m "feat(planner): input screen with prefilled context and generate flow"
```

---

### Task 11: 플래너를 앱 흐름에 배선 (main.dart)

**Files:**
- Modify: `lib/main.dart` (`AppStep`에 `plannerInput`, `plannerResult` 추가; `HomeScreen` CTA; 라우팅; 체크리스트 핸드오프)

**Interfaces:**
- Consumes: `PlannerInputScreen`, `PlannerResultScreen`, `PlanInput`, `PlanCandidate`, `CampPlan`.
- Produces: 홈 "AI 플래너 시작" → 입력 → 결과 → "체크리스트로 보내기"가 기존 `ChecklistScreen`에 항목을 주입하는 완결 흐름.

- [ ] **Step 1: AppStep 확장 및 상태 필드**

`enum AppStep`에 `plannerInput, plannerResult` 추가. `_CampOnShellState`에 `CampPlan? _plan;`와 체크리스트 주입용 `List<String> _plannerChecklistItems = [];` 추가.

- [ ] **Step 2: PlanInput 구성 헬퍼**

`_CampOnShellState`에 현재 온보딩 상태(선택 지역/날짜/인원/hasCar/숙련도/선호/장비)와 최근 추천/조회 결과(`List<Campsite>`)로 `PlanInput`을 만드는 `PlanInput _buildPlanInput()` 추가. `candidates`는 최근 캠핑장 리스트를 `PlanCandidate(name, facility, equipmentRental)`로 매핑. 좌표는 선택 지역 `CampRegion.lat/lon` 사용.

- [ ] **Step 3: 라우팅 및 CTA**

`HomeScreen`에 "AI 플래너로 시작" 버튼을 추가하고 콜백으로 `setState(() => step = AppStep.plannerInput)`. build의 화면 스위치에 두 케이스 추가:
```dart
case AppStep.plannerInput:
  return PlannerInputScreen(
    prefill: _buildPlanInput(),
    onBack: () => setState(() => _step = AppStep.home),
    onGenerated: (plan) => setState(() { _plan = plan; _step = AppStep.plannerResult; }));
case AppStep.plannerResult:
  return PlannerResultScreen(
    plan: _plan!,
    onBack: () => setState(() => _step = AppStep.plannerInput),
    onSendToChecklist: (items) => setState(() {
      _plannerChecklistItems = items; _step = AppStep.checklist;
    }));
```

- [ ] **Step 4: 체크리스트 주입**

`ChecklistScreen`이 외부 주입 항목을 받도록 옵셔널 파라미터 `List<String> injectedItems = const []` 추가하고, 있으면 기존 항목 위에 "AI 추천" 카테고리로 병합 표시. 배선부에서 `_plannerChecklistItems`를 전달.

- [ ] **Step 5: 검증 (분석 + 실행)**

Run: `flutter analyze`
Expected: error 0.
Run: `flutter run`(시뮬레이터) 후 홈 → AI 플래너 → 플랜 생성(폴백) → 체크리스트로 보내기까지 수동 확인. 각 섹션이 순차 등장하고 체크리스트에 항목이 채워지는지 눈으로 확인.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart && git commit -m "feat: wire AI planner into app flow with checklist handoff"
```

---

### Task 12: 전면 모션 적용 (기존 화면)

**Files:**
- Modify: `lib/main.dart` (주요 화면에 reveal/pressable/shimmer 적용)

**Interfaces:**
- Consumes: `revealColumn`, `Shimmer`, `Pressable` (motion).

- [ ] **Step 1: 리스트/카드 등장 모션**

`CampsiteListScreen`, `HomeScreen`, `ChecklistScreen`의 카드 목록을 `revealColumn`으로 감싸거나 개별 카드에 `.animate().fadeIn().slideY()` 적용.

- [ ] **Step 2: 버튼 press 피드백**

`CampButton`/주요 CTA를 `Pressable`로 감싸 탭 스케일 피드백 부여(기존 onTap 유지).

- [ ] **Step 3: 로딩 shimmer**

`LoadingPanel`을 `Shimmer` 블록 3~4개 스택으로 교체.

- [ ] **Step 4: 검증**

Run: `flutter analyze` → error 0.
Run: `flutter run` → 각 화면 전환/로딩에서 모션 확인. 프레임 드랍 없는지 육안 확인.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart && git commit -m "feat(motion): apply reveal, press feedback, and shimmer across screens"
```

---

### Task 13: 프록시 배포 + 앱 연결 + 라이브 검증

**Files:**
- Modify: (없음 — 환경/배포 작업)

**Interfaces:**
- Produces: 배포된 프록시 URL + Gemini 키 설정 + 앱에서 라이브 LLM 플랜 확인.

- [ ] **Step 1: Gemini 키 발급**

사용자가 https://aistudio.google.com/apikey 에서 무료 API 키 발급(무료 티어). 키를 프록시 환경변수로 준비.

- [ ] **Step 2: 프록시 배포**

Run: `cd proxy && vercel deploy --prod` (최초 로그인/링크는 사용자가 `! vercel login`으로 수행)
배포 후 환경변수 설정:
```bash
vercel env add GEMINI_API_KEY production
```
Expected: 배포 URL 확보(예: `https://campon-ai-proxy.vercel.app`).

- [ ] **Step 3: 라이브 curl 검증**

```bash
curl -s -X POST https://<배포URL>/api/plan -H 'content-type: application/json' \
 -d '{"query":"주말 2명 강원 초보 오토캠핑","context":{"date":"2026-08-01","people":2,"hasCar":true,"experience":"초보","region":"강원","preferences":[],"equipment":[]},"coords":{"lat":37.8,"lon":128.9},"candidates":[{"name":"가리왕산 캠핑장","facility":["전기"],"equipmentRental":[]}]}'
```
Expected: `"source":"llm"`이고 한국어 플랜이 채워짐.

- [ ] **Step 4: 앱을 배포 URL로 실행**

Run: `flutter run --dart-define=PLAN_PROXY_URL=https://<배포URL>`
홈 → AI 플래너 → 실제 LLM 플랜이 스트리밍 리빌되는지 확인.

- [ ] **Step 5: Commit(문서)**

배포 URL을 `README.md` 또는 `DEVELOPMENT_NOTES.md`에 기록:
```bash
git add README.md && git commit -m "docs: record AI proxy deployment URL and run flag"
```

---

### Task 14: 브랜드/일러스트 에셋 (Claude Design, 시각 점수)

**Files:**
- Create: `assets/illustrations/*.svg` (빈 상태, 날씨 등급 아이콘, 히어로)
- Modify: `pubspec.yaml` (assets 경로), 관련 화면에서 에셋 사용

**Interfaces:**
- Produces: 일관된 브랜드 일러스트 에셋. flutter_svg로 렌더.

- [ ] **Step 1: 에셋 제작**

Amber/Forest 팔레트에 맞춘 SVG 일러스트를 디자인 툴로 제작(빈 상태 캠핑 씬, 날씨 good/caution/risk 아이콘, 플래너 히어로). `assets/illustrations/`에 저장.

- [ ] **Step 2: pubspec 등록 및 사용**

`pubspec.yaml`의 `flutter:` 하위 `assets:`에 경로 추가 후 `EmptyPanel`/플래너 날씨 카드에서 `SvgPicture.asset(...)`로 표시.

- [ ] **Step 3: 검증**

Run: `flutter run` → 해당 화면에서 에셋이 정상 렌더되는지 확인.

- [ ] **Step 4: Commit**

```bash
git add assets pubspec.yaml lib/main.dart lib/planner && git commit -m "feat(design): brand illustration assets for empty states and planner"
```

---

## Self-Review

**Spec coverage:**
- AI 플래너 화면 흐름 → Task 9,10,11 ✓
- 데이터 흐름(앱→프록시→Open-Meteo+Gemini) → Task 4,5,7 ✓
- 플랜 JSON 계약 → Task 5(서버), 6(앱) 양쪽에서 동일 구조 ✓
- 폴백(프록시/앱 양측) → Task 5(buildFallbackPlan), 6(buildLocalFallbackPlan) ✓
- 전면 모션 → Task 8(헬퍼), 12(적용) ✓
- 로딩 shimmer → Task 8,12 ✓
- 체크리스트 핸드오프 → Task 11 ✓
- Claude Design 에셋 → Task 14 ✓
- 코드 구조 분리(theme/api) → Task 1,2 ✓
- Gemini 키 미설정 무중단 → Task 5,7 폴백 ✓
- 배포/라이브 검증 → Task 13 ✓

**Placeholder scan:** 로직 태스크(4,5,6,7,8)는 완전한 코드 포함. UI 태스크(9,10,12,14)는 구조+핵심 코드 명시(위젯 픽셀 단위는 실행 확인으로 검증). "적절한 에러 처리" 같은 모호 표현 없음.

**Type consistency:** 플랜 JSON 키(summary/weather/campsites/checklist/timeline, grade/nightLowC/precipPct/windMs/diurnalRangeC/advice)가 프록시(Task 5)와 앱(Task 6) 양쪽에서 동일. `PlanInput.toRequestJson()`의 키(query/context/coords/candidates)가 프록시 `PlanRequest`와 일치. `PlanService.generate`가 `{plan: ...}` 래핑을 파싱하고 핸들러가 `{plan, source}`로 반환 — 일치.

## 미해결 의존성 (실행 시작 전 확인)

1. **git 초기화 여부** — 커밋 단계 동작에 필요.
2. **Gemini API 키 + Vercel 로그인** — Task 13 라이브 경로에 필요(그 전까지는 폴백으로 전 기능 데모 가능).
