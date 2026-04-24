# 에이전트 권한 매트릭스 (Agent Permissions)

여러 워크트리에서 Claude Code 인스턴스를 자율 모드로 운영할 때, 각 인스턴스가 어떤 도구·명령을 자동 실행할 수 있고 어떤 것은 차단되는지를 명세한 문서. **새 레포지토리에 같은 협업 구조를 도입할 때 그대로 복사·수정해 사용**하는 것을 목표로 한다.

이 문서는 협업 구조 자체(역할 분담, 메시지 채널, 브랜치 플로우) 는 다루지 않는다 — 그건 `README.md` 참조. 여기는 **Claude Code의 `permissions` 설정 결정 근거와 구체 패턴**만.

---

## 0. 설계 철학

> **"넓게 allow, 좁게 deny"** — 위험한 일만 명시적으로 막고 나머지는 자유롭게.

이전 시도(자세한 화이트리스트)는 다음 문제로 실패했다:

- 복합 shell (`for ... do`, `&&`, `|`, `cmd1; cmd2`, heredoc) 이 단일 패턴 매칭에서 자주 빠짐 → 잦은 프롬프트
- 새 명령 등장할 때마다 settings 추가 필요 (운영 비용)
- `ls /abs/path` 같은 안전 명령이 path 한정 시에도 프롬프트 발생

자율 세션(사람이 안 붙어 있는 tmux 백그라운드 세션)에서는 프롬프트가 곧 **무한 대기**라 워크플로우가 막힌다. 따라서 **위험 패턴만 deny + 나머지 자유**가 실용적이다.

대신 deny 목록은 **신중하게** 설계한다 — 한 줄 빠뜨리면 사고 가능성.

---

## 1. 역할 (Role) 정의

| 역할 | 워크트리 접미사 | 코드 권한 | GitHub 권한 | 비고 |
|------|----------------|-----------|------------|------|
| **PM** (Product Manager) | `*_prom` | 코드 수정·커밋·머지 금지 | 이슈·PR 생성·편집·코멘트 (머지 제외) | 기획·브랜치 생성·PR 생성 담당 |
| **Frontend** | `*_front` | 프론트엔드 코드 자유. 백엔드 read-only | 이슈·PR 코멘트만 | 자기 영역만 commit/push |
| **Backend** | `*_back` | Go 코드·인프라 자유. 프론트 read-only | 이슈·PR 코멘트만 | 자기 영역만 commit/push |
| **Reviewer** | `*_review` | 코드 fetch·diff·읽기만. **수정·커밋·푸시 금지** | 이슈·PR 코멘트만 | PR 생성 승인 게이트 |

각 역할에 대응되는 책임은 `README.md`의 "워크트리별 역할" 섹션 참조.

---

## 2. 공통 settings.json 골격

모든 4개 워크트리가 공유하는 기본 구조:

```json
{
  "defaultMode": "acceptEdits",
  "additionalDirectories": [
    "~/path/to/llm-comm-docs"
  ],
  "permissions": {
    "allow": [
      "Read",
      "Grep",
      "Glob",
      "Edit",
      "Write",
      "NotebookEdit",
      "WebFetch",
      "WebSearch",
      "TodoWrite",
      "Monitor",
      "Bash(*)"
    ],
    "deny": [
      ...역할별 deny 목록...
    ]
  }
}
```

### 각 키의 의미

- **`defaultMode: "acceptEdits"`** — 파일 편집(`Edit`/`Write`/`NotebookEdit`)과 일반적인 파일시스템 명령(`mkdir`, `mv`, `cp` 등)을 **자동 승인**. 적용 범위: 워크트리 cwd + `additionalDirectories`.
- **`additionalDirectories`** — cwd 외부에서도 acceptEdits 효과를 받을 디렉토리. 워크트리 외부의 공유 소통 디렉토리(`llm-comm-docs/`) 같은 곳을 등록.
- **`Bash(*)` allow** — 모든 bash 명령을 일단 허용. 위험은 `deny`로 잡는다.
- **`Read`/`Grep`/`Glob` 등 도구 allow** — 파일·검색 도구는 전면 허용.

### 패턴 문법 (Claude Code permissions)

| 패턴 | 의미 |
|------|------|
| `Bash(cmd *)` | `cmd` 로 시작하는 bash 명령 (인자 무관) |
| `Bash(cmd arg *)` | `cmd arg` 로 시작 |
| `Bash(*)` | 모든 bash 명령 |
| `Edit(/abs/path/**)` | 절대경로 (단일 슬래시는 **프로젝트 루트 기준**) |
| `Edit(//abs/path/**)` | **파일시스템 절대경로** (이중 슬래시) |
| `Edit(~/path/**)` | 홈 디렉토리 기준 |
| `Edit(./path/**)` 또는 `Edit(path/**)` | cwd 기준 |
| `**` | 디렉토리 재귀 매칭 |
| `*` | 단일 path segment 매칭 |

복합 shell(`A && B`, `A | B`, heredoc)은 **각 부분이 분해되어 매칭**된다. `Bash(*)`로 풀어두면 분해 분제 없음.

**deny가 allow보다 우선** — `Bash(*)` allow에도 불구하고 `Bash(rm -rf *)` deny가 적용됨.

---

## 3. 공통 deny 목록

모든 4개 역할에 공통으로 적용되는 deny. 카테고리별 근거.

### 3.1 파괴적 git (히스토리·remote 손상)

```
Bash(git push --force *)
Bash(git push -f *)
Bash(git push --force-with-lease *)
Bash(git push --mirror *)
Bash(git push * --delete *)
Bash(git push * :*)
Bash(git reset --hard *)
Bash(git clean -f *)
Bash(git clean -fd *)
Bash(git branch -D *)
Bash(git filter-branch *)
```

근거: 공유 브랜치 force push는 다른 워크트리·CI를 깨뜨림. `reset --hard`·`clean -f`·`branch -D`는 미커밋 작업물 유실. `filter-branch`는 히스토리 재작성.

### 3.2 GitHub 위험 작업

```
Bash(gh pr merge *)
Bash(gh pr close *)
Bash(gh repo delete *)
Bash(gh release delete *)
```

근거: 머지·repo·release 삭제는 **사람만**. PR close도 신중해야 함.

### 3.3 시스템 파괴

```
Bash(rm -rf *)
Bash(rm -fr *)
Bash(sudo *)
Bash(chmod *)
Bash(chown *)
```

근거: `rm -rf` 사고·권한 변경 사고 차단. `sudo`는 자율 세션에 부적합.

### 3.4 패키지 무단 설치

```
Bash(npm install *)
Bash(npm i *)
Bash(go get *)
Bash(go install *)
Bash(pip install *)
```

근거: 의존성 도입은 의식적 결정 필요. 자동 설치는 보안·재현성 리스크.

### 3.5 호스트 테스트 실행 (docker-only 원칙)

```
Bash(go test *)
Bash(npm test *)
Bash(vitest *)
Bash(jest *)
Bash(pytest *)
```

근거: 호스트 환경 vs 컨테이너 환경 차이로 **거짓 안심** 발생. CI·prod와 동일한 컨테이너에서만 테스트.

### 3.6 Docker 파괴

```
Bash(docker system prune *)
Bash(docker volume rm *)
Bash(docker rmi *)
Bash(docker kill *)
```

근거: 다른 워크트리·서비스의 컨테이너·볼륨까지 영향 가능.

---

## 4. 역할별 추가 deny

### 4.1 PM (`*_prom`)

PM은 **코드를 수정·커밋·머지하지 않는다**. 단 GitHub 이슈·PR 생성·편집은 PM의 핵심 업무.

```
Bash(git commit *)
Bash(git add *)
Bash(git merge *)
Bash(git rebase *)
Bash(docker compose up *)
Bash(docker compose run *)
Bash(docker compose exec *)
```

| 차단 | 이유 |
|------|------|
| `git commit/add/merge/rebase` | PM은 코드 변경 안 함 |
| `docker compose up/run/exec` | PM은 컨테이너 안 돌림 |

`git push`는 **빈 task 브랜치 push** 용도로 허용 (PM이 task 브랜치 생성·remote 등록 담당).

### 4.2 Frontend (`*_front`), Backend (`*_back`)

GitHub 이슈·PR 생성·편집은 PM의 영역.

```
Bash(gh pr create *)
Bash(gh pr edit *)
Bash(gh issue create *)
Bash(gh issue edit *)
Bash(gh issue close *)
```

`gh issue/pr view/list/comment/diff/checks` 는 허용 (작업 컨텍스트 확인용).

front 추가:

```
Bash(npm ci *)
Bash(npm uninstall *)
Bash(npm audit fix *)
Bash(pnpm install *)
Bash(yarn add *)
```

근거: 프론트엔드 패키지 설치 우회 경로 차단.

### 4.3 Reviewer (`*_review`)

Reviewer는 **fetch·checkout·diff·읽기만** 한다. 코드 수정해도 git 차단으로 propagate 못 함 (사실상 무해), 하지만 워크플로우 명시성 위해 commit/push 자체도 deny.

```
Bash(git add *)
Bash(git commit *)
Bash(git push *)
Bash(git merge *)
Bash(git rebase *)
Bash(git stash *)
Bash(git reset *)
Bash(git clean *)
Bash(git branch -D *)
Bash(git branch -d *)
Bash(gh pr create *)
Bash(gh pr edit *)
Bash(gh issue create *)
Bash(gh issue edit *)
Bash(gh issue close *)
Bash(docker compose up *)
```

| 차단 | 이유 |
|------|------|
| 모든 git mutation | Reviewer는 코드를 변경·전파하지 않음 |
| `gh pr/issue` 쓰기 | 리뷰는 messages로, GitHub 이슈는 PM 영역 |
| `docker compose up` | Reviewer는 영구 기동 안 함. 테스트는 `docker compose run --rm` |

`docker compose run --rm`, `docker compose exec`, `docker run`, `docker exec` 는 허용 (테스트 실행용).

---

## 5. Edit/Write 정책

`defaultMode: acceptEdits` + `additionalDirectories` 조합으로 **모든 4개 역할이 자기 cwd + `llm-comm-docs/`를 자유롭게 편집**한다. 별도의 path-scoped Edit/Write 패턴은 두지 않는다.

### Reviewer가 코드를 수정하면?

Reviewer cwd에 코드 편집은 자동 승인되지만, **`git add/commit/push` 모두 deny**라서 커밋·전파 불가. 로컬 수정은 의미 없음. 따라서 위험 없음.

만약 더 엄격하게 하려면:

```json
"deny": [
  "Edit",
  "Write",
  "NotebookEdit",
  ...
]
"allow": [
  "Edit(~/path/to/llm-comm-docs/**)",
  "Write(~/path/to/llm-comm-docs/**)",
  ...
]
```

단점: scoped allow가 모든 경로 형식(상대·절대·`~`)에 일관되게 매칭되지 않아 종종 프롬프트. 권장하지 않음.

---

## 6. 새 레포지토리에 적용하는 법

### 6.1 워크트리 구조 결정

같은 4-role 패턴 그대로 쓰려면:

```
{repo-shared-parent}/
├── llm-comm-docs/                ← 이 디렉토리 (그대로 복사·재초기화)
├── {project}_front/              ← 독립 clone
├── {project}_back/               ← 독립 clone
├── {project}_prom/               ← 독립 clone (PM)
└── {project}_review/             ← 독립 clone
```

다른 역할 구성(예: `_qa`, `_devops` 추가)도 가능. 새 역할 추가 시:

1. 위 "공통 deny" + 새 역할의 책임 영역에 맞는 deny 추가
2. `messages/{새역할}/` 디렉토리 생성
3. 본 문서에 "역할별 추가 deny" 섹션 추가

### 6.2 settings.json 복사·치환

각 워크트리의 `.claude/settings.json` 에 본 문서의 골격 + 해당 역할 deny를 적용. 치환할 부분:

- `additionalDirectories`의 `~/path/to/llm-comm-docs` → 실제 경로
- 도메인별 패키지 매니저 deny (예: 백엔드가 Rust면 `Bash(cargo install *)` 추가)
- 도메인별 테스트 러너 deny (예: 백엔드가 Rust면 `Bash(cargo test *)` 추가, Java면 `Bash(mvn test *)`, `Bash(gradle test *)` 추가)

### 6.3 검증 절차

1. 한 역할(예: review)부터 단일 세션 띄우기
2. 가벼운 task로 시범 운영
3. 프롬프트가 자주 뜨는 패턴 발견 시 deny 누락 확인 또는 더 좁은 deny로 교체
4. 의도치 않은 명령 실행이 가능했는지 사후 점검 (audit)

### 6.4 운영 시 사고 대응

만약 자율 세션이 의도치 않은 동작을 하면:

```bash
tmux send-keys -t {session} Escape    # 현재 작업 중단
tmux kill-session -t {session}        # 세션 종료
```

복구 후 deny 패턴 보강 → 재시작.

---

## 7. 운영상 함정 (Pitfalls)

### 7.1 복합 shell 명령

`Bash(*)` allow면 무관. 화이트리스트 방식이면 `cmd1 | cmd2`, `cmd1 && cmd2` 가 단일 패턴에 매칭 안 되는 경우 빈번. 그래서 본 문서는 `Bash(*)` 권장.

### 7.2 필요한 위험 패턴 우회 차단

deny 목록이 너무 광범위하면 정상 작업도 막힌다. 예: `Bash(chmod *)` deny가 있으면 빌드 산출물의 실행권한 부여가 안 됨. 실제로 막혔을 때 "이 deny가 정말 필요한가?" 재검토.

### 7.3 Reviewer의 acceptEdits

Reviewer가 코드를 편집할 수 있다는 점이 직관에 어긋날 수 있으나, **git push deny가 propagation을 막아 사실상 무해**. 더 엄격한 격리가 필요하면 5절의 path-scoped 방식 고려 (단점 감수).

### 7.4 자율 세션 vs 인터랙티브 세션

본 문서의 모든 정책은 **사람이 실시간으로 붙어 있지 않은 자율 세션**을 가정한다. 인터랙티브 사용 시는 더 보수적인 화이트리스트도 유효.

---

## 8. 변경 관리

이 문서·settings.json은 **워크플로우 v2**의 일부. 변경 시:

- 본 문서 업데이트
- 4개 settings.json 중 영향받는 파일 동시 갱신
- `messages/` 채널로 모든 에이전트에 변경 통보 → 각자 세션 재시작 (settings는 세션 시작 시 로드)

---

## 9. 참고

- Claude Code 공식 docs: https://code.claude.com/docs/en/permissions.md
- 본 프로젝트의 협업 구조: `README.md`
- 세션 운영 가정: `README.md` → "세션 운영 가정 (자율 모드)"
