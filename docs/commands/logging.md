# Logging (l*)

Logging commands in Hug provide powerful ways to view, search, and inspect commit history. Prefixed with `l` for "log," they enhance Git's `log` command with intuitive searches by message, code changes, authors, dates, and file-specific histories. File-focused commands (llf*) handle renames via `--follow` and support limiting to recent commits (e.g., `-1` for the most recent).

## Quick Reference

| Command | Memory Hook | Summary |
| --- | --- | --- |
| `hug l` | **L**og summary | Oneline history with graph and decorations |
| `hug ll` | **L**og **L**ong | Detailed log with full messages |
| `hug la` | **L**og **A**ll | Detailed log across all branches |
| `hug lp` | **L**og **P**atch | Log with diffs for each commit |
| `hug lf` | **L**og message **F**ilter | Search commit messages |
| `hug lc` | **L**og **C**ode search | Search diffs for exact term |
| `hug lcr` | **L**og **C**ode **R**egex | Search diffs with regex |
| `hug lau` | **L**og **A**uthor | Filter log by author |
| `hug ld` | **L**og **D**ate | Log commits within a date range |
| `hug llf` | **L**og **L**ookup **F**ile | File history following renames |
| `hug llfs` | **L**og **L**ookup **F**ile **S**tats | File history with change statistics |
| `hug llfp` | **L**og **L**ookup **F**ile **P**atch | File history with full patches |

## Basic Logging

- `hug l [options]`
  - **Description**: One-line log with graph visualization and branch decorations for a concise history overview.
  - **Example**:
    ```
    hug l              # Current branch history
    hug l --all        # All branches
    ```
  - **Safety**: Read-only; no repo changes.
  - **Git Equivalent**: `git log --oneline --graph --decorate --color`

- `hug ll [options]`
  - **Description**: Detailed log with graph, short date, author, decorations, and full commit message.
  - **Example**:
    ```
    hug ll             # Current branch detailed history
    hug ll --all       # All branches
    ```
  - **Safety**: Read-only.
  - **Git Equivalent**: `git log --graph --pretty=log1 --date=short`

- `hug la [options]`
  - **Description**: Log across all branches (alias for `hug ll --all`).
  - **Example**: `hug la`
  - **Safety**: Read-only.

- `hug lp [options]`
  - **Description**: Detailed log including patches/diffs for each commit.
  - **Example**:
    ```
    hug lp             # Patches for current branch
    hug lp -3          # Last 3 commits with patches
    ```
  - **Safety**: Read-only.

## Search by Commit Message

- `hug lf <search-term> [-i] [-p] [--all]`
  - **Description**: Search commit history by grep on commit messages.
  - **Options**:
    - `-i`: Ignore case.
    - `-p`: Include patches in results.
    - `--all`: Search all branches.
  - **Usage**:
    ```
    hug lf "fix bug"           # Case-sensitive search
    hug lf -i "fix bug" --all  # Ignore case, all branches
    ```
  - **Safety**: Read-only.

## Search by Code Changes

- `hug lc <search-term> [-i] [-p] [--all] [-- file]`
  - **Description**: Search commits where the diff (code changes) contains the term (Git's pickaxe search). Restrict to a file with `-- file`.
  - **Options**:
    - `-i`: Ignore case.
    - `-p`: Show patches.
    - `--all`: All branches.
  - **Example**:
    ```
    hug lc "getUserById"              # Search code changes
    hug lc "getUserById" -- src/users.js  # Restrict to file
    ```
  - **Safety**: Read-only.

- `hug lcr <regex> [-i] [-p] [--all] [-- file]`
  - **Description**: Search commits where the diff matches a regex (more flexible than `lc`).
  - **Options**: Same as `lc`.
  - **Example**:
    ```
    hug lcr "TODO:" --all    # Regex search across branches
    ```
  - **Safety**: Read-only.

## Search by Author and Date

- `hug lau <author> [options]`
  - **Description**: Filter log to commits by a specific author.
  - **Example**:
    ```
    hug lau "John Doe"       # Author's commits
    hug lau "John Doe" -5    # Last 5 by author
    ```
  - **Safety**: Read-only.

- `hug ld <since-date> [<until-date>]`
  - **Description**: Log commits within a date range (until defaults to now).
  - **Example**:
    ```
    hug ld "2023-01-01"      # Since date
    hug ld "2023-01-01" "2023-12-31"  # Date range
    ```
  - **Safety**: Read-only.

## File Inspection (llf*)

These commands show the history of changes to a specific file, following renames. Use `-N` to limit to the last N commits (e.g., `-1` for most recent). Combine with log options like `--stat` or `-p`.

- `hug llf <file> [-N] [log options]`
  - **Description**: Log commits that modified a file (handles renames). Ideal for finding the most recent change to a file.
  - **Example**:
    ```
    hug llf file.txt -1          # Most recent commit touching file
    hug llf file.txt -2 --stat   # Last 2 commits with stats
    ```
  - **Safety**: Read-only.

- `hug llfs <file> [-N] [log options]`
  - **Description**: File history with change statistics (insertions/deletions).
  - **Example**:
    ```
    hug llfs file.txt -1  # Stats for most recent change
    ```
  - **Safety**: Read-only.
  - **Git Equivalent**: `git log --follow --stat -- <file>`

- `hug llfp <file> [-N] [log options]`
  - **Description**: File history including full patches/diffs.
  - **Example**:
    ```
    hug llfp file.txt -1  # Patch of most recent change
    ```
  - **Safety**: Read-only.

## Tips
- **Most recent commit touching a file**: `hug llf <file> -1` (handles renames with `--follow`).
- **Last N commits for a file**: `hug llf <file> -N` (e.g., `-2` for last 2). Use `hug llfs <file> -1` for stats or `hug llfp <file> -1` for patches.
- **Search history by file changes**: Combine with `lf` or `lc` for message/code searches restricted to file touches, e.g., `hug lc "TODO" -- file.txt`.
- Pipe to pager for long outputs: `hug ll | less`.
- For line-level inspection (blame), see [File Inspection](file-inspection) like `hug fblame <file>`.
- Use `hug la` or `hug ll --all` to search across branches.

Pair logging with [Status & Staging](status-staging) to inspect changes, or [HEAD Operations](head) to undo based on history.
