# Worktree Management

Worktrees allow you to work on multiple branches simultaneously without context switching overhead. Each worktree has its own working directory but shares the same repository history.

## Commands Overview

| Command | Purpose | Pattern |
|---------|---------|---------|
| `hug wt` | Interactive worktree management | Like `hug b` |
| `hug wtl` | List worktrees (short format) | Like `hug bl` |
| `hug wtll` | List worktrees (long format) | Like `hug bll` |
| `hug wtsh` | Show detailed worktree information | Like `hug sh` |
| `hug wtc` | Create worktree for branch | Like `hug bc` |
| `hug wtdel` | Remove worktree safely | Like `hug bdel` |
| `hug wtprune` | Clean up stale worktree metadata | Maintenance utility |

## Core Concepts

### What is a Worktree?

A worktree is a separate working directory linked to the same repository. This enables:

- **Parallel Development**: Work on multiple features simultaneously
- **Context Isolation**: Each branch has its own working directory and staged changes
- **Fast Switching**: No need to stash changes when switching branches
- **Safe Experimentation**: Test changes without affecting your main work

### Worktree States

- **`+`** (dirty): Worktree has uncommitted changes
- **`#`** (locked): Worktree is locked (cannot be removed)
- **`*`** prefix on branch name: The worktree you're currently in
- **`@ detached`** in branch column: Worktree is in detached HEAD state

## Commands

### `hug wt` - Interactive Worktree Management

Interactive command for listing and switching between worktrees.

```bash
hug wt [<path>] [options]
```

**Examples:**
```bash
hug wt                    # Show interactive menu of worktrees
hug wt ~/project-feature  # Switch to specific worktree path
hug wt --summary          # Show non-interactive worktree summary
hug wt --json             # Output worktree information in JSON format
```

**Interactive Menu:**
- Lists all available worktrees with status indicators
- Shows current worktree with `*` prefix on branch name
- Supports keyboard selection and quick navigation

### `hug wtl` - List Worktrees (Short Format)

Lists worktrees in a compact, scannable format.

```bash
hug wtl [OPTIONS] [SEARCH_TERMS...]
```

**Options:**
- `-h, --help`: Show help message
- `--json`: Output in JSON format
- `-q, --quiet`: Suppress legend line
- `-b, --branch NAME`: Filter by exact branch name (repeatable, OR logic)

**Filtering:**
- Positional args: substring match on path or branch (case-insensitive, OR logic)
- `-b, --branch`: exact match on branch name (case-sensitive, repeatable, OR logic)
- Combined: both filters must match (AND logic)

**Examples:**
```bash
hug wtl                              # List all worktrees
hug wtl feature                      # Substring: worktrees containing "feature"
hug wtl feature auth                 # Substring: "feature" OR "auth"
hug wtl -b main                      # Exact branch "main" only
hug wtl -b main -b dev               # Exact: "main" OR "dev"
hug wtl feat -b main                 # Substring "feat" AND exact branch "main"
hug wtl --json                       # Output in JSON format
```

**Output Format:**
```
Worktrees:
  + dirty  # locked  * current

.+ *main                 (1b87e92) ~/IdeaProjects/hug-scm
..  feature-auth         (a3f2b1c) ~/IdeaProjects/hug-scm.WT.feature-auth
..  hotfix-patch         (d8e9f0a) ~/IdeaProjects/hug-scm.WT.hotfix-patch
```

### `hug wtll` - List Worktrees (Long Format)

Lists worktrees with detailed information including commit subjects.

```bash
hug wtll [OPTIONS] [SEARCH_TERMS...]
```

**Options:**
- `-h, --help`: Show help message
- `--json`: Output in JSON format
- `-b, --branch NAME`: Filter by exact branch name (repeatable, OR logic)

**Examples:**
```bash
hug wtll                             # List all worktrees with details
hug wtll feature                     # Substring: worktrees containing "feature"
hug wtll feature auth                # Substring: "feature" OR "auth"
hug wtll -b main                     # Exact branch "main" only
hug wtll --json                      # Output detailed information in JSON format
```

**Output Format:**
```
Worktrees (long format):
  + dirty  # locked  * current

.+ *main                 1b87e92 (~/IdeaProjects/hug-scm)
  docs: update branching command documentation for search filtering feature
  Status: Modified ! (1 staged, 2 unstaged) ! | Locked: No

..  feature-auth         a3f2b1c (~/IdeaProjects/hug-scm.WT.feature-auth)
  feat: implement OAuth authentication flow
  Status: Clean ✓ | Locked: No
```

### `hug wtsh` - Show Worktree Details

Displays detailed information about worktrees in a comprehensive, readable format with tree-style layout.

```bash
hug wtsh [OPTIONS] [SEARCH_TERMS...]
hug wtsh --           # Interactive worktree selection
```

**Options:**
- `-h, --help`: Show help message
- `-a, --all`: Show all worktrees (preserves current behavior)
- `-b, --branch NAME`: Filter by exact branch name (repeatable, OR logic)

**Behavior:**

**DEFAULT (no arguments):**
  Shows details for the CURRENT worktree only. This provides focused information
  about your current working context.

**--all FLAG:**
  Shows details for ALL worktrees (preserves existing hug wtsh behavior).

**-- FLAG (interactive mode):**
  Presents an interactive menu to select which worktree to display.
  Uses gum filter for enhanced selection when available.

**SEARCH TERMS:**
  Positional args: substring match on path or branch (case-insensitive, OR logic)
  `-b, --branch`: exact match on branch name (case-sensitive, repeatable, OR logic)
  Combined: both filters must match (AND logic)

**Examples:**
```bash
hug wtsh                   # Current worktree only (new default)
hug wtsh --all             # All worktrees (preserves current behavior)
hug wtsh -a                # All worktrees (short alias for --all)
hug wtsh --                # Interactive worktree selection

# Substring search (positional args)
hug wtsh feature           # Substring: worktrees containing "feature"
hug wtsh feature auth      # Substring: "feature" OR "auth"
hug wtsh /path/to/project  # Substring: match by path

# Exact branch filtering
hug wtsh -b main           # Exact branch "main" only
hug wtsh -b main -b dev    # Exact: "main" OR "dev"

# Combined (AND logic)
hug wtsh feat -b main      # Substring "feat" AND exact branch "main"
```

**Output Format:**
```
Worktree Summary
───────────────────────
Current: ~/IdeaProjects/hug-scm

Worktrees (3 total)
───────────────────────

.+ ~/IdeaProjects/hug-scm (*test-new-worktree)
├─ Commit: deab0e2 fix: make hug wt actually change working directory (13 hours ago)
├─ Author: Elifarley C
├─ Branch: *test-new-worktree (no remote)
├─ Path: /home/ecc/IdeaProjects/hug-scm
├─ Status: Dirty (2 files changed: 0 staged, 2 unstaged)
└─ Config: Standard worktree (detached: no)

..  ~/workspaces-project/feature-auth (feature-auth)
├─ Commit: a3f2b1c feat: implement OAuth authentication (2 days ago)
├─ Author: Jane Smith
├─ Branch: feature-auth (origin/feature-auth ↑2)
├─ Path: /home/ecc/workspaces-project/feature-auth
├─ Status: Clean
└─ Config: Standard worktree (detached: no)

.#  ~/workspaces-project/temp (@ detached)
├─ Commit: abc1234 fix: security issue (1 week ago)
├─ Author: Bob Wilson
├─ Branch: @ detached
├─ Path: /home/ecc/workspaces-project/temp
├─ Status: Clean
└─ Config: Locked worktree (detached: yes)
```

**Status Indicators:**
```
  +  dirty (uncommitted changes)
  #  locked
  *  prefix on branch = current worktree
  @  prefix on branch = detached HEAD
  .  (inactive)
```

**Information Displayed:**
- Worktree path and branch name with commit hash
- Commit subject, author, and relative date
- Branch information with remote tracking details
- Working directory status with file change counts
- Worktree configuration (locked, detached state)

**Search Filtering:**
- Positional args: substring match on path or branch (case-insensitive, OR logic)
- `-b, --branch`: exact match on branch name (case-sensitive, repeatable, OR logic)
- Combined: both filters must match (AND logic)
- Error if no worktrees match the filters

```

### `hug wtc` - Create Worktree

Creates a new worktree for an existing or new branch.

```bash
hug wtc <branch> [path] [options]
```

**Arguments:**
- `<branch>`: Name of branch to create worktree for (existing or new)
- `[path]`: Custom path for worktree (optional, auto-generated if not provided)

**Options:**
- `-f, --force`: Skip confirmation prompts and allow creating worktrees for branches checked out elsewhere
- `-y, --yes`: Skip confirmation prompts (NOT sufficient for blocked states requiring `-f`)
- `--dry-run`: Show what would be done without creating the worktree (composes with `-f`)
- `--new, -B, --with-branch`: Automatically create branch if it doesn't exist
- `--base POINT`: Create the new branch from a specific commit, branch, tag, or ref (implies `--new`)
- `-p, --path PATH`: Explicit worktree path (alternative to positional arg)
- `-q, --quiet`: Suppress summary and informational output
- `--json`: Emit results as JSON on stdout
- `-h, --help`: Show help message

**Examples:**
```bash
hug wtc feature-auth                           # Create worktree with auto-generated path
hug wtc feature-auth ~/work/feature            # Create worktree at custom path
hug wtc feature-auth --new                     # Create new branch and worktree
hug wtc feature-auth -B                        # Same as --new
hug wtc feature-auth --dry-run -f              # Preview with force semantics
hug wtc feature-auth -f                        # Create without confirmation
hug wtc hotfix-123 --base v2.0                 # Create branch from tag
hug wtc scripty --new --json -y                # Scriptable JSON output to stdout
```

**Auto-generated Path Pattern:**
```
../<repo-name>.WT.<branch-name>
```

### `hug wtdel` - Remove Worktree

Safely removes one or more worktrees after validation.

```bash
hug wtdel [branch...] [options]
hug wtdel -p <path> [options]
```

**Arguments:**
- `[branch...]`: One or more branch names (repeatable for batch)
- `-p, --path PATH`: Target by filesystem path (repeatable for batch)

**Options:**
- `-f, --force`: Skip confirmation prompts and remove even with uncommitted changes
- `-y, --yes`: Auto-confirm routine prompts (NOT sufficient for removal — use `-f`)
- `--dry-run`: Show what would be removed without doing it
- `-B, --with-branch`: Also delete the associated branch after removing the worktree
- `-q, --quiet`: Suppress summary and informational output
- `--json`: Emit results as JSON on stdout
- `-h, --help`: Show help message

**Examples:**
```bash
hug wtdel                                     # Interactive selection
hug wtdel feature-auth                        # Remove worktree for branch
hug wtdel feat-1 feat-2 feat-3                # Batch remove by branch names
hug wtdel feature-auth --dry-run              # Preview removal
hug wtdel feature-auth -f                     # Force remove without confirmation
hug wtdel -p /path/to/worktree                # Remove by path
hug wtdel feat-1 feat-2 -B --force            # Batch remove worktrees + branches
hug wtdel feat-1 --json                       # Machine-readable result
```

**Safety Features:**
- Validates ALL targets before removing ANY (atomic batch semantics)
- Checks for uncommitted changes before removal
- Requires confirmation unless `--force` is used
- Prevents removal of current worktree
- Shows pre-flight plan before execution
- Scoped prune: only prunes the target stale entry, not unrelated ones
- Never falls back to blind filesystem deletion

### `hug wtprune` - Clean Up Stale Worktree Metadata

Cleans up orphaned worktree metadata from Git's internal database. Orphaned worktrees are references to worktree directories that no longer exist on the filesystem.

```bash
hug wtprune [options]
```

**Options:**
- `-f, --force`: Skip confirmation prompts and prune all stale worktrees
- `--dry-run`: Show what would be pruned without actually doing it
- `-v, --verbose`: Show detailed output with progress information
- `-h, --help`: Show help message

**Examples:**
```bash
hug wtprune                               # Interactive pruning with confirmation
hug wtprune --dry-run                     # Preview what would be pruned
hug wtprune -f                            # Force prune without confirmation
hug wtprune --verbose                     # Detailed output with progress
```

**When to Use:**
- Worktree directories were manually deleted
- External processes removed worktree directories
- You want to clean up stale references after system maintenance
- Git worktree operations show references to non-existent directories

**Safety Features:**
- Never prunes current worktree or existing directories
- Shows exactly what will be pruned before doing it
- Requires confirmation before cleanup (unless `--force` is used)
- Supports `--dry-run` to preview changes

## JSON Output

`hug wtl`, `hug wtll`, `hug wtc`, and `hug wtdel` all support `--json` output for programmatic use. JSON is emitted on stdout with zero non-JSON bytes.

### wtl --json

```json
{
  "worktrees": [
    {
      "path": "/home/user/project",
      "branch": "main",
      "commit": "1b87e92",
      "dirty": true,
      "locked": false,
      "current": true,
      "missing": false,
      "dirty_details": "2 staged, 3 unstaged"
    },
    {
      "path": "/home/user/project.WT.feature-auth",
      "branch": "feature-auth",
      "commit": "a3f2b1c",
      "dirty": false,
      "locked": false,
      "current": false,
      "missing": false,
      "dirty_details": ""
    },
    {
      "path": "/home/user/project.WT.old-feature",
      "branch": "old-feature",
      "commit": "gone",
      "dirty": false,
      "locked": false,
      "current": false,
      "missing": true,
      "dirty_details": ""
    }
  ],
  "current": "/home/user/project",
  "count": 3
}
```

Fields unique to JSON (not shown in human output):
- `missing`: `true` when the worktree directory was deleted externally (stale metadata)
- `dirty_details`: Human-readable breakdown of dirty state (e.g. `"2 staged, 3 unstaged"`)

### wtc --json

```json
{"branch": "feature-auth", "path": "/home/user/project.WT.feature-auth", "created_branch": true, "base": "main", "start_point": "a3f2b1c"}
```

### wtdel --json

```json
{"dry_run": false, "targets": [{"spec": "feature-auth", "path": "/home/user/project.WT.feature-auth", "branch": "feature-auth", "state": "removed", "detail": ""}], "counts": {"removed": 1, "pruned": 0, "failed": 0}}
```

## Script-Friendly Output

Listing commands (`hug wtl`, `hug wtll`, `hug wtsh`) keep stdout clean so you can pipe or capture their output. Headers, legends, and status messages go to stderr.

```bash
# Capture listing for scripting
worktrees=$(hug wtl)
hug wtll | grep feature

# Suppress non-data output
hug wtl 2>/dev/null

# Get path for a specific branch (scriptable)
path=$(hug wtl -p -b feature-auth)

# Suppress summary chatter
hug wtc feature-auth --new -q -y
hug wtdel feature-auth -q

# Parse JSON output
hug wtl --json | python3 -m json.tool
hug wtc feature-auth --new --json | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['path'])"
```

Run `hug wtl --help` and see the CAPTURING OUTPUT section for details.

## Safety Model

Worktree commands use a three-tier safety model to balance usability and protection.

| Tier | Examples | `-y` | `-f` / `--force` |
|------|----------|------|-------------------|
| **Safe** | Create worktree for existing branch; confirm branch creation prompt | Answers yes | Not needed |
| **Warn** | Remove clean worktree; remove stale entry | Answers yes | Not needed |
| **Danger** | Remove dirty worktree; create worktree for branch checked out in main | Ignored | Required |

**Key rules:**
- `-y` auto-confirms routine prompts (safe and warn tiers). It does NOT authorize dangerous operations.
- `-f` authorizes danger-tier operations AND also answers routine confirmations.
- `-f` overrides blocked states (dirty worktree, branch checked out in main worktree).
- When safety blocks a `-y` operation, the exit code is `3` (blocked), not `1` (operational failure).

## Exit Codes

All worktree commands share a common exit code convention.

| Code | Meaning | Example |
|------|---------|---------|
| `0` | Success | `hug wtc feature-auth` |
| `1` | Operational error | `hug wtl -b nonexistent` (no matches) |
| `2` | Usage error (bad flags/arguments) | `hug wtc --unknown-flag` |
| `3` | Blocked by safety (use `-f`) | `hug wtdel dirty-wt -y` (needs `-f`) |

## Stale Worktrees

A stale worktree is one whose directory was removed externally (e.g. `rm -rf`) without using `hug wtdel`. Git's metadata still references the directory.

**Detection:**
- `hug wtl` shows `(gone)` instead of a commit hash for stale entries
- `hug wtl --json` includes `"missing": true` in the worktree object
- `hug wtl -e` (or `--existing`) excludes stale entries entirely

**Cleanup:**
- `hug wtdel <stale-branch>` prunes only that specific stale entry
- `hug wtprune` removes all stale entries at once

**Important:** removing one worktree no longer prunes unrelated stale entries. Pruning is scoped to the target.

## Deferred

- **`hug wtc --detach`**: Create a worktree without a branch (inspect a commit/tag without branch creation). Deferred — see [elifarley/hug-scm#177](https://github.com/elifarley/hug-scm/issues/177).

## Workflows

### Parallel Feature Development

```bash
# Create worktrees for multiple features
hug wtc feature-auth
hug wtc feature-ui

# Get overview of all worktrees and their status
hug wtsh

# Work on authentication in isolation
cd ~/workspaces-project/feature-auth
# ... make changes and commits

# Switch to UI work without stashing
hug wt ~/workspaces-project/feature-ui
# ... make changes and commits

# Switch back to main
hug wt ~/project

# Check current status of all worktrees
hug wtsh
```

### Hotfix Workflow

```bash
# Working on feature, urgent hotfix needed
hug wtc hotfix-security-patch

# Work on hotfix in isolation
cd ~/workspaces-project/hotfix-security-patch
# ... fix security issue, test, commit

# Merge hotfix to main, tag release
hug b main
hug bpull
hug m hotfix-security-patch main
hug t v1.2.1-hotfix

# Continue working on feature
hug wt ~/workspaces-project/feature-auth
```

### Experimental Work

```bash
# Try out experimental changes safely
hug wtc experiment-refactor

# Work on experimental changes
cd ~/workspaces-project/experiment-refactor
# ... make experimental changes

# If experiment fails:
hug wtdel ~/workspaces-project/experiment-refactor

# If experiment succeeds:
# Rebase and merge to main branch
hug b main
hug bpull
hug rb experiment-refactor main
```

## Best Practices

### Organization

**Consistent Naming:**
- Use descriptive branch names that translate to clear worktree paths
- Consider using prefixes: `feature/`, `bugfix/`, `hotfix/`, `experiment/`

**Path Management:**
- Let Hug auto-generate paths when possible (`../<repo>.WT.<branch>`)
- Keep worktree paths short and meaningful
- Use consistent base directory for all worktrees

### Safety

**Before Removing Worktrees:**
```bash
# Always check status first
hug wtll ~/project-feature

# Use dry-run to preview
hug wtdel ~/project-feature --dry-run

# Remove only when sure
hug wtdel ~/project-feature
```

**Clean Workflow:**
- Commit or stash changes before switching worktrees frequently
- Regular cleanup of completed feature worktrees
- Use `hug wtll --json` for automated cleanup scripts

### Performance

**For Large Repositories:**
- Limit the number of active worktrees (3-5 is usually sufficient)
- Remove worktrees for completed features promptly
- Consider using shallow clones for experimental worktrees

## Troubleshooting

### Common Issues

**"Cannot remove current worktree"**
```bash
# Solution: Switch to a different worktree first
hug wt ~/other-worktree
hug wtdel ~/current-worktree
```

**"Branch already checked out"**
```bash
# Check which worktree has the branch
hug wtll <branch-name>

# Switch to that worktree or remove it first
hug wt ~/worktree-with-branch
# or
hug wtdel ~/worktree-with-branch
```

**"Parent directory does not exist"**
```bash
# Create parent directory manually
mkdir -p ~/workspaces-your-project
hug wtc feature-branch
```

### Recovery

**If Worktree Directory is Deleted:**
```bash
# Prune the stale worktree reference
git worktree prune

# Verify with Hug
hug wt
```

**If Worktree Gets Corrupted:**
```bash
# Remove and recreate the worktree
hug wtdel ~/corrupted-worktree -f
hug wtc <branch-name>
```

## Integration with Other Hug Commands

Worktrees integrate seamlessly with other Hug commands:

- **Branch Management**: `hug b`, `hug bc`, `hug bdel` work within any worktree
- **Status/Staging**: `hug s`, `hug a`, `hug aa` operate on current worktree only
- **Committing**: `hug c`, `hug ca` work normally within each worktree
- **Pushing/Pulling**: `hug bpush`, `hug bpull` work from any worktree
- **Logging**: `hug ll`, `hug lf` show repository history from any worktree

## See Also

- [Branching Documentation](branching.md) - For creating and managing branches
- [Workflows Documentation](../workflows.md) - For complete development workflows
- [Command Map](../command-map.md) - For overview of all Hug commands
