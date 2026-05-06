# agent-worktree-comm

## What is this directory

A directory for **real-time communication** between Claude Code instances across worktrees. The permanent record (plans, issues, decisions) lives in GitHub issues as the single source of truth (SSOT); this directory is the local channel for in-flight tasks.

This project splits a single git repository into **multiple worktrees (independent clones)**, attaching an independent Claude Code instance to each. Each instance focuses on its own role (front, back, pm, review) and shares context through this directory.

## Worktree Strategy

### Structure

```
<repo-shared-parent>/
├── agent-worktree-comm/                    ← shared comm docs (outside any git worktree)
│   ├── api-contracts/                      ← API specs (paired with code)
│   ├── messages/                           ← directed messages (per-recipient inbox)
│   │   ├── front/
│   │   ├── back/
│   │   ├── pm/
│   │   └── review/
│   └── old/                                ← archive of processed messages
│       ├── front/
│       ├── back/
│       ├── pm/
│       └── review/
│
├── <project>_front/                        ← frontend worktree
│   └── CLAUDE.md
│
├── <project>_back/                         ← backend worktree
│   └── CLAUDE.md
│
├── <project>_prom/                         ← PM (Product Manager) worktree
│   └── CLAUDE.md
│
└── <project>_review/                       ← Reviewer worktree
    └── CLAUDE.md
```

### Core Principles

1. **Role separation**: each worktree's `CLAUDE.md` constrains its role. front owns `frontend/`, back owns server code, pm/review handle docs/review only.
2. **CLAUDE.md is gitignored**: managed independently per worktree.
3. **Build/deploy/test via Docker**: never run language-native tests on the host. See "Test Execution Rule".
4. **Communication via this directory**: no direct cross-worktree file edits.
5. **Directed-first**: any message with a specific recipient goes to `messages/{recipient}/`. Broadcasts are rare; copy into multiple inboxes when needed.
6. **Permanent record is GitHub issues**: plans, decisions, discussion, completion live in issues/PRs. Local channel is real-time/ephemeral only.

For each instance's tool / command permissions (`.claude/settings.json` patterns), see the companion document `agent-permissions.md`.

### Roles per Worktree

| Worktree | Role | Edit scope | Notes |
|----------|------|------------|-------|
| `*_front` | Frontend | `frontend/` only | Backend API endpoints read-only |
| `*_back` | Backend | server code, config files | Authors/maintains `api-contracts/` |
| `*_prom` | PM (Product Manager) | no code edits (docs only) | Plans / issues / impact analysis. Manages GitHub issues, PRs, branches. Judges feasibility, necessity, user impact, side effects |
| `*_review` | Reviewer | no code edits (read & feedback only) | Reviews task-branch diffs. correctness / security / tests / simplicity. Tags blocker / major / minor / question. Approval gate before PM creates PR |

### Adding a New Worktree

1. Create the new worktree under `<repo-shared-parent>/` (independent clone).
2. Author a role-appropriate `CLAUDE.md` for that worktree.
3. Reference the `agent-worktree-comm/` path in the new `CLAUDE.md`.
4. Include the session-start auto-watcher (own inbox only).
5. Add `messages/{new-role}/` and `old/{new-role}/` directories.
6. Update the role table and structure diagram in this README.

### Workflow (per-task branches)

Each worktree is an independent clone but all push to the same remote. Same-task agents share **the same branch**.

#### Canonical Task Flow (end-to-end)

One task = one issue = one branch = **one PR**. Every task follows this sequence; deviations require explicit PM call-out in the issue.

```
PM: 이슈 작성 + 브랜치 생성·push + task 브랜치 체크아웃 유지 + back/front 핑 (메시지 파일)
  ↓
back: pull → 작업 → push → 핑 (front if needed / review / pm)
  ↓                                          ↘
front: pull → 작업 → push → 핑 (back if needed / review / pm)
  ↓                                          ↘
PM: pull --ff-only (누적 흡수) → diff 검토 → 의견·결정 메시지 (필요 시)
  ↓
review: 누적된 sha 전체 검토 → blocker/major 피드백 또는 approved → pm 핑
  ↓
PM: 한 PR 생성 (gh pr create, 본문에 Closes #issue) → 메시지 아카이브 → task 브랜치에서 대기
  ↓
사람: 테스트 → 머지 + 브랜치 삭제 → PM 에 머지 완료 알림
  ↓
PM: main 으로 복귀
```

**한 브랜치 = 한 PR.** backend / frontend 가 같은 task 면 같은 브랜치에 누적되고, **PR 도 하나로 묶인다**. 분리 PR (backend PR + frontend PR) 은 명시 예외 케이스 (예: API contract 를 frontend 가 소비하기 전 backend pre-publish 가 필요한 경우) 가 아니면 금지. 분리하고 싶으면 task 자체를 두 이슈로 쪼개고 두 브랜치를 만든 다음 시작했어야 한다 — 작업 도중에 갈라치기 하지 않는다.

front / back 이 "PR 두 개 만들까요?" 라고 PM 에게 묻는 일이 없도록 한다. 같은 브랜치 위에 작업했으면 자동으로 한 PR 이다.

**PM 의 워크트리 위치**: PM 은 task 시작 시 task 브랜치를 체크아웃한 뒤 **사람이 PR 을 머지했다고 확인할 때까지** 그 브랜치에 머무른다. main 으로 돌아오는 시점은 머지 완료 확인 직후 한 번뿐. 이유: (1) PM 의 메시지·결정·리뷰 의견은 PR 에 실제로 들어갈 코드를 봐야 의미가 있고 main 에 앉아 있으면 누적 변경이 working tree 에 반영되지 않아 의견 형성이 둔해진다. (2) PR 오픈 후에도 사람이 이 워크트리에서 직접 테스트하는 경우가 있어 task 브랜치 working tree 가 그대로 유지되어야 한다. front/back push 알림이 오면 `git pull --ff-only` 로 흡수 (PR 후 review-driven follow-up 커밋 포함).

#### Branch Rules

- New task → new branch (`task/{name}` or project convention)
- All agents working on the same task share the same branch
- No force push (shared branch)
- Rebase **locally only**

#### Long-lived Deploy Branches (`deploy/*`)

Deploy branches (`deploy/airgap`, `deploy/*`) are long-lived and shared across teams. They periodically need to absorb `main` changes via rebase, which usually requires force-push. The roles are:

- **PM**: dry-run rebase / `fetch` / `log` / `diff` for conflict-area analysis is OK (read-only mechanics). **Conflict resolution + force-push is a handoff** — PM does not perform either.
- **Handoff target**: the agent owning the file footprint where conflicts concentrate. Backend-heavy → `back`. Frontend-heavy → `front`. If both are hit, the larger-footprint side leads and pings the other when they reach the smaller footprint.
- **Force-push permission**: must be explicit in the message (e.g. `force-push 권한 위임: deploy/airgap rebase 후 origin 업데이트`).
- **Tracking**: deploy-branch rebases tied to a specific main-side merge should be referenced in the corresponding deploy issue (e.g. `#93` for airgap), not a new task issue.

#### Starting (PM-driven)

PM first creates the GitHub issue, then creates / pushes the branch, then pings the relevant instances via messages.

```bash
# 1. Create the GitHub issue (plan body)
gh issue create --title "..." --body "..."

# 2. Create and push the branch
git checkout main && git pull
git checkout -b task/{name}
git push -u origin task/{name}

# 3. Ping messages/{front|back}/ with issue link + branch name
```

#### Work Cycle (front / back)

```bash
# Before starting
git fetch
git checkout task/{name}
git pull --rebase

# Edit + commit

# Right before push
git pull --rebase

# Push
git push

# Send messages/{recipient}/ notification with the sha
```

#### Core Rules

- **Always `pull --rebase` before push** — absorb conflicts via rebase
- **Notify immediately after push** — `sha abc123 pushed, {summary}` (recipient decides pull timing)
- **Reference the issue in commit / PR** — commit message `... (#123)`, PR body `Closes #123`
- **Concurrency concern** → write a "working on it" soft lock in `messages/{recipient}/`

#### Review Step

Reviewer approval is **required** before PR merge.

1. After push, the author sends a review request to `messages/review/` (branch / sha / issue link).
2. Reviewer leaves feedback in `messages/{author}/` (blocker / major / minor / question).
3. Author resolves blockers / majors and re-pushes → re-requests review.
4. On pass, Reviewer sends `approved: task/{name} @ {sha}` to `messages/pm/`.
5. PM does not create the PR without approval. (The actual merge is performed by a human.)

Details: see `<project>_review/CLAUDE.md`.

#### Closing

- After approval, PM **creates** the PR (`gh pr create`). Body must include `Closes #123` so the issue auto-closes on merge.
- **A human performs the actual merge.** PM / agents never run `gh pr merge` or merge directly.
- At PR creation time, PM archives related messages to `old/{recipient}/` (the human's merge is treated as an external event).
- Branch deletion (local + remote) is the human's responsibility post-merge.

#### Exceptions

- **Code-free task** → no branch / review needed; issue and messages only
- **Joining an existing branch** → don't create a new one; cite the existing branch name in the message
- **Trivial change** (typos, comments) → review may be skipped at PM's discretion. Any logic change requires review.

## GitHub Issue Integration Rules

GitHub issues are the **single source of truth (SSOT)** for plans, discussion, and completion. Local `messages/` is a real-time channel that complements issues.

### Where things go

| Content | Location |
|---------|----------|
| Plan body / acceptance criteria / discussion | GitHub issue |
| Design decisions (rationale, alternatives, agreement) | GitHub issue comments |
| Task assignment / status / completion | GitHub issue labels / state |
| Quick questions / answers / pings | `messages/` |
| push / review notifications | `messages/` |
| API specs (paired with code) | `api-contracts/` |

### Mandatory Rules

- **Once PM creates an issue, immediately ping `messages/{front|back}/`**: issue number + branch name + 1–3 sentence summary. Agents don't watch GitHub in real time, so without this ping they won't see the issue.
- **Don't paste long specs into messages**: link to the issue only.
- **Reference the issue in commits / PRs**: commit `... (#123)`, PR `Closes #123`.
- **Important discussion goes in issue comments**: so anyone arriving later can read it. messages/ is for immediacy only.

### Urgent Global Broadcast

For task-unrelated urgent events (merge freeze, infra maintenance) that don't fit a single issue, **copy the same content** into `messages/front/`, `messages/back/`, and `messages/review/`. These are rare, so the duplication cost is acceptable.

## Local Docker Environment Isolation

Each worktree is an independent clone, all sharing the same `docker-compose.yml`. Running `docker compose up` simultaneously would collide on container names / ports. Per-worktree env files resolve this.

### Principles

- **Commit a single `docker-compose.yml`** (no per-worktree edits or stashes)
- No hardcoded `container_name:` or ports
- Each worktree owns its own `.env` (gitignored)
- Commit `.env.example` for reproducibility

### `docker-compose.yml` Authoring Rules

- **Avoid container-name collisions** — choose one of:
  - **A**: omit `container_name:` → compose auto-generates `${COMPOSE_PROJECT_NAME}_{service}_N`
  - **B**: keep `container_name: ${COMPOSE_PROJECT_NAME:-<default>}-<service>` env-prefix template
  - If external scripts (`docker inspect <name>` etc.) depend on the fixed name, B is safer for compatibility. Without that dependency or with refactoring possible, A is the standard.
- External ports: env-template like `"${API_PORT:-8080}:8080"`
- Volumes / networks split via env when needed

### Per-Worktree `.env` Examples

```
# front
COMPOSE_PROJECT_NAME=<project>-front
API_PORT=18080
WEB_PORT=13000

# back
COMPOSE_PROJECT_NAME=<project>-back
API_PORT=28080
WEB_PORT=23000

# review
COMPOSE_PROJECT_NAME=<project>-review
API_PORT=38080
WEB_PORT=33000
```

Separate port bands per worktree (1xxxx, 2xxxx, 3xxxx).

### `.gitignore`

```
.env
docker-compose.override.yml
```

Commit `.env.example`. Never commit the real `.env`.

### On Collision

- Container name: check for duplicate `COMPOSE_PROJECT_NAME` in `.env`
- Port: change the relevant port in `.env`
- When adding a new service port: update `.env.example` + announce via messages to everyone

## Test Execution Rule

**All tests run inside docker containers.** Same rule for front, back, and review.

### Forbidden

Don't run language-native test commands on the host.

- `go test ...` ❌
- `npm test`, `npm run test`, `vitest`, `jest` ❌
- `pytest`, `python -m unittest` ❌
- Any other host-direct execution ❌

### Allowed

- `docker compose run --rm {service} {test-cmd}`
- `docker compose exec {service} {test-cmd}`
- Project make targets (`make test`) — only when they wrap docker
- Frontend **dev server** (`npm run dev`) — exception: not a test

### Why

- Container vs host environment differences (OS, libraries, network)
- CI / production run in containers → host pass is false comfort
- Reproducibility from a single source (Dockerfile / compose)

### When the Container Test Breaks

Don't bypass to host. Fix the root cause or escalate via `messages/`. Reviewer treats this as a blocker.

## Autonomous Session Assumption

Each worktree's Claude Code instance operates under the assumption that it is an **automated session with no human attached in real time**. Whether or not a person is at the tmux pane, this assumption does not change.

### Rules

- **The session TUI's stdout is a log**, not a communication channel. Writing "Which option do you prefer?" to tmux will not reach PM or other agents.
- **All questions, design choices, blockers, and intermediate reports are written as `messages/{recipient}/` files.** This is the only communication path.
- **"ping" = message file creation.** Wherever this doc (or any agent CLAUDE.md) says "ping the recipient", create a file at `messages/{recipient}/{date}-{sender}-{topic}.md`. The word is shorthand, not a separate action.
- For decisions that don't need an immediate answer, **proceed with a sensible default** and log the rationale in a message or GitHub issue comment. Holding choices open and waiting stalls the entire pipeline.
- **Completion / push / error notifications follow the same path** — via `messages/{recipient}/`.

### Decision tree — when you want to ask another agent something

1. **Blocking** (cannot proceed without an answer) → write the message file, wait for response.
2. **Pre-authorized** (PM / spec already greenlit this) → just proceed, report result via message. "Let me double-check first" written to console and idling is neither — it is the **worst option**.
3. **Non-blocking but rationale non-obvious** → proceed with sensible default, log rationale in a message or issue comment.

If you catch yourself writing a question or status to the console addressed to another agent, **stop and move that text into a message file**.

### Self-Check Checklist

Ask yourself during and at the end of work:

- [ ] If a design question came up → did I write a `messages/pm/` file? (Did I avoid answering only into tmux?)
- [ ] Decision needed but no immediate response → did I proceed with a default and record the rationale?
- [ ] After completion → did I write the sha + summary into `messages/{recipient}/`?
- [ ] Did I avoid ending with "I'll proceed like this" only on stdout?

## Session Startup Auto-Watch

On session start, each worktree watches **its own inbox only** in real time. The simpler the structure, the simpler the watch target.

### Prerequisite

```bash
sudo apt install -y inotify-tools
```

### Watch Target per Agent

| Agent | Watch directories |
|-------|-------------------|
| front | `messages/front/`, `api-contracts/` |
| back | `messages/back/` |
| pm | `messages/pm/` |
| review | `messages/review/` |

- **back is the author of `api-contracts/`** → no need to watch its own writes
- **front needs to track `api-contracts/` updates** → watch
- **pm / review treat api-contracts as read-only**, query on demand

**`old/` is not watched.** Archive moves must not generate inotify events.

### Watch Commands

Run via Claude Code's `Monitor` tool with `persistent: true`. Replace `<ABS-PATH-TO>` with the absolute path to the parent directory of `agent-worktree-comm/`.

**front:**
```bash
inotifywait -m -r -q \
  -e close_write,moved_to,create \
  --format '%w%f %e' \
  <ABS-PATH-TO>/agent-worktree-comm/messages/front \
  <ABS-PATH-TO>/agent-worktree-comm/api-contracts
```

**back:**
```bash
inotifywait -m -q \
  -e close_write,moved_to,create \
  --format '%w%f %e' \
  <ABS-PATH-TO>/agent-worktree-comm/messages/back
```

**pm:**
```bash
inotifywait -m -q \
  -e close_write,moved_to,create \
  --format '%w%f %e' \
  <ABS-PATH-TO>/agent-worktree-comm/messages/pm
```

**review:**
```bash
inotifywait -m -q \
  -e close_write,moved_to,create \
  --format '%w%f %e' \
  <ABS-PATH-TO>/agent-worktree-comm/messages/review
```

### Behavior

- One-line event notification on file create / save
- Claude reads the file and processes it
- Watcher terminates automatically on session end
- Processed messages move to `old/{self}/` (outside the watch path)

### Event Interpretation

| Event | Meaning | Expected action |
|-------|---------|----------------|
| `messages/{me}/*.md CREATE` | new request / question / instruction for me | read and respond, or start work |
| `messages/{me}/*.md CLOSE_WRITE` | existing message edited | check the diff |
| `api-contracts/*.md CREATE/CLOSE_WRITE` (front) | API spec added / changed | read and assess frontend impact |

## Per-Directory Usage Rules

### api-contracts/

Backend authors / updates the spec when adding or changing API endpoints.

- **Author**: back
- **Consumers**: front (watches), pm / review (on-demand)
- **Filename**: per domain (e.g. `webui-api.md`, `admin-api.md`)
- **Content**: endpoint path, method, request / response, auth

### messages/

Directed messages with a specific recipient. Requests, questions, work assignments, reviews, replies, push notifications — all everyday communication.

- **Author**: anyone
- **Consumer**: only the named recipient (watching)
- **Location**: `messages/{recipient}/`
- **Filename**: `YYYY-MM-DD-{sender}-{topic}.md`
  - e.g. `messages/front/2026-04-23-pm-quota-ui-plan.md`
  - e.g. `messages/back/2026-04-23-front-quota-endpoint-question.md`

#### Message File Format

```markdown
---
from: pm              # front | back | pm | review
to: front             # recipient (matches the directory name)
reply-to:             # (optional) original message path when replying
  messages/pm/2026-04-22-front-quota-question.md
re:                   # (optional) related references
  - api-contracts/webui-api.md
  - https://github.com/{owner}/{repo}/issues/123
---

# Title

Body — only as much as needed.
```

#### Reply Rule

Replies go into the **original sender's inbox**.
- front asks back a question → `messages/back/...`
- back replies → `messages/front/...` (with `reply-to` linking the original)

### old/

**Archive of processed messages.** Not watched.

- **Location**: `old/{recipient}/` — same structure as the original inbox
- **When to move**: when the message (or thread) is **fully concluded**. No mid-thread moves (preserves `reply-to` link stability).
  - Single-shot notifications (e.g. push completion) → move as soon as read
  - Threads (request → reply → re-request → final reply) → move all at once after the thread is sealed
  - On task close → move all task-related messages together
- **Filename**: keep **as-is** when moving from inbox. Optional monthly subfolders like `old/{recipient}/YYYY-MM/`.

#### Why It's Not Watched

If `old/` were watched, every archive move would emit a `moved_to` event and create an infinite loop. `old/` must stay outside the watcher path.

## Message Template

The content matters. Keep the template minimal.

```markdown
---
from: {sender}              # front | back | pm | review
to: {recipient}             # matches the directory name
reply-to: {original message path}  # (optional) only for replies
re:                         # (optional) related issues / APIs / messages
  - https://github.com/.../issues/123
---

# {Title}

{Body — who, to whom, what, why. Only as much as needed.}
```

## Communication Flow Examples

- **PM creates a GitHub issue, then pings front**: `messages/front/2026-04-23-pm-quota-ui-issue123.md` (issue link + branch name)
- **PM pings back about the issue**: `messages/back/2026-04-23-pm-quota-api-issue123.md`
- **front asks back about an endpoint**: `messages/back/2026-04-23-front-quota-endpoint-question.md`
- **back answers**: `messages/front/2026-04-23-back-quota-endpoint-answer.md` (`reply-to`)
- **back finalizes the API spec**: `api-contracts/webui-api.md` (updated)
- **back requests review**: `messages/review/2026-04-23-back-quota-api-review-request.md`
- **reviewer feedback to back**: `messages/back/2026-04-23-review-quota-api-round1.md`
- **reviewer notifies PM of approval**: `messages/pm/2026-04-23-review-quota-api-approved.md`
- **PM creates the PR** (human merges) → archive related messages to `old/{recipient}/`
- **Merge-freeze announcement** (urgent broadcast): copy the same content into `messages/front/`, `messages/back/`, `messages/review/`
- **PM hands off deploy-branch rebase to back** (after dry-run conflict analysis): `messages/back/2026-04-28-pm-airgap-rebase-handoff.md` — issue link (`#93`), conflict-area summary (e.g. "PR #96 rename 흡수, conflict 집중: `cmd/server/main.go`, `internal/middleware/`, `internal/drive/store.go`"), explicit force-push permission, "frontend conflict 만나면 front 핑" 단서, 완료 시 `messages/pm/` 보고 요청.
