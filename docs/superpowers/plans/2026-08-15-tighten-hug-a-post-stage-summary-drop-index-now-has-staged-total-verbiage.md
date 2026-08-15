# Tighten "hug a" Post-Stage Summary — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the verbose `hug a` post-stage summary with a tighter format that drops git jargon and lazy plurals.

**Architecture:** Single format string change in `git-config/bin/git-a`, four test assertion updates in `tests/unit/test_add.bats`, and two CHANGELOG entry updates. No new files, no new logic.

**Tech Stack:** Bash (shell script), Bats (test framework)

## Global Constraints

- Preserve the existing plural helper (`[[ $_staged -eq 1 ]] && echo '' || echo 's'`) — only the format string template changes.
- Preserve the printf argument order (`$_staged`, plural helper, `$_index_after`).
- Tests should assert on count number + "staged total now" rather than exact phrasing for resilience to future wording changes.

---

### Task 1: Update format string in `git-config/bin/git-a`

**Files:**
- Modify: `git-config/bin/git-a:77-78`

**Interfaces:**
- Produces: new output format `Staged N file(s). M staged total now.` on stderr

- [ ] **Step 1: Update the printf format string**

In `git-config/bin/git-a`, replace lines 77-78:

```bash
# Before (line 77-78):
    printf 'Staged %d file%s. Index now has %d file(s) staged total.\n' \
      "$_staged" "$([[ $_staged -eq 1 ]] && echo '' || echo 's')" "$_index_after" >&2

# After:
    printf 'Staged %d file%s. %d staged total now.\n' \
      "$_staged" "$([[ $_staged -eq 1 ]] && echo '' || echo 's')" "$_index_after" >&2
```

The only change is the format string template. The three printf arguments and their order are unchanged.

- [ ] **Step 2: Verify the script parses correctly**

Run: `bash -n git-config/bin/git-a`
Expected: exit 0 (no syntax errors)

- [ ] **Step 3: Commit**

```bash
hug c -F - <<'EOF'
fix(hug-a): tighten post-stage summary wording (#278)

Drop "Index now has" jargon and parenthesized (s) plurals from the
second sentence of the hug a post-stage summary.

Before: Staged 1 file. Index now has 1 file(s) staged total.
After:  Staged 1 file. 1 staged total now.

The existing plural helper for the first sentence stays as-is.
Only the printf format string template changes.

Refs: elifarley/hug-scm#278
EOF
```

---

### Task 2: Update test assertions in `tests/unit/test_add.bats`

**Files:**
- Modify: `tests/unit/test_add.bats:19,32,44,53`

**Interfaces:**
- Consumes: new output format from Task 1

- [ ] **Step 1: Update the four test assertions**

In `tests/unit/test_add.bats`, make these four changes:

Line 19:
```bash
# Before:
  assert_output --partial "Index now has 1 file(s) staged total."
# After:
  assert_output --partial "1 staged total now."
```

Line 32:
```bash
# Before:
  assert_output --partial "Index now has 2 file(s) staged total."
# After:
  assert_output --partial "2 staged total now."
```

Line 44:
```bash
# Before:
  assert_output --partial "file(s) staged total."
# After:
  assert_output --partial "staged total now."
```

Line 53:
```bash
# Before:
  refute_output --partial "file(s) staged total."
# After:
  refute_output --partial "staged total now."
```

- [ ] **Step 2: Run the unit tests**

Run: `make unit`
Expected: all tests pass (exit 0). The `test_add.bats` tests specifically should all be green.

- [ ] **Step 3: Commit**

```bash
hug c -F - <<'EOF'
test(hug-a): update assertions for tightened summary wording (#278)

Match the new output format from the previous commit. Tests assert
on count + "staged total now" rather than exact phrasing, so they
won't break if the wording evolves further.

Refs: elifarley/hug-scm#278
EOF
```

---

### Task 3: Update CHANGELOG entries

**Files:**
- Modify: `CHANGELOG.md:134,145`

- [ ] **Step 1: Update the two CHANGELOG references**

In `CHANGELOG.md`, update lines 134 and 145 to reflect the new output format.

Line 134 — replace `Staged N file(s). Index now has M file(s) staged total.` with `Staged N file(s). M staged total now.`

Line 145 — replace `Staged N file(s). Index now has M file(s) staged total.` with `Staged N file(s). M staged total now.`

- [ ] **Step 2: Commit**

```bash
hug c -F - <<'EOF'
docs(changelog): update hug a output format references (#278)

The two CHANGELOG entries describing the hug a post-stage summary
still referenced the old verbose format. Update to match the new
wording from the previous commits.

Refs: elifarley/hug-scm#278
EOF
```
