# Getting Started with Hug SCM

Welcome to Hug SCM! This guide will take you from complete beginner to comfortable user, teaching you the essentials of version control with Hug's humane interface.

[[toc]]

## Why Hug?

Hug SCM provides **four layers of value** over raw Git:

### 1. Humanization - Better UX for Git
- **Brevity Hierarchy**: Shorter = safer (`hug a` stages tracked only; `hug aa` stages everything)
- **Memorable Commands**: `hug back 1` vs `git reset --soft HEAD~1`
- **Progressive Destructiveness**: `discard < wipe < purge < zap < rewind`
- **Semantic Prefixes**: Commands grouped by purpose (`h*` = HEAD, `w*` = working dir, etc.)
- **Built-in Safety**: Auto-backups, confirmations, dry-run on destructive operations
- **Clear Feedback**: Informative messages with ✅ success, ⚠️ warnings, colored output

### 2. Workflow Automation
- **Combined Operations**: `--with-files` = log + file listing in one command
- **Temporal Queries**: `-t "3 days ago"` instead of date math
- **Smart Defaults**: Sensible scoping, interactive file selection
- **Interactive Modes**: Gum-based selection with `--` or `-i`

### 3. Computational Analysis ⭐ (Impossible with Pure Git)
- **Co-change Detection**: Statistical correlation analysis of files that change together
- **Ownership Calculation**: Recency-weighted expertise detection (who knows this code)
- **Dependency Graphs**: Graph traversal to find related commits via file overlap
- **Activity Patterns**: Temporal histograms showing when/how team works
- **Churn Analysis**: Line-level change frequency to identify code hotspots

*These features require Python-based data processing, graph algorithms, and statistical analysis—beyond what Git's plumbing commands can provide.*

### 4. Machine-Readable Data Export 🤖
- **JSON Output**: `--json` flag on analyze, stats, and churn commands
- **Automation Ready**: Build dashboards, integrate with CI/CD, create custom reports
- **Structured Data**: All computational analysis exports to JSON for external tools

## Core Concepts: Your Programming Laboratory

To make Git's abstract concepts more concrete, let's think of your repository as a **high-tech lab facility**. Hug provides a humane layer over Git's core components.

### The Three Areas of Your Lab

Git manages your code across three main areas. Hug's commands give you clear visibility and control over each one.

#### 1. Working Directory - Your Lab Table

These are the actual files on your filesystem.

> [!TIP] Lab Analogy
> Think of your working directory as **the main lab table** in your current lab room. It's where you have all your files laid out in front of you.
>
> You can edit them, add new ones, and delete old ones freely. This is your live, hands-on workspace. Any changes you make here are "live," but they haven't been officially recorded by Hug's security cameras yet.

**Hug's View**:
- `hug su` (**S**tatus + **U**nstaged) shows you the "mess" on your lab table
- `hug w discard` cleans it up

#### 2. The Index (Staging Area) - Your Preparation Counter

A "holding area" where you prepare your next official record, known as a commit.

> [!TIP] Lab Analogy
> This is your lab's **preparation counter**. After completing an experiment on your lab table, you move the results (your changed files) here to be documented and stored.

**Hug's View**:
- `hug a` (**A**dd) and `hug aa` (**A**dd **A**ll) move files from the lab table to the preparation counter
- `hug ss` (**S**tatus + **S**taged) shows you exactly what's on the counter
- `hug us` moves things back to the lab table

#### 3. The Repository (Commits & HEAD) - Your Security Recording

The permanent history of your project, made up of commits.

> [!TIP] Lab Analogy
> A **commit** is like a **labeled moment in your lab's security camera recording**. It's a permanent snapshot of your staged files at a specific point in time. **HEAD** is simply a pointer to the most recent recording you've made on your current timeline.

**Hug's View**:
- `hug c` (**C**ommit) takes everything on the preparation counter and creates that permanent snapshot
- `hug l` lets you review the timeline of all your recordings
- `hug h back` and `hug h undo` move the HEAD pointer back to an earlier recording

### Branches: Your Lab Rooms

As your project grows, you might want to work on a new feature without disturbing the stable, working version of your code.

> [!TIP] Lab Analogy
> A **branch** is like having a **separate lab room** within your main facility. You can experiment with new ideas in this room without affecting the main project. If your experiment is successful, you can merge your findings back into the main room. If not, you can simply close off the room.

**Hug's View**:
- `hug bc new-feature`: Creates a new lab room called `new-feature` and immediately moves you into it
- `hug b main`: Moves you out of your current room and back into the `main` lab room
- The files on your "lab table" (working directory) instantly swap to match the state of the new room you've entered

### The WIP Workflow: A Better Way to Park Work

Other version control systems have a more convoluted "stash" feature that is a single, temporary holding area local to your machine. It can be lost if something happens to your computer.

Hug promotes the **WIP (Work-In-Progress) workflow** as a safer, more robust alternative.

**What is it?** Instead of a stash, `hug wip` (**W**ork **I**n **P**rogress) creates a real, timestamped branch (`WIP/YY-MM-DD/HHmm.slug`). It commits all your current changes (staged, unstaged, and untracked) to this branch.

**Why is it better?**
- **Persistent & Safe**: A WIP branch is part of your repository's history. It won't get lost if you rebase or switch machines.
- **Shareable**: You can push a WIP branch (`hug bpush`) to a remote repository to back it up or get feedback from a teammate.
- **Versioned**: You can continue to work on a WIP branch, adding more commits to document your experiment or spike.
- **Clear**: `hug bl` (**B**ranch **L**ist) gives you a clear, descriptive list of all your parked tasks, unlike the cryptic lists from other tools.

The `wip` / `wips` / `unwip` / `wipdel` commands provide a complete, safe lifecycle for managing temporary work, making it one of Hug's cornerstone features.

## Your First Workflow

This is the simple, repeatable process you'll use every day to save your work.

### Step 1: Create Your Lab Facility (`hug init`)

You have a new project idea, which means you need a place to work. In our analogy, `hug init` (**Init**ialize) gives you a big, empty laboratory facility for your project.

The `hug init` command initializes a new Git repository in your project folder. A repository (or "repo") is essentially your project's dedicated lab facility (with multiple lab rooms), containing all your files and the entire history of their changes.

To create your lab facility, navigate to your project's folder in the terminal and type:

```shell
hug init
```

This creates a hidden `.git` folder, which is the "control center" of your facility where all the history is stored.

### Step 2: Do Your Work (The Lab Table)

Now that you have your lab facility, where do you actually *do* the work? The folder on your computer where your project files are located is your **working directory**.

Think of your working directory as **the main lab table** in your current lab room. It's where you have all your files laid out in front of you. You can edit them, add new ones, and delete old ones freely. This is your live, hands-on workspace.

Let's create a file:

```shell
echo "Hello, World!" > hello.txt
```

### Step 3: Check Your Progress (`hug s`)

How do you know what you've changed? Ask your lab assistant for a status report.

```shell
hug sl
```

[`hug sl` (**S**tatus + **L**ist changes)](commands/status-staging.md#basic-status) gives you a quick, colorful summary of what's going on in your lab. It will tell you about any new or modified files on your lab table.

### Step 4: Prepare Your Snapshot (`hug aa`)

Before creating a permanent save point, you need to tell your lab assistant *what* to include. This is called "**staging**".

The staging area is your lab's **preparation counter**. You move the finished parts of your experiment from the main lab table to this counter, getting them ready to be officially recorded.

The easiest way to do this is with `hug aa`:

```shell
hug aa
```

`hug aa` (**A**dd **A**ll) moves *all* the changes from your lab table to the preparation counter.

Now's a good time to check status with `hug sl`:

### Step 5: Create a Save Point (`hug c`)

Once your changes are on the "preparation counter," you can create a permanent snapshot, called a **commit**.

> [!TIP] Lab Analogy
> A commit is like a **labeled moment in your lab's security camera recording**. It's a snapshot of your project, frozen in time, with a descriptive message.

```shell
hug c -m "Created my first file"
```

`hug c` (**C**ommit) takes everything on the preparation counter and saves it to your project's history. The message is crucial - it's the note you're leaving for your future self!

### The Loop

That's it! Your daily workflow is a simple loop:

#### Pattern 1: Change → Add to Staging → Commit

1. **Make changes** to your code
2. **Check your work** with `hug sl` (optional)
3. **Stage everything** with `hug aa`
4. **Save your progress** with `hug c -m "Describe what you did"`

#### Pattern 2: Change Existing File → Commit

1. **Make changes** to an *existing* file
2. **Check your work** with `hug sl` (optional)
3. **Stage & Save your progress** with `hug ca -m "Describe what you did"`
   - `ca` is for _**C**ommit **A**ll tracked files_

#### Pattern 3: Create New File → Commit

1. **Create new file** and make changes
2. **Check your work** with `hug sla` (optional)
   - `sla` is for **S**tatus + **L**ist **A**ll
3. **Stage & Save your progress** with `hug caa -m "Describe what you did"`
   - `caa` is for _**C**ommit **A**ll tracked **A**nd untracked files_

> [!TIP]
> To learn other possible ways to add files to the staging area and to commit your changes, see:
> - [Status & Staging (s*, a*)](commands/status-staging.md)
> - [Commits (c*)](commands/commits.md)

## Experimenting Safely with Separate Lab Rooms (Branches)

What if you want to try a new, risky idea without messing up your main project? You can create a new **branch**.

> [!TIP] Lab Analogy
> A branch is like a **separate lab room**. You can make a huge mess in there, and it won't affect the clean, stable work in your main room.

### 1. Create and Enter a New Room (`hug bc`)

Let's create a branch to test a new feature.

```shell
hug bc new-idea
```

`hug bc` (**B**ranch: **C**reate) does two things: it creates a new lab room called `new-idea` and immediately moves you inside it.

### 2. Work in Your New Room

Now you're in the `new-idea` room. You can make changes, stage them, and commit them, just like before. This history is completely separate from your main work.

```shell
echo "A brilliant new idea!" > idea.txt
hug a idea.txt
hug c -m "Add my new idea"
```

### 3. Return to the Main Room (`hug b`)

To go back to your main, stable project, just switch back to the `main` branch.

```shell
hug b main
```

`hug b` (**B**ranch) switches you between lab rooms. Notice that `idea.txt` has vanished from your lab table! It's safely stored in the `new-idea` room, waiting for you.

> [!TIP]
> Execute `hug b` without passing a branch name to get an interactive menu showing you all available branches.

### 4. Merge Your Discovery (`hug m`)

If your experiment was a success, you can bring the changes from your experimental room into your main room. This is called a **merge**.

```shell
# Make sure you are in the main room first
hug b main

# Now, merge the work from the other room
hug m new-idea  # This brings in the changes from that branch
hug c -m "Incorporate the new idea"
```

> [!TIP]
> Learn more about [`m*` commands](commands/merge.md) and the [WIP workflow](commands/working-dir.md#wip-workflow)

## Your Ultimate Safety Net: Handling Interruptions & Mistakes

Hug makes it safe to fix common mistakes and handle interruptions without losing your progress.

### Interruption: "I need to switch tasks, but my work isn't ready to commit!"

**Solution**: Use Hug's **WIP (Work-In-Progress) workflow**. This is a safer, more robust alternative to the confusing "stash" feature found in other tools.

`hug wip` (**W**ork **I**n **P**rogress) parks all your changes on a temporary, real branch, keeping your working directory clean (free from uncommitted changes).

```shell
hug wip "Pausing work on the login form"
```

When you're ready to return, `hug w unwip` (**Un**park **WIP**) will bring your changes right back.

### Mistake #1: "I made a typo in my file, but I haven't committed yet."

**Solution**: Just discard the changes from your lab table.

```shell
hug w discard hello.txt  # **W**orking directory **Discard**
```

### Mistake #2: "I just made a commit, but it was wrong!"

**Solution**: Tell your lab assistant to roll back the timeline by one step, but leave all your files on the lab table so you can fix them.

```shell
hug h back  # **H**EAD **Back**
```

This moves HEAD back one commit but **keeps your changes staged**. You can edit them and re-commit correctly.

## Safety Features Built Into Hug

### Auto-Backups

All destructive HEAD operations create automatic backup branches:

```shell
# These commands auto-create hug-backup-* branches
hug h back
hug h rollback
hug h rewind
hug h squash

# List backup branches
hug bl | grep backup

# Restore from backup if needed
hug b <backup-branch-name>
```

### Dry-Run Everything

Always preview destructive operations first:

```shell
# Preview before executing
hug w zap-all --dry-run
hug h rollback --dry-run
hug w purge --dry-run

# Then execute with -f to skip confirmation
hug w zap-all -f  # after reviewing dry-run output
```

### Interactive Selection

Most commands support interactive file/branch/commit selection:

```shell
# Use -- for interactive selection with Gum
hug lc "import" --          # select file to search in
hug w discard --            # select files to discard
hug bdel --                 # select branch to delete

# --browse-root for full repo scope (default: current dir)
hug lc "import" --browse-root
```

## Next Steps

You now know the essential commands to safely manage your code with Hug. You can build entire projects with just this workflow!

When you feel more confident, explore:

- **[Workflows Guide](workflows.md)** - Advanced patterns and real-world scenarios
- **[Command Map](command-map.md)** - Complete command organization
- **[Cheat Sheet](cheat-sheet.md)** - Quick syntax reference

**Ready to dive deeper?** The [Workflows Guide](workflows.md) shows you how to combine these basics into powerful development patterns.
