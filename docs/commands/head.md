# HEAD Operations (h*)

HEAD operations in Hug allow you to safely move or undo commits without losing work. Commands are prefixed with `h` for "HEAD" and follow a progressive destructiveness: `back` (safest) to `rewind` (most destructive). Use `hug h files` to preview affected files before any operation.

These map to Git's `reset` modes but with intuitive names and built-in safeguards where applicable (e.g., confirmations for destructive actions).

## Commands

### `hug h back [N|commit]`
- **Description**: Soft reset HEAD back by N commits (default: 1) or to a specific commit. Keeps changes from the undone commits staged—non-destructive, ideal for re-committing with adjustments.
- **Usage**:
  ```
  hug h back                # Undo last commit, keep changes staged
  hug h back 3              # Undo last 3 commits
  hug h back a1b2c3         # Reset to specific commit
  ```
- **Safety**: Non-destructive; changes remain staged and can be inspected with `hug sl` (**S**tatus + **L**ist uncommitted files) and `hug ss` (**S**tatus + **S**taged diff) or re-committed. No confirmation prompt.

### `hug h undo [N|commit]`
- **Description**: Mixed reset back by N commits (default: 1) or to a specific commit. Unstages changes from the undone commits but keeps them in your working directory—perfect for editing before re-staging.
- **Usage**:
  ```
  hug h undo                # Undo last commit, unstage changes
  hug h undo 3              # Undo last 3 commits
  hug h undo main           # Undo to main branch
  ```
- **Safety**: Non-destructive; changes remain in working directory and can be viewed with `hug su` (**S**tatus + **U**nstaged diff). No confirmation prompt.
- **Git Equivalent**: `git reset --mixed [commit]` (or `git reset [commit]` for short)

### `hug h rollback [N|commit]`
- **Description**: Hard reset back by N commits (default: 1) or to a specific commit, discarding commit history and staged changes, but preserving any uncommitted local changes in the working directory.
- **Usage**:
  ```
  hug h rollback            # Rollback last commit, keep local work
  hug h rollback 2          # Rollback last 2 commits
  hug h rollback a1b2c3     # Rollback to specific commit
  ```
- **Safety**: Aborts if it would overwrite uncommitted changes. No built-in preview or confirmation in current implementation - use `hug h files` first to inspect.

### `hug h rewind [N|commit]`
- **Description**: Full hard reset by N commits (default: 1) or to a specific commit, moving to a clean state. Highly destructive! Discards all staged/unstaged changes in tracked files (untracked/ignored files are preserved).
- **Usage**:
  ```
  hug h rewind              # Rewind to last commit's clean state
  hug h rewind 3            # Rewind last 3 commits
  hug h rewind origin/main  # Rewind to remote main
  ```
- **Safety**: Previews commits to be discarded, requires typing "rewind" to confirm. Untracked files are safe, but always backup with `hug w backup` first.

### `hug h files [N|commit] [options]`
- **Description**: Preview unique files touched by commits in the specified range (default: last 1 commit). Useful before back, undo, rollback, or rewind to understand impact.
- **Usage**:
  ```
  hug h files                # Files in last commit
  hug h files 3              # Files in last 3 commits
  hug h files main           # Files changed since main
  hug h files --stat         # With line change stats
  ```
- **Safety**: Read-only; no changes to repo.

## Tips
- Preview impact with `hug h files` before any HEAD movement (e.g., `hug h files 2` then `hug h back 2`).
- Always run `hug w backup` before destructive ops like `rollback` or `rewind`.
- Use `hug s` or `hug sw` (**S**tatus + **W**orking directory diff) to check status after any HEAD movement.
- For interactive rebase (edit/squash multiple commits), see [Rebase Commands](/commands/commits#rebase).
- Aliases like `hug back` are available as shortcuts for `hug h back`.

Pair with [Working Directory](/commands/working-dir) for cleanup/restore, or [Logging](/commands/logging) to inspect history before resetting.
