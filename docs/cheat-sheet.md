# 🏁 Hug Commands Cheat Sheet 🏁

A quick reference for daily workflows with Hug SCM. Focus on intuitive commands that keep you coding, not wrestling Git. Grouped by common scenarios.

## Setup & Installation
```bash
# Clone and install
git clone https://github.com/elifarley/hug-scm.git
cd hug-scm
./install.sh

# Verify
hug s    # Quick status check
hug help # List all commands
```

## Basic Workflow
```bash
# Check status (colored summary)
hug s

# Stage tracked changes
hug a <file>     # Specific file
hug a .          # Current directory
hug a            # All tracked updates

# Stage everything (tracked + untracked)
hug aa

# Commit staged changes
hug c "Add login feature"

# View history
hug l    # One-line log with graph
hug ll   # Detailed log with messages
```

## Branching & Switching
```bash
# List branches
hug bl   # Local branches
hug bla  # All (local + remote)

# Create and switch
hug bc feature-branch

# Switch to existing
hug b main
hug bs   # Back to previous branch

# Merge
hug m feature-branch  # Squash merge (no commit)
hug mkeep feature-branch  # Merge commit

# Delete (safe)
hug bdel old-branch
hug bdelr origin/old-branch  # Remote
```

## Pushing & Pulling
```bash
# Push current branch (sets upstream)
hug bpush

# Safe fast-forward pull (fails if merge/rebase needed)
hug bpull

# Pull with rebase (linear history)
hug bpullr

# Force push (safe)
hug bpushf

# Pull from all remotes
hug pullall
```

## Inspecting Changes
```bash
# Status variants
hug sl   # Tracked files only
hug sla  # Include untracked
hug ss   # Staged diff
hug su   # Unstaged diff
hug sw   # Full working directory diff

# File history
hug llf <file> -1    # Last change to file
hug fblame <file>    # Who changed each line

# Search history
hug lf "fix bug"     # By message
hug lc "getUser"     # By code changes
```

## Undoing & Cleaning Up
```bash
# Discard changes (preview with --dry-run)
hug w discard <file>     # Unstaged
hug w discard-all        # All unstaged
hug w discard-all -s     # Staged only

# Full reset
hug w wipe-all           # Tracked files to clean state
hug w purge-all          # Remove untracked/ignored
hug w zap-all            # Nuclear: wipe + purge (-f to force)

# Undo commits (non-destructive)
hug h back               # Keep changes staged
hug h undo               # Keep changes unstaged
hug h steps <file>       # Steps back to last file change

# Revert pushed commit
hug revert <commit-hash>
```

## Parking Work (WIP)
```shell
# Save all uncommitted changes on new WIP branch (pushable, persistent)
hug wip  "Draft feature" # Park changes on a new branch so that you can focus on something else on the current branch
hug wips "Deep spike"    # Park changes on a new branch and stay on it so that you can focus without affecting the current branch

# Resume WIP (for more edits)
hug b WIP/2023-10-05/1430.draftfeature

# Unpark/finish: Squash-merge to current branch + delete
hug unwip WIP/<date>/<time>.<slug>

# Discard worthless WIP
hug wipdel WIP/<date>/<time>.<slug>
```

**Tip: `wips` vs. `wip`**: Use `wips` for immersive sessions (stay on WIP to add commits like `hug c`). Use `wip` for interruptions (e.g., switch to hotfix,   resume later). Both beat stash for shareability - push WIP branches for team backups.

## Advanced Workflows
```bash
# Amend last commit
hug cm "Updated message"  # Staged changes only
hug cma                   # All tracked changes

# Cherry-pick commit
hug cc <commit-hash>      # Copy onto HEAD

# Interactive rebase
hug rbi                  # From root
hug rb main              # Onto main

# Tag releases
hug ta v1.0 "Release 1.0"
hug tpush v1.0           # Push tag
```

## Tips for Smooth Sailing
- **Always preview:** Use `hug s` after every operation.
- **Safety first:** Destructive commands (e.g., `zap-all`) require confirmation; add `--dry-run` to simulate.
- **Discover commands:** `hug help <prefix>` (e.g., `hug help w` for working directory).
- **WIP > Stash:** Use `hug wip` for shareable progress; stash for quick local saves.
- **File-focused:** `hug llf <file> -1` for the latest commit touching a file.

For full details, see [Documentation](https://elifarley.github.io/hug-scm/). Happy developing! 🚀
