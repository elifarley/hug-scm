<!-- /autoplan restore point: /home/ecc/.gstack/projects/elifarley-hug-scm/fix-207-208-visibility-autoplan-restore-20260714-173242.md -->
# Visibility Batch (#207 + #208) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close #207 (silent-commit hazard on `hug c` and `hug a`) and #208 (`hug rb` same-name no-op + dirty-tree remediation text suggests non-existent commands) with four atomic commits in a single PR.

**Architecture:** Add an optional `--cap` / `--more-hint` API to the existing `print_list` helper (lib infrastructure, default behavior unchanged), then thread it into `hug c` as a pre-commit RECOVERY preview. Separately, fix the dirty-tree remediation strings in `hug-git-state` (replacing operation-wrong `discard` suggestions with the correct `wipe` for full clean), and teach `hug rb`'s same-name no-op to point at the upstream tracking ref via `git rev-parse @{u}`. Finally, add a PREVENTION counterpart in `hug a` (Task 4): a one-line post-stage index summary so the agent sees they're staging into a populated index — the actual root-cause fix for #207, accepting codex's U1 challenge. All four land in one worktree.

**Why four commits (not three):** Task 2's `hug c` preview is honestly a RECOVERY aid, not a gate (U1 accepted). The user accepted codex's challenge and asked for staging-time visibility to address the root cause. Task 4 (`hug a` index summary) delivers the PREVENTION counterpart. Together they close the full #207 hazard class: prevention at staging + recovery at commit.

**Tech Stack:** Bash, BATS test framework, hug-scm conventions (`info`/`error` to stderr, `gum_log` for color/TTY handling, Makefile test targets).

**Spec:** `docs/superpowers/specs/2026-07-14-visibility-batch-207-208-design.md`

---

## File Structure

### Files modified

| File | Purpose | Commit |
|------|---------|--------|
| `git-config/lib/hug-arrays` | Add `--cap` / `--more-hint` to `print_list` (lines 39-56) | 1 |
| `tests/lib/test_hug-arrays.bats` | EXTEND existing file with `print_list` API tests | 1 |
| `git-config/bin/git-c` | Replace `info "Committing staged changes..."` with capped preview (lines 82-92) | 2 |
| `tests/unit/test_commit.bats` | Update existing `--quiet` test + add preview tests | 2 |
| `git-config/lib/hug-git-state` | Fix remediation in `check_working_tree_clean` (lines 67-74) + `check_file_unstaged` (line 189) | 3 |
| `git-config/bin/git-rb` | Same-name no-op upstream pointer (lines 114-117) | 3 |
| `.github/copilot-instructions.md` | Fix line 467 stale `git w-discard` | 3 |
| `tests/unit/test_rb.bats` | Same-name no-op tests | 3 |
| `tests/lib/test_hug_git_state.bats` (or new) | Remediation-text assertions | 3 |
| `git-config/bin/git-a` | Add post-stage index summary (Task 4, U1 accepted) | 4 |
| `tests/unit/test_add.bats` (extend or create) | Index-summary tests | 4 |

### Decomposition rationale

- **One file per concern.** `hug-arrays` is the list-rendering helper; `git-c` is the consumer; `hug-git-state` + `git-rb` are the rebase-side fixes.
- **No file grows large.** Each modification is bounded — `print_list` gains ~25 lines, `git-c` swaps ~5 lines for ~10, `git-rb` adds ~5 lines.
- **Existing patterns preserved.** All new tests use the established `create_test_repo*` helpers and `run` / `assert_output --partial` shape.

---

## Task 1: Extend `print_list` with `--cap` and `--more-hint`

**Goal:** Add an optional cap-and-overflow API to the existing `print_list` helper without changing default behavior for any existing caller.

**Files:**
- Modify: `git-config/lib/hug-arrays:39-56` (function `print_list`)
- Modify: `tests/lib/test_hug-arrays.bats` (EXTEND — file already exists with 4 print_list tests at lines 86-126; add new --cap tests there)

**Acceptance Criteria:**
- [ ] `print_list "Title" a b c` (no flags) still prints `Title (3):\n  a\n  b\n  c\n` to stderr (regression — existing 4 tests must still pass).
- [ ] `print_list --cap 2 "Title" a b c d` prints title + first 2 items + overflow line `... (+2 more)` to stderr.
- [ ] `print_list --cap 2 --more-hint "see more" "Title" a b c d` prints overflow line `... (+2 more — see more)`.
- [ ] `print_list --cap 5 "Title" a b` (count ≤ cap) prints full list, no overflow line.
- [ ] `print_list --cap 0 "Title" a b c` is treated as no-cap (full list, no overflow).
- [ ] `print_list --cap 08 "Title" a b c d e f g h i` is treated as decimal 8 (no octal error).
- [ ] `print_list --more-hint "x" "Title" a b c` (hint without cap) ignores hint, prints full list.
- [ ] `print_list --cap` (no value, end of args) prints "requires a value" to stderr, returns 1.
- [ ] `print_list --cap T "Title" a b` (non-integer value) prints "non-negative integer" error, returns 1.
- [ ] `print_list --cap 99999999999999999999999 "Title" a b` (overflow value) prints "out of range" error, returns 1 (bash arithmetic overflow guard).
- [ ] `print_list --cap 5` (no title after flags) prints "requires a title" error, returns 1 (set -u safety).
- [ ] `print_list --cap 3 -- "--my title--" a b c d` parses title after `--` delimiter.
- [ ] All output goes to stderr; stdout is empty in every case.
- [ ] `HUG_QUIET=T print_list "T" a b c` STILL produces output (print_list does NOT honor HUG_QUIET — it's data for dry-run callers; callers gate themselves).

**Verify:** `make test-lib TEST_FILE=test_hug-arrays.bats` → all tests pass (new tests + existing 4 print_list tests).

**Steps:**

- [ ] **Step 1: Append the failing tests to `tests/lib/test_hug-arrays.bats`**

The file already exists with 4 `print_list` tests (lines 86-126) covering basic title/items behavior. Append the new `--cap` API tests below them. Don't duplicate the existing coverage.

```bash
# Append to existing tests/lib/test_hug-arrays.bats (which already loads
# test_helper and hug-arrays at the top). These tests cover the new --cap
# and --more-hint API. print_list is human-facing: ALL output goes to stderr.
# Note: print_list does NOT honor HUG_QUIET (it is data output for dry-run
# callers); callers gate at the call site if they want silence.

@test "print_list: --cap with overflow — shows first N + overflow line" {
  run print_list --cap 2 "T" a b c d
  assert_success
  assert_output --partial "T (4):"
  assert_output --partial "  a"
  assert_output --partial "  b"
  refute_output --partial "  c"
  assert_output --partial "... (+2 more)"
}

@test "print_list: --cap with non-empty --more-hint" {
  run print_list --cap 2 --more-hint "see more" "T" a b c d
  assert_success
  assert_output --partial "... (+2 more — see more)"
}

@test "print_list: --cap with empty --more-hint — no trailing em-dash" {
  run print_list --cap 2 --more-hint "" "T" a b c d
  assert_success
  assert_output --partial "... (+2 more)"
  refute_output --partial "—"
}

@test "print_list: count ≤ cap — no overflow line" {
  run print_list --cap 5 "T" a b
  assert_success
  assert_output --partial "T (2):"
  refute_output --partial "more"
}

@test "print_list: --cap 0 — treated as no-cap" {
  run print_list --cap 0 "T" a b c
  assert_success
  assert_output --partial "  c"
  refute_output --partial "more"
}

@test "print_list: --cap 08 — decimal 8, not octal error" {
  # 9 items, cap 8: should show 8 items + 1 overflow
  run print_list --cap 08 "T" a b c d e f g h i
  assert_success
  assert_output --partial "T (9):"
  assert_output --partial "  h"
  refute_output --partial "  i"
  assert_output --partial "... (+1 more)"
}

@test "print_list: --more-hint without --cap — hint ignored" {
  run print_list --more-hint "x" "T" a b c
  assert_success
  refute_output --partial "more"
}

@test "print_list: --cap with no value (end of args) — error, return 1" {
  # No title, no items — --cap is the LAST arg, value is missing.
  run print_list --cap
  assert_failure
  assert_output --partial "requires a value"
}

@test "print_list: --cap value not an integer — error, return 1" {
  # --cap has a value (T), but T is non-numeric — different error message.
  run print_list --cap T "Title" a b
  assert_failure
  assert_output --partial "non-negative integer"
}

@test "print_list: --cap value too large (overflow guard) — error, return 1" {
  # Bash arithmetic silently overflows huge numbers; bound the cap to
  # prevent silent corruption (cap=99999999999999999999999 wraps to garbage).
  run print_list --cap 99999999999999999999999 "T" a b
  assert_failure
  assert_output --partial "out of range"
}

@test "print_list: --cap with no title/items — error, return 1" {
  # Under set -u, `local title=$1` with no args fails. Guard against this.
  run print_list --cap 5
  assert_failure
  assert_output --partial "requires a title"
}

@test "print_list: -- delimiter — leading-dash title parsed" {
  run print_list --cap 2 -- "--my title--" a b c d
  assert_success
  assert_output --partial "--my title-- (4):"
  assert_output --partial "... (+2 more)"
}

@test "print_list: all output on stderr, stdout empty" {
  # Source the full library files (NOT line-range slices — fragile across edits).
  # Both files only define functions at top level; no execution side effects.
  run bash -c '. "'"$BATS_TEST_DIRNAME"'/../../git-config/lib/hug-common"; . "'"$BATS_TEST_DIRNAME"'/../../git-config/lib/hug-arrays"; print_list --cap 1 "T" a b 2>/dev/null'
  assert_success
  assert_output ""
}

@test "print_list: HUG_QUIET does NOT suppress output (print_list is data, not chatter)" {
  # Without HUG_QUIET, output appears
  run bash -c '. "'"$BATS_TEST_DIRNAME"'/../../git-config/lib/hug-common"; . "'"$BATS_TEST_DIRNAME"'/../../git-config/lib/hug-arrays"; print_list "T" a b 2>&1'
  assert_success
  assert_output --partial "T (2):"
  # With HUG_QUIET set, output STILL appears — print_list is used in dry-run paths
  # where the file list IS the data. Callers gate themselves if they want silence.
  run bash -c 'HUG_QUIET=T . "'"$BATS_TEST_DIRNAME"'/../../git-config/lib/hug-common"; HUG_QUIET=T . "'"$BATS_TEST_DIRNAME"'/../../git-config/lib/hug-arrays"; HUG_QUIET=T print_list "T" a b 2>&1'
  assert_success
  assert_output --partial "T (2):"
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test-lib TEST_FILE=test_hug-arrays.bats
```

Expected: most tests FAIL because `print_list` doesn't accept `--cap` — it treats `--cap` as the title and shifts everything.

- [ ] **Step 3: Implement the new `print_list` API**

Replace the existing `print_list` function in `git-config/lib/hug-arrays` (lines 39-56) with:

```bash
# Prints a titled list of items, with optional cap-and-overflow.
# Usage: print_list [--cap N] [--more-hint "<text>"] [--] "Title" item1 item2 ...
# Parameters:
#   --cap N          Cap the rendered list at N items; append an overflow line
#                    when count > N. N=0 or non-integer disables capping.
#   --more-hint "<text>"  Text appended to the overflow line. Ignored without --cap.
#   --               End-of-flags delimiter (lets titles start with --).
#   Title for the list (first positional after flags / --)
#   $@ - Items to list (remaining arguments)
# Output:
#   Title with count, followed by indented items, optionally followed by an
#   overflow line (ALL on stderr).
# NOTE: All output goes to stderr. This function is for human-facing labels
# and lists (chatter), NOT machine-consumable data. For data output, use printf directly.
# Flag-parsing contract:
#   - Flags must precede the title. The first non-flag arg OR the arg after `--`
#     is the title; everything else is an item.
#   - `--cap` requires a following value; missing → error to stderr, return 1.
#   - Repeated flags: last one wins.
#   - `--cap <value>` validation: regex `^[0-9]+$`. The implementation normalizes
#     via `cap=$((10#$cap))` to force decimal, defusing the bash octal-literal
#     trap (e.g. `08` is invalid octal; `10#08` is decimal 8).
#   - Empty / unset `--more-hint`: overflow line is `... (+M more)`.
#     Non-empty: `... (+M more — <hint>)`.
print_list() {
  # NOTE: print_list does NOT honor HUG_QUIET. This is deliberate.
  # Existing callers (hug-git-discard, hug-output) use print_list in DRY-RUN
  # output paths where the file list IS the data the user needs (e.g.,
  # `hug w discard --dry-run` prints the affected files via print_list). If
  # print_list went quiet under HUG_QUIET, dry-run output would lose the file
  # list while keeping the header — silent data loss in a safety path.
  # Callers that want chatter-style suppression (like hug c's preview) must
  # gate the call site themselves with [[ -z "${HUG_QUIET:-}" ]].
  # (autoplan CEO C1 reverted after eng review confirmed this regression.)

  local cap=0
  local more_hint=""
  local has_more_hint=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cap)
        if [[ $# -lt 2 ]]; then
          printf 'print_list: --cap requires a value\n' >&2
          return 1
        fi
        local _cap_raw="$2"
        if ! [[ "$_cap_raw" =~ ^[0-9]+$ ]]; then
          printf 'print_list: --cap value must be a non-negative integer, got %q\n' "$_cap_raw" >&2
          return 1
        fi
        # Overflow guard: bash arithmetic silently wraps huge numbers
        # (99999999999999999999999 → 200376420520689663). Bound the cap to a
        # sane upper limit so the silent wrap can't produce nonsense behavior.
        # 100000 is generous — the largest realistic staged-file count is ~10k.
        if [[ ${#_cap_raw} -gt 6 ]]; then
          printf 'print_list: --cap value out of range (max 999999)\n' >&2
          return 1
        fi
        cap=$((10#$_cap_raw))
        shift 2
        ;;
      --more-hint)
        if [[ $# -lt 2 ]]; then
          printf 'print_list: --more-hint requires a value\n' >&2
          return 1
        fi
        more_hint="$2"
        has_more_hint=true
        shift 2
        ;;
      --)
        shift
        break
        ;;
      --*)
        printf 'print_list: unknown option: %q\n' "$1" >&2
        return 1
        ;;
      *)
        break
        ;;
    esac
  done

  # No-title guard: under set -u, `local title=$1` with no args fails
  # unbound. Detect explicitly and emit a helpful error.
  if [[ $# -lt 1 ]]; then
    printf 'print_list: requires a title (got only flags)\n' >&2
    return 1
  fi

  local title=$1
  shift

  local total=$#
  printf '%s (%d):\n' "$title" "$total" >&2

  local item
  local shown=0
  for item in "$@"; do
    if [[ $cap -gt 0 && $shown -ge $cap ]]; then
      break
    fi
    printf '  %s\n' "$item" >&2
    shown=$((shown + 1))
  done

  if [[ $cap -gt 0 && $total -gt $cap ]]; then
    local remaining=$((total - cap))
    if $has_more_hint && [[ -n "$more_hint" ]]; then
      printf '... (+%d more — %s)\n' "$remaining" "$more_hint" >&2
    else
      printf '... (+%d more)\n' "$remaining" >&2
    fi
  fi
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
make test-lib TEST_FILE=test_hug-arrays.bats
```

Expected: all tests PASS.

- [ ] **Step 5: Run full lib test suite to confirm no regressions in other `print_list` callers**

```bash
make test-lib
```

Expected: all tests PASS. Existing callers (`hug-git-discard`, `hug-output`) pass `Title items...` only — no flags — so the new parser handles them identically to the old code (the `while` loop falls through immediately on the first non-flag arg).

- [ ] **Step 6: Commit**

```bash
git add git-config/lib/hug-arrays tests/lib/test_hug-arrays.bats
git commit -m "feat(hug-arrays): print_list gains --cap and --more-hint flags

WHY: hug c needs to render a potentially long staged-file list with an
overflow marker ('+N more — run hug sls for the full list'), and that
truncation pattern is a generic list-rendering concern, not commit-specific.
Extending the existing print_list helper makes the cap-and-overflow API
available to every current and future caller; the alternative (inline in
git-c) would duplicate the pattern the next time any listing command wants it.

WHAT: Adds optional --cap N and --more-hint '<text>' flags. Default behavior
(no flags) is byte-identical to the old function — every existing caller
(hug-git-discard, hug-output) passes only 'Title items...' and is unaffected.
New behavior triggers only when --cap is supplied and count > cap: prints
the first N items, then an overflow line. The line shape is '... (+M more)'
by default, or '... (+M more — <hint>)' when a non-empty hint is supplied,
so callers can point users at the canonical full-list command.

HOW: Flag-parsing contract is fully specified in the function header comment
because this is now a public helper API, not a one-off utility:
- Flags precede the title; first non-flag arg or arg-after-`--` is the title.
- --cap requires a value; missing → error, return 1. Regex-validate as
  ^[0-9]+\$ and normalize via `cap=\$((10#\$cap))` to force decimal — bash
  otherwise treats 08 as an invalid octal literal and errors under set -e.
- --more-hint empty/unset → overflow line is '... (+M more)' with no
  trailing em-dash. Non-empty → '... (+M more — <hint>)'.
- Repeated flags: last-wins (matches getopt default).
- Unknown flags (--foo): error, return 1.
- Leading-dash titles: callers must use `--` delimiter.

IMPACT: Reusable truncation idiom, matching the shape already used by
hug wtl, hug ll -10, and rb_render_plan. No behavior change for any
existing caller; full test coverage of the new API in
tests/lib/test_hug-arrays.bats. Sets up commit 2 (hug c preview) and
unblocks future 'preview staged files' needs elsewhere without new helpers."
```

---

## Task 2: `hug c` staged-file preview (closes #207)

**Goal:** Replace `hug c`'s post-hoc-only "13 files changed" signal with a pre-commit staged-file preview, so agents and humans can spot unexpected entries (e.g. left over from a soft-reset) before the commit lands.

**Files:**
- Modify: `git-config/bin/git-c:82-92`
- Modify: `tests/unit/test_commit.bats:93-97` (update existing `--quiet` test)
- Add to: `tests/unit/test_commit.bats` (new preview tests)

**Acceptance Criteria:**
- [ ] After running `hug c -m "x"` with 1+ staged files, stderr contains `Committing staged file(s) (N):` followed by file names.
- [ ] With ≤10 staged files, all names appear on stderr; no overflow line.
- [ ] With >10 staged files, first 10 names + overflow `... (+M more — run 'hug sls' for the full list)` appear on stderr.
- [ ] With `hug c --allow-empty` and no staged files, stderr does NOT contain the preview.
- [ ] Existing `hug c: works with --quiet` test passes after updating its assertion (the old `Committing staged changes...` line is gone).
- [ ] `hug c -m "x"` stdout contains only git's own commit output; the preview is on stderr.
- [ ] Regression: `hug c -m "x"` still creates a commit (exit 0).

**Verify:** `make test-unit TEST_FILE=test_commit.bats` → all tests pass.

**Steps:**

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_commit.bats` (and update the existing `--quiet` test). The plan removes the old `info "Committing staged changes..."` line entirely, so EVERY existing assertion referencing that string must be updated. Six assertions currently reference it (verified by grep):

| Line | Test name | Current assertion | New assertion |
|------|-----------|-------------------|---------------|
| 53 | `hug c: allows empty commit with --allow-empty` | `assert_output --partial "Committing staged changes..."` | **DELETE the assertion** (preview is skipped for `--allow-empty` with no staged files per D7; the test already verifies the commit at line 56-57) |
| 66 | `hug c: commits staged changes with -m` | `assert_output --partial "Committing staged changes..."` | `assert_output --partial "Committing staged file(s) (1):"` |
| 96 | `hug c: works with --quiet (minimal output)` | `refute_output --partial "Committing staged changes..."` | `refute_output --partial "Committing staged file(s)"` (still valid: `print_list` now honors `HUG_QUIET` per fix C1) |
| 150 | first-commit test | `assert_output --partial "Committing staged changes..."` | `assert_output --partial "Committing staged file(s)"` |
| 207 | editor-invocation test (asserts `--quiet` suppression) | `refute_output --partial "Committing staged changes..."  # Quiet suppresses` | `refute_output --partial "Committing staged file(s)"  # Quiet suppresses via HUG_QUIET` |
| 962 | push-suggestion test | `assert_output --partial "Committing staged changes..."` | `assert_output --partial "Committing staged file(s)"` |

Update each one in place. The string `"Committing staged file(s)"` (without count) is a safe partial-match for both 1-file and N-file cases.

Then add these new tests at the end of `test_commit.bats`:

```bash
@test "hug c: pre-commit preview shows staged file name on stderr" {
  echo "stage me" > preview_one.txt
  hug a preview_one.txt
  run hug c -m "preview test"
  assert_success
  assert_output --partial "Committing staged file(s) (1):"
  assert_output --partial "preview_one.txt"
}

@test "hug c: preview caps at 10 with overflow marker" {
  # Stage 12 files. Use ZERO-PADDED names so lexical order matches numeric
  # order — `capfile_10.txt` lexically sorts BEFORE `capfile_2.txt` without
  # padding, which would make the cap-test assertions nondeterministic.
  for i in $(seq -w 1 12); do
    echo "content $i" > "capfile_${i}.txt"
  done
  hug a capfile_*.txt
  run hug c -m "cap test"
  assert_success
  assert_output --partial "Committing staged file(s) (12):"
  # First 10 lexically (with zero-pad) = capfile_01 .. capfile_10
  assert_output --partial "capfile_01.txt"
  assert_output --partial "capfile_10.txt"
  # capfile_11 and capfile_12 are in the overflow
  refute_output --partial "capfile_11.txt"
  refute_output --partial "capfile_12.txt"
  assert_output --partial "... (+2 more — run 'hug sls' for the full list)"
}

@test "hug c: --allow-empty with no staged files skips preview" {
  run hug c --allow-empty -m "empty"
  assert_success
  refute_output --partial "Committing staged file(s)"
}

@test "hug c: --quiet suppresses the preview (HUG_QUIET contract)" {
  echo "quiet test" > quiet_preview.txt
  hug a quiet_preview.txt
  run hug c -m "quiet preview" --quiet
  assert_success
  refute_output --partial "Committing staged file(s)"
  refute_output --partial "quiet_preview.txt"
}

@test "hug c: preview goes to stderr, git output to stdout" {
  # Use the file-redirection pattern from the spec — `run` merges streams.
  # Stage one file, then capture stdout and stderr separately.
  echo "stream test" > stream_test.txt
  hug a stream_test.txt
  local _out _err
  _out=$(mktemp)
  _err=$(mktemp)
  hug c -m "stream test" >"$_out" 2>"$_err"
  # stdout must NOT contain the preview header or the staged filename
  ! grep -q "Committing staged file(s)" "$_out"
  ! grep -q "stream_test.txt" "$_out"
  # stderr MUST contain the preview header and the staged filename
  grep -q "Committing staged file(s)" "$_err"
  grep -q "stream_test.txt" "$_err"
  rm -f "$_out" "$_err"
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test-unit TEST_FILE=test_commit.bats
```

Expected: the new preview tests FAIL (no `Committing staged file(s)` text yet). The updated `--quiet` test passes (the old line still exists, but `--quiet` already suppresses it).

- [ ] **Step 3: Implement the preview in `git-c`**

Open `git-config/bin/git-c`. Currently lines 82-92 are:

```bash
# Check for staged changes upfront
if ! $allow_empty && ! has_staged_changes; then
  info "No staged changes found.\n\nSuggestions:\n  - Stage files with 'hug a <files>'.\n  - To commit all changes (staged + unstaged), use 'hug ca'.\n  - For an empty commit, use 'hug c --allow-empty'.\n  - To preview staged changes, run 'hug sl' for a list or 'hug ss' for a diff."
  exit 1
fi

info "Committing staged changes..."

# Run git commit directly without capturing output to allow interactive editor
_suggest_args=()
$_c_amend && _suggest_args+=(--amend)
git commit "$@" && suggest_next_push_command "${_suggest_args[@]}"
```

Replace lines 82-92 (from `# Check for staged changes upfront` through `git commit "$@" && ...`) with:

```bash
# Check for staged changes upfront — compute once, use twice.
# (Previously has_staged_changes was re-evaluated in the rejection guard AND
#  would have been re-evaluated by the preview condition. One call, one truth.)
_has_staged=false
has_staged_changes && _has_staged=true

if ! $allow_empty && ! $_has_staged; then
  info "No staged changes found.\n\nSuggestions:\n  - Stage files with 'hug a <files>'.\n  - To commit all changes (staged + unstaged), use 'hug ca'.\n  - For an empty commit, use 'hug c --allow-empty'.\n  - To preview staged changes, run 'hug sl' for a list or 'hug ss' for a diff."
  exit 1
fi

# Pre-commit visibility (elifarley/hug-scm#207).
# Show staged file names so agents/humans can spot unexpected entries
# (e.g. left over from a soft-reset) BEFORE the commit lands — the post-commit
# "N files changed" line is too late to abort cheaply. Skipped for explicit
# --allow-empty invocations with nothing staged (D7). Suppressed by --quiet
# (HUG_QUIET) at the CALL SITE — print_list itself is data-only and stays
# loud for dry-run callers like `hug w discard --dry-run`.
#
# HONEST scope: this preview is a RECOVERY/TRANSPARENCY aid, not a gate.
# For interactive humans, the time window between the preview rendering and
# git commit running is too short to read 10 filenames and Ctrl-C. For
# agents, the output arrives only AFTER the commit completes — they can
# spot the mismatch in their own transcript and recover (hug h back 1,
# restage, recommit). This is still strictly better than today (no signal
# at all), which is why we ship it — but it is NOT a prevention mechanism.
# Prevention lives at staging time in `hug a` (see Task 4), not here.
#
# `hug c` forwards arbitrary git options via `git commit "$@"`, so options
# like -a/--all, --include, --only, --interactive, --patch can cause the
# final commit to differ from this preview. Acceptable for #207's incident
# class (soft-reset leftovers in the index); agents passing those options
# are explicitly opting into git's own semantics. (See T6 follow-up issue:
# detect -a/--all and abort with an educational message pointing at hug
# commands that stage explicitly.)
if $_has_staged && [[ -z "${HUG_QUIET:-}" ]]; then
  mapfile -t _staged_files < <(git diff --cached --name-only 2>/dev/null || true)
  if [[ ${#_staged_files[@]} -gt 0 ]]; then
    print_list --cap 10 --more-hint "run 'hug sls' for the full list" \
      "Committing staged file(s)" "${_staged_files[@]}"
  fi
fi

# Run git commit directly without capturing output to allow interactive editor
_suggest_args=()
$_c_amend && _suggest_args+=(--amend)
git commit "$@" && suggest_next_push_command "${_suggest_args[@]}"
```

Notes on the change:
- The old `info "Committing staged changes..."` line is GONE. The `print_list` header (`Committing staged file(s) (N):`) replaces it as the single "commit is starting" announcement.
- `has_staged_changes` is called once, captured in `_has_staged`. The preview condition becomes a cheap boolean check.
- `git diff --cached --name-only` failure is swallowed by `|| true` — preview never blocks a commit. The empty-array check ensures no preview renders when the diff unexpectedly returns nothing.
- `git-c` already sources `hug-git-kit` (line 10), which sources `hug-arrays` transitively. If for some reason it doesn't, add `hug-arrays` to the source line. Verify by running the test in Step 4 — if `print_list: command not found`, add the explicit source.

- [ ] **Step 4: Run tests to verify they pass**

```bash
make test-unit TEST_FILE=test_commit.bats
```

Expected: all tests PASS, including the new preview tests and the updated `--quiet` test.

- [ ] **Step 5: Manual smoke test of #207 repro**

```bash
_smoke=$(mktemp -d)
cd "$_smoke" && git init -q
for i in $(seq 1 12); do echo "content $i" > "f$i.txt"; done
hug a f*.txt
hug c -m "smoke test"
# Visual check: stderr shows "Committing staged file(s) (12):" + first 10 names +
# "... (+2 more — run 'hug sls' for the full list)" BEFORE the [main <hash>] line.
cd / && rm -rf "$_smoke"
```

- [ ] **Step 6: Commit**

```bash
git add git-config/bin/git-c tests/unit/test_commit.bats
git commit -m "fix(hug-c): show staged-file preview before committing (closes #207)

WHY: hug c commits whatever is staged with only a post-hoc 'N files changed'
line. An agent that ran 'hug a file.txt' after a soft-reset gets surprised
when the commit lands with 14 files; the lone signal is easy to miss and
arrives too late to abort cheaply. The root cause is lack of *visibility*
(not lack of a gate): the count alone doesn't surface 'wait, that file
shouldn't be here' — only file *names* do, and they need to appear BEFORE
the commit lands.

WHAT: Between the staged-changes check and git commit, render a capped
(10-item) staged-file preview to stderr via the new print_list --cap API.
Replaces the old 'Committing staged changes...' info line — the preview
header ('Committing staged file(s) (N):') announces the commit. With >10
staged files, the overflow line points at 'hug sls' for the full list.
Skipped for --allow-empty with nothing staged (no noise on explicit empty
commits).

HOW: Compute has_staged_changes ONCE into _has_staged (the old code
re-evaluated it in the guard AND would have in the preview condition).
git diff --cached --name-only failure is swallowed by '|| true' — the
preview never blocks a commit; an empty array means no preview renders.
stdout discipline preserved: the preview is on stderr (per CLAUDE.md
hug-c is interactive, no data output), git's own commit output on stdout
is unchanged. The old 'Committing staged changes...' assertion in
test_commit.bats is updated to assert the new header instead.

IMPACT: Closes the 'agent silently committed the wrong files' hazard class
on the most common commit path. Agents (the primary hug c users) can now
spot unexpected staged entries (e.g. leftovers from a soft-reset) and
abort with Ctrl-C / hug us <file> before the commit lands. The full
file list remains available via 'hug sls'; the preview is a visibility
aid, not a gate — no new prompts, no -y threading required by CI scripts.

Design ref: docs/superpowers/specs/2026-07-14-visibility-batch-207-208-design.md (#207, decision D1-D7)."
```

---

## Task 3: Fix `hug rb` same-name no-op + dirty-tree remediation text (closes #208)

**Goal:** Make `hug rb`'s same-name no-op informative (point at the upstream tracking ref) and replace the three non-existent `git w-backup` / `git w-discard-all` / `git w-discard <file>` remediation commands with the correct `hug w wip` / `hug w wipe-all` / `hug w wipe <file>`.

**Files:**
- Modify: `git-config/lib/hug-git-state:60-76` (`check_working_tree_clean`)
- Modify: `git-config/lib/hug-git-state:183-191` (`check_file_unstaged`)
- Modify: `git-config/bin/git-rb:113-117` (same-name no-op)
- Modify: `.github/copilot-instructions.md:467`
- Test: `tests/lib/test_hug_git_state.bats` (extend or create)
- Test: `tests/unit/test_rb.bats` (extend)

**Acceptance Criteria:**
- [ ] `check_working_tree_clean` with a dirty tree (staged OR unstaged) outputs an error containing `hug w wip "<msg>"`, `hug w wipe-all`, and `hug w wipe <file>`; does NOT contain `git w-`.
- [ ] Following either `wipe` remedy leaves the tree actually clean (re-running the guard succeeds).
- [ ] `check_file_unstaged` error contains `hug w discard` (NOT `git w-discard`) — `discard` stays because the function only asserts unstaged state.
- [ ] `hug rb main` while on `main` with `origin/main` upstream prints `Already on 'main' — did you mean 'hug rb origin/main'? (Rebases onto the last-fetched upstream tracking ref; run 'hug fetch' first if you need fresh commits.)` to stderr, exits 0.
- [ ] `hug rb main` while on `main` with NO upstream prints `Already on 'main'; nothing to rebase.`, exits 0.
- [ ] `hug rb main --dry-run` while on main (upstream set) prints the same pointer message.
- [ ] `.github/copilot-instructions.md` no longer contains `git w-discard`.
- [ ] `grep -rn 'git w-' git-config/ .github/` returns zero runtime matches.

**Verify:** `make test-unit TEST_FILE=test_rb.bats && make test-lib TEST_FILE=test_hug_git_state.bats` → all tests pass.

**Steps:**

- [ ] **Step 1: Check whether `tests/lib/test_hug_git_state.bats` exists**

```bash
ls tests/lib/test_hug_git_state.bats 2>&1
```

If it exists, we'll extend it. If not, we'll create it. (Plan accounts for both.)

- [ ] **Step 2: Write the failing tests**

For `tests/lib/test_hug_git_state.bats` — if the file does NOT exist, create it with this content. If it DOES exist, append the new tests.

```bash
#!/usr/bin/env bats

# Tests for hug-git-state library — focused on the dirty-tree remediation
# text fixes from the 207+208 visibility batch.

load '../test_helper'

setup() {
  CMD_BASE="$(readlink -f "$BATS_TEST_DIRNAME/../../git-config/lib" 2>/dev/null)"
  [ -d "$CMD_BASE" ] || CMD_BASE="$BATS_TEST_DIRNAME/../../git-config/lib"
  . "$CMD_BASE/hug-common"
  . "$CMD_BASE/hug-git-state"
}

@test "check_working_tree_clean: dirty tree error offers wipe (not discard)" {
  # create_test_repo already creates an initial commit (README.md) so HEAD is stable.
  cd "$(create_test_repo)" || exit 1
  # Stage one new file (staged changes present)
  echo "staged content" > staged_file.txt
  git add staged_file.txt
  # Modify the existing README.md (unstaged changes present) — README.md is
  # guaranteed to exist because create_test_repo creates it.
  echo "modification" >> README.md

  run check_working_tree_clean
  assert_failure
  assert_output --partial "hug w wip"
  assert_output --partial "hug w wipe-all"
  assert_output --partial "hug w wipe <file>"
  refute_output --partial "git w-"
  refute_output --partial "hug w discard-all"
}

@test "check_file_unstaged: error says hug w discard (not git w-discard)" {
  # create_test_repo creates README.md in the initial commit. Modify it to
  # create unstaged changes on a known-existing tracked file.
  cd "$(create_test_repo)" || exit 1
  echo "modification" >> README.md
  run check_file_unstaged "README.md"
  assert_failure
  assert_output --partial "hug w discard"
  refute_output --partial "git w-discard"
}
```

For `tests/unit/test_rb.bats`, append these new tests at the end:

```bash
@test "hug rb: same-name no-op points at upstream tracking ref" {
  # create_test_repo_with_remote_upstream sets up main with origin/main as upstream
  cd "$(create_test_repo_with_remote_upstream)" || exit 1
  run hug rb main --dry-run
  assert_success
  assert_output --partial "Already on 'main'"
  assert_output --partial "did you mean 'hug rb origin/main'"
  # Exit code 0 — still a no-op
}

@test "hug rb: same-name no-op falls back when no upstream configured" {
  cd "$(create_test_repo_with_history)" || exit 1
  # No remote, no upstream — bare no-op message should fire
  run hug rb main --dry-run
  assert_success
  assert_output --partial "Already on 'main'"
  assert_output --partial "nothing to rebase"
  refute_output --partial "did you mean"
}

@test "hug rb: dirty-tree error offers wipe (not discard)" {
  # create_test_repo_with_remote_upstream already has commits + upstream set,
  # so HEAD is stable and `hug rb origin/main` reaches the tree guard.
  cd "$(create_test_repo_with_remote_upstream)" || exit 1
  # STAGED change: stage a new file
  echo "staged content" > new_staged.txt
  git add new_staged.txt
  # UNSTAGED change: modify an existing tracked file (README.md exists from init)
  echo "more" >> README.md

  run hug rb origin/main --dry-run
  assert_failure
  assert_output --partial "hug w wip"
  assert_output --partial "hug w wipe-all"
  refute_output --partial "git w-"
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
make test-unit TEST_FILE=test_rb.bats
make test-lib TEST_FILE=test_hug_git_state.bats
```

Expected: new tests FAIL — current remediation text says `git w-backup` etc., and current same-name no-op is a bare message.

- [ ] **Step 4: Fix `check_working_tree_clean` in `git-config/lib/hug-git-state`**

Replace lines 60-76 (the `check_working_tree_clean` function):

```bash
# Checks if working tree is clean (no uncommitted changes)
# Usage: check_working_tree_clean
# Exits:
#   With error if there are uncommitted changes (staged or unstaged)
#   Error message includes counts and suggested solutions
check_working_tree_clean() {
    if ! git diff --quiet || ! git diff --cached --quiet; then
        local unstaged_count
        local staged_count
        unstaged_count=$(git diff --name-only | wc -l)
        staged_count=$(git diff --cached --name-only | wc -l)

        # IMPORTANT: this guard fires when EITHER staged OR unstaged changes
        # exist, so the remediation must offer operations that produce a
        # FULLY clean tree. hug w discard[-all] defaults to unstaged-only —
        # suggesting it here would leave staged changes (and the guard still
        # firing), trapping the user in a loop. wipe[-all] does both.
        # (elifarley/hug-scm#208)
        error "Working tree is not clean!
       Unstaged changes: $unstaged_count files
       Staged changes: $staged_count files

       Run 'hug sl' to see the full file list, then:
       Solutions:
       • Use 'hug w wip \"<msg>\"' to park all changes on a WIP branch
       • Use 'hug w wipe-all' to discard both staged and unstaged changes
       • Use 'hug w wipe <file>' for specific files"
    fi
}
```

- [ ] **Step 5: Fix `check_file_unstaged` in the same file**

Find line 189 (the `check_file_unstaged` error message):

```bash
    error "File '$file' has unstaged changes
    Use 'git w-discard $file' to discard changes first"
```

Replace with:

```bash
    # check_file_unstaged only asserts UNSTAGED state — so 'discard'
    # (unstaged-only by default) is the correct operation here, unlike
    # check_working_tree_clean where both staged+unstaged matter.
    error "File '$file' has unstaged changes
    Use 'hug w discard $file' to discard changes first"
```

- [ ] **Step 6: Fix the same-name no-op in `git-config/bin/git-rb`**

Find lines 113-117 (the `# Check if already on target` block):

```bash
  # Check if already on target.
  if [[ "$current_branch" == "$target_branch" ]]; then
    info "Already on '$target_branch'; nothing to rebase."
    return 0
  fi
```

Replace with:

```bash
  # Check if already on target. If so, point at the upstream tracking ref
  # when one exists AND resolves — the user almost certainly meant to sync
  # with the remote, not rebase a branch onto itself.
  # Detection is textual (current_branch == target_branch); equivalent refs
  # like `refs/heads/main` or `main^{commit}` do NOT match and fall through
  # to the normal rebase flow, which is correct (those aren't no-ops anyway).
  # We require `git rev-parse` to succeed on @{u} so a configured-but-never-
  # fetched upstream (where the remote-tracking ref doesn't exist) falls back
  # to the bare no-op rather than suggesting a command that would itself fail.
  # (elifarley/hug-scm#208)
  if [[ "$current_branch" == "$target_branch" ]]; then
    local _upstream
    if _upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) \
       && [[ -n "$_upstream" && "$_upstream" != "$current_branch" ]]; then
      info "Already on '$target_branch' — did you mean 'hug rb $_upstream'? (Rebases onto the last-fetched upstream tracking ref; run 'hug fetch' first if you need fresh commits.)"
    else
      info "Already on '$target_branch'; nothing to rebase."
    fi
    return 0
  fi
```

- [ ] **Step 7: Fix `.github/copilot-instructions.md` line 467**

Open `.github/copilot-instructions.md` and find line 467. It contains a `git w-discard` reference. Change `git w-discard` to `hug w discard`. (Read the surrounding context to make sure the change preserves the sentence's meaning — likely just a command substitution.)

- [ ] **Step 8: Run tests to verify they pass**

```bash
make test-unit TEST_FILE=test_rb.bats
make test-lib TEST_FILE=test_hug_git_state.bats
```

Expected: all tests PASS.

- [ ] **Step 9: Verify no stale `git w-` strings remain**

```bash
grep -rn 'git w-' git-config/ .github/
```

Expected: zero runtime matches. (Doc files in `git-config/lib/python/articles/` may mention git-prefix in narrative context — those are not runtime messages and are out of scope.)

- [ ] **Step 10: Manual smoke test of #208 repros**

Same-name no-op:
```bash
_smoke=$(mktemp -d)
cd "$_smoke" && git init -q
git remote add origin /tmp/fake-origin.git 2>/dev/null || true
# Set a fake upstream (won't actually fetch but rev-parse @{u} needs the config)
git config branch.main.remote origin
git config branch.main.merge refs/heads/main
git commit --allow-empty -q -m init
hug rb main --dry-run
# Expected: "Already on 'main' — did you mean 'hug rb origin/main'..."
cd / && rm -rf "$_smoke"
```

Dirty-tree remediation:
```bash
_smoke=$(mktemp -d)
cd "$_smoke" && git init -q
echo x > a && git add a && git commit -q -m init
echo y >> a  # unstaged
echo z > b && git add b  # staged
hug rb main 2>&1 || true
# Expected: error with "hug w wip", "hug w wipe-all", "hug w wipe <file>"
cd / && rm -rf "$_smoke"
```

- [ ] **Step 11: Commit**

```bash
git add git-config/lib/hug-git-state git-config/bin/git-rb .github/copilot-instructions.md tests/lib/test_hug_git_state.bats tests/unit/test_rb.bats
git commit -m "fix(hug-rb,hug-git-state): correct dirty-tree remediation + same-name no-op pointer (closes #208)

WHY: Two independent UX correctness bugs in hug rb and its dirty-tree guard.
Both cost operator time during a routine main-sync workflow:

  (a) 'hug rb main' while already on main silently no-ops with no hint that
      origin/main was the intended target — the documented example
      ('hug rb main # Rebase onto main') sends users straight into this trap.
  (b) check_working_tree_clean's dirty-tree error suggested three non-existent
      commands (git w-backup, git w-discard-all, git w-discard <file>).
      Worse: even if those names existed as hug w-* equivalents, 'discard'
      defaults to UNSTAGED-ONLY — using it as the 'clean the tree' remedy
      leaves staged changes intact and the guard still firing, trapping the
      user in a loop. The bug is operation-level, not prefix-level.

WHAT: Three coordinated fixes in one commit:

  1. check_working_tree_clean: replaced the three bad suggestions with
     hug w wip \"<msg>\" / hug w wipe-all / hug w wipe <file>. wipe[-all]
     discards BOTH staged and unstaged, so following the remedy actually
     produces the clean tree the guard demands. Added an inline comment
     explaining the operation-level reasoning so the next maintainer
     doesn't 'fix' it back to discard.

  2. check_file_unstaged: kept on 'discard' (changed only the prefix from
     'git' to 'hug'). This function only asserts UNSTAGED state, so
     discard's unstaged-only default IS correct here — a maintainer
     reviewing both fixes side-by-side needs the comment in #1 to
     understand why the two functions diverge.

  3. hug rb same-name no-op: detects the upstream tracking ref via
     git rev-parse --abbrev-ref --symbolic-full-name @{u} and prints
     'did you mean hug rb <upstream>' when one is configured. Wording is
     'upstream tracking ref' (not 'fetched remote tip') because @{u}
     reflects whatever was last fetched, which may be stale. Falls back
     to the bare no-op when no upstream is set. Detection is textual —
     refs/heads/main or other equivalent refs fall through to the bare
     message, which is correct.

HOW: @{u} is the canonical git mechanism for 'the upstream this branch
tracks' — exactly the ref the user meant to type. Abbreviated form
(--)abbrev-ref --symbolic-full-name) gives 'origin/main' rather than a
full refname, drop-in for the suggestion text. The detection runs only
on the already-existing same-name no-op path, so the cost is one git
rev-parse per occurrence — negligible.

IMPACT: hug rb's same-name case is now informative without becoming
magical (no silent rewrite — the user still types the suggested command
themselves). The dirty-tree remediation actually works: following either
wipe suggestion leaves the tree clean and hug rb succeeds on retry.
Every runtime 'git w-' string is gone; users never copy-paste a command
that doesn't exist. The copilot-instructions.md doc fix (.github/) keeps
the project's own AI tooling aligned with the actual command vocabulary.

Design ref: docs/superpowers/specs/2026-07-14-visibility-batch-207-208-design.md (#208, decisions D8-D10)."
```

---

## Task 4: `hug a` post-stage index summary (closes #207 root cause)

**Goal:** Add staging-time visibility to `hug a` so agents and humans see how many files are staged AFTER their `hug a` invocation, in the context where they can still act on it. This is the prevention mechanism the #207 root-cause analysis identified — the index was already populated from a soft-reset before the user ran `hug a file.txt`, and nothing told them.

**Why this is in this PR (U1 accepted):** Task 2's `hug c` preview is honestly a RECOVERY aid, not a gate. The user accepted codex's challenge U1 and asked for staging-time visibility to address the root cause. This task delivers it: a one-line index summary printed by `hug a` after staging.

**Files:**
- Modify: `git-config/bin/git-a` (add post-stage summary)
- Test: `tests/unit/test_add.bats` (extend — file likely exists; if not, create)

**Acceptance Criteria:**
- [ ] After `hug a <file>` succeeds, stderr contains a line like: `Staged 1 file. Index now has N file(s) staged total.` (where N includes files staged by prior commands).
- [ ] After `hug a` (no args, stages all tracked modifications), stderr contains the same shape with the count of newly-staged files.
- [ ] When the index has 0 files staged total after `hug a` (e.g., nothing to stage), the summary still prints: `Staged 0 files. Index now has 0 file(s) staged total.`
- [ ] `--quiet` / `HUG_QUIET` suppresses the summary (same contract as other chatter — call-site gate).
- [ ] When `git add` fails, no summary prints (early exit path).
- [ ] Summary goes to stderr; stdout is empty (consistent with `hug a`'s current behavior).

**Verify:** `make test-unit TEST_FILE=test_add.bats` → all tests pass.

**Steps:**

- [ ] **Step 1: Check whether `tests/unit/test_add.bats` exists**

```bash
ls tests/unit/test_add.bats 2>&1
```

If missing, create it; if present, extend it. (Plan handles both.)

- [ ] **Step 2: Write the failing tests**

Append (or create) `tests/unit/test_add.bats`:

```bash
@test "hug a: prints post-stage index summary" {
  cd "$(create_test_repo)" || exit 1
  echo "content" > new_file.txt
  run hug a new_file.txt
  assert_success
  assert_output --partial "Staged 1 file."
  assert_output --partial "Index now has 1 file(s) staged total."
}

@test "hug a: summary reflects cumulative index state" {
  cd "$(create_test_repo)" || exit 1
  # Pre-stage one file
  echo "first" > a.txt
  hug a a.txt 2>/dev/null  # quiet to suppress first summary
  # Now stage a second — total should be 2
  echo "second" > b.txt
  run hug a b.txt
  assert_success
  assert_output --partial "Staged 1 file."
  assert_output --partial "Index now has 2 file(s) staged total."
}

@test "hug a: with no args, counts all newly-staged modifications" {
  cd "$(create_test_repo_with_history)" || exit 1
  # Modify two existing tracked files
  echo "mod1" >> README.md
  echo "more" >> "$(ls *.md | grep -v README || echo README.md)" 2>/dev/null || echo "mod2" >> README.md
  # Run hug a (no args) — stages all tracked modifications
  run hug a
  assert_success
  # Should report at least 1 newly-staged file
  assert_output --partial "Staged"
  assert_output --partial "file(s) staged total."
}

@test "hug a: --quiet suppresses the index summary" {
  cd "$(create_test_repo)" || exit 1
  echo "content" > quiet_file.txt
  run hug a quiet_file.txt --quiet
  assert_success
  refute_output --partial "Staged"
  refute_output --partial "file(s) staged total."
}

@test "hug a: empty stage still prints summary" {
  cd "$(create_test_repo)" || exit 1
  # Run hug a with nothing to stage
  run hug a
  assert_success
  assert_output --partial "Staged 0 files."
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
make test-unit TEST_FILE=test_add.bats
```

Expected: new tests FAIL — `hug a` doesn't print any summary today.

- [ ] **Step 4: Implement the post-stage summary in `git-a`**

Open `git-config/bin/git-a`. The current script has 4 `exec git add ...` exit points (lines 126, 152, 156, 158). We need to intercept ALL of them so the summary fires regardless of which path runs.

The cleanest approach: replace the `exec git add ...` calls with a helper function that runs `git add`, captures the before/after staged counts, and prints the summary.

Add this helper function near the top of the file (after the library sources, before the flag-parsing loop):

```bash
# Stage files and print a one-line index summary.
# WHY (elifarley/hug-scm#207): an agent running `hug a file.txt` after a
# soft-reset has no signal that the index was already populated with N other
# files from the reset. The summary surfaces the cumulative count at the
# moment the user can still act on it (unstage, inspect, abort) — making
# this the PREVENTION counterpart to hug c's RECOVERY preview.
# Usage: hug_add_with_summary <git add args...>
# Output: stderr summary line on success, suppressed by HUG_QUIET.
hug_add_with_summary() {
  # Capture pre-stage count (files in index vs HEAD)
  local _before
  _before=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')

  # Run the actual git add (forward all args, honor errors under set -e)
  git add "$@"

  # Capture post-stage count
  local _after
  _after=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')

  # Newly-staged = after - before (clamped at 0; can be negative if git add
  # unstaged something, but that's not a real add path)
  local _new=$(( _after > _before ? _after - _before : 0 ))

  # Print summary to stderr, suppressed by HUG_QUIET (call-site gate,
  # consistent with hug c preview — do NOT check HUG_QUIET inside print_list
  # or other helpers; see eng review finding E1).
  if [[ -z "${HUG_QUIET:-}" ]]; then
    printf 'Staged %d file%s. Index now has %d file(s) staged total.\n' \
      "$_new" "$([[ $_new -eq 1 ]] && echo '' || echo 's')" "$_after" >&2
  fi
}
```

Then replace the four `exec git add ...` exit points:

**Line 126** (`--from-file` / `--from-commit` path):
```bash
# OLD: exec git add "${files[@]}"
# NEW:
hug_add_with_summary "${files[@]}"
```

**Line 152** (interactive file selection path):
```bash
# OLD: exec git add "${files[@]}"
# NEW:
hug_add_with_summary "${files[@]}"
```

**Line 156** (no-args `git add -u` path):
```bash
# OLD: test ${#remaining_args[@]} -eq 0 && exec git add -u
# NEW:
if [[ ${#remaining_args[@]} -eq 0 ]]; then
  hug_add_with_summary -u
  exit 0
fi
```

**Line 158** (explicit args path):
```bash
# OLD: exec git add "${remaining_args[@]}"
# NEW:
hug_add_with_summary "${remaining_args[@]}"
```

Note: removing `exec` means the script continues after `git add` rather than replacing the process. Since the summary is the last thing each path does, add explicit `exit 0` where the original used `exec` (as shown above for the `-u` path; the function-call paths naturally fall through to end-of-script).

- [ ] **Step 5: Run tests to verify they pass**

```bash
make test-unit TEST_FILE=test_add.bats
```

Expected: all tests PASS.

- [ ] **Step 6: Run full unit suite to confirm no regressions**

```bash
make test-unit
```

Expected: all tests PASS. (Other tests may assert on `hug a`'s output; if any break, update them per the new summary line. Most existing tests will use `--quiet` or `2>/dev/null` already, so impact should be minimal.)

- [ ] **Step 7: Manual smoke test**

```bash
_smoke=$(mktemp -d)
cd "$_smoke" && git init -q
git config user.email t@t; git config user.name t
echo "base" > base.txt && git add base.txt && git commit -q -m init
# Simulate soft-reset: stage multiple files, soft-reset, then hug a one more
echo "a" > a.txt && git add a.txt
echo "b" > b.txt && git add b.txt
git reset --soft HEAD~0 2>/dev/null || true  # keeps index populated
echo "target" > target.txt
hug a target.txt
# Expected: "Staged 1 file. Index now has N file(s) staged total." where N > 1
# This is the prevention signal — user sees they're not staging into an empty index.
cd / && rm -rf "$_smoke"
```

- [ ] **Step 8: Commit**

```bash
git add git-config/bin/git-a tests/unit/test_add.bats
git commit -m "feat(hug-a): print post-stage index summary (closes #207 root cause)

WHY: The #207 incident root cause was index-state blindness — an agent ran
'hug a file.txt' after a soft-reset that had populated the index with 13
other files, and nothing told them. The Task 2 hug c preview is a RECOVERY
aid (output arrives post-commit, too late to prevent); this task adds the
PREVENTION counterpart: a one-line summary printed by hug a AFTER staging,
showing how many files were just staged AND how many total are in the index.
At this moment the user/agent can still act (unstage, inspect, abort).

WHAT: hug_add_with_summary() helper wraps every git add exit point in git-a
(four paths: --from-file/--from-commit, interactive, no-args, explicit).
Captures staged-file count before and after, prints:
  Staged <new> file(s). Index now has <total> file(s) staged total.
Suppressed by --quiet / HUG_QUIET (call-site gate, same pattern as the
hug c preview — do NOT check HUG_QUIET inside shared helpers per eng
review E1).

HOW: Two git diff --cached --name-only | wc -l calls (sub-millisecond each,
index-only reads). The 'newly-staged' count is after - before, clamped at 0.
The pluralization ('file' vs 'files') uses a small bash conditional so the
output reads naturally for the 1-file case. Removing 'exec' from the four
exit paths means the script continues to the summary line; exit 0 added
where needed.

IMPACT: Closes the prevention gap that the hug c preview alone couldn't
address. An agent reading 'Index now has 14 files staged total' after
running 'hug a file.txt' (expecting 1) immediately knows to inspect/unstage
before reaching for hug c. Together with Task 2's recovery preview, this
closes the full #207 hazard class: staging-time prevention + commit-time
recovery. HONEST framing documented in both code comments.

Related: #190 (cmoda dirty-tree docs) — follow-up worktree per autoplan
commitment U3.

Design ref: docs/superpowers/specs/2026-07-14-visibility-batch-207-208-design.md (#207, U1 accepted)."
```

---
## Final Validation (after all four commits)

- [ ] `make test-full` — **NOT `make test`** (which only runs unit+integration, skipping lib tests). `make test-full` runs test-check + test-lib-py + test-lib + test-unit + test-integration. Since this plan adds lib tests (`test_hug-arrays.bats`, `test_hug-git-state.bats`), `make test` alone would NOT run them and silently pass with new code untested.
- [ ] `grep -rn 'git w-' git-config/ .github/` returns zero runtime matches.
- [ ] Manual repro #207 prevention: stage 2 files manually, then `hug a file3.txt` — stderr shows `Staged 1 file. Index now has 3 file(s) staged total.` (the prevention signal — user sees they're staging into a populated index).
- [ ] Manual repro #207 recovery: stage 12 files, `hug c -m x` — preview block appears on stderr before `[main <hash>]`.
- [ ] Manual repro #208 same-name: `hug rb main` on main with upstream — pointer message with `hug fetch` wording.
- [ ] Manual repro #208 remediation: dirty tree + `hug rb origin/main` — `wipe` suggestions.
- [ ] **Remediation actually works:** run `hug w wipe-all -f` after the error, verify tree is now clean, re-run `hug rb origin/main` and verify it succeeds.
- [ ] `hug bpush` (with `--track` if needed) to publish the branch.
- [ ] Open PR closing #207 and #208. PR body should also **reference #190 as "related"** (not "closes") — the `hug c` preview establishes a precedent #190's `cmoda` runtime guard may follow, but #190 is not closed by this PR. **Also note the chatter-string change** in the PR description: `"Committing staged changes..."` → `"Committing staged file(s) (N):"`, plus a new summary line in `hug a` stderr. Any external script grepping either command's stderr for old strings will need to update its pattern. (Internal: `hug c`/`hug a` are documented as interactive; the in-repo test assertions are updated by Tasks 2 and 4.)
- [ ] **After merge:** file a follow-up issue for T6 (`-a`/`--all`/`--only`/`--patch` detection in `hug c` — abort with educational message pointing at explicit-stage hug commands).

## Out of Scope (deferred)

- #209 (`hug w unwip` exit code) — separate worktree / PR.
- #190 / #191 (`cmoda` dirty-tree docs + runtime guard) — **commitment (U3 accepted):**
  this PR ships the `hug c` preview precedent and the corrected dirty-tree
  remediation pattern. #190 (cmoda docs update) and #191 (cmoda runtime guard
  design) follow immediately as the next worktree/PR after this one merges,
  applying the same operation-level remediation thinking to the `cmoda`/`cmod`
  family. Not closed by this PR — but the policy is now explicit and the
  implementation pattern is proven.
- `hug ca` / `hug caa` preview — not motivated by any incident.
- Items-with-newlines handling in `print_list` — pre-existing.

---

<!-- AUTONOMOUS DECISION LOG -->

## /autoplan CEO Phase Outputs

### NOT in scope (CEO confirmation)

| Item | Why deferred | Principle |
|------|-------------|-----------|
| `hug ca` / `hug caa` preview | No incident; `ca`'s purpose is "commit everything" so preview would be noise. Codex flagged this as incoherent under the stated "prevent unintended commits" promise (X4) — see User Challenge U2 at the final gate. | YAGNI (P3) |
| Sweep all dirty-tree guards for stale remediation | Codex grep already confirmed only `hug-git-state` prints bad strings at runtime. Done. | P2 |
| `hug help h back` doc audit (#196 class) | Separate issue, has its own thread. | P3 |
| `print_list --json` | `print_list` is human-chatter by design. | YAGNI |
| `--preview` skip flag | `--quiet` already exists. | YAGNI |

### What already exists (leverage map)

| Sub-problem | Existing code reused |
|------------|---------------------|
| Render capped list | `print_list` (extended, not rebuilt) |
| Detect staged files | `has_staged_changes`, `git diff --cached --name-only` |
| Detect upstream ref | `git rev-parse @{u}` |
| Dirty-tree guard | `check_working_tree_clean` (fixed in-place) |
| Same-name no-op | existing `current_branch == target_branch` branch |
| Stderr printers | `info`, `warning`, `error`, `gum_log` (HUG_QUIET-aware) |
| Test repo with upstream | `create_test_repo_with_remote_upstream` at test_helper.bash:967 |

No DRY violations. No rebuilding of existing flows.

### Dream state delta

```
CURRENT (today)                  THIS PLAN (after merge)            12-MONTH IDEAL
─────────────                    ───────────────────                ──────────────
hug c silently commits           hug c shows staged-file preview    Every state-modifying
whatever's staged. Post-hoc      before commit; hug rb points       hug command previews
"N files changed" is the         at upstream on same-name no-op;    its blast radius BEFORE
only signal. hug rb silently     dirty-tree remediation actually    acting; every guard's
no-ops on same-name; dirty-      unblocks the user.                 remediation is operationally
tree errors suggest non-existent                                    correct; "Already on X"
commands.                                                           always has a productive
                                                                    next step.
```

Trajectory: plan moves toward the ideal. 3 of 4 ideals addressed. The "every command" sweep is correctly out of scope.

### Implementation alternatives considered (0C-bis)

| Approach | Effort | Risk | Pros | Cons | Verdict |
|----------|--------|------|------|------|---------|
| A. Three-commit batch (the plan) | S | Low | Atomic story; reusable infra; ships together | PR mixes lib + 2 fixes | **CHOSEN** |
| B. Minimal-viable single commit | S | Low | Smallest diff; no blast radius | Duplicates cap pattern next time; violates lib principle | Rejected (P4 DRY) |
| C. Full commit-family audit | M | Medium | Closes hazard class in one pass | Touches commands with no incident (YAGNI); larger PR | Rejected (P3 + spec D5) |

Auto-decided per autoplan P3 (pragmatic) + P5 (explicit-over-clever). APPROACH A selected.

### Mode selection

**SELECTIVE EXPANSION** (default for "feature enhancement or iteration on existing system"). Complexity check: 8 files touched (6 modified + 2 new tests) — right at the threshold but each file has clear single responsibility. No expansions accepted.

### Temporal interrogation (decision preview for implementer)

| Hour | Decisions needed | Resolved in plan? |
|------|-----------------|-------------------|
| 1 (foundations) | `print_list` callers all pass Title only — strict superset | ✓ verified by grep |
| 2-3 (core) | `_has_staged` dedup; `cap=$((10#$_cap_raw))` octal trap; `@{u}` abbrev-form | ✓ in code blocks |
| 4-5 (integration) | `create_test_repo_with_remote_upstream` exists and sets upstream | ✓ verified |
| 6+ (tests/polish) | "no `git w-` runtime strings remain" final grep | ✓ in validation |

No open questions for the user from temporal analysis.

## CEO DUAL VOICES — CONSENSUS TABLE

```
═══════════════════════════════════════════════════════════════════════
  Dimension                                    Claude   Codex   Consensus
  ──────────────────────────────────────────── ──────── ─────── ─────────
  1. Premises valid?                            PARTIAL  NO      DISAGREE
  2. Right problem to solve?                    YES      NO      DISAGREE
  3. Scope calibration correct?                 YES      NO      DISAGREE
  4. Alternatives sufficiently explored?        YES      YES     CONFIRMED
  5. Competitive/market risks covered?          N/A      N/A     N/A
  6. 6-month trajectory sound?                  YES      PARTIAL DISAGREE
═══════════════════════════════════════════════════════════════════════
Confirmed: 1. Disagree: 4. N/A: 1.
```

## Decision Audit Trail

| # | Phase | Decision | Classification | Principle | Rationale |
|---|-------|----------|---------------|-----------|-----------|
| 1 | CEO 0C-bis | Approve Approach A (three-commit batch) | Mechanical | P3, P5 | DRY + explicit; B duplicates pattern, C overreaches |
| 2 | CEO 0D | Mode: SELECTIVE EXPANSION | Mechanical | default | Iteration on existing commands |
| 3 | CEO 0D | Defer `hug ca`/`caa` preview | Mechanical | P3 YAGNI | No incident; surfaced as User Challenge U2 (codex X4) |
| 4 | CEO 0D | Defer `print_list --json` | Mechanical | YAGNI | Helper is human-chatter by design |
| 5 | CEO C1 | Add `HUG_QUIET` gate to `print_list` | Mechanical | correctness | Every lib printer honors HUG_QUIET; print_list broke contract |
| 6 | CEO C2 | Enumerate all 6 test assertions | Mechanical | correctness | Subagent found 5 plan missed |
| 7 | CEO C3 | Delete `--allow-empty` line-53 assertion | Mechanical | correctness | Preview skipped for empty commits (D7) |
| 8 | CEO C5 | Use file-redirection for stream-discipline test | Mechanical | correctness | Chained-`hug c` pattern was broken |
| 9 | CEO C6 | Confirm `wip` is correct semantic for old `w-backup` | Mechanical | verified | No `hug w backup` exists; `wip` parks changes restorably |
| 10 | CEO C8 | Add #190 to PR description as "related" | Mechanical | correctness | #190 not closed by this PR; precedent only |
| 11 | CEO X6 | Confirm #209 correctly excluded | Mechanical | confirmed | Different blast radius, different PR |
| 12 | CEO X9 | Note "no outcome metric" critique, defer | Mechanical | scope | Proxies acceptable for v1 |

### Surfaced at Final Gate (NOT auto-decided)

| ID | Source | Issue | Classification |
|----|--------|-------|---------------|
| U1 | Codex X1+X2+X3 | "Preview isn't actionable; root cause is index-state, not rendering" | **User Challenge** (but user already chose visibility-only in Q1; codex is re-litigating) |
| U2 | Codex X4 + Claude C7 | `hug ca`/`caa` exclusion incoherent under stated promise | **Taste decision** |
| U3 | Codex X5 | #190/#191 excluded for implementation reason, not customer-risk | **User Challenge** |
| U4 | Codex X7 | `hug rb` suggestion conflates upstream with intent | **Taste decision** |
| U5 | Codex X8 | Release structure: urgent fix hostage to debatable one | **User Challenge** |

---

## /autoplan Eng Phase Outputs

### Architecture ASCII dependency graph

```
                       ┌─────────────────────────────┐
                       │   git-config/lib/hug-arrays │
                       │   ┌──────────────────────┐  │
                       │   │ print_list [NEW API] │  │
                       │   │  + --cap N           │  │
                       │   │  + --more-hint T     │  │
                       │   │  + overflow guard    │  │
                       │   │  + no-title guard    │  │
                       │   │  + octal defuse      │  │
                       │   └──────────┬───────────┘  │
                       └──────────────┼──────────────┘
                                      │ sourced by (17 call sites incl.
                                      │ git-w-purge, hug-git-discard,
                                      │ hug-output — default behavior unchanged)
                   ┌──────────────────┼──────────────────┐
                   ▼                  ▼                  ▼
        ┌──────────────────┐ ┌────────────────┐ ┌────────────────┐
        │  git-config/bin/ │ │ git-config/lib/│ │ git-config/bin/│
        │     git-c        │ │ hug-git-state  │ │    git-rb      │
        │ ┌──────────────┐ │ │                │ │                │
        │ │ NEW: preview │ │ │ FIX:           │ │ FIX: same-name │
        │ │ calls        │ │ │ check_working_ │ │ no-op +@{u}    │
        │ │ print_list   │ │ │ tree_clean     │ │ pointer, with  │
        │ │ --cap 10     │ │ │ (wipe not      │ │ rev-parse      │
        │ │ + HUG_QUIET  │ │ │  discard)      │ │ resolvability  │
        │ │ call-site    │ │ │                │ │ check          │
        │ │ gate         │ │ │ FIX:           │ │                │
        │ │ + dedup      │ │ │ check_file_    │ │ uses check_    │
        │ │ _has_staged  │ │ │ unstaged       │ │ working_tree_  │
        │ └──────────────┘ │ │ (prefix only)  │ │ clean()        │
        └──────────────────┘ └────────────────┘ └────────────────┘
                   │                  │
                   ▼                  ▼
        ┌──────────────────────────────────────────┐
        │ .github/copilot-instructions.md:467      │
        │ FIX: git w-discard → hug w discard       │
        └──────────────────────────────────────────┘

Tests:
  tests/lib/test_hug-arrays.bats (EXTEND — file already exists, 4 print_list tests)
  tests/lib/test_hug-git-state.bats (NEW or extend)
  tests/unit/test_commit.bats (extend, 6 assertion updates + 5 new tests)
  tests/unit/test_rb.bats (extend, 3 new tests)
```

### ENG DUAL VOICES — CONSENSUS TABLE

```
═══════════════════════════════════════════════════════════════════════
  Dimension                                    Claude   Codex   Consensus
  ──────────────────────────────────────────── ──────── ─────── ─────────
  1. Architecture sound?                        YES      YES     CONFIRMED
  2. Test coverage sufficient?                  PARTIAL  NO      DISAGREE
  3. Performance risks addressed?               YES      YES     CONFIRMED
  4. Security threats covered?                  YES      PARTIAL DISAGREE
  5. Error paths handled?                       YES      YES     CONFIRMED
  6. Deployment risk manageable?                YES      YES     CONFIRMED
═══════════════════════════════════════════════════════════════════════
Confirmed: 4. Disagree: 2.
```

### Eng Findings reconciliation (Claude vs Codex)

| # | Source | Finding | Severity | Verdict |
|---|---|---|---|---|
| E1 | Claude | HUG_QUIET in print_list breaks dry-run callers | CRITICAL | **Fixed**: reverted C1, gate at call site instead |
| E2 | Claude | sed -n line-range test fragility | HIGH | **Fixed**: source full files |
| E3 | Claude | Bare-repo `create_test_repo` assumption | HIGH | **Wrong**: helper creates initial commit (line 169-171); dismissed |
| E4 | Claude | Operator precedence in test setup | MEDIUM | **Fixed**: explicit if/else, use README.md directly |
| E5 | Claude | Dirty-tree test only creates unstaged | MEDIUM | **Fixed**: stage new_staged.txt + modify README.md |
| E6 | Codex | Wrong test filename (`_` vs `-`) | BLOCKER | **Fixed**: extend existing test_hug-arrays.bats |
| E7 | Codex | Missing-value test asserts wrong message | BLOCKER | **Fixed**: split into 2 tests (missing vs non-integer) |
| E8 | Codex | Preview not reliable under -a/--only/--patch | HIGH | **Noted**: documented as ADVISORY in code comment |
| E9 | Codex | Lexical-sort cap test assertion wrong | HIGH | **Fixed**: zero-padded filenames |
| E10 | Codex | Bash arithmetic overflow on huge caps | HIGH | **Fixed**: 6-digit length guard |
| E11 | Codex | set -u failure when no title after flags | HIGH | **Fixed**: no-title guard |
| E12 | Codex | Command injection via @{u} / $file | HIGH | **Noted**: git ref-name rules already prevent; defensive comment only |
| E13 | Codex | Semantic-vs-textual same-name detection; stale upstream | MEDIUM | **Fixed**: require rev-parse to succeed; clarify comment |
| E14 | Codex | Remediation tests don't verify remedy actually works | MEDIUM | **Fixed**: added "run wipe-all, verify clean" step in validation |
| E15 | Codex | `make test` excludes lib tests | MEDIUM | **Fixed**: mandate `make test-full` |

### Test plan artifact

Written to: `~/.gstack/projects/elifarley-hug-scm/fix-207-208-visibility-test-plan-20260714.md` (75 lines). Coverage matrix maps every new codepath to a test. One deferred gap (G1: "following wipe remedy cleans tree" — manual repro only; acceptable because it tests existing `git-w-wipe-all`, not this plan's changes).

## Decision Audit Trail (Eng additions)

| # | Phase | Decision | Classification | Principle | Rationale |
|---|-------|----------|---------------|-----------|-----------|
| 13 | Eng E1 | Revert CEO C1 (HUG_QUIET in print_list); gate at call site | Mechanical | correctness | print_list used in dry-run data paths; silence would lose data |
| 14 | Eng E2 | Source full library files in tests, not sed -n slices | Mechanical | maintainability | line-range slices drift on edits |
| 15 | Eng E4/E5 | Use explicit if/else + README.md in test setup | Mechanical | correctness | operator-precedence footgun |
| 16 | Eng E6 | Extend existing test_hug-arrays.bats, don't create new | Mechanical | DRY | file already exists with 4 print_list tests |
| 17 | Eng E7 | Split missing-value vs non-integer --cap tests | Mechanical | correctness | two distinct error branches |
| 18 | Eng E9 | Zero-pad capfile names in cap test | Mechanical | determinism | lexical sort != numeric sort |
| 19 | Eng E10 | 6-digit cap length guard (overflow defense) | Mechanical | correctness | bash arithmetic silently wraps |
| 20 | Eng E11 | No-title guard (set -u safety) | Mechanical | correctness | `local title=$1` fails unbound |
| 21 | Eng E13 | Require rev-parse success on @{u} | Mechanical | correctness | stale upstream → bad suggestion |
| 22 | Eng E15 | Use `make test-full`, not `make test` | Mechanical | correctness | `make test` skips lib tests |

---

## /autoplan DX Phase Outputs

### Developer persona (auto-decided)

```
TARGET DEVELOPER PERSONA
========================
Who:       AI agent (and the human scripting Git workflows it automates)
Context:   Runs hug c / hug rb in automation scripts or interactively during
           routine branch sync, commit, rebase flows
Tolerance: Zero — agent runs commands non-interactively, can't read buried
           signals. Human tolerates ~5s of confusion.
Expects:   Stderr = chatter, stdout = data; --quiet works as documented;
           remediation text actually unblocks them.
```

### DX Scorecard

| # | Dimension | Score (0-10) | Notes |
|---|-----------|--------------|-------|
| 1 | Getting Started / TTHW | 9 | Plan doesn't touch install/onboarding |
| 2 | API/CLI Ergonomics | 9 | `--cap`/`--more-hint` guessable; `hug rb <upstream>` suggestion is copy-pasteable |
| 3 | Error Handling | 9 (was 5) | Dirty-tree remediation now works (`wipe` not `discard`); +`hug sl` pointer |
| 4 | Documentation | 8 | copilot-instructions.md fixed; inline comments thorough |
| 5 | Escape Hatches | 9 | `--quiet` (HUG_QUIET) gates preview at call site; `--allow-empty` skips |
| 6 | Dev Environment Friction | 9 | Test infrastructure reused, not rebuilt |
| 7 | Upgrade Path | 10 | Backward compatible for 17 existing callers; new flags opt-in |
| 8 | Observability | 8 | Preview block observable; stderr/stdout discipline preserved |

**Overall DX: 8.9/10** (estimated +1.4 from pre-plan baseline; largest gains in Error Handling and Documentation)

### DX DUAL VOICES — CONSENSUS TABLE

```
═══════════════════════════════════════════════════════════════════════
  Dimension                                    Claude   Codex   Consensus
  ──────────────────────────────────────────── ──────── ─────── ─────────
  1. Getting started < 5 min?                   YES      N/A     CONFIRMED
  2. API/CLI naming guessable?                  YES      YES     CONFIRMED
  3. Error messages actionable?                 YES      YES     CONFIRMED
  4. Docs findable & complete?                  YES      YES     CONFIRMED
  5. Upgrade path safe?                         YES      PARTIAL DISAGREE
  6. Dev environment friction-free?             YES      YES     CONFIRMED
═══════════════════════════════════════════════════════════════════════
Confirmed: 5. Disagree: 1.
```

### DX Findings reconciliation (Claude vs Codex)

| # | Source | Finding | Severity | Verdict |
|---|---|---|---|---|
| D-F4 | Claude | Advisory scope caveat absent from user-facing output | MEDIUM | **Taste decision** (T6 at gate) |
| D-F18 | Claude | Silent `git diff --cached` failure | LOW | **Taste decision** (T7 at gate) |
| D-F20 | Claude | Chatter string change breaks scripted greps | MEDIUM | **Fixed**: PR description note added |
| D-F22 | Claude | Test filename underscore vs hyphen | MEDIUM | **Fixed**: all refs now `test_hug-arrays.bats` |
| D-F25 | Claude | Duplicated test code blocks | LOW | **Fixed**: deleted leftover block |
| D-F26 | Claude | `make test-full` target existence | MEDIUM | **Confirmed exists** at Makefile:223 |
| D-X-P0 | Codex | Duplicated test block (markdown malformed) | BLOCKER | **Fixed**: deleted lines 188-285 |
| D-X-P1-1 | Codex | `--`-prefixed title backward compat | HIGH | **Noted** in contract doc; no existing caller affected |
| D-X-P1-2 | Codex | `--no-preview` escape hatch too coarse | HIGH | **Taste decision** (T8 at gate) |
| D-X-P1-3 | Codex | `hug rb` says "sync" without fetching | HIGH | **Taste decision** (T9 at gate) |
| D-X-P2 | Codex | Remediation lacks file-list pointer; preview lacks A/M/D/R | MEDIUM | **Partial fix**: added `hug sl` pointer; A/M/D/R deferred |

## Decision Audit Trail (DX additions)

| # | Phase | Decision | Classification | Principle | Rationale |
|---|-------|----------|---------------|-----------|-----------|
| 23 | DX D-F20 | Add chatter-string change note to PR description | Mechanical | backward compat | external scripts may grep old string |
| 24 | DX D-F22 | Standardize test filename to `test_hug-arrays.bats` | Mechanical | correctness | match actual existing file |
| 25 | DX D-F25/X-P0 | Delete duplicated test block | Mechanical | correctness | markdown rendering broken |
| 26 | DX X-P2 | Add `hug sl` pointer to dirty-tree remediation | Mechanical | observability | dev needs to see file list before deciding |
| 27 | DX X-P1-1 | Document `--`-prefix title contract (not silently break) | Mechanical | backward compat | no existing caller affected; contract explicit |

---

## /autoplan Cross-Phase Themes

**Theme 1: Test quality.** Surfaced independently in Eng (Claude E2 fragility, E4/E5 setup bugs; Codex E6 filename, E7 message-split, E9 lexical sort) and DX (Claude F22 filename, F25 duplication; Codex X-P0 duplication). **High-confidence signal:** the plan's test code needed significant rework across both phases. Now addressed: deterministic naming, full-file sourcing, split error cases, zero-padded cap test, no duplication.

**Theme 2: HUG_QUIET contract.** Surfaced in CEO (C1 — add to print_list) and Eng (E1 — revert, gate at call site instead). The contract tension between "print_list is data" vs "print_list is chatter" resolved in Eng's favor. **Single-phase decisions can be wrong; the dual-phase review caught the regression before it shipped.**

**Theme 3: Bash footguns.** Eng codex caught three (octal-literal overflow, set -u no-title failure, lexical-sort cap test). None were on Claude's radar. **Codex's adversarial depth paid off here.**

No other cross-phase themes. Each phase's other concerns were distinct.

---

## /autoplan Final Approval Gate Inputs

### User Challenges (both models agree plan direction should change — NOT auto-decided)

| ID | Source | Title | User's direction | Both models recommend | Why | If we're wrong, cost is |
|----|--------|-------|-----------------|----------------------|-----|------------------------|
| U1 | Codex CEO X1+X2+X3 | "Preview isn't actionable; root cause is index-state" | Visibility-only (Q1 choice) | Reconsider gate/preview model; address root cause at staging | Preview-then-immediately-commit gives no real decision point; agents receive output post-completion | User already chose A explicitly; revisiting opens the prompts-vs-visibility debate again |
| U3 | Codex CEO X5 | #190/#191 excluded for implementation reason | Defer to separate PR | Make commit-safety policy explicit; commit to #190 priority next | "Different command shape" is implementation reason, not customer-risk; safety-branded batch shouldn't leave safety gap | Splitting #190 out is fine if priority is committed; merging it in expands scope 2x |
| U5 | Codex CEO X8 | Release structure | Three-commit batch | Ship urgent fix (#208 remediation) independently of debatable preview model | Correcting non-existent commands shouldn't wait behind a new print_list API and a controversial safety model | Decoupling adds review overhead; the three commits share test infrastructure |

### Taste Decisions (reasonable people could disagree — auto-decided, surfaced)

| ID | Source | Title | Recommendation | Alternative |
|----|--------|-------|----------------|-------------|
| T6 | Claude DX F4 | Advisory scope caveat in user-facing preview output | **Skip** — code comment + commit msg suffice; adding `(advisory)` suffix adds noise to every preview | Add unconditional `(advisory — staged index snapshot)` suffix, OR detect `-a`/`--all`/`--only`/`--patch` and annotate |
| T7 | Claude DX F18 | Silent `git diff --cached` failure observability | **Skip** — `|| true` is correct (preview never blocks); failure is extremely rare; adding warning adds noise | Add `warning "Could not list staged files (preview skipped)"` on failure path |
| T8 | Codex DX P1-2 | `--no-preview` / `HUG_COMMIT_PREVIEW=0` escape hatch | **Skip** — `--quiet` + `2>/dev/null` cover the use cases; new flag is YAGNI | Add `--no-preview` flag and `HUG_COMMIT_PREVIEW=0` env var; document in `hug c --help` |
| T9 | Codex DX P1-3 | `hug rb` "sync" wording | **Tighten** — change "sync with the upstream tracking ref" to "rebase onto the upstream tracking ref (run `hug f` first if you need fresh commits)" | Leave wording as-is |
| U2 | Codex CEO X4 + Claude C7 | `hug ca`/`caa` exclusion | **Defer** — no incident; `ca`'s purpose is "commit everything" so preview is noise | Include `ca`/`caa` preview in this PR |
| U4 | Codex CEO X7 | `hug rb` suggestion conflates upstream with intent | **Ship as-is** — detection is textual and requires rev-parse success; wording can be tightened via T9 | Drop the suggestion entirely; just fix the remediation text |

### Auto-Decided: 27 decisions (see Decision Audit Trail above)

### Review Scores Summary
- **CEO:** Approach A (three-commit batch) approved; mode SELECTIVE EXPANSION; 5 scope expansions deferred
- **CEO Voices:** Codex 9 concerns (3 user challenges, 2 taste, 4 mechanical), Claude 8 findings (1 critical, 4 high, 1 false alarm, 2 minor). Consensus 1/6 confirmed.
- **Design:** SKIPPED (no UI scope detected)
- **Eng:** Architecture sound; test plan artifact written; 3 bash footguns caught (overflow, set -u, lexical sort)
- **Eng Voices:** Codex 10 findings (2 blockers, 5 high, 3 medium — all fixed), Claude 6 findings (1 critical, 2 high, 3 medium — all fixed or dismissed). Consensus 4/6 confirmed.
- **DX:** Overall 8.9/10 (+1.4 from baseline); no regressions; largest gains in Error Handling (+4) and Documentation (+2)
- **DX Voices:** Codex 5 findings (1 P0 blocker fixed, 3 P1 taste, 1 P2 partial-fix), Claude 8 findings (0 critical, 4 medium fixed, 3 low). Consensus 5/6 confirmed.

### Deferred to TODOS.md (or future issues)

- `hug ca` / `hug caa` preview (T6/U2) — log as future enhancement if an incident surfaces
- `--no-preview` flag / `HUG_COMMIT_PREVIEW=0` env (T8) — log as future agent-ergonomics enhancement
- A/M/D/R status codes in preview (Codex DX P2) — log as future observability enhancement
- #190 / #191 cmoda dirty-tree docs + runtime guard (U3) — already open as separate issues; commit to priority
- #209 hug w unwip exit code — already excluded, separate worktree/PR
- `hug help h back` doc audit (#196 class) — separate issue

### Implementation Tasks (aggregated across phases)

The plan's three tasks (Task 1, 2, 3) are the implementation units. No additional tasks were generated by the review phases — all findings were folded back into the existing tasks' steps and acceptance criteria. The native task list (Tasks #11, #12, #13) reflects this structure.

---

