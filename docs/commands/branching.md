# Branching (b*)

Branching commands in Hug simplify managing local and remote branches. Prefixed with `b` for "branch", they provide intuitive ways to list, switch, create, delete, and query branches with safety checks and clear output.

These commands are implemented as Git aliases and scripts in the Hug tool suite, wrapping Git's branch operations for better usability, including interactive selection, color highlighting, and formatted views.

## Listing Branches

### `hug b [branch]`
- **Description**: Switch (checkout) to an existing local branch. If no branch is specified, shows an interactive menu of local branches for selection.
- **Example**:
  ```
  hug b main                 # Switch to main branch
  hug b                      # Interactive menu to select branch
  hug b feature/new-ui       # Switch to feature branch
  ```
- **Safety**: Interactive mode prevents accidental switches. Always checks if you're in a Git repo.
- **Git Equivalent**: `git switch <branch>`

### `hug bl`
- **Description**: List local branches in short format, sorted alphabetically. The current branch is marked with an asterisk (*).
- **Example**:
  ```
  hug bl    # List all local branches
  ```
- **Safety**: Read-only operation; no changes to repo state.
- **Git Equivalent**: `git branch`

### `hug bla`
- **Description**: List all branches (local and remote) in short format.
- **Example**:
  ```
  hug bla   # List all branches including remotes
  ```
- **Safety**: Read-only.
- **Git Equivalent**: `git branch -a`

### `hug blr`
- **Description**: List remote branches only in short format.
- **Example**:
  ```
  hug blr   # List remote branches
  ```
- **Safety**: Read-only.
- **Git Equivalent**: `git branch -r`

### `hug bll`
- **Description**: List local branches in long format with details: short commit hash, upstream tracking info (e.g., ahead/behind counts), and the latest commit message title. Current branch is highlighted in green and marked with *. Branches are left-aligned for readability.
- **Example**:
  ```
  hug bll   # Detailed local branch listing
  ```
- **Safety**: Read-only; displays tracking info like `git branch -vv` but with commit subjects.
- **Git Equivalent**: Enhanced `git branch -vv`

## Branch Creation / Modification

### `hug bc <branch-name>`
- **Description**: Create a new branch and switch to it.
- **Example**:
  ```
  hug bc new-feature    # Create and switch to new-feature
  ```
- **Safety**: Non-destructive; creates from current HEAD.
- **Git Equivalent**: `git switch -c <branch>`

### `hug br <new-name>`
- **Description**: Rename the current branch to a new name.
- **Example**:
  ```
  hug br updated-feature  # Rename current branch
  ```
- **Safety**: Prompts for confirmation if the new name exists.
- **Git Equivalent**: `git branch -m <new-name>`

## Branch Deletion

### `hug bdel <branch>`
- **Description**: Safely delete a local branch (only if fully merged into current branch).
- **Example**:
  ```
  hug bdel old-feature    # Safe delete if merged
  ```
- **Safety**: Fails if unmerged; requires confirmation.
- **Git Equivalent**: `git branch -d <branch>`

### `hug bdelf <branch>`
- **Description**: Force-delete a local branch, even if unmerged.
- **Example**:
  ```
  hug bdelf risky-branch  # Force delete unmerged branch
  ```
- **Safety**: Double-prompts for confirmation to prevent accidents.
- **Git Equivalent**: `git branch -D <branch>`

### `hug bdelr <branch>`
- **Description**: Delete a remote branch (pushes delete to origin).
- **Example**:
  ```
  hug bdelr origin/old-remote  # Delete remote branch
  ```
- **Safety**: Prompts for confirmation; assumes 'origin' remote.
- **Git Equivalent**: `git push origin --delete <branch>`

## Branch Queries (bw*)

These commands help inspect which branches relate to specific commits or states.

### `hug bwc [<commit>]`
- **Description**: Show branches that contain a specific commit (in their history). Defaults to HEAD.
- **Example**:
  ```
  hug bwc a1b2c3    # Branches containing commit a1b2c3
  hug bwc           # Branches containing HEAD
  ```
- **Safety**: Read-only.
- **Git Equivalent**: `git branch --contains <commit>`

### `hug bwp [<object>]`
- **Description**: Show branches that point exactly at a specific object (e.g., commit). Defaults to HEAD.
- **Example**:
  ```
  hug bwp HEAD       # Branches pointing at HEAD
  ```
- **Safety**: Read-only.
- **Git Equivalent**: `git branch --points-at <object>`

### `hug bwnc [<commit>]`
- **Description**: Show branches that do NOT contain a specific commit. Defaults to HEAD.
- **Example**:
  ```
  hug bwnc HEAD      # Branches not containing HEAD
  ```
- **Safety**: Read-only.
- **Git Equivalent**: `git branch --no-contains <commit>`

### `hug bwm [<commit>]`
- **Description**: Show branches merged into a specific commit (defaults to HEAD).
- **Example**:
  ```
  hug bwm            # Branches merged into HEAD
  ```
- **Safety**: Read-only.
- **Git Equivalent**: `git branch --merged <commit>`

### `hug bwnm [<commit>]`
- **Description**: Show branches NOT merged into a specific commit (defaults to HEAD).
- **Example**:
  ```
  hug bwnm           # Branches not merged into HEAD
  ```
- **Safety**: Read-only.
- **Git Equivalent**: `git branch --no-merged <commit>`

## Tips
- Use `hug b` to review branch status and easily switch via an interactive menu.
- For creating a branch from an existing one: `hug bc <new> <existing>` (e.g., `hug bc new-feature existing-feature`).
- Always backup work with `hug w backup` before deleting branches.
- Queries like `bwc` and `bwm` are useful for cleanup before `bdel`.

See [Status & Staging](/commands/status-staging) for checking changes after branching operations.
