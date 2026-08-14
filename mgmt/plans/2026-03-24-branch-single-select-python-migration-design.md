# Branch Single-Select Python Migration — Design

**Date:** 2026-03-24
**Status:** Draft
**Builds on:** branch_select.py (multi-select), branch_filter.py, hug_git_branch.py
**Precedent:** `git-config/lib/python/git/tag_select.py`, `git-config/lib/python/git/worktree_select.py`

---

## Problem

`print_interactive_branch_menu()` in `hug-git-branch` is the core single-branch
selection function used by `git-b` (the most-used branch command), `git-wtc`, and
`git-brestore`. It still:

- Builds `formatted_options[]` inline via a parallel-array loop (lines 217–245)
- Duplicates formatting logic already present in `branch_select.py`'s
  `format_multi_select_options()`
- Uses `get_gum_selection_index` and `get_numbered_selection_index` — pure Bash
  helpers that duplicate what `tag_select.py` and `worktree_select.py` already do
  in Python

Additionally:
- `select_wip_branch()` (line 444) has no gum-unavailable fallback — it errors
  if gum isn't installed, unlike every other selection function
- `git-brestore` calls `get_gum_selection_index` with 4 args (function takes 2) —
  a latent bug where extra args are silently ignored

## Decision

Extend `branch_select.py` with `prepare` and `single-select` CLI commands,
following the two-mode pattern established by `tag_select.py` and `worktree_select.py`.
Python owns formatting, filtering, and numbered-list interaction. Bash keeps gum
invocation and caller contracts.

**Why extend branch_select.py (not create a new module):**
- Branch data fetching already flows through `hug_git_branch.py` → eval → Bash arrays
- `branch_filter.py` already receives data from Bash via CLI args
- `branch_select.py` already has `format_multi_select_options()` — adding single-select
  formatting is a natural extension, not a new module
- Avoids creating a 4th branch-related Python module

**Why NOT have Python call git directly (unlike tag/worktree pattern):**
- `hug_git_branch.py` already handles all git calls for branch data with sophisticated
  context-aware sorting (gum-single, gum-multi, static)
- Duplicating that logic in branch_select.py would create a DRY violation
- The data already arrives in Python-safe form via eval'd declare statements
- The serialisation boundary works fine here — it's already tested and battle-hardened

## Data Model Changes

No new dataclasses needed. `branch_select.py` already has `SelectOptions` and
`SelectedBranches`. Add a single-select result:

```python
@dataclass
class SingleSelectResult:
    """Result of single-branch selection.

    Attributes:
        status: "selected" | "cancelled" | "no_branches"
        branch: Selected branch name (empty unless status == "selected")
        index: 0-based index into the input list (-1 if not selected)
    """
    status: str
    branch: str
    index: int
```

## New CLI Commands

```
# Prepare mode (gum path) — outputs formatted_options for gum_filter_by_index
python3 branch_select.py prepare \
    --branches "..." --hashes "..." --dates "..." --subjects "..." --tracks "..." \
    --current-branch "main" [--placeholder TEXT]

# Single-select mode (numbered-list path) — full interactive selection
python3 branch_select.py single-select \
    --branches "..." --hashes "..." --dates "..." --subjects "..." --tracks "..." \
    --current-branch "main" [--placeholder TEXT]
```

**prepare** outputs bash declare statements:
```bash
declare -a formatted_options=('main abc1234 ...' 'feature def5678 ...')
declare selection_status="ready"
declare -i branch_count=5
```

**single-select** outputs:
```bash
declare selected_branch='feature'
declare selection_status="selected"
declare -i selected_index=2
```

## Bash Adapter

`print_interactive_branch_menu()` shrinks from ~60 lines to ~25 lines:

1. Build python_args from function parameters
2. If gum available + branches >= MIN_ITEMS_FOR_GUM:
   - Call `prepare`, eval output → `formatted_options[]`
   - Feed to `gum_filter_by_index`, get index
   - Look up branch by index
3. Else:
   - Call `single-select`, eval output → `selected_branch`, `selection_status`
   - Return based on status

Callers (`git-b`, `git-wtc`, `select_branches`) are unchanged.

## What Changes

| Component | Before | After |
|-----------|--------|-------|
| Single-select formatting | Inline Bash loop in `print_interactive_branch_menu` | `format_single_select_options()` in Python |
| Numbered-list interaction (single) | `get_numbered_selection_index()` in Bash | `single-select` CLI command in Python |
| `get_gum_selection_index` | Called from Bash | Still called from Bash (thin wrapper around `gum_filter_by_index`) |
| `get_numbered_selection_index` | Called from Bash for single-select | No longer called for branches (Python handles it) |

## What Stays in Bash

- `compute_local_branch_details()` — already uses `hug_git_branch.py`
- `get_gum_selection_index()` — gum invocation stays in Bash
- `gum_filter_by_index()` — infrastructure, not a migration target
- `select_branches()` — orchestrator, adapts to new Python commands
- `filter_branches()` — Bash fallback for custom filter functions
- `compute_wip_branch_details()` — simple git for-each-ref wrapper
- `print_branch_line()` — used by static list display, not selection
- Caller scripts (`git-b`, `git-wtc`, `git-bdel`, etc.) — unchanged

## What Gets Removed from Bash

- Inline `formatted_options[]` loop in `print_interactive_branch_menu` (lines 217–245)
- Inline `printf` numbered-list display in `print_interactive_branch_menu` (lines 257–268)
- `get_numbered_selection_index()` call from `print_interactive_branch_menu`

## Testing Strategy

### pytest (extend existing test_branch_select.py)

New test cases for:
- `SingleSelectResult` dataclass construction and `to_bash_declare()`
- `format_single_select_options()` — current branch marker, alignment, color codes
- `single_select_branches()` — numbered-list interaction with test input
- CLI `prepare` command — valid bash declares, correct formatted_options
- CLI `single-select` command — selection, cancellation, no-branches states

### BATS (existing, unchanged)

- `tests/lib/test_hug-git-branch.bats` — exercises `print_interactive_branch_menu`
  through callers; same behavior, different engine
- `tests/unit/test_branch.bats` — `git-b` black-box tests unchanged

## Out of Scope

- Migrating `select_wip_branch()` — separate, smaller task
- Migrating gum path of `multi_select_branches()` — separate task
- Unifying `branch_select.py` + `branch_filter.py` into one module — premature
- Having Python call git directly for branches — existing flow works
- `git-brestore` 4-arg bug fix — separate commit, not part of this migration

## Future Work (not this task)

1. `select_wip_branch()` → Python (simple, self-contained)
2. Gum path of `multi_select_branches()` → Python `prepare` command
3. Inline selections in `git-us`, `git-untrack`, `git-bdel-backup` → library functions
4. `git-brestore` bug fix (extra args to `get_gum_selection_index`)
