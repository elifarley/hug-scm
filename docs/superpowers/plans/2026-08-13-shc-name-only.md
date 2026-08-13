# hug shc --name-only Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `-n, --name-only` to `hug shc`, printing repo-relative changed-file paths (one per line, exit 0 on empty), backed by a new library function.

**Architecture:** One new library function `show_changed_file_names()` in `git-config/lib/hug-git-show` (the show-family module `git-shc` already sources). The `git-shc` script gains a `git-wtl`-style reject-loop that peels `-n`/`--name-only` and loudly rejects unknown `-`-tokens (so `-nq`/`-qn` fail rather than silently run stats mode). The `--name-only` output branch calls the new function; the existing `--stat` path is unchanged except for an `is_range()` D.R.Y. consolidation.

**Tech Stack:** Bash, BATS (test framework), GNU getopt (shared flag parsing). The codebase rule "scripts stay thin, work in lib/" governs placement.

**Spec:** `docs/superpowers/specs/2026-08-13-shc-name-only-design.md`

**Companion issues:** [elifarley/hug-scm#266](https://github.com/elifarley/hug-scm/issues/266) (this feature), [#268](https://github.com/elifarley/hug-scm/issues/268) (merge-commit bug, out of scope), [#269](https://github.com/elifarley/hug-scm/issues/269) (convention alignment, out of scope).

**Test fixture note:** `create_test_repo_with_history` (from `tests/test_helper.bash`) produces: base commit adding `README.md`, then a commit adding `feature1.txt`, then a commit adding `feature2.txt`. So `HEAD` touches only `feature2.txt`; range `HEAD~2..HEAD` touches `feature1.txt` and `feature2.txt`; root commit (`HEAD~2`) touches `README.md`.

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `git-config/lib/hug-git-show` | Modify (add function after `show_single_commit`, ~line 148) | New `show_changed_file_names()` — owns range-vs-single dispatch + pathspec + exit-0 contract |
| `git-config/bin/git-shc` | Modify (flag-parsing section ~line 109-128, output branch ~line 145) | `-n/--name-only` flag via `wtl`-style reject-loop; output branch; `is_range()` consolidation; help text |
| `tests/lib/test_hug_git_show.bats` | Modify (append tests) | Library-function tests for `show_changed_file_names` |
| `tests/unit/test_sh.bats` | Modify (append tests in the `shc` section) | Script-level tests for the `-n` flag incl. bundled-flag rejection |
| `README.md`, `docs/commands/head.md`, `docs/cookbook.md`, `docs/meta/hug-completion-reference.md`, `docs/skills/hug-repo-analysis/guides/bug-hunting.md`, `docs/skills/hug-repo-analysis/guides/pre-commit-review.md`, `docs/skills/hug-repo-analysis/SKILL.md` | Modify | Document `-n` on the `shc` command surface |

---

## Task 1: Add `show_changed_file_names()` library function with tests

**Goal:** Add the `show_changed_file_names()` function to `hug-git-show` and cover it with library tests for single commit, range, root commit, pathspec filtering, and the exit-0-on-empty contract.

**Files:**
- Modify: `git-config/lib/hug-git-show` (insert after `show_single_commit`, before the `_show_commit_standard` comment block around line 148)
- Test: `tests/lib/test_hug_git_show.bats` (append in a new `# show_changed_file_names TESTS` section)

**Acceptance Criteria:**
- [ ] `show_changed_file_names "HEAD"` prints repo-relative paths (e.g. `feature2.txt`), one per line, exit 0
- [ ] `show_changed_file_names "HEAD~2..HEAD"` prints cumulative paths across the range, exit 0
- [ ] `show_changed_file_names "<root-sha>"` lists the root-commit file (`README.md`) via `--root`
- [ ] `show_changed_file_names "HEAD" "*.nomatch"` (pathspec that hits nothing) prints empty stdout, **exit 0**
- [ ] The function does NOT read `HUG_QUIET` and emits no header (pure data)

**Verify:** `make test-lib TEST_FILE=test_hug_git_show.bats TEST_FILTER="show_changed_file_names" TEST_SHOW_ALL_RESULTS=1` → all new tests PASS

**Steps:**

- [ ] **Step 1: Write the failing library tests**

Append to `tests/lib/test_hug_git_show.bats`, after the existing `resolve_commit_ref`/`show_*` tests (before EOF):

```bash
################################################################################
# show_changed_file_names TESTS
################################################################################

@test "show_changed_file_names: single commit prints repo-relative paths" {
  run show_changed_file_names "HEAD"
  assert_success
  assert_output "feature2.txt"
}

@test "show_changed_file_names: range prints cumulative paths" {
  run show_changed_file_names "HEAD~2..HEAD"
  assert_success
  # Cumulative across feature1 + feature2 commits (README is the base, excluded by range)
  assert_line "feature1.txt"
  assert_line "feature2.txt"
}

@test "show_changed_file_names: root commit lists files via --root" {
  local root_sha
  root_sha=$(git rev-list --max-parents=0 HEAD)
  run show_changed_file_names "$root_sha"
  assert_success
  assert_output "README.md"
}

@test "show_changed_file_names: pathspec filters output" {
  run show_changed_file_names "HEAD~2..HEAD" "feature1.txt"
  assert_success
  assert_output "feature1.txt"
}

@test "show_changed_file_names: no-match pathspec exits 0 with empty stdout" {
  run show_changed_file_names "HEAD" "*.nomatch"
  assert_success
  assert_output ""
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test-lib TEST_FILE=test_hug_git_show.bats TEST_FILTER="show_changed_file_names"`
Expected: FAIL — `show_changed_file_names: command not found` (function not yet defined)

- [ ] **Step 3: Add the function to `hug-git-show`**

Insert this block in `git-config/lib/hug-git-show`, immediately after the closing `}` of `show_single_commit()` (around line 148, before the `# Shows a single commit in standard human-readable format` comment):

```bash

# Prints the repo-relative paths of files changed in a commit or range, one per
# line — the --name-only equivalent of git-shc's --stat output.
#
# Usage: show_changed_file_names "commit_or_range" [pathspec...]
# Parameters:
#   $1   - Commit ref, range, or N/-N form (resolved internally via
#          resolve_commit_ref, so the function is independently testable without
#          the script wrapper).
#   $2.. - Optional pathspecs (already-exploded args, passed as-is).
# Output:
#   Repo-relative file paths to stdout, one per line. Empty on no matches.
# Exit codes:
#   0 always (zero matches → empty stdout — caller detects emptiness via stdout).
# Environment:
#   None read; does NOT honor HUG_QUIET (output is pure data — no header by design).
# Notes:
#   - Mirrors git-shc's dispatch EXACTLY: is_range → git diff --name-only,
#     else git diff-tree --no-commit-id --name-only -r --root.
#   - Merge-commit single-commit shows nothing (same as --stat) — known parity,
#     see elifarley/hug-scm#268 for the pre-existing bug this preserves.
#   - Bundled-flag handling lives in the git-shc script wrapper, NOT here.
show_changed_file_names() {
    local target="${1:-HEAD}"
    shift || true
    local -a path_args=()
    [[ $# -gt 0 ]] && path_args=(-- "$@")

    local resolved
    resolved=$(resolve_commit_ref "$target" "HEAD")

    if is_range "$resolved"; then
        git diff --name-only "$resolved" "${path_args[@]+"${path_args[@]}"}"
    else
        git diff-tree --no-commit-id --name-only -r --root "$resolved" "${path_args[@]+"${path_args[@]}"}"
    fi
}
```

Note: the local array is named `path_args` (not `pathspec_args`) to avoid the visual collision with the script-scope `pathspec_args` flagged in the roast review — both are correctly scoped (`local` here), but the distinct name aids skimmability.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test-lib TEST_FILE=test_hug_git_show.bats TEST_FILTER="show_changed_file_names" TEST_SHOW_ALL_RESULTS=1`
Expected: PASS — all 5 new tests green

- [ ] **Step 5: Commit**

```bash
git add git-config/lib/hug-git-show tests/lib/test_hug_git_show.bats
git commit -m "feat(shc): add show_changed_file_names() library function"
```

---

## Task 2: Wire `-n/--name-only` into `git-shc` with the `wtl` reject-loop

**Goal:** Add `-n/--name-only` flag parsing to `git-shc` using the proven `git-wtl` reject-loop pattern (parse_pathspecs → parse_common_flags → own while-loop with `-*` → `reject_flag_ref`), and add the `--name-only` output branch. Also consolidate the inline `*..*` check to `is_range()`.

**Files:**
- Modify: `git-config/bin/git-shc` (flag-parsing block ~lines 109-128; output section ~lines 145-172)
- Test: `tests/unit/test_sh.bats` (append in the `hug shc tests` section)

**Acceptance Criteria:**
- [ ] `hug shc -n HEAD` and `hug shc --name-only HEAD` print paths only (e.g. `feature2.txt`), no header on stdout, no `.../` elision
- [ ] `hug shc -n main..HEAD` (range form) prints cumulative paths
- [ ] `hug shc -n -3` and `hug shc -n HEAD~2` work (N/-N forms)
- [ ] `hug shc -n HEAD~1..HEAD -- 'feature*.txt'` filters by pathspec in name-only mode
- [ ] `hug shc -n HEAD -- '*.nomatch'` exits 0 with empty stdout, no stderr hint
- [ ] `hug shc -nq HEAD` and `hug shc -qn HEAD` are REJECTED (exit 2, help shown) — NOT silently run in stats mode
- [ ] `hug shc --stat` is still rejected with help + exit 2 (existing regression guard stays green)
- [ ] stdout/stderr discipline: `hug shc -n HEAD 2>/dev/null` leaves data intact; `hug shc -n HEAD 2>&1 1>/dev/null` shows nothing human-facing leaked to stdout
- [ ] The default `--stat` mode is unchanged (existing `hug shc` tests still pass)

**Verify:** `make test-unit TEST_FILE=test_sh.bats TEST_FILTER="shc" TEST_SHOW_ALL_RESULTS=1` → all shc tests (existing + new) PASS

**Steps:**

- [ ] **Step 1: Write the failing script tests**

Append to `tests/unit/test_sh.bats` in the `hug shc tests` section (after the existing `hug shc: shows help with -h` test):

```bash
@test "hug shc -n: prints repo-relative paths only for single commit" {
  run hug shc -n HEAD
  assert_success
  assert_output "feature2.txt"
}

@test "hug shc --name-only: long flag works identically" {
  run hug shc --name-only HEAD
  assert_success
  assert_output "feature2.txt"
}

@test "hug shc -n: range prints cumulative paths" {
  run hug shc -n HEAD~2..HEAD
  assert_success
  assert_line "feature1.txt"
  assert_line "feature2.txt"
}

@test "hug shc -n: N/-N forms work" {
  run hug shc -n -3
  assert_success
  # HEAD~3..HEAD range in the 3-commit fixture
  assert_line "README.md"
  assert_line "feature1.txt"
  assert_line "feature2.txt"
  run hug shc -n HEAD~2
  assert_success
  assert_output "feature1.txt"
}

@test "hug shc -n: pathspec filtering works" {
  run hug shc -n HEAD~1..HEAD -- 'feature1.txt'
  assert_success
  assert_output "feature1.txt"
}

@test "hug shc -n: no-match pathspec exits 0 with empty stdout, no stderr hint" {
  run hug shc -n HEAD -- '*.nomatch'
  assert_success
  assert_output ""
  refute_output --partial "No files matching"
}

@test "hug shc -n: bundled -nq is rejected, not silently run in stats mode" {
  run hug shc -nq HEAD
  assert_failure
  assert_output --partial "USAGE:"
  run hug shc -qn HEAD
  assert_failure
  assert_output --partial "USAGE:"
}

@test "hug shc -n: stdout is data-only, no human chatter" {
  run hug shc -n HEAD
  assert_success
  # No header emoji/legend on stdout — pure data
  refute_output --partial "Changed files"
  refute_output --partial "📊"
}

@test "hug shc -n: regression -- still rejects --stat with help" {
  run hug shc --stat
  assert_failure
  assert_output --partial "hug shc"
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test-unit TEST_FILE=test_sh.bats TEST_FILTER="shc -n"`
Expected: FAIL — `hug shc -n` not recognized; output is stats-mode (the `-n: prints repo-relative paths` and bundled-rejection tests fail)

- [ ] **Step 3: Replace the flag-parsing block in `git-shc`**

In `git-config/bin/git-shc`, find the existing flag-parsing block (currently lines ~109-128):

```bash
# Pre-parse pathspecs BEFORE parse_common_flags, which intercepts
# trailing -- for interactive file selection.
eval "$(parse_pathspecs "$@")"
eval "$(parse_common_flags "${_pathspec_pre_args[@]}")"

# Extract commit_ref from pre_args (NOT from original "$@")
commit_ref=""
for arg in "${_pathspec_pre_args[@]}"; do
  case "$arg" in
  -h | --help | -q | --quiet) ;; # Already handled by parse_common_flags
  *)
    commit_ref="$arg"
    ;;
  esac
done
```

Replace it with the `wtl`-style reject-loop (keeping `parse_pathspecs` first — `shc` accepts `-- <pathspec>`, so `parse_pathspecs` must protect `--` from `parse_common_flags`):

```bash
# Pre-parse pathspecs BEFORE parse_common_flags, which intercepts
# trailing -- for interactive file selection.
eval "$(parse_pathspecs "$@")"
eval "$(parse_common_flags "${_pathspec_pre_args[@]}")"

# Extract commit_ref and the -n/--name-only flag from pre_args.
# git-wtl-style reject-loop: any unrecognized -token is rejected loud via
# reject_flag_ref (which lets valid -N range shorthands through). Without this,
# the old last-wins extraction silently swallowed unknown tokens like -nq and
# the command ran in --stat mode. See the spec's "Bundled-flag hazard" section.
name_only=false
commit_ref=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  -n | --name-only)
    name_only=true
    shift
    ;;
  -*)
    # Any other -token: reject. reject_flag_ref allows -N (e.g. -3 → HEAD~3..HEAD)
    # and rejects everything else (-nq, -qn, --foo) with help + exit 2.
    reject_flag_ref "$1" && {
      commit_ref="$1"
      shift
    }
    ;;
  *)
    commit_ref="$1"
    shift
    ;;
  esac
done
```

Note: `$@` here is the post-`parse_common_flags` remainder (the shared flags `-q`/`-h`/etc. have already been consumed). `--` is absent because `parse_pathspecs` split it into `_pathspec_pathspecs` at the top.

- [ ] **Step 4: Add the `--name-only` output branch and the `is_range()` consolidation**

In `git-config/bin/git-shc`, find the dispatch block (currently lines ~145-172, starting `stats_output=""`). The `--name-only` branch goes immediately after `commit_ref=$(resolve_commit_ref "$commit_ref" "HEAD")` and before `stats_output=""`. Also change the inline `*..*` check to `is_range()`.

Insert this branch right after the `commit_ref=$(resolve_commit_ref ...)` line:

```bash
# --name-only mode: print repo-relative paths only, no stats/header.
# Pure data output (no HUG_QUIET coupling, no no-match hint) by design —
# callers detect empty via stdout. See spec "No-match hint" section.
if $name_only; then
  show_changed_file_names "$commit_ref" "${_pathspec_pathspecs[@]+"${_pathspec_pathspecs[@]}"}"
  exit 0
fi
```

Then, in the `--stat` dispatch below it, change the range check (do not change anything else in the stats path):

```diff
-stats_output=""
-if [[ "$commit_ref" == *..* ]]; then
+stats_output=""
+if is_range "$commit_ref"; then
```

- [ ] **Step 5: Update the `show_help` function in `git-shc`**

In the `OPTIONS:` block of `show_help` (currently around lines 27-30), add the `-n` entry after `-q, --quiet`:

```
    -n, --name-only Print ONLY changed file paths (repo-relative), one per line.
                    No stats, no header on stdout, no elision. Exit 0 even on
                    zero matches (detect via empty stdout). Machine-parseable.
```

In the `CAPTURING OUTPUT:` section (around line 65-69), add:

```
    hug shc -n main..HEAD            # Paths only (repo-relative, pipe-safe)
    files=$(hug shc -n -3)           # Capture changed-file list to a variable
    hug shc -n main..HEAD -- '*.py'  # Paths only, filtered to Python files
```

In the `GIT EQUIVALENTS:` section (around line 91-95), add:

```
    git diff --name-only main..HEAD  →  hug shc -n main..HEAD
    git diff-tree --no-commit-id --name-only -r --root HEAD  →  hug shc -n HEAD
```

And add a note line after the GIT EQUIVALENTS additions:

```
    # The full diff-tree invocation (--no-commit-id -r --root) is what hug uses
    # internally; dropping those flags would prepend the commit hash and break
    # the one-path-per-line contract.
```

- [ ] **Step 6: Run the new + existing shc tests to verify all pass**

Run: `make test-unit TEST_FILE=test_sh.bats TEST_FILTER="shc" TEST_SHOW_ALL_RESULTS=1`
Expected: PASS — all existing shc tests AND all new `-n`/bundled-rejection tests green

- [ ] **Step 7: Run the full unit suite to confirm no regressions**

Run: `make test-unit`
Expected: PASS — no existing test broken by the flag-loop restructure or `is_range()` consolidation

- [ ] **Step 8: Commit**

```bash
git add git-config/bin/git-shc tests/unit/test_sh.bats
git commit -m "feat(shc): add -n/--name-only flag with wtl-style reject-loop"
```

---

## Task 3: Document `-n` on the `shc` command surface (7 sibling docs)

**Goal:** Update every file that documents the `shc` command surface to mention `-n/--name-only`, so the new flag isn't invisible after the feature ships.

**Files:**
- Modify: `README.md:546`
- Modify: `docs/commands/head.md:215`
- Modify: `docs/cookbook.md:191`
- Modify: `docs/meta/hug-completion-reference.md:105`
- Modify: `docs/skills/hug-repo-analysis/guides/bug-hunting.md:104`
- Modify: `docs/skills/hug-repo-analysis/guides/pre-commit-review.md:310`
- Modify: `docs/skills/hug-repo-analysis/SKILL.md:113,287`

**Acceptance Criteria:**
- [ ] Each of the 7 files mentions `-n` or `--name-only` in connection with `shc`
- [ ] `README.md` command signature reflects the new flag
- [ ] `docs/meta/hug-completion-reference.md` (the canonical flag listing) includes `-n`
- [ ] No doc claims behavior that contradicts the implementation (exit 0 on empty, repo-relative paths)

**Verify:** `grep -rn "hug shc\b\|shc <" README.md docs/ | grep -v "superpowers/"` → every hit line's surrounding context mentions `-n` OR is a pure example that needs no flag annotation. Plus `make docs-build` succeeds.

**Steps:**

- [ ] **Step 1: `README.md:546`** — extend the command signature

Current:
```
hug shc [N|commit|range] [-- <path>...] # SHow: Changed files (cumulative stats, optionally filtered by path)
```
Change to:
```
hug shc [N|commit|range] [-n] [-- <path>...] # SHow: Changed files (cumulative stats, or -n for paths only)
```

- [ ] **Step 2: `docs/commands/head.md:215`** — add a `-n` example near the existing `hug shc HEAD~3..HEAD` line

After the existing line:
```
- Preview cumulative file changes before squashing: `hug shc HEAD~3..HEAD` shows all files that would be affected by squashing the last 3 commits.
```
Add:
```
- List just the affected file paths (scriptable, repo-relative): `hug shc -n HEAD~3..HEAD`.
```

- [ ] **Step 3: `docs/cookbook.md:191`** — add a `-n` example alongside the existing `hug shc abc1234`

After the existing line, add:
```
    hug shc -n abc1234        # same, but paths only (repo-relative, pipe-safe)
```

- [ ] **Step 4: `docs/meta/hug-completion-reference.md:105`** — add `-n` to the args description

Current:
```
- `shc <commit>`: Files changed in commit. Args: `<commit>` (required), `[-- <path>...]` (optional pathspecs).
```
Change to:
```
- `shc <commit>`: Files changed in commit. Args: `<commit>` (required), `[-n|--name-only]` (optional: paths only, one per line), `[-- <path>...]` (optional pathspecs).
```

- [ ] **Step 5: `docs/skills/hug-repo-analysis/guides/bug-hunting.md:104`** — note `-n`

After the existing `hug shc <commit-hash>` line, add a line noting the scriptable form:
```
hug shc -n <commit-hash>      # paths only, for piping into other tools
```

- [ ] **Step 6: `docs/skills/hug-repo-analysis/guides/pre-commit-review.md:310`** — note `-n`

After the existing `hug shc HEAD` line, add:
```
hug shc -n HEAD               # paths only — scriptable pre-commit file list
```

- [ ] **Step 7: `docs/skills/hug-repo-analysis/SKILL.md:113,287`** — note `-n` at both recipe sites

After the `hug shc a1b2c3d` line (113) and the `hug shc <commit-hash>        # files changed` line (287), add the `-n` variant as a comment or sibling line:
```
hug shc -n <commit-hash>      # files changed, paths only (pipe-safe)
```

- [ ] **Step 8: Verify docs build and grep coverage**

Run: `make docs-build`
Expected: build succeeds (no broken VitePress syntax)

Run: `grep -rn "hug shc\b" README.md docs/ | grep -v superpowers`
Expected: every hit is either annotated with `-n` or is a pure example unchanged intentionally.

- [ ] **Step 9: Commit**

```bash
git add README.md docs/
git commit -m "docs(shc): document -n/--name-only across the shc command surface"
```

---

## Task 4: Full suite verification + sanitize

**Goal:** Confirm the whole test suite passes and the code passes the project's sanitize gate (format/lint/typecheck), then close the loop on the spec's acceptance criteria.

**Files:** None (verification only)

**Acceptance Criteria:**
- [ ] `make test` passes (all BATS + pytest)
- [ ] `make sanitize` passes (no format/lint/typecheck errors)
- [ ] The issue #266 acceptance criteria are demonstrably met (see verify commands)
- [ ] Companion issues #268/#269 are NOT touched (out of scope confirmed)

**Verify:**
- `make test` → exit 0, "All tests passed"
- `make sanitize` → no errors
- Issue AC spot-check: `hug shc main..HEAD --name-only | wc -l` equals the file count from `hug shc main..HEAD`

**Steps:**

- [ ] **Step 1: Run the full test suite**

Run: `make test`
Expected: exit 0, summary shows all BATS + pytest green

- [ ] **Step 2: Run the sanitize gate**

Run: `make sanitize`
Expected: no errors (this also runs automatically on stop, but run it explicitly so subagent-committed code is confirmed green before push — per engineering-conventions)

- [ ] **Step 3: Demonstrate the issue #266 acceptance criteria**

In a test repo with multi-file changes on a branch:
```bash
# AC: --name-only prints full repo-relative paths, one per line, pipe-safe
hug shc main..HEAD --name-only
# AC: pipe test — line count equals file count
test "$(hug shc main..HEAD --name-only | wc -l)" -eq "$(hug shc main..HEAD --name-only | sort -u | wc -l)"
echo "AC pipe test passed: $?"
# AC: works for single commit, ranges, -N
hug shc HEAD --name-only
hug shc -3 --name-only
```
Expected: paths print cleanly; pipe test exits 0; all three forms produce output.

- [ ] **Step 4: Confirm scope boundary (no #268/#269 changes)**

Run: `git diff --name-only main...HEAD`
Expected: only `git-config/lib/hug-git-show`, `git-config/bin/git-shc`, the two test files, and the 7 doc files. No changes to `git-wtl`, `git-shcp`, or any merge-commit logic.

- [ ] **Step 5: No commit (verification-only task)**

This task produces no code change. If steps 1-4 all pass, the feature is complete and ready for the PR.
