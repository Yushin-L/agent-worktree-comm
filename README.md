# llm-comm-docs

## 이 디렉토리는 무엇인가

워크트리 간 Claude Code 인스턴스가 **실시간 소통**하기 위한 디렉토리. 영구 기록(기획·이슈·결정)은 GitHub 이슈가 단일 진실원(SSOT)이며, 이곳은 진행 중 task의 로컬 소통 채널이다.

이 프로젝트는 하나의 git 저장소를 **여러 워크트리(독립 clone)로 분리**하여, 각 워크트리에 독립된 Claude Code 인스턴스를 붙여 운영한다. 각 인스턴스는 자기 역할(front, back, pm, review)에만 집중하고, 이 디렉토리를 통해 서로 맥락을 공유한다.

## 워크트리 전략

### 구조

```
worktree-drive/
├── llm-comm-docs/                         ← 공유 소통 문서 (git 밖)
│   ├── api-contracts/                     ← API 명세 (코드와 짝지어진 스펙)
│   ├── messages/                          ← 지향성 메시지 (수신자별 inbox)
│   │   ├── front/
│   │   ├── back/
│   │   ├── pm/
│   │   └── review/
│   └── old/                               ← 처리 완료된 메시지 아카이브
│       ├── front/
│       ├── back/
│       ├── pm/
│       └── review/
│
├── object_storage_for_tools_front/        ← 프론트엔드 워크트리
│   └── CLAUDE.md
│
├── object_storage_for_tools_back/         ← 백엔드 워크트리
│   └── CLAUDE.md
│
├── object_storage_for_tools_prom/         ← PM (Product Manager) 워크트리
│   └── CLAUDE.md
│
└── object_storage_for_tools_review/       ← Reviewer 워크트리
    └── CLAUDE.md
```

### 핵심 원칙

1. **역할 분리**: 각 워크트리의 `CLAUDE.md`가 역할을 제한한다. front는 `frontend/`, back은 Go 코드, pm·review는 문서/리뷰만.
2. **CLAUDE.md는 gitignore**: 워크트리마다 독립 관리.
3. **빌드/배포/테스트는 Docker**: 호스트에서 언어 네이티브 테스트 실행 금지. "테스트 실행 규칙" 참조.
4. **소통은 이 디렉토리를 통해**: 워크트리 간 직접 파일 수정 금지.
5. **지향성 우선 (Directed-first)**: 특정 수신자가 있는 모든 소통은 `messages/{수신자}/`로. 브로드캐스트는 드물게, 여러 inbox에 복사.
6. **영구 기록은 GitHub 이슈**: 기획·결정·토론·완료는 이슈/PR에 남는다. 로컬은 실시간·임시 전용.

각 인스턴스의 구체적인 도구·명령 권한 (`.claude/settings.json` 패턴) 은 별도 문서 `agent-permissions.md` 참조.

### 워크트리별 역할

| 워크트리 | 역할 | 수정 범위 | 비고 |
|----------|------|-----------|------|
| `*_front` | 프론트엔드 | `frontend/` 만 | 백엔드 API 엔드포인트 읽기 전용 |
| `*_back` | 백엔드 | Go 코드, 설정 파일 | `api-contracts/` 작성·유지 |
| `*_prom` | PM (Product Manager) | 코드 수정 금지 (문서만) | 기획·이슈·영향도 분석, GitHub 이슈·PR·브랜치 관리. 기술적 가능성, 필요성, 유저 영향, 사이드이펙트 판단 |
| `*_review` | Reviewer | 코드 수정 금지 (읽기·피드백만) | task 브랜치 diff 리뷰. correctness / security / tests / simplicity. blocker/major/minor/question 태그. PM PR 생성 승인 게이트 |

### 새 워크트리 추가 시

1. `worktree-drive/` 아래에 새 워크트리를 생성한다 (독립 clone).
2. 해당 워크트리에 역할에 맞는 `CLAUDE.md` 작성.
3. `CLAUDE.md`에 `llm-comm-docs/` 경로를 참조.
4. 세션 시작 시 자동 감시 설정 포함 (자기 inbox만).
5. `messages/{새역할}/`, `old/{새역할}/` 디렉토리 추가.
6. 이 README의 워크트리 역할 표와 구조 다이어그램 업데이트.

### 작업 플로우 (task별 브랜치)

각 워크트리는 독립 clone이며 모두 같은 remote repo에 push한다. 같은 task 참여자는 **같은 브랜치**에서 작업한다.

#### 브랜치 규칙

- 새 task → 새 브랜치 (`task/{name}` 또는 프로젝트 컨벤션)
- 같은 task의 모든 에이전트는 같은 브랜치 공유
- force push 금지 (공유 브랜치)
- rebase는 **로컬에서만**

#### 시작 (PM 주도)

PM이 GitHub 이슈를 먼저 만들고, 이후 브랜치를 생성·push한 뒤 관련 인스턴스에 메시지로 핑.

```bash
# 1. GitHub 이슈 생성 (기획 본문)
gh issue create --title "..." --body "..."

# 2. 브랜치 생성·push
git checkout main && git pull
git checkout -b task/{name}
git push -u origin task/{name}

# 3. messages/{front|back}/ 에 이슈 링크 + 브랜치명 핑
```

#### 작업 사이클 (front/back)

```bash
# 시작 전
git fetch
git checkout task/{name}
git pull --rebase

# 편집 + commit

# push 직전
git pull --rebase

# push
git push

# messages/{상대}/ 에 sha 포함 알림
```

#### 핵심 규칙

- **push 전 항상 `pull --rebase`** — 충돌 rebase로 흡수
- **push 후 즉시 메시지** — `sha abc123 pushed, {요지}` (상대가 pull 타이밍 결정)
- **커밋·PR에 이슈 번호 참조** — 커밋 메시지 `... (#123)`, PR 본문 `Closes #123`
- **동시 편집 우려 시** — `messages/{상대}/`에 "작업 중" soft lock

#### 리뷰 단계

구현 후 PR 머지 전 **Reviewer 승인** 필수.

1. 저자는 push 후 `messages/review/`에 리뷰 요청 (브랜치·sha·이슈 링크)
2. Reviewer가 `messages/{저자}/`에 피드백 (blocker/major/minor/question)
3. 저자가 blocker·major 해결 후 재푸시 → 재리뷰 요청
4. 통과 시 Reviewer가 `messages/pm/`에 `approved: task/{name} @ {sha}` 전송
5. PM은 승인 없이 PR을 생성하지 않는다 (실제 머지는 사람이 수행)

상세: `object_storage_for_tools_review/CLAUDE.md` 참조.

#### 종료

- Reviewer 승인 후 PM이 PR **생성**(`gh pr create`). 본문에 `Closes #123` 포함 → 머지 시 이슈 자동 close
- **실제 머지는 사람이 수행**. PM·에이전트는 `gh pr merge`나 직접 머지를 하지 않는다
- PM은 PR 생성 시점에 관련 메시지들을 `old/{수신자}/`로 아카이브 (사람 머지는 외부 이벤트로 취급)
- 머지·브랜치 삭제는 사람 몫

#### 예외

- **코드 변경이 없는 task** → 브랜치·리뷰 불필요, 이슈·메시지만
- **기존 브랜치에 합류** → 새 브랜치 만들지 않고 기존 이름을 메시지에 명시
- **트리비얼 변경** (오타, 주석) → PM 판단으로 리뷰 생략 가능. 로직 변경 있으면 리뷰 필수

## GitHub 이슈 연동 규칙

GitHub 이슈는 기획·토론·완료의 **단일 진실원(SSOT)**이다. 로컬 `messages/`는 이슈를 보조하는 실시간 채널.

### 담는 곳이 다르다

| 내용 | 위치 |
|------|------|
| 기획 본문·수용 기준·토론 | GitHub 이슈 |
| 설계 결정(근거·대안·합의) | GitHub 이슈 댓글 |
| 작업 할당·상태·완료 | GitHub 이슈 라벨·상태 |
| 빠른 질문·답변·핑 | `messages/` |
| push/review 알림 | `messages/` |
| API 명세 (코드 짝) | `api-contracts/` |

### 필수 룰

- **PM이 이슈 생성하면 즉시 `messages/{front|back}/`에 핑**: 이슈 번호 + 브랜치명 + 1~3문장 요지. GitHub는 실시간 감시 대상이 아니므로 이 핑이 없으면 에이전트가 못 본다.
- **긴 spec을 messages에 복붙 금지**: 이슈 링크만.
- **커밋·PR은 이슈 번호 참조**: 커밋 `... (#123)`, PR `Closes #123`.
- **중요한 토론은 이슈 댓글에**: 나중에 누가 와도 읽을 수 있도록. messages는 즉시성에만.

### 긴급 전역 공지

task와 무관한 긴급 이벤트(머지 프리즈, 인프라 점검)는 이슈에 담기 애매하다. 이 경우 `messages/front/`, `messages/back/`, `messages/review/`에 **동일 내용을 각각 복사**해서 보낸다. 드물게 일어나므로 복사 비용은 감내 가능.

## 로컬 Docker 환경 분리 규칙

각 워크트리가 독립 clone이고 모두 같은 `docker-compose.yml`을 쓰기 때문에, 동시에 `docker compose up` 돌리면 컨테이너명·포트가 충돌. 워크트리별 env로 해결.

### 원칙

- `docker-compose.yml`은 **하나만 커밋** (워크트리별 수정·stash 금지)
- `container_name:`·포트 하드코딩 금지
- 각 워크트리가 **자기 `.env`** 보유 (gitignored)
- `.env.example`을 커밋해 재현성 확보

### `docker-compose.yml` 작성 규칙

- **컨테이너명 충돌 방지** — 다음 둘 중 하나 선택:
  - **A**: `container_name:` 제거 → compose가 `${COMPOSE_PROJECT_NAME}_{service}_N`로 자동 생성
  - **B**: `container_name: ${COMPOSE_PROJECT_NAME:-<기본>}-<서비스>` 식 env prefix 템플릿 유지
  - 외부 스크립트(`docker inspect <name>` 등)가 고정 이름에 의존하면 B가 호환성상 안전. 의존이 없거나 리팩토링 가능하면 A가 표준
- 외부 포트: `"${API_PORT:-8080}:8080"` 식으로 env 템플릿
- 볼륨·네트워크도 필요 시 env로 분리

### 워크트리별 `.env` 예시

```
# front
COMPOSE_PROJECT_NAME=tools-front
API_PORT=18080
WEB_PORT=13000

# back
COMPOSE_PROJECT_NAME=tools-back
API_PORT=28080
WEB_PORT=23000

# review
COMPOSE_PROJECT_NAME=tools-review
API_PORT=38080
WEB_PORT=33000
```

포트 대역을 워크트리별로 분리(1xxxx, 2xxxx, 3xxxx).

### `.gitignore`

```
.env
docker-compose.override.yml
```

`.env.example`은 커밋. 실제 `.env`는 커밋 금지.

### 충돌 시

- 컨테이너명: `.env`의 `COMPOSE_PROJECT_NAME` 중복 확인
- 포트: `.env`에서 해당 포트 변경
- 새 서비스 포트 추가 시 `.env.example` 업데이트 + messages로 전원 공지

## 테스트 실행 규칙

**모든 테스트는 docker 컨테이너 내부에서 실행한다.** front, back, review 전원 동일.

### 금지

호스트에서 언어 네이티브 테스트 명령 직접 실행 금지.

- `go test ...` ❌
- `npm test`, `npm run test`, `vitest`, `jest` ❌
- `pytest`, `python -m unittest` ❌
- 그 외 호스트 직접 실행 ❌

### 허용

- `docker compose run --rm {service} {test-cmd}`
- `docker compose exec {service} {test-cmd}`
- 프로젝트 Make 타깃 (`make test`) — 내부적으로 docker를 쓸 때만
- 프론트엔드 **dev server** (`npm run dev`) — 테스트가 아니므로 예외

### 왜

- 컨테이너 vs 호스트 환경 차이 (OS, 라이브러리, 네트워크)
- CI·프로덕션은 컨테이너 → 호스트 통과는 거짓 안심 가능
- 재현성은 단일 소스(Dockerfile·compose)로

### 컨테이너 테스트가 깨지면

호스트로 우회하지 않는다. 원인 수정 또는 `messages/`로 escalate. reviewer는 blocker로 본다.

## 세션 운영 가정 (자율 모드)

각 워크트리의 Claude Code 인스턴스는 **사람이 실시간으로 붙어 있지 않은 자동화 세션**이라는 가정 하에 동작한다. tmux에 사람이 있든 없든 이 가정은 바뀌지 않는다.

### 규칙

- **세션 TUI의 stdout은 로그**일 뿐 통신 경로가 아니다. "어느 쪽 선호하시나요?" 같은 질문을 tmux에 출력해두면 PM이나 다른 에이전트에게 도달하지 않는다.
- **모든 질문·설계 선택지·블로커·중간 보고는 `messages/{수신자}/` 파일로 작성**한다. 이것이 유일한 통신 경로.
- 즉답을 요구하지 않는 결정은 **합리적 기본값(default)으로 진행**하고 근거를 메시지나 GitHub 이슈 댓글에 남긴다. 선택지를 열어두고 대기하면 전체 파이프라인이 멈춘다.
- **완료·push·에러 알림도 동일** — `messages/{상대}/`로.

### 체크리스트 (자기점검)

작업 중·종료 시 자신에게 물어본다:

- [ ] 설계 질문이 생겼다면 → `messages/pm/` 파일로 작성했는가? (tmux에만 답하지 않았는가)
- [ ] 결정 필요한데 즉답 없음 → 기본값으로 진행하고 근거 기록했는가?
- [ ] 완료 후 → `messages/{상대}/`에 sha·요지 적었는가?
- [ ] "이렇게 진행하겠습니다" 를 stdout에만 쓰고 끝내지 않았는가?

## 세션 시작 시 자동 감시

각 워크트리는 세션 시작 시 **자기 inbox만** 실시간 감시한다. 구조가 단순해져 감시 대상도 단순하다.

### 사전 요구사항

```bash
sudo apt install -y inotify-tools
```

### 에이전트별 감시 대상

| 에이전트 | 감시 디렉토리 |
|----------|---------------|
| front | `messages/front/`, `api-contracts/` |
| back | `messages/back/` |
| pm | `messages/pm/` |
| review | `messages/review/` |

- **back은 `api-contracts/`의 저자**이므로 자기 글 감시 불필요
- **front는 `api-contracts/` 업데이트 추적** 필요 → 감시
- **pm·review는 api-contracts read-only**, 필요 시 수동 조회

**`old/`는 감시 대상 아님**. 아카이브 이동이 inotify 이벤트를 만들면 안 된다.

### 감시 명령어

Claude Code `Monitor` 도구로 `persistent: true` 실행.

**front:**
```bash
inotifywait -m -r -q \
  -e close_write,moved_to,create \
  --format '%w%f %e' \
  /home/infmedix/dev/khdp/2026/worktree-drive/llm-comm-docs/messages/front \
  /home/infmedix/dev/khdp/2026/worktree-drive/llm-comm-docs/api-contracts
```

**back:**
```bash
inotifywait -m -q \
  -e close_write,moved_to,create \
  --format '%w%f %e' \
  /home/infmedix/dev/khdp/2026/worktree-drive/llm-comm-docs/messages/back
```

**pm:**
```bash
inotifywait -m -q \
  -e close_write,moved_to,create \
  --format '%w%f %e' \
  /home/infmedix/dev/khdp/2026/worktree-drive/llm-comm-docs/messages/pm
```

**review:**
```bash
inotifywait -m -q \
  -e close_write,moved_to,create \
  --format '%w%f %e' \
  /home/infmedix/dev/khdp/2026/worktree-drive/llm-comm-docs/messages/review
```

### 동작

- 파일 생성·저장 시 한 줄 이벤트 알림
- Claude는 파일 읽고 처리
- 세션 종료 시 감시 자동 종료
- 처리 완료된 메시지는 `old/{자기}/`로 이동 (감시 대상 밖)

### 이벤트 해석

| 이벤트 | 의미 | 기대 동작 |
|--------|------|----------|
| `messages/{me}/*.md CREATE` | 나에게 새 요청·질문·지시 | 읽고 응답 또는 작업 착수 |
| `messages/{me}/*.md CLOSE_WRITE` | 기존 메시지 수정 | 변경점 확인 |
| `api-contracts/*.md CREATE/CLOSE_WRITE` (front) | API 명세 추가·변경 | 읽고 프론트 영향 검토 |

## 디렉토리별 사용 규칙

### api-contracts/

백엔드가 API 엔드포인트 추가·변경 시 명세를 작성/업데이트.

- **작성자**: back
- **소비자**: front (감시), pm·review (필요 시 조회)
- **파일명**: 도메인별 (예: `webui-api.md`, `admin-api.md`)
- **내용**: 엔드포인트 경로, 메서드, 요청/응답, 인증

### messages/

특정 수신자에게 보내는 지향성 메시지. 요청, 질문, 작업 지시, 리뷰, 답변, push 알림 등 모든 일상 소통.

- **작성자**: 누구나
- **소비자**: 해당 수신자만 (감시)
- **위치**: `messages/{수신자}/`
- **파일명**: `YYYY-MM-DD-{발신자}-{주제}.md`
  - 예: `messages/front/2026-04-23-pm-quota-ui-plan.md`
  - 예: `messages/back/2026-04-23-front-quota-endpoint-question.md`

#### 메시지 파일 포맷

```markdown
---
from: pm              # front | back | pm | review
to: front             # 수신자 (디렉토리명과 일치)
reply-to:             # (선택) 답장일 때 원 메시지 경로
  messages/pm/2026-04-22-front-quota-question.md
re:                   # (선택) 관련 문서
  - api-contracts/webui-api.md
  - https://github.com/{owner}/{repo}/issues/123
---

# 제목

본문 — 필요한 만큼만.
```

#### 답장 규칙

답장은 **원 발신자의 inbox**에 쓴다.
- front가 back에게 질문 → `messages/back/...`
- back이 답변 → `messages/front/...` (`reply-to`로 원 메시지 링크)

### old/

**처리 완료된 메시지 아카이브**. 감시 대상 아님.

- **위치**: `old/{수신자}/` — 원래 inbox와 같은 구조
- **이동 시점**: 메시지(또는 스레드)가 **완전히 종결**됐을 때. mid-thread 이동 금지 (reply-to 링크 안정성).
  - 단발성 알림 (예: push 완료 통지) → 읽자마자 바로 이동 OK
  - 스레드(요청 → 답변 → 재요청 → 최종 답변) → 스레드 전체가 닫힌 뒤 일괄 이동
  - task 종료 시 → 해당 task 관련 메시지 일괄 이동
- **파일명**: inbox에서 이동 시 **그대로 유지**. 필요 시 `old/{수신자}/YYYY-MM/` 월별 하위 폴더로 정리 가능.

#### 왜 감시 대상 밖인가

`old/`를 감시하면 아카이브 이동마다 `moved_to` 이벤트가 발생해 무한 루프에 빠진다. `old/`는 반드시 watcher 경로 밖.

## 메시지 템플릿

중요한 건 내용이다. 템플릿은 최소로.

```markdown
---
from: {sender}              # front | back | pm | review
to: {recipient}             # 디렉토리명과 일치
reply-to: {원 메시지 경로}  # (선택) 답장일 때만
re:                         # (선택) 관련 이슈·API·메시지
  - https://github.com/.../issues/123
---

# {제목}

{본문 — 누가 누구에게 무엇을 왜. 필요한 만큼만.}
```

## 통신 흐름 예시

- **PM이 GitHub 이슈 생성 후 front에 핑**: `messages/front/2026-04-23-pm-quota-ui-issue123.md` (이슈 링크 + 브랜치명)
- **PM이 back에 이슈 핑**: `messages/back/2026-04-23-pm-quota-api-issue123.md`
- **front가 back에 엔드포인트 질문**: `messages/back/2026-04-23-front-quota-endpoint-question.md`
- **back이 answer**: `messages/front/2026-04-23-back-quota-endpoint-answer.md` (`reply-to`)
- **back이 확정한 API 명세**: `api-contracts/webui-api.md` (업데이트)
- **back이 reviewer에 리뷰 요청**: `messages/review/2026-04-23-back-quota-api-review-request.md`
- **reviewer가 back에 피드백**: `messages/back/2026-04-23-review-quota-api-round1.md`
- **reviewer가 PM에 승인 통보**: `messages/pm/2026-04-23-review-quota-api-approved.md`
- **PM이 PR 생성** (사람이 머지) → 관련 메시지들 `old/{수신자}/`로 일괄 이동
- **머지 프리즈 공지** (긴급 전역): `messages/front/`, `messages/back/`, `messages/review/`에 동일 내용 복사
