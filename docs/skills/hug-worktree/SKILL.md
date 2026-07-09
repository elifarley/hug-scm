---
name: hug-worktree
description: Use whenever starting branch-worthy work (features, bugfixes, refactors, spec/plan documents, multi-step tasks) — the worktree-first ritual.
argument-hint: "[new-branch-name or task description]"
allowed-tools: Bash
---

# Worktree-first workflow (hug)

Branch-worthy work always starts in a fresh worktree, never a bare branch in the main
checkout — and the worktree is created FIRST, before any other action on the task.

**Run `hug help :worktree` and follow that ritual.** It is the single source of truth
for the full sequence: when to skip, base-branch selection, provisioning, working
inside the worktree, sanitize-before-finish, cleanup, and subagent rules. This skill is
a thin pointer so the ritual can never drift from the article.

Authoritative command syntax lives in `hug help :worktree` and each command's own `-h`
(`hug wtc -h`, `hug wtl -h`, `hug wtdel -h`) — check there if a flag looks off.

## The safety floor (if you do nothing else)

- Create + enter: `hug -C <repo> wtc <branch> --base origin/main -y`, then `cd` into the
  sibling `<repo>.WT.<branch>` and do ALL work there.
- Never use `git worktree` (hard-blocked); never pass an explicit path or `.worktrees/`.
- After merge: `hug -C <repo> wtdel <branch> --force` (append `--with-branch` to drop the branch).
