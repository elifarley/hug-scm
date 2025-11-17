# History Cleanup Guide

This guide teaches safe approaches for cleaning up Git history before sharing work via pull requests or merges.

## When to Clean Up History

Clean up history when:
- Preparing a feature branch for PR review
- Removing "WIP" or "fixup" commits
- Combining related commits
- Reordering commits logically
- Improving commit messages
- Removing accidentally committed files

**Never** rewrite public/shared history unless you coordinate with your team!

## The Cleanup Workflow

### Phase 1: Assess What Needs Cleaning

```bash
# See your local commits
hug lol

# Or with more detail
hug ll @{u}..HEAD

# Count commits
hug l @{u}..HEAD --oneline | wc -l

# See files touched
hug h files -u
```

### Phase 2: Backup Your Work

**Always create a backup before history rewriting:**

```bash
# Create backup branch
hug bc backup/feature-name --no-switch

# Or manually
git branch backup-$(date +%Y%m%d-%H%M%S)

# Verify backup exists
hug bl | grep backup
```

Hug's HEAD operations create automatic backups, but explicit backups are safer for complex cleanup.

### Phase 3: Choose Your Cleanup Strategy

#### Strategy 1: Simple Squash (Recommended for Most Cases)

Use when you want to combine all commits into one:

```bash
# Squash last N commits
hug h squash 5

# This will:
# 1. Create automatic backup
# 2. Combine commits
# 3. Open editor for final message

# Preview first with dry-run
hug h squash 5 --dry-run
```

#### Strategy 2: Interactive Rebase (For Complex Cleanup)

Use when you need fine-grained control:

```bash
# Rebase from main
hug rbi main

# Or last N commits
hug rbi HEAD~5

# In the editor, you can:
# - pick: keep commit as-is
# - reword: change commit message
# - edit: pause to modify commit
# - squash: combine with previous, keep messages
# - fixup: combine with previous, discard message
# - drop: remove commit entirely
```

#### Strategy 3: Reset and Re-commit (Nuclear Option)

Use when starting over is easier:

```bash
# Soft reset to main (keeps all changes staged)
hug h back main

# Review all changes
hug ss -p

# Make logical commits
hug c -m "feat: implement feature A"
hug c -m "test: add tests for feature A"
hug c -m "docs: document feature A"
```

### Phase 4: Clean Up Commit Messages

#### Improve Message Quality

Before:
```
WIP
fix stuff
more fixes
actually works now
```

After:
```
feat(auth): implement JWT token validation

- Add token validation middleware
- Implement refresh token rotation
- Add expiration checking

Closes #123
```

#### Using Conventional Commits

```bash
# Reword last commit
hug cm  # opens editor

# Or specify new message
git commit --amend -m "feat(auth): add JWT validation"

# For older commits, use interactive rebase
hug rbi HEAD~5
# Mark commits with 'reword'
```

### Phase 5: Verify the Cleanup

```bash
# Check the result
hug lol

# Review each commit
hug ll @{u}..HEAD

# Verify files are correct
hug h files -u

# Check individual commits
hug sh
hug sh HEAD~1
hug sh HEAD~2

# Make sure nothing was lost
git diff @{u}..HEAD  # should match your intended changes
```

### Phase 6: Force Push Safely

```bash
# Use safe force-push (with lease)
hug bpushf

# This is safer than git push --force because it:
# 1. Checks if remote changed since your last fetch
# 2. Prevents accidentally overwriting others' work
# 3. Is equivalent to: git push --force-with-lease
```

## Detailed Examples

### Example 1: Squash All WIP Commits

**Before:**
```bash
$ hug lol
abc123 WIP: trying fix
def456 WIP: still broken
ghi789 WIP: maybe works?
jkl012 feat: add authentication
```

**Cleanup:**
```bash
# Squash all 4 commits
hug h squash 4

# Editor opens with all commit messages
# Replace with clean message:
feat(auth): implement user authentication

- Add JWT token generation
- Implement login/logout endpoints
- Add session management

Closes #123

# Save and close editor
```

**After:**
```bash
$ hug lol
mno345 feat(auth): implement user authentication
```

### Example 2: Interactive Rebase to Reorder

**Before:**
```bash
$ hug ll @{u}..HEAD
abc123 docs: update README
def456 feat: add feature
ghi789 test: add tests
jkl012 fix: typo in feature
```

**Cleanup:**
```bash
# Start interactive rebase
hug rbi @{u}

# Editor shows:
pick def456 feat: add feature
pick ghi789 test: add tests
pick jkl012 fix: typo in feature
pick abc123 docs: update README

# Reorder and squash:
pick def456 feat: add feature
fixup jkl012 fix: typo in feature
pick ghi789 test: add tests
pick abc123 docs: update README

# Save and close
```

**After:**
```bash
$ hug ll @{u}..HEAD
def456 feat: add feature
ghi789 test: add tests
abc123 docs: update README
```

### Example 3: Split a Large Commit

**Before:**
```bash
$ hug sh
abc123 feat: add auth and update docs
  (100+ files changed)
```

**Cleanup:**
```bash
# Reset last commit but keep changes
hug h back

# Now all changes are staged
hug ss

# Unstage everything
hug usa

# Stage and commit logically
hug a src/auth/
hug c -m "feat(auth): implement authentication"

hug a docs/
hug c -m "docs: update authentication guide"

hug a tests/auth/
hug c -m "test(auth): add authentication tests"
```

## Advanced Techniques

### Technique 1: Fixup Commits

During development, mark fixes for specific commits:

```bash
# Make a fix for earlier commit
git commit --fixup=abc123

# Later, autosquash during rebase
git rebase -i --autosquash @{u}
```

### Technique 2: Cherry-Pick Cleanup

Rebuild history by cherry-picking:

```bash
# Create new branch from main
hug bc feature-clean --point-to main

# Cherry-pick commits in desired order
hug ccp abc123
hug ccp def456
hug ccp ghi789

# Switch back and verify
hug b feature-original
git diff feature-clean  # should be empty if all picked

# Replace original branch
git branch -f feature-original feature-clean
hug b feature-original
```

### Technique 3: Interactive Edit

Modify specific commit in history:

```bash
# Start interactive rebase
hug rbi HEAD~5

# Mark commit with 'edit'
edit abc123 feat: add feature
pick def456 test: add tests
pick ghi789 docs: update

# Rebase pauses at abc123
# Make changes
vim src/feature.js

# Amend the commit
hug a src/feature.js
hug cm

# Continue rebase
hug rbc
```

## Removing Sensitive Data

### Remove File from Last Commit

```bash
# Remove from commit but keep in working dir
git rm --cached secrets.env
hug cm  # amend last commit

# Add to .gitignore
echo "secrets.env" >> .gitignore
hug a .gitignore
hug c -m "chore: ignore secrets.env"
```

### Remove File from History

For files in older commits:

```bash
# Use git filter-branch or git filter-repo
git filter-branch --index-filter \
  'git rm --cached --ignore-unmatch path/to/secret' \
  HEAD~10..HEAD

# Or better, use git-filter-repo
git filter-repo --path path/to/secret --invert-paths
```

**Warning:** This rewrites history extensively. Coordinate with team!

## Recovery from Mistakes

### Undo Squash/Rebase

If cleanup went wrong:

```bash
# Find your backup branch
hug bl | grep backup

# Or use reflog
git reflog

# Restore to before cleanup
hug b backup-branch
# or
git reset --hard HEAD@{5}  # from reflog
```

### Abort Rebase in Progress

```bash
# If rebase is stuck
hug rba  # rebase abort

# Returns to state before rebase
```

## Quick Reference

```bash
# Assessment
hug lol                      # see outgoing commits
hug ll @{u}..HEAD            # detailed view
hug h files -u               # files in unpushed commits

# Backup
hug bc backup-feature --no-switch

# Cleanup Methods
hug h squash n               # squash last n commits
hug rbi @{u}                 # interactive rebase
hug h back n                 # reset n commits (keeps changes)

# Commit Message Fixes
hug cm                       # amend last commit
git commit --amend -m "new message"

# Verification
hug ll @{u}..HEAD            # review result
hug h files -u               # check files
git diff @{u}..HEAD          # verify changes

# Force Push
hug bpushf                   # safe force push
```

## Best Practices

1. **Always backup first** - Create explicit backup branch
2. **Preview with dry-run** - Use `--dry-run` when available
3. **Verify before pushing** - Review with `hug ll @{u}..HEAD`
4. **Push carefully** - Use `hug bpushf` (force-with-lease)
5. **Communicate** - Tell team if rewriting shared branches
6. **Keep it simple** - Squash is often sufficient
7. **Don't over-clean** - Preserve meaningful history

## Common Cleanup Scenarios

### Scenario 1: Prepare for PR

```bash
hug lol                      # assess commits
hug bc backup-feature --no-switch  # backup
hug h squash 8               # combine all commits
# Write clean commit message
hug bpushf                   # force push
```

### Scenario 2: Fix Commit Message

```bash
hug cm                       # amend last commit
# or
hug rbi HEAD~5               # reword older commits
```

### Scenario 3: Remove Debug Commits

```bash
hug rbi @{u}                 # interactive rebase
# Mark debug commits with 'drop'
# Save and close
```

### Scenario 4: Logical Grouping

```bash
hug rbi @{u}                 # interactive rebase
# Reorder commits logically
# Squash related commits
# Save and close
```

## Warning Signs

Don't clean up history if:
- ❌ Branch is shared with others
- ❌ Commits are already on main/master
- ❌ You don't have a backup
- ❌ You're unsure what you're doing

Safe to clean up when:
- ✅ Working on personal feature branch
- ✅ Commits not yet pushed
- ✅ You have a backup
- ✅ Team expects rebased PRs

## See Also

- [Main Skill Documentation](../SKILL.md)
- [Pre-Commit Review Guide](./pre-commit-review.md)
- [Branch Analysis Guide](./branch-analysis.md)
- [Practical Workflows](../../docs/practical-workflows.md)
