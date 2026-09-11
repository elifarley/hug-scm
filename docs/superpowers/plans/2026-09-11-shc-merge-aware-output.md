# shc Merge-Aware Output (issue 268) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `hug shc <merge-commit>` list the merge's changes (instead of printing nothing with exit 0), via an explicit opt-in flag on the shared `pinned_diff` helper, and flip the documentation/test contract that PR #345 pinned for exactly this round.

**Architecture:** `pinned_diff` (git-config/lib/hug-git-diff:650) is the single choke point through which BOTH `shc` modes flow (`--stat` directly at git-shc:294, `-n`/`-z` via `show_changed_file_names` at hug-git-show:207). Per the recorded user preference (OB `29171525`): behavior changes on shared helpers must ride an explicit two-valued contract — a new `--merge-aware` flag, default byte-identical for all 3 existing callers. `sh`/`shp` stats DELEGATE to `git shc` (`HUG_QUIET=T git shc` at hug-git-show:274), so fixing shc fixes their File stats sections for free; `hug-file-input` (h-file-input:149) does NOT opt in and stays suppressed (boundary pin).

**Tech Stack:** Bash, git diff-tree `-m` (per-parent merge diffs — the verified fix candidate from the #268 evidence note; `--cc`/combined rejected because it omits clean merges), BATS (bats >= 1.14 for `run --separate-stderr`).

**Key behavioral facts (all probe-verified on git 2.34.1, PR #345 rounds):**
- Plain `git diff-tree --no-commit-id -r --root M` on a merge → empty, exit 0 (the bug).
- `git diff-tree -m ...` → one diff PER PARENT, sequentially. Typical feature-into-main merge where main did not move: parent-2 diff is empty, so output = exactly the brought-in files, once. When both sides moved: two blocks (a file touched on both sides appears once per parent — git's `-m` semantics, kept raw, no dedup).
- `sh`/`shp` stats inherit everything through `git shc`.

---

### Task 1: `pinned_diff --merge-aware` (shared helper, explicit contract)

**Goal:** The shared helper learns merge-aware diffs as an explicit opt-in; every existing caller stays byte-identical.

**Files:**
- Modify: `git-config/lib/hug-git-diff` (function `pinned_diff`, lines ~650-700)
- Test: `tests/lib/test_hug_git_diff.bats`

**Acceptance Criteria:**
- [ ] `pinned_diff --merge-aware --name-only <merge>` lists the merged file(s); without the flag, the same call prints nothing (v1 behavior pinned).
- [ ] `--merge-aware` on a NON-merge commit produces byte-identical output to the same call without the flag.
- [ ] `--merge-aware` with a range ref is a usage error (exit 2, message "--merge-aware is only valid for single commits").
- [ ] `--merge-aware --stat <merge>` prints the per-parent stat block(s).
- [ ] Full existing suite green (no caller behavior changed).

**Verify:** `make test-lib TEST_FILE=test_hug_git_diff.bats` → all pass; `make test` → green.

**Steps:**

- [ ] **Step 1: Write the failing tests** — append to `tests/lib/test_hug_git_diff.bats` (after the fixture helpers; reuses `_make_fixture`):

```bash
# Fixture: branch `side` adds side.txt at HEAD; merge --no-ff into the main
# line (main did NOT move → parent-2 diff is empty, so -m output lists
# side.txt exactly once). Deterministic typical-merge shape.
_make_merge_fixture() {
  _make_fixture
  git checkout -qb side
  echo s > side.txt && git add side.txt && git commit -qm side
  git checkout -q main
  git merge -q --no-ff side -m "Merge side"
}

@test "pinned_diff: merge commit suppressed by default (v1 byte-identical guard)" {
  _make_merge_fixture
  run pinned_diff --name-only HEAD
  assert_success
  assert_output ""
}

@test "pinned_diff: --merge-aware lists merge changes vs each parent (-n)" {
  _make_merge_fixture
  run pinned_diff --merge-aware --name-only HEAD
  assert_success
  assert_line "side.txt"
}

@test "pinned_diff: --merge-aware --stat lists merge stats" {
  _make_merge_fixture
  run pinned_diff --merge-aware --stat HEAD
  assert_success
  assert_output --partial "side.txt"
}

@test "pinned_diff: --merge-aware is byte-identical no-op on non-merge commits" {
  _make_fixture
  run pinned_diff --name-only HEAD
  [[ "$status" -eq 0 ]]
  local plain="$output"
  run pinned_diff --merge-aware --name-only HEAD
  assert_success
  [[ "$output" == "$plain" ]]
}

@test "pinned_diff: --merge-aware rejected for ranges" {
  _make_fixture
  run pinned_diff --merge-aware --name-only 'HEAD~1..HEAD'
  assert_failure
  assert_output --partial "--merge-aware is only valid for single commits"
}
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `make test-lib TEST_FILE=test_hug_git_diff.bats`
Expected: the 5 new tests FAIL (`unknown format '--merge-aware'` / empty-output assertions), all pre-existing tests PASS.

- [ ] **Step 3: Implement the flag** — in `pinned_diff` (hug-git-diff:650), change the flag-parse loop and the diff-tree branch:

```bash
pinned_diff() {
    local null_mode=false no_renames=false merge_aware=false
    # Consume leading flags in a LOOP (any order, any subset — see history
    # below). --merge-aware is the explicit #268 contract: opt into per-parent
    # diffs (-m) for merge commits; without it, output is byte-identical to
    # v1 for every caller.
    while [[ "${1:-}" == "--null" || "${1:-}" == "--no-renames" || "${1:-}" == "--merge-aware" ]]; do
        case "$1" in
        --null) null_mode=true ;;
        --no-renames) no_renames=true ;;
        --merge-aware) merge_aware=true ;;
        esac
        shift
    done
```

After the existing `--null`/format guards, add the range guard:

```bash
    if $merge_aware && is_range "$resolved_ref"; then
        error_usage "pinned_diff: --merge-aware is only valid for single commits, not ranges"
    fi
```

Replace the diff-tree (single-commit) branch:

```bash
    # Merge detection: rev-list --parents prints "<commit> <parent>..." —
    # word count > 2 ⇔ more than one parent ⇔ merge. Cost: one rev-list call
    # ONLY when --merge-aware was passed; default path pays nothing.
    local -a merge_flag=()
    if $merge_aware &&
       [[ $(git rev-list --parents -n 1 -- "$resolved_ref" | wc -w) -gt 2 ]]; then
        merge_flag=(-m)
    fi
    git -c core.quotePath=false -c diff.relative=false \
        diff-tree --no-commit-id "$format" -r --root "${merge_flag[@]+"${merge_flag[@]}"}" \
        "${zflag[@]+"${zflag[@]}"}" "$rename_flag" --ignore-submodules=none \
        "$resolved_ref" "${path_args[@]+"${path_args[@]}"}"
```

(The range/`git diff` branch is untouched — ranges are rejected above before reaching it.)

- [ ] **Step 4: Run the lib file to green**

Run: `make test-lib TEST_FILE=test_hug_git_diff.bats`
Expected: ALL pass (old + new).

- [ ] **Step 5: Byte-identical regression sweep (the preference is load-bearing)**

Run: `make test-bash`
Expected: full BATS suite green — proves the 3 existing callers (`git-shc --stat`, `show_changed_file_names`, `hug-file-input`) are unchanged.

- [ ] **Step 6: Commit**

```bash
hug a git-config/lib/hug-git-diff tests/lib/test_hug_git_diff.bats
hug c -F -   # message: "feat: pinned_diff --merge-aware — explicit per-parent merge diffs (issue 268 contract)"
```

---

### Task 2: Wire shc + flip the PR-#345 contract map (one atomic commit)

**Goal:** `hug shc <merge>` lists merge changes in BOTH modes; the help text, NOTE, equivalents comment, and the four #345-pinned tests flip together so the suite is green atomically.

**Files:**
- Modify: `git-config/bin/git-shc` (flag wiring at the `-n` block ~line 271 and `--stat` site ~line 294; help heredoc lines ~46-52, ~104-107; NOTE ~lines 12-16)
- Modify: `git-config/lib/hug-git-show` (`show_changed_file_names`, lines 194-208 — accept + forward the flag)
- Test: `tests/unit/test_sh.bats` (flip 3 tests, rewrite 1 guard test)

**Acceptance Criteria:**
- [ ] `hug shc <merge>` (default `--stat`) lists the merged file(s), exit 0.
- [ ] `hug shc -n <merge>` and `hug shc -n -z <merge>` list the merged path(s) (line mode C-quotes structural chars exactly as for normal commits; `-z` is raw).
- [ ] `hug shc <merge> -q` → stats on stdout, nothing on stderr; pathspec filtering works; a genuinely-empty merge diff (pathspec matching nothing the merge changed) still prints the (now truthful) "No files matching" hint.
- [ ] Non-merge commits and ranges: byte-identical (full suite pins this).
- [ ] Help text no longer claims merge silence; guard test pins the NEW wording.

**Verify:** `make test-unit TEST_FILE=test_sh.bats` → 97+ rows green; `make test-bash` → green; `make test-lib-py TEST_FILTER="corpus"` → green.

**Steps:**

- [ ] **Step 1: Flip the failing-test oracle first (TDD)** — in `tests/unit/test_sh.bats`, rewrite the two behavioral tests and the guard test:

```bats
@test "hug shc -n: merge commit lists merged files (parity with --stat, issue 268)" {
  git checkout -q -b side HEAD~1
  echo side > side.txt
  git add side.txt
  git commit -qm "side change"
  git checkout -q main
  git merge -q --no-ff side -m "Merge side" >/dev/null 2>&1
  run hug shc -n HEAD
  assert_success
  assert_line "side.txt"
}

@test "hug shc: merge commit lists changes vs each parent (--stat, issue 268)" {
  git checkout -q -b side-stat HEAD~1
  echo side > side-stat.txt
  git add side-stat.txt
  git commit -qm "side-stat change"
  git checkout -q main
  git merge -q --no-ff side-stat -m "Merge side-stat" >/dev/null 2>&1
  # Per-parent diff (git -m): main did not move in this fixture, so the
  # parent-2 diff is empty and side-stat.txt appears exactly once.
  run --separate-stderr hug shc HEAD
  assert_success
  assert_line "side-stat.txt"
}
```

Guard test: keep the `refute_output --regexp 'git diff --stat HEAD[[:space:]]+→'` and `"git show --stat HEAD"` pins; REPLACE the caveat pins with the new wording pins:

```bats
  # Merge contract (issue 268 FIXED): help documents per-parent diffs.
  assert_output --partial "against each parent"
  assert_output --partial "Merge commits"
```

- [ ] **Step 2: Run to verify red** — `make test-unit TEST_FILE=test_sh.bats` → the 2 flipped tests FAIL (merge still silent), guard test FAILS (old wording still present). Everything else passes.

- [ ] **Step 3: Implement.** In `git-config/lib/hug-git-show`, `show_changed_file_names` accepts and forwards the flag:

```bash
show_changed_file_names() {
    local null_mode=false merge_aware=false
    while [[ "${1:-}" == "-z" || "${1:-}" == "--null" || "${1:-}" == "--merge-aware" ]]; do
        case "$1" in
        -z | --null) null_mode=true ;;
        --merge-aware) merge_aware=true ;;
        esac
        shift
    done
    local target="${1:-HEAD}"
    shift || true

    local resolved
    resolved=$(resolve_commit_ref "$target" "HEAD")

    local -a zflag=() maflag=()
    $null_mode && zflag=(--null)
    $merge_aware && maflag=(--merge-aware)
    pinned_diff "${maflag[@]+"${maflag[@]}"}" "${zflag[@]+"${zflag[@]}"}" --name-only "$resolved" "$@"
}
```

In `git-shc`, add merge detection once (after the unborn-HEAD `case` block, before the `-n` branch) and thread it through both sites:

```bash
# Issue 268: a merge commit's plain diff-tree output is EMPTY (git suppresses
# merge diffs without -m). Opt into per-parent diffs only for merges —
# non-merge refs keep byte-identical output.
local -a diff_flags=()
if [[ $(git rev-list --parents -n 1 -- "$commit_ref" 2> /dev/null | wc -w) -gt 2 ]]; then
  diff_flags=(--merge-aware)
fi
```

`-n` branch (both calls):

```bash
  if $null_sep; then
    show_changed_file_names -z "${diff_flags[@]+"${diff_flags[@]}"}" "$commit_ref" "${_pathspec_pathspecs[@]+"${_pathspec_pathspecs[@]}"}"
  else
    show_changed_file_names "${diff_flags[@]+"${diff_flags[@]}"}" "$commit_ref" "${_pathspec_pathspecs[@]+"${_pathspec_pathspecs[@]}"}"
  fi
```

`--stat` site:

```bash
stats_output=$(pinned_diff "${diff_flags[@]+"${diff_flags[@]}"}" --stat "$commit_ref" "${_pathspec_pathspecs[@]+"${_pathspec_pathspecs[@]}"}")
```

Help heredoc — replace the "Exception — merge commits" caveat block (and its trailing blank line) with:

```
    For merge commits, shc diffs against EACH parent (git's -m mode):
    a two-parent merge shows what each side contributed — a file changed
    on both sides appears once per parent diff.
```

Delete the false-hint sentence and the `git show --stat <merge-commit>` escape-hatch pointer (no longer needed; keep the `-q`/`HUG_QUIET` header note in its original CAPTURING OUTPUT place — it is already there).

In the GIT EQUIVALENTS block, replace the "notable divergence" comment pair with:

```
    # Merge commits: hug shc diffs against EACH parent (-m) — for the
    # first-parent-only view, use 'git show --stat <merge-commit>'.
```

Update the top NOTE (lines ~12-16) to:

```bash
# NOTE: since the issue-268 fix, merge commits list per-parent diffs (git -m);
# the contract is test-pinned in tests/unit/test_sh.bats. sh and shp inherit
# this via their HUG_QUIET=T git shc delegation (hug-git-show); hug-file-input
# does NOT pass --merge-aware and stays suppressed (deliberate boundary).
```

- [ ] **Step 4: Run to green (atomic)** — `make test-unit TEST_FILE=test_sh.bats && make test-lib && make test-bash && make test-lib-py TEST_FILTER="corpus"` → all green. If `sh`/`shp`/`h files` tests fail here, STOP: a caller regressed — the byte-identical contract was violated; fix the wiring, not the test.

- [ ] **Step 5: Commit**

```bash
hug a git-config/bin/git-shc git-config/lib/hug-git-show tests/unit/test_sh.bats
hug c -F -   # message: "feat: shc lists merge changes vs each parent — flips the #345 docs contract (issue 268)"
```

---

### Task 3: Delegation contract tests (sh/shp inherit, h files boundary) + close-out

**Goal:** Pin that `sh`/`shp` File stats are merge-aware via their `git shc` delegation, pin `hug-file-input`'s deliberate non-opt-in, and verify no docs page claims the old silence.

**Files:**
- Test: `tests/unit/test_sh.bats` (2 new tests)
- Verify-only: `docs/` (grep), `git-config/lib/hug-file-input:149` (untouched)

**Acceptance Criteria:**
- [ ] `hug sh <merge>` prints the merged file under "📊 File stats:".
- [ ] `hug shp <merge>` shows the patch plus merged-file stats.
- [ ] `hug-file-input` path (no `--merge-aware`) stays suppressed for merges — boundary documented by a test.
- [ ] `grep -rn "lists NO changes\|merge commit lists nothing\|shows nothing" docs/ git-config/` → no stale merge-silence claims (test names/asserts for the FLIPPED behavior are fine).

**Verify:** `make test-unit TEST_FILE=test_sh.bats` → green; `make test` → full green.

**Steps:**

- [ ] **Step 1: Add the delegation + boundary tests** to `tests/unit/test_sh.bats` (after the flipped `--stat` contract test):

```bats
@test "hug sh: merge commit File stats list merged files (shc delegation, issue 268)" {
  git checkout -q -b side-sh HEAD~1
  echo side > side-sh.txt
  git add side-sh.txt
  git commit -qm "side-sh change"
  git checkout -q main
  git merge -q --no-ff side-sh -m "Merge side-sh" >/dev/null 2>&1
  # hug-git-show delegates stats via `HUG_QUIET=T git shc` — shc's merge
  # awareness must surface here without any sh-specific code.
  run hug sh HEAD
  assert_success
  assert_output --partial "side-sh.txt"
}

@test "hug-file-input: merge stays suppressed (no --merge-aware opt-in — deliberate boundary)" {
  git checkout -q -b side-fi HEAD~1
  echo side > side-fi.txt
  git add side-fi.txt
  git commit -qm "side-fi change"
  git checkout -q main
  git merge -q --no-ff side-fi -m "Merge side-fi" >/dev/null 2>&1
  # Pinned so an accidental default-on flip of pinned_diff is caught:
  # only explicit --merge-aware callers may see merge diffs.
  source git-config/lib/hug-git-diff
  run pinned_diff --no-renames --name-only HEAD
  assert_success
  assert_output ""
}
```

(If `test_sh.bats` does not resolve the lib path relatively, anchor the `source` via `$HUG_HOME`/repo root exactly as other lib-sourcing tests in the suite do.)

- [ ] **Step 2: Run** — `make test-unit TEST_FILE=test_sh.bats` → green (the boundary test passes because Task 1 kept the default byte-identical).

- [ ] **Step 3: Docs sweep** — `grep -rn "lists NO changes\|merge commit lists nothing\|first-parent view" docs/ README.md git-config/bin/` → fix any stale claim; expected: none outside the (already flipped) shc heredoc and this plan.

- [ ] **Step 4: Full gate + commit**

```bash
make test   # full BATS + pytest
hug a tests/unit/test_sh.bats
hug c -F -   # message: "test: pin sh/shp merge-stat delegation + hug-file-input suppression boundary (issue 268)"
```

---

## Out of scope (deliberate)

- `hug-file-input` gaining merge awareness (its consumer flows never asked; YAGNI — the boundary is pinned instead).
- Octopus (3+ parent) merge-specific output shaping: `-m` already diffs against every parent; covered by the same contract, no special casing.
- Dedup of paths appearing in multiple parent diffs: kept raw to preserve git `-m` semantics (documented in the help text).
- `--cc`/combined-diff modes: rejected in the #268 evidence note (they omit clean merges entirely).

## Convergence record (context for implementers)

PR #345 (`3a98555` → `3ffe99c` → `d672e96`) pinned the then-current silence as a documented, test-enforced contract: caveat text, NOTE, equivalents comment, and 4 test pins. This plan flips that map atomically in Task 2 — the suite must be green before AND after; the flips are the proof the map worked.
