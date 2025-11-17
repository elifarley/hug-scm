# Pre-Commit Review Guide

This guide teaches you how to thoroughly review changes before committing, ensuring clean commits and catching issues early.

## The Pre-Commit Review Workflow

### Phase 1: Understand What You're Committing

#### Check Repository State

```bash
# Quick overview
hug s

# Detailed view with untracked files
hug sla

# Just staged changes
hug ss

# Just unstaged changes
hug su

# Combined working directory view
hug sw
```

#### Review Actual Changes

```bash
# See staged changes with diff
hug ss -p

# See unstaged changes with diff
hug su -p

# See all working directory changes
hug sw -p

# Review specific file
hug shf <file>
```

### Phase 2: Verify What's Being Included

#### Check Staged Files

```bash
# List staged files
hug ss

# Review each staged file's diff
hug ss -p

# Check if you're about to commit unintended files
hug ss | grep -i "secret\|password\|key\|token"
```

#### Verify No Sensitive Data

```bash
# Search for common secrets patterns
hug su -p | grep -E "(api_key|password|secret|token)"

# Check for debug code
hug su -p | grep -E "(console\.log|debugger|TODO|FIXME)"

# Check for large files
git diff --cached --stat | awk '$3 > 1000 {print}'
```

### Phase 3: Review Related History

#### See Recent Commits

```bash
# Last 5 commits for context
hug l -5

# Or with more detail
hug ll -5

# See what files you've been touching
hug h files 5
```

#### Check for Conflicts

```bash
# What commits are on remote but not local?
hug l @{u}..HEAD

# What will you push?
hug lol

# Check for divergence
hug b  # shows if behind/ahead of upstream
```

### Phase 4: Test and Validate

Before committing, ensure:

1. **Code builds**: Run build command
2. **Tests pass**: Run test suite
3. **Linting passes**: Run linter
4. **No debug code**: Search for console.log, debugger, etc.

### Phase 5: Stage Intelligently

#### Selective Staging

```bash
# Stage specific files only
hug a <file1> <file2>

# Stage all tracked changes (safe - no untracked)
hug a

# Interactive file selection
hug a --

# Stage everything including untracked
hug aa  # careful - includes new files!
```

#### Patch-Level Staging

```bash
# Interactively stage hunks
hug ap

# Or use Git's interactive add
hug ai
```

### Phase 6: Write a Good Commit Message

#### Commit Message Best Practices

```bash
# Use conventional commits format
hug c -m "feat: add user authentication"
hug c -m "fix: correct email validation regex"
hug c -m "docs: update installation guide"
hug c -m "refactor: extract validation logic"

# Multi-line messages (opens editor)
hug c

# Amend last commit message
hug cm
```

#### Message Quality Checks

Good commit messages:
- Start with type: feat, fix, docs, refactor, test, chore
- Are concise but descriptive (50 chars for title)
- Explain **why**, not what (the diff shows what)
- Reference issues if applicable

### Phase 7: Final Review Before Push

```bash
# Review what you just committed
hug sh

# With full diff
hug shp

# See commits ready to push
hug lol

# Or shorter
hug lo
```

## Detailed Examples

### Example 1: Feature Branch Review

```bash
# Step 1: Check status
hug sla

# Step 2: Review unstaged changes
hug su -p

# Step 3: Stage carefully
hug a src/features/auth/  # only auth files

# Step 4: Review staged
hug ss -p

# Step 5: Verify no secrets
hug ss -p | grep -iE "(api_key|password|secret)"

# Step 6: Commit with good message
hug c -m "feat(auth): implement JWT token validation

- Add token validation middleware
- Include expiration checking
- Add refresh token support

Closes #123"

# Step 7: Verify commit
hug sh
```

### Example 2: Bug Fix Review

```bash
# Step 1: Status
hug s

# Step 2: Review the fix
hug su -p

# Step 3: Check related files
hug h files 1  # see recent changes

# Step 4: Verify fix is minimal
hug ss --stat

# Step 5: Commit with fix type
hug c -m "fix: correct off-by-one error in pagination

The page calculation was using >= instead of >, causing
the last page to show twice.

Fixes #456"
```

### Example 3: Cleanup Before PR

```bash
# Step 1: See all local commits
hug lol

# Step 2: Review file changes
hug h files -u  # -u for upstream comparison

# Step 3: Check for commits to squash
hug ll @{u}..HEAD

# Step 4: Interactive squash if needed
hug rbi @{u}

# Step 5: Final review
hug h files -u -p
```

## Advanced Techniques

### Split Unrelated Changes

If you have multiple unrelated changes:

```bash
# Stage and commit feature A
hug a src/featureA/
hug c -m "feat: add feature A"

# Stage and commit feature B
hug a src/featureB/
hug c -m "feat: add feature B"

# Or use patch staging
hug ap  # select hunks interactively
hug c -m "refactor: extract common logic"
```

### Amend Without Changing Message

```bash
# Made a typo in last commit?
hug a typo-file.js
hug cm  # amend without editing message
```

### Review Large Changes

For big changesets:

```bash
# Get summary first
hug sw

# Review by directory
hug su -p -- src/components/
hug su -p -- src/utils/
hug su -p -- tests/

# Stage in logical groups
hug a src/components/
hug c -m "refactor(components): extract button styles"

hug a src/utils/
hug c -m "refactor(utils): add validation helpers"
```

### Verify Commit Atomicity

Each commit should be atomic (single logical change):

```bash
# Check files in commit
hug shc HEAD

# If too many unrelated files, consider splitting
hug h back  # undo commit
# Then stage and commit separately
```

## Common Mistakes to Avoid

### Mistake 1: Committing Debug Code

**Prevention:**
```bash
# Before staging, search for debug statements
grep -r "console.log\|debugger" src/

# Or in the diff
hug su -p | grep -E "(console\\.log|debugger)"
```

### Mistake 2: Committing Secrets

**Prevention:**
```bash
# Check for common secret patterns
hug su -p | grep -iE "(api_key|password|secret|token|private_key)"

# Use .gitignore for env files
echo ".env" >> .gitignore
echo ".env.local" >> .gitignore
```

### Mistake 3: Large Commits

**Prevention:**
```bash
# Check commit size
hug ss --stat

# If too large, split it:
hug us  # unstage all
# Then stage in logical chunks
```

### Mistake 4: Missing Files

**Prevention:**
```bash
# Always check untracked files
hug sla

# Make sure you're not missing new files
hug sw  # shows untracked count
```

## Using Interactive Staging

### Patch Mode Workflow

```bash
# Start interactive patch staging
hug ap

# For each hunk, choose:
# y - stage this hunk
# n - don't stage
# s - split hunk into smaller hunks
# e - manually edit hunk
# q - quit (remaining unstaged)

# Review what was staged
hug ss -p

# Commit the staged hunks
hug c -m "refactor: extract validation logic"

# Repeat for remaining changes
hug ap
```

## Integration with Testing

### Pre-Commit Test Workflow

```bash
# Stage changes
hug a

# Review what will be committed
hug ss -p

# Run tests on staged changes
git stash --keep-index  # stash unstaged
make test
git stash pop

# If tests pass
hug c -m "fix: handle null values in parser"

# If tests fail
hug us  # unstage
# Fix issues
# Repeat
```

## Quick Reference

```bash
# Status Checks
hug s                        # quick status
hug sla                      # full status
hug ss                       # staged only
hug su                       # unstaged only

# Review Changes
hug ss -p                    # staged diff
hug su -p                    # unstaged diff
hug sw -p                    # working dir diff

# Staging
hug a <files>                # stage specific files
hug a                        # stage all tracked
hug aa                       # stage everything (careful!)
hug ap                       # interactive patch staging
hug a --                     # interactive file selection

# Committing
hug c -m "type: message"     # commit with message
hug c                        # commit (opens editor)
hug cm                       # amend last commit
hug ca -m "message"          # commit all tracked

# Review Commits
hug sh                       # last commit with stats
hug shp                      # last commit with diff
hug lol                      # commits to push
hug h files -u               # files in unpushed commits

# Verification
hug b                        # branch status
hug l @{u}..HEAD             # commits ahead
```

## Pre-Commit Checklist

Before every commit:

- [ ] `hug sla` - Verify all changes are intentional
- [ ] `hug ss -p` - Review staged changes for:
  - [ ] No debug code (console.log, debugger)
  - [ ] No secrets (API keys, passwords)
  - [ ] No commented-out code
  - [ ] No TODO/FIXME in production code
- [ ] `hug ss --stat` - Verify file list makes sense
- [ ] Run tests
- [ ] Run linter
- [ ] Write good commit message
- [ ] `hug sh` - Final review of commit

## Tips for Clean Commits

1. **Commit often** - Small, focused commits are easier to review
2. **One logical change per commit** - Makes history bisectable
3. **Review before staging** - Catch issues early
4. **Use meaningful messages** - Future you will thank you
5. **Test before committing** - Don't break the build
6. **Stage selectively** - Use `hug a <files>` not `hug aa`
7. **Use patch staging** - For complex changes with `hug ap`
8. **Amend freely** - Fix typos in last commit with `hug cm`

## See Also

- [Main Skill Documentation](../SKILL.md)
- [Bug Hunting Guide](./bug-hunting.md)
- [History Cleanup Guide](./history-cleanup.md)
- [Branch Analysis Guide](./branch-analysis.md)
