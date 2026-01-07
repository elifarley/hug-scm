# 🏁 Hug Commands Cheat Sheet 🏁

A quick reference for daily workflows with Hug SCM. Focus on intuitive commands that keep you coding, not wrestling Git. Grouped by common scenarios.

> 📖 **[Command Map](command-map.md)** - Learn command organization and structure
> 📚 **[Getting Started](getting-started.md)** - Installation and quick start guide

## Setup & Installation
```bash
# Clone and install
git clone https://github.com/elifarley/hug-scm.git
cd hug-scm
./install.sh

# Verify
hug s    # **S**tatus check
hug help # List all commands
```

## Basic Workflow
```bash
# Check status (colored summary)
hug sl    # **S**tatus + **L**ist

# Stage changes for commit
hug aa   # **A**dd **A**ll (tracked + untracked)
hug a    # **A**dd tracked

# Commit staged changes
hug c "Add login feature"  # **C**ommit

# View history
hug l    # **L**og
hug ll   # **L**og **L**ong
```

## Branching & Switching
```bash
# List branches
hug bl   # **B**ranch **L**ist (local)
hug blr  # **B**ranch **L**ist **R**emote

# Create and switch
hug bc feature-branch  # **B**ranch **C**reate

# Copy a branch (create snapshot without switching)
hug bcp main                  # **B**ranch **CP** (auto-generates main.copy.YYYYMMDD-HHMM from main's HEAD)
hug bcp feat-1 backup-feat    # Explicit name for the copy

# Switch to existing (interactive menu)
hug b    # **B**ranch
hug br   # **B**ranch **R**emotes (interactive menu of remotes only)
hug brr   # **B**ranch **R**efreshed **R**emotes (fetch first, then remote menu)

# Move commits between branches
hug cmv 3 feature/api --new   # **C**ommit **M**o**V**e to new branch (relocates commits, resets source)
hug cmv 6 main                # Move 6 commits to existing main branch

# Merge (squash, no commit)
hug m feature-branch  # **M**erge

# Delete (safe)
hug bdel old-branch    # **B**ranch **DEL**ete (local)
hug bdelr old-remote-branch  # **B**ranch **DEL**ete **R**emote
```

## 🌳 Worktree Management (Parallel Development)
```bash
# Create worktree for existing branch
hug wtc feature-auth     # **W**ork**T**ree **C**reate

# Interactive worktree management
hug wt                    # **W**ork**T**ree (menu + switching)

# List worktrees
hug wtl                   # **W**ork**T**ree **L**ist (short)
hug wtll                  # **W**ork**T**ree **L**ong **L**ist (with commit details)

# Switch to worktree directly
hug wt ~/workspaces-project/feature-auth

# Remove worktree (safe - checks for changes)
hug wtdel feature-auth    # **W**ork**T**ree **DEL**ete

# Worktree workflow example
hug wtc feature-auth      # Create worktree
hug wt ~/workspaces-project/feature-auth  # Switch to it
# ... work on feature ...
hug wtdel ~/workspaces-project/feature-auth  # Remove when done

# JSON output for automation
hug wtll --json | jq '.worktrees[] | select(.dirty == true)'
```
> **💡 Worktree Benefits**: No stashing needed, work on multiple features simultaneously, isolated working directories, easy context switching without losing uncommitted work.

## Syncing with Remote
```bash
# Push current branch (sets upstream)
hug bpush  # **B**ranch **Push**

# Safe fast-forward pull (fails if merge/rebase needed)
hug bpull  # **B**ranch **Pull**

# Pull with rebase (linear history)
hug bpullr  # **B**ranch **Pull** **R**ebase

# Safe force push (for rewritten local history)
hug bpushf  # **B**ranch **Push** **F**orce

# Convert HTTPS remote to SSH
hug remote2ssh  # Convert origin to SSH URL
```
> **CRITICAL**: Always review before pushing. Run `hug lol` (**L**og **O**utgoing **L**ong) for a full preview of commits that will be pushed, followed by a final status check.

## Inspection & Discovery
```bash
# See what will be pushed
hug lol  # **L**og **O**utgoing **L**ong

# Most recent commit touching a file
hug llf <file> -1  # **L**og **L**ookup **F**ile

# Who changed each line in a file
hug fblame <file>  # **F**ile **B**lame

# Who contributed to a file
hug fcon <file>  # **F**ile **CON**tributors

# Search commit messages
hug lf "fix bug"  # **L**og message **F**ilter

# Search code changes
hug lc "getUser"  # **L**og **C**ode search
```

## Undoing & Cleaning Up
```bash
# Discard unstaged changes in a file
hug w discard <file>  # **W**orking directory **Discard**

# Discard ALL unstaged changes
hug w discard-all  # **W**orking directory **discard** **ALL**

# Full reset of tracked files (staged + unstaged)
hug w wipe-all  # **W**orking directory **W**ipe **ALL**

# Remove all untracked/ignored files
hug w purge-all  # **W**orking directory **P**urge **ALL**

# Fix "committed to wrong branch" mistake
hug cmv 2 correct-branch --new  # **C**ommit **M**o**V**e to new branch (relocates last 2 commits)

# Undo last commit (keep changes staged)
hug h back  # **H**EAD **Back**

# Undo last commit (keep changes unstaged)
hug h undo  # **H**EAD **Undo**

# Rewind to a clean state (destructive)
hug h rewind  # **H**EAD **Rewind**

# Find how many steps back to last file change
hug h steps <file>  # **H**EAD **Steps**

# Revert a specific commit (creates a new commit undoing it)
hug revert <commit-hash>
```

## WIP (Work-In-Progress) Workflow
```bash
# Park all changes on a new WIP branch to have a clean working directory (free from uncommitted changes)
hug wip "Pausing work on feature X"  # **W**ork **I**n **P**rogress

# Park all changes on a new WIP branch and Stay on it
hug wips "Starting a focused spike"  # **W**ork **I**n **P**rogress **S**tay

# Integrate a WIP branch into your current branch (squash-merge)
hug w unwip WIP/YY-MM-DD/HHMM.slug  # **Un**park **W**ork **I**n **P**rogress

# Delete a WIP branch without integrating it
hug w wipdel WIP/YY-MM-DD/HHMM.slug  # **W**ork **I**n **P**rogress **DEL**ete
```

## Advanced Analysis & Statistics

```bash
# Computational analysis (files that change together)
hug analyze co-changes 100              # Find coupling in last 100 commits
hug analyze co-changes --threshold 0.50 # Strong coupling only (≥50%)

# Code ownership & expertise
hug analyze expert <file>               # Who owns this code? (recency-weighted)
hug analyze expert --author "Alice"     # Where does Alice have expertise?

# Team activity patterns
hug analyze activity --by-hour          # When does team commit?
hug analyze activity --by-author        # Per-author breakdown

# Commit dependency graph
hug analyze deps <commit>               # Find related commits via file overlap
hug analyze deps --all --format json    # Repository-wide coupling (JSON export)

# Repository statistics
hug stats file <file>                   # File metrics (commits, authors, churn)
hug stats author "Alice"                # Author contributions & expertise
hug stats branch feature/x              # Branch statistics
```

### Hidden Gems
```bash
# Regex support in message search (undocumented!)
hug lf "fix\|bug\|resolve" -i --all     # OR patterns in commit messages

# JSON export for automation
hug analyze co-changes --json           # Machine-readable coupling data
hug analyze expert <file> --json        # Ownership data export
hug stats file <file> --json            # File metrics export

# Temporal operations (works on most commands)
hug h files -t "3 days ago"             # Files changed recently
hug lf "keyword" --since="1 week ago"   # Time-filtered search

# Churn analysis (code hotspots)
hug fblame --churn <file>               # Line-level change frequency
hug fblame --churn --since="3 months ago" <file>  # Recent churn
```

## Tips
- **Get a reminder**: Forgetting a command? Just type `hug help` to see all families.
- **Check before you act**: `hug sl` is your best friend. Run it often.
- **Learn the structure**: See [Command Map](command-map.md) for comprehensive organization
- **Use computational analysis**: `analyze` commands reveal architectural issues (coupling, ownership)
- Hug's `bpull` and `bpullr` handle fetching for you in most cases. But you can run `hug fetch` to get the latest remote info without affecting your local branches.

---

**See also**: [Command Map](command-map.md) for complete command reference | [Getting Started](getting-started.md) for installation guide
