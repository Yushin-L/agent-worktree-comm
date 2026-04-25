# agent-worktree-comm — 사람용 운영 가이드

이 디렉터리는 다중 에이전트 (PM + back + front + review) 작업 환경을 위한 **인프라 키트**입니다. `README.md` 가 에이전트(LLM)가 따라야 할 메시지 규약 문서라면, 이 `README.human.md` 는 **사람이 환경을 띄우고 운영**하는 방법을 적은 문서입니다.

## 디렉터리 구성

```
agent-worktree-comm/
├── README.md             ← 에이전트용: 메시지 포맷·작업 플로우 규약
├── README.human.md       ← (이 파일) 사람용: 셋업 / 운영
├── agents                ← tmux 오케스트레이터 (실행 스크립트)
├── .agents.sh.example    ← 프로젝트별 설정 템플릿
├── .agents.sh            ← (gitignore) 실제 프로젝트 설정 — 사용자가 작성
├── claude.md_example/    ← 역할별 CLAUDE.md 템플릿 (init 이 복사)
│   ├── pm_CLAUDE.md
│   ├── back_CLAUDE.md
│   ├── front_CLAUDE.md
│   └── review_CLAUDE.md
├── setting_example/      ← 역할별 .claude/settings.json 템플릿 (init 이 복사)
│   ├── pm_settings.json
│   ├── back_settings.json
│   ├── front_settings.json
│   └── review_settings.json
├── messages/             ← 에이전트 간 실시간 채널 (역할별 인박스)
│   ├── pm/
│   ├── back/
│   ├── front/
│   └── review/
├── old/                  ← 처리된 메시지 아카이브 (역할별)
│   ├── pm/
│   └── ...
├── api-contracts/        ← 백엔드 API 계약 (백엔드가 작성)
└── agent-permissions.md
```

## 사용 가능한 ROLES (표준 vocab)

`pm | back | front | review` 4개. 새 ROLE 을 쓰려면 `claude.md_example/<role>_CLAUDE.md` 와 `setting_example/<role>_settings.json` 두 템플릿을 먼저 추가해야 합니다 — 이게 없으면 `agents init` 이 거부합니다.

ROLE 명은 워크트리 디렉터리 suffix, 메시지 인박스 디렉터리, tmux 세션 이름의 일관된 식별자로 쓰입니다.

## 일상 운영 (이미 셋업된 프로젝트)

`agents` 의 모든 명령은 **프로젝트 root 에서 호출**합니다 (= comm 디렉터리의 부모 = 워크트리들과 같은 레벨).

| 동작 | 명령 | 설명 |
|---|---|---|
| 4 세션 일괄 기동 + PM 진입 | `agent-worktree-comm/agents up` | idempotent — 이미 떠있으면 skip + 그대로 attach |
| 일괄 종료 | `agent-worktree-comm/agents down` | 작업 종료 / 머신 자원 회수 시점에만. 태스크마다 down 안 함 |
| 세션별 상태 dump | `agent-worktree-comm/agents status` | attach 없이 마지막 5줄 점검 |
| 특정 역할 attach | `agent-worktree-comm/agents attach [role]` | role 생략 시 ATTACH_TARGET (기본 pm) |
| detach (세션 유지) | `Ctrl+B d` | tmux 표준 |

매번 `agent-worktree-comm/` 타이핑이 귀찮으면 alias:
```bash
# ~/.bashrc 또는 ~/.zshrc
alias agents='./agent-worktree-comm/agents'   # 프로젝트 root 에서만 동작
```

### SSH 끊김 대응

tmux 세션은 SSH 단절을 견딥니다. 끊긴 후 재접속하면 `agents up` 또는 `tmux attach -t <PROJECT>-pm` 으로 PM conversation 그대로 복귀.

## 새 프로젝트 셋업

### 전제

- git 인증 (gh CLI / SSH key / PAT) 이 미리 설정돼 있어야 함. `agents init` 중 clone 실패하면 git 에러 그대로 노출되며 abort.

### 단계

```bash
# 1. 프로젝트 디렉터리 생성 + comm repo clone
mkdir myproject
cd myproject
git clone https://github.com/Yushin-L/agent-worktree-comm.git

# 2. .agents.sh 작성
cd agent-worktree-comm
cp .agents.sh.example .agents.sh
$EDITOR .agents.sh
#   PROJECT=myproject
#   ROLES=(pm back review)              # 사용할 역할만 부분집합으로
#   REPO_URL=https://github.com/owner/repo.git

# 3. init 실행 (프로젝트 root 에서)
cd ..
agent-worktree-comm/agents init
#   → ROLES 의 각 값마다 git clone, CLAUDE.md/settings.json 복사 + 변수 치환,
#     messages/<role>, old/<role> 스캐폴드

# 4. 세션 기동
agent-worktree-comm/agents up

# 5. PM 과 대화
#   "이 프로젝트는 ... 도메인이고 ... 특수 규칙이 있어" 알려주면
#   PM 이 4개 CLAUDE.md 에 customization 섹션 추가
```

### Placeholder 치환 매핑

`claude.md_example/*` 와 `setting_example/*` 안의 placeholder 가 init 시 자동 치환됩니다:

| Placeholder | 치환값 |
|---|---|
| `<project>` | `.agents.sh` 의 `PROJECT` |
| `<ABS-PATH-TO>` | init 시점의 project root 절대경로 |

새 placeholder 추가는 `agents` 스크립트의 `cmd_init()` 의 `sed` 라인에 같이 추가.

### 불규칙 워크트리 레이아웃

기본 디렉터리 명규약: `<repo-name><SEPARATOR><role>` (e.g. `myrepo_pm`). repo-name 은 `REPO_URL` 의 마지막 path component 에서 자동 추출. SEPARATOR 기본값은 `_`.

다른 레이아웃이 필요하면 `.agents.sh` 에서 `worktree_dir()` 함수 직접 정의:

```bash
PROJECT=fhir
ROLES=(pm back review)
REPO_URL=https://github.com/owner/fhir-server.git

worktree_dir() {
  case "$1" in
    pm) echo "fhir-main" ;;
    *)  echo "fhir-worktree-$1" ;;
  esac
}
```

함수가 정의돼 있으면 `SEPARATOR` 와 자동 derived 이름은 무시됩니다.

## 동작 원리 (필요할 때 참고)

- `agents up` 은 각 역할에 대해 `tmux new-session -d -s <PROJECT>-<role>` 으로 백그라운드 세션을 띄우고 `claude` 실행
- `BOOT_SLEEP` 초 대기 (claude 인터랙티브 프롬프트 렌더 시간 확보)
- `tmux send-keys` 로 `BOOTSTRAP_PROMPT` 전송 → 각 에이전트가 자기 CLAUDE.md 의 Session Startup Watcher 지침을 읽고 inbox 감시 시작
- 마지막에 `tmux attach -t <PROJECT>-<ATTACH_TARGET>` 으로 PM 세션 진입
- `down` 은 `tmux kill-session` (claude 는 SIGTERM 으로 정상 종료)
- `status` 는 각 세션의 마지막 5줄 캡처
- `init` 은 각 ROLE 별로 `git clone $REPO_URL`, 템플릿 복사 + sed 치환, messages/old 스캐폴드

## 트러블슈팅

| 증상 | 원인 / 해결 |
|---|---|
| 세션은 떴는데 부트스트랩 프롬프트가 사라짐 | claude 부팅이 `BOOT_SLEEP` 보다 늦었음. `.agents.sh` 에 `BOOT_SLEEP=4` 등으로 늘리기 |
| `worktree missing: ...` | 해당 역할의 워크트리 디렉터리가 없음. `agents init` 안 했거나 디렉터리가 삭제됨. 또는 `worktree_dir()` 결과 점검 |
| `agents init` 이 즉시 abort | (a) 이미 worktree 가 있음 — 정상 가드. (b) `.agents.sh` 의 ROLES 에 example 템플릿 없는 값. (c) git 인증 미설정 → clone 단계에서 fail |
| `agents up` 후 attach 직후 detach 됨 | nested tmux. 외부 tmux 안에서 또 호출하면 발생. 외부 tmux 에서 빠져나오거나 `tmux switch-client` 로 처리 |
| SSH 끊긴 뒤 재접속 시 세션이 안 보임 | `tmux ls` 가 비었다면 새 머신/사용자로 접속한 것. 같은 사용자 같은 머신이면 세션은 살아있어야 정상. `tmux ls 2>&1` 로 에러 메시지 확인 |
| 메시지가 archive 가 안 돼 inbox 가 쌓임 | PM 책임. 작업 thread 끝나면 `messages/{role}/` 의 처리된 파일을 `old/{role}/` 로 이동. 자세한 규약은 `README.md` |
| 같은 머신에 여러 프로젝트 동시 운영 | 세션명이 `<PROJECT>-<role>` 이라 prefix 충돌 없음. `tmux ls | grep '^<PROJECT>-'` 로 본 프로젝트만 필터 |

## 운영 팁

- **태스크 단위로 `agents down` 하지 않음** — tmux 세션은 SSH 끊겨도 살아있어서, 다음 task 가 들어오면 PM 에 지시만 추가하면 같은 conversation 으로 이어감. PM 의 누적 컨텍스트가 큰 자산. `down` 은 하루 작업 종료 / 머신 자원 회수 / 프로젝트 전환 시점에만.
- **여러 프로젝트 동시 운영** — 세션 namespace 가 `<PROJECT>-` prefix 로 격리됨. 각 프로젝트 디렉터리에서 `agents up` 따로 돌리면 됨.
- **`claude --continue` 로 부팅** — `.agents.sh` 에 `CLAUDE_CMD="claude --continue"` 두면 매번 새 conversation 이 아니라 직전 세션 이어감. 부트스트랩 프롬프트는 매번 들어가지만 watcher 가 이미 있으면 에이전트가 알아서 무시.
- **`.agents.sh` 는 gitignore 대상** — 프로젝트별 로컬 설정이라 comm repo 에 커밋되지 않아야 함. 새 프로젝트마다 `.agents.sh.example` 복사해서 작성.

## 변경 이력

- 2026-04-24 초안 (drive 프로젝트 기반)
- 2026-04-26 `agents init` 추가 (clone 기반 신규 프로젝트 부트스트랩), ROLES vocab 표준화 (`pm | back | front | review`), placeholder 치환 매핑 정리
