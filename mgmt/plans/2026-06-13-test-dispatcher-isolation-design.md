# Design: Fix `test_dispatcher.bats` working-directory isolation

- **Date:** 2026-06-13
- **Status:** Approved (design); implementation pending
- **Fixes:** [elifarley/hug-scm#180](https://github.com/elifarley/hug-scm/issues/180) — and, incidentally, [elifarley/hug-scm#167](https://github.com/elifarley/hug-scm/issues/167)
- **Related, out of scope (separately tracked):** [elifarley/hug-scm#168](https://github.com/elifarley/hug-scm/issues/168), [elifarley/hug-scm#181](https://github.com/elifarley/hug-scm/issues/181), [elifarley/hug-scm#182](https://github.com/elifarley/hug-scm/issues/182), [elifarley/hug-scm#183](https://github.com/elifarley/hug-scm/issues/183)

## Problem

`tests/unit/test_dispatcher.bats` has **no `setup()`** and never assigns `TEST_REPO`. Several tests
follow this pattern:

```bash
create_test_repo        # echoes the temp-repo path to stdout — DISCARDED here
cd "$TEST_REPO"         # TEST_REPO unset → `cd ""` → a silent no-op (stays in the ambient CWD)
echo "x" > newfile.txt && git add newfile.txt
run hug s -C
```

`cd ""` is a no-op, so the shell stays in the **ambient working directory** (the developer's worktree
root when the suite is run from a worktree). The two tests that *write files* (lines 375 and 390) leak
`newfile.txt` / `staged.txt` into that directory and stage them — the symptom reported in
[elifarley/hug-scm#180](https://github.com/elifarley/hug-scm/issues/180) and
[elifarley/hug-scm#168](https://github.com/elifarley/hug-scm/issues/168). The other ~5 tests with the
same pattern don't write files, so they silently run against the ambient repo and pass *vacuously*,
which masked the defect.

Confirmed by audit:

- `create_test_repo` / `create_test_repo_with_history` / `create_test_repo_with_changes` /
  `create_test_hg_repo` **echo** a path — callers MUST capture it (`X=$(...)`).
  `create_test_repo_with_submodule` **sets globals** and is correctly called bare.
- `test_dispatcher.bats` is the *only* suite file that references `$TEST_REPO` with no `setup()` and
  no assignment, so the **leak** is unique to it. (The milder redundant-bare-call variant exists in
  `test_commit.bats` / `test_head.bats` and is tracked separately in
  [elifarley/hug-scm#181](https://github.com/elifarley/hug-scm/issues/181).)

## Decision — add `setup()` / `teardown()` (matches the suite norm)

Adopt the same `setup()` / `teardown()` every sibling command/status test file already uses.
`test_status_json.bats` is the exact template (status-focused, no gum):

```bash
setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}
```

Every test now starts inside a fresh, isolated repo (created under `$BATS_TEST_TMPDIR`, auto-removed),
and `cleanup_test_repo` adds the teardown this file currently lacks.

**Why this over the alternatives:** it adheres to the established project norm, is DRY, and makes the
`cd ""`-no-op class *structurally impossible* in this file — a future test that forgets to capture a
repo path still starts inside an isolated repo rather than the ambient worktree.

### Edits

Remove the now-redundant / dead lines:

| Tests (current line) | Change | Rationale |
|---|---|---|
| 276, 333, 375, 390, 404, 417, 426 | delete `create_test_repo` + `cd "$TEST_REPO"` | `setup()` supplies a fresh repo + `cd`; **fixes the leak** — 375/390 now write inside the isolated repo |
| 31, 42, 52 | delete the bare `create_test_repo` (dead) + the redundant `cd "$TEST_REPO"` | keep `other_repo=$(create_test_repo)` + `run hug -C "$other_repo" …`; the test now genuinely runs *from a repo, targeting another* |
| 105 | delete the dead bare `create_test_repo` | the test builds its own spaced dir and `cd /tmp` |

**Leave untouched:** every `cd /tmp` test, every `-S` submodule test (`cd "$TEST_PARENT_REPO"`), and
the help / version / clone / init dispatch tests. They manage their own CWD or are CWD-independent;
they receive a fresh `TEST_REPO` they ignore (cheap; cleaned by `teardown`).

Net diff: ≈ +9 added (`setup`/`teardown`) / −21 removed (redundant + dead lines) across 11 tests.

## Incidental fix: [elifarley/hug-scm#167](https://github.com/elifarley/hug-scm/issues/167)

The `regression: hug init dispatch still works (no args = error)` test asserts `hug init` *fails*.
`hug-init`'s "already a repo" guard (`bin/hug-init:137`) checks `-d ".git"` — a **directory**:

- **Main checkout:** `.git` is a directory → guard fires → `hug init` errors → `assert_failure` holds → test passes.
- **Linked worktree:** `.git` is a **file** (gitdir pointer) → guard skipped → re-init succeeds → `assert_failure` fails. ← the bug in [elifarley/hug-scm#167](https://github.com/elifarley/hug-scm/issues/167).

`create_test_repo` runs `git init`, which produces a `.git` **directory**. With `setup()` in place,
this test always runs against a `.git`-dir repo, so the guard always fires and `assert_failure` always
holds — **deterministically, from main and from a worktree.** This resolves
[elifarley/hug-scm#167](https://github.com/elifarley/hug-scm/issues/167) as a side effect, so the
change can close both #180 and #167 (pending the worktree verification below).

## Scope boundaries (NOT in this change)

- [elifarley/hug-scm#181](https://github.com/elifarley/hug-scm/issues/181) — suite-wide cleanup of the
  redundant bare echo-helper calls in `test_commit.bats` / `test_head.bats`.
- [elifarley/hug-scm#182](https://github.com/elifarley/hug-scm/issues/182) — shared-helper guardrail
  (fail loudly on empty `cd` / refuse `git add` at the repo root).
- [elifarley/hug-scm#183](https://github.com/elifarley/hug-scm/issues/183) — CI gate that runs the
  suite from a linked worktree and asserts a clean tree.

Those are the systemic prevention and remain independently tracked; this change fixes the concrete
instance in `test_dispatcher.bats`.

## Success criteria (reproduce → fix → verify)

1. **Reproduce first** (from a linked worktree, before the fix):
   `make test-unit TEST_FILE=test_dispatcher.bats` leaves `newfile.txt` / `staged.txt` in the worktree
   root, *and* the `hug init` test fails. Confirms #180 + #167 are real and environment-dependent.
2. **After the fix:**
   - all `test_dispatcher.bats` tests pass on the main checkout (42 today; the count is unchanged — this refactor adds/removes no `@test` blocks);
   - from a linked worktree: the same tests pass (including `hug init`), and
     `test ! -e newfile.txt && test ! -e staged.txt` holds (the #180 acceptance check);
   - full `make test-unit` is green;
   - `make sanitize-check` is clean (format / shellcheck).

## Risks & mitigations

- **`setup()` changes the starting CWD for the help/version/clone/init tests** (previously the ambient
  CWD). *Mitigation:* those are CWD-independent except `hug init`, whose new CWD (a `.git`-dir repo)
  makes its assertion deterministically hold (see the #167 section). Verified by running the whole
  file from both a normal checkout and a linked worktree.
- **Redundant repo creation for the `cd`-elsewhere tests.** *Mitigation:* negligible cost (one
  `git init` under `$BATS_TEST_TMPDIR`), it matches the suite norm, and `teardown` cleans it.

## Alternatives considered

- **Capture-only (no `setup()`):** add `TEST_REPO=$(create_test_repo)` to each broken test and keep the
  per-test `cd`. Smaller blast radius, but it keeps boilerplate, doesn't adopt the file-wide norm, and
  would **not** stabilize the `hug init` test ([elifarley/hug-scm#167](https://github.com/elifarley/hug-scm/issues/167))
  because those tests keep the ambient CWD. Rejected: less DRY, and it misses the #167 win.
- **Minimal (two tests only):** fix just lines 375/390. Rejected: leaves ~5 vacuously-passing tests
  and the dead calls in place, so the defect stays latent.
