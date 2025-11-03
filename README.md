# Hug SCM - The Humane Source Control Management Interface

[![Tests](https://github.com/elifarley/hug-scm/actions/workflows/test.yml/badge.svg)](https://github.com/elifarley/hug-scm/actions/workflows/test.yml) [![Deploy Docs to GitHub Pages](https://github.com/elifarley/hug-scm/actions/workflows/deploy-docs.yml/badge.svg)](https://github.com/elifarley/hug-scm/actions/workflows/deploy-docs.yml) [![Regenerate VHS Images](https://github.com/elifarley/hug-scm/actions/workflows/regenerate-vhs-images.yml/badge.svg)](https://github.com/elifarley/hug-scm/actions/workflows/regenerate-vhs-images.yml)

A humane, intuitive interface for Git and other version control systems. Hug transforms complex and forgettable Git commands into a simple, predictable language that feels natural to use, keeping you focused on your code, not on wrestling with version control.

| [**&rarr; View the Documentation**](https://elifarley.github.io/hug-scm/) | [![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/elifarley/hug-scm) |
| :--- | :--- |

![Made with VHS](https://vhs.charm.sh/vhs-4D3aNvebEOccORctJOta77.gif)

## Table of Contents
- [What is Hug?](#what-is-hug)
- [Why Hug?](#why-hug)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Command Reference](#command-reference)
- [Philosophy](#philosophy)
- [Testing](#testing)
- [Roadmap](#roadmap)
- [License](#license)

## What is Hug?

Hug SCM is a humane interface layer for version control systems that currently supports **Git** and **Mercurial**.
It transforms complex, often intimidating SCM commands into an intuitive, predictable language that feels natural to developers.

With Hug, you get:

- Intuitive commands that make sense
- Progressive safety (shorter = safer, longer = more powerful)
- Consistent patterns across all operations
- Rich feedback and previews before destructive actions
- **Multi-VCS support** - Use the same commands whether you're working with Git or Mercurial repositories

## Why Hug?
While Git is incredibly powerful, its command syntax can be inconsistent and difficult to remember. Hug smooths out these rough edges.

✅ Making common operations trivial

`hug b feature` gets you to a branch, instead of `git checkout -b feature`

✅ Keeping you safe

Destructive commands require explicit confirmation

✅ Being discoverable

Commands are grouped logically: `h*` for `HEAD` operations, `w*` for working directory, `s*` for status

✅ Providing superpowers

Complex operations become one-liners: `hug w zap-all` for a complete "factory reset" of your local working directory.

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
# Hug, Head movement: Back
hug h back
# Tip: When the staging area has no staged changes, Hug skips the confirmation prompt automatically; existing staged work still triggers it. Unstaged changes are never touched by this command. The same protection applies to `hug h squash` and `hug h undo`, which keep you safe when staged or unstaged work might otherwise be unintentionally lumped into the action while skipping the prompt when no staged or unstaged changes are present.

# Want to see what changed in a specific file?
# Hug, Status: Working dir (meaning unstaged changes)
hug sw file.js

# Clean up build artifacts?
hug w purge

# Get a file from an old commit?
# Hug, Working dir: Get from <commit> the file <file>
hug w get a1b2c3 file.js

# Preview a destructive operation
hug w zap-all --dry-run

# Force a cleanup without prompts
hug w zap-all -f

# Undo last 3 commits, unstage changes
# Hug, Head movement: UNDO last 3 commits
hug h undo 3

# Find steps back to last change in a file, then rewind precisely
hug h steps src/app.js  # e.g., "2 steps back..."
hug h back 2

# Safe pull (fast-forward only; fails on divergence)
hug bpull

# Pull with rebase for linear history
hug bpullr

# Park WIP for interruption to have a clean working directory
hug wip "Draft feature" → hug bc hotfix && hug c "Fix bug" → hug bpush

# Deep work on WIP (stay and iterate)
hug wips "Prototype UI" → hug a . && hug c "Add components" → hug bs (pause) → later hug b WIP/... → hug w unwip WIP/... (integrate)
```

**Tip: `wips` vs. `wip`**: Use `wips` for immersive sessions (stay on WIP to add commits like `hug c`). Use `wip` for quick pauses (park). Both are pushable branches - better than local stash for persistence.

## Mercurial Support

Hug now supports Mercurial! The same intuitive commands work across both Git and Mercurial repositories.

Once installed, Hug will automatically detect whether you're in a Git or Mercurial repository and use the appropriate commands. The same familiar Hug commands work in both!

### Quick Mercurial Start

```shell
# Use the same Hug commands in Mercurial repos!
cd ~/my-hg-repo
hug s              # Status
hug a file.txt     # Add file
hug c -m "Update"  # Commit
hug b feature      # Switch bookmark
hug l              # View history
```

### Key Features

- **Automatic Detection**: Hug automatically detects whether you're in a Git or Mercurial repository
- **Unified Interface**: Use the same commands regardless of SCM type
- **Bookmark Support**: Mercurial bookmarks work like Git branches
- **Working Directory Ops**: Full support for discard, purge, and zap operations
- **HEAD Operations**: Uncommit operations via the evolve extension

### Mercurial-Specific Notes

- **No Staging Area**: Mercurial commits directly from working directory
- **Bookmarks vs Branches**: Hug uses bookmarks (like Git branches) instead of permanent Mercurial branches
- **Extensions Required**: Some commands require `purge` and `evolve` extensions

See [hg-config/README.md](hg-config/README.md) for full Mercurial documentation.

## Installation

Check the [Installation Guide](https://elifarley.github.io/hug-scm/installation.html)

---

## Quick Start Tips

- **No Git Knowledge Needed**: Hug handles the complexity; focus on intent.
- **Explore**: Run `hug help` to see Hug commands.

---

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
hug a --                    # Interactive file selection (requires gum)
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
hug lf [term]         # Search commits by message (interactive if no term, add -i for case-insensitive)
hug lc [code]         # Search commits by code changes in diff (interactive if no code)
hug lcr [regex]       # Search commits by regex in code changes (interactive if no regex)
hug lau <author>      # Commits by specific author
hug ld <since> <until># Commits in date range
hug lp                # Log with patches
hug llf [file]        # Log commits to a specific file (interactive if no file, add -p for patches)
```

#### File Inspection (`f*`)

```shell
hug fblame [file]     # Blame with whitespace/copy detection (interactive if no file)
hug fb [file]         # Short blame (author and line only) (interactive if no file)
hug fcon [file]       # List all contributors to a file (interactive if no file)
hug fa [file]         # Count commits per author for a file (interactive if no file)
hug fborn [file]      # Show when file was added (interactive if no file)
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

---

## License

Apache 2.0 License - see [LICENSE](LICENSE) for details.
