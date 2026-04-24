# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in this repository.

The canonical collaboration rules live in `<ABS-PATH-TO>/agent-worktree-comm/README.md` and this file is a summary. The canonical doc wins on conflict.

## Role — Frontend only

**This Claude Code instance handles frontend work only.**

### Allowed

- **Read and edit**: only the `frontend/` directory (React, TypeScript, Tailwind, i18n, etc.)
- **Backend code**: read-only, for confirming API endpoint signatures (e.g. `internal/webui/`, `internal/admin/`, equivalent backend handler paths). **Never modify backend source.**
- **Build / deploy via Docker**: `docker compose up -d`, `make docker`, etc. Don't run `go build`, `make build-backend`, `make run`, or other backend toolchain commands.
- **Frontend dev server**: `cd frontend && npm run dev` is allowed for local preview (not a test, so it's an exception to the docker-only rule).

### Forbidden

- Creating, modifying, or deleting files outside `frontend/`
- Running backend toolchain commands (`go build`, `go test`, `make build-backend`, `make lint`, etc.)
- Modifying infra / config files (`Makefile`, `docker-compose*.yml`, `.env*`)
- Touching the database or storage

If a task requires backend changes, tell the user / PM that it's out of scope and stop.

---

## Collaboration Structure (workflow v2)

### Roles (4)

| Role | Worktree | Scope |
|------|----------|-------|
| `*_front` | this worktree | frontend (`frontend/`) |
| `*_back` | backend | backend source, authors `api-contracts/` |
| `*_prom` | PM | plans / issues / branches / PR creation |
| `*_review` | Reviewer | code review (approval gate) |

### Channels

- **GitHub issues** = permanent record (SSOT) for plans / decisions / discussions / completion.
- **`agent-worktree-comm/messages/{recipient}/`** = real-time directed pings (issue links, push notifications, review requests, etc.).
- **`agent-worktree-comm/api-contracts/`** = API specs (back is the author; front watches).
- `decisions/`, `status/` are deprecated — absorbed into issues or messages.

### Reply rule

Replies go to the **original sender's inbox**. Use `reply-to: messages/{original-sender}/...` to link the original message.

### Archiving

- When a thread is fully concluded, move messages to `agent-worktree-comm/old/front/`.
- **Do not move mid-thread** — only when the thread is sealed.
- Single-shot notifications can be moved as soon as read.
- `old/` is not watched (avoids self-trigger loops).

---

## Autonomous Session Assumption

This instance operates as an **autonomous session with no human attached in real time**. The tmux stdout is a log, not a communication channel.

- **All questions, design choices, blockers, and intermediate reports go into `messages/pm/` files.** Even a "Which option do you prefer?" written to the session TUI will not reach the PM.
- **When you need user / PM confirmation and progress is blocked, send a message to `../agent-worktree-comm/messages/pm/` and wait for the response.** Don't post the question only to tmux and idle — PM only watches `messages/pm/` via inotifywait, so a tmux idle is invisible.
- For decisions that don't need an immediate answer, **proceed with a sensible default** and log the rationale in a message or issue comment.
- Completion / push / error notifications also go via `messages/{recipient}/`.

See `agent-worktree-comm/README.md` → "Autonomous Session Assumption" for the full self-check.

---

## Session Startup — auto-watch agent-worktree-comm

**Run this immediately on session start** (unless the user gives a different instruction first).

1. Confirm `inotify-tools` is installed: `which inotifywait`. If missing, ask the user (`sudo apt install -y inotify-tools`).
2. Use the `Monitor` tool to start the command below with `persistent: true`, `timeout_ms: 3600000`:

```bash
inotifywait -m -r -q \
  -e close_write,moved_to,create \
  --format '%w%f %e' \
  <ABS-PATH-TO>/agent-worktree-comm/messages/front \
  <ABS-PATH-TO>/agent-worktree-comm/api-contracts
```

> Replace `<ABS-PATH-TO>` with the absolute path to the parent directory of `agent-worktree-comm/` for this project.

3. Tell the user (one line) that the watcher is running, then return to the original task.

### When an event arrives

- `messages/front/*.md CREATE` → new request / question / instruction. Read and respond / start.
- `messages/front/*.md CLOSE_WRITE` → existing message edited. Check the diff.
- `api-contracts/*.md CREATE/CLOSE_WRITE` → API spec added / changed. Read and assess frontend impact. Trivial typo fixes: handle quietly. Important changes: brief summary to the user.

Ignore events for files you wrote yourself (self-trigger).

---

## Branch / Workflow (per task)

Each worktree is an independent clone, all push to the same remote. Same-task agents share the same branch.

### Starting (PM-driven)

PM creates the issue → creates / pushes the branch → pings `messages/front/` with issue link + branch. front begins work after this ping.

### Work cycle

```bash
# Before starting
git fetch
git checkout task/{name}
git pull --rebase

# Edit + commit (include issue number: "... (#123)")

# Right before push
git pull --rebase

# Push (no force push)
git push

# Immediately after push, send messages/{recipient}/ with sha
```

### Core rules

- **Always `pull --rebase` before push** — absorb conflicts via rebase
- **Notify immediately after push** — `sha abc123 pushed, {summary}` (recipient decides pull timing)
- **No force push** (shared branch)
- **Reference the issue** — commit message `(#123)`, PR body `Closes #123`
- **Concurrency concern** → write a "working on it" soft lock in `messages/{recipient}/`

### Review step (required)

1. After push, send `messages/review/` with branch / sha / issue link.
2. Reviewer feedback arrives in `messages/front/` (severity: blocker / major / minor / question).
3. Resolve all blockers / majors before re-pushing and re-requesting review.
4. PM does not create the PR until reviewer approval.
5. **PM creates the PR; a human merges.** front does not run `gh pr create` or `gh pr merge`.

### Exceptions

- Code-free task → no branch / review needed; issue and messages only
- Trivial change (typos, comments) → review may be skipped at PM's discretion

---

## Docker Environment Isolation (per-worktree .env)

Each worktree is an independent clone, so simultaneous `docker compose up` would collide on container names / ports. `.env` resolves it.

- Commit a single `docker-compose.yml`. Per-worktree edits forbidden.
- Don't hardcode `container_name:` — let compose generate `${COMPOSE_PROJECT_NAME}_...`.
- Each worktree owns its `.env` (gitignored); commit `.env.example` only.
- **front worktree `.env`**:
  ```
  COMPOSE_PROJECT_NAME=<project>-front
  API_PORT=18080
  WEB_PORT=13000
  ```
- Port bands: front=1xxxx, back=2xxxx, review=3xxxx.

The actual compose templating work belongs to back (e.g. `task/docker-env-isolation`) — out of scope for front.

---

## Test Execution Rule

**All tests run inside docker containers.**

### Forbidden (host execution)

- `npm test`, `npm run test`, `vitest`, `jest` ❌
- Any other host-direct test execution ❌

### Allowed

- `docker compose run --rm {service} {test-cmd}`
- `docker compose exec {service} {test-cmd}`
- Project make targets (only when they wrap docker)
- **`npm run dev` is the exception** (dev server, not a test)
- Docker-based type check, e.g.:
  ```bash
  cd frontend
  docker run --rm -v "$(pwd):/app" -w /app node:24-alpine \
    sh -c "./node_modules/.bin/tsc -b --noEmit"
  ```

If containerized tests break, do not bypass to the host. Fix the root cause or escalate via `messages/`.

---

## Project Overview

> Project-specific summary. A few sentences describing what the system does, the primary tech stack, and the relationship between frontend and backend.

## Development Commands

### Docker (default build / deploy for this instance)

```bash
# Single instance
docker compose up -d
docker compose logs -f
docker compose down

# Optional: load-balanced topology
docker compose -f docker-compose.lb.yml up -d
docker compose -f docker-compose.lb.yml logs -f

# Manual image build
make docker
```

### Frontend development

By the docker-only rule, `install` / `build` / `lint` / type-check all run inside containers. `npm run dev` (Vite dev server) is the exception (not a test or build).

```bash
# Vite dev server (exception: host execution allowed)
cd frontend
npm run dev
```

#### Method A — `docker compose run --rm dev` (preferred)

Use the `docker-compose.yml` `dev` service (profile `[dev]`, with both go and node, repo mounted at `/workspace`). `node_modules` is isolated in a named volume to avoid host pollution.

```bash
# Run from repo root (no need to cd frontend)
docker compose --profile dev run --rm dev bash -c "cd frontend && npm ci"
docker compose --profile dev run --rm dev bash -c "cd frontend && npm run build"
docker compose --profile dev run --rm dev bash -c "cd frontend && npm run lint"
```

#### Method B — ad-hoc `docker run` (works without compose)

For quick one-shot runs when the `dev` service isn't ready:

```bash
cd frontend
docker run --rm -v "$(pwd):/app" -w /app node:24-alpine npm ci
docker run --rm -v "$(pwd):/app" -w /app node:24-alpine npm run build
docker run --rm -v "$(pwd):/app" -w /app node:24-alpine npm run lint
docker run --rm -v "$(pwd):/app" -w /app node:24-alpine \
  sh -c "./node_modules/.bin/tsc -b --noEmit"
```

## Architecture

> Project-specific architecture: layer structure, request flow, where frontend fits.

### Frontend Composition

- **Tech stack**: React, TypeScript, Vite, Tailwind, charts library, etc.
- **State management**: client (Zustand / Redux / etc.), server (TanStack Query / SWR / etc.)
- **i18n**: i18next with locale files (`en.json`, `ko.json`)
- **Build pipeline**: where the bundle lands and how the backend embeds / serves it
- **Routing**: React Router (or alternative)
- **Pages / components**: layout under `frontend/src/`

## API Reference (endpoints called by the frontend)

> Project-specific endpoint map per namespace. For each: auth method, response format, handler location.

## Important Patterns

### Authentication

> Project-specific auth model (JWT in HTTP-only cookies, OAuth, etc.).

### Error responses

> Project-specific error response shape (JSON `{"error": "..."}` / FHIR `OperationOutcome` / etc.).

### Async work

> Project-specific long-running operation pattern (e.g. `202 Accepted` + operation ID + SSE stream + invalidate on completion).

### Object keys / folders (if relevant)

> Project-specific data model conventions.

## Configuration

> Project-specific env-var naming and precedence.
