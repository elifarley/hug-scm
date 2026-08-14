+++
title   = "Worktrees: the branch-worthy-work ritual"
summary = "Always start branch-worthy work in a fresh worktree — the ritual."
order   = 30
+++

Branch-worthy work — a spec, a plan, a feature, a bugfix, a refactor, any multi-step
change — ALWAYS starts in a fresh worktree, never a bare branch in the main checkout.
Creating the worktree is the FIRST step, before any other action on the task (before
reproducing a bug, before writing a failing test).

WHY: an isolated worktree keeps the main checkout clean and usable, lets independent
tasks run in parallel, and stops a half-finished change from polluting the working
tree — which matters most when an autonomous agent is making the edits.

## Skip a new worktree ONLY when

- You are ALREADY inside a worktree dedicated to this task (never nest worktrees).
- The task is a trivial in-place edit on the already-correct branch.
- You are only inspecting, read-only.

When in doubt, create the worktree.

## The ritual

1. **Create the branch and its worktree in one step**, based off an UP-TO-DATE
   integration branch (usually `origin/main` — confirm per repo; some use
   `origin/develop` or `master`), NOT a stale local HEAD:

       hug -C <repo> wtc <new-branch> --base origin/main -y

   For an existing branch: `hug -C <repo> wtc <existing-branch> -y`. Hug chooses the
   canonical worktree path (a sibling `<repo>.WT.<branch>`); never pass an explicit
   path or a `.worktrees/` directory.

2. **Enter the worktree and do all work there.** `cd` INTO it (find it with
   `hug -C <repo> wtl <branch>`) so `make`, tests, and relative paths target the
   worktree, not the main checkout. Keep passing `hug -C <worktree>` for clarity.

3. **Provision the environment** when the project ships a Makefile target for it —
   e.g. a `dev-env-init` target (creates the baseline env) and/or a `deps-sync` target
   (installs from the lockfile). Run whichever exist, `dev-env-init` before `deps-sync`;
   both are idempotent and safe to run.

## Work INSIDE the worktree

Creating a worktree and then editing the original checkout — or running `make`/tests
with the CWD still at the main repo — is the #1 mistake. After you `cd` in, the
worktree is your working tree for the entire task.

## Before finishing

An automated harness may run the project's `sanitize`/verify target on finish against
the session's ORIGINAL directory, not a worktree created mid-session — so run the
project's sanitize/verify yourself, inside the worktree, before you wrap up.

## After merge — clean up

    hug -C <repo> wtdel <branch> --force      # append --with-branch to drop the branch too

List worktrees any time with `hug -C <repo> wtl [branch]`.

## Hard rules

- NEVER use `git worktree` (or any raw git worktree command) — it is hard-blocked.
  Always use `hug wtc` / `hug wtl` / `hug wtdel`.
- NEVER pass an explicit path or a `.worktrees/` directory — hug owns the canonical
  `<repo>.WT.<branch>` path.
- If you need a worktree operation not covered here, say what you need (and which raw
  git command would do it) and stop — do not run a raw git command.

## Subagents

A dispatched agent inherits the worktree: if your CWD is a `*.WT.*` directory, just
work there — every edit and every `hug -C <worktree-path>` stays in that worktree,
never the sibling repo root. Don't create worktrees as a subagent unless the
orchestrator delegated it.
