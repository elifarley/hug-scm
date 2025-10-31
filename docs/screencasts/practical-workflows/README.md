# Practical Workflows - Screencasts

This directory contains VHS tape files for generating screenshots used in the practical workflows guide (`docs/practical-workflows.md`).

## Structure

```
practical-workflows/
├── setup.tape              # Workflow-specific setup (uses /tmp/workflows-repo)
├── bin/
│   └── repo-setup.sh       # Creates realistic development repository
├── branch-create.tape      # Creating feature branches
├── wip-workflow.tape       # WIP workflow demonstration
├── commit-modify.tape      # Modifying last commit
├── cherry-pick.tape        # Cherry-picking commits
├── commit-move.tape        # Moving commits between branches
└── head-back.tape          # Undoing local commits
```

## Workflows Repository

The practical workflow tapes use a **realistic development repository** (`/tmp/workflows-repo`) that has:
- A project structure with source files
- Multiple commits representing realistic development history
- Clean but not overly complex setup
- Suitable for demonstrating professional workflows

This is different from:
- The main demo repository (`/tmp/demo-repo`) - used for command reference with complex scenarios
- The beginner repository (`/tmp/beginner-repo`) - minimal and clean for learning basics

## Creating the Workflows Repository

```bash
bash docs/screencasts/practical-workflows/bin/repo-setup.sh
```

This creates `/tmp/workflows-repo` with a realistic project structure.

## Building Screenshots

From this directory:

```bash
# Build single tape
../bin/vhs wip-workflow.tape

# Build all tapes (except setup.tape)
for tape in *.tape; do
    [[ "$tape" != "setup.tape" ]] && ../bin/vhs "$tape"
done
```

Screenshots are generated to: `../../img/practical-workflows/`

## Design Principles

1. **Co-location**: Tapes for `practical-workflows.md` live in `screencasts/practical-workflows/`
2. **Self-contained**: Has its own setup script and configuration
3. **Realistic scenarios**: Shows professional development workflows
4. **Focused on Hug**: Only demonstrates Hug commands, not raw Git commands

## Workflows Demonstrated

- **Branch Creation**: Starting new features the right way
- **WIP Workflow**: Parking and resuming work safely
- **Commit Modify**: Fixing the last commit
- **Cherry-Pick**: Copying commits between branches
- **Commit Move**: Moving commits to correct branches
- **HEAD Operations**: Safely undoing local changes

## Image References

In the markdown, reference images as:
```markdown
![Description](img/practical-workflows/wip-workflow.png)
```
