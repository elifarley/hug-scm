# HEAD Operations (h *)

HEAD operations in Hug allow you to safely move or undo commits without losing work. Commands are accessed via the main `h` command (for "HEAD") and follow a progressive destructiveness: `back` (safest) to `rewind` (most destructive). Use `hug h files` to preview affected files before any operation.

These commands provide intuitive names and built-in safeguards for moving the branch pointer (HEAD), avoiding the complexity of Git's `reset` modes.

## Quick Reference

| Command | Memory Hook | Summary                                                                           |
| --- | --- |-----------------------------------------------------------------------------------|
| `hug h back [-u] [--force]` | **H**EAD **Back** | HEAD goes back, keeping changes staged                                            |
| `hug h undo [-u] [--force]` | **H**EAD **Undo** | HEAD goes back, keeping changes unstaged                                          |
| `hug h rollback [-u] [--force]` | **H**EAD **R**ollback | HEAD goes back, discarding changes but preserving uncommitted changes             |
| `hug h rewind [-u] [--force]` | **H**EAD **Re**wind | HEAD goes back, discarding ALL changes, including uncommitted ones                |
| `hug h squash [-u] [--force]` | **H**EAD **S**quash | HEAD goes back + commit last N/local/specific commits as 1 with original HEAD msg |
| `hug h files [-u]` | **H**EAD **F**iles | Preview files touched in the selected range (or local-only with -u)               |
| `hug h steps <file>` | **H**EAD **Steps** | Count steps back to find most recent file change (query for rewinds)              |

## Upstream Safety Workflow (`-u` / `--upstream`)
Several HEAD commands (`hug h back`, `hug h rollback`, `hug h undo`, `hug h rewind`, `hug h squash`) share a read-only preview/confirmation helper when you pass `-u`/`--upstream`. It lists the commits above the upstream tip and shows their file change statistics before any reset happens, letting you cancel with zero repository changes. Use `--force` to skip the confirmation. `hug h files -u` uses the same preview data while staying read-only.
> Developer note: the shared helper (`handle_upstream_operation`) inspects history only—it never modifies commits, the index, or the working tree.

## Commands

### `hug h back [N|commit] [-u, --upstream] [--force]`
- **Description**: HEAD goes back by N commits (default: 1) or to a specific commit. Keeps changes from the undone commits staged - non-destructive, ideal for re-committing with adjustments. With `-u`, resets to upstream remote tip (e.g., origin/my-branch), discarding local-only commits (no fetch needed).
- **Example**:
  ```shell
  hug h back                # Undo last commit, keep changes staged
  hug h back 3              # Undo last 3 commits
  hug h back a1b2c3         # HEAD goes back to specific commit
  hug h back -u             # HEAD goes back to upstream tip, keep local changes staged
  hug h back 3 --force      # Skip confirmation
  ```
- **Safety**: Non-destructive; changes remain staged and can be inspected with `hug sl` (**S**tatus + **L**ist uncommitted files) and `hug ss` (**S**tatus + **S**taged diff) or re-committed. Previews commits and their file change statistics and requires y/n confirmation when staged changes are present (skipped with --force or when the staging area is clean); the preview helper is read-only, so no reset happens until you confirm. Cannot mix `-u` with explicit target.

### `hug h undo [N|commit] [-u, --upstream] [--force]`
- **Description**: HEAD goes back by N commits (default: 1) or to a specific commit. Unstages changes from the undone commits but keeps them in your working directory - perfect for editing before re-staging. With `-u`, resets to upstream remote tip, discarding local-only commits.
- **Example**:
  ```shell
  hug h undo                # Undo last commit, unstage changes
  hug h undo 3              # Undo last 3 commits
  hug h undo main           # Undo to main branch
  hug h undo -u             # Undo to upstream tip, keep local changes unstaged
  hug h undo 3 --force      # Skip confirmation
  ```
- **Safety**: Non-destructive; changes remain in working directory and can be viewed with `hug su` (**S**tatus + **U**nstaged diff). Previews commits and their file change statistics and requires y/n confirmation (skipped with --force); the preview helper is read-only, so no reset happens until you confirm. Cannot mix `-u` with explicit target.

### `hug h rollback [N|commit] [-u, --upstream] [--force]`
- **Description**: HEAD goes back by N commits (default: 1) or to a specific commit, discarding commit history and staged changes, but preserving any uncommitted local changes in the working directory. With `-u`, resets to upstream remote tip, discarding local-only commits but keeping uncommitted work.
- **Example**:
  ```shell
  hug h rollback            # Rollback last commit, keep local work
  hug h rollback 2          # Rollback last 2 commits
  hug h rollback a1b2c3     # Rollback to specific commit
  hug h rollback -u         # Rollback to upstream tip, preserve local uncommitted changes
  hug h rollback 2 --force  # Skip confirmation
  ```
- **Safety**: Aborts if it would overwrite uncommitted changes. Previews commits and their file change statistics and requires y/n confirmation (skipped with --force); the preview helper is read-only, so no reset happens until you confirm. Cannot mix `-u` with explicit target. Use `hug h files` first to inspect.

### `hug h rewind [N|commit] [-u, --upstream] [--force]`
- **Description**: HEAD goes back by N commits (default: 1) or to a specific commit, moving to a clean state. Highly destructive! Discards all staged/unstaged changes in tracked files (untracked/ignored files are preserved). With `-u`, resets to upstream remote tip, discarding everything after it.
- **Example**:
  ```shell
  hug h rewind              # Rewind to last commit's clean state
  hug h rewind 3            # Rewind last 3 commits
  hug h rewind origin/main  # Rewind to remote main
  hug h rewind -u           # Rewind to upstream tip
  hug h rewind 3 --force    # Skip confirmation (very dangerous!)
  ```
- **Safety**: Previews commits and their file change statistics to be discarded, requires typing "rewind" to confirm (skipped with --force). The preview helper is read-only; nothing changes until you confirm. Untracked files are safe. Cannot mix `-u` with explicit target.

### `hug h squash [N|commit] [-u, --upstream] [--force]`
- **Description**: Moves HEAD back by N commits (default: 2) or to a specific commit (like `h back`), then immediately commits the staged changes as one new commit, combining all commit messages.
Changes from all squashed commits are kept staged so that they can be committed in sequence. With `-u`, squashes local-only commits onto the upstream tip. Non-destructive to uncommitted working directory changes.
- **Example**:
  ```shell
  hug h squash               # Squash last 2 commits into 1
  hug h squash 3             # Squash last 3 commits into 1
  hug h squash a1b2c3        # Keep a1b2c3 unchanged; Squash all commits above it into 1
  hug h squash -u            # Keep upstream tip unchanged; Squash local-only commits on top
  hug h squash 3 --force     # Skip confirmation
  ```
- **Safety**: Previews commits and their file change statistics affected and requires y/n confirmation (skipped with --force). The shared preview helper is read-only; the squash only runs after you confirm. Aborts if no upstream set for `-u` or invalid target. If no staged changes after reset, skips commit and warns. Cannot mix `-u` with explicit target.
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
- **Safety**: Read-only; no changes to repo. Upstream mode uses the shared preview data but remains read-only. Cannot mix `-u` with explicit target.

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
- Sync to remote after local dev: `hug h squash -u` (all local-only commits squashed into 1), `hug h undo -u` (unstaged) etc.
- For quick squashing: `hug h squash N` (HEAD goes back + auto-commit with top-most message).
- Use `--force` for non-interactive scripting (skips confirmations but prints other messages; combine with `--quiet` for minimal output).
- Use [`hug sl` or `hug sw` (**S**tatus + **W**orking directory diff)](status-staging.md#quick-reference) to check status after any HEAD movement.
- For interactive history editing (edit/squash multiple commits), see [Rebase Commands](rebase.md).
- Aliases like `hug back` are available as shortcuts for `hug h back`.

Pair with [Working Directory](working-dir.md) for cleanup/restore, or [Logging](logging.md) to inspect history before resetting.
