# Working Directory (w*)

Working Directory commands in Hug help you manage, clean up, and restore changes in your local files. Prefixed with `w` for "working directory," they range from safe discards to nuclear cleanups, always with previews.

These build on Git's `reset`, `stash`, and `clean` but add intuitive names and safety layers.

## Quick Reference

| Command | Memory Hook                             | Summary                                                  |
| --- |-----------------------------------------|----------------------------------------------------------|
| `hug w discard` | **W**orking directory **D**iscard       | Discard unstaged or staged changes for paths             |
| `hug w discard-all` | **W**orking directory **discard **ALL** | Discard unstaged or staged changes across the repository |
| `hug w wipe` | **W**orking directory **W**ipe          | Discard uncommitted changes for paths                       |
| `hug w wipe-all` | **W**orking directory **W**ipe **ALL**  | Drop uncommitted changes in entire repo                  |
| `hug w purge` | **W**orking directory **P**urge         | Remove untracked or ignored files for paths              |
| `hug w purge-all` | **W**orking directory **P**urge **ALL** | Repo-wide purge of untracked/ignored files               |
| `hug w zap` | **W**orking directory **Z**ap           | Combine wipe + purge for paths                           |
| `hug w zap-all` | **W**orking directory **Z**ap **ALL**   | Full repo cleanup of tracked and untracked files         |
| `hug w wip` | **W**ork **I**n **P**rogress            | Park changes on dated WIP branch (pushable)              |
| `hug w unwip` | **Un**park **W**ork **I**n **P**rogress | Squash-merge WIP to current + delete                     |
| `hug w wipdel` | **W**ork **I**n **P**rogress **DEL**ete | Delete WIP branch (no integration)                       |
| `hug w backup` | **W**orking directory **B**ackup        | Stash tracked and untracked changes safely               |
| `hug w get` | **W**orking directory **G**et           | Restore files from a specific commit                     |

## Commands

### Discard Changes
Discard unstaged or staged changes without affecting untracked files.

- `hug w discard [-u|-s] <files...>`
  - **Description**: Discard unstaged (`-u`, default) or staged (`-s`) changes for specific files/paths.
  - **Example**:
    ```shell
    hug w discard file.js     # Discard unstaged changes in file.js
    hug w discard -s .        # Discard all staged changes
    ```
  - **Safety**: `--dry-run` to preview; requires `-f` to force.

- `hug w discard-all [-u|-s]`
  - **Description**: Repo-wide discard of unstaged or staged changes.
  - **Example**: `hug w discard-all -u` (default unstaged).

### Wipe Changes
Drop uncommitted changes (both staged and unstaged).

- `hug w wipe <files...>`
  - **Description**: Wipe staged + unstaged for specific files (tracked only).
  - **Example**: `hug w wipe src/*.js`

- `hug w wipe-all`
  - **Description**: Wipe all tracked files to clean state.
  - **Safety**: Confirmation required; `--dry-run` available.

### Purge Untracked
Remove untracked or ignored files (e.g., build artifacts).

- `hug w purge [-u|-i] <paths...>`
  - **Description**: Purge untracked (`-u`, default) or ignored (`-i`) files/paths.
  - **Example**: `hug w purge -i node_modules/`

- `hug w purge-all [-u|-i]`
  - **Description**: Repo-wide purge.
  - **Safety**: `--dry-run`; `-f` to skip prompts.

### Zap (Nuclear Cleanup)
Combines wipe + purge for full reset.

- `hug w zap <paths...>`
  - **Description**: Full cleanup (discard + purge) for paths.
  - **Example**: `hug w zap my-file` (careful!)

- `hug w zap-all`
  - **Description**: Complete repo reset - tracked to clean, untracked/ignored removed.
  - **Safety**: Always previews and confirms; use with caution.

### Utilities
- `hug w wip "<msg>"`
  - **Description**: Park all changes (staged/unstaged/untracked) on a new dated branch like `WIP/YY-MM-DD/HHmm.slug` with `[WIP] <msg>` commit, then switch back. Preferred over stashing for pushable, persistent saves of temp work.
  - **Example**: `hug w wip "Draft feature"` → Resume: `hug b WIP/24-10-05/1430.draftfeature`; finish: `hug w unwip WIP/24-10-05/1430.draftfeature` (squash-merges to current and deletes).

- `hug w unwip [WIP_BRANCH]`
  - **Description**: Unpark by squash-merging WIP changes into the current branch as one commit, then deleting the WIP branch. Interactive if no branch specified (requires fzf).
  - **Example**: `hug w unwip` (prompts to select); `--no-squash` for regular merge.
  - **Safety**: Previews changes; aborts on conflicts (resolve manually).

- `hug w wipdel [WIP_BRANCH]`
  - **Description**: Delete a WIP branch without integrating (for worthless/abandoned work). Safe if merged; `-f` to force.
  - **Example**: `hug w wipdel WIP/24-10-05/1430.draftfeature`
  - **Safety**: Prompts if unmerged.

- `hug w backup [-m "msg"]`
  - **Description**: Safe stash of all changes (tracked + untracked). Use for quick local backups; prefer `w wip` for longer workflows.
  - **Example**: `hug w backup -m "WIP before refactor"`

- `hug w get <commit> [files...]`
  - **Description**: Restore files from a specific commit to working directory.
  - **Example**: `hug w get HEAD~2 README.md` (gets from 2 commits ago)

## Tips
- Chain with status: `hug w discard file.js && hug sl`
- Restore from stash: Use [Stash Commands](status-staging#s*) like `hug sapply`.
- For undoing HEAD moves that affect working dir, see [HEAD Operations](head).
- For WIP: Park with `hug w wip`, resume with `hug b <wip>`, finish with `hug w unwip` or discard with `hug w wipdel`.

Backup first with `hug w backup`!
