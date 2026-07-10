# Design: Fix `git-bc` time-based test flake via `HUG_FAKE_CLOCK` override

- **Date:** 2026-07-10
- **Issue:** [elifarley/hug-scm#200](https://github.com/elifarley/hug-scm/issues/200)
- **Branch:** `fix-bc-fake-clock-200`
- **Status:** Approved (brainstorm phase)

## Problem

The unit test `hug bc --point-to: auto-generated name is unique per minute`
(`tests/unit/test_bc.bats:334`) is a timing-dependent flake that intermittently
fails in CI.

`git-bc` generates branch names at minute granularity:

```
v1.0.0.branch.YYYYMMDD-HHMM
```

via `iso_datetime=$(date +"%Y%m%d-%H%M")` at `git-bc:132`. The test creates the
same-minute name twice and asserts that the second call hits the collision-suffix
path (`git-bc:172` → `warn "Generated name existed; using $branch_name"`).

If the minute rolls over between the two `hug bc` calls, the second call generates
a fresh, non-colliding name, and the assertion fails. This blocked the otherwise-
green docs-only [elifarley/hug-scm#199](https://github.com/elifarley/hug-scm/pull/199)
on its first CI run.

### Root cause

Wall-clock time is read directly via `date` at three call sites in `git-bc`
(lines 132, 159, 162). There is no seam to control it from tests, so the
collision logic is non-deterministic by construction.

A secondary latent flake exists: the minute call (`date +"%Y%m%d-%H%M"`) and the
seconds-suffix call (`date +%S`) at `git-bc:159/162` are two separate `date`
invocations. They can themselves disagree if invoked across a second boundary.

## Approach

Of the three options ranked in the issue, this spec adopts **option 1: inject a
fixed clock.** A new `HUG_FAKE_CLOCK` environment variable (unix epoch seconds)
overrides the `date` command inside hug commands. The test pins both `hug bc`
calls to the same frozen instant, making the collision provably reproducible.

Rejected alternatives:

- **Force a collision deterministically (option 2):** would require pre-creating
  a branch whose name matches the *current* minute — reintroducing wall-clock
  dependence. Does not generalize.
- **Loosen the assertion (option 3):** hides regressions in the collision-suffix
  logic. Explicitly rejected by the issue author.

## Design

### New module: `git-config/lib/hug-clock`

A thin, single-concern sourced bash library providing a testable "current time"
abstraction. Wraps GNU `date` with an optional `HUG_FAKE_CLOCK` override.

Follows the existing module pattern (`hug-fs`, `hug-strings`, `hug-terminal`):
sourced, pure functions, no side effects beyond reading the env var.

**Public API:**

```bash
# Print formatted current time to stdout, honoring HUG_FAKE_CLOCK if set.
# Args: $1 = GNU date format string (e.g. "%Y%m%d-%H%M"). Required.
hug_clock_now() { ... }

# Print current unix epoch (seconds) to stdout. Honors the same override.
hug_clock_epoch() { ... }
```

**Override semantics:**

- `HUG_FAKE_CLOCK` accepts a **unix epoch (integer seconds)**.
- Empty / unset → real wall clock (zero behavioral change for existing users and
  CI runs that don't set it).
- Invalid value → the functions detect the parse failure and **fall back to real
  `date` with a stderr warning** rather than crashing. Rationale: a clock helper
  must never take down a user-facing command over a bad env value. Tests set a
  controlled value, so the warning path is never exercised in CI.

**Reference implementation (illustrative):**

```bash
# shellcheck shell=bash
# Library: HUG clock — testable current-time helper
#
# Wraps GNU date with an optional HUG_FAKE_CLOCK override (unix epoch seconds).
# When unset/empty, behaves identically to `date` — zero behavior change for
# real users. When set, all derived times come from the same instant, which
# makes time-sensitive commands (e.g. git-bc's auto-generated branch names)
# deterministic in tests.
#
# Why a library instead of inline in git-bc:
#   - git-tc (date suggestions) and git-w-wip (timestamp stashes) also call
#     `date` directly and are the same class of latent test flake. Centralizing
#     the override now means adopting it there later is a one-line change.
#   - Matches the existing single-concern lib pattern (hug-fs, hug-strings).

hug_clock_now() {
  local fmt="$1"
  local fake="${HUG_FAKE_CLOCK:-}"
  if [[ -n "$fake" ]]; then
    # Validate: must be a positive integer epoch.
    if [[ "$fake" =~ ^[0-9]+$ ]]; then
      date -d "@$fake" +"$fmt"
      return $?
    fi
    # Bad override → warn and fall back. Never crash a user command over a clock bug.
    printf 'hug-clock: ignoring invalid HUG_FAKE_CLOCK=%q (expected unix epoch)\n' \
      "$fake" >&2
  fi
  date +"$fmt"
}

hug_clock_epoch() {
  local fake="${HUG_FAKE_CLOCK:-}"
  if [[ -n "$fake" ]] && [[ "$fake" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$fake"
    return 0
  fi
  date +%s
}
```

### Registration: `git-config/lib/hug-common`

Add `"hug-clock"` to the `_hug_common_libs` array at `hug-common:80`, alongside
the other small single-concern modules (`hug-cli-flags`, `hug-confirm`,
`hug-strings`). Every command that already sources `hug-common` gets
`hug_clock_now` / `hug_clock_epoch` for free — including `git-bc`.

### Consumer change: `git-config/bin/git-bc`

Three call sites:

```diff
- iso_datetime=$(date +"%Y%m%d-%H%M")
+ iso_datetime=$(hug_clock_now "%Y%m%d-%H%M")
```

```diff
  while git show-ref --verify --quiet "refs/heads/$branch_name" 2> /dev/null; do
    if [[ $counter -eq 0 ]]; then
      # First collision: try appending seconds
-     branch_name="${original_name}.$(date +%S)"
+     branch_name="${original_name}.$(hug_clock_now "%S")"
    else
      # Subsequent collisions: append counter
-     branch_name="${original_name}.$(date +%S).${counter}"
+     branch_name="${original_name}.$(hug_clock_now "%S").${counter}"
    fi
```

When `HUG_FAKE_CLOCK` is set, all three calls derive from the same frozen
instant — the minute and the seconds-suffix can never disagree, and two
back-to-back `hug bc` calls always land in the same minute.

### Test fix: `tests/unit/test_bc.bats`

Rewrite the flaky test at line 334 to set `HUG_FAKE_CLOCK`:

```bash
@test "hug bc --point-to: collision on same-minute name produces unique suffix" {
  # Freeze wall clock so both calls land in the same minute, deterministically.
  # Epoch 946684800 = 2000-01-01 00:00:00 UTC.
  export HUG_FAKE_CLOCK=946684800

  original_branch=$(git branch --show-current)

  run hug bc --point-to v1.0.0
  assert_success
  first_branch=$(git branch --show-current)

  git switch "$original_branch"

  # Same frozen minute → name collides → git-bc appends seconds suffix.
  run hug bc --point-to v1.0.0
  assert_success
  assert_output --partial "Generated name existed; using"
  second_branch=$(git branch --show-current)

  [[ "$first_branch" != "$second_branch" ]]
  git show-ref --verify "refs/heads/$first_branch" >/dev/null
  git show-ref --verify "refs/heads/$second_branch" >/dev/null
}
```

The test is also **renamed** from `auto-generated name is unique per minute` to
`collision on same-minute name produces unique suffix`. The old name was a
misnomer — the test has always exercised the collision path, not uniqueness per
minute. The rename keeps `TEST_FILTER` queries honest.

`HUG_FAKE_CLOCK` does not need explicit teardown: `test_helper.bash`'s per-test
repo setup creates a fresh environment, and the export is scoped to the test
subshell.

## Testing strategy

### 1. Library tests — new file `tests/lib/test_hug_clock.bats`

Pure-function tests; no git repo needed. Locks in the override contract so
future adoption in `git-tc` / `git-w-wip` is safe.

| Test | Setup | Assert |
|---|---|---|
| `hug_clock_now: returns real time when override unset` | `unset HUG_FAKE_CLOCK` | output matches `^[0-9]{8}-[0-9]{4}$` |
| `hug_clock_now: honors HUG_FAKE_CLOCK epoch` | `HUG_FAKE_CLOCK=946684800` | `hug_clock_now "%Y%m%d-%H%M"` → `20000101-0000` |
| `hug_clock_now: seconds format honors override` | `HUG_FAKE_CLOCK=946684800` | `hug_clock_now "%S"` → `00` |
| `hug_clock_now: invalid override warns and falls back` | `HUG_FAKE_CLOCK=not-a-number`, capture stderr+stdout | stdout is valid-format real time; stderr contains `ignoring invalid HUG_FAKE_CLOCK` |
| `hug_clock_epoch: returns real epoch when unset` | `unset HUG_FAKE_CLOCK` | output is integer; within ±5 of `date +%s` |
| `hug_clock_epoch: returns override verbatim` | `HUG_FAKE_CLOCK=946684800` | output is exactly `946684800` |
| `hug_clock_epoch: invalid override falls back silently` | `HUG_FAKE_CLOCK=garbage` | output is integer real epoch |

### 2. Unit test fix — `tests/unit/test_bc.bats:334`

The rewritten test above. Deterministic by construction: with `HUG_FAKE_CLOCK`
set, both `hug bc` calls provably land on the same frozen minute.

### 3. Flake-reproduction verification — manual, not committed

Per the issue:

```bash
for i in $(seq 1 50); do
  make test-unit TEST_FILE=test_bc.bats TEST_FILTER="collision on same-minute" || break
done
```

Must pass 50/50. This is the acceptance gate.

### 4. Regression sweep — full `test_bc.bats` + full unit suite

```bash
make test-unit TEST_FILE=test_bc.bats TEST_SHOW_ALL_RESULTS=1
make test-unit TEST_SHOW_ALL_RESULTS=1
```

Confirms zero new failures, and that the other `git-bc` tests (which do not set
`HUG_FAKE_CLOCK`) still use real time — proving the override is opt-in and
invisible to existing behavior.

No new integration tests are needed: this is a deterministic fix to an existing
unit test, not new user-facing behavior.

## Out of scope

- Adopting `hug_clock_now` in `git-tc` (date suggestions, `git-tc:117/124`) and
  `git-w-wip` (timestamp stashes, `git-w-wip:65/66`). These are the same class
  of latent flake, but YAGNI for this issue. The library is ready for them when
  needed — adoption is a one-line change per call site.
- Changing the branch-name format. The user-visible `YYYYMMDD-HHMM` format and
  the `.SS` / `.SS.N` collision suffix are unchanged.

## Acceptance criteria

- [ ] `git-config/lib/hug-clock` exists with `hug_clock_now` and `hug_clock_epoch`.
- [ ] `hug-common` sources `hug-clock`.
- [ ] `git-bc` uses `hug_clock_now` at all three former `date` call sites.
- [ ] `tests/lib/test_hug_clock.bats` exists and passes, covering all 7 cases above.
- [ ] `tests/unit/test_bc.bats:334` rewritten and renamed; sets `HUG_FAKE_CLOCK`.
- [ ] 50× loop on the rewritten test passes 50/50.
- [ ] `make test-unit` is green with zero new failures.
- [ ] No `date` call remains in `git-bc`'s name-generation block.
