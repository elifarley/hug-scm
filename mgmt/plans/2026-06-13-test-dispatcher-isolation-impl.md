# test_dispatcher.bats Working-Directory Isolation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `tests/unit/test_dispatcher.bats` a per-test `setup()`/`teardown()` so every test runs in a fresh isolated repo — eliminating the `newfile.txt`/`staged.txt` worktree leak ([elifarley/hug-scm#180](https://github.com/elifarley/hug-scm/issues/180)) and making the CWD-sensitive `hug init` test deterministic ([elifarley/hug-scm#167](https://github.com/elifarley/hug-scm/issues/167)).

**Architecture:** Adopt the established suite norm (`test_status_json.bats`): a `setup()` that does `TEST_REPO=$(create_test_repo); cd "$TEST_REPO"` and a `teardown()` that calls `cleanup_test_repo`. Then strip the now-redundant `create_test_repo` / `cd "$TEST_REPO"` lines (and dead bare calls) from individual tests. Tests that deliberately use a different CWD (`/tmp`, the submodule parent) keep their own `cd` and are unaffected.

**Tech Stack:** Bash, BATS, the shared `tests/test_helper.bash` (`create_test_repo`, `cleanup_test_repo`, `require_hug`).

**Design spec:** `mgmt/plans/2026-06-13-test-dispatcher-isolation-design.md`

**Worktree:** `~/IdeaProjects/hug-scm.WT.fix-test-dispatcher-isolation` (branch `fix-test-dispatcher-isolation`, off `origin/main`). All commands below run from this worktree root.

---

### Task 1: Isolate per-test CWD in `test_dispatcher.bats`

**Goal:** Every test starts inside a fresh isolated repo; the file no longer relies on the ambient CWD; the worktree leak is gone and the `hug init` test is deterministic.

**Files:**
- Modify: `tests/unit/test_dispatcher.bats` (add `setup()`/`teardown()` after the `load '../test_helper'` line; remove redundant/dead `create_test_repo` + `cd "$TEST_REPO"` lines from the tests listed in Step 4)

**Acceptance Criteria:**
- [ ] `setup()` and `teardown()` exist, matching the `test_status_json.bats` pattern.
- [ ] No `create_test_repo` (bare/uncaptured) or `cd "$TEST_REPO"` line remains in the file — verified by grep (Step 6).
- [ ] From the linked worktree, `make test-unit TEST_FILE=test_dispatcher.bats` passes every test **and** leaves no `newfile.txt`/`staged.txt` in the worktree root.
- [ ] The `regression: hug init dispatch still works (no args = error)` test passes from the worktree (not just the main checkout).
- [ ] Full `make test-unit` is green; `make sanitize-check` is clean.

**Verify:**
`cd ~/IdeaProjects/hug-scm.WT.fix-test-dispatcher-isolation && make test-unit TEST_FILE=test_dispatcher.bats && test ! -e newfile.txt && test ! -e staged.txt && echo CLEAN`
→ all tests pass, prints `CLEAN`.

**Steps:**

- [ ] **Step 1: Reproduce the leak (red).** From the worktree root, run the *current* (unfixed) dispatcher tests and confirm the leak + the env-dependent init behavior:

```bash
cd ~/IdeaProjects/hug-scm.WT.fix-test-dispatcher-isolation
make test-unit TEST_FILE=test_dispatcher.bats TEST_SHOW_ALL_RESULTS=1
# Then inspect the worktree root for leaked scratch files:
hug slk        # expect: untrcK newfile.txt  /  untrcK staged.txt  (the leak)
ls -l newfile.txt staged.txt 2>&1
```
Expected: the suite passes (the leak is silent), but `newfile.txt`/`staged.txt` (content `x`) now exist in the worktree root — the bug. Note whether the `hug init` test passed or failed (it may fail here because the worktree's `.git` is a file — that is elifarley/hug-scm#167).

- [ ] **Step 2: Clean up the reproduced leak** so it cannot be committed:

```bash
rm -f ~/IdeaProjects/hug-scm.WT.fix-test-dispatcher-isolation/newfile.txt \
      ~/IdeaProjects/hug-scm.WT.fix-test-dispatcher-isolation/staged.txt
hug -C ~/IdeaProjects/hug-scm.WT.fix-test-dispatcher-isolation slk   # expect: clean (no newfile/staged)
```

- [ ] **Step 3: Add `setup()`/`teardown()`** immediately after the `load '../test_helper'` line (currently line 24) in `tests/unit/test_dispatcher.bats`. Insert exactly:

```bash
load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}
```

Rationale (comment not required — matches `test_status_json.bats` verbatim): every test now starts inside a fresh repo under `$BATS_TEST_TMPDIR`; `cleanup_test_repo` removes it afterward.

- [ ] **Step 4: Remove the now-redundant / dead lines.** In each `@test` below, delete the indicated lines. (Identify tests by name — line numbers shift as you edit.) Delete *only* these lines; leave every other line in each test intact.

  Delete BOTH `create_test_repo` and `cd "$TEST_REPO"` from these tests (the bare `create_test_repo` is dead, the `cd` is now done by `setup()`):
  - `hug -C <repo> s: runs status in target repo` — delete `create_test_repo` and `cd "$TEST_REPO"  # be in some repo` (keep `other_repo=$(create_test_repo)` and the `run`).
  - `hug -C <repo> s --branch: reports target repo branch` — delete `create_test_repo` and `cd "$TEST_REPO"` (keep `other_repo=...`).
  - `hug -C <repo> ll -1: log from target repo` — delete `create_test_repo` and `cd "$TEST_REPO"` (keep `other_repo=...`).

  Delete the single dead bare `create_test_repo` (this test uses `cd /tmp`, not `cd "$TEST_REPO"`):
  - `hug -C '<path with spaces>': works with spaces in path` — delete the leading `create_test_repo` only.

  Delete BOTH `create_test_repo` and `cd "$TEST_REPO"` from these (they relied on the no-op `cd`; `setup()` now provides the repo):
  - `hug -S: error when repo has no submodules (.gitmodules missing)`
  - `regression: hug s works without global flags`
  - `regression: hug s -C still means --counts (not global -C)` — keep `echo "x" > newfile.txt && git add newfile.txt` and the `run` (they now write inside the isolated repo — **this is the leak fix**).
  - `regression: hug s -S still means --staged (not global -S)` — keep `echo "x" > staged.txt && git add staged.txt`.
  - `regression: unknown global flag passes through to git`
  - `regression: -- ends global flags, rest passes to command`
  - `regression: hug with no args in git repo shows hughelp`

  **Leave entirely untouched:** all `-S <submodule>` tests (they `cd "$TEST_PARENT_REPO"`), the `cd /tmp` tests (`works from non-git directory`, the hg test, the composition tests), and the help/version/clone/init dispatch tests. They manage their own CWD or are CWD-independent; `setup()`'s fresh `TEST_REPO` is harmless for them.

- [ ] **Step 5: Run the dispatcher tests from the worktree (green) and confirm no leak:**

```bash
cd ~/IdeaProjects/hug-scm.WT.fix-test-dispatcher-isolation
make test-unit TEST_FILE=test_dispatcher.bats TEST_SHOW_ALL_RESULTS=1
test ! -e newfile.txt && test ! -e staged.txt && echo "LEAK-FREE" || echo "STILL LEAKING"
```
Expected: every test passes (including `hug init dispatch`), and it prints `LEAK-FREE`.

- [ ] **Step 6: Static check + full unit suite:**

```bash
cd ~/IdeaProjects/hug-scm.WT.fix-test-dispatcher-isolation
# No bare create_test_repo / cd "$TEST_REPO" should remain:
grep -nE '^[[:space:]]*create_test_repo[[:space:]]*$|cd "\$TEST_REPO"' tests/unit/test_dispatcher.bats || echo "NONE (good)"
make test-unit
make sanitize-check
```
Expected: grep prints `NONE (good)`; `make test-unit` green; `make sanitize-check` clean. (If `sanitize-check` reports a fixable issue, run `make sanitize` and re-check.)

- [ ] **Step 7: Commit** (load the `commit-message` skill for the message; use `hug -C <worktree>`):

```bash
hug -C ~/IdeaProjects/hug-scm.WT.fix-test-dispatcher-isolation a tests/unit/test_dispatcher.bats
hug -C ~/IdeaProjects/hug-scm.WT.fix-test-dispatcher-isolation ss   # review the staged diff
# then commit with a WHY/WHAT/HOW/IMPACT message ending with:
#   Closes elifarley/hug-scm#180
#   Closes elifarley/hug-scm#167
#   Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```

**Verification note (covers both issues):** Steps 5 confirms #180 (no leak) and #167 (the `hug init` test passes from a worktree, where it previously failed). Run Step 5 from the *worktree* specifically — running only from the main checkout would not exercise the #167 / #180 conditions.

---

## Out of scope (separately tracked — do NOT touch in this plan)

- [elifarley/hug-scm#181](https://github.com/elifarley/hug-scm/issues/181) — suite-wide cleanup of redundant bare echo-helper calls (`test_commit.bats`, `test_head.bats`).
- [elifarley/hug-scm#182](https://github.com/elifarley/hug-scm/issues/182) — shared-helper guardrail.
- [elifarley/hug-scm#183](https://github.com/elifarley/hug-scm/issues/183) — CI worktree-safety gate.
