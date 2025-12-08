# Tag Management Commands

Hug SCM provides comprehensive tag management with interactive browsing, smart defaults, and safety features. The enhanced tag commands follow the same patterns as branch and worktree commands for consistency, while maintaining backward compatibility with existing aliases.

## Enhanced Commands (Scripts)

### `hug t` - Interactive Tag Browser

Interactive tag browser with selection and actions.

```bash
# Interactive tag browser
hug t

# Checkout specific tag directly
hug t v1.0.0

# Show tag details
hug t --action show v1.0.0

# Delete tag interactively
hug t --action delete v1.0.0

# Filter by tag type
hug t --type annotated

# Filter by pattern
hug t --pattern "v1.*"
```

**Features:**
- Interactive selection with gum (if available)
- Type indicators: `[L]` lightweight, `[A]` annotated, `[S]` signed
- Remote status awareness
- Action menu: checkout, show, delete
- Search and filtering capabilities

### `hug tl` - Enhanced Tag List

List tags with type indicators and formatting.

```bash
# List all tags with type indicators
hug tl

# List with remote status
hug tl --remote

# List in JSON format
hug tl --json

# Search for tags by commit message, name, or hash
hug tl "fix"                     # Find tags related to fixes
hug tl "release" "v1"           # Multiple search terms
hug tl 67fc1bd                  # Find tags with this hash in their details

# List without type indicators
hug tl --no-type
```

### `hug twp` - Tags Which Point to Commit

Find tags that directly point to a specific commit or object.

```bash
# Find tags pointing to HEAD
hug twp

# Find tags pointing to specific commit
hug twp 67fc1bd

# Find tags pointing to branch tip
hug twp main
```

**Output Format:**
```
* 67fc1bd 1.0.0 [L] fix: make git-tc handle non-interactive environments ...
  5890587 hug-backups/test-tag-backup-20251206-200825 [L] fix: remove local declarations...
```

### `hug tll` - Detailed Tag List

List tags with full information and annotations.

```bash
# Detailed list with all information
hug tll

# Filter by tag type
hug tll --type annotated
hug tll --type signed
hug tll --type lightweight

# Output in JSON format
hug tll --json

# Show tags matching pattern
hug tll "release-*"
```

**Output Format:**
```
v1.1.0 (annotated) [CURRENT] [REMOTE]
  Commit: abc1234
  Subject: Release v1.1.0
  Tagged: 2025-12-06 19:18:55 -0300
  Tagger: Test User <test@example.com>
  Signature: Verified

v1.0.0 (lightweight)
  Commit: def5678
  Subject: Initial commit
```

### `hug tc` - Interactive Tag Creation

Create tags with smart defaults and interactive prompts.

```bash
# Interactive tag creation
hug tc

# Create lightweight tag
hug tc v1.0.0

# Create annotated tag with message
hug tc -a v1.0.0 "Release version 1.0.0"

# Create signed tag
hug tc -s v1.0.0 -m "Release v1.0.0"

# Tag specific commit
hug tc v1.0.0 HEAD~5

# Force overwrite existing tag
hug tc -f v1.0.0

# Interactive mode with pre-filled name
hug tc --interactive v1.0.0
```

**Interactive Features:**
- Target commit selection (defaults to HEAD)
- Tag name suggestions (version increment, date-based, branch-based)
- Tag type selection (lightweight/annotated/signed)
- Message composition for annotated tags
- Optional remote push

### `hug tdel` - Interactive Tag Deletion

Delete tags with safety features and confirmations.

```bash
# Interactive tag deletion
hug tdel

# Delete specific tag
hug tdel v1.0.0

# Delete without confirmation
hug tdel -f v1.0.0

# Delete from remote as well
hug tdel -r v1.0.0

# Preview deletions without executing
hug tdel --dry-run

# Delete multiple tags
hug tdel --multi

# Filter by type
hug tdel --type annotated
```

**Safety Features:**
- Confirmation prompts
- Backup creation before deletion
- Remote deletion warnings
- Dry-run mode for preview
- Multi-tag support

## Legacy Commands (Aliases)

These commands remain available for backward compatibility:

| Command | Description |
|---------|-------------|
| `hug ts <tag>` | Show tag details |
| `hug tr <old> <new>` | Rename tag |
| `hug tm <tag> [commit]` | Move tag to different commit |
| `hug tma <tag> <message> [commit]` | Move and re-annotate tag |
| `hug tpush [tags...]` | Push tags to remote |
| `hug tpull` | Fetch tags from remote |
| `hug tpullf` | Force fetch and prune tags |
| `hug tdelr <tag>` | Delete remote tag |
| `hug tco <tag>` | Checkout tag |
| `hug twc [commit]` | Tags containing commit |
| `hug twp [object]` | Tags pointing to object |

## Tag Types

### Lightweight Tags
- Simple pointers to commits
- No metadata or messages
- Fast and minimal
- Created with: `hug tc <tag> <commit>`

**Example:**
```bash
hug tc v1.0.0 HEAD
```

### Annotated Tags
- Full tag objects with metadata
- Include message, author, date
- Recommended for releases
- Created with: `hug tc -a <tag> -m "message" <commit>`

**Example:**
```bash
hug tc -a v1.0.0 -m "Release version 1.0.0"
```

### Signed Tags
- Annotated tags with GPG signature
- Cryptographically verifiable
- For security-critical releases
- Created with: `hug tc -s <tag> -m "message" <commit>`

**Example:**
```bash
hug tc -s v1.0.0 -m "Release version 1.0.0"
```

## Visual Indicators

When using enhanced commands, tags are marked with type indicators:

- `[L]` - Lightweight tag
- `[A]` - Annotated tag
- `[S]` - Signed tag
- `*` - Current tag (when checked out)
- `[REMOTE]` - Tag exists on remote

## Workflows

### Basic Release Workflow

```bash
# 1. Ensure your code is ready
hug s
hug ll

# 2. Create release tag
hug tc -a v1.0.0 -m "Release version 1.0.0"

# 3. Push tag to remote
# (Say yes when prompted to push during creation)
# Or push manually:
hug tpush v1.0.0
```

### Browse and Checkout Tags

```bash
# 1. Browse available tags with indicators
hug tl

# 2. See detailed information
hug tll

# 3. Interactive browser
hug t

# 4. Checkout specific tag
hug t v1.0.0
```

### Cleanup Old Tags

```bash
# 1. Browse tags to identify what to delete
hug tll --type annotated

# 2. Preview deletions
hug tdel --dry-run --pattern "old-*"

# 3. Delete with backup and confirmation
hug tdel --pattern "old-*"
```

## Advanced Usage

### Pattern Filtering and Search

```bash
# Search by commit message content
hug tl "fix"                    # Tags fixing issues
hug tl "feature" "add"         # Tags adding features
hug tl "release"               # Release-related tags

# Search by tag name
hug tl "backup"                # Tags containing "backup"
hug tl "v1.*"                  # Tags starting with "v1"

# Search by commit hash
hug tl "67fc1bd"               # Tags pointing to specific commit
hug tl "a55c7d7"               # Another specific commit

# Multiple search terms (OR logic)
hug tl "fix" "release"          # Tags with either "fix" OR "release"
```

### JSON Output

For programmatic use:

```bash
# Simple JSON
hug tl --json

# Detailed JSON
hug tll --json

# Example output
[
  {
    "name": "v1.0.0",
    "hash": "abc1234",
    "type": "annotated",
    "subject": "Release version 1.0.0",
    "current": false,
    "remote": true
  }
]
```

### Type-Specific Operations

```bash
# List only annotated tags (good for releases)
hug tll --type annotated

# Delete only lightweight tags (temporary tags)
hug tdel --type lightweight --multi

# Browse only signed tags (security-focused)
hug t --type signed
```

## Migration from Git Commands

| Git Command | Hug Equivalent | Notes |
|-------------|---------------|--------|
| `git tag` | `hug tl` | Enhanced with type indicators |
| `git tag -l` | `hug tl` | Same functionality with better formatting |
| `git tag -a` | `hug tc -a` | Interactive with smart defaults |
| `git tag -d` | `hug tdel` | Safety features and backups |
| `git checkout <tag>` | `hug t <tag>` | Interactive selection available |
| `git show <tag>` | `hug ts <tag>` | Same functionality |

## Best Practices

- **Use annotated tags for releases**: Annotated tags (`hug tc -a`) are recommended for version releases because they include metadata about who tagged and when.
- **Use lightweight tags for temporary markers**: Lightweight tags (`hug tc`) are good for temporary bookmarks or personal references.
- **Never move or delete shared tags**: Once a tag is pushed and others have pulled it, avoid moving or deleting it. This causes confusion and breaks reproducibility.
- **Use semantic versioning**: Follow patterns like `v1.2.3` for consistent, sortable version tags.
- **Tag before pushing**: Create and verify your tag locally before pushing to remote.
- **Use interactive mode for releases**: `hug tc` provides smart suggestions and validation for release tagging.

## Configuration

Tag commands respect these environment variables:

- `HUG_FORCE`: Skip confirmation prompts
- `HUG_QUIET`: Suppress output
- `HUG_DISABLE_GUM`: Disable interactive UI

## Integration with Other Commands

Tag commands work seamlessly with other Hug commands:

```bash
# See commits in tag
hug l v1.0.0..HEAD

# Create branch from tag
hug bc feature-from-v1.0.0 v1.0.0

# Create worktree from tag
hug wtc hotfix-v1.0.0 v1.0.0

# Compare tags
hug ld v1.0.0 v1.1.0
```

## Troubleshooting

### Common Issues

**Command not found:**
```bash
# Ensure Hug is activated
source /path/to/hug/bin/activate
```

**No tags shown:**
```bash
# Check if repository has tags
git tag

# Tags might be filtered
hug tl --pattern "*"
```

**Permission denied on remote deletion:**
```bash
# Check remote permissions
git remote -v

# Delete local only first
hug tdel <tag>
# Then push manually if needed
git push origin --delete <tag>
```

### Getting Help

```bash
# Command-specific help
hug help t
hug help tl
hug help tll
hug help tc
hug help tdel

# General help
hug help
```

See also: [Branching](branching) for branch management, [Commits](commits) for creating commits to tag, and [Logging](logging) for viewing tagged history.