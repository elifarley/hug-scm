# Hug SCM for Entry-Level Developers: A Practical Guide

Git is powerful, but its commands can feel overwhelming. Enter Hug SCM – a humane interface that makes version control intuitive and safe. This guide walks you through real-world scenarios using Hug, so you can focus on coding, not memorizing Git syntax.

## What is Hug SCM and Why Should You Care?

Imagine accidentally deleting code, breaking a feature during experimentation, or clashing changes in a team. Hug solves these by wrapping Git in simple, descriptive commands like `hug s` for status or `hug w discard` to safely undo mistakes.

Hug is your friendly time machine for code: track changes, experiment fearlessly, and collaborate smoothly – all with natural language commands.

## Getting Started: Your First Repository

### Use Case 1: Starting a New Project

You're building a personal portfolio. Set up Hug tracking from scratch.

```shell
# Create your project folder
mkdir my-portfolio
cd my-portfolio

# Initialize Git (Hug works on top of it)
git init

# Create your first file
echo "# My Portfolio" > README.md

# Check status with Hug
hug s

# Stage the file
hug a README.md

# Make your first commit
hug c "Initial commit: Add README"
```

**What just happened?** You created a repository and saved your first snapshot. Hug's `s` gives a quick, colorful summary.

### Use Case 2: Building Your Project with Regular Commits

Adding pages to your portfolio? Commit as you go.

```shell
# Create an HTML file
touch index.html

# Add some code, then check status
hug s

# Stage and commit
hug a index.html
hug c "Add homepage structure"

# Add CSS
touch styles.css
hug a styles.css
hug c "Add base styling"

# View your history
hug l
```

**Pro tip:** Commit small, meaningful changes. Hug's `c` prompts for a message if needed, keeping your history clear.

## Working with Remote Repositories (GitHub)

### Use Case 3: Backing Up Your Work

Save your portfolio online for sharing.

```shell
# On GitHub, create a new repository (don't initialize with README)

# Connect your local repo to GitHub
git remote add origin https://github.com/yourusername/my-portfolio.git

# Push your code with Hug
hug bpush
```

Now your code is backed up with a shareable URL. Hug's `bpush` handles setting upstream automatically.

### Use Case 4: Cloning a Project to Work On

Joining a team or open source?

```shell
# Clone the repository
git clone https://github.com/company/project-name.git

# Navigate into it
cd project-name

# Check branches
hug bl

# Start working
# ... make changes ...

# Stage, commit, and push
hug aa
hug c "Fix navigation bug"
hug bpush
```

## Branching: Experimenting Safely

### Use Case 5: Adding a New Feature

Add a blog without risking your main site.

```shell
# Create and switch to a new branch
hug bc add-blog-section

# Make your changes
touch blog.html
# ... add blog code ...

# Commit on the branch
hug a blog.html
hug c "Add blog page with recent posts"

# Switch back to main
hug bs

# Merge when ready
hug b main
hug m add-blog-section

# Delete the branch
hug bdel add-blog-section
```

**Why branches matter:** Experiment safely. Hug's `bc` creates and switches in one command.

### Use Case 6: Working on Multiple Features

Building a contact form and header redesign?

```shell
# Branch for contact form
hug bc contact-form
# ... work on contact form ...
hug a contact.html
hug c "Add contact form"

# Switch to header work
hug bs
hug bc redesign-header
# ... work on header ...
hug a styles.css index.html
hug c "Redesign header with new logo"

# View branches
hug bl

# Merge both
hug b main
hug m contact-form
hug m redesign-header
```

## Collaboration Scenarios

### Use Case 7: Team Development Workflow

Working with teammates on an e-commerce site.

```shell
# Start day with latest code
hug bpull

# Branch for your task
hug bc add-shopping-cart

# Work and commit
# ... build shopping cart ...
hug a cart.js cart.html
hug c "Implement shopping cart functionality"

# Push branch
hug bpush

# On GitHub, create Pull Request for review
# After merge, update local main
hug b main
hug bpull
```

### Use Case 8: Handling Merge Conflicts

You and a teammate edited the same file.

```shell
# Merge and get conflict
hug m teammate-branch

# Hug shows: CONFLICT in styles.css

# Open styles.css: markers like <<<<<<< HEAD show conflicts

# Edit to resolve, remove markers, save

# Stage and commit resolution
hug a styles.css
hug c "Resolve styling conflict"
```

## Common Mistakes and How to Fix Them

### Use Case 9: Undoing Changes

Changes not committed? Start over safely.

```shell
# Discard specific file
hug w discard index.html

# Discard all uncommitted
hug w discard-all
```

### Use Case 10: Fixing Your Last Commit

Forgot a file or message typo?

```shell
# Stage forgotten file
hug a forgotten-file.js

# Amend
hug cm "Corrected commit message"
```

### Use Case 11: Reverting a Pushed Commit

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

### Use Case 12: Viewing Changes Before Committing

Review hours of work.

```shell
# Uncommitted changes
hug sw

# Staged changes
hug ss

# Specific file
hug sw index.html
```

### Use Case 13: Working with Stash

Switch tasks quickly.

```shell
# Save work
hug w backup

# Fix bug on main
hug b main
# ... fix ...
hug c "Fix critical bug"

# Restore
hug w restore
```

## Essential .gitignore Patterns

Add to `.gitignore` to exclude junk:

```gitignore
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

# Collab
hug bpull                  # Pull rebase
hug bpush                  # Push branch
```

## Next Steps

Practice with a real project. Start solo, then contribute to open source. Hug makes Git approachable – `hug s` and `hug l` are your allies.

Tools like VS Code's Git integration work great with Hug. For servers without GUI, Hug's commands keep things simple.

Questions? Check `hug --help` or use the search bar. Happy coding!
