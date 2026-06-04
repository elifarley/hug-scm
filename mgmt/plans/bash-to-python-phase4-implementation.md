# Plan: Phase 4 - get_worktrees Python Integration

## Executive Summary

Phase 4 Python module (`worktree.py`) was created in earlier work but was **never integrated** into the Bash code (`hug-git-worktree`). The plan documents claimed Phase 4 was complete, but the actual Bash integration with feature flags had not been done.

**Status:** COMPLETED (2026-01-31)
**Implementation Commits:**
- `d27829a` - Integrated Python worktree module into get_worktrees functions
- `eadc665` - Added HUG_USE_PYTHON_WORKTREE feature flag with Bash fallback

**Actual Effort:** ~2 hours
**Risk:** Low (Python module was already tested and working)

---

## Implementation Completed

### Completion Summary (2026-01-31)

The Python module integration is now complete with feature flag support for gradual rollout.

### What Was Done

1. **Task #12 (Commit d27829a):** Integrated Python worktree module into both `get_worktrees()` and `get_all_worktrees_including_main()` functions
   - Removed 165 lines of duplicate Bash state machine parsing code
   - Added 82 lines of Python integration code
   - Net reduction: 83 lines of Bash code
   - Fixed bug in worktree.py to handle both "commit " and "HEAD " lines from git worktree output

2. **Task #16 (Commit eadc665):** Added `HUG_USE_PYTHON_WORKTREE` feature flag with Bash fallback
   - Restored Bash implementation as fallback (221 lines added)
   - Feature flag defaults to `true` (Python mode)
   - Both Python and Bash implementations tested independently

### What Exists Now

**File:** `git-config/lib/python/git/worktree.py` (~400 lines)

**Components:**
- `WorktreeInfo` dataclass for single worktree information
- `WorktreeList` dataclass with `to_bash_declare()` for bash output
- `parse_worktree_list()` state machine parser for `git worktree list --porcelain`
- `main()` CLI entry point with `--include-main` and `--main-repo-path` flags
- `_bash_escape()` helper for string escaping
- `_check_worktree_dirty()` for dirty status detection

**Tests:** `git-config/lib/python/tests/test_worktree.py` (~570 lines, 30 tests, all passing)

**File:** `git-config/lib/hug-git-worktree`

**Current state:** Python integration with Bash fallback via feature flag

**Functions with Python integration:**
1. `get_worktrees()` - Now uses Python module (with Bash fallback)
2. `get_all_worktrees_including_main()` - Now uses Python module (with Bash fallback)

---

## Implementation Plan

### Step 1: Integrate Python Module into `get_worktrees()`

**Current code (lines 34-148):**
```bash
get_worktrees() {
    local -n paths_ref="$1"
    local -n branches_ref="$2"
    ...

    # Parse git worktree list --porcelain output
    local -a worktree_output
    mapfile -t worktree_output < <(git worktree list --porcelain 2>/dev/null)

    # ... ~100 lines of state machine parsing ...
}
```

**Target structure:**
```bash
get_worktrees() {
    local -n paths_ref="$1"
    local -n branches_ref="$2"
    ...

    # Get main repository path
    local main_repo_path
    main_repo_path=$(git rev-parse --show-toplevel 2>/dev/null)

    # Use Python module for worktree parsing
    local -a _wt_paths=() _wt_branches=() _wt_commits=()
    local -a _wt_dirty=() _wt_locked=()

    eval "$(python3 "$HUG_HOME/git-config/lib/python/git/worktree.py" list \
              --main-repo-path "$main_repo_path")"

    # Assign Python outputs to namerefs
    paths_ref=("${_wt_paths[@]}")
    branches_ref=("${_wt_branches[@]}")
    commits_ref=("${_wt_commits[@]}")
    status_ref=("${_wt_dirty[@]}")
    locked_ref=("${_wt_locked[@]}")

    return 0
}
```

**Lines to remove:** ~100 lines of state machine parsing
**Lines to add:** ~15 lines of Python integration

### Step 2: Replace `get_all_worktrees_including_main()` with Python call

**Current code (lines 180-268):**
```bash
get_all_worktrees_including_main() {
    # ... ~90 lines of duplicate state machine parsing ...
}
```

**Target structure:**
```bash
get_all_worktrees_including_main() {
    local -n paths_ref="$1"
    local -n branches_ref="$2"
    ...

    # Get main repository path
    local main_repo_path
    main_repo_path=$(git rev-parse --show-toplevel 2>/dev/null)

    # Use Python module with --include-main flag
    local -a _wt_paths=() _wt_branches=() _wt_commits=()
    local -a _wt_dirty=() _wt_locked=()

    eval "$(python3 "$HUG_HOME/git-config/lib/python/git/worktree.py" list \
              --main-repo-path "$main_repo_path" --include-main)"

    # Assign Python outputs to namerefs
    paths_ref=("${_wt_paths[@]}")
    branches_ref=("${_wt_branches[@]}")
    commits_ref=("${_wt_commits[@]}")
    status_ref=("${_wt_dirty[@]}")
    locked_ref=("${_wt_locked[@]}")

    return 0
}
```

**Lines to remove:** ~90 lines (entire function body)
**Lines to add:** ~15 lines (Python call with --include-main flag)

**Note:** This eliminates the duplicate function entirely.

### Step 3: Add Feature Flag (Optional, Recommended for Gradual Rollout)

**Why add a feature flag?**
- Allows instant rollback if issues arise
- Enables parallel testing of Python vs Bash implementations
- Maintains the proven pattern from Phases 2, 3, 5

**Implementation:**
```bash
get_worktrees() {
    # ... declarations ...

    # Use Python module if feature flag is enabled (default)
    if [[ "${HUG_USE_PYTHON_WORKTREE:-true}" == "true" ]]; then
        # Python module implementation
        eval "$(python3 ... worktree.py list ...)"
    else
        # Bash fallback (original implementation)
        # ... state machine parsing ...
    fi
}
```

**Feature flag:** `HUG_USE_PYTHON_WORKTREE` (default: true)

### Step 4: Update Callers of `get_all_worktrees_including_main()`

**Find callers:**
```bash
grep -r "get_all_worktrees_including_main" git-config/
```

**Update callers** to use `get_worktrees --include-main` pattern:
- Either add a `--include-main` flag to `get_worktrees()`
- Or have Python module handle it via parameter

### Step 5: Verify Tests

**Test sequence:**
```bash
# Python tests
make test-lib-py TEST_FILTER="test_worktree"

# BATS library tests
make test-lib TEST_FILE=test_hug_git_worktree.bats

# Full test suite
make test
```

**Expected:** 30/30 Python tests passing, 39/39 worktree BATS tests passing

---

## Files to Modify

1. **git-config/lib/hug-git-worktree** (main integration)
   - Update `get_worktrees()` function
   - Replace `get_all_worktrees_including_main()` with Python call
   - Add feature flag if using gradual rollout

2. **git-config/bin/git-wtll** (if needed)
   - Update callers if they reference `get_all_worktrees_including_main()`

---

## Metrics

### Before Integration

| Metric | Value |
|--------|-------|
| Bash lines in get_worktrees() | ~120 |
| Bash lines in get_all_worktrees_including_main() | ~90 |
| Total duplicate parsing code | ~210 |
| Python module exists | Yes (~400 lines) |
| Python tests passing | 30/30 (100%) |
| Bash integration | No |

### After Integration (Actual)

| Metric | Value |
|--------|-------|
| Bash lines removed (initial integration) | 165 |
| Bash lines added (Python integration) | 82 |
| Bash lines added (Bash fallback restored) | 221 |
| Net change | +138 lines (with type safety and feature flag) |
| Feature flags added | 1 (HUG_USE_PYTHON_WORKTREE) |
| Total Bash lines removed (all phases) | ~655 |
| Python tests passing | 30/30 (100%) |
| BATS tests passing | 505/505 (100%) |

**Note on net line increase:** While the net line count increased by 138 lines, this provides:
- Type safety through Python dataclasses
- Feature flag for safe rollback
- Dual implementation for gradual rollout
- The Bash fallback can be removed in future cleanup (like other phases)

---

## Testing Strategy

### Before Integration

1. Verify Python tests pass: `make test-lib-py TEST_FILTER="test_worktree"`
2. Document baseline: `make test-lib TEST_FILE=test_hug_git_worktree.bats`

### During Integration

1. Add Python integration with feature flag first
2. Test with both Python (default) and Bash (flag=false)
3. Compare outputs to ensure equivalence
4. Remove Bash fallback once Python is proven

### After Integration

1. Run full test suite: `make test`
2. Manual smoke test: `hug wtll` (worktree list command)
3. Verify all worktree operations work correctly

---

## Rollback Plan

### Quick Rollback (< 1 minute)
```bash
export HUG_USE_PYTHON_WORKTREE=false
```

### Git Revert (< 5 minutes)
```bash
git revert <integration-commit>
```

---

## Success Criteria

- [x] Python module integrated into `get_worktrees()`
- [x] `get_all_worktrees_including_main()` replaced with Python call
- [x] Feature flag added (HUG_USE_PYTHON_WORKTREE)
- [x] All 30 Python tests passing
- [x] All 39 BATS worktree tests passing
- [x] No breaking changes to existing functionality
- [x] 165 Bash lines removed initially (before feature flag restoration)

**Result:** All success criteria met ✓

---

## Timeline

| Step | Description | Time |
|------|-------------|------|
| 1 | Integrate Python into get_worktrees() | 45 min |
| 2 | Replace get_all_worktrees_including_main() | 30 min |
| 3 | Add feature flag with Bash fallback | 20 min |
| 4 | Update callers | 15 min |
| 5 | Verify tests | 10 min |
| **Total** | | **~2 hours** |

---

## Why This Wasn't Done Before

### Root Cause Analysis

1. **Phase 4 completion document** claimed completion, but only documented the Python module creation
2. **Bash integration** was marked as "complete" in progress summary, but it wasn't actually done
3. **No feature flag** exists in hug-git-worktree (verified via grep)
4. **hug-git-worktree** still uses pure Bash state machine parsing

### Impact

- **~210 lines of duplicate code** remain in hug-git-worktree
- **No type safety** for worktree operations
- **Maintenance burden** - bug fixes need to be applied to both modules (if Python was integrated)

---

## Next Steps

1. ~~Review and approve this plan~~ ✓ Done
2. ~~Execute Step 1 (integrate Python into get_worktrees)~~ ✓ Done (d27829a)
3. ~~Execute Step 2 (replace get_all_worktrees_including_main)~~ ✓ Done (d27829a)
4. ~~Execute Step 3 (add feature flag)~~ ✓ Done (eadc665)
5. ~~Execute Step 4 (update callers)~~ ✓ Done (no callers needed updating)
6. ~~Execute Step 5 (verify tests)~~ ✓ Done (505/505 BATS, 30/30 Python)
7. ~~Update documentation to mark Phase 4 truly complete~~ ✓ Done (this update)

## Lessons Learned

### Bug Discovered During Integration

The Python `worktree.py` module originally only handled `commit ` lines in the porcelain output, but `git worktree list --porcelain` actually outputs `HEAD ` lines for detached HEAD worktrees. This was fixed during integration by adding support for both formats:

```python
# Before: only handled "commit "
if line.startswith("commit "):
    commit = line.split(" ", 1)[1]

# After: handles both "commit " and "HEAD "
if line.startswith("commit ") or line.startswith("HEAD "):
    commit = line.split(" ", 1)[1]
```

This bug was only discovered when running the actual BATS integration tests with real git worktree output, demonstrating the value of integration testing even when unit tests pass.

### Feature Flag Pattern Validation

The HUG_USE_PYTHON_WORKTREE feature flag pattern (default: true) was validated as the correct approach for gradual rollout:
- Python mode tested in production first
- Easy rollback via environment variable
- Bash implementation preserved as fallback
- Matches patterns used successfully in Phases 2, 3, and 5

---

**Status:** COMPLETED ✓
**Created:** 2026-01-31
**Completed:** 2026-01-31
**Author:** Claude Code
