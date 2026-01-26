# Commits (c*)

The `c*` commands handle creating and modifying commits, making it easier to record changes in your repository.

## Quick Reference

| Command   | Memory Hook                           | Summary                                            |
|-----------|---------------------------------------|----------------------------------------------------|
| `hug c`   | **C**ommit staged                     | Commit staged changes                              |
| `hug ca`  | **C**ommit **A**ll tracked            | Commit ALL tracked changes                         |
| `hug caa` | **C**ommit **A**dd **A**ll            | Stage and commit ALL changes (tracked + untracked) |
| `hug cm`  | **C**ommit **M**odify                 | Modify last commit with staged changes only        |
| `hug cma` | **C**ommit **M**odify **A**ll tracked | Modify last commit with all tracked changes        |
| `hug ccp` | **C**ommit **C**o**P**y (cherry-pick) | Copy a commit from another branch onto HEAD        |
| `hug cmv [N|commit] \<branch\> [--new] [-u, --upstream] [--force]` | **C**ommit **M**o**V**e | Move commits to another branch (like mv for files) |

## hug c (Commit staged)

Commit staged changes.

**Usage:** `hug c [options]`

**Options:**
- `-C <commit>`: Reuse commit message from specified commit (exact copy)
- `-c <commit>`: Reuse and edit commit message from specified commit (opens in editor)

**Examples:**
```shell
hug c # A text editor will be shown so that you can add a message
hug c -m "Fix typo in README"
hug c -C HEAD~1          # Reuse message from previous commit
hug c -c main~2          # Reuse and edit message from main branch
```

### Commit Message Patterns

Choose the right pattern based on your message complexity:

**Simple single-line** (most common):
```shell
hug c -m "Fix typo in README"
```

**Multi-line from LLM** (natural formatting, no escaping):
```shell
hug c -F - <<'EOF'
feat: add user authentication

WHY: Users need secure login
WHAT: Implemented OAuth2
IMPACT: Improved security
EOF
```

**Why use `-F -` with heredoc for multi-line?**
- LLM writes literal newlines (no `\n` escaping)
- Avoids the complex `hug c -m "$(cat <<'EOF'...EOF)"` nesting
- Git's native convention for stdin (`-F -` reads from standard input)

This is a safe way to commit, ensuring only staged files are included.

To preview what would be committed, run `hug sl` for a list of changed files or `hug ss` for a diff of staged changes.

### Reusing Commit Messages

Git natively supports reusing commit messages from existing commits:

```shell
# Reuse message exactly
hug c -C <commit>

# Reuse and edit message
hug c -c <commit>
```

Common use cases:
- Applying the same fix to multiple branches
- Creating revert commits with context
- Using well-written commits as templates

**Examples:**
```shell
# Apply the same bug fix to multiple branches
# On feature branch:
hug c -m "Fix critical security vulnerability in auth module"

# Switch to main branch and apply similar fix:
hug c -C feature~1

# Create a revert with proper context:
hug revert abc123
hug c -c abc123  # Reuse original message and add "Revert: " prefix
```

## hug ca (Commit All tracked)

Commit all tracked changes.

**Usage:** `hug ca`

**Examples:**
```shell
hug ca # A text editor will be shown so that you can add a message
hug ca -m "Fix typo in README"
```

This is a quick way to commit without having to add files to the staging area first.
Useful if you know that ALL tracked files must be committed.

## hug caa (Commit Add All)

Stage all untracked changes and commit (tracked and untracked).

**Usage:** `hug caa`

**Examples:**
```shell
hug caa -m "Add new feature with all related files"
```

Stages all current changes (staged and unstaged) and creates a new commit.
It is a convenient shortcut for `hug aa && hug c`.

## hug cm (Commit Modify)

Modify the last commit with staged changes.

This command allows you to add staged changes to the previous commit without creating a new one. It's ideal for fixing small mistakes or adding forgotten files.

When you run `hug cm` (**C**ommit **M**odify) without flags, your editor will open with the previous commit message already populated. This is very convenient if you just need to fix a typo or slightly reword the message.

If you want to replace the old message entirely, you can provide a new one directly with the `-m` flag, which avoids opening the editor.

**Usage:** `hug cm`

**Examples:**
```shell
# Realize you forgot to add a file to the last commit
hug a docs/forgotten-file.md
# Open the editor to see the last message and confirm or tweak it
hug cm

# Or... Replace the last commit message entirely without opening the editor
hug cm -m "A completely new and corrected commit message"
```

## hug cma

Modify the last commit with all tracked changes.

Similar to `hug cm` (**C**ommit **M**odify), this command modifies the last commit.
However, it automatically includes all changes to **ALL tracked files**, so you don't need to stage them first.

Running `hug cma` opens your editor with the existing commit message, making it perfect for small edits. To replace the message entirely without opening the editor, use the `-m` flag.

Usage: `hug cma`

**Examples:**
```shell
# After committing, you make a quick change to a file you just committed
# Open the editor to adjust the commit message
hug cma

# Modify and provide a new message in one step
hug cma -m "Add new feature (with all files)"
```

## hug ccp (Commit Copy)

Copy a commit from another branch onto the current branch (cherry-pick).

**Usage:**
- `hug ccp <commit>...`  # Cherry-pick commits
- `hug ccp --husk <commit>`  # Create template commit with same files and message

**Options:**
- `--husk`: Stage the same files as the source commit and reuse its message

**Examples:**
```shell
# Cherry-pick commits (original behavior)
hug ccp a1b2c3d4              # Copy a single commit by hash
hug ccp HEAD~2                # Copy the commit two steps back
hug ccp a1b2c3 d4e5f6         # Copy multiple commits
hug ccp --no-commit a1b2c3    # Copy without auto-committing

# Husk mode (new feature)
hug ccp --husk abc123         # Stage same files as abc123 and reuse its message
```

Applies the changes from a specific commit on top of the current HEAD, creating a new commit on the current branch. Hug uses `git cherry-pick -x`, which adds the original commit hash to the new commit message for reference. This is useful for bringing a specific bug fix or feature from one branch to another without merging the entire source branch.

**When to use:**
- You want to apply a specific bug fix from another branch without merging all changes
- You need to backport a feature to a maintenance branch
- You want to copy a commit from someone else's branch

**Note:** If conflicts occur during cherry-pick, resolve them with `hug s` to see the status, fix the conflicts, then `hug caa` to complete the cherry-pick.

## hug cmv (Commit Move)

Move (relocate) commits from the current branch to another branch (new or existing), like `mv` for files. After the move, switches to and stays on the target branch.

**Usage:** `hug cmv [N|commit] \<branch\> [--new] [-u, --upstream] [--force]`

**Description**: Moves the last N commits (default: 1) or commits above a specific commit from the current branch to \<branch\>, preserving individual commit history. Then resets the current branch back.

**Visual Example:**
```
BEFORE:                           AFTER:
feature-branch                    feature-branch
    ↓                                ↓
  ●─●─●─●─●─●  (6 commits)         ●  (reset back 6 commits)
    ↓
  ● main                           ● main
                                     ↓
                                   ●─●─●─●─●─●  (6 commits added)

Command: hug cmv 6 main
Result:  Now on 'main' with 6 commits (new SHAs via cherry-pick)
```

**Behavior**:
- **New branches**: Creates pointer at original HEAD then resets source back (exact history preserved, original SHAs kept, no conflicts possible)
- **Existing branches**: Cherry-picks commits onto target (creates NEW commit SHAs, may conflict)

If \<branch\> missing without --new: Combined prompt "Branch 'X' doesn't exist. Proceed with creating a new branch named 'X' and moving N commit(s) to it?" (y/n); auto-creates with --force (no prompt). Use --new for explicit non-interactive creation. With -u, moves local-only commits above the upstream tip (read-only preview/confirmation; no fetch). Post-move: You'll end up on the target branch for easy continuation.

**When to Use What:**

| Scenario | Command | Why |
|----------|---------|-----|
| Move commits, don't keep on source | `hug cmv` | Relocates commits (source loses them) |
| Copy commits, keep on source | `hug ccp` | Duplicates commits (source keeps them) |
| Just move HEAD back | `hug h back` | Doesn't relocate commits to another branch |
| Interactive history editing | `hug rbi` | More control, can squash/edit/reorder |

**Real-World Examples:**

### Scenario 1: Wrong Branch Recovery
```shell
# You're on main, but commits should be on feature branch
$ git branch --show-current
main

$ hug ll -3
* abc123 2025-11-21 Add new API endpoint
* def456 2025-11-21 Update tests
* ghi789 2025-11-21 Fix typo

$ hug cmv 3 feature/api --new
📊 3 commits since ghi789~1:
...
📤 moving to feature/api:
* abc123 Add new API endpoint
* def456 Update tests
* ghi789 Fix typo

✅ Created and moved 3 commits to new branch 'feature/api'
✅ main reset back 3 commits
✅ Now on 'feature/api'
```

### Scenario 2: Consolidate to Main
```shell
# Feature branch work done, move to main
$ git branch --show-current
feature/refactor

$ hug cmv 6 main
📊 6 commits since abc123:
...
📤 moving to main:
...

✅ Moved 6 commits to 'main'
✅ feature/refactor reset back 6 commits
✅ Now on main (ready to push)
```

**Basic Examples:**
```shell
hug cmv 2 feature/new           # Combined prompt to create if missing
hug cmv 2 feature/new --new     # Explicitly create new branch 'feature/new'
hug cmv a1b2c3 existing-branch  # Move commits above a1b2c3 to 'existing-branch'
hug cmv -u feature/local --force # Auto-creates if missing, skip confirmation
hug cmv 3 bugfix --force        # Skip confirmation (auto-create if missing)
```

**Safety**: Requires clean working tree and index (no staged or unstaged changes; untracked ok). Previews commits and file changes; requires y/n confirmation for move (skipped with --force). Auto-creation on --force for scripting; combined interactive prompt otherwise. For new branches: Simple detach (no reapplication). For existing: Cherry-pick may conflict/abort. Cannot mix -u with explicit N/commit. The preview is read-only.

## Tips
- Use `hug s` (**S**tatus) or `hug sl` (**S**tatus + **L**ist) to check what you are about to commit, especially before using `hug c` (**C**ommit).
- `hug ca` (**C**ommit **A**ll tracked) and `hug caa` (**C**ommit **A**dd **A**ll) are great for speed, but be sure you want to commit *all* changes. For more selective commits, stage files individually with `hug a` (**A**dd) or `hug aa` (**A**dd **A**ll) and then use `hug c` (**C**ommit).
- Use `hug cm` (**C**ommit **M**odify) or `hug cma` (**C**ommit **M**odify **A**ll tracked) to fix mistakes in your last commit (e.g., forgotten changes or typos in the message) without creating extra "fixup" commits. This keeps your history cleaner.

\> [!WARNING]
\> Avoid using `hug cm` (**C**ommit **M**odify) or `hug cma` (**C**ommit **M**odify **A**ll tracked) on commits that have already been pushed to a remote repository (like GitHub).
\> Modifying a commit rewrites history, which can create significant problems for anyone who has already pulled your changes.
