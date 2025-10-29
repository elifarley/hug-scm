# VHS Screencasts for Hug SCM Documentation

This directory contains VHS tape files that generate animated GIFs and static PNG screenshots for the Hug SCM documentation.

## Overview

VHS (Video Handshake) is a tool for generating terminal GIFs and screenshots from plain text instructions. We use it to create consistent, reproducible visual documentation for Hug commands.

## Directory Structure

```
screencasts/
├── bin/
│   ├── vhs-build.sh       # Script to build GIFs/PNGs from tape files
│   └── repo-setup.sh      # Script to create demo repository
├── *.tape                 # VHS tape files (input)
└── README.md             # This file

Generated outputs go to:
└── ../commands/img/       # Generated GIFs and PNGs (output)
```

## Prerequisites

1. **VHS**: Install from https://github.com/charmbracelet/vhs
   ```bash
   # macOS
   brew install vhs
   
   # Linux (using Go)
   go install github.com/charmbracelet/vhs@latest
   ```

2. **Hug SCM**: Must be installed and activated
   ```bash
   make install
   source bin/activate
   ```

3. **Demo Repository**: Required for realistic examples
   ```bash
   make demo-repo
   ```

## Creating Tape Files

### Basic Tape Structure

```tape
# Output file (relative to tape location)
Output ../commands/img/command-name.gif

# Requirements
Require echo
Require hug

# Terminal settings
Set Shell "fish"
Set FontSize 13
Set Width 1020
Set Height 400
Set Theme "Afterglow"

# Hide initial setup
Hide
Type "cd /tmp/demo-repo" Enter
Sleep 500ms
Type "clear" Enter
Sleep 200ms
Show

# Demonstrate the command
Type "hug command" Enter
Sleep 2s

# For PNG screenshots, use:
Screenshot ../commands/img/command-name.png
```

### Tape File Naming Convention

- `hug-<command>.tape` - Single command demonstration
- `hug-<command>-states.tape` - Multiple states of a command
- `hug-<command>-<variation>.tape` - Specific variation or scenario

### Output File Types

- **GIF** (`Output file.gif`) - Animated demonstrations showing command execution
- **PNG** (`Screenshot file.png`) - Static screenshots of command output

## Building Screencasts

### Build All Tapes

```bash
make vhs
# or
make vhs-build
```

### Build Specific Tape

```bash
make vhs-build-one TAPE=hug-lol.tape
# or directly
bash docs/screencasts/bin/vhs-build.sh hug-lol.tape
```

### Preview Without Building (Dry Run)

```bash
make vhs-dry-run
# or
bash docs/screencasts/bin/vhs-build.sh --dry-run --all
```

### Check VHS Installation

```bash
make vhs-check
```

### Clean Generated Files

```bash
make vhs-clean
```

## Tape File Best Practices

### 1. Use Demo Repository

Always use `/tmp/demo-repo` for consistent, reproducible demos:

```tape
Hide
Type "cd /tmp/demo-repo" Enter
Sleep 500ms
Type "clear" Enter
Sleep 200ms
Show
```

### 2. Clean State

Start with a clean state and clean up after:

```tape
# At start
Hide
Type "hug w zap-all -f" Enter
Sleep 500ms

# At end (optional, for cleanup)
Hide
Type "hug w zap-all -f" Enter
```

### 3. Appropriate Timing

- Use `Sleep` to give users time to read output
- Typical values:
  - `Sleep 500ms` - After command execution
  - `Sleep 1s-2s` - For reading short output
  - `Sleep 3s-5s` - For reading detailed output
  - `Sleep 200ms` - Between setup commands

### 4. Set Typing Speed

```tape
Set TypingSpeed 40ms  # Default typing speed
Type@60ms "slow typing" Enter
Type@0ms "instant typing" Enter
```

### 5. Hide Setup Commands

Use `Hide`/`Show` to hide setup and cleanup:

```tape
Hide
Type "setup commands here" Enter
Type "clear" Enter
Show
Type "user-visible command" Enter
```

### 6. Consistent Dimensions

Standard dimensions for consistency:

- **Width**: 1020px (fits documentation well)
- **Height**: 
  - 280-400px for simple commands
  - 600-800px for detailed output
  - 1000px+ for multi-command workflows
- **FontSize**: 13 (readable, not too large)
- **Theme**: "Afterglow" (matches Hug aesthetic)

### 7. Add Comments

Use inline comments to explain what's being shown:

```tape
Type "hug sl  # Status with list of changes" Enter
```

## Existing Tape Files

### Current Tapes

1. **hug-lol.tape**
   - Demonstrates: `hug lol` - Log Outgoing Long
   - Output: `hug-lol.gif` (animated)
   - Shows: Preview of commits before pushing

2. **hug-lo.tape**
   - Demonstrates: `hug lo` - Log Outgoing (quiet)
   - Output: `hug-lo.png` (static)
   - Shows: Quick preview of outgoing commits

3. **hug-sl-states.tape**
   - Demonstrates: `hug sl` in 4 different states
   - Output: 4 separate PNGs
     - `hug-sl-clean.png` - Clean working directory
     - `hug-sl-unstaged.png` - Unstaged changes only
     - `hug-sl-staged.png` - Staged changes only
     - `hug-sl-mixed.png` - Both staged and unstaged
   - Shows: Different states of the working directory

4. **hug-status-changes.tape**
   - Demonstrates: Status commands workflow
   - Output: `hug-status-changes.gif` (animated)
   - Shows: `hug sl`, `hug ss`, `hug su`, `hug sw` in action

5. **Logging Commands**
   - `hug-l.tape` - Basic log with graph
   - `hug-ll.tape` - Detailed log
   - `hug-la.tape` - Log all branches
   - `hug-lla.tape` - Detailed log all branches
   - `hug-lp.tape` - Log with patches
   - `hug-lf.tape` - Log message filter
   - `hug-lc.tape` - Log code search
   - `hug-lau.tape` - Log by author
   - `hug-ld.tape` - Log by date
   - `hug-llf.tape` - Log file history

6. **Branching Commands**
   - `hug-bl.tape` - List local branches
   - `hug-bla.tape` - List all branches
   - `hug-blr.tape` - List remote branches
   - `hug-bll.tape` - Detailed branch list

7. **File Inspection Commands**
   - `hug-fblame.tape` - File blame
   - `hug-fcon.tape` - File contributors
   - `hug-fa.tape` - File authors
   - `hug-fborn.tape` - File origin

8. **Working Directory Commands**
   - `hug-w-discard.tape` - Discard changes
   - `hug-w-purge.tape` - Purge untracked files

9. **HEAD Operations Commands**
   - `hug-h-back.tape` - Move HEAD back
   - `hug-h-undo.tape` - Undo commit
   - `hug-h-files.tape` - Preview files

## Adding Screencasts to Documentation

### Reference Generated Images

In markdown documentation:

```markdown
- ![hug lol example](img/hug-lol.gif)
- ![hug lo example](img/hug-lo.png)
```

### Multiple State Screenshots

For commands with multiple states, show all relevant ones:

```markdown
#### Clean Working Directory
![Clean state](img/hug-sl-clean.png)

#### With Unstaged Changes
![Unstaged changes](img/hug-sl-unstaged.png)

#### With Staged Changes
![Staged changes](img/hug-sl-staged.png)

#### Mixed (Staged + Unstaged)
![Mixed state](img/hug-sl-mixed.png)
```

## Troubleshooting

### VHS Not Found

```bash
# Check if installed
make vhs-check

# Install VHS
brew install vhs  # macOS
go install github.com/charmbracelet/vhs@latest  # Linux
```

### Demo Repository Missing

```bash
# Create demo repository
make demo-repo

# Rebuild from scratch
make demo-repo-rebuild

# Check status
make demo-repo-status
```

### Tape Fails to Build

1. Check VHS installation: `make vhs-check`
2. Check demo repo exists: `ls -la /tmp/demo-repo`
3. Verify Hug is activated: `hug help`
4. Run tape directly to see errors: `cd docs/screencasts && vhs tape-file.tape`

### Generated Images Not Showing

1. Check output path in tape file matches documentation reference
2. Verify images are in `docs/commands/img/`
3. Clear VitePress cache: `make clean`
4. Rebuild documentation: `make docs-build`

## CI/CD Integration

The VHS build process is integrated into documentation builds:

```makefile
docs-dev: vhs    # Builds GIFs before starting dev server
docs-build: vhs  # Builds GIFs before building docs
docs-preview: vhs # Builds GIFs before preview
```

## Suggested Tape Files to Create

Commands that would benefit from visual documentation:

### Status & Staging
- [x] `hug-sl-states.tape` - Status list in different states
- [ ] `hug-ss.tape` - Staged diff
- [ ] `hug-su.tape` - Unstaged diff
- [ ] `hug-sw.tape` - Working directory diff

### Logging
- [x] `hug-lol.tape` - Log outgoing long (exists)
- [x] `hug-lo.tape` - Log outgoing quiet
- [x] `hug-l.tape` - Basic log with graph
- [ ] `hug-ll.tape` - Detailed log
- [ ] `hug-lf.tape` - Log message filter

### Branching
- [x] `hug-branch.tape` - Branch switching, creation, and listing

### Commits
- [x] `hug-commit.tape` – Demonstrates: `c`, `ca`

### HEAD Operations
- [x] `hug-head.tape` – Demonstrates: `h back`, `h undo`, `h rewind`

### Working Directory
- [x] `hug-working-dir.tape` – Demonstrates: `w discard`, `w wipe`, `w purge`, `w zap`

## Tips

1. **Test Before Committing**: Always run `make vhs-dry-run` first
2. **Keep Tapes Simple**: Focus on one command or workflow per tape
3. **Use Consistent Styling**: Follow the established theme and dimensions
4. **Comment Liberally**: Explain what each section does
5. **Clean Up**: Reset state at the end of tape files
6. **Version Control**: Commit tape files, not generated images (add to .gitignore if needed)

## Resources

- [VHS Documentation](https://github.com/charmbracelet/vhs)
- [VHS Examples](https://github.com/charmbracelet/vhs/tree/main/examples)
- [Hug SCM Documentation](../index.md)
