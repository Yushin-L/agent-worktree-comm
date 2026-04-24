# Agent Permissions

When operating Claude Code instances across multiple worktrees in autonomous mode, this document specifies which tools / commands each instance may auto-execute and which are blocked. The goal is to be **copy-and-modifiable as-is when introducing the same collaboration structure to a new repository**.

This doc does **not** cover the collaboration structure itself (role split, message channels, branch flow) — see `README.md` for that. Here we cover only **the rationale and concrete patterns for Claude Code's `permissions` settings**.

---

## 0. Design Philosophy

> **"Wide allow, narrow deny"** — block only the dangerous, leave the rest free.

The previous attempt (detailed allow-list) failed for these reasons:

- Compound shell forms (`for ... do`, `&&`, `|`, `cmd1; cmd2`, heredoc) often miss single-pattern matches → frequent prompts
- Each new command requires a settings update (operational overhead)
- Safe commands like `ls /abs/path` still prompted even with path scoping

In an autonomous session (a tmux background session with no human attached), a prompt is effectively **infinite wait** and stalls the workflow. So **deny-only-the-dangerous + free everywhere else** is practical.

In exchange, the deny list is designed **carefully** — one missing line could cause an incident.

---

## 1. Roles

| Role | Worktree suffix | Code permissions | GitHub permissions | Notes |
|------|-----------------|------------------|--------------------|-------|
| **PM** (Product Manager) | `*_prom` | No code edits / commits / merges | Can create / edit / comment on issues / PRs (no merge) | Owns plans, branch creation, PR creation |
| **Frontend** | `*_front` | Free in frontend code. Backend read-only | Issue / PR comments only | Commits / pushes only its own area |
| **Backend** | `*_back` | Free in server code / infra. Frontend read-only | Issue / PR comments only | Commits / pushes only its own area |
| **Reviewer** | `*_review` | fetch / diff / read only. **No edits / commits / pushes** | Issue / PR comments only | Approval gate before PR creation |

Each role's responsibilities are described in README.md's "Roles per Worktree" section.

---

## 2. Common settings.json Skeleton

Shared base across all four worktrees:

```json
{
  "defaultMode": "acceptEdits",
  "additionalDirectories": [
    "~/path/to/agent-worktree-comm"
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
      ...role-specific deny list...
    ]
  }
}
```

### Meaning of each key

- **`defaultMode: "acceptEdits"`** — file edits (`Edit`/`Write`/`NotebookEdit`) and routine filesystem commands (`mkdir`, `mv`, `cp`, ...) are **auto-approved**. Scope: the worktree cwd + `additionalDirectories`.
- **`additionalDirectories`** — directories outside cwd that should also receive the acceptEdits effect. Register the shared comm directory (`agent-worktree-comm/`) here, since it lives outside any single worktree.
- **`Bash(*)` allow** — initially allow all bash. Risk is caught by `deny`.
- **`Read`/`Grep`/`Glob` etc. allow** — file / search tools fully allowed.

### Pattern Syntax (Claude Code permissions)

| Pattern | Meaning |
|---------|---------|
| `Bash(cmd *)` | bash commands starting with `cmd` (any arguments) |
| `Bash(cmd arg *)` | starts with `cmd arg` |
| `Bash(*)` | all bash commands |
| `Edit(/abs/path/**)` | absolute path (single slash is **project-root-relative**) |
| `Edit(//abs/path/**)` | **filesystem absolute path** (double slash) |
| `Edit(~/path/**)` | home-directory-relative |
| `Edit(./path/**)` or `Edit(path/**)` | cwd-relative |
| `**` | recursive directory match |
| `*` | single path-segment match |

Compound shell (`A && B`, `A | B`, heredoc) is **decomposed and matched per part**. With `Bash(*)` open, decomposition is a non-issue.

**deny wins over allow** — `Bash(rm -rf *)` deny applies even with `Bash(*)` allow.

---

## 3. Common Deny List

Common deny applied to all four roles, organized by category with rationale.

### 3.1 Destructive git (history / remote damage)

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

Rationale: force-pushing a shared branch breaks other worktrees / CI. `reset --hard` / `clean -f` / `branch -D` lose uncommitted work. `filter-branch` rewrites history.

### 3.2 GitHub destructive actions

```
Bash(gh pr merge *)
Bash(gh pr close *)
Bash(gh repo delete *)
Bash(gh release delete *)
```

Rationale: merge / repo / release deletion is **human-only**. PR close also requires care.

### 3.3 System destruction

```
Bash(rm -rf *)
Bash(rm -fr *)
Bash(sudo *)
Bash(chmod *)
Bash(chown *)
```

Rationale: block `rm -rf` accidents and permission-change accidents. `sudo` is unsuitable for autonomous sessions.

### 3.4 Unauthorized package installation

```
Bash(npm install *)
Bash(npm i *)
Bash(go get *)
Bash(go install *)
Bash(pip install *)
```

Rationale: introducing dependencies needs a deliberate decision. Auto-install is a security / reproducibility risk.

### 3.5 Host test execution (docker-only principle)

```
Bash(go test *)
Bash(npm test *)
Bash(vitest *)
Bash(jest *)
Bash(pytest *)
Bash(python -m unittest *)
```

Rationale: host vs container environment differences cause **false comfort**. Tests run only in the same containers as CI / prod.

### 3.6 Docker destruction

```
Bash(docker system prune *)
Bash(docker volume rm *)
Bash(docker rmi *)
Bash(docker kill *)
```

Rationale: can affect other worktrees' / services' containers and volumes.

---

## 4. Per-Role Additional Deny

### 4.1 PM (`*_prom`)

PM **does not edit / commit / merge code**. But creating / editing GitHub issues and PRs is core PM work.

```
Bash(git commit *)
Bash(git add *)
Bash(git merge *)
Bash(git rebase *)
Bash(docker compose up *)
Bash(docker compose run *)
Bash(docker compose exec *)
```

| Blocked | Reason |
|---------|--------|
| `git commit/add/merge/rebase` | PM doesn't change code |
| `docker compose up/run/exec` | PM doesn't run containers |

`git push` is **allowed** for the **empty task-branch push** case (PM creates task branches and registers them on the remote).

### 4.2 Frontend (`*_front`), Backend (`*_back`)

GitHub issue / PR creation and editing is PM's domain.

```
Bash(gh pr create *)
Bash(gh pr edit *)
Bash(gh issue create *)
Bash(gh issue edit *)
Bash(gh issue close *)
```

`gh issue/pr view/list/comment/diff/checks` are allowed (for work-context lookups).

front-specific addition:

```
Bash(npm ci *)
Bash(npm uninstall *)
Bash(npm audit fix *)
Bash(pnpm install *)
Bash(yarn add *)
```

Rationale: block bypass paths for frontend package installation.

### 4.3 Reviewer (`*_review`)

Reviewer does **fetch / checkout / diff / read only**. Even if it edited code, the git deny list would prevent propagation (effectively harmless), but for workflow clarity, commit / push themselves are also denied.

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

| Blocked | Reason |
|---------|--------|
| All git mutations | Reviewer doesn't change / propagate code |
| `gh pr/issue` writes | Reviews go through messages; GitHub issues are PM's domain |
| `docker compose up` | Reviewer doesn't run persistent services. Tests use `docker compose run --rm` |

`docker compose run --rm`, `docker compose exec`, `docker run`, `docker exec` are allowed (for test execution).

---

## 5. Edit / Write Policy

The combination of `defaultMode: acceptEdits` + `additionalDirectories` lets **all four roles edit their own cwd + `agent-worktree-comm/` freely**. There is no separate path-scoped Edit/Write pattern.

### What if Reviewer edits code?

Code edits inside the Reviewer cwd are auto-approved, but **`git add/commit/push` are all denied**, so commits / propagation are impossible. Local edits have no effect. Therefore no risk.

For stricter isolation:

```json
"deny": [
  "Edit",
  "Write",
  "NotebookEdit",
  ...
]
"allow": [
  "Edit(~/path/to/agent-worktree-comm/**)",
  "Write(~/path/to/agent-worktree-comm/**)",
  ...
]
```

Downside: scoped allows don't match consistently across all path forms (relative / absolute / `~`), so prompts often appear. Not recommended.

---

## 6. Applying to a New Repository

### 6.1 Decide the worktree structure

To use the same 4-role pattern as-is:

```
<repo-shared-parent>/
├── agent-worktree-comm/             ← this directory (copy / re-init)
├── <project>_front/                 ← independent clone
├── <project>_back/                  ← independent clone
├── <project>_prom/                  ← independent clone (PM)
└── <project>_review/                ← independent clone
```

Other role compositions (e.g. add `_qa`, `_devops`) are also possible. When adding a new role:

1. Add the "common deny" + role-appropriate denies
2. Create the `messages/{new-role}/` directory
3. Add a "Per-Role Additional Deny" section to this doc

### 6.2 Copy / substitute settings.json

In each worktree's `.claude/settings.json`, apply the skeleton from this doc + the role's deny. Substitute:

- `additionalDirectories`'s `~/path/to/agent-worktree-comm` → real path
- Domain-specific package-manager denies (e.g. for a Rust backend add `Bash(cargo install *)`)
- Domain-specific test-runner denies (e.g. for Rust add `Bash(cargo test *)`; for Java add `Bash(mvn test *)`, `Bash(gradle test *)`)

### 6.3 Verification Procedure

1. Start with a single role (e.g. review) — single session
2. Run a light task as a trial
3. If a pattern prompts frequently, check for missing deny or replace with a narrower deny
4. Audit afterwards whether unintended commands were possible

### 6.4 Incident Response

If an autonomous session does something unintended:

```bash
tmux send-keys -t {session} Escape    # interrupt current work
tmux kill-session -t {session}        # kill the session
```

After recovery, reinforce the deny patterns → restart.

---

## 7. Operational Pitfalls

### 7.1 Compound shell commands

A non-issue with `Bash(*)` allow. With an allowlist approach, `cmd1 | cmd2` and `cmd1 && cmd2` often miss single-pattern matches. That's why this doc recommends `Bash(*)`.

### 7.2 Over-broad deny blocking legitimate work

If the deny list is too broad, normal work is blocked. Example: with `Bash(chmod *)` denied, granting execute permission on a build artifact won't work. When actually blocked, re-evaluate "is this deny really necessary?".

### 7.3 Reviewer's acceptEdits

It may seem counterintuitive that Reviewer can edit code, but **the git-push deny prevents propagation, making it effectively harmless**. For stricter isolation, consider the path-scoped approach in §5 (with the downsides).

### 7.4 Autonomous vs interactive sessions

All policies in this doc assume **autonomous sessions with no human attached in real time**. For interactive use, more conservative allowlists are also valid.

---

## 8. Change Management

This doc + settings.json are part of **workflow v2**. On change:

- Update this doc
- Simultaneously update affected files among the 4 settings.json
- Notify all agents via the `messages/` channel → each restarts their session (settings load at session start)

---

## 9. References

- Claude Code official docs: https://code.claude.com/docs/en/permissions.md
- This project's collaboration structure: `README.md`
- Autonomous session assumption: `README.md` → "Autonomous Session Assumption"
