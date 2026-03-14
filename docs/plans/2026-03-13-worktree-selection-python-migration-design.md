# Worktree Selection Python Migration — Design

## Problem

Three command scripts (`git-wt`, `git-wtdel`, `git-wtsh`) duplicate identical
menu-building and gum-selection logic for worktree interactive selection. Each
independently builds `menu_items[]` + `worktree_selection_paths[]` from five
parallel arrays, formats the same status indicators, and invokes raw
`gum filter` with fragile string matching to recover the selected index.

This is the same structural problem the tag selection migration solved: the
data model already lives in Python (`worktree.py`'s `WorktreeInfo`), but
formatting and selection remain tangled in Bash with triplicated code.

Additionally:
- All three bypass `gum_filter_by_index`, the project's index-based gum API
- `git-wtsh` has zero non-gum fallback (hard error if gum is absent)

## Goal

Consolidate worktree selection into a single Python module that imports from
`worktree.py`, so the three Bash scripts become thin adapters calling one
shared `select_worktree()` function.

## Architecture

**Approach A: Two-mode CLI with worktree.py import** (chosen over self-contained
or extend-worktree.py alternatives).

`worktree_select.py` imports `WorktreeInfo` and `parse_worktree_list` from
`worktree.py`. This is the first cross-module import in `git/` — justified
because the data model is identical (copying it would be the anti-DRY move
we're eliminating).

## Data Model

```python
from git.worktree import WorktreeInfo, parse_worktree_list

@dataclass
class WorktreeFilterOptions:
    include_main: bool = True       # git-wtsh needs main; git-wt/git-wtdel don't
    exclude_current: bool = False   # git-wtdel excludes the worktree you're in

@dataclass
class WorktreeSelectionResult:
    status: str    # "selected" | "cancelled" | "no_worktrees" | "error"
    path: str      # selected worktree path (empty if not selected)
```

No multi-select — all three commands select a single worktree.

## Python Module Structure

**File:** `git-config/lib/python/git/worktree_select.py`

### Pure functions (no side effects)

- `filter_worktrees(worktrees, options, current_path)` — applies include/exclude
  filters, returns filtered `list[WorktreeInfo]`
- `format_display_rows(worktrees, current_path)` — builds display strings with
  status indicators (`[CURRENT]`, `[DIRTY]`, `[LOCKED]`), branch, commit, path.
  One function replacing three copies.
- `_bash_escape(s)` — single-quote wrapping (same pattern as tag_select.py)

### Bash output functions

- `worktrees_to_bash_declare(worktrees, formatted, status)` — emits `declare -a
  worktree_paths=(...)`, `declare -a formatted_options=(...)`,
  `declare selection_status="..."`, `declare -i worktree_count=N`
- `selection_to_bash_declare(result)` — emits `declare selected_path='...'` and
  `declare selection_status="..."`

### CLI entry points

**`prepare`** — gum path:
1. Loads worktrees via `parse_worktree_list()` (reuses worktree.py's git calls)
2. Applies `filter_worktrees()`
3. Calls `format_display_rows()`
4. Outputs declare statements for Bash to pipe into `gum_filter_by_index`

**`select`** — numbered-list path:
1. Same load + filter + format
2. Prints numbered list to stderr
3. Reads user input from stdin
4. Outputs declare statements with selected path and status

**CLI flags:** `--include-main`, `--exclude-current`, `--prompt "..."`

### Key design choice: reuse worktree.py's git calls

Unlike `tag_select.py` which implements its own `_run_git()` and `load_tags()`,
`worktree_select.py` delegates all git interaction to `worktree.py`'s
`parse_worktree_list()` and `_check_worktree_dirty()`. No duplicated subprocess
code.

## Bash Adapter

### Shared function in `hug-git-worktree`

```bash
select_worktree() {
    local selected_path_var="$1"  # nameref for result
    shift
    # Options: --include-main, --exclude-current, --prompt "..."
    # Return: 0=selected, 1=cancelled, 2=error/no-data
}
```

This function:
- Builds `python_args` from options
- Gum path (>= 10 items + gum available): calls `prepare`, pipes to
  `gum_filter_by_index`, maps index to `worktree_paths[]`
- Non-gum path (< 10 items or no gum): calls `select`, reads back
  `selected_path` and `selection_status`

### Command script changes

Each script's interactive selection block collapses to ~10 lines:

- **git-wt** (lines 207-335 → ~10): `select_worktree result_path --prompt "Select worktree to switch to:"`
- **git-wtdel** (`show_interactive_removal_menu` 53-185 → ~10): `select_worktree result_path --exclude-current --prompt "Select worktree to remove:"`
- **git-wtsh** (`interactive_worktree_selection` 78-146 → ~10): `select_worktree result_path --include-main --prompt "Select worktree to show details:"`

**git-wtsh gains a numbered-list fallback** it never had.

### What stays in Bash

- Non-interactive modes: `--summary`, `--json`, `--all`, search filtering
- `show_worktree_details()` (display-only, not selection)
- The `< 10` threshold (UX policy decision)
- `switch_to_worktree()`, `remove_worktree()`, confirmation logic

## Testing Strategy

### pytest (~40-50 tests)

- `TestFilterWorktrees` — include/exclude main, exclude current, empty list,
  all-excluded edge case
- `TestFormatDisplayRows` — status indicator combinations (current/dirty/locked),
  path shortening (`$HOME` → `~`), detached HEAD, empty branch
- `TestBashEscape` — spaces, quotes, backslashes in paths
- `TestWorktreesToBashDeclare` — declare output format, empty list, status values
- `TestCLIPrepare` — mock `parse_worktree_list`, verify full declare output
- `TestCLISelect` — mock stdin for valid selection, cancel (empty), invalid input,
  out-of-range

Uses `@patch("git.worktree_select.parse_worktree_list")` — no real git calls.
`worktree.py` already has its own 30-test suite for parsing correctness.

### BATS regression

Existing worktree tests continue to pass. No new BATS tests unless observable
CLI behavior changes (it shouldn't — same display format, same return codes).

## Scope Boundaries

### In scope
- `worktree_select.py` with filtering, formatting, selection
- Shared `select_worktree()` in `hug-git-worktree`
- Refactor `git-wt`, `git-wtdel`, `git-wtsh` interactive selection paths
- Fix `git-wtsh` missing non-gum fallback
- Fix all three to use `gum_filter_by_index` via the shared function
- pytest suite

### Out of scope
- Non-interactive display modes stay in Bash
- `show_worktree_details()` stays in Bash
- `worktree.py` unchanged
- No `_bash_escape()` unification across modules
- No generic selection framework (premature abstraction)

### Future work (not this task)
- Compare `worktree_select.py` with `tag_select.py` and `branch_select.py` for
  shared selection core potential
- Consider whether `format_display_rows` patterns across modules warrant a
  shared formatting helper
