# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Role — Backend only

**This Claude Code instance handles backend work only.**

Worktree strategy: a single git repository is split into multiple worktrees, each with an independent Claude Code instance. Frontend work belongs to a separate worktree (`<project>_front`).

### Allowed

- **Read and edit**: backend source (the language's primary directories — e.g. `internal/`, `cmd/`, `src/`, `backend/`), config files (`Makefile`, `docker-compose*.yml`, `.env*`, `config.yaml`), tests, infra files.
- **Read `frontend/`**: for confirming API call signatures, etc. — read-only.
- **Build / test always via Docker**: `make docker`, `docker compose build`, `docker compose run --rm ...`. **Never invoke the host language toolchain directly** (`go build`, `go test`, `npm run build`, `python -m ...`, `pytest`, `make build`, `make test`, `make lint`).

### Forbidden

- Modifying / deleting / creating anything in `frontend/` (front worktree owns it)
- Editing other worktrees (`<project>_front` etc.) directly
- Reading or syncing other worktrees' `CLAUDE.md` (each worktree manages its own; gitignored)

### Work Types

1. Receive an API spec request from frontend → implement on the backend.
2. Develop / refactor internal logic (services, storage, auth, middleware, workers, etc.).
3. Infra / config / migration changes.

---

## Communication Hard Rule — every outbound utterance is a file

Any text addressed to another agent (PM / front / review) or to the user **must be a file at `<ABS-PATH-TO>/agent-worktree-comm/messages/{recipient}/{date}-{sender}-{topic}.md`**. tmux / console output is not communication — other agents' inotifywait only watches message files, so a question, report, or request printed to the console will never reach them.

**"ping" = message file creation.** It is shorthand, nothing more. Wherever this doc says "ping the recipient," create a message file at that spot.

### Decision tree — when you want to ask another agent something

1. **Blocking (you cannot proceed without an answer)** → write the message file in `messages/pm/` (or the relevant recipient inbox) and wait.
2. **Pre-authorized (you can proceed without an answer)** → just proceed, then report the result via message. "Let me double-check first" written to the console and idling is neither (1) nor (2) — it is the **worst option**.
3. **Decision is not blocking but the rationale is non-obvious** → proceed with a sensible default, log the rationale in a message or issue comment.

If you catch yourself writing "PM please confirm" or "which one should I pick?" to the console, **stop immediately and move that text into a message file**.

---

## Autonomous Session Assumption

This instance operates as an **autonomous session with no human attached in real time**. The tmux stdout is a log, not a communication channel.

- **All questions, design choices, blockers, and intermediate reports go into `messages/pm/` files.** A "Which option do you prefer?" written to the session TUI will not reach the PM.
- For decisions that don't need an immediate answer, **proceed with a sensible default** and log the rationale in a message or issue comment. Waiting on choices stalls the pipeline.
- Completion / push / error notifications also go via `messages/{recipient}/`.
- **When you need user / PM confirmation and progress is blocked, send a message to `../agent-worktree-comm/messages/pm/` and wait for the response.** Don't post the question only to tmux and idle — PM only watches `messages/pm/` via inotifywait, so a tmux-only question gets delayed by the cron polling interval at best.

See `agent-worktree-comm/README.md` → "Autonomous Session Assumption" for the full self-check.

### Cross-Worktree Communication (workflow v2)

The four collaboration roles: `*_front`, `*_back`, `*_prom` (PM), `*_review` (Reviewer).

**Channels:**

- **GitHub issues** = permanent record (SSOT) for plans / decisions / discussions / completion. Long specs in the body, design rationale in comments.
- **`agent-worktree-comm/messages/{recipient}/`** = real-time directed pings (issue link relay, push sha notifications, review requests / feedback, etc.).
- **`agent-worktree-comm/api-contracts/`** = API specs. **back is the author** (front is the consumer). back doesn't watch its own writes.
- `decisions/`, `status/` are **deprecated** — absorbed into GitHub issues or messages.

**Message frontmatter:**

```markdown
---
from: back
to: pm                # front | back | pm | review
reply-to: messages/back/2026-04-23-pm-foo.md  # optional, for replies
re:
  - https://github.com/{owner}/{repo}/issues/123
---

# Title

Body.
```

Replies go to the **original sender's inbox** (with `reply-to` linking the original).

### Branch / Workflow (per-task branches)

> **One task = one issue = one branch = one PR.** Backend and frontend stack commits onto the same branch and ship in a single PR that PM creates. Do not ask "should we make two PRs?" — same branch means one PR, automatically. Splitting requires the task to have been scoped as two issues with two branches from the start; you cannot split mid-stream. See `<ABS-PATH-TO>/agent-worktree-comm/README.md` "Canonical Task Flow" for the end-to-end sequence.

1. New task → **PM creates the GitHub issue first**, then creates / pushes the branch (`task/{name}`) → pings `messages/back/` with issue link + branch name.
2. back work cycle:
   ```bash
   git fetch && git checkout task/{name} && git pull --rebase
   # edit + commit (include the issue number in the message: "... (#123)")
   git pull --rebase   # always before push
   git push            # no force push (shared branch)
   ```
3. Immediately after push, send `messages/{recipient}/` with `sha abc123 pushed, {summary}`.
4. Review request: `messages/review/` with branch / sha / issue link.
5. Reviewer feedback arrives in `messages/back/` (severity: `blocker` / `major` / `minor` / `question`). Resolve all blockers / majors before re-pushing and re-requesting review.
6. PM does not create the PR until reviewer approval. The actual merge is the human's job.

### Message Archiving

- When a thread is fully concluded, move messages to `agent-worktree-comm/old/back/`.
- **Do not move mid-thread** (preserves `reply-to` link stability). Single-shot notifications can be moved as soon as read.
- `old/` is not watched (avoids move-event loops).

### Local Docker Environment Isolation

- Commit a single `docker-compose.yml`. Don't hardcode `container_name:`; use env templates for ports (`"${API_PORT:-8080}:8080"`).
- back worktree `.env`: `COMPOSE_PROJECT_NAME=<project>-back`, port band **2xxxx** (e.g. `API_PORT=28080`, `WEB_PORT=23000`).
- `.env` and `docker-compose.override.yml` are gitignored. Commit `.env.example` only.
- **back owns the compose-templating work** — related hardcoding cleanups are back's responsibility.

The canonical operational rules live in `<ABS-PATH-TO>/agent-worktree-comm/README.md`.

---

## Session Startup — auto-watch own inbox

**Run this immediately on session start** (unless the user gives a different instruction first).

1. Confirm `inotify-tools` is installed: `which inotifywait`. If missing, ask the user (`sudo apt install -y inotify-tools`).
2. Use the `Monitor` tool to start the command below with `persistent: true`, `timeout_ms: 3600000`:

```bash
inotifywait -m -q \
  -e close_write,moved_to,create \
  --format '%w%f %e' \
  <ABS-PATH-TO>/agent-worktree-comm/messages/back
```

> Replace `<ABS-PATH-TO>` with the absolute path to the parent directory of `agent-worktree-comm/` for this project.

3. Tell the user (one line) that the watcher is running, then return to the original task.

**Watch only `messages/back/`.** `api-contracts/` is back-authored (no need to watch your own writes); `old/` must not be watched (move events would loop).

### When an event arrives

1. `Read` the file immediately.
2. Check `from:` and `re:` (related issue).
3. Triage:
   - PM task / issue ping → set priority, plan, report back
   - front API question → reply in `messages/front/` (with `reply-to`)
   - Reviewer feedback → triage by severity, address blockers / majors first
   - Urgent global broadcast (merge freeze, etc.) → immediately summarize for the user
4. Trivial fixes / pure information: handle quietly.

After every push, leave a `messages/{recipient}/` notification with the sha.

---

## Project Overview

> Project-specific summary goes here. A few sentences describing what the system does, the primary tech stack, and how the binary / service is shaped (single binary, microservices, etc.).

## Development Commands

**All builds / tests / lint run inside docker.** Do not call host toolchains directly. Make targets should wrap `docker compose run --rm dev ...` (the Dockerfile's `dev` stage) so they can be invoked normally.

### One-time setup

```bash
cp .env.example .env                      # per-worktree — adjust COMPOSE_PROJECT_NAME, port band
docker network create <shared-network>    # if the compose uses an external network
make dev-build                            # build the dev image once (downstream targets reuse it)
```

### Build / test / lint (all docker)

> Project-specific commands go here. The pattern is: thin Make targets that delegate to `docker compose run --rm dev ...`. Examples:

```bash
make build              # production image
make build-backend      # backend binary inside dev container
make test               # tests inside dev container
make lint               # linter inside dev container
make dev-shell          # interactive shell in dev container (ad-hoc commands)
```

### Docker Compose (start services)

```bash
docker compose up -d
docker compose logs -f
docker compose down

# Optional alternative profiles
docker compose -f docker-compose.lb.yml up -d
docker compose -f docker-compose.airgap.yml up -d
```

### Forbidden (host execution — same rule as the role section above)

Don't run language-native build / test commands on the host (`go test`, `go build`, `npm test`, `npm run build`, `pytest`, `python -m ...`). When the container test breaks, fix the dev image / volume / network root cause; do not fall back to host execution.

## Architecture

> Project-specific architecture goes here. A useful template:

```
Client Layer (...)
    ↓
HTTP Router (...)
    ↓
Middleware Layer (Auth, CORS, Audit, Rate Limit, ...)
    ↓
Handler Layer
    ├── ...
    ↓
Service Layer (...)
    ↓
Data Layer
    ├── MetadataStore (...)
    └── ObjectStore (...)
```

### Key Components

- Brief one-line description of each major package / module.

### Frontend (read-only reference)

- Tech stack, state management, i18n, build pipeline (so back can verify API call signatures without modifying frontend code).

## Configuration

> Project-specific config conventions: env-var naming, precedence (env > YAML > defaults), location of `.env.example`, secret handling.

## Important Patterns

> Project-specific patterns: error handling shape, middleware order, DB access conventions, auth model (S3 SigV4 / JWT / OAuth / etc.), domain-specific behaviors.

## Testing

### Unit tests (docker only)

```bash
make test
docker compose --profile dev run --rm -T dev <test-runner> <package> -v
```

Don't run native test commands on the host. If the container is broken, fix the image / volume / network — don't bypass.

### Integration tests

> Project-specific integration test layout (location, runner, prerequisites).

## API Routes

> Project-specific route map: namespaces, auth method per namespace, response format (JSON / XML / etc.), handler locations.

## Important Files

> Project-specific entry points and reference files.

## Notes

> Project-specific gotchas: data-format quirks, performance caveats, deployment specifics.
