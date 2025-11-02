# Hug SCM - The Humane Source Control Management Interface

[![Tests](https://github.com/elifarley/hug-scm/actions/workflows/test.yml/badge.svg)](https://github.com/elifarley/hug-scm/actions/workflows/test.yml) [![Deploy Docs to GitHub Pages
[Command Reference](#command-reference)
- [Philosophy](#philosophy)
- [Roadmap](#roadmap)
- [Testing](#testing)
- [License](#license)

## What is Hug?

Hug SCM is a humane interface for Git and Mercurial that transforms complex commands into a simple, predictable language. It's designed to keep you focused on your code, not on wrestling with version control.

## Core Features

- **Intuitive Commands:** Simple, memorable commands for common operations (`hug b feature` instead of `git checkout -b feature`).
- **Safety First:** Destructive operations require confirmation and offer previews, preventing accidental data loss.
- **Multi-VCS Support:** Use the same commands for both Git and Mercurial repositories.
- **Discoverable Interface:** Commands are grouped by prefixes (`h*` for HEAD, `w*` for working directory), making them easy to find and learn.
- **WIP Workflow:** A robust alternative to `git stash` that uses temporary branches to park work safely.

## Installation

1. **Clone the repository:**
   ```shell
   git clone https://github.com/elifarley/hug-scm.git
   ```
2. **Run the installer:**
   ```shell
   cd hug-scm && ./install.sh
   ```

For more details, see the [full installation guide](https://elifarley.github.io/hug-scm/installation.html).

## Quick Start

### Basic Workflow

```shell
# Check status with beautiful output
hug sl # **S**tatus + **L**ist

# Stage changes (smart defaults)
hug a            # Stage tracked changes
hug aa           # Stage everything including untracked (new) files

# Commit with context
hug c            # Commit staged changes
hug ca           # Commit all tracked changes
hug caa          # Commit all tracked & untracked changes

# Branch operations
hug bc feature   # Create and switch to new branch
hug bs           # Switch back to previous branch

# Safe pull (fast-forward only; fails on divergence)
hug bpull

# Pull with rebase for linear history
hug bpullr

# Working directory cleanup
hug w zap        # Complete cleanup (reset + purge) for specific files
hug w zap-all    # Complete cleanup across the entire repository

# Park WIP (preferred over stash)
hug wip "Draft feature"    # Park and get a clean working directory (quick pause)
hug wips "Deep spike"      # Park and stay (continue immediately)
```

### Common Scenarios

```shell
# Oops, made bad changes to a file?
hug w discard file.js

# Need to undo the last commit but keep changes staged?
hug h back

# Want to see what changed in a specific file?
hug sw file.js

# Clean up build artifacts?
hug w purge

# Get a file from an old commit?
hug w get a1b2c3 file.js

# Preview a destructive operation
hug w zap-all --dry-run
```

**Tip:** Run `hug help` to see all available commands.

## Documentation

For a complete guide to all commands and concepts, check out the [full documentation](https://elifarley.github.io/hug-scm/).

- **[Command Map](https://elifarley.github.io/hug-scm/command-map)**: A quick overview of all command families.
- **[Cheat Sheet](https://elifarley.github.io/hug-scm/cheat-sheet)**: A handy reference for daily workflows.
- **[Core Concepts](https://elifarley.github.io/hug-scm/core-concepts)**: An introduction to the philosophy behind Hug.

## Command Reference

### Command Groups

Prefix|Category|Description
-|-|-
`h*`|HEAD Operations|Move HEAD, undo commits
`w*`|Working Directory|Discard, wipe, purge, zap changes
`s*`|Status & Staging|View status
`b*`|Branching|Create, switch, manage branches
`t*`|Tagging|Create, manage tags
`l*`|Logging|View history, list matching commits for a search term
`f*`|File Inspection|Analyze file authorship and history (blame, contributors)

### Core Commands

#### 📍 HEAD Operations (`h`)

```shell
hug h back [N|commit]     # Move HEAD back, keep changes staged (non-destructive)
hug h undo [N|commit]     # Move HEAD back, unstage changes (non-destructive)
hug h rollback [N|commit] # Rollback commits and their changes (preserves local work)
hug h rewind <commit>     # Destructive rewind to clean state (discards history and changes, but keeps current untracked files)
hug h squash [N|commit]   # Squash commits into one
hug h files [N|commit]    # Preview files touched in commit range
hug h steps <file> [--raw] # Steps back from HEAD to last change in <file> (for precise rewinds)
```

#### 🧹 Working Directory (`w`)

```shell
# Discard changes
hug w discard [-u|-s] <files>     # Discard unstaged/staged changes for specific files
hug w discard-all [-u|-s]         # Discard across entire repo

# Wipe changes (staged + unstaged)
hug w wipe <files>                # Complete reset for specific files
hug w wipe-all                    # Reset all tracked files to last commit

# Remove untracked/ignored files
hug w purge [-u|-i] <files>       # Remove untracked/ignored for specific paths
hug w purge-all [-u|-i]           # Remove across entire repo

# Nuclear option: discard + purge
hug w zap [-u|-s|-i] <files>      # Full cleanup for specific paths
hug w zap-all [-u|-s|-i]          # Complete repo cleanup

# Utility
hug w get <commit> [files]        # Restore files from specific commit
```

#### Parking Work (WIP)

```shell
# Save all changes on a WIP branch (pushable, persistent)
hug wip "msg"              # Move uncommitted changes away into a new WIP branch (for interruptions)
hug wips "msg"             # Park work and stay on the new WIP branch (for focused work)

# Resume WIP
hug b <wip-branch-name>    # Switch to the WIP branch to continue

# Finish and integrate WIP
hug w unwip <wip-branch>   # Squash-merges WIP into current branch and deletes it

# Abandon WIP
hug w wipdel <wip-branch>  # Deletes the WIP branch without merging
```

#### 📊 Status & Staging (`s`)

```shell
hug s                       # Quick summary of staged/unstaged changes
hug sl                      # Status without untracked files
hug sla                     # Full status with untracked files
hug sli                     # Status with list of ignored files

hug ss [file]               # Status with staged changes patch
hug su [file]               # Status with unstaged changes patch
hug sw [file]               # Status with working dir changes patch (staged and unstaged)

# Staging
hug a [files]               # Stage tracked files (or all if no args)
hug aa                      # Stage everything (tracked + untracked + deletions)
hug us <files>              # Unstage specific files
hug usa                     # Unstage all files
```

#### 🌿 Branching (`b`)

```shell
hug b <branch>              # Switch to existing branch
hug bs                      # Switch back to previous branch
hug bc <branch>             # Create and switch to new branch
hug bl                      # List local branches
hug bla                     # List all branches (local + remote)
hug bdel <branch>           # Safe delete local branch (if merged)
hug bdelf <branch>          # Force delete local branch
hug bdelr <branch>          # Delete remote branch
```

### Full Command List

<details>
<summary>Click to expand all commands</summary>

#### Logging & History (`l*`)

```shell
hug l                 # One-line log with graph and decorations
hug ll                # Log with date, author, and message (short date)
hug la                # Log all branches
hug lf <term>         # Search commits by message (add -i for case-insensitive)
hug lc <code>         # Search commits by code changes in diff
hug lcr <regex>       # Search commits by regex in code changes
hug lau <author>      # Commits by specific author
hug ld <since> <until># Commits in date range
hug lp                # Log with patches
hug llf <file>        # Log commits to a specific file (add -p for patches)
```

#### File Inspection (`f*`)

```shell
hug fblame <file>     # Blame with whitespace/copy detection
hug fb <file>         # Short blame (author and line only)
hug fcon <file>       # List all contributors to a file
hug fa <file>         # Count commits per author for a file
hug fborn <file>      # Show when file was added
```

#### Tagging (`t*`)

```shell
hug t [pattern]       # Tags (List tags (matching pattern))
hug tc <tag> [commit] # Create lightweight tag
hug ta <tag> "msg"    # Create annotated tag
hug ts <tag>          # Show tag details
hug tr <old> <new>    # Rename tag
hug tm <tag> [commit] # Move tag to new commit (default HEAD)
hug tma <tag> "msg" [commit] # Move and re-annotate tag
hug tpush [tags]      # Push tags to remote (or all if no args)
hug tpull             # Fetch tags from remote
hug tpullf            # Force fetch and prune tags
hug tdel <tag>        # Delete local tag
hug tdelr <tag>       # Delete remote tag
hug tco <tag>         # Checkout tag
hug twc [commit]      # Tags which contain commit (default HEAD)
hug twp [object]      # Tags which point to object (default HEAD)
```

#### Branching (`b*`) - Additional Details

```shell
hug blr               # Branch: List Remote (List remote branches only)
hug br <new-name>     # Branch: Rename (Rename current branch)
hug bwc [commit]      # Branches which contain commit (default HEAD)
hug bwp [object]      # Branches which point to object (default HEAD)
hug bwnc [commit]     # Branches which do not contain commit
hug bwm [commit]      # Branches merged into commit (default HEAD)
hug bwnm [commit]     # Branches not merged into commit
```

#### Commits (`c*`)

```shell
hug c [-m msg]        # Commit (staged changes)
hug ca [-m msg]       # Commit: All (all tracked changes)
hug caa [-m msg]      # Commit: All All (tracked + untracked + deletions)
hug cm [-m msg]       # Commit: Modify (Amend last commit with staged changes)
hug cma [-m msg]      # Commit: Modify (Amend last commit with all tracked changes)
hug ccp <commit>      # Commit Copy (cherry-pick commit onto current branch)
hug cmv [N] <branch> [--new] # Move commits to another branch and switch to it (like mv; detaches for new (exact history), cherry-picks for existing; combined prompt to create if missing, auto with --force)
hug cii               # Interactive patch commit (add --patch then commit)
hug cim               # Full interactive staging and commit
```

#### Rebase & Merge (`r*`, `m*`)

```shell
hug rb <branch>       # Rebase current onto branch
hug rbi [commit]      # Interactive rebase (default root)
hug rbc               # Continue rebase
hug rba               # Abort rebase
hug rbs               # Skip commit in rebase
hug m <branch>        # Squash-merge branch (no commit)
hug mff <branch>      # Merge with fast-forward only
hug mkeep <branch>    # Merge with no fast-forward (create commit)
hug ma                # Abort merge
```

#### Push/Pull (`bpush`, etc.)

```shell
hug bpush             # Branch: Push (Push current branch)
hug bpushf            # Branch: Push-Force (Force push with lease)
hug bpush-unsafe      # Branch: Push-unsafe (Unsafe force push)
hug bpull             # Pull with rebase
hug pullall           # Pull from all remotes
```

#### Utilities

```shell
hug lol [<remote-branch>] # Log Outgoing Long: Show outgoing changes (what will be pushed; optional remote branch target, e.g., origin/dev)
hug w wip "<msg>"     # Park all changes on WIP branch
hug w unwip [wip]     # Unpark WIP: squash-merge to current branch + delete
hug w wipdel [wip]    # Delete WIP branch without integration
hug type <object>     # Show object type
hug dump <object>     # Show object contents
hug untrack <files>   # Stop tracking files but keep locally
```

#### Status & Show (`s*`, `sh*`)

```shell
hug s                 # Status
hug sl                # Status: List (without untracked files)
hug sla               # Status: List All (Full status with untracked files)
hug sh [commit]       # SHow [commit] (with stat; default: last)
hug shp [commit]      # SHow: with Patch (commit with patch)
hug shc <commit>      # SHow: Changed files (Files changed in commit)
hug shf <file> [commit] # SHow: File at [commit] (File diff in commit)
```

</details>

## Philosophy

### 1. **Brevity Hierarchy**

-   Shorter commands = more common/safer
-   Longer commands = more specific/powerful
-   `hug b` for branch switching (most common)
-   `hug bdelr` for remote branch deletion (rare)

### 2. **Semantic Clarity**

-   Commands describe what they do
-   `w wipe` = wipe changes clean
-   `w purge` = purge unwanted files
-   `w zap` = make it pristine

### 3\. **Progressive Destructiveness**

```shell
`discard < wipe < zap < rewind`
```

### 4. **Safety First**

-   All destructive operations show previews
-   Explicit confirmations required
-   Dry-run mode everywhere

### 5. **Discoverability**

-   Related commands share prefixes
-   Built-in help with examples
-   Smart completion with partial matching

## Roadmap

- ✅ **Mercurial Support** - Full compatibility with `hg` commands (COMPLETED!)
  - Core commands (status, staging, commits, branches)
  - Working directory operations (discard, purge, zap)
  - HEAD operations (back, undo)
  - Automatic repository detection
  - See [ADR-002](docs/architecture/ADR-002-mercurial-support-architecture.md) for details
-    **Sapling Support** - Meta's next-gen VCS
-    **Interactive Mode** - TUI with visual diff preview
-    **AI Integration** - Smart commit suggestions
-    **GUI Frontend** - Visual interface for complex operations
-    **Plugin System** - Custom command extensions

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Testing

Hug SCM uses [BATS (Bash Automated Testing System)](https://github.com/bats-core/bats-core) for automated testing. We have comprehensive test coverage for core commands and workflows.

**Running Tests:**
```bash
# Using Make (recommended)
make test              # Run all tests
make test-unit         # Run unit tests only
make test-integration  # Run integration tests only
make test-check        # Check prerequisites

# Or use the test script directly
tests/run-tests.sh                              # Run all tests
tests/run-tests.sh tests/unit/test_status_staging.bats  # Run specific test
tests/run-tests.sh -v                           # Run with verbose output
```

**For Contributors:**
- All new commands must include tests
- Tests run automatically in CI on every PR
- See [TESTING.md](TESTING.md) for detailed testing guide
- See [tests/README.md](tests/README.md) for test suite documentation
- See [ADR-001](docs/architecture/ADR-001-automated-testing-strategy.md) for testing strategy rationale

---

## License

Apache 2.0 License - see [LICENSE](LICENSE) for details.
