# Worktree Commands: Branch-as-Default Redesign

Date: 2026-05-03

## Summary

Redesign worktree commands so that branch names are the default positional
argument, replacing the current mix of positional paths, search terms, and
`-B`/`--branch` flags. Path targeting moves to `-p/--path`, substring search
moves to `-s/--search`.

## Motivation

Worktrees are identified by branch in almost every user-facing scenario. The
current interface requires `-B` flags for branch targeting in some commands
(`wtdel`, `wtl`, `wtll`) while using paths or search terms as positionals.
Making branch the default reduces cognitive load and produces shorter, more
intuitive commands:

```
# Before                              # After
hug wtdel -B feature-auth             hug wtdel feature-auth
hug wtl -B feature-auth               hug wtl feature-auth
hug wtll -B feature-auth              hug wtll feature-auth
```

## Command Interface Changes

### Commands that change

| Command | Before | After |
|---------|--------|-------|
| `wtdel` | `wtdel [path...] [-B branch]` | `wtdel [branch...] [-p path]` |
| `wtl` | `wtl [SEARCH_TERM] [-B branch]` | `wtl [branch...] [-s search]` |
| `wtll` | `wtll [SEARCH_TERM] [-B branch]` | `wtll [branch...] [-s search]` |
| `wtsh` | `wtsh [SEARCH_TERM]` | `wtsh [branch...] [-s search]` |

### Commands that stay the same

| Command | Why |
|---------|-----|
| `wt` | Already branch-first in positional |
| `wtc` | Already takes branch as first positional |
| `wtwp` | Kept as convenience alias (now functionally identical to `wtl`) |
| `wtprune` | No branch/path targeting needed |

### New flags

| Flag | Scope | Meaning |
|------|-------|---------|
| `-s, --search TERM` | `wtl`, `wtll`, `wtsh` | Case-insensitive substring match on path or branch. Repeatable with OR logic. |
| `-p, --path PATH` | `wtdel` | Target worktree by filesystem path. Repeatable for batch deletion. |

### Positional argument semantics

- **Branch names**: exact match, case-sensitive. Multiple positional args use OR logic.
- **Branch + search combined**: AND logic between the two filter stages.
- **No args**: `wtl`/`wtll`/`wtsh` show all worktrees, `wtdel` shows interactive selection.

### Removed flags

- `-B, --branch` removed from `wtdel`, `wtl`, `wtll` (replaced by positional)

## Library Layer

No functional changes needed. The clean separation between CLI parsing and
library logic means this is purely a command-script-level change:

- `filter_worktrees()` — accepts branch filters and search terms as separate
  parameters already; commands just populate them differently.
- `branch_matches_any()` — exact match logic unchanged.
- `get_worktree_path_by_branch()` — branch-to-path resolution unchanged.
- Python modules (`worktree.py`, `worktree_select.py`) — CLI subcommand
  interfaces unchanged.
- `wtwp` — simplifies to transparent delegation to `wtl`.

## Testing

### Affected test files

| Test file | What changes |
|-----------|-------------|
| `test_worktree_list.bats` | Replace `-B` tests with positional branch tests, add `-s/--search` tests |
| `test_worktree_remove.bats` | Replace `-B` tests with positional branch tests, add `-p/--path` tests |
| `test_worktree_show.bats` | Change positional from search to branch, add `-s/--search` tests |
| `test_hug-git-worktree.bats` | No changes (library tests don't exercise CLI parsing) |

### New test cases

**`wtl` / `wtll`:**
- Positional branch: exact match
- Multiple positional branches: OR logic
- `-s` single and multiple: substring search, OR'd
- Branch + search combined: AND logic
- No args: show all

**`wtdel`:**
- Single branch positional
- Multiple branch positional: batch
- `-p` single and multiple: path-based deletion
- No args: interactive selection

**`wtsh`:**
- Positional branch: exact match
- `-s` substring search
- No args: interactive selection

## Implementation Strategy

Single big-bang commit: all 5 commands change at once. No users to migrate,
so a clean break maximizes elegance and maintainability.

## Task Breakdown

| Task ID | Subject |
|---------|---------|
| #7 | Update `git-wtdel`: positional branches, `-p/--path`, remove `-B` |
| #8 | Update `git-wtl`: positional branches, `-s/--search`, remove `-B` |
| #9 | Update `git-wtll`: positional branches, `-s/--search`, remove `-B` |
| #10 | Update `git-wtsh`: positional branches, `-s/--search` |
| #11 | Simplify `git-wtwp` to transparent `wtl` delegation |
| #12 | Update `test_worktree_remove.bats` |
| #13 | Update `test_worktree_list.bats` |
| #14 | Update `test_worktree_show.bats` |
| #15 | Run full test suite and verify |
