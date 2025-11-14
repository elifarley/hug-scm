# Merge (m*)

Merge commands in Hug integrate changes from one branch into another using different strategies suited to different workflows. Hug defaults to **squash merging** (`hug m`) for clean, linear history on shared branches, while offering alternatives like standard merges (`hug mkeep`) and fast-forward-only (`hug mff`) for specific scenarios. All merge commands are prefixed with `m` for "merge."

::: info Mnemonic Legend
- **Bold letters** in command names show the initials that build each command
- Safety icons used below: ✅ safe/preview-only · ⚠️ destructive/history-rewriting · 🔄 requires caution or confirmation
:::

## On This Page
- [Quick Reference](#quick-reference)
- [Commands](#commands)
- [Understanding Merge Strategies](#understanding-merge-strategies)
- [Merge Conflicts](#merge-conflicts)
- [Scenarios](#scenarios)
- [Tips](#tips)

> [!TIP] Related Commands
> See [Rebase (r*)](rebase) for alternative history-rewriting strategies
> See [HEAD Operations (h*)](head) for undoing commits after a merge
> See [Branching (b*)](branching) for creating and managing branches before merging
> See [WIP Workflow](working-dir#wip-workflow) for parking work safely before merging

## Quick Reference

| Command | Memory Hook | Summary |
|---------|-------------|---------|
| `hug m <branch>` | **M**erge (squash) | Squash-merge branch into current (stages changes, you commit) |
| `hug mkeep <branch>` | **M**erge **Keep** commit | Standard merge with merge commit (preserves branch history) |
| `hug mff <branch>` | **M**erge **F**ast-**F**orward only | Fast-forward merge only (fails if merge needed) |
| `hug ma` | **M**erge **A**bort | Abort merge in progress (escape from conflicts) |

## Understanding Merge Strategies

Before diving into commands, it helps to understand the three strategies:

```
Original State:
  main:    A ── B ── C
  feature:       D ── E

After `hug m feature` (Squash):
  main:    A ── B ── C ── F  (F = squashed D+E, you commit)

After `hug mkeep feature` (Standard):
  main:    A ── B ── C ──────┐
            \               M (merge commit)
             D ────── E ───/

After `hug mff feature` (Fast-Forward):
  main:    A ── B ── C ── D ── E  (C must be ancestor of E)
```

## Commands

### `hug m <branch-name>`

- **Description**: Performs a **squash merge**, combining all commits from `<branch-name>` into a single set of changes and staging them in your current branch. You must then run `hug c` to create a clean, single commit. This keeps the target branch's history linear and readable.

  **Best for**: Feature branches being merged to main/develop where you want clean, atomic commits in the primary branch history.

- **Example**:
  ```shell
  # On main, merge feature with clean history
  hug m feature/auth-redesign
  hug c "Add authentication redesign"  # Your commit message becomes the official one

  # Clean history: main now has a single commit for the whole feature
  hug l
  # Shows: "Add authentication redesign" as one commit, not 8 scattered ones
  ```

- **Safety**: ✅ Safe; you review and commit the squashed changes manually. Original feature branch remains untouched.

- **When to use**:
  - Merging feature branches to main/develop
  - You want clean, atomic commits in primary history
  - The feature branch has many small or WIP commits
  - Working in a team with shared main branch

- **When NOT to use**:
  - You need to preserve the branch's commit history
  - Multiple people are working on the same feature branch (use `hug mkeep` instead)
  - You want to track when the merge happened (use `hug mkeep` instead)

### `hug mkeep <branch-name>`

- **Description**: Performs a **standard merge** with the `--no-ff` flag, which always creates an explicit merge commit even if a fast-forward would be possible. This preserves the feature branch's entire commit history and records the merge event in the history.

  **Best for**: Team workflows where you want to keep branch history and track merges explicitly.

- **Example**:
  ```shell
  # On main, merge feature preserving all commits
  hug mkeep feature/api-refactor

  # History shows:
  # - The refactor commits from the feature branch
  # - A merge commit linking them back to main
  # - Preserves when/how the feature was integrated
  ```

- **Safety**: 🔄 Requires caution; conflicts may occur if both branches modified the same files. The merge commit creates permanent history.

- **When to use**:
  - Team workflows where history is important for auditing
  - Multiple people contributed to the branch and should be credited
  - You want to explicitly record "when" the merge happened
  - Working on shared branches (not squashing)

- **When NOT to use**:
  - You want clean, linear history on main
  - The branch has many WIP or temporary commits
  - You prefer atomic, logical commits in the history

### `hug mff <branch-name>`

- **Description**: Performs a **fast-forward merge only**. This simply advances your current branch pointer to match `<branch-name>`, creating no merge commit. This only works if your current branch is a direct ancestor of `<branch-name>` (i.e., no divergence).

  **Best for**: Keeping branches aligned without merge commits, or ensuring no unexpected merges happen.

- **Example**:
  ```shell
  # Fast-forward works (main is ancestor of feature)
  hug b feature
  hug mff main    # Fails if main diverged from feature

  # Safe: knows exactly what happened—no surprise merge commits
  ```

- **Safety**: ✅ Safe and predictable; fails loudly if merge would be needed (preventing surprise merges).

- **When to use**:
  - You want the safety of "fail if merge is needed"
  - Updating branches in sync (e.g., feature to latest main)
  - You explicitly don't want merge commits
  - Enforcing a linear, no-merge-commit workflow

- **When NOT to use**:
  - Merging diverged branches (use `hug m` or `hug mkeep`)
  - You want to record a merge event

### `hug ma`

- **Description**: **Aborts** a merge that's in progress (usually due to conflicts). Returns your working directory and staging area to the state before the merge started. This is your escape route if a merge becomes complicated.

  **Best for**: Getting out of a confusing merge without losing work.

- **Example**:
  ```shell
  # Merge starts with conflicts
  hug m feature/complex-branch
  # ✗ CONFLICT (content): Merge conflict in file.js

  # Realize this is too complicated right now
  hug ma

  # Back to pre-merge state, no changes lost
  hug sl  # Status shows clean
  ```

- **Safety**: ✅ Completely safe; restores repo to pre-merge state.

- **When to use**:
  - Merge resulted in conflicts you're not ready to resolve
  - Want to pause and resolve differently
  - Merge would take more effort than expected

## Merge Conflicts

If your merge results in conflicts, Hug will pause and show you which files conflict. You have two options:

**Option 1: Resolve conflicts manually**
```shell
# Edit conflicting files (look for <<<< ==== >>>> markers)
hug s                  # View conflict status
# ... edit files ...
hug a .                # Stage resolved files
git commit             # Complete the merge
```

**Option 2: Abort and try a different approach**
```shell
hug ma                 # Back out of the merge
hug rb branch-name     # Try rebasing instead (rewrites history)
# or
hug h back             # Undo commits and try a different merge strategy
```

> [!TIP] Conflict Prevention
> Before merging, check if branches have diverged:
> ```shell
> hug lol                # See what commits are ahead/behind
> hug sl                 # Check if you have uncommitted changes
> ```

## Scenarios

### Merging a Feature to Main (Clean History)

You completed a feature on a separate branch and want to integrate it into main with a clean commit:

```shell
# On feature branch with 8 commits
hug b feature/new-ui
hug l                      # Shows 8 small, WIP commits

# Switch to main and squash-merge
hug b main
hug m feature/new-ui       # Combines all 8 into staged changes
hug c "Add new UI component"  # Single clean commit

# Result: main has ONE commit with all the changes
# The 8 original commits are still on feature branch, not in main's history
hug l                      # Shows clean history
```

### Preserving Feature Branch History (Team Workflow)

Multiple team members worked on a feature, and you want to preserve everyone's contributions:

```shell
# Feature branch has 8 commits from different authors
hug b feature/api-refactor
hug l                      # Shows: [Alice] Add endpoints [Bob] Fix auth [Carol] Tests

# Merge to main preserving history
hug b main
hug mkeep feature/api-refactor  # Creates merge commit, preserves all 8 commits

# Result: main shows all contributions AND the merge event
# Each person's commits are visible in history
hug l
```

### Ensuring No Divergence (Safe Update)

You want to update a feature branch with the latest from main, but ensure it's a simple fast-forward:

```shell
# Feature is behind main
hug b feature/hotfix
hug mff main               # ✗ Fails: main diverged from feature
# Conflict would require merge—safely fails instead

# Safe option: rebase or reword
hug rb main                # Rebase feature onto main
# or
hug m main                 # Squash main into feature (not common)
```

### Aborting a Complicated Merge

A merge resulted in many conflicts, and you decide it's too complex right now:

```shell
hug b main
hug m feature/complex      # Merge starts...
# ✗ Many conflicts in critical files

# Too complex, abort
hug ma                     # Back to pre-merge state

# Try again later or with a different approach
hug b feature/complex
# ... fix some issues ...
hug b main
hug m feature/complex      # Try merge again
```

## Tips

- **Squash by default**: Use `hug m` for most feature merges to keep main clean. Use `hug mkeep` only when history matters to your team.

- **Check before merge**: Always run `hug lol` before merging to see what you're about to integrate. Run `hug sl` to ensure your working tree is clean.

- **Preview with `--dry-run`**: While Hug's merge doesn't have dry-run mode, you can check what would merge by running:
  ```shell
  hug lol <branch-name>    # See all commits that would merge
  git diff --stat HEAD..branch-name  # See file changes summary
  ```

- **Prefer squash for linear history**: Teams that prefer clean, atomic commits on main use `hug m` almost exclusively. Use `hug mkeep` only for major milestone merges you want to record as events.

- **Fast-forward as a safety check**: Use `hug mff` when you want to ensure no merge is needed (fail-safe). If it fails, you know divergence happened and can decide how to handle it.

- **Combine with branch deletion**: After successful merge, clean up with:
  ```shell
  hug bdel feature-name     # Delete local feature branch
  # or
  hug bdelr origin/feature-name  # Delete remote feature branch
  ```

- **Merge conflicts are normal**: If you get conflicts, don't panic. They just mean both branches changed the same parts. Resolve manually or abort with `hug ma`.
