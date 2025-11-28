# Worktree Management

Worktrees allow you to work on multiple branches simultaneously without context switching overhead. Each worktree has its own working directory but shares the same repository history.

## Commands Overview

| Command | Purpose | Pattern |
|---------|---------|---------|
| `hug wt` | Interactive worktree management | Like `hug b` |
| `hug wtl` | List worktrees (short format) | Like `hug bl` |
| `hug wtll` | List worktrees (long format) | Like `hug bll` |
| `hug wtc` | Create worktree for branch | Like `hug bc` |
| `hug wtdel` | Remove worktree safely | Like `hug bdel` |

## Core Concepts

### What is a Worktree?

A worktree is a separate working directory linked to the same repository. This enables:

- **Parallel Development**: Work on multiple features simultaneously
- **Context Isolation**: Each branch has its own working directory and staged changes
- **Fast Switching**: No need to stash changes when switching branches
- **Safe Experimentation**: Test changes without affecting your main work

### Worktree States

- **[CURRENT]**: The worktree you're currently in
- **[DIRTY]**: Worktree has uncommitted changes
- **[LOCKED]**: Worktree is locked (cannot be removed)

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
- Shows current worktree with `[CURRENT]` marker
- Supports keyboard selection and quick navigation

### `hug wtl` - List Worktrees (Short Format)

Lists worktrees in a compact, scannable format.

```bash
hug wtl [OPTIONS] [SEARCH_TERM]
```

**Options:**
- `-h, --help`: Show help message
- `--json`: Output in JSON format

**Examples:**
```bash
hug wtl                              # List all worktrees
hug wtl feature                      # Show worktrees containing "feature"
hug wtl /home/user/project           # Show worktrees containing that path
hug wtl --json                       # Output in JSON format
```

**Output Format:**
```
Worktrees:
* [DIRTY] main                 (1b87e92) ~/IdeaProjects/hug-scm
feature-auth         (a3f2b1c) ~/IdeaProjects/worktrees-hug-scm/feature-auth
hotfix-patch         (d8e9f0a) ~/IdeaProjects/worktrees-hug-scm/hotfix-patch
```

### `hug wtll` - List Worktrees (Long Format)

Lists worktrees with detailed information including commit subjects.

```bash
hug wtll [OPTIONS] [SEARCH_TERM]
```

**Options:**
- `-h, --help`: Show help message
- `--json`: Output in JSON format

**Examples:**
```bash
hug wtll                             # List all worktrees with details
hug wtll feature                     # Show worktrees containing "feature"
hug wtll --json                      # Output detailed information in JSON format
```

**Output Format:**
```
Worktrees (long format):
* [DIRTY] main                 1b87e92 (~/IdeaProjects/hug-scm)
  docs: update branching command documentation for search filtering feature
  Status: Modified ! (1 staged, 2 unstaged) ! | Locked: No

feature-auth         a3f2b1c (~/IdeaProjects/worktrees-hug-scm/feature-auth)
  feat: implement OAuth authentication flow
  Status: Clean ✓ | Locked: No
```

### `hug wtc` - Create Worktree

Creates a new worktree for an existing branch.

```bash
hug wtc <branch> [path] [options]
```

**Arguments:**
- `<branch>`: Name of existing branch to create worktree for
- `[path]`: Custom path for worktree (optional, auto-generated if not provided)

**Options:**
- `-f, --force`: Skip confirmation prompts
- `--dry-run`: Show what would be done without creating the worktree
- `-h, --help`: Show help message

**Examples:**
```bash
hug wtc feature-auth                           # Create worktree with auto-generated path
hug wtc feature-auth ~/work/feature            # Create worktree at custom path
hug wtc feature-auth --dry-run                 # Preview creation without doing it
hug wtc feature-auth -f                        # Create without confirmation
```

**Auto-generated Path Pattern:**
```
../worktrees-<repo-name>/<branch-name>
```

### `hug wtdel` - Remove Worktree

Safely removes a worktree after checking for uncommitted changes.

```bash
hug wtdel [path] [options]
```

**Arguments:**
- `[path]`: Path to worktree to remove (optional, shows interactive menu if not provided)

**Options:**
- `-f, --force`: Skip confirmation prompts
- `--dry-run`: Show what would be removed without doing it
- `-h, --help`: Show help message

**Examples:**
```bash
hug wtdel                              # Show interactive menu of worktrees to remove
hug wtdel ~/project-feature            # Remove specific worktree
hug wtdel ~/project-feature --dry-run  # Preview removal without doing it
hug wtdel ~/project-feature -f         # Remove without confirmation
```

**Safety Features:**
- Checks for uncommitted changes before removal
- Requires confirmation unless `--force` is used
- Prevents removal of current worktree
- Shows detailed removal summary

## JSON Output

Both `hug wtl` and `hug wtll` support `--json` output for programmatic use:

```json
{
  "worktrees": [
    {
      "path": "/home/user/project",
      "branch": "main",
      "commit": "1b87e92",
      "dirty": true,
      "locked": false,
      "current": true
    },
    {
      "path": "/home/user/worktrees-project/feature-auth",
      "branch": "feature-auth",
      "commit": "a3f2b1c",
      "dirty": false,
      "locked": false,
      "current": false
    }
  ],
  "current": "/home/user/project",
  "count": 2
}
```

## Workflows

### Parallel Feature Development

```bash
# Create worktrees for multiple features
hug wtc feature-auth
hug wtc feature-ui

# Work on authentication in isolation
cd ~/workspaces-project/feature-auth
# ... make changes and commits

# Switch to UI work without stashing
hug wt ~/workspaces-project/feature-ui
# ... make changes and commits

# Switch back to main
hug wt ~/project
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
- Let Hug auto-generate paths when possible (`../worktrees-<repo>/`)
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
