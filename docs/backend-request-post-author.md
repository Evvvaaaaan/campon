# 백엔드 요청: 게시글 응답에 작성자 정보 추가

작성일: 2026-08-04
대상 API: `campon.seohamin.com` / `post-controller`
요청자: CampOn 앱 클라이언트

---

## 1. 한 줄 요약

`PostResponseDto`에 **작성자 유저 ID(`authorId`)** 를 추가해 주세요. 이 값이 없어서 앱의 유저 차단 기능이 동작하지 못하고 있습니다.

---

## 2. 왜 필요한가

### 2-1. 현재 응답에는 작성자 정보가 없습니다

`GET /api/v1/posts?campsiteId=1&size=5&page=0` 실제 응답 (2026-08-04 확인):

```json
{
  "hasNext": false,
  "items": [
    {
      "id": 2,
      "campsiteId": 1,
      "title": "제목",
      "content": "본문",
      "createdAt": "2026-08-04T06:14:05.568966"
    }
  ]
}
```

`id`는 게시글 식별자, `campsiteId`는 캠핑장 식별자입니다. **글을 쓴 사람이 누구인지 알려주는 필드가 없습니다.** swagger의 `PostResponseDto` 정의도 동일하게 5개 필드뿐입니다.

### 2-2. 그런데 차단 API는 유저 ID를 요구합니다

```
POST /api/v1/blocks
{ "blockedUserId": 2 }
```

앱에서 차단을 걸 수 있는 유일한 지점은 커뮤니티 게시글의 더보기 메뉴입니다. 그런데 게시글 응답에 작성자 ID가 없으니 `blockedUserId`에 넣을 값을 만들어낼 수 없습니다. 결과적으로 **"이 유저 차단" 메뉴는 어떤 글에서도 화면에 뜨지 않고, 차단 목록에 사람을 추가할 방법이 앱에 존재하지 않습니다.**

블록 API 자체(`POST` / `GET` / `DELETE /api/v1/blocks`)는 정상 동작하는 것을 왕복 호출로 확인했습니다. 클라이언트 연동 코드도 이미 작성되어 있습니다. 막혀 있는 건 오직 "누구를 차단할지"를 알아낼 방법입니다.

### 2-3. 삭제 버튼 노출도 같은 이유로 잘못돼 있습니다

서버는 남의 글 삭제를 이미 정상적으로 막고 있습니다. 유저 1이 쓴 글을 유저 2의 토큰으로 삭제 시도한 결과:

```
DELETE /api/v1/posts/3   (Authorization: 유저 2)
→ 403
```

서버 동작은 올바릅니다. 문제는 앱이 내 글과 남의 글을 구분할 정보가 없어서 **모든 글에 삭제 메뉴를 띄운다는 점**입니다. 사용자는 삭제를 누르고 403 에러 메시지를 보게 됩니다. `authorId`가 내려오면 이 문제도 함께 해결됩니다.

### 2-4. 스토어 심사 이슈

Apple App Store 심사 지침 1.2(User-Generated Content)는 이용자 생성 콘텐츠가 있는 앱에 **부적절한 사용자를 차단하는 수단**을 요구합니다. 현재 상태로는 차단 UI가 존재하지만 실제로는 도달할 수 없어, 심사에서 리젝될 수 있습니다.

---

## 3. 요청 사항

### (필수) `PostResponseDto`에 `authorId` 추가

| 항목 | 값 |
|---|---|
| 필드명 | `authorId` |
| 타입 | `integer` / `int64` |
| 필수 여부 | 항상 포함 (null 금지) |
| 의미 | 글을 작성한 유저의 ID. `POST /api/v1/blocks`의 `blockedUserId`와 **같은 체계의 값**이어야 합니다 |

`PostResponseDto` 하나만 고치면 아래 네 엔드포인트에 모두 반영됩니다.

- `GET /api/v1/posts` (목록, `items[]` 내부)
- `GET /api/v1/posts/{id}`
- `POST /api/v1/posts`
- `PATCH /api/v1/posts/{id}`

**주의:** `blockedUserId`와 다른 체계의 값(예: 별도 프로필 ID, 해시된 ID)을 내려주면 차단이 엉뚱한 사람에게 걸립니다. 반드시 동일한 유저 ID여야 합니다.

### (권장) `authorNickname` 추가

| 항목 | 값 |
|---|---|
| 필드명 | `authorNickname` |
| 타입 | `string` |
| 필수 여부 | 선택 (없으면 앱이 "유저 #12" 형태로 표시) |

현재 차단 관리 화면은 서버가 `blockedUserId`만 주기 때문에 목록을 "유저 #2"처럼 숫자로만 보여줍니다. 닉네임이 있으면 사용자가 자기가 누구를 차단했는지 알아볼 수 있습니다.

닉네임을 추가하실 경우 `BlockResponseDto`에도 같은 필드를 넣어주시면 차단 관리 화면에서 바로 쓸 수 있습니다.

### (권장) 차단한 유저의 글을 서버에서 제외

`GET /api/v1/posts` 응답에서, 요청자가 차단한 유저의 글을 **서버가 미리 걸러서** 내려주는 방식을 권합니다.

앱에서 클라이언트 측으로 거를 수도 있지만, 이 API는 페이지네이션(`page`, `size`)을 쓰기 때문에 문제가 생깁니다. `size=20`으로 받은 20건 중 5건을 앱이 지우면 사용자에게는 15건만 보이고, 페이지마다 개수가 들쭉날쭉해집니다. 무한 스크롤에서는 "다음 페이지가 있는데 화면은 비어 보이는" 상황도 생깁니다.

서버가 쿼리 단계에서 제외하면 `size`와 `hasNext`가 정확하게 유지됩니다.

---

## 4. 요청하지 않는 것

**"내 글인지" 여부를 알려주는 플래그(`isMine` 등)는 필요 없습니다.**

액세스 토큰의 JWT payload에 이미 `sub`로 유저 ID가 들어 있습니다:

```json
{ "sub": "1", "authorities": ["ROLE_USER"], "tokenType": "access", "iat": ..., "exp": ... }
```

앱이 `sub`를 읽어 `authorId`와 비교하면 내 글인지 판별할 수 있으므로, `authorId`만 있으면 충분합니다.

---

## 5. 기대하는 응답 형태

### 변경 전

```json
{
  "id": 2,
  "campsiteId": 1,
  "title": "제목",
  "content": "본문",
  "createdAt": "2026-08-04T06:14:05.568966"
}
```

### 변경 후

```json
{
  "id": 2,
  "campsiteId": 1,
  "authorId": 7,
  "authorNickname": "캠핑러버",
  "title": "제목",
  "content": "본문",
  "createdAt": "2026-08-04T06:14:05.568966"
}
```

`authorId`는 필수, `authorNickname`은 선택입니다. 기존 필드는 그대로 두고 추가만 하는 변경이므로 앱의 기존 동작에는 영향이 없습니다.

---

## 6. 반영 후 확인 방법

```bash
TOKEN=$(curl -s "https://campon.seohamin.com/api/v1/auth/dev/token?userId=1" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['accessToken'])")

# 1) 글 작성 후 응답에 authorId가 있는지
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"campsiteId":1,"title":"확인","content":"확인"}' \
  https://campon.seohamin.com/api/v1/posts

# 2) 목록 조회 시 items[] 안에 authorId가 있는지
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://campon.seohamin.com/api/v1/posts?campsiteId=1&size=5&page=0"
```

두 응답 모두에 `authorId`가 보이고, 그 값이 `POST /api/v1/blocks`의 `blockedUserId`로 그대로 사용 가능하면 완료입니다.

권장 사항까지 반영하셨다면, 서로 다른 유저 두 명으로 글을 쓴 뒤 한쪽을 차단하고 목록을 조회했을 때 차단한 유저의 글이 응답에서 빠지는지도 확인해 주세요.

---

## 7. 클라이언트 현황

앱은 이미 `authorId`를 읽도록 작성되어 있습니다 (`lib/main.dart`의 `CampPost.fromJson`). 서버가 필드를 내려주기 시작하면 앱 배포 없이도 파싱은 되지만, 차단 메뉴 노출과 삭제 버튼 소유자 판별은 클라이언트 수정과 함께 배포되어야 합니다.

문의: 이 문서의 요청 사항 중 구현이 어렵거나 다른 방식이 나은 부분이 있으면 알려주세요.
