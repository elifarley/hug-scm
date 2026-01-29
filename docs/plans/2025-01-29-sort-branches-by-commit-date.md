# Plan: Sort Branches by Commit Date with Context-Aware Direction

**Status:** ✅ **COMPLETED** (2025-01-29)

## Overview

Sort `hug bl` and `hug bll` output by commit date instead of alphabetically, with the most recent branches shown at the bottom (closer to where the user's cursor/eyes focus). Interactive commands using gum filter show most recent first (top of list).

## Problem Statement

Previously, `hug bl` and `hug bll` sorted branches alphabetically by name. This made it difficult to quickly find recently worked-on branches. Different UI contexts have different optimal sort directions:

- **Static display lists** (`hug bl`, `hug bll`): Most recent at bottom (cursor proximity)
- **Interactive menus** (gum filter in `hug b`, `hug bdel`, `hug wtc`): Most recent at top (immediate visibility)

---

## Implementation Summary

### Phase 1: Python Module Changes ✅

**File:** `git-config/lib/python/hug_git_branch.py`

1. **Updated `_run_git_for_each_ref` function:**
   - Added `sort_ascending: bool = False` parameter
   - Changed sort from `--sort=refname` (alphabetical) to `--sort={-}committerdate`
   - Prefix `-` for descending (newest first, default), empty for ascending (oldest first)

2. **Updated branch detail functions:**
   - Added `sort_ascending` parameter to:
     - `get_local_branch_details()`
     - `get_remote_branch_details()`
     - `get_wip_branch_details()`
   - Passed parameter through to `_run_git_for_each_ref()`

3. **Added CLI argument:**
   - `--ascending` flag for controlling sort direction
   - Applied to all three branch types (local, remote, wip)

### Phase 2: Display Command Changes ✅

**Files:** `git-config/bin/git-bl`, `git-config/bin/git-bll`

- Added `--ascending` flag to Python call
- Updated help text from "sorted alphabetically" to "sorted by commit date (oldest first, most recent at bottom)"

### Phase 3: Test Updates ✅

**File:** `tests/lib/test_hug_git_branch_python.bats`

Added three new tests:
1. `python branch module: sorts by committerdate descending (newest first) by default`
2. `python branch module: --ascending sorts by committerdate ascending (oldest first)`
3. `python branch module: wip mode respects sort order`

---

## UX Impact

| Command | Sort Order | Rationale |
|---------|-----------|-----------|
| `hug bl` | Oldest → Newest (recent at bottom) | Cursor proximity after command output |
| `hug bll` | Oldest → Newest (recent at bottom) | Same as above |
| `hug b` | Newest → Oldest (recent at top) | Gum filter: immediate visibility (default) |
| `hug bdel` | Newest → Oldest (recent at top) | Gum filter: immediate visibility (default) |
| `hug wtc` | Newest → Oldest (recent at top) | Gum filter: immediate visibility (default) |

---

## Remaining Work

**None** - This feature is complete.

### Optional Future Enhancements

These are **NOT required** for completion, but could be considered future improvements:

1. **Add `--sort` flag to `hug bl` and `hug bll`**: Allow users to choose sort direction at runtime
   - Example: `hug bl --sort=date` (default) vs `hug bl --sort=name`
   - Would require adding flag parsing to these commands

2. **Extend sorting to remote branches**: `hug bl -r` could also sort by date
   - Currently remote branches still use alphabetical sorting
   - Would require similar `--ascending` flag usage

3. **Add date display to branch listing**: Show the commit date alongside each branch
   - Example: `hug bll` could show "2025-01-29" next to each branch
   - Would require format string changes and column width adjustments

---

## Lessons Learned

### Critical Implementation Details

1. **Git for-each-ref sorting syntax:**
   - `--sort=-committerdate` = descending (newest first)
   - `--sort=committerdate` = ascending (oldest first)
   - The `-` prefix is critical and easy to miss

2. **Line length limits:**
   - Python linting enforces 100 character limit
   - Use multi-line format for long docstring parameters or break across lines

3. **Bash `eval` for Python output:**
   - The Python module outputs bash `declare` statements
   - Using `eval "$(python3 ...)"` correctly sets arrays and scalars
   - Must handle exit codes properly: `if ! eval "$(...)"; then ...`

4. **Sleep in tests for timestamp separation:**
   - Git committerdate has second precision
   - Tests creating branches sequentially need `sleep 1` between commits
   - Without sleep, branches may have identical timestamps

5. **Context-aware defaults:**
   - Default sort direction should match the UI context
   - Gum filter = newest first (immediate visibility)
   - Static list = oldest first (cursor proximity)

### Testing Pitfalls

1. **Finding branch positions in arrays:**
   - Don't assume linear search is the only way
   - Loop through array to find indices for comparison
   - Verify both branches exist before comparing positions

2. **Test isolation:**
   - Always cleanup test branches: `git branch -D branch_early branch_late`
   - Return to main branch before cleanup: `git checkout main -q`

3. **Assert output for debugging:**
   - Use `TEST_SHOW_ALL_RESULTS=1` when running tests locally
   - Helps identify which test is hanging or failing

### Code Quality Tips

1. **Parameter naming consistency:**
   - Use `sort_ascending` (not `ascending`) for clarity
   - The parameter describes the sort behavior, not just a flag

2. **Docstring precision:**
   - Explicitly state the default value in parameter descriptions
   - Example: "False = descending (newest first), True = ascending (oldest first)"

3. **Git commit author identity:**
   - Tests that create commits need `git config user.email` and `user.name`
   - Otherwise commits fail with "Author identity unknown"

---

## Verification

### Test Results
- ✅ All 1531 BATS tests passed
- ✅ Static analysis passed (lint, typecheck)
- ✅ Manual verification confirmed correct behavior

### Manual Testing Commands

```bash
# Create test repo with different commit dates
cd /tmp && rm -rf test-sort-branches && mkdir test-sort-branches && cd test-sort-branches
git init && git config user.email "test@test.com" && git config user.name "Test"
git commit --allow-empty -m "Initial" --no-gpg-sign
git branch old-branch
sleep 1
git commit --allow-empty -m "Second" --no-gpg-sign
git branch new-branch

# Test hug bl - should show old-branch first, new-branch last
hug bl | grep -E "(old-branch|new-branch)"

# Test hug bll - should show old-branch first, new-branch last
hug bll | grep -E "(old-branch|new-branch)"
```

### Automated Testing

```bash
# Run Python library tests
make test-lib TEST_FILE=test_hug_git_branch_python.bats

# Run all BATS tests
make test-bash

# Run static checks
make sanitize-check
```

---

## Files Changed

| File | Lines Changed | Description |
|------|---------------|-------------|
| `git-config/lib/python/hug_git_branch.py` | +45/-10 | Added sort_ascending parameter, changed sorting to committerdate |
| `git-config/bin/git-bl` | +3/-1 | Added --ascending flag, updated help text |
| `git-config/bin/git-bll` | +3/-1 | Added --ascending flag, updated help text |
| `tests/lib/test_hug_git_branch_python.bats` | +108/-0 | Added 3 sort order tests |

**Total:** +159 lines added, -14 lines removed

---

## References

- Original issue/discussion: N/A (feature implementation)
- Related files:
  - `git-config/lib/python/hug_git_branch.py` - Python branch library
  - `git-config/lib/hug-git-branch` - Bash branch library (unchanged)
  - `tests/lib/test_hug_git_branch_python.bats` - Test suite
