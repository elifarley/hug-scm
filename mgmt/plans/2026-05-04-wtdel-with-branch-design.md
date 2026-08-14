# Design: `wtdel --with-branch` Flag

**Date:** 2026-05-04
**Status:** Approved

## Problem

When removing a worktree with `hug wtdel`, the associated branch is left behind. Users must run a separate `hug bdel` command to clean up the branch. This two-step workflow leads to:

1. Orphaned branches accumulating over time (users forget the second step)
2. Confusion about which branches are "active" vs. stale
3. Unnecessary friction for the common case of "I'm done with this feature, clean everything up"

## Solution

Add an opt-in `--with-branch` / `-B` flag to `wtdel` that also deletes the associated branch after removing the worktree.

**Flag choice:** Uppercase `-B` (harder to type) signals destructive behavior, consistent with Hug's safety philosophy and Git's `-D` vs `-d` convention.

## Design

### Flag Specification

| Flag | Short | Behavior |
|------|-------|----------|
| `--with-branch` | `-B` | After removing the worktree, delete the associated branch |

### Execution Flow

1. Run existing worktree removal logic unchanged (all current safety checks: dirty detection, locked check, main/current protection)
2. On successful worktree removal, resolve the branch name from the removed worktree (already captured before removal begins)
3. If branch is detached HEAD or doesn't exist → skip branch deletion silently
4. If branch exists:
   - **Merged** → delete with confirmation (unless `--force`)
   - **Unmerged** → warn with unmerged commit count, prompt for explicit confirmation
5. Report branch deletion outcome in the output

### Confirmation Flow

| Scenario | Without `--force` | With `--force` |
|----------|-------------------|----------------|
| Worktree removal | Confirmation required | Skipped |
| Branch deletion (merged) | Confirmation required | Skipped |
| Branch deletion (unmerged) | Warning + confirmation required | Skipped |

### Dry-Run Interaction

`wtdel <branch> -B --dry-run` shows:
- Existing worktree removal preview
- "Would delete branch 'X' (merged)" or "Would delete branch 'X' (has N unmerged commits)"
- No actions taken

### Batch Behavior

When processing multiple worktrees (`hug wtdel feat-a feat-b feat-c -B`):

1. Process each worktree sequentially (existing behavior)
2. After each successful worktree removal, immediately attempt branch deletion
3. Track per-item outcomes:
   - Worktree removed, branch deleted
   - Worktree removed, branch not deleted (user declined / unmerged)
   - Worktree removed, branch not found (detached HEAD)
   - Worktree removal failed (branch untouched)

### Error Handling

- Branch deletion fails (git error) → worktree is already removed, report failure clearly
- Branch checked out elsewhere → skip with warning (shouldn't happen normally)
- Detached HEAD worktree → skip branch deletion silently, no error

### Output Format

**Per-item output** (extends existing format):

Success:
```
Worktree removed for branch 'feature-auth'
Deleted directory: ~/path/to/repo.WT.feature-auth
      ✓ Branch 'feature-auth' deleted
```

Branch deletion declined/failed:
```
Worktree removed for branch 'experiment-1'
Deleted directory: ~/path/to/repo.WT.experiment-1
      ✗ Branch 'experiment-1' not deleted (unmerged, declined)
```

Detached HEAD:
```
Worktree removed for branch '(detached)'
Deleted directory: ~/path/to/repo.WT.experiment-1
```
(No branch deletion line — skipped silently)

**Batch summary** extends to include branch outcomes:
```
Batch Removal Summary:
  Removed: 2
  Branches deleted: 1
  Branches kept: 1
  Failed: 0
```

**Tip behavior:**
- Without `-B`: existing tip "Branch 'X' still exists. To delete it: hug bdel X" (unchanged)
- With `-B`: tip suppressed (branch deletion was handled)

All summary output goes to stderr (consistent with existing `wtdel` stdout/stderr discipline).

### Implementation Approach

- Add flag parsing in `git-wtdel` via `hug-cli-flags`
- After successful worktree removal (line ~357), branch into `--with-branch` logic
- Reuse merge-status check pattern from `git-bdel` (`git branch --merged`)
- Reuse confirmation pattern from `git-bdel` (`prompt_confirm_warn` / `prompt_confirm_danger`)
- No new library functions needed — all logic stays in `git-wtdel`

## Testing

New test cases for `tests/unit/test_worktree_remove.bats`:

### Basic Flag Behavior
- `wtdel <branch> -B` removes worktree + deletes merged branch
- `wtdel <branch> --with-branch` works identically
- `wtdel <branch> -B --dry-run` previews both removals without acting

### Branch States
- Merged branch → deleted after confirmation
- Unmerged branch → prompts with warning, deleted on confirm
- Unmerged branch → prompts with warning, skipped on decline
- Detached HEAD → worktree removed, branch step skipped silently
- Non-existent branch → worktree removed, branch step skipped silently

### Force Interaction
- `wtdel <branch> -B -f` skips all confirmations including unmerged
- `HUG_FORCE=true` with `-B` behaves same as `-f`

### Batch Mode
- Multiple branches with `-B` deletes all associated branches
- Mixed batch: some merged, some unmerged, some detached

### Edge Cases
- Branch deletion fails (git error) → worktree still removed, error reported
- Help text includes `-B` / `--with-branch`
- Tip suppressed when `-B` is active
- Tip shown when `-B` is NOT active (existing behavior preserved)
