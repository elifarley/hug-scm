# Design: GIT EQUIVALENTS Help Section for `hug shc` and `hug shcp`

**Date:** 2026-05-05
**Status:** Approved

## Context

Users (especially Claude Code agents) often fall back to raw git commands because they don't know which hug command replaces them. Adding a concise "git equivalent" mapping to the help text makes this discoverable at the point of need.

This is a pilot for two commands. After validation, a comprehensive sweep will add the section to all hug commands.

## Design

### Section name and placement

- **Header:** `GIT EQUIVALENTS:`
- **Placement:** After EXAMPLES, before SEE ALSO
- **Format:** Side-by-side git → hug mapping, 4-5 entries per command

### For `hug shc`

```
GIT EQUIVALENTS:
    git diff --stat HEAD                  →  hug shc
    git diff-tree --stat -r HEAD          →  hug shc HEAD
    git diff --stat HEAD~3..HEAD          →  hug shc -3
    git diff --stat main..HEAD -- '*.py'  →  hug shc main..HEAD -- '*.py'
```

### For `hug shcp`

```
GIT EQUIVALENTS:
    git show HEAD                         →  hug shcp
    git diff HEAD~3..HEAD                 →  hug shcp -3
    git diff main..HEAD                   →  hug shcp main..HEAD
    git diff main..HEAD -- '*.py'         →  hug shcp main..HEAD -- '*.py'
```

## Files to modify

1. `git-config/bin/git-shc` — add GIT EQUIVALENTS section to `show_help()`
2. `git-config/bin/git-shcp` — add GIT EQUIVALENTS section to `show_help()`

## Not in scope

- Other hug commands (deferred to comprehensive sweep)
- Doc/completion changes (help text only)

## Verification

```bash
hug help shc   # Verify section appears
hug help shcp  # Verify section appears
make test-unit TEST_FILE=test_sh.bats  # No regressions
```
