# Promote `hug c -F -` for Multi-Line Commit Messages Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Update Hug SCM documentation to show `hug c -F -` as the recommended pattern specifically for multi-line or complex commit messages (from LLMs or scripts), while keeping `hug c -m "message"` as the simple, standard pattern for single-line commits.

**Architecture:** Documentation-only change. No code modifications. The plan replaces the complex heredoc-with-substitution syntax `hug c -m "$(cat <<'EOF'...EOF)"` with the simpler Git-native `hug c -F - <<'EOF'` heredoc pattern.

**Tech Stack:** Markdown documentation, Bash help text (heredoc format)

---

## Context

### Why This Change

When LLMs generate multi-line commit messages, the current documentation suggests:
```bash
hug c -m "$(cat <<'EOF'
[message]
EOF
)"
```

This is unnecessarily complex. The simpler Git-native pattern:
```bash
hug c -F - <<'EOF'
[message]
EOF
```

### Pattern Decision Matrix

| Pattern | Use When | Example |
|---------|----------|---------|
| `hug c -m "message"` | Simple single-line (human or LLM) | `hug c -m "Fix typo in README"` |
| `hug c -F - <<'EOF'` | Multi-line from LLM (natural formatting) | Heredoc with literal newlines |

### Why `-F -` with heredoc for multi-line
- LLM writes literal newlines (no `\n` escaping needed)
- Avoids complex `hug c -m "$(cat <<'EOF'...EOF)"` nesting
- Git's native pattern (`-F -` = read from stdin)

---

## Task 1: Update hug-workflow SKILL.md (CRITICAL)

**Files:**
- Modify: `docs/skills/hug-workflow/SKILL.md:28-36`

**Step 1: Read the current content to understand context**

Read: `docs/skills/hug-workflow/SKILL.md` lines 20-45
Purpose: Understand the surrounding context before making changes

**Step 2: Replace the multi-line commit message section**

Find lines 28-35:
```markdown
**Handling multi-line commit messages**

```sh
hug c -m "$(cat <<'EOF'
[1 or more lines of carefully formatted content]
EOF
)"
```
```

Replace with:
```markdown
**Handling commit messages**

Simple single-line (use -m):
```sh
hug c -m "Fix typo in README"
```

Multi-line from LLM (use -F - with heredoc):
```sh
hug c -F - <<'EOF'
feat: add feature

WHY: Users need this feature
WHAT: Implementation details
IMPACT: Benefits
EOF
```

Note: This avoids the complex pattern `hug c -m "$(cat <<'EOF'...EOF)"` while keeping natural multi-line formatting.
```

**Step 3: Verify documentation builds**

Run: `make docs-build`
Expected: Build succeeds with no errors

**Step 4: Commit**

```bash
git add docs/skills/hug-workflow/SKILL.md
git commit -m "docs: promote hug c -F - for multi-line commit messages in SKILL.md

WHY: The current hug-workflow skill recommends the complex pattern
'hug c -m \"\$(cat <<'EOF'...EOF)\" for multi-line messages. This is
unnecessarily nested and confusing for LLMs to generate correctly.

WHAT: Updated docs/skills/hug-workflow/SKILL.md to:
- Show 'hug c -m \"message\"' for simple single-line commits
- Show 'hug c -F - <<'EOF'' for multi-line from LLMs
- Rename section from 'Handling multi-line commit messages' to 'Handling commit messages'
- Add note about why -F - avoids the complex pattern

HOW: Direct documentation replacement following the plan in
docs/plans/2025-01-26-promote-hug-c-F-minus-for-multiline-commits.md

IMPACT: LLMs following the hug-workflow skill will now generate simpler,
more readable commit commands. The -F - pattern is Git-native and
avoids the confusing command substitution nesting.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Add Commit Message Patterns section to commits.md (IMPORTANT)

**Files:**
- Modify: `docs/commands/commits.md` (insert after line 33)

**Step 1: Read the current context**

Read: `docs/commands/commits.md` lines 25-50
Purpose: Find the exact insertion point (before "### Reusing Commit Messages")

**Step 2: Insert the new section**

After line 33 (after the examples closing ``` and blank line), insert:

```markdown
### Commit Message Patterns

Choose the right pattern based on your message complexity:

**Simple single-line** (most common):
```shell
hug c -m "Fix typo in README"
```

**Multi-line from LLM** (natural formatting, no escaping):
```shell
hug c -F - <<'EOF'
feat: add user authentication

WHY: Users need secure login
WHAT: Implemented OAuth2
IMPACT: Improved security
EOF
```

**Why use `-F -` with heredoc for multi-line?**
- LLM writes literal newlines (no `\n` escaping)
- Avoids the complex `hug c -m "$(cat <<'EOF'...EOF)"` nesting
- Git's native convention for stdin (`-F -` reads from standard input)
```

**Step 3: Verify documentation builds**

Run: `make docs-build`
Expected: Build succeeds with no errors
Expected: New section renders correctly with proper formatting

**Step 4: Commit**

```bash
git add docs/commands/commits.md
git commit -m "docs: add Commit Message Patterns section to commits.md

WHY: Users need clear guidance on when to use 'hug c -m' vs 'hug c -F -'
for different commit message scenarios. The main command reference
should document both patterns with context on when each is appropriate.

WHAT: Added new 'Commit Message Patterns' section to docs/commands/commits.md
after line 33, before 'Reusing Commit Messages' section. Shows:
- Simple single-line pattern with -m flag
- Multi-line pattern with -F - and heredoc
- Explanation of why -F - is better for multi-line LLM output

HOW: Inserted new section following the pattern decision matrix from
the implementation plan.

IMPACT: Users consulting the commit command reference will now see
clear guidance on both patterns, enabling them to choose the right
approach for their use case (simple human commits vs LLM-generated
multi-line messages).

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Update help text in git-c script (IMPORTANT)

**Files:**
- Modify: `git-config/bin/git-c:34-40`

**Step 1: Read the full help heredoc**

Read: `git-config/bin/git-c` lines 1-60
Purpose: Understand the complete help heredoc structure before modifying

**Step 2: Update the EXAMPLES section**

Find lines 34-39:
```bash
EXAMPLES:
  hug a file.txt          # Stage a file
  hug c -m "Add feature"  # Commit staged file with message
  hug c -v                # Verbose commit
  hug c -C HEAD~1         # Reuse message from previous commit
  hug c -c main~2         # Reuse and edit message from main branch
```

Replace with:
```bash
EXAMPLES:
  hug a file.txt          # Stage a file
  hug c -m "Add feature"  # Commit with inline message
  hug c -v                # Verbose commit
  hug c -C HEAD~1         # Reuse message from previous commit
  hug c -c main~2         # Reuse and edit message from main branch

Note: For multi-line messages from LLMs, use 'hug c -F - <<'EOF'' (heredoc).
```

**Step 3: Test help text displays correctly**

Run: `source bin/activate && hug help c`
Expected: Help text displays with proper formatting
Expected: New note appears at end of EXAMPLES section

**Step 4: Commit**

```bash
git add git-config/bin/git-c
git commit -m "docs: update git-c help text with multi-line message note

WHY: The 'hug help c' output should guide users toward the correct
pattern for multi-line commit messages from LLMs, just as the
documentation does.

WHAT: Updated git-config/bin/git-c help text EXAMPLES section:
- Changed comment to 'Commit with inline message' (was 'Commit staged file with message')
- Added note about using 'hug c -F - <<'EOF'' for multi-line LLM messages

HOW: Direct help heredoc modification with clear, concise note.

IMPACT: Users running 'hug help c' will now see guidance on the -F -
pattern, aligning the in-app help with the documentation updates in
SKILL.md and commits.md.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Verification and Final Testing

**Files:**
- Test: Manual verification only (no test files to modify)

**Step 1: Verify all documentation builds**

Run: `make docs-build`
Expected: Clean build with no errors or warnings

**Step 2: Manual testing of -F - pattern**

Run the following in a test repo:
```bash
# Create test repo
cd /tmp && mkdir test-hug-f && cd test-hug-f && git init
echo "test" > file.txt
git add file.txt

# Test 1: Piped input
echo "test commit" | hug c -F -
Expected: Commit created with message "test commit"

# Test 2: Multi-line with newlines preserved
printf "multi\nline\nmessage\n" | hug c -F -
Expected: Commit created with multi-line message

# Test 3: Heredoc pattern
hug c -F - <<'EOF'
feat: test feature

WHY: Testing
WHAT: Implementation
IMPACT: Benefits
EOF
Expected: Commit created with properly formatted multi-line message
```

**Step 4: Verify help text**

Run: `source bin/activate && hug help c`
Expected: EXAMPLES section shows updated text with note about -F -

**Step 5: Final documentation review**

Read: `docs/skills/hug-workflow/SKILL.md` lines 28-50
Read: `docs/commands/commits.md` lines 30-60
Read: `git-config/bin/git-c` lines 30-50

Verify:
- New sections render correctly
- Code blocks are properly formatted
- No markdown syntax errors
- Examples are clear and copy-pasteable

**Step 6: No commit needed for verification**

This is the final verification step. If all checks pass, the implementation is complete.

---

## Summary

| File | Change | Type |
|------|--------|------|
| `docs/skills/hug-workflow/SKILL.md` | Replace lines 28-35 (simplify section, add -m single-line, show -F - heredoc for multi-line) | CRITICAL |
| `docs/commands/commits.md` | Add ~20 lines after line 33 (new "Commit Message Patterns" section) | IMPORTANT |
| `git-config/bin/git-c` | Update lines 34-40 (keep examples simple, add note about -F - for multi-line) | IMPORTANT |

**Total:** ~30 lines across 3 files
**Risk:** Low (documentation only, no code changes)
**Testing:** Manual verification + docs build check

---

## Files NOT to Update (per plan)

- `docs/getting-started.md` - Keep simple for beginners
- `docs/practical-workflows.md` - Current examples are appropriate
- Test files and VHS screencasts - These are examples, not documentation
