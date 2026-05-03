# Add Info Messages for Empty Diffs (su/ss/sw commands) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add info messages to diff commands when there are no changes, matching the behavior of sl* commands.

**Architecture:** Modify three functions in `hug-git-diff` library to call `info()` when no changes are detected. The `info()` function already respects `HUG_QUIET` environment variable.

**Tech Stack:** Bash library functions, existing `info()` helper from `hug-common`

---

## Task 1: Add Info Message to `show_staged_diff()`

**Files:**
- Modify: `git-config/lib/hug-git-diff:161`

**Step 1: Add info message when no staged changes exist**

Replace line 161:
```bash
if diff_has_staged_changes; then
```

With:
```bash
if diff_has_staged_changes; then
```

And add the else clause after line 180 (before the closing `fi`):
```bash
else
  info "No staged changes."
```

**Step 2: Run tests to verify no regressions**

Run: `make test-lib TEST_FILTER="show_staged_diff"`
Expected: PASS (with new info message output in quiet-less mode)

**Step 3: Manual test - clean repo**

```bash
cd /tmp && rm -rf test-staged-info && mkdir test-staged-info && cd test-staged-info
git init
touch file.txt && git add file.txt && git commit -m "initial"
source /home/ecc/IdeaProjects/hug-scm/bin/activate
hug ss
```

Expected output includes: `ℹ️ Info: No staged changes.`

**Step 4: Manual test - quiet mode**

```bash
HUG_QUIET=T hug ss
hug ss -q
```

Expected: No info message (silent)

**Step 5: Manual test - with actual staged changes**

```bash
echo "changed" > file.txt
git add file.txt
hug ss
```

Expected: Shows diff, NOT "No staged changes."

**Step 6: Commit**

```bash
cd /home/ecc/IdeaProjects/hug-scm
git add git-config/lib/hug-git-diff
git commit -m "$(cat <<'EOF'
feat: add info message for empty staged diff

WHY: The sl* commands consistently show info messages when no files are
found, but the ss command shows nothing when there are no staged changes.
This inconsistency creates a confusing user experience.

WHAT: Added "No staged changes." info message to show_staged_diff().

HOW: Added an else clause after the staged changes check that calls
info() with the appropriate message.

IMPACT: Users now get consistent feedback across all status-related commands.
The info() function respects HUG_QUIET, so behavior is unchanged in quiet mode.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude (GLM-4.7) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add Info Message to `show_unstaged_diff()`

**Files:**
- Modify: `git-config/lib/hug-git-diff:258`

**Step 1: Add info message when no unstaged changes exist**

Replace line 258:
```bash
if diff_has_unstaged_changes; then
```

And add the else clause after line 277 (before the closing `fi`):
```bash
else
  info "No unstaged changes."
```

**Step 2: Run tests to verify no regressions**

Run: `make test-lib TEST_FILTER="show_unstaged_diff"`
Expected: PASS (with new info message output)

**Step 3: Manual test - clean repo**

```bash
cd /tmp/test-staged-info  # Using the same test repo
hug su
```

Expected output includes: `ℹ️ Info: No unstaged changes.`

**Step 4: Manual test - quiet mode**

```bash
HUG_QUIET=T hug su
hug su -q
```

Expected: No info message (silent)

**Step 5: Manual test - with actual unstaged changes**

```bash
echo "more changes" > file.txt
hug su
```

Expected: Shows diff, NOT "No unstaged changes."

**Step 6: Commit**

```bash
cd /home/ecc/IdeaProjects/hug-scm
git add git-config/lib/hug-git-diff
git commit -m "$(cat <<'EOF'
feat: add info message for empty unstaged diff

WHY: The sl* commands consistently show info messages when no files are
found, but the su command shows nothing when there are no unstaged changes.

WHAT: Added "No unstaged changes." info message to show_unstaged_diff().

HOW: Added an else clause after the unstaged changes check that calls
info() with the appropriate message.

IMPACT: Users now get consistent feedback across all status-related commands.
The info() function respects HUG_QUIET, so behavior is unchanged in quiet mode.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude (GLM-4.7) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add Info Message to `show_combined_diff()`

**Files:**
- Modify: `git-config/lib/hug-git-diff:391`

**Step 1: Add info message when both unstaged and staged are empty**

Add after line 391 (end of function):
```bash
# Show info message if nothing was displayed
if ! $showed_unstaged && ! $showed_staged; then
  info "No staged or unstaged changes."
fi
```

**Step 2: Run tests to verify no regressions**

Run: `make test-lib TEST_FILTER="show_combined_diff"`
Expected: PASS (with new info message output)

**Step 3: Manual test - clean repo**

```bash
cd /tmp/test-staged-info  # Using the same test repo
hug sw
```

Expected output includes: `ℹ️ Info: No staged or unstaged changes.`

**Step 4: Manual test - quiet mode**

```bash
HUG_QUIET=T hug sw
hug sw -q
```

Expected: No info message (silent)

**Step 5: Manual test - with unstaged changes only**

```bash
echo "unstaged change" > file.txt
hug sw
```

Expected: Shows unstaged diff, NOT "No staged or unstaged changes."

**Step 6: Manual test - with both changes**

```bash
git add file.txt
echo "more" >> file.txt
hug sw
```

Expected: Shows both diffs with separator, NOT "No staged or unstaged changes."

**Step 7: Commit**

```bash
cd /home/ecc/IdeaProjects/hug-scm
git add git-config/lib/hug-git-diff
git commit -m "$(cat <<'EOF'
feat: add info message for empty combined diff

WHY: The sl* commands consistently show info messages when no files are
found, but the sw command shows nothing when there are no changes at all.

WHAT: Added "No staged or unstaged changes." info message to show_combined_diff().

HOW: Added a check at the end of the function that tests both showed_unstaged
and showed_staged flags. If neither is true, calls info() with the message.

IMPACT: Users now get consistent feedback across all status-related commands.
The info() function respects HUG_QUIET, so behavior is unchanged in quiet mode.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude (GLM-4.7) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Verify No Impact on shc/shp/sh Commands

**Files:**
- No changes required (verification only)

**Step 1: Verify shc still works**

```bash
cd /tmp/test-staged-info
hug shc HEAD
```

Expected: Shows commit details (unchanged behavior)

**Step 2: Verify shp still works**

```bash
hug shp HEAD
```

Expected: Shows commit details with diff (unchanged behavior)

**Step 3: Verify sh still works**

```bash
hug sh HEAD
```

Expected: Shows commit details (unchanged behavior)

**Step 4: Run full test suite**

Run: `make test-bash`
Expected: All tests pass

**Step 5: Run diff-specific tests**

Run: `make test-unit TEST_FILE=test_diff.bats`
Expected: All tests pass

---

## Task 5: Update Tests (if needed)

**Files:**
- Modify: `tests/lib/test_hug_git_diff.bats` (if it exists)
- Or: `tests/unit/test_diff.bats` (if the tests are there)

**Step 1: Check for existing tests that expect silent behavior**

```bash
cd /home/ecc/IdeaProjects/hug-scm
grep -n "No staged changes" tests/lib/test_hug_git_diff.bats tests/unit/test_diff.bats 2>/dev/null || echo "No existing tests for this behavior"
```

**Step 2: Update any tests that expect exact output without info messages**

If tests exist that check for empty output when there are no changes, update them to expect the info message instead.

**Step 3: Run the updated tests**

Run: `make test-lib TEST_FILTER="diff"`
Expected: All tests pass

**Step 4: Commit**

```bash
git add tests/
git commit -m "$(cat <<'EOF'
test: update diff tests to expect info messages for empty state

WHY: New info messages are shown when no changes exist. Tests expecting
empty output need to be updated.

WHAT: Updated tests to expect info messages instead of silent output.

HOW: Modified assertions to check for the new info messages.

IMPACT: Tests now accurately reflect the new behavior.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude (GLM-4.7) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Cleanup and Final Verification

**Files:**
- None (verification only)

**Step 1: Clean up test repository**

```bash
rm -rf /tmp/test-staged-info
```

**Step 2: Run full test suite**

Run: `make test`
Expected: All tests pass

**Step 3: Verify git status**

```bash
cd /home/ecc/IdeaProjects/hug-scm
hug sl
```

Expected: Working tree clean (no uncommitted changes)

**Step 4: Verify implementation with quick manual test**

```bash
cd /tmp && rm -rf final-test && mkdir final-test && cd final-test
git init
touch file.txt && git add file.txt && git commit -m "initial"
source /home/ecc/IdeaProjects/hug-scm/bin/activate

# Test all three commands
hug su  # Should show: "Info: No unstaged changes."
hug ss  # Should show: "Info: No staged changes."
hug sw  # Should show: "Info: No staged or unstaged changes."

# Test quiet mode
HUG_QUIET=T hug su  # Silent
HUG_QUIET=T hug ss  # Silent
HUG_QUIET=T hug sw  # Silent

# Test with changes
echo "change" > file.txt
hug su  # Shows diff
git add file.txt
hug ss  # Shows diff
hug sw  # Shows both diffs
```

Expected: All behaviors as described

**Step 5: Cleanup**

```bash
cd /home/ecc/IdeaProjects/hug-scm
rm -rf /tmp/final-test
```

---

## Summary of Changes

**Files modified:**
1. `git-config/lib/hug-git-diff` - Added 3 info message calls

**Total commits:** 3-4 (depending on whether tests need updates)

**Risk:** Very low - The `info()` function is well-tested and respects `HUG_QUIET`. The shc/shp/sh commands are unaffected as they don't use these functions.

**User benefit:** Consistent feedback across all status-related commands, reducing confusion when commands produce no output.
