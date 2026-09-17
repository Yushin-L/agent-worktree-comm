# agent-worktree-comm — 사람용 운영 가이드

이 디렉터리는 다중 에이전트 (PM + back + front + review) 작업 환경을 위한 **인프라 키트**입니다. 역할마다 Claude Code 또는 Codex를 선택할 수 있습니다. `README.md` 가 에이전트(LLM)가 따라야 할 메시지 규약 문서라면, 이 `README.human.md` 는 **사람이 환경을 띄우고 운영**하는 방법을 적은 문서입니다.

## 디렉터리 구성

```
agent-worktree-comm/
├── README.md             ← 에이전트용: 메시지 포맷·작업 플로우 규약
├── README.human.md       ← (이 파일) 사람용: 셋업 / 운영
├── agents                ← tmux 오케스트레이터 (실행 스크립트)
├── watch-inbox           ← 엔진 공통 외부 인박스 watcher
├── .agents.sh.example    ← 프로젝트별 설정 템플릿
├── .agents.sh            ← (gitignore) 실제 프로젝트 설정 — 사용자가 작성
├── role_templates/       ← 엔진 공통 역할 지침 템플릿
│   ├── pm.md             (init 시 엔진에 맞는 지침 파일 생성)
│   ├── back.md
│   ├── front.md
│   └── review.md
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

`pm | back | front | review` 4개. 새 ROLE 을 쓰려면 `role_templates/<role>.md`를 추가합니다. Claude로 실행할 역할은 `setting_example/<role>_settings.json`도 필요합니다. `agents init`은 선택한 엔진에 필요한 파일을 검사합니다.

ROLE 명은 워크트리 디렉터리 suffix, 메시지 인박스 디렉터리, tmux 세션 이름의 일관된 식별자로 쓰입니다.

## Claude Code / Codex 혼합 구성

`.agents.sh`에서 역할별 엔진을 지정합니다. 생략한 역할은 `DEFAULT_AGENT_ENGINE` 값(기본 `claude`)을 사용합니다.

```bash
PROJECT=myproject
ROLES=(pm back review)
REPO_URL=https://github.com/owner/repo.git

declare -A AGENT_ENGINES=(
  [pm]=codex
  [back]=claude
  [review]=codex
)

EXTERNAL_WATCHER=true
```

- 공통 원본: `role_templates/<role>.md`에 역할 책임과 협업 규칙 작성
- Claude 역할: 공통 원본으로 `CLAUDE.md` 생성, 별도로 `.claude/settings.json` 설치
- Codex 역할: 공통 원본으로 `AGENTS.md` 생성
- `setting_example/`은 Claude 전용 권한 설정이며 Codex에는 적용하지 않음
- 현재 지원 엔진은 Claude Code와 Codex이며, 다른 하네스는 실행·초기화 처리를 추가해야 함
- `EXTERNAL_WATCHER=true`: 각 tmux 세션에 `inbox-watch` 창을 추가하고 `messages/{role}/` 변경을 해당 에이전트 TUI에 전달
- 외부 watcher는 기본적으로 1초 polling을 사용하므로 `inotify-tools`가 없어도 동작
- `WATCH_POLL_INTERVAL=0.5`처럼 polling 간격을 조정 가능
- 자동화나 서버 부팅 시 `NO_ATTACH=true`를 사용하면 `agents up`이 세션 생성 후 터미널에 attach하지 않음

Codex 기본 실행 명령은 작업 디렉터리와 comm 디렉터리만 쓰도록 `workspace-write` sandbox를 사용하며, 무인 세션에서 승인 대기로 멈추지 않도록 approval policy를 `never`로 둡니다. 프로젝트별 조정은 `CODEX_CMD`로 덮어쓸 수 있습니다.

### 모델과 추론 강도 지정

`.agents.sh`에 엔진별 모델과 effort를 지정할 수 있습니다. 같은 엔진을 사용하는 모든 역할에 적용됩니다.

```bash
CODEX_MODEL=gpt-6-astra
CODEX_REASONING_EFFORT=high

CLAUDE_MODEL=claude-opus-5
CLAUDE_EFFORT=high
```

- Codex: 기본 실행 명령에 `--model gpt-6-astra -c 'model_reasoning_effort="high"'`를 추가합니다. 기존 sandbox와 comm 디렉터리 접근 옵션은 유지됩니다.
- Claude: `claude --model claude-opus-5 --effort high`로 실행합니다.
- 각 설정은 선택 사항입니다. 생략하거나 빈 값으로 두면 해당 옵션을 전달하지 않고 CLI 자체 설정을 따릅니다.
- `CODEX_CMD` 또는 `CLAUDE_CMD`를 지정하면 해당 엔진의 **전체 실행 명령을 재정의**합니다. 이 경우 위 모델·effort 설정은 무시되므로 필요한 옵션을 명령에 직접 포함하세요.
- 이미 실행 중인 세션에는 적용되지 않습니다. `agents up`은 기존 세션을 건너뛰므로 변경은 새로 시작하는 세션부터 반영됩니다.
- 모델 접근 권한과 지원 effort 값은 사용하는 계정·CLI·모델에 따라 달라집니다. 시작 후 세션에 표시된 모델과 effort를 확인하세요.

예를 들어 전체 명령을 직접 관리하려면 다음과 같이 설정할 수도 있습니다.

```bash
CLAUDE_CMD='claude --model claude-opus-5 --effort high'
CODEX_CMD="codex --model gpt-6-astra -c 'model_reasoning_effort=\"high\"' --no-alt-screen --sandbox workspace-write --ask-for-approval never --add-dir '$SCRIPT_DIR'"
```

설정 근거: [Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference), [GPT-6 Astra](https://developers.openai.com/api/docs/models/gpt-6-astra), [Claude Code model configuration](https://code.claude.com/docs/en/model-config).

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
#   → ROLES 의 각 값마다 git clone, 엔진별 역할 지침 복사 + 변수 치환,
#     messages/<role>, old/<role> 스캐폴드

# 4. 세션 기동
agent-worktree-comm/agents up

# 5. PM 과 대화
#   "이 프로젝트는 ... 도메인이고 ... 특수 규칙이 있어" 알려주면
#   PM 과 역할별 지침 파일(CLAUDE.md / AGENTS.md)의 프로젝트 규칙 정리
```

### Placeholder 치환 매핑

`role_templates/*` 와 `setting_example/*` 안의 placeholder 가 init 시 자동 치환됩니다:

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

- `agents up` 은 각 역할에 대해 `tmux new-session -d -s <PROJECT>-<role>` 으로 백그라운드 세션을 띄우고 설정된 `claude` 또는 `codex` 실행
- `BOOT_SLEEP` 초 대기 (claude 인터랙티브 프롬프트 렌더 시간 확보)
- `tmux send-keys` 로 엔진별 bootstrap prompt 전송. 외부 watcher 사용 시 에이전트 내부 watcher는 시작하지 않음
- 외부 watcher는 별도 `inbox-watch` tmux 창에서 파일 변경을 polling하고 역할의 `agent` 창에 처리 프롬프트 전송
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
