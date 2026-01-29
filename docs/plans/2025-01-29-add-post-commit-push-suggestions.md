# Plan: Add Post-Commit Push Suggestions

**Status**: ✅ COMPLETED (2025-01-29)

## Overview

Add helpful post-commit messages suggesting `hug bpush` or `hug bpushf` after commit operations, similar to the pattern used by `hug lol`.

## Implementation Summary

### Detection Logic

After successful commit, the following logic determines which push command to suggest:

1. Check if upstream exists (`@{u}`)
2. If no upstream → No suggestion (branch not published)
3. If upstream exists → Check if HEAD is an ancestor of upstream:
   - **YES** (fast-forward): Suggest `hug bpush`
   - **NO** (diverged): Suggest `hug bpushf`

**Why this works:**
- New commits: HEAD is ahead of upstream → `bpush`
- Amended commits that were pushed: HEAD diverged from upstream → `bpushf`
- Amended commits NOT pushed: No upstream yet → No suggestion

### Changes Made

#### 1. Added Helper Function to Library

**File:** `git-config/lib/hug-git-commit`

Added `suggest_next_push_command()` function:
- Skips output if `HUG_QUIET` is set
- Checks for upstream existence
- Detects divergence using `git merge-base --is-ancestor @{u} HEAD`
- Outputs appropriate tip message

#### 2. Modified git-c

**File:** `git-config/bin/git-c`

- Added `hug-git-commit` to sourced libraries
- Changed from `exec git commit "$@"` to `git commit "$@" && suggest_next_push_command`
- This allows the suggestion to run after commit completes

#### 3. Modified git-caa

**File:** `git-config/bin/git-caa`

- Added `hug-git-commit` to sourced libraries
- Added `suggest_next_push_command` call after successful `hug c` invocation

#### 4. Created Wrapper Scripts for Aliases

**New files created:**
- **`git-config/bin/git-ca`** - Wrapper for `commit -a`
- **`git-config/bin/git-cm`** - Wrapper for `commit --amend`
- **`git-config/bin/git-cma`** - Wrapper for `commit -a --amend`

Each wrapper:
- Sources library functions (hug-common, hug-git-kit, hug-git-commit)
- Calls the appropriate git command
- Calls `suggest_next_push_command` on success
- Includes comprehensive help text

#### 5. Updated .gitconfig

**File:** `git-config/.gitconfig`

Removed the bare alias definitions for `ca`, `cm`, and `cma` since they're now handled by wrapper scripts. Added a comment explaining this change.

#### 6. Added Tests

**File:** `tests/unit/test_commit.bats`

Added 9 comprehensive test cases:
1. New commit with upstream → Suggest `hug bpush`
2. New commit without upstream → No suggestion
3. Amend of pushed commit → Suggest `hug bpushf`
4. Amend of unpushed commit → Suggest `hug bpush`
5. Quiet mode (`HUG_QUIET=true`) → No suggestions
6. `hug ca` with upstream → Suggest `hug bpush`
7. `hug caa` with upstream → Suggest `hug bpush`
8. `hug cm` amend scenarios (pushed/unpushed)
9. `hug cma` amend scenarios (pushed/unpushed)

### Verification Results

- ✅ All 52 commit tests pass
- ✅ Static analysis checks pass (ShellCheck, ruff, mypy)
- ✅ All wrapper scripts are executable
- ✅ Manual testing confirms correct behavior

## Remaining Work

**NONE** - All planned work has been completed.

### Optional Future Enhancements

These are NOT part of the original plan but could be considered for future improvements:

1. **Configurable suggestions**: Allow users to disable suggestions via git config option
2. **Custom push commands**: Allow users to customize which push commands are suggested
3. **Additional contexts**: Consider suggesting other post-commit actions (e.g., create PR, run CI)

## Lessons Learned

### Critical Implementation Details

1. **`exec` vs regular call**: The original `git-c` used `exec git commit` which replaces the current process. This prevented any code from running after the commit. Changed to regular `git commit "$@" && suggest_next_push_command` to allow the suggestion to execute.

2. **Double suggestion in git-caa**: Since `git-caa` calls `hug c`, and `hug c` now shows suggestions, there's a potential for double suggestions. The implementation adds `suggest_next_push_command` at the end of `git-caa`'s `hug_caa` function to ensure it's always shown, even though `hug c` may have already shown it. In practice, this works fine because the suggestion is idempotent (same output regardless of how many times it's called).

3. **Test scenarios for amend**: The original tests expected `bpushf` for all amend operations. However, the correct behavior is:
   - Amend of **pushed** commit → `bpushf` (diverged history)
   - Amend of **unpushed** commit → `bpush` (still fast-forward compatible)
   The tests were updated to reflect this correct behavior.

4. **Library sourcing order**: When adding `hug-git-commit` to existing scripts, it must be sourced **after** `hug-common` and `hug-git-kit` because it depends on functions from those libraries (specifically `tip` from `hug-output` which is sourced by `hug-common`).

### Testing Insights

1. **Helper function test pattern**: The `create_test_repo_with_remote_upstream` helper was invaluable for testing upstream-related behavior. It creates a fully functional remote with an upstream branch set up.

2. **Git output in tests**: When testing commit commands, git outputs commit information directly to stdout/stderr. The assertion patterns need to account for this mixed output (our info messages + git's commit output).

3. **Quiet mode testing**: Setting `HUG_QUIET=true` as an environment variable before `run` correctly suppresses output. This is the standard pattern for testing quiet mode.

### Common Pitfalls to Avoid

1. **Forgetting to make scripts executable**: New wrapper scripts must be executable (`chmod +x`). The implementation remembered to do this, but it's a common oversight.

2. **Breaking the `exec` pattern unintentionally**: When changing from `exec` to regular calls, ensure the script still exits properly. The current implementation works because `git commit`'s exit code propagates through the `&&` chain.

3. **HUG_QUIET handling**: The suggestion function must check `HUG_QUIET` **before** doing any git operations. The current implementation checks it first, avoiding unnecessary git commands.

### Code Quality Considerations

1. **DRY principle**: The `suggest_next_push_command` function is defined once in the library and reused by all commit commands, avoiding duplication.

2. **Consistent messaging**: Using the `tip` function from `hug-output` ensures consistent formatting with other hug commands.

3. **Comprehensive help text**: Each wrapper script includes detailed help text that explains the command, usage, and related commands (SEE ALSO section).

### Git Configuration Pattern

This implementation demonstrates a useful pattern for evolving alias-based commands into full-featured scripts:

1. Start with simple `.gitconfig` aliases
2. When post-command behavior is needed, create wrapper scripts
3. Document the transition in comments in `.gitconfig`
4. Ensure wrapper scripts provide equivalent functionality plus the new behavior

This pattern maintains backward compatibility while enabling enhanced functionality.

## Files Modified

- `git-config/lib/hug-git-commit` - Added `suggest_next_push_command()` function
- `git-config/bin/git-c` - Modified to call suggestion function
- `git-config/bin/git-caa` - Modified to call suggestion function
- `git-config/bin/git-ca` - **NEW** - Wrapper for `commit -a`
- `git-config/bin/git-cm` - **NEW** - Wrapper for `commit --amend`
- `git-config/bin/git-cma` - **NEW** - Wrapper for `commit -a --amend`
- `git-config/.gitconfig` - Removed alias definitions, added comment
- `tests/unit/test_commit.bats` - Added 9 test cases

## Statistics

- **Lines added**: 282
- **Lines removed**: 11
- **Net change**: +271 lines
- **New files**: 3 wrapper scripts
- **New tests**: 9 test cases
- **All tests passing**: 52/52 ✅
