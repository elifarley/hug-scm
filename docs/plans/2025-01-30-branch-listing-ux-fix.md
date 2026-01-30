# Plan: Fix Branch Listing Consistency and Gum Filter UX

## Status

**COMPLETED** - Implementation finished and all tests passing.

## Problem Summary

1. **`hug b`**: Cursor at bottom (with `--reverse`), but newest branches at top - oldest at cursor position ❌
2. **`hug bdel`**: Cursor at top (no `--reverse`), newest branches at top - correct ✓
3. **Static output** (`hug bl`, `hug bll`): Oldest first, newest at bottom - correct ✓
4. **Tests didn't catch this** because they mock gum entirely or use EOF simulation
5. **Placeholder text is hardcoded** in `print_interactive_branch_menu()`

## Root Cause Analysis

### Gum Filter Design (Correct - Should Not Change)

| Selection Type | Cursor Position | Gum Flag | UX Reasoning |
|---------------|-----------------|----------|---------------|
| **Single-select** | **Bottom** | `--reverse` | User expectation: when opening a picker, pressing ↑ naturally moves toward more recent items (which are "above" in mental model). With cursor at bottom, ↑ shows newest branches immediately. |
| **Multi-select** | **Top** | none | TAB workflow: after TAB to select current item, gum moves cursor DOWN to next item. With cursor at top and newest at top, user can TAB through branches from newest to oldest without scrolling. |

### Current Sort Order Issue (FIXED)

The Python module (`hug_git_branch.py`) sorts by **commit date descending** (newest first) by default. This created the mismatch where single-select menus had newest branches at the top while the cursor was at the bottom.

### Desired State (ACHIEVED)

| Context | Sort Order | Cursor Position | What User Sees First | UX Reasoning |
|---------|-----------|-----------------|---------------------|---------------|
| Single-select (`hug b`) | **Oldest first** ✓ | Bottom | Newest branches | Cursor at bottom (due to `--reverse`), newest at bottom = immediate access to recent work |
| Multi-select (`hug bdel`) | **Newest first** ✓ | Top | Newest branches | Cursor at top, newest at top = first TAB selects newest, subsequent TABs go to older branches |
| Static (`hug bl`, `hug bll`) | Oldest first ✓ | N/A | Oldest first | Terminal output scrolls down; newest at bottom puts recent work near terminal cursor/proximity |

## Solution Implemented

### 1. Added Context-Aware Sorting to Python Module ✅

**File**: `git-config/lib/python/hug_git_branch.py`

Added `--sort-context` parameter with three valid values:

| Context Value | Sort Order | Git Flag | Usage |
|---------------|-----------|----------|-------|
| `gum-single` | Ascending (oldest first) | `--sort=committerdate` | Single-select menus (`hug b`) |
| `gum-multi` | Descending (newest first) | `--sort=-committerdate` | Multi-select menus (`hug bdel`) |
| `static` | Ascending (oldest first) | `--sort=committerdate` | Static output |

**Key Implementation Detail**: Default behavior (no `--sort-context`) remains descending for backward compatibility with existing code and tests.

### 2. Updated Bash Library Functions ✅

**File**: `git-config/lib/hug-git-branch`

#### 2a. Added `sort_context` parameter to `compute_local_branch_details()`

```bash
compute_local_branch_details() {
    # ... existing parameters ...
    local include_subjects="${7:-false}"
    local sort_context="${8:-}"  # NEW: gum-single, gum-multi, or static

    # If sort_context is specified, use Python module
    if [[ -n "$sort_context" ]]; then
        local python_args=(local)
        python_args+=(--sort-context="$sort_context")
        eval "$(python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" "${python_args[@]}")"
        # Copy values to namerefs
        current_branch_ref="$current_branch"
        max_len_ref="$max_len"
        branches_ref=("${branches[@]}")
        # ... etc
        return 0
    fi
    # ... existing bash implementation ...
}
```

#### 2b. Added placeholder parameter to `print_interactive_branch_menu()`

```bash
print_interactive_branch_menu() {
    # ... existing parameters ...
    local -n subjects_ref="$7"
    local placeholder="${8:-Pick one to switch to...}"  # NEW

    # ... use placeholder in gum filter call ...
}
```

#### 2c. Updated `select_branches()` to pass correct sort context

- Automatically determines sort context based on single/multi-select mode
- Uses Python module with sort context when available
- Fixed variable shadowing bug by using unique variable names (`sel_branches`, `sel_current_branch`, etc.)

```bash
select_branches() {
    # ... options parsing ...

    # Determine sort context if not explicitly set
    if [[ -z "$sort_context" ]]; then
        if [[ "$multi_select" == "true" ]]; then
            sort_context="gum-multi"  # Descending for multi-select
        else
            sort_context="gum-single"  # Ascending for single-select
        fi
    fi

    # Use unique variable names to avoid shadowing Python module output
    declare -a sel_branches=() sel_hashes=() sel_subjects=() sel_tracks=()
    local sel_current_branch="" sel_max_len=""

    compute_local_branch_details sel_current_branch sel_max_len sel_hashes sel_branches sel_tracks sel_subjects "true" "$sort_context"
    # ...
}
```

### 3. Updated Command Callers ✅

**File**: `git-config/bin/git-b`

```bash
# Use --sort-context=gum-single for ascending sort
if ! eval "$(python3 "$CMD_BASE/../lib/python/hug_git_branch.py" local --sort-context=gum-single)"; then
  error "No local branches found."
  exit 1
fi

# Pass placeholder to menu function
print_interactive_branch_menu selected_branch "$current_branch" "$max_len" hashes branches tracks subjects "Pick one to switch to..."
```

## Files Modified

1. ✅ `git-config/lib/python/hug_git_branch.py` - Added `--sort-context` parameter support
2. ✅ `git-config/lib/hug-git-branch` - Added sort context and placeholder parameters
3. ✅ `git-config/bin/git-b` - Updated to use `--sort-context=gum-single` and placeholder

## Verification Steps Completed

1. ✅ Run `make test-bash TEST_FILTER="branch"` - All branch tests pass
2. ✅ Run `make test-lib-py` - Python module tests pass
3. ✅ Manual test `hug b` with 10+ branches:
   - Cursor starts at bottom
   - Newest branch is at bottom (at cursor position)
4. ✅ Manual test `hug bdel`:
   - Cursor starts at top
   - Newest branch is at top (at cursor position)
5. ✅ Verify `hug bl` and `hug bll` still show oldest first, newest at bottom
6. ✅ All `hug bdel` tests pass (20/20)

## Remaining Work (Optional)

### 1. Add Tests for Sort Context Parameter (OPTIONAL)

**File**: `tests/lib/test_hug_git_branch_python.bats`

Add tests for `--sort-context` parameter:
- `--sort-context=gum-single` → ascending (oldest first)
- `--sort-context=gum-multi` → descending (newest first)
- `--sort-context=static` → ascending (oldest first)
- Default (no flag) → descending (newest first) for backward compatibility

### 2. Add Gum Filter Behavioral Tests (OPTIONAL)

**File**: `tests/lib/test_hug_gum_filter.bats` (new file to create)

Add behavioral tests:
- Single-select gum filter uses `--reverse` flag
- Multi-select gum filter does NOT use `--reverse` flag
- Placeholder text is passed correctly

### 3. Add Branch Switch Sort Order Test (OPTIONAL)

**File**: `tests/unit/test_branch_switch.bats`

Add test verifying branches are in correct order (oldest first) for single-select context.

## Lessons Learned

### Bash Variable Shadowing with eval and namerefs

**CRITICAL ISSUE DISCOVERED**: When using `eval` to execute `declare` statements inside a function that creates variables with the same names as the caller's variables, bash creates function-local variables that shadow the caller's variables. This causes nameref assignments to fail silently.

**Example of the problem:**
```bash
caller_function() {
    declare -a branches=()  # Caller's local variable
    inner_function branches    # Pass name "branches" to function
}

inner_function() {
    local -n branches_ref="$1"  # Nameref to caller's "branches"

    # This eval creates a FUNCTION-LOCAL variable named "branches"
    # that shadows the caller's "branches" variable
    eval 'declare -a branches=("a" "b" "c")'

    # This assigns to the function-local "branches", not the caller's "branches"
    branches_ref=("${branches[@]}")  # ❌ Doesn't affect caller's variable!
}
```

**Solution**: Use different variable names inside the function to avoid shadowing:
```bash
select_branches() {
    # Use unique names that won't conflict with Python module output
    declare -a sel_branches=() sel_hashes=() ...
    local sel_current_branch="" sel_max_len=""

    # Now "sel_branches" won't be shadowed by eval'd "branches" variable
    compute_local_branch_details sel_current_branch sel_max_len sel_hashes sel_branches ...
}
```

### Design Philosophy

- **Cursor position and sort order must be aligned**: The most relevant items (newest branches) should be at the user's immediate access point
- **Single-select**: `--reverse` puts cursor at bottom → sort ascending so newest is at bottom
- **Multi-select**: no `--reverse` puts cursor at top → sort descending so newest is at top
- **Static output**: sort ascending so newest is at bottom (near terminal cursor/proximity)

### Testing Challenges

- Tests that mock gum entirely won't catch UX issues like cursor/sort misalignment
- EOF simulation tests (`echo "" | command`) can't test gum filter behavior
- For interactive UX testing, use gum mock system (`setup_gum_mock`) or manual verification
- Always test both with gum available and with gum disabled

### Backward Compatibility

- When adding new parameters like `--sort-context`, default behavior must match original behavior
- Existing tests that don't pass the new flag should continue to pass
- Default for `--sort-context` is `None` (descending), not `static` (ascending), to preserve existing behavior
