# Hug SCM - The Humane Source Control Management Interface

Try it now:
[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/elifarley/hug-scm)

A humane, intuitive interface for Git and other version control systems.

Works as a universal language to control the underlying SCM tool yo use.

Installation • Quick Start • Commands • Philosophy

## Table of Contents
- What is Hug?
- Why Hug?
- Installation
- Quick Start
- Command Reference
- Philosophy
- Contributing
- License

## What is Hug?

Hug SCM is a humane interface layer for version control systems, starting with Git. It transforms the complex, often intimidating Git commands into an intuitive, predictable language that feels natural to developers.

With Hug, you get:

- Intuitive commands that make sense
- Progressive safety (shorter = safer, longer = more powerful)
- Consistent patterns across all operations
- Rich feedback and previews before destructive actions
- Multi-VCS support (Git now, Mercurial and others coming soon)

## Why Hug?
Git is powerful but its learning curve can be brutal. Hug fixes that by:

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
hug aa           # Stage everything including new files

# Commit with context
hug c            # Commit staged changes
hug ca           # Commit all tracked changes

# Branch operations
hug b feature    # Create and switch to new branch
hug bs           # Switch back to previous branch

# Working directory cleanup
hug w backup     # Stash current work safely
hug w zap        # Complete cleanup (reset + purge)
```

### Common Scenarios

```shell
# Oops, made bad changes to a file?
hug w discard file.js

# Need to undo the last commit but keep changes?
hug h back

# Want to see what changed in a specific file?
hug sw file.js

# Clean up build artifacts?
hug w purge

# Get a file from an old commit?
hug w get a1b2c3 file.js
```

## Command Reference

### Command Groups

Prefix|Category|Description
-|-|-
`h*`|HEAD Operations|Move HEAD, undo commits
`w*`|Working Directory|Discard, wipe, purge, zap changes
`s*`|Status & Staging|View status, stage/unstage
`b*`|Branching|Create, switch, manage branches
`t*`|Tagging|Create, manage tags
`l*`|Logging|View history, search commits

### Core Commands

#### 📍 HEAD Operations (`h`)


```shell
`hug h back [N|commit]      # Move HEAD back, keep staged
hug h undo [N|commit]      # Move HEAD back, unstage changes  hug h rollback [N|commit]  # Rollback commit, preserve local work
hug h rewind commit        # Destructive rewind to clean state`
```

#### 🧹 Working Directory (`w`)

```shell
`# Discard changes
hug w discard [-u|-s] <files>     # Discard unstaged/staged changes
hug w discard-all [-u|-s]         # Discard across repo
# Wipe changes (staged + unstaged)
hug w wipe <files>                 # Complete file reset
hug w wipe-all                     # Reset all tracked files
# Remove files
hug w purge [-u|-i] <files>        # Remove untracked/ignored files
hug w purge-all [-u|-i]            # Remove across repo
# Nuclear option
hug w zap [-u|-s|-i] <files>       # Discard + purge
hug w zap-all [-u|-s|-i]           # Complete cleanup`

```

#### 📊 Status & Staging (`s`)


```shell
`hug s                # Quick status
hug sa               # Status with untracked files
hug ss               # Status with staged changes
hug sw               # Status with working changes
# Staging
hug a [files]        # Stage tracked files
hug aa               # Stage everything
hug us <files>       # Unstage files`

```

#### 🌿 Branching (`b`)

```shell
`hug b <branch>       # Switch to branch
hug bs               # Switch back to previous branch
hug bc <branch>      # Create and switch
hug bl               # List branches
hug bdel <branch>    # Delete branch`

```

### Full Command List

<details>

<summary>Click to expand all commands</summary>

#### Logging & History


```shell
`hug l                 # Log one-line with graph
hug ll                # Log with date, author, message
hug la                # All branches
hug lf <term>         # Search commits by message
hug lc <code>         # Search commits by code changes`

```

#### File Operations

```shell
`hug fl <file>         # Full file history with diffs
hug fh <file>         # Compact file history
hug fblame <file>     # Who changed what line
hug fcon <file>       # List contributors to file`

```

#### Stashing


```shell
`hug ssave             # Quick stash
hug ssavea "msg"      # Stash with message
hug sls               # List stashes
hug spop              # Pop stash with preview
hug sclear            # Clear all stashes`

```

#### Tagging


```shell
`hug t "pattern"       # List tags matching pattern
hug tc <tag>          # Create lightweight tag
hug ta <tag> "msg"    # Create annotated tag
hug ts <tag>          # Show tag details
hug tp                # Push tags to remote`

```

</details>

---

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

---

## Roadmap

-    **Mercurial Support** - Full compatibility with `hg` commands
-    **Sapling Support** - Meta's next-gen VCS
-    **Interactive Mode** - TUI with visual diff preview
-   \[\] **AI Integration** - Smart commit suggestions
-    **GUI Frontend** - Visual interface for complex operations
-   \[\] **Plugin System** - Custom command extensions

