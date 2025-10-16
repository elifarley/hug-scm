# Status & Staging (s*, a*)

Status and staging commands in Hug provide clear views of your repo state and easy ways to stage/unstage changes. Prefixed with `s` for "status" and `a` for "add/stage."

These enhance Git's `status` and `add` with colored summaries, patches, and smart defaults.

## Status Commands (s*)

### Basic Status
- `hug s`: **S**tatus 
  - **Description**: Quick colored summary of staged/unstaged changes (no untracked files).
  - **Example**: `hug s` (always safe, no args).

- `hug sl`: **S**tatus + **L**ist of uncommitted files)
  - **Description**: Status without untracked files (Git-like).
  - **Example**: `hug sl`

- `hug sla`: **S**tatus + **L**ist of **A**ll uncommitted files)
  - **Description**: Full status including **untracked** files.
  - **Example**: `hug sla`

- `hug sli`: **S**tatus + **L**ist of **I**gnored / untracked files)
  - **Description**: Status + list of ignored / untracked files.
  - **Example**: `hug sli`

### Detailed Patches
Show diffs inline for better inspection.

- `hug ss [file]`: **S**tatus + **S**taged diff
  - **Description**: Status + staged changes patch (for a file or all files).
  - **Example**: `hug ss src/app.js`

- `hug su [file]`: **S**tatus + **U**nstaged diff
  - **Description**: Status + unstaged changes patch.
  - **Example**: `hug su`

- `hug sw [file]`: **S**tatus + **W**orking directory diff
  - **Description**: Status + working directory patch (staged + unstaged).
  - **Example**: `hug sw .`

- `hug sx`
  - **Description**: Working tree summary (unstaged focus). Options: `--no-color`.
  - **Example**: `hug sx`

## Staging Commands (a*)

- `hug a [files...]`: **A**dd
  - **Description**: Stage tracked changes (or specific files if provided). If no args, stages updates only.
  - **Example**:
    ```
    hug a                     # Stage all tracked updates
    hug a src/                # Stage directory, including non-tracked files
    ```

- `hug aa`: **A**dd **A**ll
  - **Description**: Stage everything (tracked + untracked + deletions).
  - **Example**: `hug aa` (use carefully).

- `hug ai`: *A**dd **I**nteractive
  - **Description**: Interactive add menu (Git's `-i`).
  - **Example**: `hug ai`

- `hug ap`: **A**dd **P**atch by patch
  - **Description**: Interactive patch staging (hunk-by-hunk).
  - **Example**: `hug ap`

## Unstaging
- `hug us <files...>`: **U**n**S**tage
  - **Description**: Unstage specific files.
  - **Example**: `hug us file.js`

- `hug usa`: **U**n**S**tage **A**ll
  - **Description**: Unstage all files.
  - **Example**: `hug usa`

- `hug untrack <files...>`
  - **Description**: Stop tracking files but keep them locally (e.g., for secrets).
  - **Example**: `hug untrack .env`

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
- Pipe status to pager: `hug sl | less`
- Interactive staging pairs well with `hug cii` for commit.
- For file inspection (blame, history), see [Logging](/commands/logging#file-inspection).

Use `hug s` or `hug sl` frequently to stay oriented!
