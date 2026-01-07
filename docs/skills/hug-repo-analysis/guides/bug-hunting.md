# Bug Hunting Guide

This guide teaches systematic approaches for tracking down bugs using Hug SCM's investigation commands.

## The Bug Investigation Workflow

### Phase 1: Gather Information

**What you need to know:**
- When did the bug appear? (approximate timeframe)
- What files/features are affected?
- Any error messages or symptoms?

### Phase 2: Locate the Introduction Point

#### Strategy 1: Search Commit Messages

If the bug relates to a specific feature:

```bash
# Search for feature name in commits
hug lf "authentication" -i

# Search in specific file
hug lf "login" -- src/auth.js

# Interactive file selection
hug lf "user" --
```

#### Strategy 2: Search Code Changes

When you know the problematic code:

```bash
# Find when function was added/changed
hug lc "validatePassword"

# Case-insensitive search
hug lc "password" -i

# With patches to see context
hug lc "password" -p

# Interactive file selection
hug lc "password" --
```

#### Strategy 3: Use Regex for Patterns

For complex code patterns:

```bash
# Find when pattern was introduced
hug lcr "if.*null.*throw"

# Find TODO/FIXME comments
hug lcr "TODO|FIXME" -i

# Find specific class definitions
hug lcr "class \w+Controller"
```

### Phase 3: Narrow Down the Timeline

#### Use Temporal Queries

```bash
# What changed in last week?
hug h files -t "1 week ago"

# What changed since last release?
hug h files -t "2024-01-15"  # use release date

# Commits in date range
hug ld "last monday" "friday"
```

#### Find File's Last Change

```bash
# How many commits since file changed?
hug h steps src/auth.js

# When was file created?
hug fborn src/auth.js

# Full file history
hug llf src/auth.js
```

### Phase 4: Examine Suspect Commits

Once you've identified candidate commits:

```bash
# Show commit with stats
hug sh <commit-hash>

# Show full diff
hug shp <commit-hash>

# See what files changed together
hug shc <commit-hash>

# See all files in that timeframe
hug h files <commit-hash>
```

### Phase 5: Understand the Context

#### Who and Why

```bash
# See who wrote the code
hug fblame <file>

# Quick author check
hug fb <file>

# All contributors to file
hug fcon <file>

# Commits by suspected author
hug lau "Author Name"
```

#### What Changed Around It

```bash
# Files changed in same commit
hug h files 1 <commit-hash>

# Related commits nearby
hug l <commit-hash>~5..<commit-hash>~1
```

## Example Investigations

### Example 1: "Login stopped working yesterday"

```bash
# Step 1: Find recent changes to login
hug lf "login" --since="2 days ago"
hug lc "login" -t "2 days ago"

# Step 2: Check auth files
hug llf src/auth/login.js

# Step 3: Review suspects
hug shp a1b2c3d  # from step 1 results

# Step 4: Check related changes
hug h files a1b2c3d
```

### Example 2: "validateEmail function has wrong regex"

```bash
# Step 1: Find when validateEmail changed
hug lc "validateEmail"

# Step 2: See the actual change
hug lc "validateEmail" -p

# Step 3: Check file history
hug llf -- src/utils/validation.js

# Step 4: Who introduced it?
hug fblame src/utils/validation.js
```

### Example 3: "Performance degraded last month"

```bash
# Step 1: What changed in last month?
hug h files -t "1 month ago"

# Step 2: Look for performance-related commits
hug lf "performance\|slow\|optimize" -i --since="1 month ago"

# Step 3: Check specific files
hug lc "setTimeout\|setInterval" -t "1 month ago"

# Step 4: Review by author if suspected
hug lau "Suspect Author" --since="1 month ago"
```

## Advanced Techniques

### Binary Search with Git Bisect

While Hug doesn't wrap `git bisect`, you can prepare for it:

```bash
# Find good and bad commit range
hug l --oneline

# Then use git bisect
git bisect start
git bisect bad HEAD
git bisect good <known-good-commit>

# Test each commit, then:
git bisect good  # or bad
```

### Finding Related Files

```bash
# Find files that often change together
hug h files 50 | sort | uniq -c | sort -rn

# See what changed with suspect file
hug l --follow -- <file>
hug h files -t "1 month ago" | grep -A5 -B5 <suspect-file>
```

### Combining Multiple Searches

```bash
# Find intersection of searches
hug lf "feature" > /tmp/feature-commits
hug lc "problematicCode" > /tmp/code-commits
comm -12 <(sort /tmp/feature-commits) <(sort /tmp/code-commits)
```

## Common Pitfalls

### Pitfall 1: Searching Too Broadly

**Problem**: `hug lf "fix"` returns hundreds of results

**Solution**: Narrow with file or time:
```bash
hug lf "fix" -- src/specific/  # file scope
hug lf "fix" --since="1 week ago"  # time scope
```

### Pitfall 2: Missing Rename History

**Problem**: File was renamed, old changes not showing

**Solution**: Use `--follow` commands:
```bash
hug llf <current-filename>  # automatically follows renames
hug fborn <file>  # finds original creation even if renamed
```

### Pitfall 3: Ignoring Merge Commits

**Problem**: Bug came from merged branch

**Solution**: Check merge commits specifically:
```bash
hug l --merges --since="1 week ago"
hug shp <merge-commit>  # shows full merge diff
```

## Integration with Code Execution (MCP)

For complex analysis requiring data processing:

```typescript
// Find hot spots - files changed most in suspect period
const commits = await hug_log({
  count: 100,
  since: "1 month ago"
});

const fileChanges = new Map();
for (const commit of commits) {
  const files = await hug_h_files({ commit: commit.hash });
  files.forEach(f => {
    fileChanges.set(f, (fileChanges.get(f) || 0) + 1);
  });
}

// Show top 10 most-changed files
const hotSpots = Array.from(fileChanges.entries())
  .sort((a, b) => b[1] - a[1])
  .slice(0, 10);

console.log("Files changed most often:", hotSpots);
```

## Quick Reference

```bash
# Search Operations
hug lf "keyword"             # search messages
hug lc "code"                # search code changes
hug lcr "regex"              # regex code search

# Timeline Analysis
hug h files -t "3 days ago"  # recent changes
hug h steps <file>           # commits since file changed
hug ld "start" "end"         # date range

# File Investigation
hug fborn <file>             # when created
hug llf <file>               # full history
hug fblame <file>            # line-by-line authors
hug fcon <file>              # all contributors

# Commit Details
hug sh <hash>                # commit with stats
hug shp <hash>               # commit with diff
hug h files <hash>           # files in commit

# Author Analysis
hug lau "Author"             # commits by author
hug fa <file>                # author stats for file
```

## Tips for Effective Bug Hunting

1. **Start broad, narrow down** - Begin with time ranges, then specific searches
2. **Use temporal queries** - More intuitive than commit counts
3. **Leverage file birth** - `hug fborn` quickly finds original introduction
4. **Check related changes** - Bugs often span multiple files
5. **Follow the timeline** - Use `hug ld` to walk through date ranges
6. **Verify with diffs** - Always review actual changes with `-p` or `hug shp`
7. **Document your search** - Save command outputs for later reference

## See Also

- [Main Skill Documentation](../SKILL.md)
- [Pre-Commit Review Guide](pre-commit-review.md)
- [Branch Analysis Guide](branch-analysis.md)
