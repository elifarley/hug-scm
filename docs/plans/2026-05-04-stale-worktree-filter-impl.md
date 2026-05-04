# Fix: Stale Worktrees Appear in Interactive Menus

## Context

When a worktree directory is deleted externally (e.g., `rm -rf`) without `git worktree remove`, `git worktree list --porcelain` still reports the stale entry. The Python selection layer trusts this data, so interactive menus (`hug wtdel`, `hug wt`, `hug wtsh`) offer phantom worktrees that produce confusing warnings when selected.

**Symptom:** `⚠️ Warning: Worktree path does not exist: /tmp/wt-test-many/.wt-dirty`

## Root Cause Evidence

1. **No pruning before selection:** Neither `worktree_select.py` nor `worktree.py` call `git worktree prune`. Stale entries flow through unfiltered.
2. **Path source is `git worktree list --porcelain`:** The path `/tmp/wt-test-many/.wt-dirty` is exactly what git reports — no mangling or fabrication occurs in the Python or Bash layers.
3. **False dirty indicator on stale entries:** `_check_worktree_dirty()` runs `git -C <stale_path> diff --quiet`, which fails with exit code 128 ("cannot change to directory"). The function treats non-zero as "has changes", so stale entries appear with a `+` dirty indicator — making them look real.
4. **No existence check anywhere:** `filter_worktrees()` only checks `include_main` and `exclude_current`. `parse_worktree_list()` trusts git's porcelain output. No layer verifies the directory exists.

## Architecture

```
                    ┌──────────────────────┐
                    │  git-wtdel (Bash)     │
                    │  Lines 187-344       │
                    └─────────┬────────────┘
                              │ calls via eval
                    ┌─────────▼────────────┐
                    │ worktree_select.py   │
                    │ _cmd_prepare()       │◄─── git-wt (switch)
                    │ _cmd_select()        │◄─── git-wtdel (delete)
                    │ _cmd_filter()        │◄─── git-wtl (listing)
                    └─────────┬────────────┘
                              │ calls
                    ┌─────────▼────────────┐
                    │ filter_worktrees()   │  ← CHANGED: add exclude_stale
                    │ + exclude_stale      │     (True for prepare/select,
                    └─────────┬────────────┘      False for filter)
                              │ calls
                    ┌─────────▼────────────┐
                    │ worktree.py          │
                    │ parse_worktree_list()│  ← NOT changed
                    │ _check_worktree_     │  ← CHANGED: add isdir guard
                    │   dirty_details()    │
                    └──────────────────────┘
```

## Implementation Checklist

Execute in this order. Each step is self-contained.

### Step 1: Early-exit guard in dirty detection

**File:** `git-config/lib/python/git/worktree.py:240`

Add `isdir` guard at the top of `_check_worktree_dirty_details()`, before the `try` block:

```python
def _check_worktree_dirty_details(worktree_path: str) -> WorktreeDirtyInfo:
    # WHY: Stale worktrees (directory deleted externally) cause all three
    # git subprocess calls to fail with exit code 128. Without this guard,
    # each call takes up to 5 seconds (timeout) before failing — wasting
    # ~15 seconds per stale entry in listing commands.
    if not os.path.isdir(worktree_path):
        return WorktreeDirtyInfo(
            is_dirty=False, has_unstaged=False,
            has_staged=False, has_untracked=False, details="",
        )
    try:
        # ... existing code ...
```

`os` is not currently imported in `worktree.py` — add `import os` at the top.

### Step 2: Add `exclude_stale` to filter options

**File:** `git-config/lib/python/git/worktree_select.py:57`

Add `exclude_stale` field to `WorktreeFilterOptions` dataclass:

```python
@dataclass
class WorktreeFilterOptions:
    include_main: bool = True
    exclude_current: bool = False
    exclude_stale: bool = True
```

Update docstring to describe `exclude_stale`: "If True, exclude worktrees whose directory does not exist on disk. True by default to prevent phantom entries in interactive menus."

### Step 3: Add isdir filter to `filter_worktrees()`

**File:** `git-config/lib/python/git/worktree_select.py:120`

After the existing `exclude_current` filter, add:

```python
    if options.exclude_stale:
        result = [w for w in result if os.path.isdir(w.path)]
    return result
```

### Step 4: Disable stale filtering for listing commands

**File:** `git-config/lib/python/git/worktree_select.py:486`

In `_cmd_filter()`, override `exclude_stale=False` so listing commands keep stale entries:

```python
def _cmd_filter(
    options: WorktreeFilterOptions,
    branch_filters: list[str],
    search_terms: str,
) -> str:
    # Listing commands should show stale entries (diagnostic purpose).
    # Interactive commands (prepare/select) filter them out by default.
    listing_opts = WorktreeFilterOptions(
        include_main=options.include_main,
        exclude_current=options.exclude_current,
        exclude_stale=False,
    )
    worktrees, main_path, current_path = _load_worktrees()
    # ... use listing_opts instead of options in the filter call below ...
    filtered = filter_worktrees(worktrees, listing_opts, main_path, current_path)
```

### Step 5: Add `--include-stale` CLI flag

**File:** `git-config/lib/python/git/worktree_select.py:610`

Add to the `common` argparse parent (after `--exclude-current`):

```python
common.add_argument(
    "--include-stale",
    action="store_true",
    default=False,
    help="Include worktrees whose directories no longer exist (for debugging).",
)
```

### Step 6: Wire flag in `main()`

**File:** `git-config/lib/python/git/worktree_select.py:655`

Update the `WorktreeFilterOptions` construction:

```python
opts = WorktreeFilterOptions(
    include_main=args.include_main,
    exclude_current=args.exclude_current,
    exclude_stale=not args.include_stale,
)
```

### Step 7: Auto-prune stale paths in `git-wtdel`

**File:** `git-config/bin/git-wtdel:199`

Replace the existing `[[ ! -e "$worktree_path" ]]` block with stale detection + auto-prune:

```bash
if [[ ! -e "$worktree_path" ]]; then
    if git worktree list --porcelain 2>/dev/null | grep -qxF "worktree $worktree_path"; then
        info "Worktree directory already removed: ${worktree_path/#$HOME/\~}"
        if ! $dry_run; then
            info "Cleaning up orphaned Git metadata..."
            git worktree prune 2>/dev/null
            success "Pruned stale worktree entry: ${worktree_path/#$HOME/\~}"
        else
            info "Would prune stale worktree metadata (dry run)"
        fi
        removed+=("$worktree_path (pruned)")
        continue
    fi
    warning "Worktree path does not exist: $worktree_path"
    path_valid=false
fi
```

Key differences from the original plan code:
- Uses `grep -qxF` (full-line match) instead of `grep -qF` (substring match)
- Guards prune with `if ! $dry_run`
- Updates `removed` counter for batch summary

### Step 8: Update `git-wtdel` help text

**File:** `git-config/bin/git-wtdel:31`

Add to the DESCRIPTION section after the existing bullet points:

```
    - Automatically detects and prunes stale worktree metadata
      (directories removed externally without 'git worktree remove')
```

### Step 9: Tests

**Python tests** — `git-config/lib/python/tests/test_worktree_select.py`:

1. Update `TestWorktreeFilterOptions.test_defaults` to verify `exclude_stale=True` default
2. Update `test_custom_values` to verify `exclude_stale=False` works
3. Add `test_excludes_stale_by_default` to `TestFilterWorktrees` — mock `os.path.isdir` to return False for one worktree; verify excluded
4. Add `test_include_stale_option` — `exclude_stale=False` keeps all worktrees
5. Add `test_stale_filter_combined_with_other_filters` — all three filters compose
6. Add `test_stale_worktrees_excluded_from_prepare` to `TestCmdPrepare`
7. Add `test_stale_worktrees_included_when_flag_set` to `TestCmdPrepare` (inverse)
8. Add `test_stale_worktrees_excluded_from_select` to `TestCmdSelect`
9. Add `test_stale_worktrees_included_when_flag_set` to `TestCmdSelect` (inverse)
10. Add `test_filter_does_not_exclude_stale_by_default` to new `TestCmdFilter` class
11. Add `test_include_stale_flag` to `TestMain`
12. Add `test_all_stale_gives_no_worktrees` — every worktree stale → `no_worktrees` status

**Python tests** — `git-config/lib/python/tests/test_worktree.py`:

13. Add `test_stale_path_returns_clean_without_subprocess` — non-existent path returns `is_dirty=False`, verify zero subprocess calls

**BATS tests** — `tests/unit/test_worktree_remove.bats`:

14. `test_auto_prune_stale_worktree` — create stale git entry, verify `wtdel -p` prunes it
15. `test_stale_path_with_dry_run_does_not_prune` — stale + `--dry-run` → no prune, info message
16. `test_stale_and_valid_batch` — batch of stale + valid: stale auto-pruned, valid removed normally
17. `test_stale_locked_worktree_auto_prune` — stale locked worktree: prune succeeds (lock is metadata-only)

### Verification

```bash
make test-lib-py TEST_FILTER="worktree_select"
make test-lib-py TEST_FILTER="worktree"
make test-unit TEST_FILE=test_worktree_remove.bats
make test
```

## Files Modified

| File | Change |
|---|---|
| `git-config/lib/python/git/worktree.py` | Add `import os`; add isdir guard in `_check_worktree_dirty_details()` |
| `git-config/lib/python/git/worktree_select.py` | Add `exclude_stale` to `WorktreeFilterOptions`; add isdir filter to `filter_worktrees()`; disable stale in `_cmd_filter()`; add `--include-stale` flag; wire in `main()` |
| `git-config/bin/git-wtdel` | Auto-prune stale paths with dry-run guard; `grep -qxF` fix; update help text |
| `git-config/lib/python/tests/test_worktree_select.py` | 12 new/updated tests covering stale filtering |
| `git-config/lib/python/tests/test_worktree.py` | 1 new test for isdir guard |
| `tests/unit/test_worktree_remove.bats` | 4 new BATS tests for auto-prune behavior |

## What This Does NOT Change

- `worktree.py` `parse_worktree_list()` — stale entries still flow through for listing commands
- `WorktreeInfo` dataclass — no new fields (stale-ness is a filter concern, not data)
- `git-wt`, `git-wtsh` — benefit automatically from `filter_worktrees()`, no script changes needed

## Error & Rescue Registry

| Error | Trigger | Recovery | User sees |
|---|---|---|---|
| Stale worktree in menu | External dir deletion | Filtered from menu; auto-prune in delete | Menu shows only valid worktrees |
| False dirty indicator | `_check_worktree_dirty()` on missing path | Early-exit guard returns clean | Listing shows `. ` (clean) for stale entries |
| NFS/symlink temporary disappearance | Network blip during `wtdel` | `git worktree prune` removes metadata; user can `hug wtc` to recreate | Info message about pruning |
| Race condition: dir deleted between filter and selection | Concurrent terminal | `git-wtdel` auto-prune catches it | Success message with prune |

---

<!-- /autoplan review artifacts below — context for future reference, not implementation instructions -->

## Decision Audit Trail

| # | Phase | Decision | Classification | Principle | Rationale | Rejected |
|---|-------|----------|-----------|-----------|----------|----------|
| 1 | CEO | Mode: SELECTIVE EXPANSION | Mechanical | P6 | Standard for bug fix plans | — |
| 2 | CEO | Add early-exit guard in `_check_worktree_dirty_details()` | Mechanical | P1, P2 | In blast radius, avoids 3 failing subprocess calls per stale entry | Reject: do nothing |
| 3 | CEO | Keep `--include-stale` flag | Taste | P5 | Positive framing (opt-in to show), costs nothing | Reject: remove flag |
| 4 | CEO | Keep auto-prune without extra confirmation | Taste | P3, P6 | User already chose to delete via `wtdel`; metadata cleanup is not data destruction | Reject: add confirmation |
| 5 | CEO | Keep "do not change WorktreeInfo" | Mechanical | P5 | Stale-ness depends on current filesystem state; modeling it makes dataclass impure | Reject: add `is_stale` field |
| 6 | CEO | Defer workspace reconciliation | Mechanical | P2, P3 | Outside blast radius | Reject: expand scope now |
| 7 | Eng | `_cmd_filter` also filters stale | Mechanical | P5 | Set `exclude_stale=False` in `_cmd_filter()` | Reject: let listing filter stale too |
| 8 | Eng | Auto-prune ignores dry-run | Mechanical | P1 | Guard with `if ! $dry_run` | Reject: no dry-run guard |
| 9 | Eng | `--include-stale` not in bash callers | Taste | P3, P6 | Flag is for Python CLI/testing; bash callers use correct default | Reject: remove flag |
| 10 | Eng | `grep -F` substring match | Mechanical | P5 | Fix to `grep -qxF` for full-line match | Reject: keep grep -F |
| 11 | Eng | `wtsh` bash recomputes dirty | Mechanical | P3 | Stale filter prevents stale in interactive wtsh | Reject: fix wtsh bash |
| 12 | Eng | Missing BATS tests for wtdel | Mechanical | P1 | Add 4 BATS tests | Reject: Python-only tests |
| 13 | DX | No user-facing docs | Mechanical | P1 | Update git-wtdel help text | Reject: no doc changes |
| 14 | DX | Scattered implementation details | Mechanical | P5 | Consolidated into checklist above | Reject: keep plan as-is |
| 15 | DX | No changelog/upgrade note | Mechanical | P3 | Defer to commit message | Reject: add changelog |
| 16 | DX | "Clean" for stale is misleading | Taste | P5 | Guard is perf optimization; stale filtered from menus anyway | Reject: add is_stale to dataclass |
| 17 | DX | Existing BATS test conflict | Mechanical | P1 | Verify existing test still passes; add new stale-prune test | Reject: assume tests pass |

## Cross-Phase Themes

**Consistent stale-worktree model** — flagged in CEO, Eng, DX. The plan creates different stale behavior for listing vs. action commands. Mitigated by `_cmd_filter()` override + help text docs.

**Auto-prune safety** — flagged in all 3 phases. Dry-run guard + `grep -qxF` fix + counter updates address the concerns.
