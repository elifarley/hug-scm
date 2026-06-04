# Stdout/Stderr Discipline — Full Compliance Fix

**Date:** 2026-05-04
**Status:** Approved

## Context

A gap analysis identified 21 commands and 5 libraries that violate the stdout/stderr discipline principles documented in CLAUDE.md (section "Stdout/Stderr Discipline"). The principle is: **stdout = data, stderr = chatter.** `git-wtl` was already fixed as the reference implementation. This design covers fixing the remaining violations.

## Approach: Library-first cascade

Fix shared libraries first (cascading benefits to callers), then fix commands in grouped commits by category. Regression testing only (run `make test` after each commit). 13 commits total.

## Phase 1: Library Fixes (5 commits)

### Commit 1: `hug-arrays` — `print_list()` → stderr

**File:** `git-config/lib/hug-arrays:46-54`

**Why first:** Highest leverage. `print_list` is called from `hug-output` (2 functions), `hug-git-discard` (8+ call sites), and `git-w-purge` (3 call sites). Fixing it here fixes all callers automatically.

**Change:** Add `>&2` to both `printf` calls (lines 49, 52).

### Commit 2: `hug-output` — section headers → stderr

**File:** `git-config/lib/hug-output:120-158`

**Change:** Add `>&2` to the 4 `printf` statements in `print_staged_unstaged_paths` (lines 121, 124, 127, 130). `print_list` calls in `print_untracked_ignored_paths` already fixed by commit 1.

### Commit 3: `hug-git-discard` — all status messages → stderr

**File:** `git-config/lib/hug-git-discard`

**Change:** Add `>&2` to ~20 standalone `printf` statements outputting success messages, dry-run previews, and "no changes" notices (lines 44, 49, 59, 88, 124, 130, 131, 140, 167, 173, 174, 186, 216, 304, 370, 376, 379, 424, 440, 460). `print_list` calls already fixed by commit 1.

### Commit 4: `hug-git-worktree` — summary/prune → stderr

**File:** `git-config/lib/hug-git-worktree`

**Change:** Add `>&2` to headers and status messages in `show_worktree_summary` (lines 879-881, 902) and `prune_worktrees` (lines 828, 832, 838, 846). Data lines (worktree listings) stay on stdout.

### Commit 5: `hug-git-show` — section headers → stderr

**File:** `git-config/lib/hug-git-show`

**Change:** Add `>&2` to section headers in `_show_commit_standard` (lines 220, 229, 239).

## Phase 2: Command Fixes (8 commits)

### Commit 6: Worktree display (wtsh, wtll, wt)

| Command | File | Lines | What |
|---------|------|-------|------|
| `git-wtsh` | `git-config/bin/git-wtsh` | 181-183, 186, 206-207 | Headers, separators, "No worktrees" |
| `git-wtll` | `git-config/bin/git-wtll` | 115 | "Worktrees (long format):" |
| `git-wt` | `git-config/bin/git-wt` | 111 | "Worktrees (N)" |

### Commit 7: Worktree create/delete (wtc, wtdel)

| Command | File | Lines | What |
|---------|------|-------|------|
| `git-wtc` | `git-config/bin/git-wtc` | 209, 251-259, 265-273, 324 | Preview + summary blocks |
| `git-wtdel` | `git-config/bin/git-wtdel` | 246-251, 266-275, 285-294, 338, 348-354 | All summary blocks. Line 74 (path data) stays on stdout |

### Commit 8: Status/snapshot (sx, shc)

| Command | File | Lines | What |
|---------|------|-------|------|
| `git-sx` | `git-config/bin/git-sx` | 96, 148, 152, 163, 168, 172-173 | Section labels, "clean" msg, header, tip |
| `git-shc` | `git-config/bin/git-shc` | 112, 120 | "Changed files:" headers |

### Commit 9: HEAD operations (h-steps, h-files)

| Command | File | Lines | What |
|---------|------|-------|------|
| `git-h-steps` | `git-config/bin/git-h-steps` | 114, 117 | "steps back from HEAD" prose |
| `git-h-files` | `git-config/bin/git-h-files` | 170-175, 183 | Patch labels + blank lines |

### Commit 10: Tag operations (t, tc, tdel)

| Command | File | Lines | What |
|---------|------|-------|------|
| `git-t` | `git-config/bin/git-t` | 152, 155-162, 269-273, 298-308 | Tag labels + prompts |
| `git-tc` | `git-config/bin/git-tc` | 171-173, 341, 349, 357, 394-402, 416 | UI + summary |
| `git-tdel` | `git-config/bin/git-tdel` | 152-172, 239-268, 296, 330-337 | Display + summary |

### Commit 11: Working directory (w-discard, w-purge, w-purge-all, w-unwip)

| Command | File | Lines | What |
|---------|------|-------|------|
| `git-w-discard` | `git-config/bin/git-w-discard` | 199, 206 | Bare blank lines |
| `git-w-purge` | `git-config/bin/git-w-purge` | 170, 189 | Blank lines (print_list already fixed) |
| `git-w-purge-all` | `git-config/bin/git-w-purge-all` | 98, 104 | `\n` prefix |
| `git-w-unwip` | `git-config/bin/git-w-unwip` | 170, 176 | Branch deletion messages |

### Commit 12: Commit/staging (ccp, aa)

| Command | File | Lines | What |
|---------|------|-------|------|
| `git-ccp` | `git-config/bin/git-ccp` | 117, 137, 152 | Progress messages |
| `git-aa` | `git-config/bin/git-aa` | 42, 43 | Error message |

### Commit 13: Stats + reverse violation (stats-author, stats-branch, log-outgoing)

| Command | File | Lines | What |
|---------|------|-------|------|
| `git-stats-author` | `git-config/bin/git-stats-author` | 199-204 | awk "Code changes:" → `>&2` |
| `git-stats-branch` | `git-config/bin/git-stats-branch` | 353-360 | awk "Code:" → `>&2` |
| `git-log-outgoing` | `git-config/bin/git-log-outgoing` | 98, 104, 107 | **Remove** `>&2` (data wrongly on stderr) |

## Verification

After each commit: `make test` (regression only — 2457 tests: 1674 BATS + 783 Python).

After all commits: manual e2e spot-check of key commands (`hug sx`, `hug wtsh`, `hug shc HEAD`) to confirm chatter is on stderr and data is on stdout.

## Already Compliant (no changes needed)

`git-fblame`, `git-fb`, `git-fcon`, `git-fa`, `git-fborn`, `git-h`, `git-h-back`, `git-h-undo`, `git-h-squash`, `git-h-rewind`, `git-h-rollback`, `git-c`, `git-ca`, `git-caa`, `git-cm`, `git-cma`, `git-cmv`, `git-bc`, `git-bdel`, `git-bll`, `git-tll`, `git-rb`, `git-rbc-*`, `git-mff`, `git-s`, `git-ll`, `git-llu`, `git-llf`, `git-llfp`, `git-llfs`, `git-lc`, `git-lf`, `git-wtl`, `git-us`, `git-w-get`, `git-w-wipe`, `git-w-zap`, `git-sh`, `git-shp`, `git-stats-file`
