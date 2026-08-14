# Implementation Plan: wtdel Message Clarity

**Design doc:** `docs/plans/2026-05-04-wtdel-message-clarity-design.md`

## Steps

### Step 1: Update fallback success message (line 337)

**File:** `git-config/bin/git-wtdel`
**Change:** Update the `success` message to add `branch` prefix, and add `info` line showing deleted directory.

```bash
# Line 337 — BEFORE:
success "Worktree removed for '$wt_branch' (manual cleanup)"

# Line 337 — AFTER:
success "Worktree removed for branch '$wt_branch' (manual cleanup)"
info "Deleted directory: ${worktree_path/#$HOME/\~}"
```

### Step 2: Update normal success message (line 357)

**File:** `git-config/bin/git-wtdel`
**Change:** Update the `success` message to add `branch` prefix, and add `info` line showing deleted directory.

```bash
# Lines 357-358 — BEFORE:
success "Worktree removed for '$wt_branch'"
echo

# Lines 357-358 — AFTER:
success "Worktree removed for branch '$wt_branch'"
info "Deleted directory: ${worktree_path/#$HOME/\~}"
echo
```

### Step 3: Update test assertion for specific branch name

**File:** `tests/unit/test_worktree_remove.bats`
**Line:** 550

```bash
# BEFORE:
assert_output --partial "Worktree removed for 'hotfix-1'"

# AFTER:
assert_output --partial "Worktree removed for branch 'hotfix-1'"
```

The other three assertions (`--partial "Worktree removed"`) will continue to match because they're substring checks.

### Step 4: Run tests

```bash
make test-unit TEST_FILE=test_worktree_remove.bats TEST_SHOW_ALL_RESULTS=1
```
