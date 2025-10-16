# Status & Staging (s*, a*)

Status and staging commands in Hug provide clear views of your repo state and easy ways to stage/unstage changes. Prefixed with `s` for "status" and `a` for "add/stage."

These enhance Git's `status` and `add` with colored summaries, patches, and smart defaults.

## Status Commands (s*)

### Basic Status
- `hug s`
  - **Description**: Quick colored summary of staged/unstaged changes (no untracked files).
  - **Usage**: `hug s` (always safe, no args).

- `hug sl`
  - **Description**: Status without untracked files (Git-like).
  - **Usage**: `hug sl`

- `hug sla`
  - **Description**: Full status including untracked files.
  - **Usage**: `hug sla`

- `hug sli`
  - **Description**: Status + list of ignored/untracked files.
  - **Usage**: `hug sli`

### Detailed Patches
Show diffs inline for better inspection.

- `hug ss [file]`
  - **Description**: Status + staged changes patch (for file or all).
  - **Usage**: `hug ss src/app.js`

- `hug su [file]`
  - **Description**: Status + unstaged changes patch.
  - **Usage**: `hug su`

- `hug sw [file]`
  - **Description**: Status + working directory patch (staged + unstaged).
  - **Usage**: `hug sw .`

- `hug sx` (or `hug w changes`)
  - **Description**: Working tree summary (unstaged focus). Options: `--no-color`.
  - **Usage**: `hug sx`

## Staging Commands (a*)

- `hug a [files...]`
  - **Description**: Stage tracked changes (or specific files if provided). If no args, stages updates only.
  - **Usage**:
    ```
    hug a                     # Stage all tracked updates
    hug a src/                # Stage directory
    ```

- `hug aa`
  - **Description**: Stage everything (tracked + untracked + deletions).
  - **Usage**: `hug aa` (use carefully).

- `hug ai`
  - **Description**: Interactive add menu (Git's `-i`).
  - **Usage**: `hug ai`

- `hug ap`
  - **Description**: Interactive patch staging (hunk-by-hunk).
  - **Usage**: `hug ap`

## Unstaging
- `hug us <files...>`
  - **Description**: Unstage specific files.
  - **Usage**: `hug us file.js`

- `hug usa`
  - **Description**: Unstage all files.
  - **Usage**: `hug usa`

- `hug untrack <files...>`
  - **Description**: Stop tracking files but keep them locally (e.g., for secrets).
  - **Usage**: `hug untrack .env`

## Stash Commands (s* overlap)
Stashing is part of status workflow for temporary backups.

- `hug ssave`
  - **Description**: Quick stash of tracked files.

- `hug ssavea "msg"`
  - **Description**: Stash with message + untracked files.

- `hug ssavefull`
  - **Description**: Stash everything including ignored.

- `hug sls`
  - **Description**: List stashes.

- `hug speek [stash]`
  - **Description**: Preview stash diff.

- `hug sshow [stash]`
  - **Description**: Stash summary.

- `hug sapply [stash]`
  - **Description**: Apply stash (keep it).

- `hug spop [stash]`
  - **Description**: Pop stash (interactive preview).

- `hug sdrop [stash]`
  - **Description**: Drop stash.

- `hug sbranch <branch> [stash]`
  - **Description**: Create branch from stash.

- `hug sclear`
  - **Description**: Clear all stashes (caution!).

## Tips
- Pipe status to pager: `hug s | less`
- Interactive staging pairs well with `hug cii` for commit.
- For file inspection (blame, history), see [Logging](/commands/logging#file-inspection).

Use `hug s` frequently to stay oriented!
