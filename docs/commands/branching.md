# Branching (b*)

Branching commands in Hug simplify managing local and remote branches. Prefixed with `b` for "branch", they provide intuitive ways to list, switch, create, delete, and query branches with safety checks and clear output.

These commands are implemented as Git aliases and scripts in the Hug tool suite, wrapping Git's branch operations for better usability, including interactive selection, color highlighting, and formatted views.

## Quick Reference

| Command | Memory Hook | Summary |
| --- | --- | --- |
| `hug b` | **B**ranch checkout | Switch to an existing branch or pick interactively |
| `hug bl` | **B**ranch **L**ist | List local branches |
| `hug bla` | **B**ranch **L**ist **A**ll | List local and remote branches |
| `hug blr` | **B**ranch **L**ist **R**emote | List remote branches only |
| `hug bll` | **B**ranch **L**ist **L**ong | Detailed local branch list with tracking info |
| `hug bc` | **B**ranch **C**reate | Create a new branch and switch to it |
| `hug br` | **B**ranch **R**ename | Rename the current branch |
| `hug brestore` | **B**ranch **RESTORE** | Restore a branch from a backup |
| `hug bdel` | **B**ranch **DEL**ete | Delete branches interactively or by name |
| `hug bdel-backup` | **B**ranch **DEL**ete **BACKUP** | Delete backup branches with filters |
| `hug bdelf` | **B**ranch **DEL**ete **F**orce | Force-delete local branch |
| `hug bdelr` | **B**ranch **DEL**ete **R**emote | Delete remote branch |
| `hug bpull` | **B**ranch **Pull** | Safe fast-forward pull (fails if merge/rebase needed) |
| `hug bpullr` | **B**ranch **Pull** **R**ebase | Pull with rebase (linear history) |
| `hug bwc` | **B**ranch **W**hich **C**ontain | Branches containing a commit |
| `hug bwp` | **B**ranch **W**hich **P**oint | Branches pointing at an object |
| `hug bwnc` | **B**ranch **W**hich **N**ot **C**ontain | Branches missing a commit |
| `hug bwm` | **B**ranch **W**hich **M**erged | Branches merged into a commit |
| `hug bwnm` | **B**ranch **W**hich **N**ot **M**erged | Branches not merged into a commit |

## Listing Branches

### `hug b [branch]`
- **Description**: Switch (checkout) to an existing local branch. If no branch is specified, shows an interactive menu of local branches for selection.
- **Example**:
  ```shell
  hug b main                 # Switch to main branch
  hug b                      # Interactive menu to select branch
  hug b feature/new-ui       # Switch to feature branch
  ```
- **Safety**: Interactive mode prevents accidental switches. Always checks if you're in a Git repo.
- ![hug b example](img/hug-b.png)
- After typing `perform`:
- ![hug b example with "perform" search term](img/hug-b-perform.png)

### `hug bl`
- **Description**: List local branches in short format, sorted alphabetically. The current branch is marked with an asterisk (*).
- **Example**:
  ```shell
  hug bl    # List all local branches
  ```
- **Safety**: Read-only operation; no changes to repo state.
- ![hug bl example](img/hug-bl.png)

### `hug bla`
- **Description**: List all branches (local and remote) in short format.
- **Example**:
  ```shell
  hug bla   # List all branches including remotes
  ```
- **Safety**: Read-only.
- ![hug bla example](img/hug-bla.png)

### `hug blr`
- **Description**: List remote branches only in short format.
- **Example**:
  ```shell
  hug blr   # List remote branches
  ```
- **Safety**: Read-only.
- ![hug blr example](img/hug-blr.png)

### `hug bll`
- **Description**: List local branches in long format with details: short commit hash, upstream tracking info (e.g., ahead/behind counts), and the latest commit message title. Current branch is highlighted in green and marked with *. Branches are left-aligned for readability.
- **Example**:
  ```shell
  hug bll   # Detailed local branch listing
  ```
- **Safety**: Read-only; displays tracking info like `git branch -vv` but with commit subjects.
- ![hug bll example](img/hug-bll.png)

## Branch Creation / Modification

### `hug bc [<branch-name>] [--point-to <commitish>]`
- **Description**: Create a new branch and switch to it. By default, creates from current HEAD. With `--point-to`, you can create a branch from any commit, tag, or branch.
- **Arguments**:
  - `<branch-name>` - Name for the new branch (optional with `--point-to`)
  - `--point-to <commitish>` - Create branch pointing to a specific commit, tag, or branch
- **Auto-Generated Names**: When using `--point-to` without a branch name, automatically generates a descriptive name:
  - If target is a branch: `<branch>.copy.<iso-datetime>`
  - If target is not a branch: `<target>.branch.<iso-datetime>`
  - ISO datetime format: YYYYMMDD-HHMM (e.g., 20251109-1430)
- **Examples**:
  ```shell
  hug bc new-feature                      # Create branch from current HEAD
  hug bc --point-to abc123 my-feature     # Create branch from commit abc123
  hug bc --point-to v1.0.0                # Auto-generate name from tag v1.0.0
  hug bc --point-to main                  # Auto-generate name: main.copy.20251109-1430
  hug bc my-feature --point-to abc123     # Flag can come after branch name
  ```
- **Use Cases**:
  - **From a tag**: Quickly create a branch to investigate or patch a specific release
  - **From a commit**: Create a branch from a specific point in history for debugging or feature development
  - **From another branch**: Create a snapshot copy of a branch's current state
  - **Experimentation**: Auto-generated names let you quickly create exploratory branches without thinking of names
- **Safety**: Non-destructive; creates from specified point or current HEAD.

### `hug br <new-name>`
- **Description**: Rename the current branch to a new name.
- **Example**:
  ```shell
  hug br updated-feature  # Rename current branch
  ```
- **Safety**: Prompts for confirmation if the new name exists.

### `hug brestore [<backup-branch>] [<target-branch>]`
- **Description**: Restore a branch from a backup created by commands like `hug rb`. Backups follow the naming convention `hug-backups/YYYY-MM/DD-HHMM.original-name`. If no arguments are provided, shows an interactive menu of available backups. When there are 10 or more backup branches and [gum](https://github.com/charmbracelet/gum) is installed, uses an interactive filter for easier selection. Otherwise, displays a numbered list. If only the backup branch is specified, restores to the original branch name. If both arguments are provided, restores to a different branch name.
- **Examples**:
  ```shell
  hug brestore                                      # Interactive: select from available backups (uses gum filter for 10+)
  hug brestore hug-backups/2025-11/02-1234.feature # Restore to 'feature'
  hug brestore hug-backups/2025-11/02-1234.feature recovered-feature  # Restore to 'recovered-feature'
  hug brestore hug-backups/2025-11/02-1234.feature --dry-run  # Preview restoration
  ```
- **Safety**: Prompts for confirmation if the target branch already exists (destructive operation). Use `--dry-run` to preview changes. The original backup branch is preserved after restoration.

## Branch Deletion

### `hug bdel [<branch>...]`
- **Description**: Interactively or directly delete one or more local branches. Supports multi-selection via `gum filter` when no branches specified.
- **Examples**:
  ```shell
  hug bdel                    # Interactive: select branches with gum filter
  hug bdel old-feature        # Delete single branch (merged only)
  hug bdel feat-1 feat-2      # Delete multiple branches
  hug bdel old-feat --force   # Force delete unmerged branch
  hug bdel --dry-run          # Preview what would be deleted
  ```
- **Features**:
  - Interactive multi-selection with `gum filter --no-limit` (when no branches specified)
  - Excludes backup branches (use `hug bdel-backup` for those)
  - Shows confirmation with branch count before deletion
  - Safe by default: only deletes merged branches (use `--force` for unmerged)
- **Safety**: Requires confirmation unless `--force` is used; fails if trying to delete unmerged branches without `--force`.

### `hug bdel-backup [<backup>...] [--keep N] [--delete-older-than PATTERN]`
- **Description**: Manage backup branches created by commands like `hug rb`. Supports filtering by date and keeping N most recent backups.
- **Examples**:
  ```shell
  hug bdel-backup                                  # Interactive: select backups to delete
  hug bdel-backup 2024-11/02-1234.feature         # Delete specific backup (short form)
  hug bdel-backup --keep 5                        # Keep 5 most recent, delete rest
  hug bdel-backup --delete-older-than 2024-11     # Delete backups from Nov 2024 and earlier
  hug bdel-backup --delete-older-than 2024-11/03  # Delete backups from Nov 3, 2024 and earlier
  hug bdel-backup --keep 3 --delete-older-than 2024  # Combine filters: delete 2024 and earlier, but keep 3 most recent overall
  ```
- **Filter Patterns**:
  - `YYYY` - Year (e.g., `2024`)
  - `YYYY-MM` - Month (e.g., `2024-11`)
  - `YYYY-MM/DD` - Day (e.g., `2024-11/03`)
  - `YYYY-MM/DD-HH` - Hour (e.g., `2024-11/03-14`)
  - `YYYY-MM/DD-HHMM` - Minute (e.g., `2024-11/03-1415`)
- **Features**:
  - Interactive multi-selection with `gum filter --no-limit`
  - `--keep N`: Always preserve N most recent backups
  - `--delete-older-than`: Delete backups with timestamps older than pattern
  - Combined filters: `--delete-older-than` identifies candidates, `--keep` protects most recent
- **Safety**: Always prompts for confirmation unless `--force` is used.

### `hug bdelf <branch>`
- **Description**: Force-delete a local branch, even if unmerged. Direct alias to `git branch -D`.
- **Example**:
  ```shell
  hug bdelf risky-branch  # Force delete unmerged branch
  ```
- **Note**: For safer multi-branch deletion with unmerged branches, use `hug bdel --force` which provides better UI and confirmation.

### `hug bdelr <branch>`
- **Description**: Delete a remote branch from the `origin` remote.
- **Example**:
  ```shell
  # First, list remote branches to find the one to delete
  hug blr
  # Then, delete the desired branch by name
  hug bdelr old-remote-feature
  ```
- **Safety**: Prompts for confirmation before deleting.

## Pulling Branches

Hug provides safe, intuitive pull commands under the `b*` prefix, emphasizing fast-forward safety by default while offering rebase for linear histories.

### `hug bpull`
- **Description**: Safe fast-forward pull from upstream. Succeeds only if your local branch can fast-forward (no local divergence); aborts otherwise to prevent unintended merges or rewrites. Ideal for verifying sync before critical operations like tagging or releasing.
- **Example**:
  ```shell
  hug bpull    # Pull if fast-forward possible; fails safely if diverged
  ```
- **Safety**: Ultra-safe - aborts on any need for merge/rebase, prompting you to inspect with `hug sl` or use `hug bpullr`.

### `hug bpullr`
- **Description**: Pull with rebase, replaying your local commits on top of remote changes for a clean, linear history. Use when you've diverged locally (e.g., after committing features).
- **Example**:
  ```shell
  hug bpullr   # Pull and rebase for linear history
  ```
- **Safety**: Non-destructive to remote history, but may require conflict resolution. Aborts on issues; resume with `hug rbc` or abort with `hug rba`. See the [Rebase Conflict Workflow](rebase.md#rebase-conflict-workflow) for a detailed guide on resolving conflicts.

## Branch Queries (bw*)

These commands help inspect which branches relate to specific commits or states.

### `hug bwc [<commit>]`
- **Description**: Show branches that contain a specific commit (in their history). Defaults to HEAD.
- **Example**:
  ```shell
  hug bwc a1b2c3    # Branches containing commit a1b2c3
  hug bwc           # Branches containing HEAD
  ```
- **Safety**: Read-only.
- ![hug bwc example](img/hug-bwc.png)

### `hug bwp [<object>]`
- **Description**: Show branches that point exactly at a specific object (e.g., commit). Defaults to HEAD.
- **Example**:
  ```shell
  hug bwp HEAD       # Branches pointing at HEAD
  ```
- **Safety**: Read-only.
- ![hug bwp example](img/hug-bwp.png)

### `hug bwnc [<commit>]`
- **Description**: Show branches that do NOT contain a specific commit. Defaults to HEAD.
- **Example**:
  ```shell
  hug bwnc HEAD      # Branches not containing HEAD
  ```
- **Safety**: Read-only.
- ![hug bwnc example](img/hug-bwnc.png)

### `hug bwm [<commit>]`
- **Description**: Show branches merged into a specific commit (defaults to HEAD).
- **Example**:
  ```shell
  hug bwm            # Branches merged into HEAD
  ```
- **Safety**: Read-only.
- ![hug bwm example](img/hug-bwm.png)

### `hug bwnm [<commit>]`
- **Description**: Show branches NOT merged into a specific commit (defaults to HEAD).
- **Example**:
  ```shell
  hug bwnm           # Branches not merged into HEAD
  ```
- **Safety**: Read-only.
- ![hug bwnm example](img/hug-bwnm.png)

## Tips
- Use `hug b` to review branch status and easily switch via an interactive menu.
- **Quick branch creation**: Use `hug bc --point-to <target>` without a branch name to quickly experiment - the auto-generated name includes a timestamp.
- **Branch from releases**: Need to patch a production release? Use `hug bc --point-to v1.2.3` to instantly create a branch from that tag.
- **Preserve branch state**: Create a snapshot before risky operations: `hug bc --point-to feature-branch` creates a timestamped copy.
- Use `hug blr` to list remote branches before deleting one with `hug bdelr`.
- Queries like `bwc` and `bwm` are useful for cleanup before `bdel`.
- Commands like `hug rb` automatically create backup branches in the `hug-backups/` namespace. Use `hug brestore` to restore them if needed.
- Backup branches follow the naming convention `hug-backups/YYYY-MM/DD-HHMM.original-name`, making them easy to identify and clean up.

See [Status & Staging](status-staging) for checking changes after branching operations.
