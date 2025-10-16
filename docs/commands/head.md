# HEAD Operations (h*)

HEAD operations in Hug allow you to safely move or undo commits without losing work. Commands are prefixed with `h` for "HEAD" and follow a progressive destructiveness: `back` (safest) to `rewind` (most destructive).

These map to Git's `reset` modes but with intuitive names, previews, and safeguards.

## Commands

### `hug h back [N|commit]`
- **Description**: Soft reset HEAD back by N commits (default: 1) or to a specific commit. Keeps changes staged—non-destructive for undoing commits while preserving staged work.
- **Usage**:
  ```
  hug h back                # Undo last commit, keep changes staged
  hug h back 3              # Undo last 3 commits
  hug h back a1b2c3         # Reset to specific commit
  ```
- **Safety**: Shows preview of changes before applying. Use `--dry-run` if available in future updates.
- **Git Equivalent**: `git reset --soft [commit]`

### `hug h undo [N|commit]`
- **Description**: Mixed reset back by N commits or to a commit. Unstages changes but keeps them in your working directory—ideal for reworking recent commits.
- **Usage**:
  ```
  hug h undo                # Undo last commit, unstage changes
  hug h undo main           # Undo to main branch
  ```
- **Safety**: Previews unstaged changes. Non-destructive to local files.
- **Git Equivalent**: `git reset --mixed [commit]`

### `hug h rollback [N|commit]`
- **Description**: Hard reset back but preserves uncommitted local changes. Discards commit history and staged changes, but keeps working directory intact.
- **Usage**:
  ```
  hug h rollback 2          # Rollback last 2 commits, keep local work
  ```
- **Safety**: Requires confirmation; shows what will be lost.
- **Git Equivalent**: `git reset --keep [commit]`

### `hug h rewind [N|commit]`
- **Description**: Full hard reset to a clean state at N commits back or a specific commit. Destructive—discards all staged/unstaged changes in tracked files (untracked files are kept).
- **Usage**:
  ```
  hug h rewind              # Rewind to last commit's clean state
  hug h rewind origin/main  # Rewind to remote main
  ```
- **Safety**: Always prompts for confirmation and shows a dry-run preview.
- **Git Equivalent**: `git reset --hard [commit]`

## Tips
- Always run `hug w backup` before destructive ops like `rewind`.
- Use `hug s` to check status after any HEAD movement.
- For interactive rebase (edit multiple commits), see [Rebase Commands](/commands/commits#rebase).

See [Working Directory Commands](/commands/working-dir) for restoring lost changes.
