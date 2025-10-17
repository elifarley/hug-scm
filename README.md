# Hug SCM - The Humane Source Control Management Interface

Try it now:
[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/elifarley/hug-scm)

[View Documentation](https://elifarley.github.io/hug-scm/)

A humane, intuitive interface for Git and other version control systems.

Works as a universal language to control the underlying SCM tool you use.

Hug transforms complex and forgettable Git commands into a simple, predictable language that feels natural to use, keeping you focused on your code, not on wrestling with version control.

![Made with VHS](https://vhs.charm.sh/vhs-4D3aNvebEOccORctJOta77.gif)

## Table of Contents
- [What is Hug?](#what-is-hug)
- [Why Hug?](#why-hug)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Command Reference](#command-reference)
- [Philosophy](#philosophy)
- [Roadmap](#roadmap)
- [License](#license)

## What is Hug?

Hug SCM is a humane interface layer for version control systems, but currently only works with Git.
It transforms the complex, often intimidating Git commands into an intuitive, predictable language that feels natural to developers.

With Hug, you get:

- Intuitive commands that make sense
- Progressive safety (shorter = safer, longer = more powerful)
- Consistent patterns across all operations
- Rich feedback and previews before destructive actions
- Multi-VCS support (Git now, Mercurial and others coming later)

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
hug s

# Stage changes (smart defaults)
hug a            # Stage tracked changes
hug aa           # Stage everything including untracked (new) files

# Commit with context
hug c            # Commit staged changes
hug ca           # Commit all tracked changes
hug caa          # Commit all tracked & untracked changes
hug cc <commit>  # Clone a Commit on top of 'HEAD'

# Branch operations
hug bc feature   # Create and switch to new branch
hug bs           # Switch back to previous branch

# Working directory cleanup
hug w backup     # Stash current work safely
hug w zap        # Complete cleanup (reset + purge) for specific files
hug w zap-all    # Complete cleanup across the entire repository
```

### Common Scenarios

```shell
# Oops, made bad changes to a file?
hug w discard file.js

# Need to undo the last commit but keep changes staged?
# Hug, Head movement: Back
hug h back

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
```

## Installation

1. **Clone the Repo**:
   ```shell
   git clone https://github.com/elifarley/hug-scm.git
   cd hug-scm
   ```

2. **Install** (run from repo root):
   ```shell
   ./install.sh
   ```

3. **Verify**:
   ```shell
   hug s  # Should show status summary
   hug help  # List available commands
   ```

**Dependencies**: Bash, Git 2.23+ (for `git restore`). Works on Linux/macOS.

---

## Quick Start Tips

- **No Git Knowledge Needed**: Hug handles the complexity; focus on intent.
- **Dry-Run Everything**: Add `--dry-run` to preview (e.g., `hug w zap-all --dry-run`).
- **Backup First**: Always `hug w backup` before destructive ops.
- **Explore**: Run `hug alias` to see all Git aliases enabled by Hug.

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
hug w backup [-m "msg"]           # Safe stash of changes
hug w get <commit> [files]        # Restore files from specific commit
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

#### Stashing (`s*` for stash, but note `s` is also status)

```shell
hug ssave             # Quick stash (tracked files only)
hug ssavea "msg"      # Stash with message and untracked files
hug ssavefull         # Stash everything including ignored files
hug sls               # List stashes with formatting
hug speek [stash]     # Preview stash contents with full diff
hug sshow [stash]     # Summary of stash changes
hug sapply [stash]    # Apply stash and keep it
hug spop [stash]      # Pop stash (with interactive preview)
hug sdrop [stash]     # Drop specific stash
hug sbranch <branch> [stash] # Create branch from stash
hug sclear            # Clear all stashes
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
hug bpush             # Branch: Push (Push current branch and set upstream)
hug bpushf            # Branch: Push-Force (Force push with lease and set upstream)
hug bpush-unsafe      # Branch: Push-unsafe (Unsafe force push and set upstream)
hug bpull             # Pull with rebase
hug pullall           # Pull from all remotes
```

#### Utilities

```shell
hug o                 # Outgoing changes (what will be pushed)
hug wip               # Commit everything as WIP
hug unwip             # Undo last WIP commit
hug alias [pattern]   # List all aliases (search with pattern)
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

-    **Mercurial Support** - Full compatibility with `hg` commands
-    **Sapling Support** - Meta's next-gen VCS
-    **Interactive Mode** - TUI with visual diff preview
-   \[\] **AI Integration** - Smart commit suggestions
-    **GUI Frontend** - Visual interface for complex operations
-   \[\] **Plugin System** - Custom command extensions

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## License

MIT License - see [LICENSE](LICENSE) for details.

