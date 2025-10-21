# HEAD Operations (h *)

HEAD operations in Hug allow you to safely move or undo commits without losing work. Commands are accessed via the main `h` command (for "HEAD") and follow a progressive destructiveness: `back` (safest) to `rewind` (most destructive). Use `hug h files` to preview affected files before any operation.

These map to Git's `reset` modes but with intuitive names and built-in safeguards where applicable (e.g., confirmations for destructive actions).

## Quick Reference

| Command | Memory Hook | Summary                                                                           |
| --- | --- |-----------------------------------------------------------------------------------|
| `hug h back [-u]` | **H**EAD **Back** | HEAD goes back, keeping changes staged                                            |
| `hug h undo [-u]` | **H**EAD **Undo** | HEAD goes back, keeping changes unstaged                                          |
| `hug h rollback [-u]` | **H**EAD **R**ollback | HEAD goes back, discarding changes but preserving uncommitted changes             |
| `hug h rewind [-u]` | **H**EAD **Re**wind | HEAD goes back, discarding ALL changes, including uncommitted ones                |
| `hug h squash [-u]` | **H**EAD **S**quash | HEAD goes back + commit last N/local/specific commits as 1 with original HEAD msg |
| `hug h files [-u]` | **H**EAD **F**iles | Preview files touched in the selected range (or local-only with -u)               |
| `hug h steps <file>` | **H**EAD **Steps** | Count steps back to find most recent file change (query for rewinds)              |

## Commands

### `hug h back [N|commit] [-u, --upstream]`
- **Description**: HEAD goes back by N commits (default: 1) or to a specific commit. Keeps changes from the undone commits staged - non-destructive, ideal for re-committing with adjustments. With `-u`, resets to upstream remote tip (e.g., origin/my-branch), discarding local-only commits (no fetch needed).
- **Example**:
  ```shell
  hug h back                # Undo last commit, keep changes staged
  hug h back 3              # Undo last 3 commits
  hug h back a1b2c3         # HEAD goes back to specific commit
  hug h back -u             # HEAD goes back to upstream tip, keep local changes staged
  ```
- **Safety**: Non-destructive; changes remain staged and can be inspected with `hug sl` (**S**tatus + **L**ist uncommitted files) and `hug ss` (**S**tatus + **S**taged diff) or re-committed. Previews commits/files and requires y/n confirmation for `-u`. Cannot mix `-u` with explicit target.

### `hug h undo [N|commit] [-u, --upstream]`
- **Description**: HEAD goes back by N commits (default: 1) or to a specific commit. Unstages changes from the undone commits but keeps them in your working directory - perfect for editing before re-staging. With `-u`, resets to upstream remote tip, discarding local-only commits.
- **Example**:
  ```shell
  hug h undo                # Undo last commit, unstage changes
  hug h undo 3              # Undo last 3 commits
  hug h undo main           # Undo to main branch
  hug h undo -u             # Undo to upstream tip, keep local changes unstaged
  ```
- **Safety**: Non-destructive; changes remain in working directory and can be viewed with `hug su` (**S**tatus + **U**nstaged diff). Previews commits/files and requires y/n confirmation for `-u`. Cannot mix `-u` with explicit target.

### `hug h rollback [N|commit] [-u, --upstream]`
- **Description**: HEAD goes back by N commits (default: 1) or to a specific commit, discarding commit history and staged changes, but preserving any uncommitted local changes in the working directory. With `-u`, resets to upstream remote tip, discarding local-only commits but keeping uncommitted work.
- **Example**:
  ```shell
  hug h rollback            # Rollback last commit, keep local work
  hug h rollback 2          # Rollback last 2 commits
  hug h rollback a1b2c3     # Rollback to specific commit
  hug h rollback -u         # Rollback to upstream tip, preserve local uncommitted changes
  ```
- **Safety**: Aborts if it would overwrite uncommitted changes. Previews commits/files and requires y/n confirmation for `-u`. Cannot mix `-u` with explicit target. Use `hug h files` first to inspect.

### `hug h rewind [N|commit] [-u, --upstream]`
- **Description**: HEAD goes back by N commits (default: 1) or to a specific commit, moving to a clean state. Highly destructive! Discards all staged/unstaged changes in tracked files (untracked/ignored files are preserved). With `-u`, resets to upstream remote tip, discarding everything after it.
- **Example**:
  ```shell
  hug h rewind              # Rewind to last commit's clean state
  hug h rewind 3            # Rewind last 3 commits
  hug h rewind origin/main  # Rewind to remote main
  hug h rewind -u           # Rewind to upstream tip
  ```
- **Safety**: Previews commits to be discarded, requires typing "rewind" to confirm (or "rewind" for `-u`). Untracked files are safe, but always backup with `hug w backup` first. Cannot mix `-u` with explicit target.

### `hug h squash [N|commit] [-u, --upstream]`
- **Description**: Moves HEAD back by N commits (default: 2) or to a specific commit (like `h back`), then immediately commits the staged changes as one new commit using the same message from the original HEAD (before the movement). Squashes the changes from the undone commits into this single commit. With `-u`, squashes local-only commits onto the upstream tip. Non-destructive to uncommitted working directory changes.
- **Example**:
  ```shell
  hug h squash               # Squash last 2 commits into 1
  hug h squash 3             # Squash last 3 commits into 1
  hug h squash a1b2c3        # Keep a1b2c3 unchanged; Squash all commits above it into 1
  hug h squash -u            # Keep upstream tip unchanged; Squash local-only commits on top
  ```
- **Safety**: Previews commits/files affected and requires y/n confirmation. Aborts if no upstream set for `-u` or invalid target. If no staged changes after reset, skips commit and warns. Cannot mix `-u` with explicit target.
- Pre-existing staged changes will be included - review with `hug ss` first.

### `hug h files [N|commit] [options]`
- **Description**: Preview unique files touched by commits in the specified range (default: last 1 commit). With `-u`, previews files in local-only commits (HEAD to upstream tip). Useful before back, undo, rollback, or rewind to understand impact.
- **Example**:
  ```shell
  hug h files                # Files in last commit
  hug h files 3              # Files in last 3 commits
  hug h files main           # Files changed since main
  hug h files -u             # Files in local-only commits to upstream
  hug h files --stat         # With line change stats
  ```
- **Safety**: Read-only; no changes to repo. Cannot mix `-u` with explicit target.

### `hug h steps <file> [--raw]`
- **Description**: Calculate how many commit steps from HEAD back to the most recent commit touching `file` (handles renames). Outputs the count; use for precise rewinds like `h back N`. Full mode shows formatted commit info via `hug ll`.
- **Example**:
  ```shell
  hug h steps src/app.js          # "3 steps back from HEAD (last commit abc123); <ll output>"
  hug h steps README.md --raw     # "3" (just the number)
  hug h steps file.txt | xargs hug h back  # Rewind exactly to last change
  ```
- **Safety**: Read-only query; errors if file has no history. If 0 steps, confirms last change is in HEAD.

## Tips
- Preview impact with `hug h files` (or `hug h files -u` for local-only) before any HEAD movement (e.g., `hug h files 2` then `hug h back 2`).
- Sync to remote after local dev: `hug h back -u` (soft, keeps staged) or `hug h undo -u` (unstaged). Use `git fetch` first if remote may have advanced.
- For quick squashing: `hug h squash N` (HEAD goes back + auto-commit with original message).
- Always run `hug w backup` before destructive ops like `rollback` or `rewind`.
- Use `hug s` or `hug sw` (**S**tatus + **W**orking directory diff) to check status after any HEAD movement.
- For interactive rebase (edit/squash multiple commits), see [Rebase Commands](commits#rebase).
- Aliases like `hug back` are available as shortcuts for `hug h back`.

Pair with [Working Directory](working-dir) for cleanup/restore, or [Logging](logging) to inspect history before resetting.
