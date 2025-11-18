# Workflows: From Comfortable to Expert

This guide takes you beyond the basics, showing you how to combine Hug's commands into fluid, powerful workflows for professional development. You'll learn the patterns that experienced developers use every day.

[[toc]]

::: tip Prerequisites
This guide assumes you've completed [Getting Started](getting-started.md) and are comfortable with basic commands. If you're new to Hug, start there first.
:::

## The Philosophy: Think in Workflows, Not Commands

Expert developers don't memorize commands—they internalize *patterns*. This guide teaches you the **investigation patterns**, **development cycles**, and **recovery strategies** that make version control feel natural.

## Part 1: Core Development Workflows

### The Feature Development Cycle

This is the backbone of most feature work. Master this, and you'll handle 80% of your daily tasks.

#### Starting Clean

**Goal**: Begin new work from a stable, up-to-date foundation.

```bash
# 1. Get latest main
hug b main
hug bpullr                      # Pull with rebase for linear history

# 2. Create feature branch
hug bc feature/user-auth        # Create and switch

# 3. Verify clean state
hug sl                          # Should show nothing
```

**Why this works**: Starting from an updated `main` prevents merge conflicts later. `bpullr` maintains a clean, linear history instead of creating unnecessary merge commits.

#### The Inner Loop: Atomic Commits

**Goal**: Make small, logical commits that tell a story.

```bash
# 1. Make focused changes to related files
# ... edit login.tsx, auth.ts ...

# 2. Review what changed
hug sw                          # Working dir diff (staged + unstaged)

# 3. Stage logically related changes
hug a login.tsx auth.ts         # Specific files
# OR
hug aa                          # Everything if it's all one logical unit

# 4. Verify what you're committing
hug ss                          # Show staged diff

# 5. Commit with clear intent
hug c -m "feat: add JWT authentication to login flow"
```

**Pro pattern**: Use conventional commit prefixes (`feat:`, `fix:`, `refactor:`) to make history scannable.

#### Handling Interruptions: The WIP Pattern

**Scenario**: Urgent bug report arrives mid-feature. You can't commit broken code, but can't lose your work.

```bash
# 1. Park current work (creates timestamped WIP branch)
hug wip "Halfway through login refactor"

# Your working directory is now clean
# The WIP branch has all your changes committed

# 2. Handle the urgent task
hug b main
hug bc hotfix/critical-bug
# ... fix, commit, push ...

# 3. Return to your feature
hug b feature/user-auth

# 4. Resume parked work
hug w unwip                     # Interactive: select the WIP branch
# Your changes are back, ready to continue
```

**Why WIP beats stash**:
- **Persistent**: WIP branches survive rebases and machine failures
- **Shareable**: Push WIP branches for backup or collaboration
- **Named**: `hug bl` shows descriptive WIP branch names, not cryptic stash numbers
- **Versioned**: Continue adding commits to WIP branches

**Advanced WIP**: Use `hug wips` (WIP + Stay) for deep exploration work where you want to add multiple commits before integrating.

### Preparing for Review

**Goal**: Clean commit history that reviewers can understand.

#### Step 1: Sync with Main

```bash
# Ensure you have latest main
hug b main
hug bpullr

# Rebase your feature onto updated main
hug b feature/user-auth
hug rb main                     # Rebase current branch onto main
```

**If conflicts occur**:
```bash
# 1. Fix conflicts in affected files
# 2. Mark as resolved
hug a <conflicted-files>
# 3. Continue
hug rbc                         # Rebase continue

# If stuck, abort and ask for help
hug rba                         # Rebase abort
```

#### Step 2: Polish Your Commits

**Interactive rebase** lets you rewrite history—combine commits, reword messages, reorder changes.

```bash
# Enter interactive mode
hug rbi main                    # Rebase interactive from main

# Git opens editor showing commits:
# pick abc1234 feat: add login form
# pick def5678 wip: debugging
# pick ghi9012 fix: typo in auth
# pick jkl3456 feat: add JWT validation

# Edit to clean up:
# pick abc1234 feat: add login form
# fixup def5678 wip: debugging       # Squash into previous, discard message
# fixup ghi9012 fix: typo in auth    # Squash into previous, discard message
# pick jkl3456 feat: add JWT validation

# Save and close. Hug combines commits automatically.
```

**Result**: Two clean commits instead of four messy ones.

#### Step 3: Verify Before Pushing

```bash
# See what you're about to push
hug lol                         # Log outgoing long

# Review files in unpushed commits
hug h files -u                  # -u = upstream comparison

# Final safety check
hug sl                          # Ensure working dir is clean

# Push when satisfied
hug bpushf                      # Force push with lease (safe)
```

::: warning Force Push Safety
Only use `hug bpushf` on **your own feature branches**. Never force-push to shared branches like `main` or branches others are using.
:::

### Advanced Commit Management

#### Cherry-Picking: Selective Commit Transfer

**Scenario**: You fixed a bug on a feature branch, but need it on `main` immediately.

```bash
# 1. Note the fix commit hash
hug l -1                        # abc1234

# 2. Switch to target branch
hug b main
hug bpull

# 3. Copy the commit
hug ccp abc1234                 # Commit CoPy (cherry-pick)

# 4. Push
hug bpush
```

**Backporting to release branches**:
```bash
# Multiple commits at once
hug b v2.1-release
hug bpull
hug ccp abc1234 def5678 ghi9012
hug bpush
```

#### Commit Move: Rescuing Misplaced Commits

**Scenario**: Made 3 commits on `main` when you meant to create a feature branch.

**Traditional approach** (complex):
```bash
git checkout -b feature/oops
git checkout main
git reset --hard HEAD~3         # Scary!
```

**Hug approach** (elegant):
```bash
hug cmv 3 feature/new-feature   # Move last 3 commits to new branch
```

**What happened**:
1. Created `feature/new-feature` at current position
2. Reset `main` back 3 commits
3. Switched you to `feature/new-feature`
4. All in one safe command!

**Moving to existing branch**:
```bash
hug cmv 2 feature/existing      # Cherry-picks commits, then resets current
```

**Upstream mode** (move all unpushed commits):
```bash
hug cmv -u feature/local-work   # Moves everything after origin/main
```

## Part 2: Investigation Workflows

### Finding When Things Changed

#### The Three-Step Investigation Pattern

**Pattern**: Status → Search → Inspect → Act

```bash
# 1. What's the current state?
hug sla                         # Full status

# 2. When was this feature added?
hug lf "user authentication"    # Search commit messages

# 3. Inspect the suspect commit
hug shp abc1234                 # Show with patch

# 4. See related changes
hug h files abc1234             # What else changed then?
```

#### Message Search with Hidden Regex Power

```bash
# Simple search
hug lf "bug fix"

# HIDDEN GEM: Regex patterns work!
hug lf "fix\|bug\|resolve" -i --all     # OR patterns
hug lf "^feat.*auth" --all              # Regex matching
hug lf "implement\|add\|create" --with-files  # Show affected files
```

::: tip Regex Support
`hug lf` uses `git --grep` internally, which supports **extended regex**. This is undocumented but incredibly powerful for complex searches.
:::

#### Code Search: Finding Implementation Changes

**Literal string search** (fast):
```bash
hug lc "getUserById"                    # When did this function change?
hug lc "import React" --with-files      # Show files affected
```

**Regex search** (powerful):
```bash
hug lcr "function.*User"                # Function definitions
hug lcr "class \w+" -i                  # Case-insensitive classes
hug lcr "TODO|FIXME" --all              # All TODOs in history
```

**Decision tree**:
- Searching **commit messages**? → `hug lf` (supports regex!)
- **Exact code string**? → `hug lc` (faster, literal)
- **Code pattern/regex**? → `hug lcr` (explicit regex)

### Deep File Investigation

#### Finding File Origins

```bash
# When was this file created?
hug fborn src/auth.ts                   # Binary search for creation commit

# See the creation context
hug sh abc1234                          # What else was added with it?

# Trace its evolution
hug llf src/auth.ts                     # Full history (follows renames)
```

#### Understanding Ownership

```bash
# Who wrote each line?
hug fblame src/auth.ts

# Who maintains this file?
hug fcon src/auth.ts                    # List all contributors

# How much does each person own?
hug fa src/auth.ts                      # Commit counts per author
```

#### Identifying Code Hotspots

```bash
# Which lines change most frequently?
hug fblame --churn src/auth.ts

# Recent churn only
hug fblame --churn --since="3 months ago" src/auth.ts

# Export for visualization
hug fblame --churn --json src/auth.ts > hotspots.json
```

### Temporal Analysis

**Time-based queries** are more intuitive than counting commits.

```bash
# What changed recently?
hug h files -t "3 days ago"
hug h files -t "last monday"

# Commits in date range
hug ld "2024-01-15" "2024-01-22"

# Author activity in time period
hug lau "Alice" --since="1 month ago"

# Code search in recent commits
hug lc "authenticate" -t "2 weeks ago"
```

### Precise History Navigation

**Pattern**: Find exact step count, then rewind precisely.

```bash
# How many commits since this file changed?
hug h steps src/auth.ts                 # "File last changed 3 steps back"

# Rewind exactly to that point
hug h back 3                            # Keeps changes staged

# OR undo if you want changes unstaged
hug h undo 3

# OR rollback if you want to discard changes (keeps uncommitted work)
hug h rollback 3 --dry-run              # Preview first
hug h rollback 3                        # Then execute
```

## Part 3: Computational Analysis ⭐

These workflows use **statistical algorithms and graph analysis** impossible with pure Git.

### Architectural Coupling Analysis

**Goal**: Find files that change together (architectural coupling).

```bash
# Basic analysis (last 100 commits)
hug analyze co-changes 100

# Strong coupling only
hug analyze co-changes 200 --threshold 0.50    # ≥50% correlation

# Top coupled pairs
hug analyze co-changes --top 10

# Export for dashboards
hug analyze co-changes --json > coupling.json
```

**Algorithm**: Builds co-occurrence matrix from commit history, calculates correlation coefficients.

**Use cases**:
- Identify tightly coupled modules that should be refactored
- Find files to review together
- Detect architectural issues

### Code Ownership & Expertise

**Goal**: Who maintains this code? Who should review changes?

```bash
# Who owns this file? (recency-weighted)
hug analyze expert src/auth.ts

# What does Alice maintain?
hug analyze expert --author "Alice"

# Custom recency decay
hug analyze expert src/auth.ts --decay 90      # 90-day decay window

# Export for code review assignment
hug analyze expert src/auth.ts --json
```

**Algorithm**: Recency-weighted commit analysis with exponential decay:
`weight = commits × exp(-days_ago / decay_days)`

**Output categories**:
- **Primary**: >40% weighted ownership
- **Secondary**: >20% weighted ownership
- **Historical**: <20% (stale contributors)

### Commit Dependency Graphs

**Goal**: Find related commits through file overlap.

```bash
# What commits are related to this one?
hug analyze deps abc1234

# Two-level dependency traversal
hug analyze deps abc1234 --depth 2

# Require strong coupling (3+ files overlap)
hug analyze deps abc1234 --threshold 3

# Repository-wide coupling
hug analyze deps --all --threshold 5

# Export formats
hug analyze deps abc1234 --format graph        # ASCII tree (default)
hug analyze deps abc1234 --format text         # Simple list
hug analyze deps abc1234 --format json         # Machine-readable
```

**Algorithm**: File-to-commits indexing + graph traversal (BFS) based on file overlap.

**Use cases**:
- Find all commits in a logical feature
- Determine review scope
- Understand feature evolution
- Detect tightly coupled code areas

### Team Health & Activity Patterns

**Goal**: Understand when and how your team works.

```bash
# Hourly commit patterns
hug analyze activity --by-hour

# Day-of-week distribution
hug analyze activity --by-day

# Per-author breakdowns
hug analyze activity --by-author --by-hour

# Time-filtered analysis
hug analyze activity --since="3 months ago"

# Export for dashboards
hug analyze activity --json
```

**Algorithm**: Temporal aggregation with statistical summaries.

**Flags**:
- ⚠️ Late night commits (10pm-4am)
- ⚠️ Weekend work patterns
- Peak productivity hours

**Insights**:
- Team sustainability assessment
- Timezone coverage detection
- Process problem indicators

### Repository Statistics

```bash
# File-level metrics
hug stats file src/app.js
hug stats file src/app.js --json               # Export

# Author contributions
hug stats author "Alice"
hug stats author "Alice" --json

# Branch statistics
hug stats branch feature/auth
hug stats branch feature/auth --json
```

## Part 4: Quick Recipes

### Recipe 1: Review Before Pushing

**Always** verify what you're about to share:

```bash
# 1. See unpushed commits
hug lol                                        # Detailed outgoing log

# 2. Review files in those commits
hug h files -u                                 # -u = upstream

# 3. Check for debug code
hug lc "console.log" -u
hug lc "debugger" -u

# 4. Final status
hug sl

# 5. Push when satisfied
hug bpush
```

### Recipe 2: Find and Revert a Bug

```bash
# 1. Search for the feature that broke
hug lf "login form" --with-files

# 2. Inspect suspect commit
hug shp abc1234

# 3. Revert it (creates new commit undoing changes)
hug revert abc1234

# 4. Push the fix
hug bpush
```

### Recipe 3: Update Feature Branch with Latest Main

```bash
# 1. Commit your current work
hug sl
hug caa -m "Save progress"

# 2. Get latest main
hug b main
hug bpullr

# 3. Rebase feature onto updated main
hug b feature/my-work
hug rb main

# 4. Resolve conflicts if any
# ... edit conflicted files ...
hug a <files>
hug rbc                                        # Continue rebase

# 5. Force push (history rewritten)
hug bpushf
```

### Recipe 4: Split Large Feature into Smaller Branches

**Scenario**: 10 commits on `feature/big`, but last 3 should be separate.

```bash
# Currently on feature/big with 10 commits
hug l -10                                      # Review commits

# Move last 3 to new branch
hug cmv 3 feature/small-enhancement

# Now you're on feature/small-enhancement with 3 commits
# feature/big has first 7 commits

# Push for separate review
hug bpush
```

### Recipe 5: Interactive File Selection

**Goal**: Avoid typing long paths, use visual selection.

```bash
# Select files to stage
hug a --

# Select files to discard
hug w discard --

# Select file to search in
hug lc "functionName" --

# Full repo scope (not just current dir)
hug lc "import" --browse-root
```

::: tip Requires Gum
Interactive selection requires [Gum](https://github.com/charmbracelet/gum). Install with `make optional-deps-install`.
:::

### Recipe 6: Find Hotspots for Refactoring

```bash
# 1. Find frequently changing files
hug h files -t "6 months ago"                  # Recent activity

# 2. Analyze churn in suspects
hug fblame --churn src/problematic.ts

# 3. Check coupling
hug analyze co-changes src/problematic.ts

# 4. Identify owners
hug analyze expert src/problematic.ts

# Combined: high churn + high coupling + unclear ownership = refactor candidate
```

### Recipe 7: Temporal Bug Hunt

**Scenario**: Feature worked last week, broken now.

```bash
# 1. What changed in the last week?
hug h files -t "1 week ago"

# 2. Search for related changes
hug lc "problematic function" -t "1 week ago"

# 3. Review each suspect commit
hug shp <commit>

# 4. When found, revert or fix
hug revert <bad-commit>
# OR
hug h back
# ... fix code ...
hug c -m "fix: correct the bug"
```

### Recipe 8: Collaborative Review with WIP

**Scenario**: Need feedback on incomplete work.

```bash
# 1. Park work on WIP branch
hug wips "Experimental UI redesign"            # Stay on WIP branch

# 2. Continue adding commits
hug a components/
hug c -m "Add new button component"
hug c -m "Update color scheme"

# 3. Push for feedback
hug bpush

# 4. Share branch name with teammate
# They can: hug b WIP/24-11-18/1430.experimental-ui

# 5. When done, integrate back
hug b feature/ui-update
hug w unwip WIP/24-11-18/1430.experimental-ui
```

## Part 5: Advanced Patterns

### Pattern 1: The Investigation Cascade

When debugging, move from broad to specific:

```bash
# Level 1: Status (what changed?)
hug sla

# Level 2: Recent history (when?)
hug h files -t "3 days ago"

# Level 3: Search (who/why?)
hug lf "relevant keyword" --with-files

# Level 4: Deep inspection (how?)
hug shp <suspect-commit>

# Level 5: Context (what else?)
hug analyze deps <suspect-commit>
```

### Pattern 2: The Safety Workflow

Before any destructive operation:

```bash
# 1. Preview
hug <command> --dry-run

# 2. Check backups exist
hug bl | grep backup

# 3. Create manual backup if needed
hug bcp main main-backup-$(date +%Y%m%d)

# 4. Execute
hug <command> -f

# 5. Verify
hug sl
hug l -5
```

### Pattern 3: The JSON Export Pipeline

Build custom dashboards and reports:

```bash
# Extract data
hug analyze co-changes --json > coupling.json
hug analyze activity --json > activity.json
hug stats file src/main.ts --json > file-stats.json

# Process with jq, Python, or your analytics tool
cat coupling.json | jq '.high_coupling_pairs'

# Visualize in Grafana, custom dashboard, etc.
```

### Pattern 4: The Four-Tier Value Extraction

Leverage Hug's complete value proposition:

```bash
# Tier 1: Humanization
hug sl                                         # Better UX than git status

# Tier 2: Workflow Automation
hug lf "keyword" --with-files                  # Combined operations

# Tier 3: Computational Analysis
hug analyze co-changes --threshold 0.5         # Statistical algorithms

# Tier 4: Machine-Readable Export
hug analyze expert src/main.ts --json          # Automation ready
```

## Key Takeaways

### Internalize These Patterns

1. **Always status before acting**: `hug sl` or `hug sla`
2. **Preview before destroying**: `--dry-run` flag
3. **WIP over stash**: Real branches beat temporary storage
4. **Search with context**: Use `--with-files` to see impact
5. **Think in time**: `-t "3 days ago"` beats counting commits
6. **Combine commands**: Investigation cascades, not isolated commands

### Command Families You Should Master

| When You Need To... | Use This Family |
|---------------------|----------------|
| Undo recent work | `h*` (HEAD operations) |
| Clean up workspace | `w*` (working directory) |
| Understand state | `s*` (status) |
| Organize work | `b*` (branching) |
| Search history | `l*` (logging) |
| Understand authorship | `f*` (file inspection) |
| Find coupling | `analyze co-changes` |
| Identify owners | `analyze expert` |

### What Makes You an Expert

Beginners memorize commands. **Experts recognize patterns**:

- You know when to `wip` vs `wips`
- You reach for `analyze deps` to understand feature scope
- You use `h steps` for precise navigation
- You leverage `--json` for automation
- You think in workflows, not individual commands

## Next Steps

- **Reference**: See [Command Map](command-map.md) for complete command catalog
- **Quick Lookup**: Use [Cheat Sheet](cheat-sheet.md) for syntax reference
- **Advanced Features**: Explore individual [command pages](commands/head.md) for deep dives on specific categories
- **Command Reference**: See [Command Map](command-map.md) for the complete list of all 139 commands

---

**Remember**: Great version control isn't about knowing every flag—it's about internalizing the patterns that make your work flow naturally.
