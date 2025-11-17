# Branch Analysis Guide

This guide teaches systematic approaches for analyzing branches, comparing work, and understanding branch relationships using Hug SCM.

## Understanding Branch Relationships

### Basic Branch Information

```bash
# Current branch
hug b

# Current branch with upstream status
hug b -v

# List all local branches
hug bl

# List all branches (local + remote)
hug bla

# List remote branches only
hug blr
```

### Branch Queries

Hug provides powerful queries for understanding branch relationships:

```bash
# Which branches contain this commit?
hug bwc <commit-hash>
hug bwc HEAD  # which branches have my current commit?

# Which branches point exactly at this commit?
hug bwp <commit-hash>
hug bwp HEAD

# Which branches DON'T contain this commit?
hug bwnc <commit-hash>

# Which branches are merged into current branch?
hug bwm

# Which branches are NOT merged?
hug bwnm
```

## Comparing Branches

### See Differences Between Branches

```bash
# Commits in branch A but not in branch B
hug l branch-b..branch-a

# Commits in current branch not in main
hug l main..HEAD

# Symmetric difference (commits in either but not both)
hug l main...feature-branch

# Just show files that differ
hug h files main..feature-branch
```

### Detailed Branch Comparison

```bash
# See all commits in feature branch
hug l main..feature-branch

# With more details
hug ll main..feature-branch

# With patches
hug lp main..feature-branch

# Summary of changes
git diff main...feature-branch --stat
```

## Analyzing Local vs Remote

### Check Sync Status

```bash
# Are you ahead/behind?
hug b  # shows ahead/behind in output

# See what you haven't pushed
hug lol  # log outgoing long
hug lo   # log outgoing short

# See local-only commits
hug l @{u}..HEAD

# Or with more detail
hug ll @{u}..HEAD

# Files in unpushed commits
hug h files -u
```

### Compare with Upstream

```bash
# Commits on remote but not local
hug l HEAD..@{u}

# Commits on local but not remote
hug l @{u}..HEAD

# All divergent commits (both sides)
hug l HEAD...@{u}
```

## Analyzing Branch Activity

### Recent Activity on Branch

```bash
# Last 10 commits
hug l -10

# Last week's commits
hug l --since="1 week ago"

# Commits in date range
hug ld "last monday" "friday"

# Files changed recently
hug h files -t "1 week ago"
```

### Author Activity

```bash
# Commits by specific author on this branch
hug lau "Author Name"

# With date range
hug lau "Author Name" --since="1 month ago"

# All authors on branch
git shortlog -sn
```

### File Activity

```bash
# Files changed most often
hug h files 50 | sort | uniq -c | sort -rn | head -10

# Files changed in last 20 commits
hug h files 20

# Files in feature branch vs main
hug h files main..HEAD
```

## Branch Workflow Analysis

### Understanding Feature Branch Progress

```bash
# How many commits ahead of main?
hug l main..HEAD --oneline | wc -l

# What files are touched?
hug h files main..HEAD

# Who's working on it?
hug l main..HEAD --format="%an" | sort | uniq -c

# Temporal spread
hug ll main..HEAD
```

### Merge Preview

```bash
# What would merge bring in?
hug l ..other-branch

# Would it fast-forward?
git merge-base --is-ancestor main feature-branch && echo "Can fast-forward"

# Preview merge result (don't actually merge)
hug m other-branch --dry-run
```

## Advanced Branch Analysis

### Find Branch Point

```bash
# Where did feature branch diverge from main?
git merge-base main feature-branch

# See that commit
hug sh $(git merge-base main feature-branch)

# All commits since divergence
hug l $(git merge-base main feature-branch)..HEAD
```

### Analyze Branch Complexity

```bash
# Number of commits
hug l main..feature-branch --oneline | wc -l

# Number of files touched
hug h files main..feature-branch | wc -l

# Number of authors
hug l main..feature-branch --format="%an" | sort -u | wc -l

# Lines changed
git diff main...feature-branch --stat | tail -1
```

### Find Related Branches

```bash
# Branches containing same commit
hug bwc <shared-commit>

# Branches with similar names
hug bl | grep "feature"

# Branches modified recently
git for-each-ref --sort=-committerdate refs/heads/ --format='%(refname:short) %(committerdate:relative)'
```

## Practical Examples

### Example 1: "Should I merge this feature branch?"

```bash
# Step 1: How much work is it?
hug l main..feature-auth
hug h files main..feature-auth

# Step 2: Is it recent?
hug ll main..feature-auth  # check dates

# Step 3: Does it conflict?
git merge-base main feature-auth
hug h files $(git merge-base main feature-auth)..main
hug h files $(git merge-base main feature-auth)..feature-auth
# Look for overlapping files

# Step 4: Who worked on it?
hug lau "Author" main..feature-auth

# Step 5: Preview
hug m feature-auth --dry-run
```

### Example 2: "Which branches are stale?"

```bash
# List branches by last commit date
git for-each-ref --sort=-committerdate refs/heads/ --format='%(committerdate:short) %(refname:short)'

# Or more detailed
git for-each-ref --sort=-committerdate refs/heads/ --format='%(committerdate:relative) %(refname:short) %(authorname)'

# Check if merged
hug bwm  # merged branches
hug bwnm  # not merged branches

# For each stale branch, check if has important work
hug l main..old-branch
```

### Example 3: "What's different between release branches?"

```bash
# Compare two release branches
hug l release-1.0..release-2.0

# See files that changed
hug h files release-1.0..release-2.0

# Summary statistics
git diff release-1.0...release-2.0 --stat

# Who did the work?
hug l release-1.0..release-2.0 --format="%an" | sort | uniq -c
```

### Example 4: "Is my branch up to date with main?"

```bash
# Check status
hug b

# See if behind
hug l HEAD..main

# See what you'd get by merging
hug ll HEAD..main

# Files that would change
hug h files HEAD..main

# If you want to update
hug bpullr  # pull main with rebase
# or
hug rb main  # rebase onto main
```

## Tag Comparisons

Similar queries work for tags:

```bash
# Which tags contain this commit?
hug twc <commit>

# Which tags point at HEAD?
hug twp HEAD

# Commits between tags
hug l v1.0..v2.0

# Files changed between releases
hug h files v1.0..v2.0
```

## Integration with Code Execution (MCP)

For complex branch analysis:

```typescript
// Compare multiple branches to find common changes
const branches = ['feature-a', 'feature-b', 'feature-c'];
const commonFiles = new Set();

for (const branch of branches) {
  const files = await hug_h_files({
    commit: `main..${branch}`
  });

  // Track which files appear in multiple branches
  files.forEach(f => {
    if (!commonFiles.has(f)) {
      commonFiles.add(f);
    }
  });
}

// Find hotspot files (changed in multiple branches)
const analysis = Array.from(commonFiles)
  .map(file => ({
    file,
    branches: branches.filter(b =>
      hug_h_files({ commit: `main..${b}` })
        .includes(file)
    )
  }))
  .filter(item => item.branches.length > 1);

console.log("Files changed in multiple branches:", analysis);
```

## Branch Management Tips

### When to Delete Branches

Delete if:
- ✅ Merged into main (`hug bwm` shows it)
- ✅ No unique commits (`hug l main..branch` is empty)
- ✅ Work is abandoned
- ✅ Superseded by another branch

Keep if:
- ❌ Has unmerged work (`hug bwnm` shows it)
- ❌ Backup/reference branch
- ❌ Active development

```bash
# Safe delete (only if merged)
hug bdel feature-branch

# Force delete (even if unmerged)
hug bdelf feature-branch

# Delete remote branch too
hug bdelr feature-branch
```

### Branch Cleanup Workflow

```bash
# 1. List all branches
hug bl

# 2. Check which are merged
hug bwm

# 3. For each merged branch, verify
hug l main..old-branch  # should be empty

# 4. Delete merged branches
hug bdel old-branch-1
hug bdel old-branch-2

# 5. Clean up remotes
git remote prune origin
```

## Quick Reference

```bash
# Branch Information
hug b                        # current branch
hug bl                       # list local branches
hug bla                      # list all branches
hug blr                      # list remote branches

# Branch Queries
hug bwc <commit>             # branches which contain
hug bwp <commit>             # branches which point at
hug bwnc <commit>            # branches which don't contain
hug bwm                      # merged branches
hug bwnm                     # not merged branches

# Comparisons
hug l branch1..branch2       # commits in branch2 not in branch1
hug l branch1...branch2      # symmetric difference
hug h files branch1..branch2 # files changed
hug ll main..HEAD            # detailed comparison

# Local vs Remote
hug lol                      # outgoing commits
hug h files -u               # files in unpushed commits
hug l @{u}..HEAD             # local-only commits
hug l HEAD..@{u}             # remote-only commits

# Activity Analysis
hug l -n                     # last n commits
hug l --since="date"         # commits since date
hug lau "Author"             # commits by author
hug h files n                # files in last n commits
```

## Common Patterns

### Pre-Merge Analysis

```bash
hug ll main..feature         # what's being merged?
hug h files main..feature    # which files?
git diff main...feature --stat  # how much changed?
hug m feature --dry-run      # test merge
```

### Post-Merge Verification

```bash
hug bwm                      # verify branch is merged
hug l main..feature          # should be empty
hug bdel feature             # safe to delete
```

### Sync Check

```bash
hug b                        # ahead/behind status
hug lol                      # what will push?
hug l HEAD..@{u}             # what would pull get?
```

## See Also

- [Main Skill Documentation](../SKILL.md)
- [Bug Hunting Guide](./bug-hunting.md)
- [Pre-Commit Review Guide](./pre-commit-review.md)
- [History Cleanup Guide](./history-cleanup.md)
