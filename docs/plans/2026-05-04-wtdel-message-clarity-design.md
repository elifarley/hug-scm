# wtdel: Make Folder Deletion Visible in Success Messages

**Date:** 2026-05-04
**Status:** Approved

## Problem

`hug wtdel` deletes the worktree folder (via `git worktree remove` + `rm -rf` fallback), but the success message — `"Worktree removed for 'branch'"` — doesn't mention the folder at all. Users may wonder whether the directory was actually deleted.

## Design

Add a separate `info` line after each success message showing the deleted directory path. Also prepend the word `branch` before branch names in success messages for clarity.

### Changes to `git-config/bin/git-wtdel`

**Normal success path** (after `git worktree remove` succeeds):

```bash
# Before:
success "Worktree removed for '$wt_branch'"

# After:
success "Worktree removed for branch '$wt_branch'"
info "Deleted directory: ${worktree_path/#$HOME/\~}"
```

**Fallback success path** (when `git worktree remove` fails, manual cleanup succeeds):

```bash
# Before:
success "Worktree removed for '$wt_branch' (manual cleanup)"

# After:
success "Worktree removed for branch '$wt_branch' (manual cleanup)"
info "Deleted directory: ${worktree_path/#$HOME/\~}"
```

### What stays the same

- Dry-run output (already shows path)
- Stale worktree prune messages (already show path)
- Batch summary (shows counts only, individual items show paths)
- Post-removal tip (`Branch 'X' still exists. To delete it: hug bdel X`)

### Example output

```
✓ Worktree removed for branch 'feature-x'
  Deleted directory: ~/projects/feature-x
💡 Branch 'feature-x' still exists. To delete it: hug bdel feature-x
```

## Scope

This is a message-only change. No behavioral or logic changes.

## Tasks

1. Update success message and add info line in normal path (line ~357)
2. Update success message and add info line in fallback path (line ~337)
3. Update tests to match new message format
