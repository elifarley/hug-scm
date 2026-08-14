# HUG_FAKE_CLOCK override — fix git-bc test flake: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the wall-clock-based CI flake in `tests/unit/test_bc.bats:334` (and the sibling flake at `:136` surfaced by Codex review) by introducing a `HUG_FAKE_CLOCK` env var (unix epoch) and a UTC-fixed, GNU/BSD-portable `hug-clock` library that wraps `date`, making `git-bc`'s auto-generated branch names deterministic in tests.

**Architecture:** New single-concern bash library `git-config/lib/hug-clock` exposes `hug_clock_now` and `hug_clock_epoch`. All output is UTC (`date -u`); the epoch formatter is GNU/BSD portable. Registered in `hug-common`'s `_hug_common_libs` array so every command that sources `hug-common` gets it. `git-bc`'s three direct `date` calls (lines 132, 159, 162) switch to `hug_clock_now`. Both flaky tests pin both `hug bc` calls to the same frozen epoch, making the collision provably reproducible. Zero behavior change when `HUG_FAKE_CLOCK` is unset (except the suffix timezone shifts local→UTC — documented, acceptable for a uniqueness hint).

**Tech Stack:** Bash, GNU/BSD `date`, BATS test framework, hug-scm lib/module conventions.

**Spec:** `docs/superpowers/specs/2026-07-10-bc-fake-clock-design.md` (updated post-Codex-review)

**Worktree:** `~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200` (all paths below are relative to its root)

**Codex review:** All 9 findings verified against ground truth. Findings #1 (TZ), #4 (second flake), #5 (separate-stderr), #9 (broken greps) are critical and incorporated below. #2 (BSD date), #3 (numeric-but-unformattable), #6 (arg validation), #7 (exact names), #8 (registration TDD) are incorporated as medium-priority hardening.

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `git-config/lib/hug-clock` | **Create** | Single-concern clock module: `hug_clock_now`, `hug_clock_epoch`, `_hug_clock_format_epoch`. Wraps `date -u` with GNU/BSD-portable `HUG_FAKE_CLOCK` override. UTC-fixed, fail-safe, arg-validated. |
| `git-config/lib/hug-common` | **Modify** (line 80-92) | Add `"hug-clock"` to `_hug_common_libs` array so all commands auto-source it. |
| `git-config/bin/git-bc` | **Modify** (lines 132, 159, 162) | Replace 3 direct `date` calls with `hug_clock_now`. |
| `tests/lib/test_hug_clock.bats` | **Create** | Pure-function lib tests for the override contract (9 cases, incl. TZ-independence and separate-stderr). |
| `tests/lib/test_hug-common.bats` | **Modify** | Add assertion that `hug-common` sources `hug-clock` (TDD guard for registration). |
| `tests/unit/test_bc.bats` | **Modify** (tests at lines 136 AND 334) | Both flaky tests set `HUG_FAKE_CLOCK`; the line-334 one is rewritten + renamed with exact-UTC-name assertions. |

---

### Task 1: Create `hug-clock` library with TDD

**Goal:** Create `git-config/lib/hug-clock` exposing `hug_clock_now` and `hug_clock_epoch` — UTC-fixed, GNU/BSD-portable, fail-safe, arg-validated — with a `HUG_FAKE_CLOCK` (unix epoch) override.

**Files:**
- Create: `git-config/lib/hug-clock`
- Test: `tests/lib/test_hug_clock.bats`

**Acceptance Criteria:**
- [ ] `hug_clock_now "%Y%m%d-%H%M"` with `HUG_FAKE_CLOCK=946684800` prints `20000101-0000` **regardless of host `TZ`** (UTC contract)
- [ ] `hug_clock_now "%S"` with `HUG_FAKE_CLOCK=946684800` prints `00`
- [ ] `hug_clock_now` with `HUG_FAKE_CLOCK` unset prints real UTC time equal to `date -u +"%Y%m%d-%H%M"`
- [ ] `hug_clock_now` with no args returns nonzero with a usage error on stderr
- [ ] `hug_clock_now` with invalid `HUG_FAKE_CLOCK=garbage` (via `run --separate-stderr`) → stdout is valid UTC time, `$stderr` contains `ignoring invalid HUG_FAKE_CLOCK`
- [ ] `hug_clock_now` with `HUG_FAKE_CLOCK=99999999999999999999` (numeric, unformattable) → stdout is real UTC time, `$stderr` contains `could not be formatted`
- [ ] `hug_clock_epoch` with `HUG_FAKE_CLOCK=946684800` prints exactly `946684800`
- [ ] `hug_clock_epoch` with `HUG_FAKE_CLOCK` unset prints an integer within ±5 of `date -u +%s`
- [ ] `hug_clock_epoch` with invalid `HUG_FAKE_CLOCK=garbage` prints an integer (real epoch)
- [ ] All 9 cases pass via `make test-lib TEST_FILE=test_hug_clock.bats`

**Verify:** `cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200 && make test-lib TEST_FILE=test_hug_clock.bats TEST_SHOW_ALL_RESULTS=1` → 9 passing tests, 0 failures

**Steps:**

- [ ] **Step 1: Write the failing test file `tests/lib/test_hug_clock.bats`**

Follow the exact pattern of `tests/lib/test_hug-fs.bats`: `load '../test_helper'` + `load '../../git-config/lib/hug-clock'`. Pure-function tests, no git repo setup. Uses `run --separate-stderr` for the invalid-override case (per Codex #5 — plain `run` merges streams and would contaminate the stdout assertion).

```bash
#!/usr/bin/env bats
# Tests for hug-clock library: testable current-time helper with HUG_FAKE_CLOCK override.
# All output is UTC; the override must render identically regardless of host TZ.

load '../test_helper'
load '../../git-config/lib/hug-clock'

@test "hug_clock_now: requires a format argument" {
  run hug_clock_now
  assert_failure
  assert_output --partial "usage"
}

@test "hug_clock_now: returns real UTC time when override unset" {
  unset HUG_FAKE_CLOCK
  run hug_clock_now "%Y%m%d-%H%M"
  assert_success
  # Must match YYYYMMDD-HHMM and equal date -u (UTC), not local time.
  [[ "$output" =~ ^[0-9]{8}-[0-9]{4}$ ]]
  assert_equal "$output" "$(date -u +"%Y%m%d-%H%M")"
}

@test "hug_clock_now: honors HUG_FAKE_CLOCK epoch regardless of host TZ" {
  # Codex #1: epoch formatting is TZ-dependent. Force a non-UTC TZ and confirm
  # the library still renders 20000101-0000 (UTC contract).
  TZ=America/Bahia HUG_FAKE_CLOCK=946684800 run hug_clock_now "%Y%m%d-%H%M"
  assert_success
  assert_output "20000101-0000"
}

@test "hug_clock_now: seconds format honors override" {
  HUG_FAKE_CLOCK=946684800 run hug_clock_now "%S"
  assert_success
  assert_output "00"
}

@test "hug_clock_now: invalid override warns on stderr, real UTC time on stdout" {
  # Codex #5: plain `run` merges streams — use --separate-stderr so $output and
  # $stderr are asserted independently.
  HUG_FAKE_CLOCK=not-a-number run --separate-stderr hug_clock_now "%Y%m%d-%H%M"
  assert_success
  [[ "$output" =~ ^[0-9]{8}-[0-9]{4}$ ]]
  [[ "$stderr" == *"ignoring invalid HUG_FAKE_CLOCK"* ]]
}

@test "hug_clock_now: numeric-but-unformattable override falls back with warning" {
  # Codex #3: a numeric value date cannot format must not propagate nonzero.
  # Use an absurdly large epoch that overflows date's range.
  HUG_FAKE_CLOCK=99999999999999999999 run --separate-stderr hug_clock_now "%Y%m%d-%H%M"
  assert_success
  [[ "$output" =~ ^[0-9]{8}-[0-9]{4}$ ]]
  [[ "$stderr" == *"could not be formatted"* ]]
}

@test "hug_clock_epoch: returns real epoch when override unset" {
  unset HUG_FAKE_CLOCK
  run hug_clock_epoch
  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]
  local real_epoch now_epoch
  real_epoch=$(date -u +%s)
  now_epoch=$output
  (( now_epoch - real_epoch <= 5 ))
  (( real_epoch - now_epoch <= 5 ))
}

@test "hug_clock_epoch: returns override verbatim" {
  HUG_FAKE_CLOCK=946684800 run hug_clock_epoch
  assert_success
  assert_output "946684800"
}

@test "hug_clock_epoch: invalid override falls back to real epoch" {
  HUG_FAKE_CLOCK=garbage run hug_clock_epoch
  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200 && make test-lib TEST_FILE=test_hug_clock.bats TEST_SHOW_ALL_RESULTS=1`
Expected: FAIL — load error (file doesn't exist yet).

- [ ] **Step 3: Write minimal implementation `git-config/lib/hug-clock`**

Follow the module header pattern of `git-config/lib/hug-fs` and `git-config/lib/hug-strings`. UTC fixed, GNU/BSD portable, arg-validated, fail-safe.

```bash
# shellcheck shell=bash
# Library: HUG clock — testable current-time helper
#
# Wraps date with an optional HUG_FAKE_CLOCK override (unix epoch seconds).
# ALL output is UTC (date -u) so the override is reproducible across host TZs.
# When unset/empty, behaves identically to real `date -u` — zero behavior
# change for real users apart from UTC (documented in the spec). When set, all
# derived times come from the same instant, making time-sensitive commands
# (e.g. git-bc's auto-generated branch names) deterministic in tests.
#
# Portability: detects GNU vs BSD date and uses -d "@$epoch" / -r "$epoch".
# macOS ships BSD date which lacks -d; the repo supports macOS per ADR-001.
#
# Why a library instead of inline in git-bc:
#   - git-tc (date suggestions) and git-w-wip (timestamp stashes) also call
#     `date` directly and are the same class of latent test flake. Centralizing
#     the override now means adopting it there later is a one-line change.
#   - Matches the existing single-concern lib pattern (hug-fs, hug-strings).
#
# Functions:
#   - hug_clock_now:   formatted current UTC time, honoring HUG_FAKE_CLOCK.
#   - hug_clock_epoch: current UTC unix epoch, honoring HUG_FAKE_CLOCK.

################################################################################
# Clock Functions
################################################################################

# Format a unix epoch per the platform's date. GNU uses -d, BSD uses -r.
# Args: $1 = epoch seconds, $2 = format string. Output: formatted UTC time to stdout.
# Returns: 0 on success, nonzero if both formatters fail (caller falls back).
_hug_clock_format_epoch() {
  local epoch="$1" fmt="$2"
  # GNU date (Linux): -d "@<epoch>"
  if date -u -d "@$epoch" +"$fmt" 2>/dev/null; then
    return 0
  fi
  # BSD date (macOS): -r <seconds>
  date -u -r "$epoch" +"$fmt" 2>/dev/null
}

# Print formatted current UTC time to stdout, honoring HUG_FAKE_CLOCK if set.
# Usage: hug_clock_now "%Y%m%d-%H%M"
# Parameters:
#   $1 - GNU/BSD date format string (e.g. "%Y%m%d-%H%M", "%S"). Required.
# Output:
#   Formatted UTC time string to stdout.
# Fail-safe:
#   If HUG_FAKE_CLOCK is set but invalid (non-numeric, or numeric-but-unformattable),
#   warns on stderr and falls back to the real UTC clock. Never crashes a calling
#   command over a bad env value.
# Returns:
#   0 on success, 2 on missing/empty format argument.
hug_clock_now() {
  # Codex #6: validate arg count to avoid set -u aborts in callers.
  if [[ $# -ne 1 || -z "${1:-}" ]]; then
    printf 'hug_clock_now: usage: hug_clock_now "<format>"\n' >&2
    return 2
  fi
  local fmt="$1"
  local fake="${HUG_FAKE_CLOCK:-}"
  if [[ -n "$fake" ]]; then
    if [[ "$fake" =~ ^[0-9]+$ ]]; then
      local rendered
      # Codex #3: capture output; if formatting fails, warn-and-fall-back rather
      # than propagating nonzero under set -euo pipefail.
      if rendered=$(_hug_clock_format_epoch "$fake" "$fmt") && [[ -n "$rendered" ]]; then
        printf '%s\n' "$rendered"
        return 0
      fi
      printf 'hug-clock: HUG_FAKE_CLOCK=%q could not be formatted; using real clock\n' \
        "$fake" >&2
    else
      printf 'hug-clock: ignoring invalid HUG_FAKE_CLOCK=%q (expected unix epoch)\n' \
        "$fake" >&2
    fi
  fi
  date -u +"$fmt"
}

# Print current UTC unix epoch (seconds) to stdout, honoring HUG_FAKE_CLOCK.
# Usage: hug_clock_epoch
# Output:
#   Integer epoch seconds to stdout.
hug_clock_epoch() {
  local fake="${HUG_FAKE_CLOCK:-}"
  if [[ -n "$fake" ]] && [[ "$fake" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$fake"
    return 0
  fi
  date -u +%s
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200 && make test-lib TEST_FILE=test_hug_clock.bats TEST_SHOW_ALL_RESULTS=1`
Expected: PASS — all 9 tests green.

- [ ] **Step 5: Commit**

```bash
cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200
hug a git-config/lib/hug-clock tests/lib/test_hug_clock.bats
hug c -F - <<'EOF'
feat(lib): add hug-clock module with HUG_FAKE_CLOCK override

WHY: Time-based test flakes (e.g. the git-bc flake at
elifarley/hug-scm#200) happen because commands call `date` directly,
with no seam to control the clock from tests. This adds that seam.

WHAT: New git-config/lib/hug-clock module exposing:
- hug_clock_now "<fmt>": wraps `date -u +<fmt>`.
- hug_clock_epoch: wraps `date -u +%s`.
Both honor HUG_FAKE_CLOCK (unix epoch seconds) when set.

HOW (design decisions hardened by Codex review):
- UTC fixed (date -u). Codex finding #1: epoch formatting via
  `date -d "@$epoch"` is TZ-dependent — on this dev box 946684800
  renders as 19991231-2200, not 20000101-0000. UTC makes the override
  reproducible across machines and is the right semantic for an
  epoch-input API.
- GNU/BSD portable. Codex #2: macOS BSD date lacks -d. The formatter
  tries GNU `date -u -d` then BSD `date -u -r`.
- Fail-safe on numeric-but-unformattable. Codex #3: a numeric value
  date cannot format (e.g. overflow) now warns and falls back rather
  than propagating nonzero under git-bc's `set -euo pipefail`.
- Arg-validated. Codex #6: hug_clock_now returns usage error (exit 2)
  on missing/empty format, preventing set -u aborts in callers.
- Zero behavior change when HUG_FAKE_CLOCK is unset (apart from UTC).
- Tests use `run --separate-stderr` for the invalid-override case so
  stdout and stderr are asserted independently (Codex #5).

IMPACT: Establishes the seam git-bc consumes next. Ready for git-tc
and git-w-wip adoption (same latent flake class).

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
```

---

### Task 2: Register `hug-clock` in `hug-common` with TDD guard

**Goal:** Add `"hug-clock"` to the `_hug_common_libs` array so every command that sources `hug-common` gets the clock functions automatically. Add a `test_hug-common.bats` assertion FIRST (Codex #8 — TDD guard for registration).

**Files:**
- Modify: `tests/lib/test_hug-common.bats` (add registration assertion)
- Modify: `git-config/lib/hug-common:80-92` (the `_hug_common_libs` array)

**Acceptance Criteria:**
- [ ] A `test_hug-common.bats` test asserts `hug_clock_now` is a function after sourcing `hug-common` alone
- [ ] That test fails BEFORE the registration edit, passes AFTER
- [ ] `"hug-clock"` is an entry in the `_hug_common_libs` array
- [ ] `git-bc` can call `hug_clock_now` without an explicit `source` line
- [ ] Existing `test_hug-common.bats` tests still pass
- [ ] Full lib suite (`make test-lib`) still passes

**Verify:**
```bash
cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200
source bin/activate
bash -c '. "$HUG_HOME/git-config/lib/hug-common" && type hug_clock_now'  # → "is a function"
make test-lib TEST_FILE=test_hug-common.bats TEST_SHOW_ALL_RESULTS=1     # registration test green
make test-lib TEST_SHOW_ALL_RESULTS=1                                    # full lib suite green
```

**Steps:**

- [ ] **Step 1: Read the current `test_hug-common.bats` to find the pattern for "sources X library" assertions**

Run: `grep -n "sources\|is a function\|type " tests/lib/test_hug-common.bats | head -20`

- [ ] **Step 2: Add the failing registration test to `tests/lib/test_hug-common.bats`**

Use Edit to append (matching the existing assertion idiom found in Step 1):

```bash
@test "hug-common: sources hug-clock library" {
  # Codex #8: TDD guard for registration. If hug_clock_now is not a function
  # after sourcing hug-common, the _hug_common_libs array is missing hug-clock.
  [[ "$(type -t hug_clock_now)" == "function" ]]
}
```

- [ ] **Step 3: Run the new test to verify it FAILS (hug-clock not yet registered)**

Run: `cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200 && make test-lib TEST_FILE=test_hug-common.bats TEST_FILTER="sources hug-clock" TEST_SHOW_ALL_RESULTS=1`
Expected: FAIL — `type -t hug_clock_now` returns empty.

- [ ] **Step 4: Add `"hug-clock"` to the `_hug_common_libs` array**

Use Edit. old_string/new_string:

old_string:
```
_hug_common_libs=(
  "hug-terminal"
  "hug-gum"
  "hug-output"
  "hug-strings"
```

new_string:
```
_hug_common_libs=(
  "hug-terminal"
  "hug-gum"
  "hug-output"
  "hug-clock"
  "hug-strings"
```

- [ ] **Step 5: Verify the function is loadable through hug-common**

```bash
cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200
source bin/activate
bash -c '. "$HUG_HOME/git-config/lib/hug-common" && type hug_clock_now'
```
Expected: `hug_clock_now is a function`

- [ ] **Step 6: Run the registration test + full lib suite**

Run: `cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200 && make test-lib TEST_SHOW_ALL_RESULTS=1`
Expected: All tests green, including the new registration test and Task 1's `test_hug_clock.bats`.

- [ ] **Step 7: Commit**

```bash
cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200
hug a git-config/lib/hug-common tests/lib/test_hug-common.bats
hug c -F - <<'EOF'
feat(lib): register hug-clock in hug-common bootstrap

WHY: hug-clock needs to be available everywhere hug-common is sourced
so git-bc (and future git-tc, git-w-wip adopters) can call hug_clock_now
without a per-command source line.

WHAT: Adds "hug-clock" to _hug_common_libs in hug-common, and a TDD
guard in test_hug-common.bats asserting hug_clock_now is a function
after sourcing hug-common alone (Codex #8).

IMPACT: hug_clock_now / hug_clock_epoch available to every hug command.
No behavior change for commands that don't call them yet.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
```

---

### Task 3: Switch `git-bc` to `hug_clock_now`

**Goal:** Replace the three direct `date` calls in `git-bc`'s name-generation block (lines 132, 159, 162) with `hug_clock_now`, making auto-generated branch names deterministic under `HUG_FAKE_CLOCK`. Note: branch-name suffixes shift from local time to UTC (documented in spec and commit).

**Files:**
- Modify: `git-config/bin/git-bc:132` — `iso_datetime=$(date +"%Y%m%d-%H%M")`
- Modify: `git-config/bin/git-bc:159` — `branch_name="${original_name}.$(date +%S)"`
- Modify: `git-config/bin/git-bc:162` — `branch_name="${original_name}.$(date +%S).${counter}"`

**Acceptance Criteria:**
- [ ] No bare `date` **invocation** (the command, not the word in comments) remains in `git-bc`'s name-generation block (lines 123-176)
- [ ] `HUG_FAKE_CLOCK=946684800 hug bc --point-to v1.0.0` (no branch name) generates a name containing `20000101-0000`
- [ ] Without `HUG_FAKE_CLOCK`, `hug bc --point-to v1.0.0` still generates a valid real-time name (format `^[0-9]{8}-[0-9]{4}$`, now UTC)
- [ ] Existing `test_bc.bats` tests (except the two flaky ones, fixed in Task 4) still pass

**Verify:**
```bash
cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200
# Codex #9 fix: grep for the date INVOCATION, not the word "date" (which appears in comments).
# Anchored: '$(date' as a command substitution, or '^  date' as a statement.
sed -n '123,176p' git-config/bin/git-bc | grep -nE '\$(date |\bdate ' || echo "OK: no date invocations"
make test-unit TEST_FILE=test_bc.bats TEST_SHOW_ALL_RESULTS=1
```
Expected: `OK: no date invocations`; test_bc.bats green except possibly the two known-flaky tests (fixed in Task 4).

**Steps:**

- [ ] **Step 1: Replace line 132 — the minute call**

Use Edit. old_string/new_string:

old_string:
```
  # Generate ISO datetime: YYYYMMDD-HHMM
  iso_datetime=$(date +"%Y%m%d-%H%M")
```

new_string:
```
  # Generate ISO datetime: YYYYMMDD-HHMM (UTC via hug_clock_now).
  # UTC, not local, because hug_clock_now is UTC-fixed — the suffix is a
  # uniqueness hint, not user-facing display, and UTC makes it stable across
  # machines. Tests pin HUG_FAKE_CLOCK to make this deterministic (#200).
  iso_datetime=$(hug_clock_now "%Y%m%d-%H%M")
```

- [ ] **Step 2: Replace line 159 — the first-collision seconds suffix**

old_string:
```
      # First collision: try appending seconds
      branch_name="${original_name}.$(date +%S)"
```

new_string:
```
      # First collision: try appending seconds (UTC, same instant as the
      # minute call above when HUG_FAKE_CLOCK is set — no second-boundary drift).
      branch_name="${original_name}.$(hug_clock_now "%S")"
```

- [ ] **Step 3: Replace line 162 — the subsequent-collision seconds+counter suffix**

old_string:
```
      # Subsequent collisions: append counter
      branch_name="${original_name}.$(date +%S).${counter}"
```

new_string:
```
      # Subsequent collisions: append counter
      branch_name="${original_name}.$(hug_clock_now "%S").${counter}"
```

- [ ] **Step 4: Verify no `date` invocation remains in the name-gen block**

Run: `sed -n '123,176p' git-config/bin/git-bc | grep -nE '\$(date |\bdate ' || echo "OK: no date invocations"`
Expected: `OK: no date invocations` (Codex #9 — anchored on invocation, not the word).

- [ ] **Step 5: Smoke-test the override manually (with a non-empty repo)**

Per Codex #9, `git tag` in an empty repo fails. Create a commit first.

```bash
cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200
source bin/activate
TD=$(mktemp -d) && cd "$TD" && git init -q && git checkout -q -b main
git config user.email t@t && git config user.name t
echo hi > f && git add f && git commit -qm "init"   # HEAD exists now
git tag v1.0.0
HUG_FAKE_CLOCK=946684800 hug bc --point-to v1.0.0 --no-switch
git branch --list 'v1.0.0.branch.*'
cd - >/dev/null && rm -rf "$TD"
```
Expected: prints `  v1.0.0.branch.20000101-0000`.

- [ ] **Step 6: Run the existing test_bc.bats suite**

Run: `cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200 && make test-unit TEST_FILE=test_bc.bats TEST_SHOW_ALL_RESULTS=1`
Expected: All tests pass except possibly the two known-flaky ones (lines 136, 334 — fixed in Task 4). The other ~20 tests must be green, confirming the override is invisible when `HUG_FAKE_CLOCK` is unset (the UTC shift is acceptable per spec).

- [ ] **Step 7: Commit**

```bash
cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200
hug a git-config/bin/git-bc
hug c -F - <<'EOF'
refactor(bc): switch git-bc name generation to hug_clock_now (UTC)

WHY: git-bc generated branch-name timestamps via three direct `date`
calls (minute, then seconds-suffix on collision). Two problems: (1)
no test seam — tests could not pin the clock, causing the flake at
elifarley/hug-scm#200; (2) the minute and seconds calls were two
separate `date` invocations that could themselves disagree across a
second boundary (latent second flake).

WHAT: All three call sites now use hug_clock_now, which is UTC-fixed
and honors HUG_FAKE_CLOCK.

HOW:
- Line 132: iso_datetime now from hug_clock_now "%Y%m%d-%H%M".
- Line 159/162: collision-suffix seconds now from hug_clock_now "%S".
- When HUG_FAKE_CLOCK is set, all three derive from the same frozen
  instant — minute and seconds can never disagree.
- Zero behavior change when HUG_FAKE_CLOCK is unset, apart from the
  suffix timezone shifting local → UTC. The suffix is a uniqueness
  hint, not user-facing display; UTC makes it stable across machines.
  Documented in the spec's "Consumer contract note".

IMPACT: Closes the seam needed to make test_bc.bats:334 and :136
deterministic. Prepares git-bc for the test fix in the next commit.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
```

---

### Task 4: Rewrite BOTH flaky tests to use `HUG_FAKE_CLOCK`

**Goal:** Rewrite `tests/unit/test_bc.bats:334` AND `:136` so both pin their `hug bc` calls to the same frozen epoch, making both collisions provably reproducible. The line-334 test is rewritten with exact-UTC-name assertions and renamed. (Codex #4 surfaced the second flake at :136; Codex #7 strengthened the line-334 assertions.)

**Files:**
- Modify: `tests/unit/test_bc.bats:334-357` (the flaky test the issue names)
- Modify: `tests/unit/test_bc.bats:136-151` (the sibling flake Codex found)

**Acceptance Criteria:**
- [ ] Line-334 test renamed from `auto-generated name is unique per minute` to `collision on same-minute name produces unique suffix`
- [ ] Line-334 test sets `export HUG_FAKE_CLOCK=946684800` and asserts exact UTC names: `v1.0.0.branch.20000101-0000` and `v1.0.0.branch.20000101-0000.00`
- [ ] Line-136 test sets `export HUG_FAKE_CLOCK=946684800` (keeps its existing assertions; minimal fix)
- [ ] `assert_output --partial "Generated name existed; using"` passes deterministically in BOTH tests
- [ ] The 50× loop on BOTH pinned tests passes 50/50

**Verify:**
```bash
cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200
# Single run of each:
make test-unit TEST_FILE=test_bc.bats TEST_FILTER="collision on same-minute" TEST_SHOW_ALL_RESULTS=1
make test-unit TEST_FILE=test_bc.bats TEST_FILTER="auto-generates unique name if conflict" TEST_SHOW_ALL_RESULTS=1
# 50× flake-repro loop on both:
for i in $(seq 1 50); do
  make test-unit TEST_FILE=test_bc.bats TEST_FILTER="collision on same-minute" TEST_SHOW_ALL_RESULTS=1 >/dev/null 2>&1 || { echo "FAILED line334 iter $i"; break; }
  make test-unit TEST_FILE=test_bc.bats TEST_FILTER="auto-generates unique name if conflict" TEST_SHOW_ALL_RESULTS=1 >/dev/null 2>&1 || { echo "FAILED line136 iter $i"; break; }
done
echo "Loop complete"
```
Expected: both single runs green; loop prints `Loop complete` with no `FAILED` line.

**Steps:**

- [ ] **Step 1: Rewrite the line-334 test**

Use Edit. old_string (the entire current test, lines 334-357):

old_string:
```
@test "hug bc --point-to: auto-generated name is unique per minute" {
  # Get current branch
  original_branch=$(git branch --show-current)

  # Create first branch
  run hug bc --point-to v1.0.0
  assert_success
  first_branch=$(git branch --show-current)

  # Switch back to original
  git switch "$original_branch"

  # Try to create another branch from same tag in same minute
  # This should succeed with a unique name (adds seconds)
  run hug bc --point-to v1.0.0
  assert_success
  assert_output --partial "Generated name existed; using"
  second_branch=$(git branch --show-current)

  # Verify branches are different but both exist
  [ "$first_branch" != "$second_branch" ]
  git show-ref --verify "refs/heads/$first_branch" >/dev/null
  git show-ref --verify "refs/heads/$second_branch" >/dev/null
}
```

new_string:
```
@test "hug bc --point-to: collision on same-minute name produces unique suffix" {
  # Freeze wall clock so both calls land in the same UTC minute, deterministically.
  # Without this, the test flakes near a minute boundary (elifarley/hug-scm#200):
  # the second call would generate a fresh, non-colliding name and the
  # "Generated name existed; using" assertion would fail.
  # Epoch 946684800 = 2000-01-01 00:00:00 UTC → renders as 20000101-0000 under
  # hug_clock_now's UTC contract, regardless of host TZ.
  export HUG_FAKE_CLOCK=946684800

  original_branch=$(git branch --show-current)

  # First call: creates v1.0.0.branch.20000101-0000
  run hug bc --point-to v1.0.0
  assert_success
  first_branch=$(git branch --show-current)
  # Codex #7: assert the exact UTC name, not just "collision happened".
  assert_equal "$first_branch" "v1.0.0.branch.20000101-0000"

  git switch "$original_branch"

  # Second call in the same frozen minute → name collides → git-bc appends
  # the seconds suffix (".00" for this epoch) and warns.
  run hug bc --point-to v1.0.0
  assert_success
  assert_output --partial "Generated name existed; using"
  second_branch=$(git branch --show-current)
  assert_equal "$second_branch" "v1.0.0.branch.20000101-0000.00"

  # Both branches exist and are distinct (the suffix made the second unique).
  [ "$first_branch" != "$second_branch" ]
  git show-ref --verify "refs/heads/$first_branch" >/dev/null
  git show-ref --verify "refs/heads/$second_branch" >/dev/null
}
```

- [ ] **Step 2: Pin the line-136 test (minimal fix — keep existing assertions)**

Use Edit. Add the `export HUG_FAKE_CLOCK` line right after the `@test` line.

old_string:
```
@test "hug bc --no-switch --point-to: auto-generates unique name if conflict" {
  original_branch=$(git branch --show-current)
```

new_string:
```
@test "hug bc --no-switch --point-to: auto-generates unique name if conflict" {
  # Codex #4 (review of the #200 fix): this test had the SAME minute-rollover
  # flake as the --point-to test below. Pin the clock so both back-to-back
  # auto-named calls land in the same minute and the collision path fires.
  export HUG_FAKE_CLOCK=946684800
  original_branch=$(git branch --show-current)
```

- [ ] **Step 3: Run both pinned tests once**

Run:
```bash
cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200
make test-unit TEST_FILE=test_bc.bats TEST_FILTER="collision on same-minute" TEST_SHOW_ALL_RESULTS=1
make test-unit TEST_FILE=test_bc.bats TEST_FILTER="auto-generates unique name if conflict" TEST_SHOW_ALL_RESULTS=1
```
Expected: both PASS.

- [ ] **Step 4: Run the 50× flake-repro loop on both**

Run:
```bash
cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200
for i in $(seq 1 50); do
  make test-unit TEST_FILE=test_bc.bats TEST_FILTER="collision on same-minute" TEST_SHOW_ALL_RESULTS=1 >/dev/null 2>&1 || { echo "FAILED line334 iter $i"; break; }
  make test-unit TEST_FILE=test_bc.bats TEST_FILTER="auto-generates unique name if conflict" TEST_SHOW_ALL_RESULTS=1 >/dev/null 2>&1 || { echo "FAILED line136 iter $i"; break; }
done
echo "Loop complete"
```
Expected: `Loop complete` with no `FAILED` line. This is the acceptance gate from the issue, applied to both flakes.

- [ ] **Step 5: Run the full test_bc.bats to confirm no collateral damage**

Run: `cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200 && make test-unit TEST_FILE=test_bc.bats TEST_SHOW_ALL_RESULTS=1`
Expected: All tests green.

- [ ] **Step 6: Commit**

```bash
cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200
hug a tests/unit/test_bc.bats
hug c -F - <<'EOF'
test(bc): pin wall clock in BOTH collision tests (HUG_FAKE_CLOCK)

WHY: Two tests in test_bc.bats asserted the collision-suffix path via
two back-to-back `hug bc` calls, relying on both landing in the same
wall-clock minute. Near a minute boundary they didn't, the second call
generated a fresh non-colliding name, and the assertion failed. The
#200 issue names the --point-to test; Codex review of this fix surfaced
a sibling flake in the --no-switch --point-to test with the identical
failure mode.

WHAT:
- Rewrites test_bc.bats:334 to `export HUG_FAKE_CLOCK=946684800` and
  asserts exact UTC branch names (v1.0.0.branch.20000101-0000 and
  .20000101-0000.00). Renamed to 'collision on same-minute name
  produces unique suffix' — the old name was a misnomer.
- Pins test_bc.bats:136 with the same override (minimal fix; keeps
  existing assertions and the brittle `git branch | grep` extraction,
  which is out of scope to rewrite here).

HOW: HUG_FAKE_CLOCK is exported in each test body; no explicit teardown
needed because test_helper.bash's per-test setup creates a fresh
subshell environment.

IMPACT: Closes elifarley/hug-scm#200 and its unnamed sibling flake.
Unblocks PRs that were being randomly tagged. Restores CI signal trust.

Verification: 50× loop of BOTH pinned tests passes 50/50.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
```

---

### Task 5: Final regression sweep and PR

**Goal:** Confirm the entire test suite is green and create the PR.

**Files:** None modified.

**Acceptance Criteria:**
- [ ] `make test` (full suite: BATS + pytest) passes with zero failures
- [ ] `make test-lib TEST_FILE=test_hug_clock.bats` passes (9 tests)
- [ ] `make test-unit TEST_FILE=test_bc.bats` passes (including both pinned tests)
- [ ] No bare `date` invocation remains in `git-bc`'s name-generation block
- [ ] PR created against `main` referencing elifarley/hug-scm#200

**Verify:** `cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200 && make test` → `All tests passed!`, zero failures.

**Steps:**

- [ ] **Step 1: Run the full test suite**

Run: `cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200 && make test`
Expected: All tests green. If any failure, STOP and diagnose.

- [ ] **Step 2: Confirm the name-gen block is clean (Codex #9 anchoring)**

Run: `sed -n '123,176p' git-config/bin/git-bc | grep -nE '\$(date |\bdate ' || echo "OK: no date invocations"`
Expected: `OK: no date invocations`.

- [ ] **Step 3: Run sanitize (formatting/lint/typecheck)**

Run: `cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200 && make sanitize-check 2>/dev/null || make sanitize`
Expected: clean.

- [ ] **Step 4: Push the branch and create the PR**

```bash
cd ~/IdeaProjects/hug-scm.WT.fix-bc-fake-clock-200
hug bpush
GH_TOKEN=$(gh auth token --user elifarley) gh pr create \
  --base main \
  --title "test(bc): fix wall-clock flakes via HUG_FAKE_CLOCK (UTC-fixed)" \
  --body "$(cat <<'EOF'
## Summary
- Adds `git-config/lib/hug-clock` exposing `hug_clock_now` / `hug_clock_epoch` — UTC-fixed (`date -u`), GNU/BSD-portable, fail-safe, arg-validated.
- Registers `hug-clock` in `hug-common` with a TDD guard in `test_hug-common.bats`.
- Switches `git-bc`'s three direct `date` calls (name generation + collision suffix) to `hug_clock_now`.
- Pins BOTH flaky `test_bc.bats` tests (:334 the issue names, :136 Codex review surfaced) to `HUG_FAKE_CLOCK=946684800`; rewrites :334 with exact-UTC-name assertions and renames it.
- Zero behavior change when `HUG_FAKE_CLOCK` is unset (apart from the suffix timezone shifting local → UTC — documented as acceptable for a uniqueness hint).
- Hardened by adversarial Codex review: all 9 findings incorporated (TZ determinism, BSD portability, numeric-but-unformattable fallback, separate-stderr test, arg validation, exact-name assertions, registration TDD guard, fixed verification greps, second-flake discovery).

## Test plan
- [ ] `make test-lib TEST_FILE=test_hug_clock.bats` (9 new lib tests, TZ-independent)
- [ ] `make test-unit TEST_FILE=test_bc.bats` (full bc suite, incl. both pinned tests)
- [ ] 50× loop on BOTH pinned tests passes 50/50 (the flake-repro gate from the issue)
- [ ] `make test` (full suite) green

Closes elifarley/hug-scm#200.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review (post-Codex)

**1. Spec coverage (all items in the updated spec map to a task):**
- New module `hug-clock` UTC-fixed + GNU/BSD portable + arg-validated + fail-safe → Task 1. ✓
- Registration in `hug-common` + TDD guard → Task 2. ✓
- `git-bc` 3 call sites → Task 3. ✓
- Library tests (9 cases, incl. TZ-independence, separate-stderr, numeric-but-unformattable) → Task 1. ✓
- Test rewrite + rename + exact-UTC-names (line 334) → Task 4 Step 1. ✓
- **Second flake pin (line 136)** → Task 4 Step 2. ✓ (Codex #4)
- 50× flake-repro gate on BOTH tests → Task 4 Step 4. ✓
- Full regression sweep → Task 5. ✓
- UTC contract / portability / consumer note documented in spec. ✓
- Out-of-scope items (git-tc, git-w-wip adoption; line-136 extraction refactor) correctly not in plan. ✓

**2. Placeholder scan:** No TBD/TODO. Every code step shows complete code. Every command includes expected output. No "similar to Task N".

**3. Consistency:** `hug_clock_now` (one arg: format string) and `hug_clock_epoch` (no args) — names and signatures identical across Task 1 implementation, Task 1 tests, Task 2 verification, Task 3 consumer. `HUG_FAKE_CLOCK=946684800` consistent in Task 1 tests, Task 3 smoke, Task 4 both test edits. Expected UTC rendering `20000101-0000` consistent everywhere. Test names in Task 4 edits match the Step 3/4 verify `TEST_FILTER` strings.

No user-gate tasks — all verification is mechanical (test runs, grep checks, 50× loops). No gate heads-up needed.
