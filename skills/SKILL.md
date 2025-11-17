---
name: Hug SCM Repository Analysis
description: Expert-level Git repository investigation using Hug SCM tools for understanding code evolution, tracking down bugs, analyzing changes, and managing development workflows
version: 1.0.0
---

# Hug SCM Repository Analysis Skill

This skill equips AI assistants with expert knowledge for investigating Git repositories using Hug SCM's humane interface. Hug transforms complex Git operations into intuitive, safe commands organized by semantic prefixes.

## Core Philosophy

Hug follows a **safety-first, discoverability-focused** design:

- **Brevity Hierarchy**: Shorter commands = safer/more common (e.g., `hug a` stages tracked only; `hug aa` stages everything)
- **Progressive Destructiveness**: Commands escalate: `discard < wipe < purge < zap < rewind`
- **Semantic Prefixes**: Commands grouped by purpose (`h*` = HEAD, `w*` = working dir, `s*` = status, `b*` = branches, etc.)
- **Built-in Safety**: Destructive operations require confirmation unless forced with `-f`
- **Interactive Modes**: Most commands support Gum-based selection with `--` or `-i`

## When to Use This Skill

Use this skill when the user asks to:
- Investigate repository history or understand what changed
- Find when bugs were introduced or features were added
- Analyze file evolution or track authorship
- Prepare commits for review or clean up history
- Recover from mistakes or undo operations
- Understand project activity patterns

## Command Prefixes Quick Reference

| Prefix | Category | Use For |
|--------|----------|---------|
| `h*` | HEAD Operations | Undoing commits, squashing, reviewing recent changes |
| `w*` | Working Directory | Discarding changes, cleaning up, managing WIP |
| `s*` | Status & Staging | Checking state, staging changes, viewing diffs |
| `b*` | Branching | Creating, switching, listing, deleting branches |
| `c*` | Commits | Committing, amending, cherry-picking, moving commits |
| `l*` | Logging | Viewing history, searching commits, analyzing changes |
| `f*` | File Inspection | Blame, contributors, file history, when file was born |
| `t*` | Tagging | Creating, managing, querying tags |

## Essential Investigation Workflows

### 1. Understanding Repository State

**Start every investigation with a status check:**

```bash
# Quick overview
hug s

# Detailed status with untracked files
hug sla

# See what's staged vs unstaged
hug ss  # staged only
hug su  # unstaged only
hug sw  # working dir summary
```

### 2. Investigating Recent Changes

**When you need to know "what happened recently":**

```bash
# See files changed in last N commits
hug h files 5

# See files changed in last week (temporal!)
hug h files -t "1 week ago"

# See what hasn't been pushed yet
hug lol  # log outgoing long
```

**Understanding what changed:**

```bash
# Show last commit with stats
hug sh

# Show last commit with full diff
hug shp

# Show files changed in specific commit
hug shc a1b2c3d
```

### 3. Finding When Things Changed

**Critical skill: Use the right search command:**

- **`hug lf "keyword"`** - Search commit **messages** for keyword
- **`hug lc "code"`** - Search for **code changes** (Git's `-S` pickaxe)
- **`hug lcr "regex"`** - Search code changes with **regex** patterns

**Examples:**

```bash
# Find commits mentioning "fix bug"
hug lf "fix bug"

# Find when function "getUserById" was added/removed
hug lc "getUserById"

# Find when any import statement changed
hug lcr "^import.*from"

# Find when specific file was last modified
hug llf <file>
```

### 4. Deep File Investigation

**When debugging or understanding file evolution:**

```bash
# Find when file was created (hidden gem!)
hug fborn <file>

# See who wrote each line
hug fblame <file>

# Short blame (author + line only)
hug fb <file>

# List all contributors to a file
hug fcon <file>

# Count commits per author for a file
hug fa <file>

# Full file history
hug llf <file>
```

### 5. Temporal Analysis

**Powerful feature: Most commands support time-based queries:**

```bash
# What changed in last 3 days?
hug h files -t "3 days ago"

# Commits from last week
hug l --since="1 week ago"

# Date range
hug ld "2024-01-01" "2024-01-31"
```

## Safety Features to Leverage

### Auto-Backups

**All destructive HEAD operations create automatic backups:**

```bash
# These commands auto-create hug-backup-* branches
hug h back
hug h rollback
hug h rewind
hug h squash

# List backup branches
hug bl | grep backup

# Restore from backup if needed
hug b <backup-branch-name>
```

### Dry-Run Everything

**ALWAYS preview destructive operations first:**

```bash
# Preview before executing
hug w zap-all --dry-run
hug h rollback --dry-run
hug w purge --dry-run

# Then execute with -f to skip confirmation
hug w zap-all -f  # after reviewing dry-run output
```

### Interactive Selection

**Most commands support interactive file/branch/commit selection:**

```bash
# Use -- for interactive selection with Gum
hug lc "import" --          # select file to search in
hug w discard --            # select files to discard
hug bdel --                 # select branch to delete

# --browse-root for full repo scope (default: current dir)
hug lc "import" --browse-root
```

## Common Investigation Patterns

### Pattern 1: Bug Investigation

**User reports**: "Feature X broke recently"

**Investigation flow:**

```bash
# 1. Find file/files involved
hug lf "feature X"           # search commit messages
hug lc "featureXFunction"    # search code changes

# 2. Check when file last changed
hug fborn <file>             # when was it created?
hug h steps <file>           # how many commits since change?

# 3. View file history
hug llf <file>               # see all commits

# 4. Examine suspect commits
hug shp <commit-hash>        # full diff
hug shc <commit-hash>        # files changed

# 5. Check related changes
hug h files <commit-hash>    # what else changed with it?
```

### Pattern 2: Understanding Unpushed Work

**User asks**: "What am I about to push?"

```bash
# See local-only commits
hug lol

# Or shorter version
hug lo

# See files in local commits
hug h files -u               # -u for upstream comparison

# Review before pushing
hug l @{u}..HEAD             # commits ahead of upstream
```

### Pattern 3: Finding Hot Spots

**User asks**: "Which files change most often?"

```bash
# Recent activity
hug h files 50               # files in last 50 commits

# By time period
hug h files -t "1 month ago"

# For specific directory
cd src/
hug l --since="1 month ago" -- .
```

### Pattern 4: Authorship Analysis

**User asks**: "Who works on this code?"

```bash
# Contributors to specific file
hug fcon <file>

# Commit counts per author
hug fa <file>

# Commits by specific author
hug lau "Author Name"

# Date range for author
hug lau "Author Name" --since="1 month ago"
```

## Working with Branches

### Branch Investigation

```bash
# Current branch status
hug b

# List all branches with tracking info
hug bla

# Which branches contain a commit?
hug bwc <commit>

# Which branches point at HEAD?
hug bwp

# Which branches are merged?
hug bwm

# Which branches are NOT merged?
hug bwnm
```

### Branch Queries (Advanced)

```bash
# Tags/branches containing commit
hug bwc <commit>             # branches which contain
hug twc <commit>             # tags which contain

# Tags/branches pointing at commit
hug bwp <commit>             # branches which point
hug twp <commit>             # tags which point
```

## Advanced Investigation Techniques

### 1. Combining Commands for Insights

```bash
# Find all commits in feature branch
hug l main..feature-branch

# See what would merge
hug m feature-branch --dry-run

# Compare branches
hug l branch1..branch2
```

### 2. Using Git Aliases (when needed)

Hug preserves Git aliases, so you can still use:

```bash
# These work through Hug
hug l --all                  # all branches log
hug ll --all                 # detailed all branches
hug la                       # shortcut for above
```

### 3. Temporal Precision

```bash
# Exact time specifications
hug h files -t "2024-01-15 14:30"
hug h files -t "yesterday"
hug h files -t "3 hours ago"

# Relative specifications work
hug ld "last monday" "friday"
```

## Important Caveats and Limitations

### When to Use Raw Git

Hug doesn't cover every Git operation. Use raw Git for:

- Submodule operations
- Worktree management
- Advanced reflog queries
- Bisect operations
- Filter-branch/filter-repo

### Understanding Hug's Safety Trade-offs

1. **Confirmations slow down scripts**: Use `-f` or `HUG_FORCE=true` for automation
2. **Interactive mode requires Gum**: Falls back gracefully, but install Gum for best experience
3. **Some operations are intentionally verbose**: This prevents accidents

### Read-Only Investigation Commands

These are always safe - no confirmations needed:

- All `l*` logging commands
- All `f*` file inspection commands
- All `s*` status commands
- Most `h files` and `h steps` commands
- Branch listing (`bl`, `bla`, `blr`)

## Integration with MCP Server

When using the Hug SCM MCP server, these tools are available:

- `hug_status` → `hug s` or `hug sla`
- `hug_log` → `hug l` with filters
- `hug_h_files` → `hug h files` (supports temporal, upstream)
- `hug_h_steps` → `hug h steps` (for precise navigation)
- `hug_show_diff` → `hug ss`, `hug su`, `hug sw`
- `hug_branch_list` → `hug bl`, `hug bla`

**The MCP server exposes read-only operations** for safe AI investigation.

## Learning More

For detailed command documentation:
- [Working Directory Commands](../docs/commands/working-dir.md)
- [HEAD Operations](../docs/commands/head.md)
- [Status & Staging](../docs/commands/status-staging.md)
- [Branching](../docs/commands/branching.md)
- [Logging](../docs/commands/logging.md)
- [File Inspection](../docs/commands/file-inspection.md)

For workflow examples:
- [Practical Workflows](../docs/practical-workflows.md)
- [Cookbook Recipes](../docs/cookbook.md)

## Quick Command Cheatsheet

```bash
# Investigation Starters
hug s                        # what's changed?
hug sla                      # full status
hug h files 10               # recent file changes
hug lol                      # what will push?

# Search Operations
hug lf "keyword"             # search messages
hug lc "code"                # search code changes
hug lcr "regex"              # regex code search
hug llf <file>               # file history

# Deep Inspection
hug fborn <file>             # when created
hug fblame <file>            # who wrote what
hug fcon <file>              # contributors
hug h steps <file>           # commits since change

# Time-Based
hug h files -t "3 days ago"  # recent changes
hug ld "monday" "friday"     # date range
hug lau "Author" --since="1 month ago"

# Branch Queries
hug bwc <commit>             # which branches contain?
hug bwm                      # which merged?
hug bwnm                     # which not merged?
```

## Tips for AI Assistants

1. **Always start with status** - `hug s` or `hug sla` before any investigation
2. **Use temporal queries** - More intuitive than commit counts (`-t "3 days ago"`)
3. **Leverage file birth** - `hug fborn` is faster than manual log walking
4. **Combine commands** - Chain investigations from broad to specific
5. **Preview first** - Use `--dry-run` before suggesting destructive operations
6. **Explain the prefix** - Help users learn the mnemonic system
7. **Suggest interactive mode** - Use `--` for Gum selection when multiple options
8. **Check for backups** - Remind users about auto-backups for HEAD operations

## Next Steps

For specific workflows, see the guide files:
- [Bug Hunting Guide](./guides/bug-hunting.md) - Finding when bugs were introduced
- [Pre-Commit Review Guide](./guides/pre-commit-review.md) - Reviewing changes before commit
- [Branch Analysis Guide](./guides/branch-analysis.md) - Understanding branch differences
- [History Cleanup Guide](./guides/history-cleanup.md) - Preparing for PR/merge
