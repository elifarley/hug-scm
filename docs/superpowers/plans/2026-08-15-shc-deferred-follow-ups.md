# shc Deferred Follow-ups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close issue [elifarley/hug-scm#274](https://github.com/elifarley/hug-scm/issues/274) — `shc -z` NUL mode, branded unborn-HEAD error, second-positional rejection, and one canonical `pinned_diff()` replacing the triplicated diff-tree invocation.

**Architecture:** One new plumbing function `pinned_diff()` in `git-config/lib/hug-git-diff` owns the determinism pins (`core.quotePath=false`, `diff.relative=false`, rename stance, `--ignore-submodules=none`) and the range/single dispatch. Three existing call sites become thin wrappers. The rename axis is an explicit two-valued contract: display callers pin `--find-renames` (collapsed), the action-list caller pins `--no-renames` (both sides — `hug a --from-commit` & co. keep byte-identical behavior).

**Tech Stack:** Bash (GNU getopt conventions, `set -euo pipefail`), BATS test framework, git 2.34+ (declared floor; all pins/guards probe-verified on 2.34.1 — receipts in the spec).

**Spec:** `docs/superpowers/specs/2026-08-14-shc-deferred-follow-ups-z-null-output-unborn-head-positionals-diff-tree-dry-design.md` (4 roast rounds, implementation-ready). Read it before starting; every behavior contract, probe receipt, and registered delta lives there.

**Pre-flight (already done, do not repeat):** all 9 probe items in the spec were executed on git 2.34.1 with receipts baked into the spec. CI's git gets its re-confirmation for free: the Task 1/3 tests assert the same bytes CI executes.

**Test commands (always via make, never direct bats):**
- `make test-lib TEST_FILE=test_hug_git_diff.bats`
- `make test-lib TEST_FILE=test_hug-file-input.bats`
- `make test-lib TEST_FILE=test_hug_git_show.bats`
- `make test-unit TEST_FILE=test_sh.bats`
- Final gate: `make pre-commit`

**NUL-testing discipline (mandatory):** BATS `run` strips NUL bytes — any `-z` assertion MUST go through a pipe (`hug shc -n -z HEAD | od -An -c`), never through `$output`. Same class as the `sl*` NUL work ([elifarley/hug-scm#249](https://github.com/elifarley/hug-scm/issues/249)).

**Commit convention:** stage with `hug a <files>`, commit with `hug c -F - <<'EOF' … EOF` (WHY/WHAT/HOW/IMPACT body). Three commits total, one per task, each independently green — matching the spec's Deliverables.

---

### Task 1: `pinned_diff()` plumbing + its test file

**Goal:** Add the canonical pinned changed-files invocation to `hug-git-diff` with its complete BATS suite — pure addition, no caller changes.

**Files:**
- Modify: `git-config/lib/hug-git-diff` (append `pinned_diff` after `_diff_invoke_combined`, line ~576)
- Create: `tests/lib/test_hug_git_diff.bats`

**Acceptance Criteria:**
- [ ] `pinned_diff` dispatches `is_range` → `git diff`, else `git diff-tree --no-commit-id -r --root`
- [ ] Leading flags `--null` and `--no-renames` parsed before positionals
- [ ] Arg-count guard (`< 2` core args), unknown-format guard, `--null`+`--stat` guard → all `error_usage` exit 2
- [ ] Pins defeat hostile config: `core.quotePath=true`, `diff.renames=false`, `diff.relative=true`, `diff.ignoreSubmodules=all`
- [ ] `--no-renames` lists BOTH rename sides and overrides `diff.renames=true` on the range branch
- [ ] Bad ref propagates exit 128 (nothing swallowed inside `pinned_diff`)
- [ ] All new tests pass; full lib suite green

**Verify:** `make test-lib TEST_FILE=test_hug_git_diff.bats` → `✓ All tests passed!`

**Steps:**

- [ ] **Step 1: Write the failing test file** `tests/lib/test_hug_git_diff.bats`:

```bats
#!/usr/bin/env bats
# Tests for pinned_diff() in git-config/lib/hug-git-diff — the canonical
# pinned changed-files invocation (spec: 2026-08-14-shc-deferred-follow-ups).

load '../test_helper'
load '../../git-config/lib/hug-common'
load '../../git-config/lib/hug-git-repo' # is_range — hug-common does NOT load it

setup() {
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

# Fixture: c1 adds plain.txt + café.txt; c2 renames plain.txt → renamed.txt
# and appends to café.txt. Non-ASCII AND structural chars where quoting matters.
_make_fixture() {
  echo a > plain.txt
  echo a > 'café.txt'
  echo a > 'back\slash.txt'
  git add -A && git commit -qm c1
  git mv plain.txt renamed.txt
  echo b >> 'café.txt'
  git add -A && git commit -qm c2
}

@test "pinned_diff: single commit dispatches to diff-tree (no commit id line)" {
  _make_fixture
  run pinned_diff --name-only HEAD
  assert_success
  refute_line --partial "$(git rev-parse HEAD)"   # --no-commit-id honored
  assert_line "renamed.txt"                        # display contract: new path only
}

@test "pinned_diff: range dispatches to git diff" {
  _make_fixture
  run pinned_diff --name-only 'HEAD~1..HEAD'
  assert_success
  assert_line "renamed.txt"
  assert_line "café.txt"
}

@test "pinned_diff: --stat is accepted for both branches" {
  _make_fixture
  run pinned_diff --stat HEAD
  assert_success
  assert_output --partial 'renamed.txt'
  run pinned_diff --stat 'HEAD~1..HEAD'
  assert_success
  assert_output --partial 'changed'
}

@test "pinned_diff: --null emits NUL-terminated raw paths (pipe assertion, never \$output)" {
  _make_fixture
  # od -c renders non-ASCII bytes as octal escapes (é → 303 251) and NUL as \0;
  # emission order is tree order (café.txt before renamed.txt). Full-stream
  # equality pins order, NUL termination, no trailing newline, and rawness —
  # C-quoted output would render as "caf\303\251.txt" (visible backslashes),
  # a different string. Fixtures here avoid od's `*` line-dedup (streams
  # under 16 bytes/line or with distinct lines only).
  [[ "$(pinned_diff --null --name-only HEAD | od -An -c | tr -d ' \n')" == 'caf303251.txt\0renamed.txt\0' ]]
}

@test "pinned_diff: --null with --stat is rejected (exit 2)" {
  _make_fixture
  run pinned_diff --null --stat HEAD
  assert_failure 2
  assert_output --partial '--null is only valid with --name-only'
}

@test "pinned_diff: unknown format is rejected (exit 2)" {
  _make_fixture
  run pinned_diff --patch HEAD
  assert_failure 2
  assert_output --partial 'unknown format'
}

@test "pinned_diff: too few core args is rejected (exit 2, not a bash unbound trace)" {
  _make_fixture
  run pinned_diff --name-only
  assert_failure 2
  assert_output --partial 'expected'
}

@test "pinned_diff: quotePath pin defeats hostile core.quotePath=true (non-ASCII raw)" {
  _make_fixture
  git config core.quotePath true
  run pinned_diff --name-only HEAD
  assert_success
  assert_line 'café.txt'                    # raw, NOT "caf\303\251.txt"
  refute_output --partial 'caf\303\251'
}

@test "pinned_diff: structural chars stay C-quoted in line mode regardless of pin" {
  _make_fixture
  run pinned_diff --name-only 'HEAD~1'
  assert_success
  assert_line '"back\\slash.txt"'           # git quotes structural chars unconditionally
}

@test "pinned_diff: --stat non-ASCII flips raw (registered delta, both branches)" {
  _make_fixture
  run pinned_diff --stat HEAD
  assert_success
  assert_output --partial 'café.txt | 2'    # raw, not "caf\303\251.txt | 2"
  run pinned_diff --stat 'HEAD~1..HEAD'
  assert_output --partial 'café.txt | 2'
}

@test "pinned_diff: rename stance — default collapses, --no-renames expands both sides" {
  _make_fixture
  run pinned_diff --no-renames --name-only HEAD
  assert_success
  assert_line 'plain.txt'                   # deleted side back in the list
  assert_line 'renamed.txt'
}

@test "pinned_diff: --no-renames overrides hostile diff.renames=true on the range branch" {
  _make_fixture
  git config diff.renames true
  run pinned_diff --no-renames --name-only 'HEAD~1..HEAD'
  assert_success
  assert_line 'plain.txt'
  assert_line 'renamed.txt'
}

@test "pinned_diff: rename collapse is forced on the single branch under hostile diff.renames=false" {
  _make_fixture
  git config diff.renames false
  run pinned_diff --stat HEAD
  assert_success
  assert_output --partial 'plain.txt => renamed.txt'
}

@test "pinned_diff: paths stay repo-relative under hostile diff.relative=true" {
  _make_fixture
  mkdir -p sub && echo x > sub/deep.txt && git add -A && git commit -qm c3
  git config diff.relative true
  cd sub
  run pinned_diff --name-only HEAD
  assert_success
  assert_line 'sub/deep.txt'                # repo-relative, not deep.txt
}

@test "pinned_diff: submodule pin defeats hostile diff.ignoreSubmodules=all" {
  local child="$BATS_TEST_TMPDIR/child-$$"
  git init -q "$child"
  ( cd "$child" \
    && git config user.email t@t.tld && git config user.name t \
    && echo x > sub.txt && git add -A && git commit -qm subinit )
  git -c protocol.file.allow=always submodule add -q "$child" sub
  git commit -qm addsub
  git config diff.ignoreSubmodules all
  run pinned_diff --name-only HEAD
  assert_success
  assert_line 'sub'                         # shown despite hostile config
}

@test "pinned_diff: pathspec passthrough filters output" {
  _make_fixture
  run pinned_diff --name-only HEAD -- 'renamed.txt'
  assert_success
  assert_line 'renamed.txt'
  refute_line 'café.txt'
}

@test "pinned_diff: bad ref propagates git exit 128 + fatal (nothing swallowed)" {
  _make_fixture
  run pinned_diff --name-only no-such-ref
  assert_failure 128
  assert_output --partial 'fatal'
}
```

- [ ] **Step 2: Run to verify it fails** — `make test-lib TEST_FILE=test_hug_git_diff.bats` → every test fails with `pinned_diff: command not found` (exit 127).

- [ ] **Step 3: Implement `pinned_diff`** — append to `git-config/lib/hug-git-diff`, after `_diff_invoke_combined()` (keep the existing load-guard at the top of the file untouched):

```bash
################################################################################
# pinned_diff — the canonical pinned changed-files invocation
################################################################################

# Runs the canonical pinned changed-files invocation for a commit or range.
# Usage: pinned_diff [--null] [--no-renames] <format> <resolved_ref> [pathspec...]
# Parameters:
#   --null       - Optional leading flag: NUL-separated output (--name-only only).
#   --no-renames - Optional leading flag: renames list BOTH sides — the ACTION-LIST
#                  contract (staging/untrack lists need the deleted side). Default is
#                  the DISPLAY contract (--find-renames: new path only / collapsed
#                  `{old => new}` stat line). Both stances are explicit and
#                  config-immune — neither depends on the user's diff.renames.
#   $1       - Format: --name-only | --stat. Anything else is a caller bug.
#   $2       - resolved_ref: an ALREADY-RESOLVED commit ref or range (anything
#              is_range() recognizes). N/-N shorthand resolution is the CALLER's
#              job (resolve_commit_ref) — this function does not call it, keeping
#              pinned_diff a thin, independently testable plumbing layer. Named
#              resolved_ref, not "target", so it cannot be confused with the raw
#              user input that show_changed_file_names accepts.
#   $3..     - Optional pathspecs (already-exploded args, passed as-is).
# Output:
#   Git's own --name-only / --stat stream on stdout. Rename stance per the flags
#   above (one path per rename by default; two with --no-renames). With --null,
#   paths are NUL-terminated and never C-quoted (git's -z semantics — output must
#   NEVER be captured into a shell variable; bash strips NUL bytes).
# Exit codes:
#   2    - usage errors this function rejects itself: too few core args,
#          unknown format, --null with --stat (all via error_usage).
#   Else - the underlying git command's (0 on success; 128 + git's fatal on
#          a bad ref). Nothing is swallowed here; callers own error policy
#          (2>/dev/null, || true, branding).
# Environment:
#   None read; does NOT honor HUG_QUIET (pure data by design).
# Pins (every invocation, immune to user/server config — the determinism
# contract from the shc --name-only adversarial review, now protecting ALL
# call sites instead of one of three):
#   -c core.quotePath=false        non-ASCII bytes (> 0x7f) print raw, in BOTH
#                                  --name-only and --stat output. Git STILL C-quotes
#                                  structural chars (newline, backslash, quote, tab)
#                                  in line-oriented output regardless of this config —
#                                  -z is the only fully-raw stream (probe-verified,
#                                  git 2.34.1)
#   -c diff.relative=false         paths stay repo-relative
#   --find-renames / --no-renames  the rename CONTRACT, pinned explicitly in both
#                                  directions (see Parameters above)
#   --ignore-submodules=none       defeats a user's diff.ignoreSubmodules
# Notes:
#   - Dispatch: is_range <resolved_ref> → `git diff <format> <pins> <resolved_ref>`;
#     else → `git diff-tree --no-commit-id <format> -r --root <pins> <resolved_ref>`.
#     (--no-commit-id is load-bearing under -z: without it the commit hash is
#     emitted as the first NUL entry.)
#   - --null with --stat is rejected via error_usage (NUL is a --name-only
#     contract; --stat is human-formatted).
#   - Merge-commit single-commit shows nothing (diff-tree without -m) — known
#     parity with the stats mode, see elifarley/hug-scm#268.
pinned_diff() {
    local null_mode=false no_renames=false
    [[ "${1:-}" == "--null" ]] && { null_mode=true; shift; }
    [[ "${1:-}" == "--no-renames" ]] && { no_renames=true; shift; }
    # Arg-count guard BEFORE any positional read: under set -u, touching $1/$2 with
    # too few args dies as "unbound variable" (exit 1) — a caller bug must surface
    # as error_usage (exit 2), not a raw bash trace.
    if [[ $# -lt 2 ]]; then
        error_usage "pinned_diff: expected [--null] [--no-renames] <format> <resolved_ref> [pathspec...]"
    fi
    local format="$1" resolved_ref="$2"
    shift 2
    local -a path_args=()
    [[ $# -gt 0 ]] && path_args=(-- "$@")
    local -a zflag=()
    $null_mode && zflag=(-z)
    # Rename stance is a never-empty scalar, so plain "$rename_flag" is set -u-safe
    # without the + guard the possibly-empty arrays need. Explicit BOTH ways — the
    # invocation never inherits the user's diff.renames config.
    local rename_flag=--find-renames
    $no_renames && rename_flag=--no-renames

    if [[ "$format" != "--name-only" && "$format" != "--stat" ]]; then
        error_usage "pinned_diff: unknown format '$format' (expected --name-only or --stat)"
    fi
    if $null_mode && [[ "$format" != "--name-only" ]]; then
        error_usage "pinned_diff: --null is only valid with --name-only"
    fi

    if is_range "$resolved_ref"; then
        git -c core.quotePath=false -c diff.relative=false \
            diff "$format" "${zflag[@]+"${zflag[@]}"}" "$rename_flag" --ignore-submodules=none \
            "$resolved_ref" "${path_args[@]+"${path_args[@]}"}"
    else
        git -c core.quotePath=false -c diff.relative=false \
            diff-tree --no-commit-id "$format" -r --root "${zflag[@]+"${zflag[@]}"}" \
            "$rename_flag" --ignore-submodules=none \
            "$resolved_ref" "${path_args[@]+"${path_args[@]}"}"
    fi
}
```

- [ ] **Step 4: Run to verify green** — `make test-lib TEST_FILE=test_hug_git_diff.bats` → `✓ All tests passed!` (18 tests).

- [ ] **Step 5: Regression sweep** — `make test-lib` → all lib tests green (pure addition; nothing else calls `pinned_diff` yet).

- [ ] **Step 6: Commit (commit 1 of 3 — `feat(lib)`)**

```bash
hug a git-config/lib/hug-git-diff tests/lib/test_hug_git_diff.bats
hug c -F - <<'EOF'
feat(lib): add pinned_diff — the canonical pinned changed-files invocation

WHY: The diff-tree flag set for changed-file listing lives in three places
(git-shc stats path, show_changed_file_names, extract_files_from_commit), with
the determinism pins protecting only one of them — a future flag change silently
diverges the others (issue elifarley/hug-scm#274 item 4).

WHAT: pinned_diff() in hug-git-diff: one function owning the pins
(core.quotePath=false, diff.relative=false, --ignore-submodules=none), the
range/single dispatch, --null NUL mode, and an explicit two-valued rename
contract (--find-renames display / --no-renames action lists). Pure addition
with its full BATS suite (18 tests: dispatch, formats, guards, hostile-config
pins incl. relative + submodules, both rename stances, NUL via od pipe, bad-ref
exit 128). No caller changes in this commit.

HOW: Leading flags parsed before positionals; arg-count guard before any
positional read (set -u makes $2-unbound die as exit 1 — the guard converts
caller bugs to error_usage exit 2); never-empty rename_flag scalar (set -u-safe
without the + guard); guarded zflag/path_args expansions per house idiom.

IMPACT: Commits 2-3 adopt this at the three call sites. Pins verified on the
declared floor (git 2.34.1): non-ASCII flips raw in --name-only AND --stat on
both branches; structural chars stay C-quoted in line mode; -z is fully raw.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
```

---

### Task 2: Adopt `pinned_diff` at the three call sites

**Goal:** Convert `show_changed_file_names`, the git-shc stats path, and `extract_files_from_commit` to thin wrappers over `pinned_diff` — pins everywhere, rename contract per consumer, `hug a --from-commit` & co. keep byte-identical behavior.

**Files:**
- Modify: `git-config/lib/hug-git-show:146-199` (doc comment + `show_changed_file_names` body)
- Modify: `git-config/bin/git-shc:170-212` (`-n` dispatch, delete `pathspec_args` builder, collapse stats path)
- Modify: `git-config/lib/hug-file-input:128-143` (`extract_files_from_commit`)
- Modify: `tests/lib/test_hug-file-input.bats` (add `hug-git-repo` load + 2 tests)
- Modify: `tests/lib/test_hug_git_show.bats` (append 2 tests in the `show_changed_file_names TESTS` section, ~line 583+)
- Modify: `git-config/lib/README.md` (add `#### hug-git-diff` subsection after `#### hug-git-rebase`, ~line 150)

**Acceptance Criteria:**
- [ ] `show_changed_file_names` delegates to `pinned_diff` (gains `-z|--null` leading token); line-mode output byte-identical
- [ ] git-shc stats path is one `pinned_diff --stat` call; `pathspec_args` builder (git-shc:178-181) deleted
- [ ] `extract_files_from_commit` calls `pinned_diff --no-renames --name-only`; renames keep BOTH sides; dependency documented in header
- [ ] `tests/lib/test_hug-file-input.bats` loads `hug-git-repo` (without it `is_range` exits 127 inside the `2>/dev/null || true` swallow → empty output, existing tests break)
- [ ] lib README documents `pinned_diff` (canonical invocation; display vs action contract)
- [ ] `make test-lib` and `make test-unit` green

**Verify:** `make test-lib TEST_FILE=test_hug-file-input.bats && make test-lib TEST_FILE=test_hug_git_show.bats && make test-unit TEST_FILE=test_sh.bats` → all `✓ All tests passed!`

**Steps:**

- [ ] **Step 1: Write the failing tests.** In `tests/lib/test_hug-file-input.bats`, first add the load after the existing `load '../../git-config/lib/hug-common'` (line 7) — this is load-bearing, not cosmetic:

```bats
load '../../git-config/lib/hug-git-repo' # is_range for pinned_diff — hug-common does NOT load it
```

Then append after the existing `extract_files_from_commit` tests (note: this file overrides `error()` to `return 1` — never assert exit codes on guard paths here, assert on output):

```bats
@test "extract_files_from_commit: rename lists BOTH sides (action contract, byte-identical with today)" {
  local test_repo=$(create_test_repo)
  cd "$test_repo"
  echo a > old.txt
  git add -A && git commit -qm init
  git mv old.txt new.txt
  git commit -qm rename
  run extract_files_from_commit HEAD
  assert_success
  # Both sides: staging/untrack lists need the deleted side (--no-renames).
  # A display pin here would silently drop old.txt — rejected in review:
  # hug a --from-commit was working; a consolidation must not shrink action lists.
  assert_line "old.txt"
  assert_line "new.txt"
}

@test "extract_files_from_commit: non-ASCII path prints raw under hostile quotePath" {
  local test_repo=$(create_test_repo)
  cd "$test_repo"
  git config core.quotePath true
  echo a > 'café.txt'
  git add -A && git commit -qm add
  run extract_files_from_commit HEAD
  assert_success
  assert_line "café.txt"
}
```

In `tests/lib/test_hug_git_show.bats`, append inside the `# show_changed_file_names TESTS` section (after the last existing test in that section):

```bats
@test "show_changed_file_names: thin-wrapper keeps line-mode output identical (regression)" {
  local test_repo=$(create_test_repo)
  cd "$test_repo"
  echo a > plain.txt
  echo b > 'café.txt'
  git add -A && git commit -qm init
  git mv plain.txt renamed.txt
  echo c >> 'café.txt'
  git add -A && git commit -qm second
  run show_changed_file_names "HEAD"
  assert_success
  assert_line "renamed.txt"   # display contract: new path only
  assert_line "café.txt"      # non-ASCII raw (quotePath pin)
}

@test "show_changed_file_names: -z leading token threads through to NUL output" {
  local test_repo=$(create_test_repo)
  cd "$test_repo"
  echo a > a.txt
  echo b > b.txt
  git add -A && git commit -qm init
  # NUL assertion via pipe — BATS run/$output strips NUL bytes. od -c renders
  # NUL as \0 (two chars); single-backslash literals below are exact bytes.
  [[ "$(show_changed_file_names -z "HEAD" | od -An -c | tr -d ' \n')" == 'a.txt\0b.txt\0' ]]
}
```

- [ ] **Step 2: Run to verify failures** — `make test-lib TEST_FILE=test_hug-file-input.bats` → the rename test fails (old side missing after refactor — wait, it fails BEFORE the refactor too because `is_range` is missing → empty output; either failure mode proves the test bites). `make test-lib TEST_FILE=test_hug_git_show.bats` → `-z` test fails (`-z` is not yet a leading token).

- [ ] **Step 3: Rewrite `show_changed_file_names`** in `git-config/lib/hug-git-show` — replace lines 146-199 (doc comment + body) with:

```bash
# Prints the repo-relative paths of files changed in a commit or range, one per
# line — the --name-only equivalent of git-shc's --stat output.
#
# Usage: show_changed_file_names [-z|--null] "commit_or_range" [pathspec...]
# Parameters:
#   $1   - Optional -z/--null, then a commit ref, range, or N/-N form (resolved
#          internally via resolve_commit_ref, so the function is independently
#          testable without the script wrapper).
#   $2.. - Optional pathspecs (already-exploded args, passed as-is).
# Output:
#   Line mode: repo-relative file paths, one per line; raw for non-ASCII bytes
#   (core.quotePath=false pin), but git still C-quotes structural chars
#   (newline, backslash, quote, tab) — one quoted token per line: safe for
#   line-based consumers, but not the path itself.
#   With -z: paths NUL-terminated and fully raw (including structural chars),
#   never captured (callers pipe to `xargs -0 -r` / `read -d ''`).
#   Empty on no matches.
# Exit codes:
#   0 on success, including zero matches (empty stdout — callers detect
#   emptiness via stdout). An invalid ref propagates git's exit 128 and its
#   fatal message on stderr.
# Environment:
#   None read; does NOT honor HUG_QUIET (output is pure data — no header by design).
# Notes:
#   - Delegates to pinned_diff (hug-git-diff), the single canonical pinned
#     changed-files invocation — the former near-copy of its flag set is gone.
#   - Merge-commit single-commit shows nothing (same as --stat) — known parity,
#     see elifarley/hug-scm#268.
#   - Bundled-flag handling lives in the git-shc script wrapper, NOT here.
show_changed_file_names() {
    local null_mode=false
    case "${1:-}" in
    -z | --null) null_mode=true; shift ;;
    esac
    local target="${1:-HEAD}"
    shift || true

    local resolved
    resolved=$(resolve_commit_ref "$target" "HEAD")

    local -a zflag=()
    $null_mode && zflag=(--null)
    pinned_diff "${zflag[@]+"${zflag[@]}"}" --name-only "$resolved" "$@"
}
```

- [ ] **Step 4: Collapse the git-shc stats path + delete the dead builder.** In `git-config/bin/git-shc`, replace the `-n` dispatch block (lines ~168-176), the `pathspec_args` builder (lines ~178-181), and the two-branch stats block (lines ~183-207) with:

```bash
if $name_only; then
  if $null_sep; then
    show_changed_file_names -z "$commit_ref" "${_pathspec_pathspecs[@]+"${_pathspec_pathspecs[@]}"}"
  else
    show_changed_file_names "$commit_ref" "${_pathspec_pathspecs[@]+"${_pathspec_pathspecs[@]}"}"
  fi
  exit 0
fi

# Show changed files with stats, optionally filtered by pathspecs.
# pinned_diff owns the invocation + determinism pins; the emoji headers stay
# here, keyed off is_range (display policy, not data policy).
if [[ ${HUG_QUIET:-} != T ]]; then
  if is_range "$commit_ref"; then
    commit_emoji="$(_diff_emoji commit)"
    stats_emoji="$(_diff_emoji stats)"
    printf '%s %s Changed files in range %s:\n' "$commit_emoji" "$stats_emoji" "$commit_ref" >&2
  else
    commit_emoji="$(_diff_emoji commit)"
    stats_emoji="$(_diff_emoji stats)"
    printf '%s %s Changed files:\n' "$commit_emoji" "$stats_emoji" >&2
  fi
fi
stats_output=$(pinned_diff --stat "$commit_ref" "${_pathspec_pathspecs[@]+"${_pathspec_pathspecs[@]}"}")
```

Keep the trailing `printf '%s\n' "$stats_output"`, the no-match hint block, and `exit 0` exactly as they are. The `pathspec_args` builder is DELETED — its only consumers were the two git calls this single `pinned_diff` call replaces (git-shc:193, 201); the `-n` path already used `_pathspec_pathspecs` directly.

- [ ] **Step 5: Convert `extract_files_from_commit`** in `git-config/lib/hug-file-input` — replace lines 128-143 with:

```bash
# Extract files directly from a commit using optimized git command
# Usage: extract_files_from_commit <commit>
# Outputs filenames one per line to stdout
# Depends on: pinned_diff (hug-git-diff) — every current consumer loads it via
# hug-common's lib list. NOTE: the `2>/dev/null || true` below masks exit 127
# (an unsourced pinned_diff) and exit 2 (pinned_diff's own error_usage guards),
# not just git's 128 — a consumer that drops hug-common inherits a
# silently-empty file list.
extract_files_from_commit() {
  local commit="$1"

  # Validate commit exists
  if ! git rev-parse --verify "$commit" > /dev/null 2>&1; then
    error "Commit '$commit' does not exist"
    return 1
  fi

  # ACTION-LIST contract (--no-renames): both sides of a rename keep listing —
  # staging/untrack consumers (git-a/us/untrack/ccp) need the deleted side too.
  # Byte-identical with the previous unpinned output on ASCII fixtures.
  pinned_diff --no-renames --name-only "$commit" 2> /dev/null || true
}
```

- [ ] **Step 6: Document in `git-config/lib/README.md`** — add after the `#### hug-git-rebase` block (line ~150), before `### hug-json`:

```markdown
#### hug-git-diff
- Run the canonical pinned changed-files invocation (`pinned_diff`) — the ONE
  flag set for commit/range file listing: determinism pins
  (`core.quotePath=false`, `diff.relative=false`, `--ignore-submodules=none`)
  on every call, range/single dispatch, and `--null` NUL mode.
- Rename contract is two-valued and explicit: default `--find-renames` is the
  DISPLAY stance (new path only / collapsed `{old => new}` stat line — use for
  human-facing output); `--no-renames` is the ACTION-LIST stance (both sides —
  use when the list feeds staging/untrack/add operations).
- Call `show_changed_file_names` (hug-git-show) instead when you need N/-N
  shorthand resolution — it resolves then delegates here.
```

- [ ] **Step 7: Run all affected suites** — `make test-lib TEST_FILE=test_hug-file-input.bats && make test-lib TEST_FILE=test_hug_git_show.bats && make test-lib TEST_FILE=test_hug_git_diff.bats && make test-unit TEST_FILE=test_sh.bats` → all green.

- [ ] **Step 8: Full regression** — `make test` → `✓ All tests passed!` (both BATS and pytest).

- [ ] **Step 9: Commit (commit 2 of 3 — `refactor`)**

```bash
hug a git-config/lib/hug-git-show git-config/bin/git-shc git-config/lib/hug-file-input tests/lib/test_hug-file-input.bats tests/lib/test_hug_git_show.bats git-config/lib/README.md
hug c -F - <<'EOF'
refactor: adopt pinned_diff at the three changed-files call sites

WHY: The determinism pins protected one of three near-copies of the diff-tree
invocation; this commit makes them protect all three (issue #274 item 4), while
preserving the exact behavior of every working command.

WHAT: show_changed_file_names (hug-git-show) and git-shc's stats path become
thin wrappers over pinned_diff (display contract: --find-renames). The -n
dispatch and stats capture pass _pathspec_pathspecs directly; the dead
pathspec_args builder is deleted. extract_files_from_commit pins the ACTION
contract (--no-renames): both sides of a rename keep listing, byte-identical
with today on ASCII fixtures. tests/lib/test_hug-file-input.bats gains the
mandatory hug-git-repo load (hug-common does not load it — without this,
is_range exits 127 inside the 2>/dev/null || true swallow and every extract
test fails with empty output). lib README gains the hug-git-diff entry
documenting the display-vs-action rename contract.

HOW: Registered deltas (spec table, probe receipts on git 2.34.1): stats
non-ASCII C-quoted → raw on BOTH branches; single-branch renames collapse to
one {old => new} line (range branch already collapsed — porcelain default);
submodules always shown. Non-deltas: plain-ASCII/absent-rename/default-config
output byte-identical; action lists byte-identical including renames.
show_changed_file_names gains a -z|--null leading token (used by commit 3).

IMPACT: git-a/us/untrack/ccp --from-commit keep their exact working behavior
while gaining non-ASCII raw + submodule determinism. shc stats become
config-immune. One flag set to rule them all — future flag changes can no
longer diverge the three sites.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
```

---

### Task 3: `shc` CLI — `-z/--null`, positional strictness, unborn-HEAD guard, help + docs

**Goal:** Surface the spec's items 1-3 on the `shc` CLI and close the doc perimeter — one `feat(shc)` commit.

**Files:**
- Modify: `git-config/bin/git-shc` (arg loop, guards, dispatch, help text)
- Modify: `tests/unit/test_sh.bats` (shc section)
- Modify: `docs/commands/head.md` (Tips bullets, ~line 216)
- Modify: `README.md` (synopsis line ~546 + prerequisites minimum-git)
- Modify: `docs/meta/hug-completion-reference.md:105` (shc entry)
- Modify: `CHANGELOG.md` (`## [Unreleased]`)

**Acceptance Criteria:**
- [ ] `hug shc -n -z` emits NUL-separated raw paths (od-pipe asserted, incl. `$'we\nird'` fixture: line mode one C-quoted line, `-z` raw bytes)
- [ ] `hug shc -z` without `-n` → exit 2 usage error
- [ ] Second positional → exit 2 naming both tokens (stats mode AND `-n` mode, both orderings)
- [ ] Unborn HEAD (`git init` only) → branded exit-1 message, no raw `fatal:` — for forms: none, `1`, `-3`, `main..HEAD`, `@`, `@~2`, `@{1}`; `@{-1}` (unresolvable unborn) keeps the raw exit-128 fatal per D5
- [ ] Orphan repo (`git switch --orphan` after a commit): `hug shc master` WORKS unchanged
- [ ] Help: `-n` truthful quoting contract, `-z` entry with `xargs -0 -r`, ARGUMENTS one-positional rule, stale internal-caller claims replaced, CAPTURING + GIT EQUIVALENTS `-z` lines
- [ ] Docs: head.md tip, README synopsis `-z` + minimum git 2.34, completion-ref entry, CHANGELOG entry
- [ ] `make pre-commit` green (full gate)

**Verify:** `make test-unit TEST_FILE=test_sh.bats && make pre-commit` → green

**Steps:**

- [ ] **Step 1: Write the failing tests** — append to the shc section of `tests/unit/test_sh.bats` (file setup already provides `create_test_repo_with_history` + `require_hug`):

```bats
# -----------------------------------------------------------------------------
# hug shc -z / positional / unborn-HEAD (issue #274)
# -----------------------------------------------------------------------------

@test "hug shc -n -z: NUL-separated paths, final entry NUL-terminated, no trailing newline" {
  echo x > a.txt && echo y > b.txt
  git add -A && git commit -qm add-ab
  # NUL assertions via pipe — run/$output strips NUL bytes (project learning).
  # od -c renders NUL as \0 (two chars); full-stream equality also pins the
  # no-trailing-newline contract.
  [[ "$(hug shc -n -z HEAD | od -An -c | tr -d ' \n')" == 'a.txt\0b.txt\0' ]]
}

@test "hug shc -n -z: structural-char filename — line mode one C-quoted line, -z raw bytes" {
  printf 'z\n' > $'we\nird' && printf 'z\n' > 'back\slash.txt'
  git add -A && git commit -qm weird-names
  # BEFORE-behavior (line mode): ONE C-quoted token per path — git never split it.
  # Real enclosing quotes; C-quoting doubles the backslash inside the token.
  run hug shc -n HEAD
  assert_success
  assert_line '"back\\slash.txt"'
  assert_line '"we\nird"'
  # AFTER-behavior (-z): raw bytes, NUL-terminated, tree order
  # (back\slash.txt sorts before we\nird). Single backslashes below are exact
  # bytes — od prints one backslash per byte, no escaping at this layer.
  [[ "$(hug shc -n -z HEAD | od -An -c | tr -d ' \n')" == 'back\slash.txt\0we\nird\0' ]]
}

@test "hug shc -z without -n is a usage error (exit 2)" {
  run hug shc -z
  assert_failure 2
  assert_output --partial 'only valid with -n'
}

@test "hug shc: second positional rejected in stats mode (exit 2, names both tokens)" {
  run hug shc HEAD extra
  assert_failure 2
  assert_output --partial "unexpected second argument 'extra'"
  assert_output --partial "already 'HEAD'"
}

@test "hug shc: second positional rejected in -n mode, both orderings" {
  run hug shc -n main..HEAD typo
  assert_failure 2
  assert_output --partial "unexpected second argument 'typo'"
  run hug shc -n typo main..HEAD
  assert_failure 2
  assert_output --partial "unexpected second argument 'main..HEAD'"
}

@test "hug shc: unborn HEAD gives branded error for every HEAD-derived ref form" {
  local empty_repo=$(mktemp -d)
  cd "$empty_repo"
  git init -q && git config user.email t@t.tld && git config user.name t
  for ref in "" "1" "-3" "main..HEAD" "@" "@~2" "@{1}"; do
    if [[ -z "$ref" ]]; then
      run hug shc -n
    else
      run hug shc -n "$ref"
    fi
    assert_failure 1
    refute_output --partial 'fatal:'
    assert_output --partial 'no commits yet (unborn HEAD)'
  done
  # @{-1} (previous checkout) reads the HEAD reflog, which does not exist while
  # HEAD is unborn — an unresolvable explicit ref keeps git's raw fatal (D5).
  run hug shc -n '@{-1}'
  assert_failure 128
  assert_output --partial 'fatal'
  cd - >/dev/null
}

@test "hug shc: orphan repo — explicit ref works, HEAD-derived forms branded" {
  local orphan_repo=$(mktemp -d)
  cd "$orphan_repo"
  git init -q && git config user.email t@t.tld && git config user.name t
  echo x > f.txt && git add -A && git commit -qm c1
  git branch -m master
  git switch --orphan fresh
  run hug shc master        # explicit ref: keeps working (probe-backed contract)
  assert_success
  assert_output --partial 'f.txt'
  run hug shc               # HEAD-derived: branded, not a raw fatal
  assert_failure 1
  assert_output --partial 'no commits yet (unborn HEAD)'
  cd - >/dev/null
}

@test "hug shc stats: rename collapses on single-commit branch; range unchanged at default config" {
  echo a > old.txt && git add -A && git commit -qm init
  git mv old.txt new.txt && git commit -qm rename
  run hug shc HEAD
  assert_success
  assert_output --partial 'old.txt => new.txt'    # single branch: collapsed (delta)
  run hug shc 'HEAD~1..HEAD'
  assert_success
  assert_output --partial 'old.txt => new.txt'    # range: already collapsed today (no delta)
}

@test "hug shc stats: non-ASCII path prints raw (registered delta, byte oracle)" {
  echo a > 'café.txt' && git add -A && git commit -qm cafe
  run hug shc HEAD
  assert_success
  assert_output --partial 'café.txt | 1'
  refute_output --partial 'caf\303\251'
}
```

- [ ] **Step 2: Run to verify failures** — `make test-unit TEST_FILE=test_sh.bats` → all new shc tests fail (`-z` rejected by the flag loop; second positional silently last-wins; unborn raw fatal).

- [ ] **Step 3: Update the arg loop** in `git-config/bin/git-shc` — replace the loop (lines ~135-161, from `name_only=false` through `done`) with:

```bash
name_only=false
null_sep=false
commit_ref=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  -n | --name-only)
    name_only=true
    shift
    ;;
  -z | --null)
    null_sep=true
    shift
    ;;
  -*)
    # Any other -token: reject. reject_flag_ref allows -N (e.g. -3 → HEAD~3..HEAD)
    # and rejects everything else (-nq, -qn, --foo) with help + exit 2. Called
    # straight-line on purpose: it either exits or approves the token, and an
    # && block here would skip the shift on a non-zero return, spinning this
    # loop forever on the same token.
    reject_flag_ref "$1"
    [[ -n "$commit_ref" ]] && error_usage "unexpected second argument '$1' — commit ref is already '$commit_ref' (pathspecs go after --)"
    commit_ref="$1"
    shift
    ;;
  *)
    [[ -n "$commit_ref" ]] && error_usage "unexpected second argument '$1' — commit ref is already '$commit_ref' (pathspecs go after --)"
    commit_ref="$1"
    shift
    ;;
  esac
done

if $null_sep && ! $name_only; then
  error_usage "-z/--null is only valid with -n/--name-only"
fi

commit_ref="${commit_ref:-HEAD}"

check_git_repo

# Resolve N/-N using unified N/-N syntax convention
commit_ref=$(resolve_commit_ref "$commit_ref" "HEAD")
```

- [ ] **Step 4: Add the unborn-HEAD guard** immediately after the `resolve_commit_ref` line added above (and before the `-n` dispatch from Task 2):

```bash
# Unborn HEAD, HEAD-derived refs only (issue #274 item 2). An unconditional
# check would mis-block `hug shc master` in a git-switch --orphan repo —
# HEAD-unborn does not mean commit-less. resolve_commit_ref maps the default
# to HEAD and N/-N to HEAD~N[..HEAD] (pure string mapping, no git calls), so
# running this AFTER resolution, `*HEAD*` plus the `@` arms is the complete
# set of HEAD-dependent forms: `@` (alias), `@~N`, `@^…`, `@{N}` (HEAD
# reflog). `@{-N}` (previous checkout) is deliberately NOT matched: it reads
# the HEAD reflog, which does not exist while HEAD is unborn (probe on 2.34.1:
# `git rev-parse @{-1}` in an orphan repo → exit 128), so it can only be an
# unresolvable ref here and keeps git's raw fatal like any invalid explicit
# ref (D5). A broad `@*` arm would brand it, contradicting D5.
# Invalid explicit refs keep git's raw exit-128 fatal (show_changed_file_names
# doc contract). Known false positive: a ref literally named like `A-HEAD` in
# an unborn repo — acceptable, documented in the spec.
case "$commit_ref" in
  *HEAD* | @ | @~* | @^* | '@{'[0-9]*)
    git rev-parse --verify -q HEAD >/dev/null 2>&1 ||
      error "no commits yet (unborn HEAD) — nothing to show; make a commit first"   # exit 1
    ;;
esac
```

- [ ] **Step 5: Thread `-z` through the `-n` dispatch** — the dispatch block from Task 2 already reads `show_changed_file_names -z "$commit_ref" …` when `$null_sep`; verify it matches the spec's §3 sketch (it does — Task 2 installed it). No edit needed if Task 2's block is in place.

- [ ] **Step 6: Update the help text** in `show_help()`:

Replace the OPTIONS block (lines ~27-34):

```text
OPTIONS:
    -q, --quiet     Suppress header line (also honors HUG_QUIET env var)
    -n, --name-only Print ONLY changed file paths (repo-relative), one per line.
                    No stats, no header on stdout, no elision. Exit 0 even on
                    zero matches (detect via empty stdout). Machine-parseable:
                    paths print raw for non-ASCII bytes (core.quotePath=false
                    pin); git still C-quotes structural characters (newline,
                    backslash, quote, tab) in line mode — use -z for a fully
                    raw, NUL-separated stream. Renames list the new path only.
    -z, --null      With -n only: separate paths with NUL (\0) instead of
                    newline. Handles filenames containing newlines; pair with
                    xargs -0 -r / read -d ''. Without -n: usage error.
                    (-r matters: GNU xargs otherwise runs the command ONCE,
                    operand-less, on empty input — e.g. a no-match
                    `| xargs -0 rm`.)
    -h, --help      Show this help
```

In ARGUMENTS (after the `<range>` line, ~line 25) add:

```text
    At most one positional (commit ref or range) is accepted; a second is a
    usage error (pathspecs go after --).
```

Replace the stale internal-caller claims (lines ~52-54):

```text
    This command is the canonical source for file statistics display.
    It is used internally by other Hug commands (h files, h squash, shcp,
    and via hug-git-show/hug-git-commit by sh, shp and commit-range flows)
    — most pass HUG_QUIET=T; h squash redirects the header to stderr.
```

In CAPTURING OUTPUT (after the `*.py` example, ~line 78) add:

```text
    hug shc -n -z main..HEAD | xargs -0 -r <cmd>   # NUL-separated: safe for
                                                   # ANY filename (the -r is
                                                   # not optional — see -z)
```

In GIT EQUIVALENTS (after the `-n HEAD` line, ~line 105) add:

```text
    git diff-tree -z --no-commit-id --name-only -r --root HEAD  →  hug shc -n -z HEAD
```

- [ ] **Step 7: Run shc tests green** — `make test-unit TEST_FILE=test_sh.bats` → all green (old + new).

- [ ] **Step 8: Audit step (spec-mandated, before the commit lands)** — run and confirm every internal caller passes exactly one positional + optional `--` pathspecs:

```bash
grep -rn "git shc" git-config/bin git-config/lib
# Expected 9 literal sites: git-h-files:195, git-h-squash:197 (no HUG_QUIET,
# >&2), git-shcp:140,147, hug-git-show:267,269,339,341, hug-git-commit:447.
# lol (.gitconfig alias) and git-cmv contain NO literal call — phantom entries
# from an early draft; do not "fix" them.
```

- [ ] **Step 9: Docs perimeter.**

`docs/commands/head.md` — replace the Tips bullet (line ~216):

```markdown
- List just the affected file paths (scriptable, repo-relative): `hug shc -n HEAD~3..HEAD`. For filenames containing newlines/backslashes use `hug shc -n -z` (NUL-separated — pair with `xargs -0 -r`); at most one positional is accepted.
```

`README.md` — update the synopsis line (~546):

```markdown
hug shc [N|commit|range] [-n] [-z] [-- <path>...] # SHow: Changed files (cumulative stats, -n for paths only, -z NUL-separated with -n)
```

Then locate the prerequisites section (`grep -n "Prerequisite\|requirement\|git version" README.md | head`) and add the floor declaration line:

```markdown
- git ≥ 2.34 (minimum supported; determinism pins and quoting contracts are probe-verified on this floor)
```

`docs/meta/hug-completion-reference.md:105` — replace the shc entry:

```markdown
- `shc [<commit>]`: Files changed in commit. Args: `[<commit>]` (optional, default HEAD; also `N`/`-N` and ranges; at most ONE positional — a second is a usage error), `[-n|--name-only]` (optional: paths only, one per line), `[-z|--null]` (optional: with -n only, NUL-separated), `[-- <path>...]` (optional pathspecs).
```

`CHANGELOG.md` — fill `## [Unreleased]`:

```markdown
## [Unreleased]

### Added
- `hug shc -z/--null` (with `-n`): NUL-separated changed-file paths — the only
  mode fully raw for every filename (line mode still C-quotes structural
  characters). Pair with `xargs -0 -r` / `read -d ''`.
- `pinned_diff()` in `hug-git-diff`: the single canonical pinned changed-files
  invocation, with an explicit rename contract — `--find-renames` for display,
  `--no-renames` for action lists (both rename sides).

### Changed
- `hug shc` stats: non-ASCII paths print raw instead of C-quoted (both dispatch
  branches); renames collapse to one `{old => new}` line on the single-commit
  branch; submodules always shown. Output is now deterministic under hostile
  `core.quotePath` / `diff.renames` / `diff.relative` / `diff.ignoreSubmodules`.
- `hug a/us/untrack/ccp --from-commit`: deterministic path lists (non-ASCII raw,
  submodules shown); rename lists keep BOTH sides — behavior preserved.
- `hug shc`: a second positional is now a usage error (exit 2); unborn HEAD
  (HEAD-derived refs, incl. `@`) gives a branded exit-1 message instead of a raw
  git fatal; explicit refs in orphan repos keep working.
```

- [ ] **Step 10: Full gate + commit (commit 3 of 3 — `feat(shc)`)**

```bash
make pre-commit   # sanitize + full test suite — must be green before committing
hug a git-config/bin/git-shc tests/unit/test_sh.bats docs/commands/head.md README.md docs/meta/hug-completion-reference.md CHANGELOG.md
hug c -F - <<'EOF'
feat(shc): -z/--null NUL mode, one-positional rule, branded unborn-HEAD error

WHY: The --name-only adversarial review deferred four weaknesses (#274); the
consolidation landed in the previous commit; this surfaces the remaining
three on the CLI and closes the doc perimeter.

WHAT: -z/--null (requires -n): NUL-separated raw paths via pinned_diff --null
— the only mode fully raw for structural-char filenames (line mode C-quotes
them, one safe token per line). Second positional → error_usage exit 2 naming
both tokens, both orderings (positionals were last-wins). Unborn HEAD →
branded exit-1 message, scoped to HEAD-derived ref forms ONLY (case on the
resolved ref: *HEAD* | @ | @*) — orphan repos keep working explicit refs
(git switch --orphan has unborn HEAD WITH commits; an unconditional guard
would mis-block hug shc master with a factually wrong message). Help text:
truthful -n quoting contract, -z entry with xargs -0 -r (GNU xargs runs the
command once operand-less on empty input), one-positional rule, stale
internal-caller claims (lol/cmv/HUG_QUIET=T blanket) replaced with the
audited nine-site picture. Docs: head.md tip, README synopsis -z + declared
git floor (2.34), completion-reference shc entry, CHANGELOG.

HOW: Guards ordered flag-coupling (exit 2) after the loop, unborn check after
resolve_commit_ref and before dispatch; NUL tests assert via od pipes, never
BATS $output (it strips NULs and would vacuously pass). Audit step executed:
all nine internal git shc call sites pass one positional + optional --
pathspecs (receipts in the plan).

IMPACT: Scriptable consumers get a filename-safe machine contract; typo'd
second refs fail loud instead of silently last-wins; fresh repos get a humane
message. Closes elifarley/hug-scm#274.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
```

---

## Self-Review (done at plan-writing time)

**Spec coverage:** item 1 (`-z`) → Tasks 1-3; item 2 (unborn) → Task 3 Step 4 + tests; item 3 (positional) → Task 3 Step 3 + tests; item 4 (consolidation) → Tasks 1-2. Registered deltas: all five table rows have asserting tests (non-ASCII stats → Task 1+3; single-branch rename → Task 1+3; submodules → Task 1; extract non-ASCII → Task 2; relative → Task 1). Reachability/harness → Task 2 Step 1. Doc perimeter (head.md, lib README, README, completion-ref, CHANGELOG) → Tasks 2-3. Probes: receipts pre-baked; CI re-confirmation = the tests themselves running on ubuntu-latest.

**Placeholder scan:** none — every step carries complete code or exact replacement text.

**Type consistency:** `pinned_diff [--null] [--no-renames] <format> <resolved_ref> [pathspec...]` used identically in Task 1 (definition), Task 2 (`--stat`, `--no-renames --name-only`, `--null` via `zflag`), Task 3 (guard text). `show_changed_file_names [-z|--null] <ref> [pathspec...]` consistent across Tasks 2-3.

**Known deviations from skill defaults:** commit commands use the repo's `hug a` / `hug c -F -` (repo rule: never raw git); test commands use `make` targets (repo rule: never direct bats). Follow-up issues to file at merge time (NOT in this PR): skills-guide `-z` adoption (docs/skills/hug-repo-analysis SKILL.md:114,289 + 2 guides) and the `xargs -0`-without-`-r` shape at git-s:84.
