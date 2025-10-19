# Hug SCM for Entry-Level Developers: A Practical Guide

Git is powerful, but its commands can feel overwhelming. Enter Hug SCM – a humane interface that makes version control intuitive and safe. This guide walks you through real-world scenarios using Hug, so you can focus on coding, not memorizing Git syntax.

## What is Hug SCM and Why Should You Care?

Imagine accidentally deleting code, breaking a feature during experimentation, or clashing changes in a team. Hug solves these by wrapping Git in simple, descriptive commands like `hug s` for status or `hug w discard` to safely undo mistakes.

Hug is your friendly time machine for code: track changes, experiment fearlessly, and collaborate smoothly – all with natural language commands.

[[toc]]

::: info Mnemonic + Workflow Legend
- **Bold letters** in command names highlight the initials that make each alias (for example, `hug sl` → **S**tatus + **L**ist).
- Multi-step workflows appear as ordered lists so you can scan the path before executing commands.
- For deep dives, pair this guide with references like [Status & Staging (s*, a*)](commands/status-staging) or [Working Directory (w*)](commands/working-dir).
:::

## Workflow Cheat Sheet

| Scenario | Command Flow                                                     | Why it works |
| --- |------------------------------------------------------------------| --- |
| Start a fresh project | `hug s` → `hug a` → `hug c`                                      | Snapshot new files, stage cleanly, commit with context. |
| Park work before a hotfix | `hug wip "WIP message"` → `hug bc hotfix` → `hug bs` | Save all changes on a dated WIP branch (pushable!), branch off, then resume later. Preferred over stash for persistence. |
| Park and continue deep work | `hug wips "msg"` → `hug c` → `hug w unwip <wip>` | Isolates experiments; stay for momentum, integrate cleanly. |
| Review before pushing | `hug ss` → `hug su` → `hug sw`                                   | Compare staged vs unstaged diffs, then ship confidently. |
| Clean up experiments | `hug w backup` → `hug w discard-all` → `hug w purge`             | Save a safety net, drop tracked edits, prune generated junk. |
| Undo a public mistake | `hug l` → `hug revert <sha>` → `hug bpush`                       | Find the bad commit, revert it, and push the fix upstream. | 

## Getting Started: Your First Repository

### Use Case 1: Starting a New Project

**Scenario:** You're creating a new project and want to track your code from the beginning.

**Steps:**
1. Initialize the repository: `hug init`
2. Check status: `hug s`
3. Stage all files: `hug aa`
4. Commit: `hug c "Initial commit"`
5. Push to remote: `hug bpush`

**Why it works:** This workflow ensures you capture all files (including new ones) in your first commit, establishing a clean baseline for future changes.

**Mnemonic breakdown:**
- `hug s` → **S**tatus snapshot
- `hug aa` → **A**dd **A**ll
- `hug c` → **C**ommit
- `hug bpush` → **B**ranch **Push**

**Git equivalents:**
- `hug init` = `git init`
- `hug s` = `git status`
- `hug aa` = `git add -A`
- `hug c` = `git commit -m`
- `hug bpush` = `git push origin <branch>`

### Use Case 2: Making Your First Changes

**Scenario:** You've made some code changes and want to commit them.

**Steps:**
1. Check status: `hug s`
2. Stage changes: `hug a`
3. Commit: `hug c "Add login feature"`
4. Push: `hug bpush`

**Why it works:** This workflow helps you review changes before committing, ensuring you only include what you intend to.

**Mnemonic breakdown:**
- `hug s` → **S**tatus snapshot
- `hug a` → **A**dd tracked
- `hug c` → **C**ommit
- `hug bpush` → **B**ranch **Push**

**Git equivalents:**
- `hug s` = `git status`
- `hug a` = `git add -u`
- `hug c` = `git commit -m`
- `hug bpush` = `git push origin <branch>`

::: tip Scenario: Patch-and-Push
**Goal:** Ship a small change without noise.
1. `hug sl` to verify tracked files.
2. `hug ap` to stage only the relevant hunk.
3. `hug ss` to double-check the staged diff, then `hug c "Describe change"`.
4. `hug bpush` to publish.
   :::

## Working with Remote Repositories (GitHub)

### Use Case 3: Undoing Mistakes

**Scenario:** You've made a mistake and want to undo it.

**Sub-scenarios:**
- **Undo last commit (keep changes staged):** `hug h back` (**H**EAD **Back**)
- **Undo last commit (keep changes unstaged):** `hug h undo` (**H**EAD **Undo**)
- **Discard uncommitted changes:** `hug w discard <file>` (**W**orking dir **Discard**)
- **Full cleanup:** `hug w zap-all` (**W**orking dir **Zap** **All**)

**Steps for undoing last commit (keep staged):**
1. Run `hug h back` (**H**EAD **Back**) to soft reset HEAD, keeping changes staged.
2. Inspect with `hug ss` (**S**tatus **S**taged).
3. Re-commit: `hug c "Fixed message"` (**C**ommit).

**Why it works:** Non-destructive; lets you adjust without losing work.

**Mnemonic breakdown:**
- `hug h back` → **H**EAD **Back** (soft reset, staged)
- `hug h undo` → **H**EAD **Undo** (mixed reset, unstaged)
- `hug w discard` → **W**orking dir **Discard** (local changes)
- `hug w zap-all` → **W**orking dir **Zap** **All** (nuclear clean)

**Git equivalents:**
- `hug h back` = `git reset --soft HEAD~1`
- `hug h undo` = `git reset --mixed HEAD~1`
- `hug w discard <file>` = `git checkout HEAD -- <file>`
- `hug w zap-all` = `git reset --hard HEAD && git clean -fd`

### Use Case 4: Cloning a Project to Work On

Joining a team or open source?

**Steps:**
1. Clone: `git clone https://github.com/company/project-name.git`
2. Navigate: `cd project-name`
3. Check branches: `hug bl` (**B**ranch **L**ist)
4. Start working: `# ... make changes ...`
5. Stage all: `hug aa` (**A**dd **A**ll)
6. Commit: `hug c "Fix navigation bug"` (**C**ommit)
7. Push: `hug bpush` (**B**ranch **Push**)

**Why it works:** Gets you up-to-date and contributing quickly.

**Mnemonic breakdown:**
- `hug bl` → **B**ranch **L**ist
- `hug aa` → **A**dd **A**ll (including new files)
- `hug c` → **C**ommit
- `hug bpush` → **B**ranch **Push** (with upstream)

**Git equivalents:**
- `hug bl` = `git branch`
- `hug aa` = `git add -A`
- `hug c` = `git commit -m`
- `hug bpush` = `git push -u origin <branch>`

## Branching: Experimenting Safely

### Use Case 5: Adding a New Feature

Add a blog without risking your main site.

**Steps:**
1. Create and switch: `hug bc add-blog-section` (**B**ranch **C**reate)
2. Make changes: `touch blog.html` `# ... add blog code ...`
3. Stage: `hug a blog.html` (**A**dd)
4. Commit: `hug c "Add blog page with recent posts"` (**C**ommit)
5. Switch back: `hug bs` (**B**ranch **S**witch back)
6. Switch to main: `hug b main` (**B**ranch)
7. Merge: `hug m add-blog-section` (**M**erge)
8. Delete: `hug bdel add-blog-section` (**B**ranch **Del**ete)

**Why it works:** Branches isolate work; merge integrates safely.

**Mnemonic breakdown:**
- `hug bc` → **B**ranch **C**reate & switch
- `hug a` → **A**dd tracked
- `hug c` → **C**ommit
- `hug bs` → **B**ranch **S**witch back
- `hug b` → **B**ranch switch
- `hug m` → **M**erge
- `hug bdel` → **B**ranch **Del**ete (safe)

**Git equivalents:**
- `hug bc` = `git checkout -b`
- `hug a` = `git add -u`
- `hug c` = `git commit -m`
- `hug bs` = `git checkout -`
- `hug m` = `git merge`
- `hug bdel` = `git branch -d`

  ### Use Case 6: Working on Multiple Features

  Building a contact form and header redesign?

  **Steps:**
    1. Branch for contact: `hug bc contact-form` (**B**ranch **C**reate)
    2. Work: `# ... work on contact form ...`
    3. Stage: `hug a contact.html` (**A**dd)
    4. Commit: `hug c "Add contact form"` (**C**ommit)
    5. Switch back: `hug bs` (**B**ranch **S**witch back)
    6. New branch: `hug bc redesign-header` (**B**ranch **C**reate)
    7. For a spike: `hug wips "Test header variant"` → Stay and experiment, then `hug bs` to park mid-way.
    8. Work: `# ... work on header ...`
    9. Stage: `hug a styles.css index.html` (**A**dd)
    10. Commit: `hug c "Redesign header with new logo"` (**C**ommit)
    11. View: `hug bl` (**B**ranch **L**ist)
    12. Switch: `hug b main` (**B**ranch)
    13. Merge first: `hug m contact-form` (**M**erge)
    14. Merge second: `hug m redesign-header` (**M**erge)

  **Why it works:** Easy switching keeps features isolated.

  **Mnemonic breakdown:**
    - `hug bc` → **B**ranch **C**reate & switch
    - `hug a` → **A**dd
    - `hug c` → **C**ommit
    - `hug bs` → **B**ranch **S**witch back
    - `hug bl` → **B**ranch **L**ist
    - `hug b` → **B**ranch switch
    - `hug m` → **M**erge

  **Git equivalents:**
    - `hug bc` = `git checkout -b`
    - `hug a` = `git add -u`
    - `hug c` = `git commit -m`
    - `hug bs` = `git checkout -`
    - `hug bl` = `git branch`
    - `hug m` = `git merge`

## Collaboration Scenarios

### Use Case 7: Team Development Workflow

Working with teammates on an e-commerce site.

**Steps:**
1. Update: `hug bpull` (**B**ranch **Pull**)
2. Branch: `hug bc add-shopping-cart` (**B**ranch **C**reate)
3. Work: `# ... build shopping cart ...`
4. Stage: `hug a cart.js cart.html` (**A**dd)
5. Commit: `hug c "Implement shopping cart functionality"` (**C**ommit)
6. Push: `hug bpush` (**B**ranch **Push**)
7. Create PR on GitHub.
8. After merge: `hug b main` (**B**ranch)
9. Update: `hug bpull` (**B**ranch **Pull**)

**Why it works:** Syncs team changes, isolates your work.

**Mnemonic breakdown:**
- `hug bpull` → **B**ranch **Pull** (rebase)
- `hug bc` → **B**ranch **C**reate
- `hug a` → **A**dd
- `hug c` → **C**ommit
- `hug bpush` → **B**ranch **Push**
- `hug b` → **B**ranch switch
- `hug bpull` → **B**ranch **Pull**

**Git equivalents:**
- `hug bpull` = `git pull --rebase`
- `hug bc` = `git checkout -b`
- `hug a` = `git add`
- `hug c` = `git commit -m`
- `hug bpush` = `git push -u origin <branch>`
- `hug b` = `git checkout`

### Use Case 8: Handling Merge Conflicts

You and a teammate edited the same file.

**Steps:**
1. Merge: `hug m teammate-branch` (**M**erge)
2. Hug reports: CONFLICT in styles.css
3. Open styles.css: Edit markers like <<<<<<< HEAD
4. Resolve, remove markers, save.
5. Stage: `hug a styles.css` (**A**dd)
6. Commit: `hug c "Resolve styling conflict"` (**C**ommit)

**Why it works:** Guides you through resolution safely.

**Mnemonic breakdown:**
- `hug m` → **M**erge
- `hug a` → **A**dd
- `hug c` → **C**ommit

**Git equivalents:**
- `hug m` = `git merge`
- `hug a` = `git add`
- `hug c` = `git commit -m`

## Common Mistakes and How to Fix Them

### Use Case 9: Undoing Changes

Changes not committed? Start over safely.

**Steps:**
1. Discard file: `hug w discard index.html` (**W**orking dir **Discard**)
2. Discard all: `hug w discard-all` (**W**orking dir **Discard** **All**)

**Why it works:** Targets exactly what you want to reset.

**Mnemonic breakdown:**
- `hug w discard` → **W**orking dir **Discard** (unstaged)
- `hug w discard-all` → **W**orking dir **Discard** **All**

**Git equivalents:**
- `hug w discard <file>` = `git checkout HEAD -- <file>`
- `hug w discard-all` = `git checkout HEAD -- .`

### Use Case 10: Fixing Your Last Commit

Forgot a file or message typo?

```shell
# Stage forgotten file
hug a forgotten-file.js

# Amend
hug cm "Corrected commit message"
```

### Use Case 11: Precise Undo to Last File Change

Need to rewind exactly to when a file was last modified?

```shell
# Find steps back
hug h steps src/app.js    # e.g., "2 steps back from HEAD..."

# Soft undo to that point (keep changes staged)
hug h back 2

# Inspect and re-commit
hug ss
hug c "Refactored app.js with fixes"
```

### Use Case 12: Reverting a Pushed Commit

Broke production? Undo it.

```shell
# Find commit
hug l

# Revert
hug revert abc1234

# Push revert
hug bpush
```

## Advanced But Essential Commands

### Use Case 13: Viewing Changes Before Committing

Review hours of work.

```shell
# Uncommitted changes
hug sw

# Staged changes
hug ss

# Specific file
hug sw index.html
```

### Use Case 14: Working with WIP Branches (Preferred Over Stash)

Switch tasks with persistent WIP branches. Use `wips` to stay and build (e.g., add commits), or `wip` to park briefly.

**Deep Work Flow (`wips`)**:
  ```shell
  # Park current task, stay on WIP for focused prototyping
  hug wips "Draft blog post"
  # Now on WIP/...; continue:
  # ... edit code ...
  hug a . && hug c "Add post rendering"
  # Pause: hug bs (back to main for hotfix)
  # Later resume: hug b WIP/... && hug c "Polish UI"
  # Finish: hug b main && hug w unwip WIP/... (squash-merge + delete)
  hug bpush  # Push integrated changes
  ```

**Quick Interrupt Flow (`wip`)**:
```shell
# Park briefly (e.g., for urgent hotfix), switch back
hug wip "Draft blog post"
# Now back on main; do hotfix: hug bc hotfix-bug && hug c "Fix bug"
hug bpush
# Resume WIP later: hug b WIP/... && hug a . && hug c "Continue post"
# Finish as above.
```

**Why `wips` vs. `wip`?** `wips` suits solo deep dives (stay isolated, version progress with commits). `wip` is better for teams/multi-tasks (quick park, swi  tch to main/hotfix, resume without disrupting flow). Both are pushable—contrast with stash (local-only, no history).

**Why WIP over stash?** Branches are versioned, pushable for backups/collaboration, and easy to list (`hug bl | grep WIP`). Unpark with `hug w unwip` to inte  grate cleanly; discard with `hug w wipdel` if worthless. For quick local saves, stash still works, but use WIP for real progress parking.


## Essential .gitignore Patterns

Add to `.gitignore` to exclude junk:

```.gitignore
# Dependencies
node_modules/
vendor/

# Environment
.env
.env.local

# Builds
dist/
build/
*.min.js

# IDE
.vscode/
.idea/
*.swp

# OS
.DS_Store
Thumbs.db

# Logs
*.log
logs/
```

Stage it with `hug a .gitignore`.

## Best Practices for Entry-Level Developers

**1. Commit often, early**  
Small commits via `hug c` make debugging easier.

**2. Meaningful messages**  
Bad: "fixed"  
Good: "Fix login alignment on mobile" – Hug prompts you.

**3. Pull before push**  
Use `hug bpull` to avoid conflicts.

**4. Branch everything**  
`hug bc feature` – never touch main directly.

**5. Review changes**  
`hug sw` before `hug c`.

**6. No secrets**  
.gitignore + env vars, not commits.

**7. Atomic commits**  
One change per `hug c`.

**8. Park WIP on branches**  
Use `hug wip "msg"` for quick saves (switch back); `hug wips "msg"` to stay and iterate (e.g., `hug c` multiple times). Unpark with `hug unwip` for clean i  ntegration; delete junk with `hug wipdel`.

## Quick Reference Cheat Sheet

```shell
# Setup
git init                   # Start repo
git clone <url>            # Copy repo

# Daily
hug s                      # Status
hug a <file>               # Stage file
hug aa                     # Stage all
hug c "msg"                # Commit
hug bpush                  # Push & upstream

# Branches
hug bl                     # List
hug bc <name>              # Create & switch
hug b <name>               # Switch
hug m <branch>             # Merge
# Inspect
hug l                      # History
hug sw                     # Working changes
hug ss                     # Staged changes

# Undo
hug w discard <file>       # Discard file
hug us <file>              # Unstage
hug cm "msg"               # Amend
hug h back                 # Undo commit, keep staged
hug h steps <file>         # Steps back to last file change (for precise undos)

# Park WIP (preferred over stash)
hug wip "msg"              # Save all changes on WIP branch, switch back
hug wips "msg"             # Save and stay on WIP branch
hug b WIP/<date>/<time>.<slug>        # Resume
hug unwip  WIP/<date>/<time>.<slug> # Unpark: squash-merge to current + delete
hug wipdel WIP/<date>/<time>.<slug> # Discard WIP branch

# Collab
hug bpull                  # Pull rebase
hug bpush                  # Push branch
```

## Next Steps

Practice with a real project. Start solo, then contribute to open source. Hug makes Git approachable – `hug s` and `hug l` are your allies.

Tools like VS Code's Git integration work great with Hug. For servers without GUI, Hug's commands keep things simple.

Questions? Check `hug --help` or use the search bar. Happy coding!
