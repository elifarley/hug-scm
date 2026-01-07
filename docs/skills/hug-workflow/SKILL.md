---
name: hug-workflow
description: |
   Git workflow management using Hug (enhanced Git replacement). Use for ALL Git operations.
   Triggers: commit, amend, staging, git status, git log, repo inspection, fixing commits.
   Use whenever Claude needs to: (1) Commit changes, (2) Inspect repo state, (3) Fix/amend commits,
   (4) Stage/unstage files, (5) View history or diffs.
allowed-tools: Bash(hug:*)
---

# Hug Workflow

Hug is a complete Git replacement with enhanced UX and safety features.
Hug accepts existing git commands as well.
CRUCIAL: When you want to run a git command, ALWAYS translate it to a `hug` equivalent instead.

## Critical Safety Rules

**Before EVERY commit, ALWAYS:**
1. Run `hug sla` - See ALL uncommitted files (staged, unstaged, untracked)
2. Stage only intended files (see Staging Decision Tree below)

**CRITICAL for `hug cm` (amend):**
- `hug cm -m 'msg'` adds ANY staged files to the commit
- ALWAYS run `hug sls` first to list staged files
- Use `hug usa` to unstage everything if you want message-only amend

**Handling multi-line commit messages**

```sh
hug c -m "$(cat <<'EOF'
[1 or more lines of carefully formatted content]
EOF
)"
```
`
## Staging Decision Tree

```
Start: hug sla
│
├─ Need to stage files?
│  ├─ Keep some unstaged? → hug a <file1> <file2> ... (selective)
│  └─ Stage ALL tracked? → hug a (no args, tracked files only)
│  └─ Stage untracked too? → hug a <file1> <file2> ... (explicit form)
│
├─ Verify: hug sls (list staged files only)
│
└─ Commit with `hug c -m`
```

**RULE OF THUMB**: If you didn't intentionally create/modify the file as part of your current task, DON'T stage it!

**NEVER stage**: Session artifacts like `.claude/settings.local.json`

## Mapping: High-level intentions to Hug Commands

1. To understand both which files were staged and what changes they contained so I can write an accurate commit message.
   - `hug ss`


## Common Workflows

### Commit Changes

```sh
hug sla                      # List S:*, U:*, UnTrck files
hug a <files>                # Stage specific files
hug sls                      # List S:* files
hug c -m 'message'           # Commit
```

### Inspect Repository State

```sh
hug sla                      # List staged, unstaged, untracked files
hug sls                      # List staged files only
hug sh                       # Last commit details, including list of files
hug llu                      # Outgoing commits (what would be pushed)
```

### Search History

```sh
hug lf "term" -i --all       # Search commit messages
hug lc "code" --all          # Search code changes
hug ll                       # Log with file stats
```

### Fix Last Commit

**Change message ONLY:**
```sh
hug sls                      # CRITICAL: Verify NO files are staged
hug cm -m 'new message'      # Amends message only (keeps files intact)
```

**Change message OR add files:**
```sh
hug sla                      # Check which files to add
hug a <files>                # Add files to stage
hug cm -m 'message'          # Amends (message + staged files)
```

**Remove files from commit:**
```sh
hug back 1                   # Go back, keeping changes staged
hug sls                      # List staged files
hug us <files>               # Unstage unwanted files
hug c -m 'original message'  # Re-commit
```

## Key git -> hug Commands Mapping
ALWAYS use the Hug command that corresponds to the git command you're trying to run:
| Git                              | Hug    | Description                                        |
|----------------------------------|--------|----------------------------------------------------|
| git diff --cached                | hug ss | Show staged changes then file stats                |
| git diff --cached --stat --patch | hug ss | Show staged changes then file stats                |
| git diff --stat --patch          | hug su | Show unstaged changes then file stats              |
| git diff HEAD --stat --patch     | hug sw | Show all working directory changes then file stats |

## Key Commands Reference

**Status & Inspection:**
- `hug sl` - List staged (S:*) and unstaged (U:*) files, with stats
- `hug sls` - List staged files only
- `hug sla` - List staged (S:*), unstaged (U:*) and untracked (UnTrck) files
- `hug sh`  - Last commit with full message and diff stats
- `hug shp` - Same as `hug sh` + diff
- `hug llu` - Outgoing commits
- `hug lol` - Outgoing commits with file stats

**Branch Operations:**
- `hug b <branch>` - Switch branch
- `hug bc <name>` - Create and switch
- `hug bpush` - Push current branch
- `hug bpull` - Pull (fast-forward only, safe)

**Working Directory:**
- `hug discard --force <file>` - Discard unstaged changes
- `hug discard-all --force` - Discard all unstaged
- `hug get <file> <commit>` - Restore file from commit
