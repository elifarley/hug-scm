# count_commits_in_range Audit — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix elifarley/hug-scm#229's two correctness defects — the `count == 0 ⟹ aligned` conflation (Defect 1) and the `|| echo 0` error-swallow (Defect 2) — across `count_commits_in_range` and its 9 call sites, with the alignment idiom replaced by a sanctioned `is_aligned` primitive and strict error propagation everywhere.

**Architecture:** Add two primitives to `git-config/lib/hug-git-commit` — `commits_ahead_behind` (three-dot symmetric-diff relationship) and `is_aligned` (the only sanctioned alignment test). Make `count_commits_in_range` strict (drop the `|| echo 0` swallow); the two display-only sites use a named `count_commits_in_range_or_zero` wrapper. Migrate the two genuine alignment sites (`handle_standard_operation`, `git-h-restore`) to `is_aligned`; keep `git-cmv`'s correct `== 0` guard (fix only its message). Every helper contract stays untouched (helpers called bare; `exit 0` guards intact). **Phase 2 (direction-truthful messaging) is explicitly out of scope.**

**Tech Stack:** Bash (`set -euo pipefail`), BATS test framework (`make test-lib` / `make test-unit`), hug SCM command layer.

**Spec:** `docs/superpowers/specs/2026-07-29-count-commits-in-range-audit-design.md` (commit `6e25999`).

**Key environment facts (verified):**
- All command scripts run `set -euo pipefail`. Libraries (`hug-git-*`) do not set it themselves; they are sourced into scripts (via the `hug-git-kit` meta-loader at `git-config/lib/hug-git-kit:30`), so library functions execute under the caller's `set -e`.
- `handle_upstream_operation` is invoked as `target=$(handle_upstream_operation …) || exit $?` in every mover — the trailing `|| exit $?` **suppresses `set -e` inside the function body**, so its `count_commits_in_range` call MUST carry an explicit `|| return 1`.
- Top-level (script-body) callers are covered by `set -e` automatically; explicit `|| exit 1` is added for clarity/robustness.
- `merge-base --is-ancestor X X` returns 0 (a commit is its own ancestor) — so `count == 0` fires both when aligned AND when the target is a descendant. This is the heart of Defect 1.

---

## File Structure

**Modify:**
- `git-config/lib/hug-git-commit` — add `commits_ahead_behind`, `is_aligned`, `count_commits_in_range_or_zero`; strictify `count_commits_in_range` (line ~215).
- `git-config/lib/hug-git-upstream` — `handle_standard_operation` (line ~101): `is_aligned` guard + strict count; `handle_upstream_operation` (line ~49): `|| return 1`.
- `git-config/lib/hug-git-rebase` — line ~238: use `count_commits_in_range_or_zero`.
- `git-config/bin/git-cmv` — line ~160: strict + branched message.
- `git-config/bin/git-h-squash` — lines ~167, ~176: strict (`|| exit 1`); keep the `:177` `== 0` branch.
- `git-config/bin/git-h-files` — line ~122: strict; line ~202: wrapper.
- `git-config/bin/git-log-outgoing` — line ~92: strict.
- `git-config/bin/git-h-restore` — line ~107: `is_aligned`; comments at :16-20, :27-28, :104-106 rewritten.
- `git-config/bin/git-h-back` — comments at :105-108 reworded (root-path).
- `git-config/bin/git-h-undo` — comments at :123-126 reworded (root-path).
- `git-config/lib/README.md` — Range counting subsection; fix `:98` predicate drift; cross-reference `is_aligned`; refresh helper examples `:425-435`.

**Test:**
- `tests/lib/test_hug-git-commit.bats` — primitives + strictification + wrapper.
- `tests/lib/test_hug-upstream.bats` — `handle_standard_operation` Defect-1 regression + aligned-guard.
- `tests/unit/test_commit.bats` — cmv branched message + no-regression.
- `tests/unit/test_h_restore.bats` — h-restore `is_aligned` no-op + invalid-SHA.
- `tests/unit/test_head.bats` — forward-mover smoke + squash live-branch + per-site strict propagation.

---

## Task 1: Add `commits_ahead_behind` + `is_aligned` primitives

**Goal:** Add the two-directional relationship primitive and the sanctioned alignment predicate to `hug-git-commit`, with unit tests. Purely additive — no behavior change yet.

**Files:**
- Modify: `git-config/lib/hug-git-commit:215-220` (insert the two functions after `count_commits_in_range`, before `print_commit_list_in_range` at line 222)
- Test: `tests/lib/test_hug-git-commit.bats`

**Acceptance Criteria:**
- [ ] `commits_ahead_behind <start> <end>` prints `"<behind>\t<ahead>"` (git's native `--left-right` order: first arg's exclusive count first).
- [ ] `commits_ahead_behind` returns non-zero with empty stdout on an invalid ref (strict — no swallow).
- [ ] `is_aligned <a> <b>` returns 0 iff `a` and `b` resolve to the same commit; non-zero otherwise.
- [ ] `is_aligned HEAD HEAD` on an unborn repo (no commits) returns non-zero (documented false-negative; never a false-positive).
- [ ] All new tests pass; existing `count_commits_in_range` tests still pass.

**Verify:** `make test-lib TEST_FILE=test_hug-git-commit.bats TEST_SHOW_ALL_RESULTS=1` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing tests** — append to `tests/lib/test_hug-git-commit.bats` (after the existing `count_commits_in_range` tests, ~line 52):

```bash
################################################################################
# commits_ahead_behind TESTS
################################################################################

@test "commits_ahead_behind: ancestor pair -> 0<TAB>N (end ahead of start)" {
  run commits_ahead_behind HEAD~2 HEAD
  assert_success
  assert_output "$(printf '0\t2')"
}

@test "commits_ahead_behind: descendant pair -> N<TAB>0 (end behind start)" {
  run commits_ahead_behind HEAD HEAD~2
  assert_success
  assert_output "$(printf '2\t0')"
}

@test "commits_ahead_behind: aligned -> 0<TAB>0" {
  run commits_ahead_behind HEAD HEAD
  assert_success
  assert_output "$(printf '0\t0')"
}

@test "commits_ahead_behind: diverged pair -> both counts > 0" {
  # Build a divergent history: branch off HEAD~1, commit on both sides.
  git checkout -q -b side HEAD~1
  echo x > side.txt; git add side.txt; git commit -qm "side commit"
  git checkout -q main 2>/dev/null || git checkout -q - 2>/dev/null || git checkout -q @{-1}
  # 'main' (or prior) now diverges from 'side'
  run commits_ahead_behind side HEAD
  assert_success
  # both fields must be > 0 (neither is an ancestor of the other)
  local f1="${output%%$'\t'*}" f2="${output##*$'\t'}"
  [ "$f1" -gt 0 ] && [ "$f2" -gt 0 ]
}

@test "commits_ahead_behind: invalid ref -> non-zero, empty stdout (strict)" {
  run commits_ahead_behind NO_SUCH_REF HEAD
  assert_failure
  assert_output ""
}

################################################################################
# is_aligned TESTS
################################################################################

@test "is_aligned: same SHA -> exit 0" {
  run is_aligned HEAD HEAD
  assert_success
}

@test "is_aligned: ancestor (not equal) -> non-zero" {
  run is_aligned HEAD~1 HEAD
  assert_failure
}

@test "is_aligned: descendant (not equal) -> non-zero" {
  # A descendant target must NOT read as aligned (this is the Defect-1 conflation).
  local descendant; descendant=$(git rev-parse HEAD)
  git reset -q --hard HEAD~1
  run is_aligned "$descendant" HEAD
  assert_failure
}

@test "is_aligned: invalid ref -> non-zero (never a false positive)" {
  run is_aligned NO_SUCH_REF HEAD
  assert_failure
}

@test "is_aligned: unborn repo (no commits) -> non-zero (false NEGATIVE, documented)" {
  local empty_repo; empty_repo=$(create_test_repo)   # fresh repo, no commits
  cd "$empty_repo"
  run is_aligned HEAD HEAD
  assert_failure
  cd "$TEST_REPO"
}
```

> Note: the `is_aligned: unborn repo` test relies on `create_test_repo` returning a repo path with NO commits (unborn HEAD). Confirm `create_test_repo` does not auto-commit; if it does, replace with `git init -q "$(mktemp -d)"` and `cd` there. The diverged test's checkout fallbacks guard against the default-branch name (`main` vs `master`).

- [ ] **Step 2: Run the tests to verify they fail** — `make test-lib TEST_FILE=test_hug-git-commit.bats TEST_SHOW_ALL_RESULTS=1`. Expected: the new `commits_ahead_behind` / `is_aligned` tests FAIL with "command not found" (functions not yet defined); existing tests pass.

- [ ] **Step 3: Implement the primitives** — in `git-config/lib/hug-git-commit`, insert after `count_commits_in_range` (after line 220, before the `print_commit_list_in_range` comment block at line 222):

```bash
# Returns the ahead/behind relationship between two commits as "<behind>\t<ahead>"
# via the three-dot symmetric difference: git rev-list --left-right --count <start>...<end>
#   <behind> = commits reachable from <start> but NOT <end>  (end is BEHIND start by this many)
#   <ahead>  = commits reachable from <end>  but NOT <start> (end is AHEAD of start by this many)
# Alignment (<start> == <end>) ⟺ "0\t0".
#
# NOTE: output order is git's native --left-right order (first arg's exclusive count
# FIRST) — i.e. "<behind>\t<ahead>", which does NOT match this function's NAME word order
# ("ahead_behind"). Consumers MUST parse into POSITIONAL field1/field2; NEVER
# `read ahead behind <<< "…"` — that silently swaps them. When BOTH counts are > 0 the
# refs have DIVERGED (neither is an ancestor) — a sideways relationship. (Shallow clones:
# the EQUALITY test via is_aligned is shallow-safe; raw ahead/behind COUNTS are not.)
#
# STRICT: a failed rev-list (invalid ref, unborn HEAD) propagates non-zero exit and prints
# nothing — it is NEVER swallowed into a zero. Callers MUST handle failure.
commits_ahead_behind() {
  local start="${1:?commits_ahead_behind: start ref required}"
  local end="${2:?commits_ahead_behind: end ref required}"
  git rev-list --left-right --count "$start...$end"
}

# True (exit 0) iff <a> and <b> resolve to the SAME existing commit.
#
# This is the ONLY sanctioned alignment test. NEVER infer alignment from a one-directional
# count_commits_in_range == 0 — that means "not ahead," which is ALSO true when one ref is
# BEHIND the other (Defect 1 of elifarley/hug-scm#229). For the full ahead/behind
# relationship use commits_ahead_behind().
#
# PRECONDITION: both <a> and <b> MUST resolve to existing commits. On an unborn repo (no
# commits) rev-list exits 128 even for HEAD...HEAD, so is_aligned returns NON-ZERO for the
# trivially-aligned case — a false NEGATIVE, never a false positive. Movers run repo/commit-
# existence guards first; and even if not, the loud-failure chain holds (commits_ahead_behind
# ALSO exits non-zero on unborn → callers propagate).
#
# $'0\t0' uses ANSI-C quoting so \t is a real TAB (git's field separator), NOT backslash-t.
is_aligned() {
  local a="${1:?is_aligned: first ref required}"
  local b="${2:?is_aligned: second ref required}"
  [ "$(commits_ahead_behind "$a" "$b" 2>/dev/null)" = $'0\t0' ]
}
```

- [ ] **Step 4: Run the tests to verify they pass** — `make test-lib TEST_FILE=test_hug-git-commit.bats TEST_SHOW_ALL_RESULTS=1`. Expected: all tests pass (new + existing).

- [ ] **Step 5: Commit**

```bash
hug a git-config/lib/hug-git-commit tests/lib/test_hug-git-commit.bats
hug c -m "feat(lib): add commits_ahead_behind + is_aligned alignment primitives

Add the two-directional relationship primitive (commits_ahead_behind, three-dot
symmetric diff) and the sanctioned alignment predicate (is_aligned) to hug-git-commit.
is_aligned is the ONLY correct way to test 'HEAD == target' — a one-directional
count_commits_in_range == 0 conflates 'aligned' with 'behind' (Defect 1 of #229).
Both propagate rev-list failures strictly (no swallow). Purely additive.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Strictify `count_commits_in_range` + add wrapper + migrate display sites

**Goal:** Remove the `|| echo 0` swallow from `count_commits_in_range` (Defect 2), add the `count_commits_in_range_or_zero` named wrapper for the two display-only sites, migrate those two sites + add the required `|| return 1` to `handle_upstream_operation`, with tests.

**Files:**
- Modify: `git-config/lib/hug-git-commit:208-220` (strictify + loud docstring; add wrapper)
- Modify: `git-config/lib/hug-git-rebase:237-238` (display → wrapper)
- Modify: `git-config/bin/git-h-files:202` (display → wrapper)
- Modify: `git-config/lib/hug-git-upstream:48-49` (`|| return 1` — required, `set -e` suppressed)
- Test: `tests/lib/test_hug-git-commit.bats`

**Acceptance Criteria:**
- [ ] `count_commits_in_range` no longer contains `|| echo 0`; an invalid start returns non-zero with empty stdout.
- [ ] `count_commits_in_range` uses `${1:?…}` so a missing `$1` fails fast.
- [ ] `count_commits_in_range_or_zero INVALID HEAD` echoes `0` and exits 0 (the named cosmetic twin).
- [ ] `grep -rn '|| echo 0' git-config/` returns exactly one line — the wrapper body.
- [ ] `handle_upstream_operation:49` carries `|| return 1` (its `set -e` is suppressed by the `|| exit $?` call form).
- [ ] `hug-git-rebase:238` and `git-h-files:202` use the wrapper.
- [ ] Existing happy-path count tests still pass.

**Verify:** `make test-lib TEST_FILE=test_hug-git-commit.bats TEST_SHOW_ALL_RESULTS=1` → all pass; `grep -rn '|| echo 0' git-config/ | wc -l` → `1`.

**Steps:**

- [ ] **Step 1: Write the failing tests** — append to `tests/lib/test_hug-git-commit.bats`:

```bash
################################################################################
# count_commits_in_range STRICTNESS TESTS (Defect 2)
################################################################################

@test "count_commits_in_range: invalid start -> non-zero, empty stdout (strict, no swallow)" {
  run count_commits_in_range NO_SUCH_REF HEAD
  assert_failure
  assert_output ""
}

@test "count_commits_in_range: missing start arg -> fails fast via \${1:?}" {
  run count_commits_in_range
  assert_failure
}

################################################################################
# count_commits_in_range_or_zero TESTS (named display wrapper)
################################################################################

@test "count_commits_in_range_or_zero: valid range -> same as strict count" {
  run count_commits_in_range_or_zero HEAD~2 HEAD
  assert_success
  assert_output "2"
}

@test "count_commits_in_range_or_zero: invalid start -> echoes 0, exit 0 (cosmetic)" {
  run count_commits_in_range_or_zero NO_SUCH_REF HEAD
  assert_success
  assert_output "0"
}
```

- [ ] **Step 2: Run the tests to verify they fail** — `make test-lib TEST_FILE=test_hug-git-commit.bats TEST_SHOW_ALL_RESULTS=1`. Expected: "invalid start -> non-zero" FAILS (current `|| echo 0` makes it succeed with "0"); "count_commits_in_range_or_zero" tests FAIL (function not defined).

- [ ] **Step 3: Strictify the helper + add the wrapper** — in `git-config/lib/hug-git-commit`, replace lines 208-220 (the `count_commits_in_range` comment + body):

```bash
# Counts how far <end> is AHEAD of <start> (commits reachable from <end> but not <start>).
# Usage: count=$(count_commits_in_range "start" ["end"])
# Parameters:
#   $1 - Start commit (exclusive) — REQUIRED
#   $2 - (Optional) End commit (inclusive), defaults to HEAD
# Output:
#   Number of commits in range to stdout.
#
# ONE-DIRECTIONAL ahead-count: a result of 0 means "<end> is NOT ahead of <start>" — which
# is TRUE in two distinct cases: (1) end == start (aligned), OR (2) end is BEHIND start.
# Do NOT treat 0 as "aligned." For an alignment test use is_aligned(); for the full
# ahead/behind relationship use commits_ahead_behind(). See lib/README.md "Range counting".
#
# STRICT: a failed rev-list (invalid ref, unborn HEAD) propagates non-zero exit and prints
# nothing — it is NEVER swallowed into a 0. Callers MUST handle failure (this is the fix for
# Defect 2 of elifarley/hug-scm#229; the old `|| echo 0` let errors masquerade as data).
count_commits_in_range() {
    local start="${1:?count_commits_in_range: start ref required}"
    local end="${2:-HEAD}"

    git rev-list --count "$start..$end"
}

# STRICT-display twin of count_commits_in_range.
# ONLY for display/tip text where a 0 on rev-list failure is cosmetically acceptable
# (e.g. a rendered plan or a "… in N commits since …" tip). NEVER use this for a branching
# or alignment decision — there, count_commits_in_range's strict propagation MUST surface
# the failure. Grep invariant: `|| echo 0` appears NOWHERE outside this single definition.
count_commits_in_range_or_zero() {
    count_commits_in_range "$@" || echo 0
}
```

- [ ] **Step 4: Migrate display site #1** — in `git-config/lib/hug-git-rebase`, replace line ~238:

```bash
  local num_commits
  num_commits=$(count_commits_in_range_or_zero "$target_branch" HEAD)
```

(was `num_commits=$(count_commits_in_range "$target_branch" HEAD)` — display-only count in the rendered rebase plan; a cosmetic 0 on failure is acceptable here).

- [ ] **Step 5: Migrate display site #2** — in `git-config/bin/git-h-files`, replace line ~202:

```bash
  num_commits=$(count_commits_in_range_or_zero "$start_point" HEAD)
```

(was `num_commits=$(count_commits_in_range "$start_point" HEAD)` — feeds the tip text "… changed in N commits since …"; cosmetic 0 acceptable).

- [ ] **Step 6: Add required `|| return 1` to `handle_upstream_operation`** — in `git-config/lib/hug-git-upstream`, replace line ~49:

```bash
    local local_commits
    local_commits=$(count_commits_in_range "$target" HEAD) || return 1
```

> This `|| return 1` is REQUIRED, not optional: `handle_upstream_operation` is invoked as `target=$(handle_upstream_operation …) || exit $?`, and the trailing `|| exit $?` suppresses `set -e` inside the function body, so without the explicit guard a failing count would leave `local_commits` empty and the following `[ "$local_commits" -eq 0 ]` would error. (Declare-then-assign is already correct here — do NOT merge into `local local_commits=$(…)`.)

- [ ] **Step 7: Run the tests to verify they pass** — `make test-lib TEST_FILE=test_hug-git-commit.bats TEST_SHOW_ALL_RESULTS=1`. Expected: all pass.

- [ ] **Step 8: Verify the grep invariant + that callers still work**

```bash
grep -rn '|| echo 0' git-config/        # expect exactly 1 line: count_commits_in_range_or_zero body
make test-lib TEST_SHOW_ALL_RESULTS=1   # all lib tests still green
```

- [ ] **Step 9: Commit**

```bash
hug a git-config/lib/hug-git-commit git-config/lib/hug-git-rebase git-config/bin/git-h-files git-config/lib/hug-git-upstream tests/lib/test_hug-git-commit.bats
hug c -m "fix(lib): strictify count_commits_in_range — remove the || echo 0 swallow

count_commits_in_range previously did \`git rev-list --count … || echo 0\`, letting a
failed rev-list (invalid ref, unborn HEAD) masquerade as 'genuinely 0 commits' (Defect 2
of #229). It now propagates the failure (non-zero exit, empty stdout) and fails fast on a
missing start arg via \${1:?}.

The two display-only sites (hug-git-rebase:238 plan count, git-h-files:202 tip count)
move to a new named count_commits_in_range_or_zero wrapper — the single sanctioned
cosmetic-0 escape hatch (grep '|| echo 0' now returns exactly that one definition). The
function NAME is the guardrail, not a comment.

handle_upstream_operation:49 gains an explicit '|| return 1': it is called as
\`target=$(handle_upstream_operation …) || exit $?\`, which suppresses set -e inside the
function, so the guard is required there (not optional).

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Site 1 — `handle_standard_operation` uses `is_aligned` (Defect 1 core)

**Goal:** Replace the `count == 0` alignment guard in `handle_standard_operation` with `is_aligned`, and make its preview count strict — so a forward (descendant) target proceeds instead of silently no-op'ing.

**Files:**
- Modify: `git-config/lib/hug-git-upstream:101-141` (`handle_standard_operation`)
- Test: `tests/lib/test_hug-upstream.bats`

**Acceptance Criteria:**
- [ ] A forward (descendant) target no longer prints "Already at target"; the guard is not taken (helper returns past it).
- [ ] An aligned target (`target == HEAD`) still prints "Already at target. No action taken." and `exit 0`.
- [ ] The helper is still called **bare** by the movers (its `exit 0` terminates the whole mover) — verified by the aligned-guard test below.
- [ ] The preview count is strict (`|| return 1`).
- [ ] Existing aligned-target tests in `test_hug-upstream.bats` still pass.

**Verify:** `make test-lib TEST_FILE=test_hug-upstream.bats TEST_SHOW_ALL_RESULTS=1` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing tests** — append to `tests/lib/test_hug-upstream.bats`:

```bash
################################################################################
# handle_standard_operation: Defect-1 regression (forward target must NOT no-op)
################################################################################

@test "handle_standard_operation: forward (descendant) target does NOT no-op (Defect 1)" {
  # HEAD at an ancestor; target is a descendant. Pre-fix this printed 'Already at target'.
  local descendant; descendant=$(git rev-parse HEAD)
  git reset -q --hard HEAD~1                       # HEAD now behind 'descendant', clean tree
  run handle_standard_operation "move back" "$descendant"
  assert_success                                   # returns past the guard (does not exit 0 early)
  refute_output --partial "Already at target"      # the guard was NOT taken
}

@test "handle_standard_operation: aligned target still no-ops with exit 0 (guard intact)" {
  local target; target=$(git rev-parse HEAD)
  run handle_standard_operation "move back" "$target"
  assert_output --partial "Already at target"
}

@test "handle_standard_operation: aligned + dirty + skip=false -> tracked-reset message" {
  echo "edit" >> file1.txt                          # tracked, unstaged (dirty)
  local target; target=$(git rev-parse HEAD)
  run handle_standard_operation "moving" "$target" false
  assert_output --partial "local tracked changes will be reset"
}
```

> The existing tests `handle_standard_operation: aligned + untracked-only -> 'Already at target'` and `… aligned + tracked-dirty + skip=false -> tracked-reset message` already exist in this file — keep them; they now exercise `is_aligned`. If the new "aligned + dirty + skip=false" test duplicates an existing one, drop the duplicate.

- [ ] **Step 2: Run the tests to verify the regression test fails** — `make test-lib TEST_FILE=test_hug-upstream.bats TEST_SHOW_ALL_RESULTS=1`. Expected: the "forward (descendant) target does NOT no-op" test FAILS (current `count == 0` guard prints "Already at target" for a forward target).

- [ ] **Step 3: Rewrite `handle_standard_operation`** — in `git-config/lib/hug-git-upstream`, replace the function body (lines ~101-141). Keep the existing preview block; only the guard and the count strictness change:

```bash
handle_standard_operation() {
    local action_name="$1"
    local target="$2"
    local skip_when_aligned="${3:-true}"

    # Defect-1 fix (#229): alignment is an EXACT SHA relationship, never a one-directional
    # count == 0 (which is also true when HEAD is BEHIND the target). A forward (descendant)
    # target used to no-op here; now only a truly-aligned target does. Called BARE by the
    # movers, so this exit 0 terminates the whole mover (preserved — do not capture this
    # helper via $(…), or exit 0 would quit only the subshell and the mover would proceed).
    if is_aligned "$target" HEAD; then
        if [[ "$skip_when_aligned" == true ]] || ! has_uncommitted_tracked_changes; then
            info "Already at target $(git rev-parse --short "$target"). No action taken."
            exit 0
        fi
        if [[ ${HUG_QUIET:-} != T ]]; then
            info "No commits to $action_name; local tracked changes will be reset."
        fi
        return 0
    fi

    # NOT aligned. Count ahead-commits STRICTLY for the preview (was: swallow via || echo 0).
    # For a forward target this count is 0 (HEAD is behind) and the preview reads
    # "changes in 0 commit:" above the diff stat — cosmetically rough; Phase 2 makes it
    # direction-aware. The operation PROCEEDS either way: resetting onto a descendant moves
    # HEAD forward instead of no-op'ing.
    local commits_to_affected
    commits_to_affected=$(count_commits_in_range "$target" HEAD) || return 1

    if [[ ${HUG_QUIET:-} != T ]]; then
        local range_for_diff
        range_for_diff="$target..HEAD"
        local commit_word="commit"
        if [ "$commits_to_affected" -gt 1 ]; then
            commit_word="commits"
        fi

        printf 'Commits to be affected:\n' >&2
        print_commit_list_in_range "$target" HEAD >&2

        if git diff --quiet "$range_for_diff"; then
            printf '\nPreview: no file changes in %d %s.\n' >&2 \
                "$commits_to_affected" "$commit_word"
        else
            printf '\nPreview: changes in %d %s:\n' >&2 \
                "$commits_to_affected" "$commit_word"
            git diff --stat "$range_for_diff" >&2
        fi
    fi
}
```

> Verify `is_aligned` is available: `hug-git-upstream` is sourced after `hug-git-commit` by `hug-git-kit:30` (order: … hug-git-commit hug-git-upstream …), so `is_aligned` is defined before `handle_standard_operation` runs. The test file loads `hug-git-commit` before `hug-git-upstream` (already the case).

- [ ] **Step 4: Run the tests to verify they pass** — `make test-lib TEST_FILE=test_hug-upstream.bats TEST_SHOW_ALL_RESULTS=1`. Expected: all pass (forward no longer no-ops; aligned still no-ops).

- [ ] **Step 5: Commit**

```bash
hug a git-config/lib/hug-git-upstream tests/lib/test_hug-upstream.bats
hug c -m "fix(head-movers): stop the forward-target no-op in handle_standard_operation

handle_standard_operation tested alignment with a one-directional
\`count_commits_in_range \"\$target\" HEAD == 0\`, which is true BOTH when aligned AND when
HEAD is BEHIND the target (a forward/descendant target). So \`hug h back|undo|rollback|
rewind <descendant-SHA>\` on a clean tree printed 'Already at target', exited 0, and left
HEAD unmoved — the mechanism behind #222's Critical #1 (recovery hints that no-op).

Replace the guard with is_aligned (exact SHA equality). A forward target now proceeds and
the mover's reset moves HEAD forward; only a truly-aligned target no-ops. The helper is
still called bare, so its exit 0 still terminates the mover (the aligned guard is intact).
The preview count is now strict. The direction-cased preview/message is deferred to Phase 2.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Site 2 — `git-cmv` strict + truthful branched message (NOT `is_aligned`)

**Goal:** Keep cmv's correct `== 0` vacuous-op guard, make it strict, and fix its misleading "already at target" message to be truthful in both sub-cases (aligned vs descendant) by branching on `is_aligned`.

**Files:**
- Modify: `git-config/bin/git-cmv:158-164`
- Test: `tests/unit/test_commit.bats` (the `# hug cmv expectations` section, ~line 336)

**Acceptance Criteria:**
- [ ] `count_commits_in_range` call carries `|| exit 1` (strict).
- [ ] `== 0` guard is retained (do NOT migrate to `is_aligned` — cmv's `== 0` is the correct vacuous-op semantic).
- [ ] Aligned target (`hug cmv HEAD <branch>` / `<SHA-of-HEAD>`) → "No commits to move (already at …)".
- [ ] Descendant target → "No commits to move (target … is a descendant of HEAD; cmv needs an ancestor target)".
- [ ] In neither case does the branch move forward (no forward-hard-reset regression).

**Verify:** `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="cmv" TEST_SHOW_ALL_RESULTS=1` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing tests** — append to the `# hug cmv expectations` section of `tests/unit/test_commit.bats`:

```bash
@test "hug cmv: aligned target (HEAD) -> 'already at' message, branch unmoved" {
  create_test_repo_with_history
  git checkout -q -b feature 2>/dev/null || git checkout -q -b feature
  local before; before=$(git rev-parse HEAD)
  run env HUG_FORCE=true hug cmv HEAD main
  assert_success
  assert_output --partial "already at"
  refute_output --partial "is a descendant"
  [ "$(git rev-parse HEAD)" = "$before" ]            # branch did NOT move
}

@test "hug cmv: descendant target -> 'is a descendant of HEAD' message, branch unmoved" {
  create_test_repo_with_history
  git checkout -q -b feature 2>/dev/null || git checkout -q -b feature
  local descendant; descendant=$(git rev-parse HEAD)
  git reset -q --hard HEAD~1                          # HEAD now behind 'descendant'
  local before; before=$(git rev-parse HEAD)
  run env HUG_FORCE=true hug cmv "$descendant" main
  assert_success
  assert_output --partial "is a descendant of HEAD"
  refute_output --partial "already at"
  [ "$(git rev-parse HEAD)" = "$before" ]            # branch did NOT move forward (no regression)
}
```

> If `test_commit.bats` has no `# hug cmv expectations` section, append these tests at the end of the file (after the existing cmv tests, if any). Adjust `create_test_repo_with_history`/branch names to match the file's existing setup helpers.

- [ ] **Step 2: Run the tests to verify they fail** — `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="cmv" TEST_SHOW_ALL_RESULTS=1`. Expected: the descendant test FAILS (current message is "already at target" for both sub-cases — wrong for the descendant case).

- [ ] **Step 3: Fix the cmv guard + message** — in `git-config/bin/git-cmv`, replace lines ~159-164:

```bash
# Early calculation for commits to relocate (for 0-commit early exit and prompts).
# cmv's target MUST be an ancestor ("specific commit to move above", "reset branch back"),
# so == 0 is the correct vacuous-op no-op — do NOT migrate this to is_aligned (a forward
# target is an incoherent cmv request, and resetting onto it would hard-reset the branch
# FORWARD + switch branch on a 'NOT RESTORABLE' command). Strict: a bad ref now fails
# loudly instead of masquerading as '0 commits'. The OLD message lied ('already at target')
# for a descendant target; branch on is_aligned so BOTH sub-cases are truthful (a commit is
# its own ancestor, so 'is not an ancestor' would lie when aligned — equality-as-ancestry).
commits_to_relocate=$(count_commits_in_range "$target" HEAD) || exit 1
if [ "$commits_to_relocate" -eq 0 ]; then
  if is_aligned "$target" HEAD; then
    info "No commits to move (already at $(git rev-parse --short "$target"))."
  else
    info "No commits to move (target $(git rev-parse --short "$target") is a descendant of HEAD; cmv needs an ancestor target)."
  fi
  exit 0
fi
```

> `is_aligned` is available: `git-cmv:9` sources `hug-common hug-git-kit`, and `hug-git-kit` loads `hug-git-commit` (where `is_aligned` lives).

- [ ] **Step 4: Run the tests to verify they pass** — `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="cmv" TEST_SHOW_ALL_RESULTS=1`. Expected: both new tests pass; existing cmv tests still pass.

- [ ] **Step 5: Commit**

```bash
hug a git-config/bin/git-cmv tests/unit/test_commit.bats
hug c -m "fix(cmv): strict count + truthful 0-commit message (keep the vacuous-op guard)

git-cmv's \`count == 0 -> no-op\` is CORRECT (its target must be an ancestor — 'commit to
move above' / 'reset branch back' — so a descendant has nothing above it). It is NOT the
Defect-1 alignment conflation, so it is deliberately NOT migrated to is_aligned (doing so
would hard-reset the branch forward + switch branch on a 'NOT RESTORABLE' command).

Fixes: (1) strictify the count (|| exit 1); (2) the old 'already at target' message lied
for a descendant target. Branch the message on is_aligned so both sub-cases are truthful —
aligned -> 'already at'; descendant -> 'is a descendant of HEAD; cmv needs an ancestor
target'. (A single 'is not an ancestor' would lie when aligned, since a commit is its own
ancestor.) The branch never moves forward in either case (regression-pinned by tests).

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 5: Sites 3a + 3b — `git-h-restore` adopts `is_aligned` + rewrite stale comments

**Goal:** Migrate `git-h-restore`'s SHA-equality check to `is_aligned` (DRY — the only alignment idiom left), and rewrite every stale comment that cites the deleted `count==0` mechanism: the `git-h-restore` header/inline blocks AND the `git-h-back`/`git-h-undo` root-path danger-tier comments.

**Files:**
- Modify: `git-config/bin/git-h-restore:107` (is_aligned) + comments `:16-20`, `:27-28`, `:104-106`
- Modify: `git-config/bin/git-h-back:105-108` (root-path comment)
- Modify: `git-config/bin/git-h-undo:123-126` (root-path comment)
- Test: `tests/unit/test_h_restore.bats`

**Acceptance Criteria:**
- [ ] `git-h-restore:107` uses `is_aligned "$target" HEAD` instead of `[ "$target" = "$(git rev-parse HEAD)" ]`.
- [ ] `hug h restore <HEAD-SHA> --back` → "Already at … Nothing to restore." (aligned no-op preserved).
- [ ] `hug h restore <invalid-SHA> --back` → non-zero (loud failure, not silent).
- [ ] `git-h-restore` header `:16-20` no longer claims the movers no-op "via handle_standard_operation's count==0 gate"; `:27-28` no longer says additions "arrive in Task 8"; inline `:104-106` no longer cites the "count==0 bailout".
- [ ] `git-h-back:105-108` and `git-h-undo:123-126` say recovery at root is a "loud failure" (strict propagation), not a "guaranteed no-op (rev-list fails ⇒ count 0)".
- [ ] `grep -rn "count==0\|aligned-target short-circuit\|count 0\b" git-config/bin/git-h-restore git-config/bin/git-h-back git-config/bin/git-h-undo` returns no stale rationale references.

**Verify:** `make test-unit TEST_FILE=test_h_restore.bats TEST_SHOW_ALL_RESULTS=1` → all pass; grep above → empty.

**Steps:**

- [ ] **Step 1: Write the failing tests** — append to `tests/unit/test_h_restore.bats`:

```bash
@test "h restore: aligned target (HEAD) -> 'Nothing to restore' no-op (via is_aligned)" {
  create_test_repo_with_history
  run env HUG_FORCE=true hug h restore "$(git rev-parse HEAD)" --back
  assert_success
  assert_output --partial "Nothing to restore"
}

@test "h restore: invalid SHA -> loud failure (not silent)" {
  create_test_repo_with_history
  run env HUG_FORCE=true hug h restore NO_SUCH_REF --back
  assert_failure
}
```

> Confirm `test_h_restore.bats` exists and uses `create_test_repo_with_history` + `HUG_FORCE`. If the file's existing tests already cover the aligned no-op, keep them and add only the invalid-SHA test. `h restore` requires an op flag (`--back|--undo|--rollback|--rewind`).

- [ ] **Step 2: Run the tests to verify behavior** — `make test-unit TEST_FILE=test_h_restore.bats TEST_SHOW_ALL_RESULTS=1`. The aligned test should already pass (the old SHA check worked); the invalid-SHA test may pass or fail depending on `validate_commitish` upstream — record the baseline. (This task's behavior change is the migration to `is_aligned`; the tests pin the preserved behavior.)

- [ ] **Step 3: Migrate the check to `is_aligned`** — in `git-config/bin/git-h-restore`, replace line ~107:

```bash
# The defining feature: no-op ONLY on exact SHA equality (via is_aligned), never the
# range-count gate. The movers now share this same is_aligned gate (hug-git-upstream),
# so recovery and the movers agree on what 'already there' means. is_aligned (unlike a
# one-directional count == 0) distinguishes 'aligned' from 'need to move forward'.
if is_aligned "$target" HEAD; then
  info "Already at $(git rev-parse --short "$target"). Nothing to restore."
  exit 0
fi
```

- [ ] **Step 4: Rewrite the `git-h-restore` header WHY block** — replace lines ~16-20:

```bash
# WHY this exists: an explicit recovery primitive that resets HEAD to a target commit as
# the inverse of a HEAD-mover (h-back/h-undo/h-rollback/h-rewind). Its no-op test is EXACT
# SHA equality (via is_aligned) — the only test that distinguishes "already there" from
# "move to a different commit," including a FORWARD move to a descendant. The movers now
# share this same is_aligned gate (hug-git-upstream), so re-invoking a mover to recover is
# no longer a special case; this command remains the dedicated, op-named inverse.
```

- [ ] **Step 5: Rewrite the `git-h-restore` "Task 8" line** — replace lines ~27-28 (the stale "safety additions … arrive in Task 8" — these are already implemented at `:85-86` and `:117-120`):

```bash
#   - Safety additions are in place: bare-numeric guard (:85-86), --rewind+dirty danger
#     escalation, and per-tier prompts (:117-120).
```

> Read the surrounding lines first to match the exact comment-block wording/indentation; the above conveys the corrected content — preserve the list's formatting.

- [ ] **Step 6: Rewrite the `git-h-back` root-path comment** — replace lines ~105-108:

```bash
    # Root-commit path stays DANGER (spec §6): recovery at root is a guaranteed LOUD FAILURE
    # post-#229-Phase-1 (unborn HEAD ⇒ the now-strict rev-list propagates non-zero ⇒ the
    # mover exits ≠ 0), so there is still no complete recovery to license a warn tier. The
    # non-root path below is warn because --soft preserves all work; this root path must NOT
    # be swept along with it.
```

- [ ] **Step 7: Rewrite the `git-h-undo` root-path comment** — replace lines ~123-126:

```bash
    # Root-commit path stays DANGER (spec §6): same root-commit reasoning as h-back — at
    # root, recovery is a guaranteed LOUD FAILURE (unborn HEAD ⇒ strict rev-list propagates
    # non-zero ⇒ mover exits ≠ 0), so there is no complete recovery to license a warn tier.
    # The non-root path below is warn because --mixed preserves all work; this root path
    # must NOT be swept along with it.
```

> (Behavior note: Phase 1 changes root-recovery from a silent no-op to a loud failure — an improvement. The danger tier stands either way. The root-recovery *fix* itself remains deferred to #222 §10.)

- [ ] **Step 8: Run the tests + grep** —

```bash
make test-unit TEST_FILE=test_h_restore.bats TEST_SHOW_ALL_RESULTS=1   # all pass
grep -rn "count==0\|aligned-target short-circuit\|count 0\b\|arrive in Task 8" \
  git-config/bin/git-h-restore git-config/bin/git-h-back git-config/bin/git-h-undo   # expect empty
```

- [ ] **Step 9: Commit**

```bash
hug a git-config/bin/git-h-restore git-config/bin/git-h-back git-config/bin/git-h-undo tests/unit/test_h_restore.bats
hug c -m "refactor(h-restore): adopt is_aligned; rewrite stale count==0 rationale comments

git-h-restore:107 now uses is_aligned instead of a raw SHA string compare, so it shares
the single sanctioned alignment idiom with the movers (DRY; behavior preserved — aligned
target no-ops, invalid SHA fails loudly).

Rewrite every comment that cited the now-deleted count==0 mechanism, so the spec doesn't
move the docs-drift: git-h-restore's header WHY block (:16-20) and inline note (:104-106)
no longer claim the movers no-op 'via the count==0 gate'; the stale 'arrive in Task 8'
line (:27-28) is corrected (those additions already exist); and the root-commit danger-tier
comments in git-h-back (:105-108) and git-h-undo (:123-126) are reworded — recovery at root
is now a LOUD FAILURE (strict rev-list propagates), not a 'guaranteed no-op (count 0)'.
The danger tier stands either way; the root-recovery fix itself stays deferred to #222 §10.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 6: Explicit strict propagation at the remaining strict call sites

**Goal:** Add explicit `|| exit 1` to the top-level strict callers that currently rely on implicit `set -e` (`git-log-outgoing:92`, `git-h-files:122`, `git-h-squash:167/:176`), for clarity/robustness — without removing `git-h-squash:177`'s LIVE `== 0` branch.

**Files:**
- Modify: `git-config/bin/git-log-outgoing:92`
- Modify: `git-config/bin/git-h-files:122`
- Modify: `git-config/bin/git-h-squash:167,176`
- Test: `tests/unit/test_head.bats` (squash live-branch pin)

**Acceptance Criteria:**
- [ ] `git-log-outgoing:92`, `git-h-files:122`, `git-h-squash:167`, `git-h-squash:176` each carry `|| exit 1`.
- [ ] `git-h-squash:177`'s `== 0` branch is **NOT** removed (it is LIVE via `merge-base` equality-as-ancestry).
- [ ] `hug h squash <SHA-of-HEAD>` → "No commits to squash", exit 0, no commit created.
- [ ] Existing log-outgoing / h-files / h-squash behavior on valid refs is unchanged.

**Verify:** `make test-unit TEST_FILE=test_head.bats TEST_FILTER="squash" TEST_SHOW_ALL_RESULTS=1` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing/pinning test** — append to `tests/unit/test_head.bats` (or the file that covers h-squash; verify with `grep -rln "h squash\|h-squash" tests/unit/`):

```bash
@test "h squash <SHA-of-HEAD>: live == 0 branch -> 'No commits to squash', no commit created" {
  create_test_repo_with_history
  local before_count; before_count=$(git rev-list --count HEAD)
  run env HUG_FORCE=true hug h squash "$(git rev-parse HEAD)"
  assert_success
  assert_output --partial "No commits to squash"
  [ "$(git rev-list --count HEAD)" = "$before_count" ]   # no orphan '[squash] 0 commits' commit
}
```

> This test PINS the live `== 0` branch (merge-base treats equality as ancestry, so `ensure_ancestor_of_head` passes for HEAD and the `:177` branch fires). It guards against a future "dead code" deletion resurrecting the 0-commit orphan bug (`git-h-squash:161-163`).

- [ ] **Step 2: Run the test to confirm it passes against current code** — `make test-unit TEST_FILE=test_head.bats TEST_FILTER="squash" TEST_SHOW_ALL_RESULTS=1`. Expected: PASS (the `== 0` branch already exists). This is a pin test; the code change in this task is the strictness explicitness, which must NOT break it.

- [ ] **Step 3: Add explicit `|| exit 1` to `git-log-outgoing:92`** —

```bash
local_commits=$(count_commits_in_range "$target" HEAD) || exit 1
```

- [ ] **Step 4: Add explicit `|| exit 1` to `git-h-files:122`** —

```bash
  local_commits=$(count_commits_in_range "$start_point" HEAD) || exit 1
```

> `git-h-files:122` is script top-level (inside an `if $upstream` block, NOT a function) — do NOT add `local` (fatal at top level). The bare assignment + `|| exit 1` is correct.

- [ ] **Step 5: Add explicit `|| exit 1` to `git-h-squash:167` and `:176`** —

```bash
  commits_to_squash=$(count_commits_in_range "$target" HEAD) || exit 1
```

and

```bash
  commits_to_squash=$(count_commits_in_range "$target_commit" HEAD) || exit 1
  if [ "$commits_to_squash" -eq 0 ]; then
    info "No commits to squash (already at $target_display)."
    exit 0
  fi
```

> Do NOT remove the `:177` `== 0` branch — it is LIVE (`hug h squash <SHA-of-HEAD>` reaches it; `ensure_ancestor_of_head` uses `merge-base --is-ancestor`, which treats equality as ancestry). Deleting it resurrects the 0-commit orphan bug the file's own comment (`:161-163`) records.

- [ ] **Step 6: Run the tests to verify nothing broke** —

```bash
make test-unit TEST_FILE=test_head.bats TEST_FILTER="squash" TEST_SHOW_ALL_RESULTS=1   # squash pin passes
make test-unit TEST_SHOW_ALL_RESULTS=1                                                  # broader unit tests green
```

- [ ] **Step 7: Commit**

```bash
hug a git-config/bin/git-log-outgoing git-config/bin/git-h-files git-config/bin/git-h-squash tests/unit/test_head.bats
hug c -m "fix: explicit strict propagation at remaining count_commits_in_range callers

Add explicit '|| exit 1' to the top-level strict callers (git-log-outgoing:92,
git-h-files:122, git-h-squash:167/:176). These are script-top-level (set -e already exits
on a failing bare assignment), so this is clarity/robustness — belt-and-suspenders against
a future set +e — not a behavior change on valid refs. git-h-files:122 stays a bare
top-level assignment (do NOT add 'local' — fatal at top level).

Pin git-h-squash:177's '== 0' branch with a regression test: it is LIVE (merge-base
equality-as-ancestry lets 'h squash <SHA-of-HEAD>' reach it), and deleting it would
resurrect the 0-commit orphan bug the file's own comment (:161-163) records.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 7: Per-site strict-propagation enforcement + edge-case + smoke tests

**Goal:** Add the integration-level tests that enforce the audit's central guarantees: every strict call site propagates a `rev-list` failure (the PRIMARY Defect-2 enforcement), the forward-mover no-op is gone end-to-end, and the edge-case behavior changes (root-recovery loud failure, garbage target) are pinned.

**Files:**
- Test: `tests/unit/test_head.bats` (forward-mover smoke, root-recovery, garbage target, per-site strict)

**Acceptance Criteria:**
- [ ] `hug h back <descendant-SHA> -y` on a clean tree moves HEAD forward (not "Already at target") — the headline acceptance criterion.
- [ ] Library-level: `handle_standard_operation` and `handle_upstream_operation` return non-zero on an invalid target.
- [ ] Command-level: `git-cmv` and `git-h-squash` exit non-zero on an invalid ref (not "0 commits").
- [ ] The two display sites (`count_commits_in_range_or_zero`) return 0 / exit 0 on failure (cosmetic).
- [ ] A mover invoked to recover at root fails loudly (not a silent no-op).
- [ ] An unresolvable target through a mover exits non-zero (not a silent "Already at target .").

**Verify:** `make test-unit TEST_FILE=test_head.bats TEST_SHOW_ALL_RESULTS=1` → all pass.

**Steps:**

- [ ] **Step 1: Write the forward-mover smoke test (headline)** — append to `tests/unit/test_head.bats`:

```bash
@test "h back <descendant>: moves HEAD forward instead of no-op'ing (#229 headline)" {
  create_test_repo
  echo a > a; git add a; git commit -qm "A"
  echo b > b; git add b; git commit -qm "B"
  echo c > c; git add c; git commit -qm "C"
  local descendant; descendant=$(git rev-parse HEAD)   # C
  git reset -q --hard HEAD~2                            # HEAD back at A, clean tree
  run env HUG_FORCE=true hug h back "$descendant"
  assert_success
  refute_output --partial "Already at target"
  [ "$(git rev-parse HEAD)" = "$descendant" ]          # HEAD moved forward to C
}
```

- [ ] **Step 2: Write the library-level strict-propagation tests** — append to `tests/lib/test_hug-upstream.bats`:

```bash
@test "handle_standard_operation: invalid target -> non-zero (strict, not silent no-op)" {
  run handle_standard_operation "move back" "NO_SUCH_REF_XYZ"
  assert_failure
}

@test "handle_upstream_operation: propagates a failing count (|| return 1)" {
  # No upstream configured -> get_upstream_commit fails first; assert non-zero either way.
  run handle_upstream_operation "moving" warn "move" "reason"
  assert_failure
}
```

- [ ] **Step 3: Write the command-level strict-propagation tests** — append to `tests/unit/test_head.bats`:

```bash
@test "h squash <invalid-ref>: exits non-zero (strict), not '0 commits'" {
  create_test_repo_with_history
  run env HUG_FORCE=true hug h squash NO_SUCH_REF_XYZ
  assert_failure
}

@test "h files -u with no upstream: exits non-zero (strict), not silent" {
  create_test_repo_with_history   # no upstream configured
  run hug h files -u
  assert_failure
}
```

> Adjust command invocations to the actual flags (`hug h files -u` may need verification; if `h files` is `git-h-files`, confirm its `-u` flag and that "no upstream" is the failure path). The intent: a `rev-list`/upstream failure surfaces as a non-zero exit, never "0 commits"/"Already synced".

- [ ] **Step 4: Write the edge-case behavior tests** — append to `tests/unit/test_head.bats`:

```bash
@test "h back at root commit (recovery): loud failure, not silent no-op (#229 edge)" {
  create_test_repo
  echo a > a; git add a; git commit -qm "A"      # single (root) commit
  # Recovering 'back' at root has no ancestor; post-Phase-1 this fails loudly.
  run env HUG_FORCE=true hug h back 1
  assert_failure                                  # was: silent 'Already at target' via the swallow
}

@test "h back <garbage-target>: loud failure, not silent 'Already at target .'" {
  create_test_repo_with_history
  run env HUG_FORCE=true hug h back "definitely-not-a-ref-12345"
  assert_failure
  refute_output --partial "Already at target"
}
```

> These two edge cases are bonus loud-failure fixes the strictification delivers (root-recovery and the garbage-target leak from `resolve_target_with_temporal`). If `hug h back 1` at a single-commit repo takes a dedicated root-path that exits 0 by design, adjust the assertion to match the actual root-path contract (the point is it must not SILENTLY no-op via the deleted swallow).

- [ ] **Step 5: Run all the new tests** —

```bash
make test-unit TEST_FILE=test_head.bats TEST_SHOW_ALL_RESULTS=1
make test-lib TEST_FILE=test_hug-upstream.bats TEST_SHOW_ALL_RESULTS=1
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
hug a tests/unit/test_head.bats tests/lib/test_hug-upstream.bats
hug c -m "test: per-site strict-propagation enforcement + forward-mover + edge cases

Integration tests for the #229 Phase-1 guarantees:
- Headline: 'hug h back <descendant>' moves HEAD forward instead of no-op'ing.
- PRIMARY Defect-2 enforcement: each strict call site propagates a rev-list failure
  (library-level handle_standard_operation/handle_upstream_operation; command-level
  h-squash/h-files), never '0 commits'/'Already synced'.
- Edge cases now loud (bonus strictification fixes): root-commit recovery and a garbage
  target through a mover both exit non-zero instead of silently no-op'ing.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 8: Documentation — `lib/README.md` + docstring cross-references

**Goal:** Document the one-directional contract + forbid the alignment idiom in `git-config/lib/README.md`, fix the pre-existing `:98` predicate drift, cross-reference `is_aligned`, and refresh the helper-usage examples.

**Files:**
- Modify: `git-config/lib/README.md` (Range counting subsection near `:414`; `:98`/`:133`; `:425-435`)

**Acceptance Criteria:**
- [ ] A "Range counting" subsection states: `count_commits_in_range` is a one-directional ahead-count (`== 0` means "not ahead," NOT "aligned"); use `is_aligned` for alignment and `commits_ahead_behind` for the relationship; the strict functions + wrapper propagate / handle failures.
- [ ] `:98` no longer attributes the aligned-target predicate to `has_untracked_or_pending_changes` (it is `has_uncommitted_tracked_changes`, matching `:133` and `hug-git-upstream:110`).
- [ ] `:98` and `:133` cross-reference `is_aligned` as the sanctioned alignment test.
- [ ] The `:425-435` examples show `handle_standard_operation` called bare (its `exit 0` guard depends on it) and `handle_upstream_operation` returning the SHA.

**Verify:** `grep -n "is_aligned\|one-directional\|Range counting" git-config/lib/README.md` shows the new content; `grep -n "has_untracked_or_pending_changes" git-config/lib/README.md` no longer misattributes the aligned-target predicate.

**Steps:**

- [ ] **Step 1: Read the current README regions** —

```bash
sed -n '95,135p' git-config/lib/README.md     # aligned-target gating prose (:98/:133)
sed -n '405,436p' git-config/lib/README.md    # helper-usage examples (:414/:425-435)
```

- [ ] **Step 2: Fix the `:98` predicate drift + add `is_aligned` cross-refs** — at `:98`, change the aligned-target-gating predicate from `has_untracked_or_pending_changes` to `has_uncommitted_tracked_changes` (matching `:133` and the code at `hug-git-upstream:110`), and add to both `:98` and `:133` a cross-reference: "alignment itself is tested with `is_aligned` (see Range counting below) — never with `count_commits_in_range == 0`."

- [ ] **Step 3: Add the "Range counting" subsection** — insert near the existing `count_commits_in_range` example (`:414`):

```markdown
#### Range counting — pick the right primitive

- **`count_commits_in_range "start" ["end"]`** — a ONE-DIRECTIONAL ahead-count: how far
  `end` is ahead of `start`. A result of `0` means "`end` is NOT ahead of `start`" — which
  is true BOTH when `end == start` (aligned) AND when `end` is *behind* `start`. **Never
  treat `0` as "aligned."** Strict: a failed `rev-list` (invalid ref, unborn HEAD)
  propagates non-zero — it is NOT swallowed into `0`.
- **`commits_ahead_behind "start" "end"`** — the full relationship as `"<behind>\t<ahead>"`
  (git's native `--left-right` order: first arg's exclusive count FIRST). `0\t0` ⟺ aligned.
  Parse into POSITIONAL fields; do not `read ahead behind` (the name order ≠ output order).
- **`is_aligned "a" "b"`** — the ONLY sanctioned alignment test (exact SHA equality). Use
  this wherever you previously wrote `count_commits_in_range … == 0` to mean "aligned."
- **`count_commits_in_range_or_zero`** — display-only twin: a cosmetic `0` on failure, for
  rendered plans / tip text only. Never for a branching or alignment decision. (`|| echo 0`
  appears nowhere outside this one definition.)
```

- [ ] **Step 4: Refresh the helper-usage examples (`:425-435`)** — ensure the `handle_standard_operation` example shows it called **bare** (add a comment: "called bare — its `exit 0` aligned-guard terminates the caller; do NOT capture via `$(…)`"), and the `handle_upstream_operation` example shows it returning the upstream SHA (`target=$(handle_upstream_operation …)`). Add a one-line `is_aligned` usage example.

- [ ] **Step 5: Verify** —

```bash
grep -n "Range counting\|is_aligned\|ONE-DIRECTIONAL" git-config/lib/README.md
grep -n "has_untracked_or_pending_changes" git-config/lib/README.md   # should not misattribute aligned-target gating
make docs-build 2>/dev/null || true                                   # if README feeds the docs site, confirm it builds
```

- [ ] **Step 6: Commit**

```bash
hug a git-config/lib/README.md
hug c -m "docs(lib): Range counting primitives + forbid the count==0 alignment idiom

Document the one-directional contract of count_commits_in_range (== 0 means 'not ahead',
NOT 'aligned'), the sanctioned is_aligned alignment test, commits_ahead_behind, and the
count_commits_in_range_or_zero display wrapper in a new 'Range counting' subsection.

Fix pre-existing drift: README:98 attributed handle_standard_operation's aligned-target
predicate to has_untracked_or_pending_changes; the code (hug-git-upstream:110) and
README:133 both use has_uncommitted_tracked_changes — corrected :98 to match. Cross-
reference is_aligned at :98/:133. Refresh the helper-usage examples to show
handle_standard_operation called bare (its exit 0 guard depends on it).

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 9: Final verification — sanitize, full suite, grep canary, manual smoke

**Goal:** Run the full quality gate: `make sanitize` (shellcheck/format), the complete test suite, the `|| echo 0` canary, and a manual end-to-end smoke of the headline fix.

**Files:** (verification only — no source changes expected; if `make sanitize` reformats, fold it in)

**Acceptance Criteria:**
- [ ] `make sanitize` passes (no shellcheck/format errors on touched files).
- [ ] `make test` (full suite: BATS + pytest) passes.
- [ ] `grep -rn '|| echo 0' git-config/` returns exactly one line (the wrapper body).
- [ ] Manual smoke: `hug h back <descendant>` moves HEAD forward; `hug h restore <HEAD> --back` no-ops; `hug cmv HEAD <branch>` says "already at".

**Verify:** `make sanitize && make test` → green; manual smoke commands behave as specified.

**Steps:**

- [ ] **Step 1: Run the sanitize gate** —

```bash
make sanitize
```

Expected: pass. If it reformats any touched file, stage the changes (`hug a <files>`) and amend the relevant task's commit (`hug cmod --no-edit`) — do not leave uncommitted reformatting.

- [ ] **Step 2: Run the full test suite** —

```bash
make test TEST_SHOW_ALL_RESULTS=1
```

Expected: all tests pass (BATS unit/lib/integration + pytest). Investigate any failure before proceeding.

- [ ] **Step 3: Verify the grep canary** —

```bash
grep -rn '|| echo 0' git-config/    # exactly 1 line: count_commits_in_range_or_zero body
grep -rn 'count_commits_in_range' git-config/ | grep -vE 'count_commits_in_range_or_zero|_or_zero|#' | grep -v '|| \(exit\|return\) 1'   # review: every remaining call should be a split-local + guarded call, the function def, or a wrapper call
```

- [ ] **Step 4: Manual end-to-end smoke** —

```bash
source bin/activate
tmp=$(mktemp -d); hug -C "$tmp" init smoke 2>/dev/null; cd "$tmp/smoke"
git config user.email t@t; git config user.name t
echo a>a; git add a; git commit -qm A
echo b>b; git add b; git commit -qm B
echo c>c; git add c; git commit -qm C
desc=$(git rev-parse HEAD)
git reset -q --hard HEAD~2
echo "--- h back <descendant> (should move HEAD forward to C) ---"
hug h back "$desc" -y; echo "HEAD now: $(git rev-parse --short HEAD) (want $(git rev-parse --short "$desc"))"
echo "--- h restore <HEAD> --back (should no-op) ---"
hug h restore "$(git rev-parse HEAD)" --back -y
echo "--- cmv HEAD main (should say 'already at') ---"
git checkout -q -b feat; hug cmv HEAD main -y
cd - >/dev/null; rm -rf "$tmp"
```

Expected: HEAD moves forward to the descendant; restore no-ops ("Nothing to restore"); cmv says "already at".

- [ ] **Step 5: Confirm Phase-1 scope is complete; Phase 2 not touched** —

```bash
# Phase 2 helpers must NOT exist yet:
grep -rn "direction_between\|report_head_move\|HUG_HEAD_MOVE_DIRECTION" git-config/ && echo "ERROR: Phase 2 leaked into Phase 1" || echo "OK: Phase 2 not present (as intended)"
```

Expected: "OK: Phase 2 not present (as intended)".

- [ ] **Step 6: Final commit (only if sanitize reformatted anything)** — if Step 1 produced reformatting not yet committed, amend it into the appropriate task commit. Otherwise no commit needed.

```bash
# Only if there are uncommitted sanitize changes:
hug a -u && hug cmod --no-edit
```

---

## Self-Review Notes

**Spec coverage** (each Phase-1 acceptance criterion → task):
- All 9 call sites audited, `== 0` classified → Tasks 2/3/4/6 implement the per-site actions from the §4 table.
- Unsafe alignment tests → `is_aligned` → Task 3 (handle_standard_operation), Task 5 (h-restore). cmv deliberately NOT migrated → Task 4.
- handle_standard_operation no longer no-ops on forward target → Task 3 + headline test in Task 7.
- `|| echo 0` removed; named wrapper; per-site strict-propagation test → Tasks 2 (wrapper + strictify) + 7 (enforcement).
- Docstring + README state the contract + forbid the idiom → Task 8 (+ docstrings in Tasks 1/2).
- h-restore stale comments + h-back/h-undo root-path comments rewritten → Task 5.
- is_aligned unborn-HEAD precondition documented + tested → Task 1.
- squash `:177` live branch preserved → Task 6 (pin test).

**Placeholder scan:** none — every code step shows the exact code; every test step shows the exact test; commands have expected output.

**Type/name consistency:** `commits_ahead_behind`, `is_aligned`, `count_commits_in_range`, `count_commits_in_range_or_zero` named identically across all tasks. `handle_standard_operation` called bare everywhere (Task 3 preserves this; Task 5 comments reference it). The direction-messaging names (`direction_between`, `report_head_move`, `HUG_HEAD_MOVE_DIRECTION`) appear ONLY in Task 9's "Phase 2 not present" guard — never implemented in Phase 1.

**Deferred to Phase 2** (explicitly NOT in this plan): direction-cased preview, `direction_between`, `report_head_move`, mover-tail direction threading, direction-truthful result messages, README messaging-helper examples.
