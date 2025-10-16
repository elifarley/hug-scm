# Working Directory (w*)

Working Directory commands in Hug help you manage, clean up, and restore changes in your local files. Prefixed with `w` for "working directory," they range from safe discards to nuclear cleanups, always with previews.

These build on Git's `reset`, `stash`, and `clean` but add intuitive names and safety layers.

## Commands

### Discard Changes
Discard specific or all changes without affecting untracked files.

- `hug w discard [-u|-s] <files...>`
  - **Description**: Discard unstaged (`-u`, default) or staged (`-s`) changes for specific files/paths.
  - **Usage**:
    ```
    hug w discard file.js     # Discard unstaged changes in file.js
    hug w discard -s .        # Discard all staged changes
    ```
  - **Safety**: `--dry-run` to preview; requires `-f` to force.

- `hug w discard-all [-u|-s]`
  - **Description**: Repo-wide discard of unstaged or staged changes.
  - **Example**: `hug w discard-all -u` (default unstaged).

### Wipe Changes
Reset both staged and unstaged changes to the last commit state.

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
  - **Description**: Complete repo reset—tracked to clean, untracked/ignored removed.
  - **Safety**: Always previews and confirms; use with caution.

### Utilities
- `hug w backup [-m "msg"]`
  - **Description**: Safe stash of all changes (tracked + untracked).
  - **Example**: `hug w backup -m "WIP before refactor"`

- `hug w get <commit> [files...]`
  - **Description**: Restore files from a specific commit to working directory.
  - **Example**: `hug w get HEAD~2 README.md` (gets from 2 commits ago)

- `hug w changes` (or `hug sx`)
  - **Description**: Quick summary of working directory changes.

## Tips
- Chain with status: `hug w discard file.js && hug sl`
- Restore from stash: Use [Stash Commands](/commands/status-staging#s*) like `hug sapply`.
- For undoing HEAD moves that affect working dir, see [HEAD Operations](/commands/head).

Backup first with `hug w backup`!
