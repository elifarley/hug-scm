# Visibility Batch (#207 + #208) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close #207 (silent-commit hazard on `hug c`) and #208 (`hug rb` same-name no-op + dirty-tree remediation text suggests non-existent commands) with three atomic commits in a single PR.

**Architecture:** Add an optional `--cap` / `--more-hint` API to the existing `print_list` helper (lib infrastructure, default behavior unchanged), then thread it into `hug c` as a pre-commit staged-file preview. Separately, fix the dirty-tree remediation strings in `hug-git-state` (replacing operation-wrong `discard` suggestions with the correct `wipe` for full clean), and teach `hug rb`'s same-name no-op to point at the upstream tracking ref via `git rev-parse @{u}`. All three land in one worktree.

**Tech Stack:** Bash, BATS test framework, hug-scm conventions (`info`/`error` to stderr, `gum_log` for color/TTY handling, Makefile test targets).

**Spec:** `docs/superpowers/specs/2026-07-14-visibility-batch-207-208-design.md`

---

## File Structure

### Files modified

| File | Purpose | Commit |
|------|---------|--------|
| `git-config/lib/hug-arrays` | Add `--cap` / `--more-hint` to `print_list` (lines 39-56) | 1 |
| `tests/lib/test_hug_arrays.bats` | New test file covering `print_list` API | 1 |
| `git-config/bin/git-c` | Replace `info "Committing staged changes..."` with capped preview (lines 82-92) | 2 |
| `tests/unit/test_commit.bats` | Update existing `--quiet` test + add preview tests | 2 |
| `git-config/lib/hug-git-state` | Fix remediation in `check_working_tree_clean` (lines 67-74) + `check_file_unstaged` (line 189) | 3 |
| `git-config/bin/git-rb` | Same-name no-op upstream pointer (lines 114-117) | 3 |
| `.github/copilot-instructions.md` | Fix line 467 stale `git w-discard` | 3 |
| `tests/unit/test_rb.bats` | Same-name no-op tests | 3 |
| `tests/lib/test_hug_git_state.bats` (or new) | Remediation-text assertions | 3 |

### Decomposition rationale

- **One file per concern.** `hug-arrays` is the list-rendering helper; `git-c` is the consumer; `hug-git-state` + `git-rb` are the rebase-side fixes.
- **No file grows large.** Each modification is bounded — `print_list` gains ~25 lines, `git-c` swaps ~5 lines for ~10, `git-rb` adds ~5 lines.
- **Existing patterns preserved.** All new tests use the established `create_test_repo*` helpers and `run` / `assert_output --partial` shape.

---

## Task 1: Extend `print_list` with `--cap` and `--more-hint`

**Goal:** Add an optional cap-and-overflow API to the existing `print_list` helper without changing default behavior for any existing caller.

**Files:**
- Modify: `git-config/lib/hug-arrays:39-56` (function `print_list`)
- Test: `tests/lib/test_hug_arrays.bats` (new file)

**Acceptance Criteria:**
- [ ] `print_list "Title" a b c` (no flags) still prints `Title (3):\n  a\n  b\n  c\n` to stderr.
- [ ] `print_list --cap 2 "Title" a b c d` prints title + first 2 items + overflow line `... (+2 more)` to stderr.
- [ ] `print_list --cap 2 --more-hint "see more" "Title" a b c d` prints overflow line `... (+2 more — see more)`.
- [ ] `print_list --cap 5 "Title" a b` (count ≤ cap) prints full list, no overflow line.
- [ ] `print_list --cap 0 "Title" a b c` is treated as no-cap (full list, no overflow).
- [ ] `print_list --cap 08 "Title" a b c d e f g h i` is treated as decimal 8 (no octal error).
- [ ] `print_list --more-hint "x" "Title" a b c` (hint without cap) ignores hint, prints full list.
- [ ] `print_list --cap` (no value after flag) prints error to stderr, returns 1.
- [ ] `print_list --cap 3 -- "--my title--" a b c d` parses title after `--` delimiter.
- [ ] All output goes to stderr; stdout is empty in every case.

**Verify:** `make test-lib TEST_FILE=test_hug_arrays.bats` → all tests pass.

**Steps:**

- [ ] **Step 1: Write the failing test file**

Create `tests/lib/test_hug_arrays.bats`:

```bash
#!/usr/bin/env bats

# Tests for hug-arrays library — specifically the print_list function and
# its --cap / --more-hint API added in the 207+208 visibility batch.
# print_list is a human-facing helper: ALL output goes to stderr.

load '../test_helper'

# We need to source hug-arrays to call print_list directly.
# It depends on hug-common for `info`/`error`/color helpers.
setup() {
  CMD_BASE="$(readlink -f "$BATS_TEST_DIRNAME/../../git-config/lib" 2>/dev/null)"
  [ -d "$CMD_BASE" ] || CMD_BASE="$BATS_TEST_DIRNAME/../../git-config/lib"
  . "$CMD_BASE/hug-common"
  . "$CMD_BASE/hug-arrays"
}

@test "print_list: no flags — full list to stderr" {
  run print_list "My Title" a b c
  assert_success
  assert_output --partial "My Title (3):"
  assert_output --partial "  a"
  assert_output --partial "  b"
  assert_output --partial "  c"
}

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

@test "print_list: --cap with no value — error, return 1" {
  run print_list --cap "T" a b
  assert_failure
  # The title "T" is consumed as the missing cap value -> error
  assert_output --partial "requires a value"
}

@test "print_list: -- delimiter — leading-dash title parsed" {
  run print_list --cap 2 -- "--my title--" a b c d
  assert_success
  assert_output --partial "--my title-- (4):"
  assert_output --partial "... (+2 more)"
}

@test "print_list: all output on stderr, stdout empty" {
  run bash -c 'source <(sed -n "1,80p" "'"$BATS_TEST_DIRNAME"'/../../git-config/lib/hug-common"); source <(sed -n "1,90p" "'"$BATS_TEST_DIRNAME"'/../../git-config/lib/hug-arrays"); print_list --cap 1 "T" a b 2>/dev/null'
  assert_success
  assert_output ""
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test-lib TEST_FILE=test_hug_arrays.bats
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
make test-lib TEST_FILE=test_hug_arrays.bats
```

Expected: all tests PASS.

- [ ] **Step 5: Run full lib test suite to confirm no regressions in other `print_list` callers**

```bash
make test-lib
```

Expected: all tests PASS. Existing callers (`hug-git-discard`, `hug-output`) pass `Title items...` only — no flags — so the new parser handles them identically to the old code (the `while` loop falls through immediately on the first non-flag arg).

- [ ] **Step 6: Commit**

```bash
git add git-config/lib/hug-arrays tests/lib/test_hug_arrays.bats
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
tests/lib/test_hug_arrays.bats. Sets up commit 2 (hug c preview) and
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

Append to `tests/unit/test_commit.bats` (and update the existing `--quiet` test). First, update the existing test at line 93:

```bash
@test "hug c: works with --quiet (minimal output)" {
  run hug c -m "Quiet commit" --quiet
  assert_success
  # The old "Committing staged changes..." line is gone; --quiet suppresses
  # the new preview too (gum_log helpers honor HUG_QUIET).
  refute_output --partial "Committing staged file(s)"
}
```

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
  # Stage 12 files to trigger the cap
  for i in $(seq 1 12); do
    echo "content $i" > "capfile_$i.txt"
  done
  hug a capfile_*.txt
  run hug c -m "cap test"
  assert_success
  assert_output --partial "Committing staged file(s) (12):"
  assert_output --partial "capfile_1.txt"
  refute_output --partial "capfile_12.txt"
  assert_output --partial "... (+2 more — run 'hug sls' for the full list)"
}

@test "hug c: --allow-empty with no staged files skips preview" {
  run hug c --allow-empty -m "empty"
  assert_success
  refute_output --partial "Committing staged file(s)"
}

@test "hug c: preview goes to stderr, git output to stdout" {
  echo "stream test" > stream_test.txt
  hug a stream_test.txt
  # Redirect stdout to a file; stderr to BATS captured output
  run bash -c 'hug c -m "stream test" 2>/dev/null'
  assert_success
  # stdout (now in $output via bash -c) must NOT contain the preview
  refute_output --partial "Committing staged file(s)"
  refute_output --partial "stream_test.txt"
  # And the inverse: with stderr merged but stdout dropped, preview IS visible
  run bash -c 'hug c -m "stream test 2" 2>&1 1>/dev/null' || true
  # (this second invocation fails because the file is already committed; that's fine)
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
# --allow-empty invocations with nothing staged (D7).
if $_has_staged; then
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
- [ ] `hug rb main` while on `main` with `origin/main` upstream prints `Already on 'main' — did you mean 'hug rb origin/main' to sync with the fetched upstream tracking ref?` to stderr, exits 0.
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
  cd "$(create_test_repo)" || exit 1
  echo "staged content" > staged_file.txt
  git add staged_file.txt
  echo "unstaged content" > unstaged_file.txt
  # unstaged_file.txt is untracked; tracked-modify instead:
  echo "modification" >> README.md 2>/dev/null || echo "modification" > tracked.txt && git add tracked.txt && echo "more" >> tracked.txt

  run check_working_tree_clean
  assert_failure
  assert_output --partial "hug w wip"
  assert_output --partial "hug w wipe-all"
  assert_output --partial "hug w wipe <file>"
  refute_output --partial "git w-"
  refute_output --partial "hug w discard-all"
}

@test "check_file_unstaged: error says hug w discard (not git w-discard)" {
  cd "$(create_test_repo)" || exit 1
  echo "unstaged content" >> README.md 2>/dev/null || {
    echo "base" > tracked.txt && git add tracked.txt && git commit -q -m init && echo "mod" >> tracked.txt
  }
  local target="README.md"
  [ -f README.md ] || target="tracked.txt"
  run check_file_unstaged "$target"
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
  cd "$(create_test_repo_with_remote_upstream)" || exit 1
  # Make the tree dirty (both staged and unstaged)
  echo "staged" > staged.txt
  git add staged.txt
  echo "base" > unstaged.txt && git add unstaged.txt && git commit -q -m init && echo "more" >> unstaged.txt

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
  # when one exists — the user almost certainly meant to sync with the
  # remote, not rebase a branch onto itself. Detection is textual
  # (current_branch == target_branch); equivalent refs like refs/heads/main
  # fall through to the bare no-op, which is correct behavior.
  # (elifarley/hug-scm#208)
  if [[ "$current_branch" == "$target_branch" ]]; then
    local _upstream
    _upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
    if [[ -n "$_upstream" && "$_upstream" != "$current_branch" ]]; then
      info "Already on '$target_branch' — did you mean 'hug rb $_upstream' to sync with the upstream tracking ref?"
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

## Final Validation (after all three commits)

- [ ] `make test` — full suite green.
- [ ] `grep -rn 'git w-' git-config/ .github/` returns zero runtime matches.
- [ ] Manual repro #207: stage 12 files, `hug c -m x` — preview block appears on stderr before `[main <hash>]`.
- [ ] Manual repro #208 same-name: `hug rb main` on main with upstream — pointer message.
- [ ] Manual repro #208 remediation: dirty tree + `hug rb origin/main` — `wipe` suggestions.
- [ ] `hug bpush` (with `--track` if needed) to publish the branch.
- [ ] Open PR closing #207 and #208.

## Out of Scope (deferred)

- #209 (`hug w unwip` exit code) — separate worktree / PR.
- #190 / #191 (`cmoda` dirty-tree docs + runtime guard) — different command shape.
- `hug ca` / `hug caa` preview — not motivated by any incident.
- Items-with-newlines handling in `print_list` — pre-existing.
