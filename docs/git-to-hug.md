# Git to Hug Translation Guide

**Transitioning from Git to Hug?** This guide maps your existing Git mental models to Hug's humane commands. Find the Git command you know, see its Hug equivalent, and understand why Hug's approach is better.

> [!TIP] How to Use This Guide
> - **Look up Git commands** you already know in the tables below
> - **Learn the Hug equivalent** and its memory hook
> - **Understand the benefits** of Hug's approach
> - **Progressive learning**: Start with essentials, expand to advanced as needed

## Why Hug Improves on Git

Git is powerful but its UX was designed for plumbing, not humans. Hug adds a humane layer:

### Better Mental Model
- **Verbs over flags**: `hug bc` instead of `git checkout -b`
- **Progressive safety**: Shorter commands = safer (`hug a` stages tracked only, `hug aa` stages everything)
- **Semantic prefixes**: Commands grouped by purpose (`s*` = status, `w*` = working dir, `h*` = HEAD)

### Clearer Intent
- **Named operations**: `hug h back` vs `git reset --soft HEAD~1`
- **Explicit danger**: `hug h rewind` makes destructive intent obvious
- **Auto-backups**: Destructive operations create backup branches automatically

### Built-in Safety
- **Confirmation prompts**: Destructive commands ask for verification
- **Dry-run mode**: Preview operations with `--dry-run`
- **Sensible defaults**: Interactive selection, scoped operations

::: info Coming from Git?
You already understand Git's concepts (commits, branches, staging). Hug just gives you better commands to manipulate them. Think of it as a Git UX upgrade.
:::

## Essential Commands (Tier 1)

These are the commands you'll use daily. Master these first.

### Status & Inspection

See what's changed in your repository.

| Git Command | Hug Equivalent | Memory Hook | Why Hug is Better |
|-------------|----------------|-------------|-------------------|
| `git status` | `hug sl` | **S**tatus + **L**ist | Cleaner colored output, shows tracked files only by default |
| `git status -u` | `hug sla` | **S**tatus + **L**ist **A**ll | Consistent naming, clear intent |
| `git diff` | `hug su` | **S**tatus + **U**nstaged | Shows patch + stats automatically |
| `git diff --staged` | `hug ss` | **S**tatus + **S**taged | Consistent naming, auto stats |
| `git diff HEAD` | `hug sw` | **S**tatus + **W**orking | Combined view of all changes |

**Key insight**: Hug's `s*` commands are all about **seeing** your repository state. The suffix tells you what to look at.

### Staging

Prepare changes for commit.

| Git Command | Hug Equivalent | Memory Hook | Why Hug is Better |
|-------------|----------------|-------------|-------------------|
| `git add <files>` | `hug a` | **A**dd tracked | Stages tracked only (safer default) |
| `git add -A` | `hug aa` | **A**dd **A**ll | Clear intent, shorter to type |
| `git add -p` | `hug ap` | **A**dd + **P**atch | Consistent prefix, easier to remember |
| `git reset <files>` | `hug us <files>` | **U**n**S**tage | Clear unstage operation |
| `git reset` | `hug usa` | **U**n**S**tage **A**ll | Explicit unstage all |

**Key insight**: Hug separates **staging** (`a*`) from **unstaging** (`us*`), making operations reversible and intentional.

### Commits

Save your changes to history.

| Git Command | Hug Equivalent | Memory Hook | Why Hug is Better |
|-------------|----------------|-------------|-------------------|
| `git commit` | `hug c` | **C**ommit | Works with staged, shorter to type |
| `git commit -a -m` | `hug ca` | **C**ommit **A**ll | One command vs flag combo |
| `git commit -a -A -m` | `hug caa` | **C**ommit **A**ll **A**ll | Includes untracked files explicitly |
| `git commit --amend` | `hug cm` | **C**ommit **M**odify | Clearer intent, safer workflow |

::: warning A Critical Difference
`hug cm` (amend) adds **staged files** to the last commit. Always run `hug sls` first to check what's staged, or use `hug usa` to unstage everything if you only want to change the message.
:::

**Key insight**: Hug's `c*` commands follow a brevity hierarchy: `c` (staged only) → `ca` (all tracked) → `caa` (everything).

### Branching

Manage parallel development.

| Git Command | Hug Equivalent | Memory Hook | Why Hug is Better |
|-------------|----------------|-------------|-------------------|
| `git branch` | `hug bl` | **B**ranch **L**ist | Verbs, not nouns |
| `git branch -a` | `hug bla` | **B**ranch **L**ist **A**ll | Consistent naming |
| `git checkout -b` | `hug bc` | **B**ranch **C**reate | Single command, no flags |
| `git switch` / `git checkout` | `hug b` | **B**ranch | Interactive menu by default |
| `git branch -d` | `hug bdel` | **B**ranch **DEL**ete | Safer default, checks for merged status |

::: tip Interactive Branch Switching
Run `hug b` without arguments to get an interactive menu showing all branches. Use `hug br` for remote branches only.
:::

**Key insight**: Hug uses **verbs** for actions (list, create, delete) instead of Git's overloaded `checkout` command.

### Log & History

View your project's timeline.

| Git Command | Hug Equivalent | Memory Hook | Why Hug is Better |
|-------------|----------------|-------------|-------------------|
| `git log --oneline` | `hug l` | **L**og | Default is useful, no flags needed |
| `git log -p` | `hug ll` | **L**og **L**ong | Consistent naming, includes patches |
| `git log --stat` | `hug lol` | **L**og **O**utgoing **L**ong | Memory hooks for variants |
| `git log --grep="term"` | `hug lf "term"` | **L**og **F**ilter | Shorter, clearer intent |
| `git log -S"code"` | `hug lc "code"` | **L**og **C**ode | Search changes, not just messages |

::: tip Outgoing Commits
Before pushing, run `hug lol` (**L**og **O**utgoing **L**ong) to see exactly what will be pushed. It shows commits, file stats, and patches.
:::

**Key insight**: Hug's `l*` commands use memorable suffixes to indicate what you're looking at (outgoing, filter, code, file).

### Syncing with Remote

Push and pull changes.

| Git Command | Hug Equivalent | Memory Hook | Why Hug is Better |
|-------------|----------------|-------------|-------------------|
| `git push -u` | `hug bpush` | **B**ranch **Push** | Sets upstream automatically |
| `git pull` | `hug bpull` | **B**ranch **Pull** | Fast-forward only (safer, rejects merge commits) |
| `git pull --rebase` | `hug bpullr` | **B**ranch **Pull** **R**ebase | Linear history, explicit intent |
| `git push --force` | `hug bpushf` | **B**ranch **Push** **F**orce | Safer force-push (requires --force-with-lease equivalent) |

::: warning Safe by Default
`hug bpull` only fast-forwards. If a merge or rebase would be needed, it fails and asks you to decide. This prevents accidental merge commits.
:::

**Key insight**: Hug's sync commands are **branch-scoped** (`b*`), making it clear you're operating on branch relationships.

## Common Workflow Migrations

Real-world translations of Git patterns to Hug patterns.

### "I used to `git commit --amend` constantly"

**Old Git pattern:**
```bash
# Make a change
echo "fix" >> file.txt
git add file.txt
git commit --amend --no-edit
```

**New Hug pattern:**
```bash
# Make a change
echo "fix" >> file.txt
hug a file.txt
hug cm -m "original message"  # Amend with staged files
```

**Why Hug is better:**
- `hug cm` makes amend intent explicit
- Safer workflow: requires checking staged files first
- Auto-creates backup branch (`hug-backup-*`)

### "I used to `git stash` for context switching"

**Old Git pattern:**
```bash
# Park current work
git stash push -m "work in progress"

# Switch to other task
git checkout other-branch
# ... work ...

# Switch back
git checkout main
git stash pop
```

**New Hug pattern:**
```bash
# Park current work
hug wip "work in progress"    # Creates WIP/YY-MM-DD/HHmm.slug branch

# Switch to other task
hug b other-branch
# ... work ...

# Switch back and integrate
hug b main
hug w unwip WIP/...           # Squash-merges the WIP branch back
```

**Why Hug is better:**
- WIP branches are **permanent** (won't vanish like stash)
- **Shareable**: Can push WIP branches for backup or feedback
- **Versioned**: Can add multiple commits to a WIP branch
- **Visible**: Appears in `hug bl`, not hidden in a stash list

### "I used to `git reset --soft` to fix commits"

**Old Git pattern:**
```bash
# Go back 2 commits, keeping changes staged
git reset --soft HEAD~2
# Make changes
git add ...
git commit -m "fixed commit"
```

**New Hug pattern:**
```bash
# Go back 2 commits, keeping changes staged
hug h back 2
# Make changes
hug a ...
hug c -m "fixed commit"
```

**Why Hug is better:**
- `hug h back` clearly says "HEAD goes back"
- Auto-creates backup branch before moving
- Consistent with other `h*` commands (`undo`, `rewind`, `rollback`)

### "I used to `git clean` to remove untracked files"

**Old Git pattern:**
```bash
# Remove untracked files
git clean -fd

# Nuke everything (tracked + untracked)
git reset --hard HEAD
git clean -fd
```

**New Hug pattern:**
```bash
# Remove untracked/ignored files
hug w purge <path>

# Nuke everything (tracked + untracked)
hug w zap <path>
```

**Why Hug is better:**
- **Progressive destructiveness**: `purge` < `zap`
- Clear intent: `zap` sounds dangerous (and is)
- Confirmation prompts prevent accidents
- `--dry-run` to preview first

## Key Concept Shifts

Hug isn't just different commands—it's a different philosophy.

### Stash → WIP Workflow

**Git's stash:**
- Single temporary holding area
- Stack-based (LIFO)
- Lost if machine fails or you rebase
- Cryptic listing (`git stash list`)

**Hug's WIP:**
- Real, timestamped branches (`WIP/YY-MM-DD/HHmm.slug`)
- Multiple WIPs can coexist
- Permanent, shareable, pushable
- Clear naming in branch list

### Reset Modes → h* Commands

**Git's reset modes** (one command, different flags):
- `git reset --soft` → keeps changes staged
- `git reset` (mixed) → keeps changes unstaged
- `git reset --hard` → discards everything

**Hug's distinct commands** (separate verbs):
- `hug h back` → HEAD back, keeps staged
- `hug h undo` → HEAD back, keeps unstaged
- `hug h rewind` → HEAD back, discards all

**Why this matters:**
- Explicit intent prevents mistakes
- Muscle memory builds on meaningful verbs
- Auto-backups on all operations

### Safety by Default

**Git:** Assumes you know what you're doing
- `git reset --hard` destroys work immediately
- `git clean -fd` deletes without asking
- Force push is one flag away

**Hug:** Assumes you might make mistakes
- Destructive commands require confirmation
- `--dry-run` to preview operations
- Auto-backups on HEAD operations
- Force operations require explicit intent

## Progressive Expansion

Ready for more? These commands are useful for power users.

<details>
<summary>Intermediate Commands (Tier 2) - Click to expand</summary>

### Undo Operations

| Git Command | Hug Equivalent | Memory Hook | Why Hug is Better |
|-------------|----------------|-------------|-------------------|
| `git reset --soft HEAD~1` | `hug h back` | **H**EAD **Back** | Clearer, keeps staged, auto-backup |
| `git reset HEAD~1` | `hug h undo` | **H**EAD **Undo** | Keeps unstaged, auto-backup |
| `git reset --hard HEAD~1` | `hug h rewind` | **H**EAD **Rewind** | More explicit danger, auto-backup |
| `git revert` | `hug revert` | **Revert** | Same concept, Hug auto-backups first |

### Cleaning Operations

| Git Command | Hug Equivalent | Memory Hook | Why Hug is Better |
|-------------|----------------|-------------|-------------------|
| `git checkout -- file` | `hug w discard <file>` | **W**orking dir **Discard** | Consistent `w*` prefix |
| `git reset --hard` | `hug w wipe-all` | **W**orking dir **Wipe** **A**ll | Progressive danger level |
| `git clean -fd` | `hug w purge <path>` | **W**orking dir **P**urge | Consistent prefix, scoped |
| `git reset --hard && git clean -fd` | `hug w zap <path>` | **W**orking dir **Z**ap | Single command, explicit danger |

**Progressive destructiveness**: `discard` < `wipe` < `purge` < `zap` < `rewind`

### Merge Operations

| Git Command | Hug Equivalent | Memory Hook | Why Hug is Better |
|-------------|----------------|-------------|-------------------|
| `git merge --squash` | `hug m` | **M**erge | Squash by default (safer) |
| `git merge` | `hug mkeep` | **M**erge **Keep** | Explicit about keeping commits |
| `git merge --ff-only` | `hug mff` | **M**erge **F**ast-**F**orward | Clear intent, safer |
| `git merge --abort` | `hug ma` | **M**erge **A**bort | Consistent abort pattern |

</details>

<details>
<summary>Advanced Commands (Tier 3) - Click to expand</summary>

### Rebase

| Git Command | Hug Equivalent | Memory Hook | Why Hug is Better |
|-------------|----------------|-------------|-------------------|
| `git rebase` | `hug rb` | **R**ebase | Consistent `r*` prefix |
| `git rebase -i` | `hug rbi` | **R**ebase **I**nteractive | Easier to remember |
| `git rebase --continue` | `hug rbc` | **R**ebase **C**ontinue | Consistent continue/abort pattern |
| `git rebase --abort` | `hug rba` | **R**ebase **A**bort | Consistent continue/abort pattern |

### File Inspection

| Git Command | Hug Equivalent | Memory Hook | Why Hug is Better |
|-------------|----------------|-------------|-------------------|
| `git blame` | `hug fblame` | **F**ile **Blame** | `f*` prefix for file operations |
| `git log --follow -p file` | `hug llfp <file>` | **L**og **L**ookup **F**ile + **P**atch | Composable, memorable |
| `git log --follow --stat file` | `hug llfs <file>` | **L**og **L**ookup **F**ile + **S**tat | Composable, memorable |

### Search Operations

| Git Command | Hug Equivalent | Memory Hook | Why Hug is Better |
|-------------|----------------|-------------|-------------------|
| `git log --grep="term"` | `hug lf "term"` | **L**og **F**ilter | Shorter, clearer |
| `git log -S"code"` | `hug lc "code"` | **L**og **C**ode | Search code changes |
| `git log --author="name"` | `hug lau "name"` | **L**og **A**uthor **U**ser | Clear author search |
| `git log --since="date"` | `hug ld --since="date"` | **L**og **D**ate | Date-based filtering |

### Tagging

| Git Command | Hug Equivalent | Memory Hook | Why Hug is Better |
|-------------|----------------|-------------|-------------------|
| `git tag` | `hug t` | **T**ag | Simple list |
| `git tag <name>` | `hug tc <name>` | **T**ag **C**reate | Lightweight by default |
| `git tag -a <name>` | `hug ta <name>` | **T**ag **A**nnotated | Explicit annotation |
| `git show <tag>` | `hug ts <tag>` | **T**ag **S**how | Consistent show pattern |

### Computational Analysis (Hug Exclusive)

These have **no Git equivalent**—they're impossible with Git's plumbing alone.

| Hug Command | Memory Hook | What It Does |
|-------------|-------------|--------------|
| `hug analyze co-changes` | **Co**-changes | Find files that change together (statistical correlation) |
| `hug analyze expert <file>` | **Expert** | Who knows this code? (recency-weighted ownership) |
| `hug analyze deps <commit>` | **Dep**endencies | Find related commits via file overlap |
| `hug analyze activity` | **Activity** | When/how does your team commit? |
| `hug stats file <file>` | **Stats** **File** | File metrics (commits, authors, churn) |

::: tip Why No Git Equivalent?
These require graph algorithms, statistical analysis, and data processing beyond Git's scope. Hug uses Python helpers to compute insights from Git history.
:::

</details>

## Next Steps

You've got the essentials—now dive deeper:

- **[Command Map](command-map.md)** - Complete catalog of all 139+ commands
- **[Cheat Sheet](cheat-sheet.md)** - Scenario-based quick reference
- **[Getting Started](getting-started.md)** - Installation and first-time setup
- **[Workflows](workflows.md)** - Advanced patterns and real-world scenarios

::: tip Still Using Git Commands?
Hug can run Git commands too. If you forget the Hug equivalent, type your Git command as usual—Hug will pass it through to Git.
:::

## Quick Reference Card

Print this out for your desk until you build muscle memory:

| I want to... | Git | Hug |
|--------------|-----|-----|
| See status | `git status` | `hug sl` |
| Stage tracked | `git add` | `hug a` |
| Stage all | `git add -A` | `hug aa` |
| Commit staged | `git commit` | `hug c` |
| Commit all tracked | `git commit -a -m` | `hug ca` |
| Amend last commit | `git commit --amend` | `hug cm` |
| Create branch | `git checkout -b` | `hug bc` |
| Switch branch | `git checkout` | `hug b` |
| List branches | `git branch` | `hug bl` |
| Show log | `git log --oneline` | `hug l` |
| Show diff | `git diff` | `hug su` |
| Show staged diff | `git diff --staged` | `hug ss` |
| Push | `git push -u` | `hug bpush` |
| Pull (ff-only) | `git pull` | `hug bpull` |
| Park work | `git stash` | `hug wip` |
| Undo last commit (keep staged) | `git reset --soft HEAD~1` | `hug h back` |
| Undo last commit (keep unstaged) | `git reset HEAD~1` | `hug h undo` |
| Discard file changes | `git checkout -- file` | `hug w discard file` |
