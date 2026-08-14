<!-- /autoplan restore point: /home/ecc/.gstack/projects/elifarley-hug-scm/fix-hug-rb-ux-correctness-autoplan-restore-20260711-123801.md -->
# Fix: `hug rb` UX & correctness — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `hug rb` (rebase-with-backup) trustworthy and script-safe by fixing the four sub-bugs in [elifarley/hug-scm#205](https://github.com/elifarley/hug-scm/issues/205) — lying exit code (#3b), backup collision on retry (#2), non-interactive cancel with no opt-in (#1), and the incoherent `--no-backup` guard (#3a) — plus two latent defects (dead conflict-guidance branch, `--quiet` authorizes the rebase).

**Architecture:** One unifying flow — **plan → render → (dry-run stops | confirm → execute)** — carries all fixes. A *dynamic confirmation tier* (backup ⇒ warn, `--no-backup` ⇒ danger) replaces the ad-hoc guard. Backup creation moves to *after* authorization. Collision-proof naming reuses the proven `git-bc` pattern (`hug_clock_now` ladder). A `--dry-run` faithfully previews the real run with zero side effects.

**Tech Stack:** Bash (`git-config/bin`, `git-config/lib`), BATS tests, existing `hug-clock` (`HUG_FAKE_CLOCK`) and `hug-confirm` tier libraries. `hug-git-kit` already aggregates `hug-git-backup` and `hug-git-rebase`, so no source-chain changes.

**Design reference:** `mgmt/plans/2026-07-11-hug-rb-ux-correctness-design.md` (the spec).

---

## File Structure (locked-in decomposition)

### Files modified
- `git-config/lib/hug-git-backup` — add `resolve_backup_name` (pure); rewrite `create_backup_branch` with `hug_clock_now` collision ladder; widen `extract_original_name` for the new timestamp formats. Refresh header doc-comment.
- `git-config/bin/git-bdel-backup` — update `normalize_backup_key` to parse the widened `DD-HHMM[SS[-N]]` form and map seconds names to a minute-precision comparison key (so `--delete-older-than` ordering stays correct).
- `git-config/lib/hug-git-rebase` — house new `rb_build_plan` / `rb_render_plan` helpers (keep `git-rb` a thin orchestrator per `bin/CLAUDE.md`); add `rb_assert_no_rebase_in_progress` covering both `rebase-merge` and `rebase-apply`.
- `git-config/bin/git-rb` — adopt plan→render→execute flow; swap confirm call per tier; make rebase status-safe (resurrect conflict guidance); fix `--quiet` authorization; rewrite `show_help` OPTIONS.

### Files created
- `tests/unit/test_rb.bats` — net-new coverage for all four sub-bugs, the bonus defects, the tier matrix, the dry-run preview, and the rebase-in-progress guard (D7).
- `tests/lib/test_hug_git_backup.bats` — lib tests for `resolve_backup_name`, the collision ladder, and `extract_original_name` widened forms.
- `tests/lib/test_hug_git_rebase.bats` — lib tests for `rb_assert_no_rebase_in_progress` (both backends).
- `tests/lib/test_hug_git_bdel_backup_keys.bats` — lib tests for the widened `normalize_backup_key` (verifies seconds-precision ordering against a minute-precision threshold).

### Docs touched
- `git-config/bin/git-rb` `show_help` (in-file, part of Task 5) — dynamic tier + richer `--dry-run`.
- `git-config/lib/hug-git-backup` header comment (part of Task 1) — new format + new function.
- Agent cheatsheet `--dry-run` note (Task 6).

---

## Task Decomposition

Tasks are ordered by dependency:

1. **Task 1** — `hug-git-backup` lib: pure `resolve_backup_name` + collision-proof `create_backup_branch` + widened `extract_original_name`. Foundation for everything else; fully testable in isolation.
2. **Task 2** — Lib tests for Task 1 (red→green; TDD).
3. **Task 3** — `git-bdel-backup` `normalize_backup_key` widening + its lib test. Depends on Task 1's naming format being decided (it is — locked in Task 1).
4. **Task 4** — `hug-git-rebase` plan/render helpers + the in-progress guard + its lib test. Depends on Task 1's `resolve_backup_name`.
5. **Task 5** — `git-rb` orchestrator rewrite + `tests/unit/test_rb.bats`. Depends on Tasks 1+4. This is where all four sub-bugs are closed for the user.
6. **Task 6** — Help text + agent cheatsheet doc tidy-up. Depends on Task 5 (documents the final UX).

---

## Task 1: `hug-git-backup` — pure `resolve_backup_name` + collision-proof `create_backup_branch` + widened `extract_original_name`

**Goal:** Replace the untestable, collision-prone backup-branch creator with a `hug_clock_now`-based ladder (mirroring `git-bc`), factored as a pure read-only `resolve_backup_name` (used by `--dry-run`) plus a `create_backup_branch` that loops around the real `git branch` call. Also widen the name parser to accept the new disambiguated forms.

**Files:**
- Modify: `git-config/lib/hug-git-backup` (entire file rewritten; ~95 LOC → ~140 LOC)
- Test: `tests/lib/test_hug_git_backup.bats` (created in Task 2)

**Acceptance Criteria:**
- [ ] `resolve_backup_name <source_ref> <base_name>` is pure (no `git` writes), reads only `git show-ref`, and echoes the name it *would* create at the current `hug_clock_now` instant. Returns 0 on success, 1 on missing args.
- [ ] `create_backup_branch <source_ref> <base_name>` uses `hug_clock_now` (not raw `date`), and produces names on the documented ladder:
  - default: `hug-backups/YYYY-MM/DD-HHMM.<base>`
  - same-minute collision: `hug-backups/YYYY-MM/DD-HHMMSS.<base>`
  - same-second collision: `hug-backups/YYYY-MM/DD-HHMMSS-N.<base>` (N=1..100)
- [ ] `create_backup_branch` is bounded at 100 attempts; on exhaustion it `error`s with a clear message and returns non-zero.
- [ ] `create_backup_branch` distinguishes collision from real failure: retries ONLY when the candidate name now exists as a ref (concurrent writer); surfaces the real `git branch` stderr immediately for any other failure (invalid source ref, bad chars, lock, permissions). *(eng-review Codex #7)*
- [ ] `create_backup_branch` re-resolves the name and retries on collision (handles TOCTOU between preview and create).
- [ ] `extract_original_name` returns the original base for all three timestamp forms (`DD-HHMM.`, `DD-HHMMSS.`, `DD-HHMMSS-N.`), including when the base name itself contains dots or digits (e.g. `feature/v2.3` → `feature/v2.3`).
- [ ] UTC labels under `HUG_FAKE_CLOCK` (not local time).
- [ ] Header doc-comment documents the new name format and lists `resolve_backup_name`.

**Verify:** `make test-lib TEST_FILE=test_hug_git_backup.bats` → all green (Task 2 lands the tests). After Task 1 alone, the lib must source cleanly: `bash -c 'set -e; . git-config/lib/hug-common; . git-config/lib/hug-git-backup; resolve_backup_name HEAD main'` in a test repo exits 0 and prints a name matching `^hug-backups/[0-9]{4}-[0-9]{2}/[0-9]{2}-[0-9]{4}\.main$`.

**Steps:**

- [ ] **Step 1: Rewrite `hug-git-backup`**

Replace the entire contents of `git-config/lib/hug-git-backup` with:

```bash
# shellcheck shell=bash
# This file is a library to be sourced by shell scripts
#
# HUG-GIT-BACKUP: Git branch backup management
#
# Backup branch name format (UTC via hug_clock_now; deterministic under
# HUG_FAKE_CLOCK so retries within the same minute never collide):
#
#   hug-backups/YYYY-MM/DD-HHMM.<base>        — default
#   hug-backups/YYYY-MM/DD-HHMMSS.<base>      — same-minute collision (widen to seconds)
#   hug-backups/YYYY-MM/DD-HHMMSS-N.<base>    — same-second collision (N=1..100)
#
# The whole timestamp+disambiguator stays BEFORE the `.<base>` dot, so the
# branch name is never ambiguous. `extract_original_name` and
# `git-bdel-backup normalize_backup_key` both parse this widened form.
#
# Why hug_clock_now instead of raw `date`: raw `date` is local-time and
# minute-precision only, which made create_backup_branch (a) untestable
# and (b) collide on retry within the same minute (#205 sub-bug 2). See
# `git-bc` for the same proven pattern.
#
# Functions:
#   - resolve_backup_name:   PURE read-only preview of the name that would be
#                            created right now. Used by --dry-run.
#   - create_backup_branch:  Creates the branch (looping on collision).
#   - get_backup_branches:   Lists existing backups.
#   - extract_original_name: Reverse-maps a backup name to its original base.
#   - format_backup_display_name: Strips the hug-backups/ prefix for display.
################################################################################
# Branch Backup
################################################################################

# (Pure) Compute the backup name that *would* be created right now.
#
# Read-only: probes `git show-ref` to skip over already-taken names on the
# collision ladder. No git writes. This is what --dry-run calls to show the
# "Backup created at …" line without side effects.
#
# @param $1  source_ref   unused for naming (kept for symmetry with
#                         create_backup_branch); only validated non-empty.
# @param $2  base_name    original branch name (e.g. "feature/v2.3")
# @output  the resolved backup name on stdout
# @return  0 on success, 1 on missing args
resolve_backup_name() {
  local source_ref="${1:-}"
  local base_name="${2:-}"

  if [[ -z "$source_ref" ]]; then
    error "Error (internal): resolve_backup_name requires a source reference." >&2
    return 1
  fi
  if [[ -z "$base_name" ]]; then
    error "Error (internal): resolve_backup_name requires a base name." >&2
    return 1
  fi

  local ym dhm secs
  ym=$(hug_clock_now "%Y-%m")
  dhm=$(hug_clock_now "%d-%H%M")
  # Base name on the ladder: DD-HHMM.<base>
  local prefix="hug-backups/${ym}/${dhm}"
  local candidate="${prefix}.${base_name}"

  if git show-ref --verify --quiet "refs/heads/$candidate" 2>/dev/null; then
    # Same-minute collision: widen to seconds.
    secs=$(hug_clock_now "%S")
    candidate="${prefix}${secs}.${base_name}"
    local counter=1
    while git show-ref --verify --quiet "refs/heads/$candidate" 2>/dev/null; do
      if [[ $counter -gt 100 ]]; then
        error "Error (internal): resolve_backup_name could not find a unique name after 100 attempts." >&2
        return 1
      fi
      candidate="${prefix}${secs}-${counter}.${base_name}"
      counter=$((counter + 1))
    done
  fi

  printf '%s\n' "$candidate"
}

# 🛡️ (Internal Helper) Creates a standardized backup branch.
#
# Used by 'hug rb' (and future destructive commands) before they perform a
# destructive operation. The name is resolved via resolve_backup_name and
# then created for real; if the actual `git branch` call fails (TOCTOU:
# another process took the name between resolve and create), the name is
# re-resolved and retried, bounded at 100 attempts.
#
# @param $1  source_ref   commit/branch to back up (e.g. "HEAD")
# @param $2  base_name    original branch name
# @output  the created backup branch name on stdout
# @return  0 on success, 1 on failure (args, or 100-attempt exhaustion)
create_backup_branch() {
  local source_ref="${1:-}"
  local base_name="${2:-}"

  if [[ -z "$source_ref" ]]; then
    error "Error (internal): create_backup_branch requires a source reference." >&2
    return 1
  fi
  if [[ -z "$base_name" ]]; then
    error "Error (internal): create_backup_branch requires a base name." >&2
    return 1
  fi

  local attempt=0
  local backup_name
  local branch_err=""
  while true; do
    if [[ $attempt -gt 100 ]]; then
      error "Error (internal): create_backup_branch failed to find a unique name after 100 attempts." >&2
      return 1
    fi

    # Re-resolve each iteration: the ladder depends only on current refs
    # and the current clock instant, both of which can move between attempts.
    backup_name=$(resolve_backup_name "$source_ref" "$base_name") || return 1

    # Capture stderr so we can distinguish a COLLISION (name now exists) from
    # a real failure (invalid source ref, bad chars, lock, permissions, etc.).
    # Without this, an invalid source_ref would loop 100x then report a
    # misleading "uniqueness" error (eng-review Codex finding #7).
    if branch_err=$(git branch "$backup_name" "$source_ref" 2>&1 >/dev/null); then
      printf '%s\n' "$backup_name"
      return 0
    fi

    # Retry ONLY if the failure is actually a collision (the candidate name
    # now exists as a real ref — meaning a concurrent writer took it between
    # resolve and create). Any other error surfaces immediately.
    if ! git show-ref --verify --quiet "refs/heads/$backup_name" 2>/dev/null; then
      error "Error (internal): create_backup_branch failed for '$backup_name': $branch_err" >&2
      return 1
    fi

    attempt=$((attempt + 1))
  done
}

# Gets list of backup branches
# Usage: branches=$(get_backup_branches)
# Output:
#   List of backup branch names (one per line) to stdout
#   Branches are sorted by refname (chronologically by date in the path)
# Returns:
#   0 if successful (even if no branches found)
get_backup_branches() {
  git for-each-ref --format='%(refname:short)' 'refs/heads/hug-backups/**' 2>/dev/null || true
}

# Extracts original branch name from a backup branch name.
# Accepts all three timestamp forms produced by create_backup_branch:
#   hug-backups/YYYY-MM/DD-HHMM.<base>
#   hug-backups/YYYY-MM/DD-HHMMSS.<base>
#   hug-backups/YYYY-MM/DD-HHMMSS-N.<base>
# Usage: original=$(extract_original_name "hug-backups/2024-11/02-1234.feature")
# Parameters:
#   $1 - Backup branch name
# Output:
#   Original branch name on stdout (unchanged input if no match)
# Note:
#   The regex strips the YYYY-MM/ prefix and the DD-HHMM[SS[-N]] timestamp,
#   leaving everything after the dot — so base names containing dots or
#   digits (e.g. "feature/v2.3") survive intact.
extract_original_name() {
  local backup="$1"
  # Match: hug-backups/YYYY-MM/ then DD-HHMM with optional SS and optional -N,
  # then a literal dot, then capture the rest (which may itself contain dots).
  echo "$backup" | sed -E 's|^hug-backups/[0-9]{4}-[0-9]{2}/[0-9]{2}-[0-9]{4}([0-9]{2}(-[0-9]+)?)\.||'
}

# Formats a backup branch name for display by removing the common prefix
# Usage: display_name=$(format_backup_display_name "hug-backups/2024-11/02-1234.feature")
# Parameters:
#   $1 - Backup branch name
# Output:
#   Display-friendly name (e.g., "2024-11/02-1234.feature") to stdout
format_backup_display_name() {
  local backup="$1"
  echo "$backup" | sed 's|^hug-backups/||'
}
```

- [ ] **Step 2: Sanity-check the lib sources cleanly**

Run: `bash -c 'set -euo pipefail; . git-config/lib/hug-common; . git-config/lib/hug-git-backup; type resolve_backup_name create_backup_branch extract_original_name'`
Expected: prints `… is a function` three times, exit 0. No syntax errors.

- [ ] **Step 3: Commit**

```bash
git add git-config/lib/hug-git-backup
git commit -m "$(cat <<'EOF'
refactor(backup): collision-proof, testable backup-branch naming

WHY: create_backup_branch used raw local-time `date +%d-%H%M` (minute
precision), which collided on retry within the same minute (#205 sub-bug 2)
and was untestable (HUG_FAKE_CLOCK did nothing). git-bc already proved the
hug_clock_now-based ladder pattern for this exact class.

WHAT: Replace raw date with hug_clock_now (UTC, deterministic). Factor the
read-only preview into resolve_backup_name (pure; used by --dry-run in a
later task). create_backup_branch loops around the actual `git branch` call
and re-resolves on failure, so uniqueness is guaranteed at the point of
creation — not at preview time (TOCTOU-safe). Collision ladder:
  DD-HHMM.<base>            — default
  DD-HHMMSS.<base>          — same-minute collision
  DD-HHMMSS-N.<base>        — same-second collision (N=1..100)
extract_original_name widened to parse all three forms; base names
containing dots/digits (e.g. feature/v2.3) survive intact.

HOW: resolve_backup_name probes git show-ref only (no writes). The ladder
mirrors git-bc's: widen to seconds first, then append a counter. The whole
timestamp+disambiguator stays before the .<base> dot so the name is never
ambiguous.

IMPACT: Removes the untestable blind spot (HUG_FAKE_CLOCK now pins names).
Eliminates the retry-within-a-minute collision. git-bdel-backup's
normalize_backup_key (next commit) is the other side of this contract —
both must parse the widened form or --delete-older-than ordering breaks.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Lib tests for `hug-git-backup` (TDD: red→green)

**Goal:** Pin the new lib's behavior with BATS tests: deterministic naming under `HUG_FAKE_CLOCK`, the collision ladder, and the widened `extract_original_name`.

**Files:**
- Create: `tests/lib/test_hug_git_backup.bats`

**Acceptance Criteria:**
- [ ] `resolve_backup_name HEAD main` under `HUG_FAKE_CLOCK=946684800` returns exactly `hug-backups/2000-01/01-0000.main` (UTC, deterministic — no host-TZ dependency).
- [ ] When a backup matching `DD-HHMM.<base>` already exists, `resolve_backup_name` returns the `DD-HHMMSS.<base>` form.
- [ ] When both `DD-HHMM` and `DD-HHMMSS` forms exist, `resolve_backup_name` returns `DD-HHMMSS-1.<base>`, then `DD-HHMMSS-2.<base>`, etc.
- [ ] `resolve_backup_name` performs no git writes — after calling it, `get_backup_branches` returns the same count as before the call.
- [ ] `create_backup_branch HEAD main` under `HUG_FAKE_CLOCK=946684800` creates exactly one branch named `hug-backups/2000-01/01-0000.main` and echoes it.
- [ ] Calling `create_backup_branch HEAD main` twice under the same `HUG_FAKE_CLOCK` produces two distinct branches (second one has seconds in its name).
- [ ] `extract_original_name` returns `feature/v2.3` for each of `hug-backups/2024-11/02-1234.feature/v2.3`, `hug-backups/2024-11/02-123456.feature/v2.3`, and `hug-backups/2024-11/02-123456-7.feature/v2.3`.
- [ ] Missing-arg paths: `resolve_backup_name "" main` returns non-zero; `create_backup_branch HEAD ""` returns non-zero.

**Verify:** `make test-lib TEST_FILE=test_hug_git_backup.bats TEST_SHOW_ALL_RESULTS=1` → all tests pass.

**Steps:**

- [ ] **Step 1: Write the failing tests**

Create `tests/lib/test_hug_git_backup.bats` with this content:

```bash
#!/usr/bin/env bats
# Lib tests for hug-git-backup: resolve_backup_name, create_backup_branch,
# extract_original_name. Pins the widened naming format and the
# HUG_FAKE_CLOCK-deterministic clock path introduced for #205 sub-bug 2.

load '../test_helper.bash'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
  # Pin the clock so names are byte-for-byte reproducible. 946684800 =
  # 2000-01-01 00:00:00 UTC. Tests in test_bc.bats use the same value.
  export HUG_FAKE_CLOCK=946684800
}

teardown() {
  cleanup_test_repo
}

# -----------------------------------------------------------------------------
# resolve_backup_name — pure read-only preview
# -----------------------------------------------------------------------------

@test "resolve_backup_name: deterministic under HUG_FAKE_CLOCK (UTC)" {
  run resolve_backup_name HEAD main
  assert_success
  assert_output "hug-backups/2000-01/01-0000.main"
}

@test "resolve_backup_name: performs no git writes" {
  local before
  before=$(get_backup_branches | wc -l)
  resolve_backup_name HEAD main >/dev/null
  local after
  after=$(get_backup_branches | wc -l)
  [[ "$before" -eq "$after" ]]
}

@test "resolve_backup_name: widens to seconds on same-minute collision" {
  # Pre-create the minute-precision name so resolve must widen.
  git branch "hug-backups/2000-01/01-0000.main" HEAD
  run resolve_backup_name HEAD main
  assert_success
  assert_output "hug-backups/2000-01/01-000000.main"
}

@test "resolve_backup_name: appends -N on same-second collision" {
  git branch "hug-backups/2000-01/01-0000.main" HEAD
  git branch "hug-backups/2000-01/01-000000.main" HEAD
  run resolve_backup_name HEAD main
  assert_success
  assert_output "hug-backups/2000-01/01-000000-1.main"
}

@test "resolve_backup_name: rejects empty args" {
  run resolve_backup_name "" main
  assert_failure
  run resolve_backup_name HEAD ""
  assert_failure
}

# -----------------------------------------------------------------------------
# create_backup_branch — real creation, collision-safe
# -----------------------------------------------------------------------------

@test "create_backup_branch: creates and echoes the expected name" {
  run create_backup_branch HEAD main
  assert_success
  assert_output "hug-backups/2000-01/01-0000.main"
  # Branch actually exists.
  git show-ref --verify "refs/heads/hug-backups/2000-01/01-0000.main"
}

@test "create_backup_branch: two calls under the same clock produce distinct names" {
  run create_backup_branch HEAD main
  assert_success
  local first="$output"

  run create_backup_branch HEAD main
  assert_success
  local second="$output"

  [[ "$first" != "$second" ]]
  # Second call should land on the seconds form.
  [[ "$second" == "hug-backups/2000-01/01-000000.main" ]]
  # Both branches exist.
  git show-ref --verify "refs/heads/$first"
  git show-ref --verify "refs/heads/$second"
}

@test "create_backup_branch: rejects empty args" {
  run create_backup_branch "" main
  assert_failure
  run create_backup_branch HEAD ""
  assert_failure
}

# -----------------------------------------------------------------------------
# extract_original_name — widened to all three timestamp forms
# -----------------------------------------------------------------------------

@test "extract_original_name: handles the DD-HHMM form" {
  run extract_original_name "hug-backups/2024-11/02-1234.feature/v2.3"
  assert_success
  assert_output "feature/v2.3"
}

@test "extract_original_name: handles the DD-HHMMSS form" {
  run extract_original_name "hug-backups/2024-11/02-123456.feature/v2.3"
  assert_success
  assert_output "feature/v2.3"
}

@test "extract_original_name: handles the DD-HHMMSS-N form" {
  run extract_original_name "hug-backups/2024-11/02-123456-7.feature/v2.3"
  assert_success
  assert_output "feature/v2.3"
}

@test "extract_original_name: passes through non-matching input unchanged" {
  run extract_original_name "some-other-branch"
  assert_success
  assert_output "some-other-branch"
}
```

- [ ] **Step 2: Run the tests — they should pass**

Run: `make test-lib TEST_FILE=test_hug_git_backup.bats TEST_SHOW_ALL_RESULTS=1`
Expected: all tests pass (Task 1 already landed the implementation; this task locks it in).

- [ ] **Step 3: Commit**

```bash
git add tests/lib/test_hug_git_backup.bats
git commit -m "$(cat <<'EOF'
test(backup): pin resolve_backup_name + collision ladder + widened parser

WHY: hug-git-backup was untestable (raw date). The previous commit added
HUG_FAKE_CLOCK-deterministic naming; this commit locks the contract so a
future regression is caught in seconds.

WHAT: tests/lib/test_hug_git_backup.bats covers resolve_backup_name (pure
read-only, deterministic under HUG_FAKE_CLOCK, collision ladder), the real
create_backup_branch loop, and extract_original_name across all three
widened timestamp forms — including base names containing dots/digits
(feature/v2.3) which the old regex would have truncated.

HOW: Uses the same HUG_FAKE_CLOCK=946684800 (2000-01-01 UTC) anchor as
test_bc.bats for consistency. Pure-preview tests assert no git writes by
counting get_backup_branches output before/after.

IMPACT: Green test suite is the success signal for Task 1. Downstream
tasks (rb, dry-run) can rely on resolve_backup_name's contract.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `git-bdel-backup` — widen `normalize_backup_key` + its lib test

**Goal:** Keep `--delete-older-than` ordering correct when backup names carry seconds precision (the new form from Task 1). Without this, a seconds-precision name fails to normalize, sorts as garbage, and `--delete-older-than` either over- or under-deletes.

**Files:**
- Modify: `git-config/bin/git-bdel-backup:160-167` (the `normalize_backup_key` helper)
- Create: `tests/lib/test_hug_git_bdel_backup_keys.bats`

**Acceptance Criteria:**
- [ ] `normalize_backup_key` parses all three timestamp forms (with the seconds group **OPTIONAL** so legacy `DD-HHMM` names still normalize — eng-review Codex #2):
  - `hug-backups/2024-11/02-1234.feature` → `2024-11/02-1234`
  - `hug-backups/2024-11/02-123456.feature` → `2024-11/02-1234` (seconds mapped to minute precision for comparison)
  - `hug-backups/2024-11/02-123456-7.feature` → `2024-11/02-1234`
- [ ] Non-matching input (e.g. an unrelated branch name) passes through unchanged (same behavior as before, so unrelated listings don't break).
- [ ] `is_older_than_pattern` semantics: a backup at minute M normalizes to minute M, and the existing `<=` comparison means a seconds-precision backup at M:SS IS considered "older than or equal to" a threshold at minute M (matches existing behavior where exact-threshold matches are included). The test asserts this contract, NOT the opposite. *(eng-review Codex #3)*

**Verify:** `make test-lib TEST_FILE=test_hug_git_bdel_backup_keys.bats TEST_SHOW_ALL_RESULTS=1` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing test (red)**

Create `tests/lib/test_hug_git_bdel_backup_keys.bats`. **CRITICAL — safe sourcing (eng-review Codex #4):** `git-bdel-backup` is a SCRIPT, not a library — its bottom line (`hug_bdel_backup "${backup_branches_to_delete[@]}"`) would EXECUTE the whole command if sourced. `|| true` does not protect against the script calling `exit`. So we sed-extract ONLY the two helper functions into the test shell — never source the script itself.

```bash
#!/usr/bin/env bats
# Lib tests for git-bdel-backup's normalize_backup_key / is_older_than_pattern.
# Pins the widened timestamp parsing introduced alongside hug-git-backup's
# new DD-HHMM[SS[-N]] naming (see test_hug_git_backup.bats).

load '../test_helper.bash'

# Path to the git-bdel-backup script (resolved at load time, not via sourcing).
BDScript="${HUG_HOME:-$(hug rev-parse --hug-home 2>/dev/null)}/git-config/bin/git-bdel-backup"

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
  # SAFE EXTRACTION: git-bdel-backup is a script (executes at the bottom),
  # NOT a library. Sourcing it would run hug_bdel_backup and possibly exit
  # the BATS shell. Extract ONLY the two pure helper functions (eng-review
  # Codex #4). If the script ever grows a `BASH_SOURCE[0] == "$0"` main
  # guard, this can switch to plain sourcing.
  if [[ -f "$BDScript" ]]; then
    eval "$(sed -n '/^normalize_backup_key()/,/^}/p; /^is_older_than_pattern()/,/^}/p' "$BDScript")"
  fi
  # Verify extraction worked; skip the file gracefully if not.
  if ! type normalize_backup_key >/dev/null 2>&1; then
    skip "could not extract normalize_backup_key from $BDScript"
  fi
}

teardown() {
  cleanup_test_repo
}

@test "normalize_backup_key: parses legacy DD-HHMM form (eng-review Codex #2 — must not break)" {
  run normalize_backup_key "hug-backups/2024-11/02-1234.feature"
  assert_success
  assert_output "2024-11/02-1234"
}

@test "normalize_backup_key: maps DD-HHMMSS to minute precision" {
  run normalize_backup_key "hug-backups/2024-11/02-123456.feature"
  assert_success
  assert_output "2024-11/02-1234"
}

@test "normalize_backup_key: maps DD-HHMMSS-N to minute precision" {
  run normalize_backup_key "hug-backups/2024-11/02-123456-7.feature"
  assert_success
  assert_output "2024-11/02-1234"
}

@test "normalize_backup_key: non-matching input passes through unchanged" {
  run normalize_backup_key "some-other-branch"
  assert_success
  assert_output "some-other-branch"
}

@test "is_older_than_pattern: seconds-precision backup AT threshold minute IS older-or-equal (eng-review Codex #3)" {
  # Contract: a backup at 10:06:37 normalizes to minute 10:06. The existing
  # is_older_than_pattern uses `<=` (line 205 of git-bdel-backup), so a backup
  # at the threshold minute IS considered "older than or equal" — same as a
  # minute-precision backup at 10:06 would be against threshold 10:06. The
  # function returns 0 (true) in that case.
  run is_older_than_pattern "hug-backups/2024-11/03-100637.x" "2024-11/03-1006"
  assert_success
}

@test "is_older_than_pattern: minute-precision backup older than later threshold" {
  # Backup at 10:06 IS older than threshold 10:07.
  run is_older_than_pattern "hug-backups/2024-11/03-1006.x" "2024-11/03-1007"
  assert_success
}

@test "is_older_than_pattern: backup after threshold is NOT older" {
  # Backup at 10:08 is NOT older than threshold 10:07.
  run is_older_than_pattern "hug-backups/2024-11/03-1008.x" "2024-11/03-1007"
  [[ "$status" -ne 0 ]]
}
```

- [ ] **Step 2: Run the test — it should fail (red)**

Run: `make test-lib TEST_FILE=test_hug_git_bdel_backup_keys.bats`
Expected: the `DD-HHMMSS` and `DD-HHMMSS-N` normalization tests fail (current regex captures exactly `[0-9]{4}` after the dash, so seconds names don't match and pass through unchanged).

- [ ] **Step 3: Widen `normalize_backup_key` (seconds group OPTIONAL — eng-review Codex #2)**

Edit `git-config/bin/git-bdel-backup` — replace the `normalize_backup_key` body (currently around lines 160-167) with:

```bash
# Helper function to normalize backup branch name format to comparison key.
# Converts the widened timestamp forms to a MINUTE-precision key so that
# --delete-older-than lexicographic comparison stays correct when backups
# exist at seconds precision (the new form from hug-git-backup):
#   hug-backups/2024-11/02-1234.feature      -> 2024-11/02-1234
#   hug-backups/2024-11/02-123456.feature    -> 2024-11/02-1234   (seconds dropped)
#   hug-backups/2024-11/02-123456-7.feature  -> 2024-11/02-1234   (seconds+counter dropped)
# Non-matching input passes through unchanged.
#
# NOTE: the seconds group `([0-9]{2}(-[0-9]+)?)?` is OPTIONAL (trailing `?`).
# Making it required would break normalization of legacy DD-HHMM names
# (eng-review Codex #2) and cause --delete-older-than to under-delete old
# backups.
normalize_backup_key() {
  local backup="$1"
  echo "$backup" | sed -E 's|^hug-backups/([0-9]{4}-[0-9]{2}/[0-9]{2}-[0-9]{4})([0-9]{2}(-[0-9]+)?)?\..*$|\1|'
}
```

- [ ] **Step 4: Run the test — it should pass (green)**

Run: `make test-lib TEST_FILE=test_hug_git_bdel_backup_keys.bats TEST_SHOW_ALL_RESULTS=1`
Expected: all tests pass, including the legacy `DD-HHMM` case.

- [ ] **Step 5: Run the existing bdel-backup unit tests to confirm no regression**

Run: `make test-unit TEST_FILE=test_bdel_backup.bats`
Expected: all existing tests still pass (no regression on minute-precision names).

- [ ] **Step 6: Commit**

```bash
git add git-config/bin/git-bdel-backup tests/lib/test_hug_git_bdel_backup_keys.bats
git commit -m "$(cat <<'EOF'
fix(bdel-backup): parse widened timestamp so --delete-older-than stays correct

WHY: The previous commit (hug-git-backup) introduced seconds-precision
backup names for collision safety. git-bdel-backup's normalize_backup_key
captured exactly [0-9]{4} (HHMM), so a name like 11-100637.feature failed
to normalize, the un-normalized hug-backups/… string sorted as garbage,
and --delete-older-than mis-classified it (#205 sub-bug 2's downstream
cousin — Codex caught this coupling during design review).

WHAT: Widen normalize_backup_key's regex to accept DD-HHMM, DD-HHMMSS,
and DD-HHMMSS-N, and MAP seconds names down to minute precision so the
existing lexicographic compare in is_older_than_pattern stays correct:
11-100637 normalizes to 11-1006, and is_older_than_pattern compares the
minute keys directly.

HOW: One sed group: capture YYYY-MM/DD-HHMM in \1, consume optional
SS and -N, keep \1. Non-matching input passes through (unchanged
behavior — unrelated branches don't get mangled).

IMPACT: --delete-older-than with mixed minute/second backups deletes
exactly the right set. Tested in isolation + existing bdel-backup suite
unchanged.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `hug-git-rebase` — plan/render helpers + the in-progress guard

**Goal:** House the shared `rb_build_plan` (pure) and `rb_render_plan` (→stderr) helpers in `hug-git-rebase` (keeping `git-rb` a thin orchestrator per `bin/CLAUDE.md`), and add `rb_assert_no_rebase_in_progress` covering BOTH the `rebase-merge` and `rebase-apply` backends (D7).

**Files:**
- Modify: `git-config/lib/hug-git-rebase` (append new helpers; ~190 LOC → ~270 LOC)
- Create: `tests/lib/test_hug_git_rebase.bats`

**Acceptance Criteria:**
- [ ] `rb_assert_no_rebase_in_progress` errors and returns non-zero if either `rebase-merge` OR `rebase-apply` state dir exists; returns 0 otherwise. Error message points the user at `hug rbc` / `hug rba`.
- [ ] `rb_assert_no_rebase_in_progress` is **worktree-aware** (eng-review Codex #1): uses `git rev-parse --git-path <sub>` (NOT a literal `.git/<sub>` path), so it correctly detects an in-progress rebase in BOTH plain repos AND linked worktrees (where `.git` is a file, not a directory).
- [ ] `rb_build_plan` is pure (no writes), reads target/current/commit-count/diffstat and produces a structured plan: `RB_PLAN_TARGET`, `RB_PLAN_CURRENT`, `RB_PLAN_NUM_COMMITS`, `RB_PLAN_WILL_BACKUP` (`true`/`false`), `RB_PLAN_TIER` (`warn`/`danger`), `RB_PLAN_AUTH_FLAG` (`-y`/`-f`), and `RB_PLAN_BACKUP_NAME` (resolved via `resolve_backup_name`).
- [ ] `rb_render_plan` writes only to stderr (stdout stays clean per the project's stdout discipline). Output includes: commit list, diffstat, backup disposition ("Would create backup at …" / "Would skip backup (--no-backup)"), and the authorization hint ("warn-tier; non-interactive needs -y" / "danger-tier; needs -f").
- [ ] `rb_render_plan` honors `HUG_QUIET` — when `HUG_QUIET=T`, it renders nothing (the preview chatter is what `--quiet` is for).
- [ ] New helpers source cleanly as part of `hug-git-kit` (no extra source lines needed in callers — already aggregated).

**Verify:** `make test-lib TEST_FILE=test_hug_git_rebase.bats TEST_SHOW_ALL_RESULTS=1` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing tests**

Create `tests/lib/test_hug_git_rebase.bats`. **CRITICAL — harness must source helpers (eng-review Codex #6):** `bash -c "source <(rb_build_plan …); rb_render_plan"` won't have the functions unless they're sourced into the child shell first. Every subshell that calls a helper must explicitly source `hug-common` + `hug-git-kit` (which transitively sources `hug-git-rebase`).

```bash
#!/usr/bin/env bats
# Lib tests for hug-git-rebase plan/render helpers and the in-progress guard.

load '../test_helper.bash'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"
  # Build a tiny history: main has 1 commit; create a feature with 1 more.
  git checkout -q -b feature
  echo "feature" > feature.txt
  git add feature.txt
  git commit -q -m "feature commit"
  git checkout -q main
  export HUG_FAKE_CLOCK=946684800
}

teardown() {
  cleanup_test_repo
}

# Resolve HUG_HOME for child shells (BATS subshells don't inherit it).
_HUG_HOME="${HUG_HOME:-$(hug rev-parse --hug-home 2>/dev/null)}"

# -----------------------------------------------------------------------------
# rb_assert_no_rebase_in_progress — D7 guard
# -----------------------------------------------------------------------------

@test "rb_assert_no_rebase_in_progress: passes when no rebase state exists" {
  run rb_assert_no_rebase_in_progress
  assert_success
}

@test "rb_assert_no_rebase_in_progress: blocks on rebase-merge backend" {
  mkdir -p "$(git rev-parse --git-path rebase-merge)"
  run rb_assert_no_rebase_in_progress
  assert_failure
  assert_output --partial "rebase already in progress"
}

@test "rb_assert_no_rebase_in_progress: blocks on rebase-apply backend" {
  mkdir -p "$(git rev-parse --git-path rebase-apply)"
  run rb_assert_no_rebase_in_progress
  assert_failure
  assert_output --partial "rebase already in progress"
}

@test "rb_assert_no_rebase_in_progress: error mentions rbc and rba" {
  mkdir -p "$(git rev-parse --git-path rebase-merge)"
  run rb_assert_no_rebase_in_progress
  assert_failure
  assert_output --partial "hug rbc"
  assert_output --partial "hug rba"
}

# -----------------------------------------------------------------------------
# rb_build_plan — pure structuring
# -----------------------------------------------------------------------------

@test "rb_build_plan: warn-tier when backup is on" {
  run rb_build_plan main feature false
  assert_success
  # Output is a set of VAR=value lines we eval in the caller. Check tier + auth.
  assert_output --partial "RB_PLAN_TIER=warn"
  assert_output --partial "RB_PLAN_AUTH_FLAG=-y"
  assert_output --partial "RB_PLAN_WILL_BACKUP=true"
  assert_output --partial "RB_PLAN_NUM_COMMITS=1"
}

@test "rb_build_plan: danger-tier when --no-backup" {
  run rb_build_plan main feature true
  assert_success
  assert_output --partial "RB_PLAN_TIER=danger"
  assert_output --partial "RB_PLAN_AUTH_FLAG=-f"
  assert_output --partial "RB_PLAN_WILL_BACKUP=false"
}

@test "rb_build_plan: resolves a backup name matching the new format" {
  run rb_build_plan main feature false
  assert_success
  assert_output --partial "RB_PLAN_BACKUP_NAME=hug-backups/2000-01/01-0000.feature"
}

# -----------------------------------------------------------------------------
# rb_render_plan — stderr discipline + quiet
#
# ENG-REVIEW CODEX #6: every subshell MUST source hug-common + hug-git-kit
# before calling rb_build_plan / rb_render_plan. A bare `bash -c "source
# <(rb_build_plan …)"` won't have the functions.
# -----------------------------------------------------------------------------

@test "rb_render_plan: writes nothing to stdout" {
  # Source helpers, build+eval the plan, render with stderr suppressed.
  # stdout must be empty (stdout discipline).
  run bash -c "
    . '$_HUG_HOME/git-config/lib/hug-common'
    . '$_HUG_HOME/git-config/lib/hug-git-kit'
    cd '$TEST_REPO'
    eval \"\$(rb_build_plan main feature false)\"
    rb_render_plan 2>/dev/null
  "
  assert_success
  assert_output ""
}

@test "rb_render_plan: includes backup disposition and auth hint" {
  run bash -c "
    . '$_HUG_HOME/git-config/lib/hug-common'
    . '$_HUG_HOME/git-config/lib/hug-git-kit'
    cd '$TEST_REPO'
    eval \"\$(rb_build_plan main feature false)\"
    rb_render_plan 2>&1
  "
  assert_success
  assert_output --partial "backup"
  assert_output --partial "-y"
}

@test "rb_render_plan: silent when HUG_QUIET=T" {
  # HUG_QUIET must be exported BEFORE the subshell so rb_render_plan sees it.
  HUG_QUIET=T run bash -c "
    . '$_HUG_HOME/git-config/lib/hug-common'
    . '$_HUG_HOME/git-config/lib/hug-git-kit'
    cd '$TEST_REPO'
    eval \"\$(rb_build_plan main feature false)\"
    rb_render_plan 2>&1
  "
  assert_success
  assert_output ""
}
```

- [ ] **Step 2: Run the test — it should fail (red)**

Run: `make test-lib TEST_FILE=test_hug_git_rebase.bats`
Expected: fails because `rb_assert_no_rebase_in_progress`, `rb_build_plan`, `rb_render_plan` don't exist yet.

- [ ] **Step 3: Add the helpers to `hug-git-rebase`**

Append to `git-config/lib/hug-git-rebase` (at end of file):

```bash

################################################################################
# hug rb orchestration helpers (plan → render → execute)
#
# These keep git-rb a thin orchestrator (per bin/CLAUDE.md): the pure
# structuring (rb_build_plan) and the stderr-only rendering (rb_render_plan)
# live here so git-rb's job is just "validate → plan → (dry-run|confirm) → execute".
# rb_assert_no_rebase_in_progress gates entry so a paused rebase doesn't get a
# fresh backup+rebase heaped on top of it (D7).
################################################################################

# Error and return non-zero if a rebase is already in progress.
# Checks BOTH backends:
#   - rebase-merge  (the merge backend; the default)
#   - rebase-apply  (the apply/`am` backend)
# Uses `git rev-parse --git-path` to resolve the path WORKTREE-AWARE
# (eng-review Codex #1): in linked worktrees, `.git` is a FILE pointing at
# the main repo's worktrees/<name>/ dir, so a literal `.git/rebase-merge`
# check would silently miss an in-progress rebase and create the orphan
# backup this guard exists to prevent. `--git-path` resolves correctly in
# both plain repos and linked worktrees.
rb_assert_no_rebase_in_progress() {
  local sub
  for sub in "rebase-merge" "rebase-apply"; do
    local dir
    dir=$(git rev-parse --git-path "$sub" 2>/dev/null || true)
    if [[ -n "$dir" && -d "$dir" ]]; then
      error "A rebase is already in progress (found $dir). Run 'hug rbc' to continue after resolving conflicts, or 'hug rba' to abort, then retry."
      return 1
    fi
  done
  return 0
}

# (Pure) Build the rebase plan as VAR=value lines on stdout for the caller
# to eval. Read-only: no git writes, no confirmations.
#
# @param $1  target_branch   the branch to rebase onto
# @param $2  current_branch  the branch being rebased
# @param $3  no_backup       "true" or "false" — whether --no-backup was passed
# @output  VAR=value lines:
#   RB_PLAN_TARGET, RB_PLAN_CURRENT, RB_PLAN_NUM_COMMITS, RB_PLAN_WILL_BACKUP,
#   RB_PLAN_TIER (warn|danger), RB_PLAN_AUTH_FLAG (-y|-f),
#   RB_PLAN_BACKUP_NAME (best-effort; may drift if clock/ref moves before create)
rb_build_plan() {
  local target_branch="$1"
  local current_branch="$2"
  local no_backup="${3:-false}"

  local num_commits
  num_commits=$(count_commits_in_range "$target_branch" HEAD)

  local will_backup="true"
  local tier="warn"
  local auth_flag="-y"
  local backup_name=""
  if [[ "$no_backup" == "true" ]]; then
    will_backup="false"
    tier="danger"
    auth_flag="-f"
  else
    # Best-effort preview name. The post-create tip is authoritative; see
    # resolve_backup_name for the TOCTOU story.
    backup_name=$(resolve_backup_name HEAD "$current_branch")
  fi

  printf 'RB_PLAN_TARGET=%q\n' "$target_branch"
  printf 'RB_PLAN_CURRENT=%q\n' "$current_branch"
  printf 'RB_PLAN_NUM_COMMITS=%d\n' "$num_commits"
  printf 'RB_PLAN_WILL_BACKUP=%s\n' "$will_backup"
  printf 'RB_PLAN_TIER=%s\n' "$tier"
  printf 'RB_PLAN_AUTH_FLAG=%s\n' "$auth_flag"
  printf 'RB_PLAN_BACKUP_NAME=%q\n' "$backup_name"
}

# Render the plan to stderr (stdout stays clean for scriptability).
# Honors HUG_QUIET=T (renders nothing — --quiet is for automation).
rb_render_plan() {
  [[ "${HUG_QUIET:-}" == "T" ]] && return 0

  local num_commits="${RB_PLAN_NUM_COMMITS:-0}"
  local commit_word="commit"
  [[ "$num_commits" -gt 1 ]] && commit_word="commits"

  printf 'Commits to be rebased:\n' >&2
  print_commit_list_in_range "${RB_PLAN_TARGET}" HEAD >&2

  local range_for_diff="${RB_PLAN_TARGET}..HEAD"
  if git diff --quiet "$range_for_diff"; then
    printf '\nPreview: no file changes in %d %s.\n' "$num_commits" "$commit_word" >&2
  else
    printf '\nPreview: changes in %d %s:\n' "$num_commits" "$commit_word" >&2
    git diff --stat "$range_for_diff" >&2
  fi

  if [[ "${RB_PLAN_WILL_BACKUP}" == "true" ]]; then
    printf '\nBackup: would create backup at %s\n' "${RB_PLAN_BACKUP_NAME}" >&2
  else
    printf '\nBackup: would SKIP backup (--no-backup)\n' >&2
  fi

  if [[ "${RB_PLAN_TIER}" == "warn" ]]; then
    printf 'Authorization: warn-tier; a non-interactive run needs %s\n' "${RB_PLAN_AUTH_FLAG}" >&2
  else
    printf 'Authorization: danger-tier; needs %s (typed-word confirmation interactively)\n' "${RB_PLAN_AUTH_FLAG}" >&2
  fi
}
```

- [ ] **Step 4: Run the test — it should pass (green)**

Run: `make test-lib TEST_FILE=test_hug_git_rebase.bats TEST_SHOW_ALL_RESULTS=1`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add git-config/lib/hug-git-rebase tests/lib/test_hug_git_rebase.bats
git commit -m "$(cat <<'EOF'
feat(rebase-lib): plan/render helpers + dual-backend in-progress guard

WHY: git-rb duplicated its preview block (dry-run vs confirm) and had no
guard against starting a rebase when one was already paused — which would
create a fresh orphan backup and then fail at `git rebase`. The plan→render
split lets both paths share one faithful preview, and the guard (D7) is
required before the orchestrator rewrite.

WHAT: rb_build_plan is pure — structures target/current/commit-count,
backup disposition, confirmation tier (warn when backup on; danger when
--no-backup), the auth flag a non-interactive run needs (-y / -f), and
the best-effort resolved backup name. rb_render_plan writes the plan to
stderr only (stdout discipline) and honors HUG_QUIET. rb_assert_no_rebase
_in_progress checks BOTH .git/rebase-merge (merge backend, default) and
.git/rebase-apply (apply/am backend) — the existing abort_if_no_rebase
_conflict checked only rebase-merge and so was insufficient as an entry
guard.

HOW: rb_build_plan emits VAR=value lines the caller evals (Bash-friendly
via %q), keeping the orchestrator declarative. Tier follows the backup
(danger ⇔ no recovery net), matching the family invariant: -y clears
warn, only -f clears danger. resolve_backup_name is reused from
hug-git-backup so dry-run and the real run agree on the name format.

IMPACT: Unblocks the git-rb rewrite (next commit). Resurrects the
currently-dead conflict-guidance branch by making the guard run BEFORE
any side effect. Closes the "starting a rebase on a paused rebase"
latent defect Codex found during design review.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: `git-rb` orchestrator rewrite + `tests/unit/test_rb.bats`

**Goal:** Rewrite `git-rb` to adopt the plan→render→execute flow, fixing all four sub-bugs (#1, #2, #3a, #3b) and both bonus defects (dead conflict branch, `--quiet` authorizes). Add net-new BATS coverage.

**Files:**
- Modify: `git-config/bin/git-rb` (rewrite `hug_rb()` function and `show_help`)
- Create: `tests/unit/test_rb.bats`

**Acceptance Criteria:**
- [ ] **#3b exit code:** `hug rb <target> -f --no-backup` on a clean linear-ahead repo exits 0 with `Success` output.
- [ ] **Conflict guidance:** On a conflicting rebase, exit is non-zero AND the stderr contains `hug rbc` and `hug rba` (proves the resurrected branch).
- [ ] **#1 non-interactive:** `hug rb <target> -y` in a non-TTY proceeds and creates a backup (warn-tier honors `-y`).
- [ ] **#1 cancel:** Bare `hug rb <target>` in a non-TTY cancels (exit 1) with `Non-interactive environment`.
- [ ] **#3a tier routing:** `hug rb <target> --no-backup -y` rejects with exit 3 (danger-tier refuses `-y`).
- [ ] **#3a force path:** `hug rb <target> --no-backup -f` proceeds with no backup created.
- [ ] **#2 no orphan:** A cancelled `hug rb <target>` (non-interactive, no `-y`) creates ZERO backup branches.
- [ ] **#2 collision:** Two `hug rb <target> -y` runs under the same `HUG_FAKE_CLOCK` produce distinct backup names (no collision, no error).
- [ ] **D6 quiet never authorizes:** `hug rb <target> --quiet` alone in a non-TTY does NOT proceed (cancels like the bare non-interactive case).
- [ ] **D7 guard:** With `.git/rebase-merge` OR `.git/rebase-apply` present, `hug rb <target> -y` refuses with `rebase already in progress` and creates NO backup.
- [ ] **Dry-run side-effect-free:** After `hug rb <target> --dry-run`, HEAD hash and branch list are unchanged, and no new backup branch exists.
- [ ] **Dry-run preview content:** `hug rb <target> --dry-run` stderr contains the backup disposition ("would create backup" or "SKIP backup") and the authorization hint ("-y" or "-f").
- [ ] **Ad-hoc `--no-backup requires --force` guard removed:** The old hard-error at `:146` is gone; `--no-backup` without `-f`/`-y` now routes through the danger-tier confirm.

**Verify:** `make test-unit TEST_FILE=test_rb.bats TEST_SHOW_ALL_RESULTS=1` → all pass. Plus `make test-unit TEST_FILE=test_bdel_backup.bats` still green (Task 3 didn't regress it).

**Steps:**

- [ ] **Step 1: Write the failing tests (red — the current git-rb will fail several)**

Create `tests/unit/test_rb.bats`:

```bash
#!/usr/bin/env bats
# Net-new coverage for hug rb. Closes elifarley/hug-scm#205:
#   #3b — exit code lies on --no-backup success
#   #2  — backup collision / orphan on cancel+retry
#   #1  — non-interactive cancel with no opt-in
#   #3a — ad-hoc --no-backup guard
# Plus the two latent defects (dead conflict branch; --quiet authorizes).

load '../test_helper.bash'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
  # Base history: main + a feature branch one commit ahead of main.
  git commit -q --allow-empty -m "main 1"
  git checkout -q -b feature
  echo "x" > x.txt
  git add x.txt
  git commit -q -m "feature 1"
  git checkout -q main
  export HUG_FAKE_CLOCK=946684800
}

teardown() {
  cleanup_test_repo
}

# Helper: count hug-backups/* branches.
count_backups() {
  git for-each-ref --format='%(refname:short)' 'refs/heads/hug-backups/**' 2>/dev/null | wc -l
}

# -----------------------------------------------------------------------------
# #3b — exit code lies
# -----------------------------------------------------------------------------

@test "rb: --no-backup -f on clean linear-ahead exits 0" {
  git checkout -q feature
  run hug rb main -f --no-backup
  assert_success
  assert_output --partial "successful"
  [[ "$(count_backups)" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# Conflict guidance resurrected (bonus defect found tracing #3b)
# -----------------------------------------------------------------------------

@test "rb: on conflict, exit non-zero AND conflict guidance printed" {
  # Make main diverge so the rebase conflicts.
  git checkout -q main
  echo "conflict" > x.txt
  git add x.txt
  git commit -q -m "main conflicting"
  git checkout -q feature

  run hug rb main -y
  assert_failure
  assert_output --partial "hug rbc"
  assert_output --partial "hug rba"
  # Abort the paused rebase so teardown can clean up.
  git rebase --abort 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# #1 — non-interactive tier routing
# -----------------------------------------------------------------------------

@test "rb: -y proceeds in non-TTY (warn-tier honors -y)" {
  git checkout -q feature
  # </dev/null forces non-interactive stdin.
  run bash -c "hug rb main -y </dev/null"
  assert_success
  [[ "$(count_backups)" -eq 1 ]]
}

@test "rb: bare non-interactive cancels (exit 1)" {
  git checkout -q feature
  run bash -c "hug rb main </dev/null"
  assert_failure
  assert_output --partial "Non-interactive"
}

@test "rb: --no-backup -y rejects with exit 3 (danger refuses -y)" {
  git checkout -q feature
  run bash -c "hug rb main --no-backup -y </dev/null"
  [[ "$status" -eq 3 ]]
  assert_output --partial "requires --force"
}

@test "rb: --no-backup -f proceeds with no backup" {
  git checkout -q feature
  run bash -c "hug rb main --no-backup -f </dev/null"
  assert_success
  [[ "$(count_backups)" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# #2 — no orphan on cancel; no collision on retry
# -----------------------------------------------------------------------------

@test "rb: cancelled run creates ZERO backup branches" {
  git checkout -q feature
  # Bare non-interactive cancels before authorization — backup must not exist.
  run bash -c "hug rb main </dev/null"
  assert_failure
  [[ "$(count_backups)" -eq 0 ]]
}

@test "rb: two runs under the same HUG_FAKE_CLOCK produce distinct backups" {
  git checkout -q feature
  hug rb main -y >/dev/null 2>&1
  # Rewind feature to its pre-rebase state and re-run in the same clock minute.
  git reset --hard HEAD@{1} >/dev/null 2>&1 || git reset --hard feature >/dev/null 2>&1 || true
  # Re-create the feature commit so there's something to rebase again.
  git checkout -q -B feature main
  echo "y" > y.txt
  git add y.txt
  git commit -q -m "feature 2"

  run hug rb main -y
  assert_success
  # Two backups total, both distinct.
  [[ "$(count_backups)" -ge 2 ]]
}

# -----------------------------------------------------------------------------
# D6 — --quiet never authorizes
# -----------------------------------------------------------------------------

@test "rb: --quiet alone does not authorize in non-TTY" {
  git checkout -q feature
  run bash -c "hug rb main --quiet </dev/null"
  assert_failure
  assert_output --partial "Non-interactive"
  [[ "$(count_backups)" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# D7 — refuse to start when a rebase is already in progress
# -----------------------------------------------------------------------------

@test "rb: refuses on rebase-merge backend, creates no backup" {
  git checkout -q feature
  mkdir -p .git/rebase-merge
  run hug rb main -y
  assert_failure
  assert_output --partial "rebase already in progress"
  [[ "$(count_backups)" -eq 0 ]]
  rmdir .git/rebase-merge 2>/dev/null || true
}

@test "rb: refuses on rebase-apply backend, creates no backup" {
  git checkout -q feature
  mkdir -p .git/rebase-apply
  run hug rb main -y
  assert_failure
  assert_output --partial "rebase already in progress"
  [[ "$(count_backups)" -eq 0 ]]
  rmdir .git/rebase-apply 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# --dry-run — faithful preview, zero side effects
# -----------------------------------------------------------------------------

@test "rb: --dry-run changes nothing and shows backup disposition + auth hint" {
  git checkout -q feature
  local head_before
  head_before=$(git rev-parse HEAD)
  local branches_before
  branches_before=$(git for-each-ref --format='%(refname)' refs/heads/ | wc -l)

  run hug rb main --dry-run
  assert_success
  assert_output --partial "would create backup"
  assert_output --partial "-y"

  # No side effects.
  [[ "$(git rev-parse HEAD)" == "$head_before" ]]
  [[ "$(git for-each-ref --format='%(refname)' refs/heads/ | wc -l)" -eq "$branches_before" ]]
}

@test "rb: --dry-run --no-backup shows skip + needs -f" {
  git checkout -q feature
  run hug rb main --dry-run --no-backup
  assert_success
  assert_output --partial "SKIP backup"
  assert_output --partial "-f"
}

# -----------------------------------------------------------------------------
# #3a — ad-hoc guard removed
# -----------------------------------------------------------------------------

@test "rb: --no-backup without -f/-y no longer hard-errors; routes to danger-tier" {
  # The old behavior: `--no-backup requires --force` hard error. New behavior:
  # in an interactive context it would prompt for the typed word. In a
  # non-TTY, danger-tier cancels with the standard "Non-interactive" message
  # (NOT the ad-hoc guard message).
  git checkout -q feature
  run bash -c "hug rb main --no-backup </dev/null"
  assert_failure
  # The ad-hoc message must be gone.
  ! assert_output --partial "--no-backup requires --force"
}
```

- [ ] **Step 2: Run the tests — most should fail (red)**

Run: `make test-unit TEST_FILE=test_rb.bats 2>&1 | tail -40`
Expected: several failures (current `git-rb` has the bugs).

- [ ] **Step 3: Rewrite `git-rb`'s `hug_rb()` function and `show_help`**

Edit `git-config/bin/git-rb`. Replace the body of `hug_rb()` (currently lines 81-188) with:

```bash
# --- Internal function for 'hug rb' ---
#
# Flow: validate → tree_guard → build_plan → render_plan →
#       (dry-run returns 0 | confirm(tier) → backup → rebase → status report).
#
# Fixes elifarley/hug-scm#205: honest exit codes (#3b), no orphan backups
# (#2), documented non-interactive opt-in via -y (#1), dynamic tier replaces
# the ad-hoc --no-backup guard (#3a), resurrected conflict guidance, and
# --quiet no longer authorizes (D6).
hug_rb() {
  local target_branch="$1"
  local no_backup="$2"
  local current_branch
  local backup_name=""

  check_git_repo

  # Validate target branch exists.
  ensure_commit_exists "$target_branch"

  # D7: refuse to start if a rebase is already in progress. Must run BEFORE
  # any side effect (backup creation would orphan; rebase would fail confusingly).
  rb_assert_no_rebase_in_progress

  current_branch=$(git rev-parse --abbrev-ref HEAD)
  if [[ "$current_branch" == "HEAD" ]]; then
    error "You are in detached HEAD state. Please check out a branch first."
  fi

  # Check if already on target.
  if [[ "$current_branch" == "$target_branch" ]]; then
    info "Already on '$target_branch'; nothing to rebase."
    return 0
  fi

  # Tree guard: clean check unless HUG_FORCE (-f warns + skips).
  # NOTE: -y does NOT weaken this guard — -y authorizes the warn-tier
  # confirmation, not the dirty-tree precondition. Only -f clears both.
  if [[ ${HUG_FORCE:-} != true ]]; then
    if has_pending_changes; then
      check_working_tree_clean
    fi
  else
    warning "Force mode: Skipping working tree clean check (uncommitted changes may be lost)."
  fi

  # --- Plan (pure) ---
  # Evaluates RB_PLAN_* vars. backup_name is best-effort; the post-create
  # tip is authoritative (see resolve_backup_name / create_backup_branch).
  eval "$(rb_build_plan "$target_branch" "$current_branch" "$no_backup")"

  # --- Render (→ stderr; honors HUG_QUIET) ---
  rb_render_plan

  # --- Dry-run stops here, before ANY side effect. ---
  if [[ ${dry_run:-false} == true ]]; then
    print_dry_run_preview "be rebased onto $target_branch"
    return 0
  fi

  # --- Confirmation (tier-aware). ---
  # D6: --quiet does NOT authorize — the confirm runs regardless of HUG_QUIET.
  # -y clears warn only (backup on); danger (--no-backup) still requires -f.
  if [[ "${RB_PLAN_TIER}" == "danger" ]]; then
    print_action_preview "rebase ${RB_PLAN_NUM_COMMITS} commit(s) onto ${target_branch} with NO BACKUP"
    prompt_confirm_danger "rebase" "no backup will be created — recovery is impossible if this goes wrong"
  else
    print_action_preview "rebase ${RB_PLAN_NUM_COMMITS} commit(s) onto ${target_branch}"
    prompt_confirm_warn
  fi

  # --- Backup AFTER authorization (D2: no orphan on cancel). ---
  if [[ "${RB_PLAN_WILL_BACKUP}" == "true" ]]; then
    backup_name=$(create_backup_branch HEAD "$current_branch") || {
      warn "Rebase aborted due to backup failure."
      return 1
    }
    tip "Backup of '$current_branch' created at: $backup_name"
  else
    warning "Skipping backup branch creation (--no-backup)."
  fi

  # --- Rebase (status-safe: stops set -e from short-circuiting). ---
  info "Starting rebase of '$current_branch' onto '$target_branch'..."
  local rebase_status=0
  git rebase "$target_branch" || rebase_status=$?

  if [[ $rebase_status -eq 0 ]]; then
    success "Rebase onto '$target_branch' successful."
    if [[ -n "$backup_name" ]]; then
      tip "Backup available at: $backup_name (can be deleted if no longer needed)."
    fi
    return 0
  else
    # Resurrected branch: previously, `set -e` killed the script here on
    # conflict and this guidance never printed. Now it does.
    warn "Rebase paused due to conflict or error."
    warn "  Resolve conflicts and run 'hug rbc' to continue."
    warn "  Or use 'hug rbc-current --all' / 'hug rbc-other --all' to auto-resolve all with one side."
    warn "  To abort, run 'hug rba'."
    if [[ -n "$backup_name" ]]; then
      tip "Backup available at: $backup_name"
    fi
    return "$rebase_status"
  fi
}
```

Then update the `hug_rb "$target_branch"` call at the bottom of the file to pass `no_backup`:

```bash
hug_rb "$target_branch" "$no_backup"
```

And replace the `show_help` OPTIONS section (lines ~23-29) with the dynamic-tier-aware version:

```bash
OPTIONS:
    --dry-run      Preview the rebase (commits, diffstat, backup disposition, auth hint) without applying
    -f, --force    Skip the working-tree-clean check AND authorize a --no-backup rebase (danger-tier)
    -y, --yes      Authorize a backed-up rebase (warn-tier) — the non-interactive opt-in
    --quiet        Suppress preview/chatter; does NOT authorize (use -y or -f for that)
    --no-backup    Skip the backup branch (routes to danger-tier; needs -f non-interactively)
    -h, --help     Show this help

DESCRIPTION:
    Rebases the current branch onto the specified target branch (e.g., 'main').
    Confirmation tier follows the backup (hug family invariant: -y clears warn, -f clears danger):
      - warn-tier  = destructive but recoverable (a backup exists). '-y' authorizes non-interactively.
      - danger-tier = no safety net. Needs '-f' non-interactively, OR type the word "rebase" interactively.
      - Default (backup ON)   ⇒ warn-tier
      - --no-backup           ⇒ danger-tier
    A backup branch is created AFTER you authorize, so cancelling leaves nothing behind.
    If conflicts occur, the rebase pauses; use 'hug rbc' to continue, 'hug rba' to abort.

EXAMPLES:
    hug rb main                    # Rebase onto main (backup, warn-tier prompt)
    hug rb main -y                 # Non-interactive rebase with backup (warn-tier authorized)
    hug rb main --dry-run          # Preview commits, backup name, and the auth flag you'll need
    hug rb main --no-backup -f     # Rebase with no backup (danger-tier, force-authorized)
```

- [ ] **Step 4: Run the tests — they should pass (green)**

Run: `make test-unit TEST_FILE=test_rb.bats TEST_SHOW_ALL_RESULTS=1`
Expected: all tests pass.

- [ ] **Step 5: Run the full unit + lib suite to confirm no regressions**

Run: `make test-bash`
Expected: all BATS tests pass (the rewritten `git-rb` doesn't break anything else; Tasks 1-4's tests remain green).

- [ ] **Step 6: Commit**

```bash
git add git-config/bin/git-rb tests/unit/test_rb.bats
git commit -m "$(cat <<'EOF'
fix(rb): honest exit codes, no orphan backups, tier-routed confirmation

WHY: hug rb had four user-visible failures (#205): it printed "Success"
but exited 1 under --no-backup (#3b — silent script-breaker); retried
rebases collided on a leftover backup branch (#2); cancelled in a
non-TTY with no documented opt-in (#1); and enforced an ad-hoc
"--no-backup requires --force" guard outside the tier system (#3a).
Two latent defects surfaced while tracing these: the conflict-guidance
branch was unreachable (set -e killed the script before it could run),
and --quiet silently AUTHORIZED the rebase.

WHAT: Rewrite hug_rb on a plan→render→(dry-run|confirm→execute) flow.
Dynamic confirmation tier (D1): backup ON ⇒ warn-tier (prompt_confirm_warn,
'-y' authorizes non-interactively — fixes #1); --no-backup ⇒ danger-tier
(prompt_confirm_danger, needs '-f' non-interactively — replaces the ad-hoc
#3a guard with principled routing). Backup moved to AFTER authorization
(D2): cancelled runs create no orphan, so retry-within-the-same-minute
stops colliding at the source (#2). Rebase is status-safe (D5):
`git rebase … || rebase_status=$?` stops set -e from short-circuiting,
resurrecting the conflict-guidance branch and making success return 0
explicitly (fixes #3b). --quiet no longer authorizes (D6): the confirm
runs regardless of HUG_QUIET; --quiet only suppresses preview/chatter.
A new entry guard (D7) refuses to start when .git/rebase-merge OR
.git/rebase-apply exists, so a paused rebase doesn't get a fresh orphan
backup. --dry-run renders the same plan the real run would execute and
returns 0 before any side effect — backup disposition + auth hint included.

HOW: hug_git_rb stays a thin orchestrator per bin/CLAUDE.md: rb_build_plan
(pure) and rb_render_plan (stderr-only, HUG_QUIET-aware) live in
hug-git-rebase and are aggregated via hug-git-kit. resolve_backup_name and
the collision-proof create_backup_branch come from hug-git-backup
(previous commits). The tier matrix is the authoritative contract:

  hug rb <t>               interactive: y/N   non-interactive: cancel
  hug rb <t> -y            proceeds+backup    proceeds+backup  ← #1 fix
  hug rb <t> -f            proceeds (skips tree-clean check)
  hug rb <t> --no-backup   type-"rebase"      cancel
  hug rb <t> --no-backup -y reject (exit 3)   reject (exit 3)
  hug rb <t> --no-backup -f proceeds, no backup                ← #3a path

IMPACT: hug rb is now script-safe: exit codes tell the truth, retries
never collide, -y is the documented non-interactive opt-in, and the
--no-backup knob behaves like every other danger-tier flag. Net-new
BATS coverage in tests/unit/test_rb.bats pins every cell of the matrix
plus the two resurrected/added code paths (conflict guidance, in-progress
guard).

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Docs polish — cheatsheet, `branching.md`, `rebase.md`, `git-to-hug.md`, `git-brestore` help, migration note

**Goal:** Make the new UX discoverable AND keep the backup-name format docs accurate. The `git-rb` `show_help` rewrite (including the warn/danger-tier gloss — DX review finding D3) is part of Task 5; this task handles every OTHER doc surface: (a) the agent cheatsheet's `--dry-run` list, (b) the widened `DD-HHMM[SS[-N]]` backup-name format across `docs/commands/branching.md`, `docs/commands/rebase.md`, `docs/git-to-hug.md`, and `git-brestore` help, and (c) a migration note for users with scripts that parse backup names.

**Why this expansion (CEO review Codex #5 + DX review Codex #4 + DX review Codex #6):** Backup branch names are a public interface. The DX review additionally flagged that updating only `branching.md` + `brestore` + cheatsheet leaves `rebase.md`, `git-to-hug.md`, and README without a copy-paste `hug rb` example or migration note — failing the 2-minute discoverability test. All in blast radius, ~20 doc lines total — P2 (boil lakes) applies.

**Files:**
- Modify: the agent cheatsheet (`hug help :agents` `:article`).
- Modify: `docs/commands/branching.md` (lines 156, 204-206, 311 + any other DD-HHMM hit).
- Modify: `docs/commands/rebase.md` (the `hug rb` section around lines 24-32: add `--dry-run`, `-y`, `--no-backup -f` examples + a "raw git equivalent" line; reference the tier gloss from Task 5).
- Modify: `docs/git-to-hug.md` (the `git rebase → hug rb` row around line 347: add a one-line note about the tier behavior change).
- Modify: `git-config/bin/git-brestore` (`show_help` + inline doc referencing the backup-name format).
- Modify or create: a migration note (release-notes style). If the project has a CHANGELOG.md, append there; otherwise add a "Backup name format change" subsection to `docs/commands/branching.md` near line 311.

**Acceptance Criteria:**
- [ ] Agent cheatsheet lists `hug rb` under `--dry-run`-supporting commands.
- [ ] `docs/commands/branching.md` documents the widened format `DD-HHMM[SS[-N]]` in: (a) `hug brestore` description (line 156), (b) `--delete-older-than` patterns (lines 204-206), (c) closing naming-convention note (line 311).
- [ ] `docs/commands/rebase.md` `hug rb` section (lines 24-32) shows at least 3 examples: basic `hug rb main`, non-interactive `hug rb main -y`, and `hug rb main --dry-run`. Bonus: a "raw git equivalent" line (`git branch backup && git rebase main` ≈ `hug rb main -y`).
- [ ] `docs/git-to-hug.md` notes the tier behavior (`-y` for backed-up rebase, `-f` for `--no-backup`) on the `git rebase → hug rb` row.
- [ ] `git-brestore -h` documents the widened format if it references the naming convention.
- [ ] A migration note exists (in CHANGELOG.md if present, else in branching.md) warning that scripts parsing `hug-backups/YYYY-MM/DD-HHMM.name` with strict regexes should widen to `[0-9]{4}([0-9]{2}(-[0-9]+)?)?` to accept the new seconds-precision names.
- [ ] `hug rb -h` reads cleanly (no stale `--no-backup requires --force`; tier gloss present from Task 5).

**Verify:**
- `hug help :agents | grep -A2 "dry-run"` shows `hug rb`.
- `grep -rn "DD-HHMM\b" docs/ git-config/bin/git-brestore` shows the widened form everywhere.
- `grep -n "hug rb main" docs/commands/rebase.md` shows ≥3 examples.
- `hug rb -h` and `hug brestore -h` exit 0.

**Steps:**

- [ ] **Step 1: Locate all doc surfaces that reference the backup-name format**

```bash
grep -rn "YYYY-MM/DD-HHMM\|DD-HHMM\.original\|DD-HHMM\.branch" \
  /home/ecc/IdeaProjects/hug-scm.WT.fix-hug-rb-ux-correctness/docs/ \
  /home/ecc/IdeaProjects/hug-scm.WT.fix-hug-rb-ux-correctness/git-config/bin/ \
  2>/dev/null
```

- [ ] **Step 2: Update `docs/commands/branching.md`**

Widen the format in: (a) `hug brestore` description (line 156), (b) `--delete-older-than` patterns (lines 204-206 — note that backup names MAY carry seconds precision but threshold patterns stay minute-precision), (c) closing naming-convention note (line 311).

- [ ] **Step 3: Update `docs/commands/rebase.md`**

In the `hug rb <branch-name>` section (lines 24-32), expand the Example block to show the new UX:

```markdown
- **Examples**:
  ```shell
  # Rebase current branch onto main (backup auto-created, warn-tier prompt)
  hug rb main

  # Non-interactive rebase (warn-tier authorized — for scripts/CI)
  hug rb main -y

  # Preview what would happen (commits, backup name, auth flag — zero side effects)
  hug rb main --dry-run

  # Rebase with NO backup (danger-tier — needs -f)
  hug rb main --no-backup -f
  ```

  Roughly equivalent to the raw-Git ritual `git branch backup-$(date +%s) && git rebase main`,
  but with collision-proof backup naming, honest exit codes, and a faithful preview.
```

Also add a one-line note under **Safety** that `-y` is the non-interactive opt-in (warn-tier) and `--no-backup` requires `-f` (danger-tier).

- [ ] **Step 4: Update `docs/git-to-hug.md`**

On the `git rebase → hug rb` row (line 347), add a note: "Creates a backup branch by default; `-y` for non-interactive (warn-tier), `--no-backup -f` for no backup (danger-tier)."

- [ ] **Step 5: Update `git-brestore` show_help**

If `git-brestore -h` references the format, apply the same widening.

- [ ] **Step 6: Add `hug rb` to the agent cheatsheet `--dry-run` list**

In the `--dry-run` bullet, add `hug rb`. Keep the existing exclusion note for `hug h *` and `hug bpush`.

- [ ] **Step 7: Write the migration note**

If the project has a `CHANGELOG.md`, append an entry under an Unreleased heading:

```markdown
### Changed (potentially breaking for script authors)
- `hug rb` backup branch names now use the form `hug-backups/YYYY-MM/DD-HHMM[SS[-N]].<base>`,
  widened from the previous `DD-HHMM.<base>`. The widening only triggers on same-minute or
  same-second collisions (a rare event). Old `DD-HHMM` names still parse correctly everywhere
  in hug. **If you have scripts that match backup names with a strict regex**, widen your
  pattern from `[0-9]{4}` (HHMM) to `[0-9]{4}([0-9]{2}(-[0-9]+)?)?` to accept the new form.
  The minute-precision threshold for `hug bdel-backup --delete-older-than` is unchanged.
- `hug rb` confirmation tiers are now dynamic: backup-on ⇒ warn-tier (auto-confirms with
  `-y`); `--no-backup` ⇒ danger-tier (needs `-f` non-interactively). The ad-hoc
  `--no-backup requires --force` hard-error is removed; `--no-backup` now routes through
  the standard danger-tier confirm (type "rebase" interactively, or pass `-f`).
```

If no CHANGELOG.md exists, add this as a "Recent changes" subsection at the top of `docs/commands/branching.md`.

- [ ] **Step 8: Verify everything reads cleanly**

```bash
hug rb -h                       # exit 0; tier gloss present; no stale guard
hug brestore -h                 # exit 0; widened format present
hug help :agents | grep -A2 "dry-run"   # shows hug rb
grep -rn "DD-HHMM\b" docs/ git-config/bin/git-brestore  # widened everywhere
grep -n "hug rb main" docs/commands/rebase.md           # ≥3 examples
```

- [ ] **Step 9: Commit**

```bash
git add docs/commands/branching.md docs/commands/rebase.md docs/git-to-hug.md \
        git-config/bin/git-brestore <cheatsheet-source-path> \
        <CHANGELOG.md or branching.md for the migration note>
git commit -m "$(cat <<'EOF'
docs(rb,backup): widen name format, add examples + migration note

WHY: Task 1 widened backup names to DD-HHMM[SS[-N]] for collision safety,
and Task 5 added dynamic confirmation tiers + a faithful --dry-run. The
original Task 6 only updated branching.md + brestore + the cheatsheet,
leaving rebase.md, git-to-hug.md, and script authors without guidance
(CEO review Codex #5 + DX review Codex #4 + #6). Backup names are a
public interface; the tier change is a UX contract change. Both need
to be documented wherever users look.

WHAT: Widen the documented format in branching.md, rebase.md (with 4
copy-paste examples + raw-git equivalent), git-to-hug.md (tier note on
the git rebase → hug rb row), brestore help, and the agent cheatsheet.
Add a migration note (CHANGELOG or branching.md) warning script authors
to widen strict regex patterns, and documenting the tier change.

HOW: Prose updates only — no behavior change. The --delete-older-than
threshold pattern itself stays minute-precision; normalize_backup_key
(Task 3) maps seconds names down for comparison.

IMPACT: A new user can copy-paste a working `hug rb main -y` from
rebase.md in under 2 minutes. Script authors parsing backup names see
the widened regex in the migration note. The tier change is documented
at every entry point a user or agent might hit. Closes the DX
discoverability gap both review voices flagged.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```


---

## Self-Review

**1. Spec coverage** — cross-checking the design doc against the tasks:

| Design decision / sub-bug | Task(s) closing it |
|---|---|
| #3b — exit code lies | Task 5 (`return 0` on success branch; status-safe rebase) |
| #2 — backup collision / orphan | Task 1 (collision ladder) + Task 5 (backup after auth) |
| #1 — non-interactive cancel | Task 5 (warn-tier honors `-y`) |
| #3a — ad-hoc `--no-backup` guard | Task 5 (dynamic tier routing) |
| Bonus — dead conflict branch | Task 5 (`git rebase … \|\| rebase_status=$?`) |
| Bonus — `--quiet` authorizes | Task 5 (confirm runs regardless of `HUG_QUIET`) |
| D1 dynamic tier | Task 5 |
| D2 backup after auth | Task 5 |
| D3 collision-proof naming | Task 1 + Task 3 |
| D4 plan→render→execute + `--dry-run` | Task 4 (helpers) + Task 5 (orchestrator) |
| D5 honest exit codes | Task 5 |
| D6 `--quiet` never authorizes | Task 4 (`rb_render_plan` honors `HUG_QUIET`) + Task 5 (confirm unconditional) |
| D7 in-progress guard | Task 4 (`rb_assert_no_rebase_in_progress`) + Task 5 (wired into flow) |
| Library changes (hug-git-backup) | Task 1 |
| Library changes (git-bdel-backup `normalize_backup_key`) | Task 3 |
| Library changes (hug-git-rebase build_plan/render) | Task 4 |
| Library changes (git-rb orchestrator + show_help) | Task 5 |
| Testing strategy — test_rb.bats | Task 5 |
| Testing strategy — lib tests for resolve_backup_name / ladder / extract | Task 2 |
| Testing strategy — bdel-backup seconds-precision | Task 3 |
| Docs — show_help rewrite | Task 5 |
| Docs — hug-git-backup header comment | Task 1 |
| Docs — agent cheatsheet `--dry-run` | Task 6 |
| Docs — ADR | Out of scope per spec (bug-fix + local refactor) |

No spec section lacks a task.

**2. Placeholder scan** — checked the plan. Task 6 Step 1 has a "locate the file" instruction but it gives the exact grep command and falls back to "use existing edit conventions" — acceptable; the path is genuinely discoverable. No TBD/TODO/"implement later"/"add error handling" patterns. All code blocks are complete.

**3. Type/signature consistency** —
- `resolve_backup_name(source_ref, base_name)` — defined in Task 1, called in Task 4's `rb_build_plan` and (indirectly via `create_backup_branch`) in Task 5. Args match.
- `create_backup_branch(source_ref, base_name)` — defined Task 1, called Task 5. Args match.
- `extract_original_name(backup)` — defined Task 1, tested Task 2. Single arg. Matches.
- `normalize_backup_key(backup)` — defined Task 3, tested Task 3. Matches.
- `rb_assert_no_rebase_in_progress()` — defined Task 4, called Task 5. No args. Matches.
- `rb_build_plan(target, current, no_backup)` — defined Task 4, called Task 5 via `eval "$(rb_build_plan …)"`. Args order matches. Vars produced (`RB_PLAN_*`) match what `rb_render_plan` reads and what Task 5's orchestrator branches on.
- `rb_render_plan()` — defined Task 4, called Task 5. No args. Matches.
- `hug_rb(target_branch, no_backup)` — Task 5 changes the signature from 1→2 args; the call site `hug_rb "$target_branch" "$no_backup"` is updated in the same task. Matches.

No drift.

---

## /autoplan CEO Review Report

**Mode:** SELECTIVE EXPANSION (auto-decided; bug-fix/refactor hybrid)
**Approach:** B (plan→render→execute refactor; auto-decided over A=point fixes, C=generic framework)
**Voices:** Codex CEO (10 findings) + Claude CEO subagent (5 findings). Both ran.

### Decision Audit Trail

| # | Phase | Decision | Classification | Principle | Rationale | Rejected |
|---|---|---|---|---|---|---|
| 1 | CEO 0C-bis | Approach B (refactor) over A (point fixes) | Mechanical | P1+P3+P5 | Shared root causes; A leaves latent defects | A (too narrow), C (YAGNI) |
| 2 | CEO 0D | Include doc updates in Task 6 (expand scope) | Mechanical | P2 (boil lakes) | `docs/commands/branching.md` + `git-brestore` help in blast radius; <5 lines | Defer (Codex #5 flagged the gap) |
| 3 | CEO 0D | Defer "split -f into auth + precondition override" | Taste → TODOS | P3 | Family-wide change; out of scope per design doc | Include (too broad for #205) |
| 4 | CEO 0D | Defer "generic --with-backup flag across destructive cmds" | Taste → TODOS | P3 | Long-term direction; no reported bug | Include (YAGNI today) |
| 5 | CEO 0D | Defer "migrate git-tc/git-w-wip to hug_clock_now" | Taste → TODOS | P3 | Known latent flake; out of blast radius | Include |
| 6 | CEO Sec 1 | Keep plan-object pattern (eval rb_build_plan) | Taste (survived) | P5+P3 | Matches parse_common_flags; centralization kills the duplicated-preview bug class | Flatten (Claude subagent + Codex #8) |
| 7 | CEO Sec 3 | No security change | Mechanical | — | No new attack surface | — |
| 8 | CEO Sec 6 | Test coverage comprehensive | Mechanical | P1 | Every tier-matrix cell + every new codepath covered | — |

### NOT in scope (deferred)

- **Split `-f` into "authorize" + "precondition override" flags** (Codex #3) — family-wide change; belongs in a cross-command safety-contract review, not a single bug fix. → TODOS.md
- **Generic `--with-backup` flag across all destructive hug commands** (Claude subagent) — long-term platform direction; adopt after this plan ships and stabilizes. → TODOS.md
- **Migrate `git-tc` / `git-w-wip` to `hug_clock_now`** — out of blast radius; addresses a known latent test flake flagged in `hug-clock`'s header comment. → TODOS.md
- **Apply plan→render→execute pattern to `hug h back/undo/rewind/rollback`** — no active bug; speculative. → TODOS.md

### What already exists (leverage map)

| Sub-problem | Existing code reused |
|---|---|
| Collision-proof branch naming | `git-bc:135-173` (hug_clock_now ladder) — mirrored in Task 1 |
| Testable clock | `hug-clock` lib (HUG_FAKE_CLOCK), sourced via `hug-common:84` |
| Confirmation tiers | `hug-confirm` (safe/warn/danger), `-y`-refuses-danger invariant |
| Preview helpers | `hug-output` (`print_dry_run_preview`, `print_action_preview`) |
| Commit-range analysis | `hug-git-commit` (`count_commits_in_range`, `print_commit_list_in_range`) |
| `eval`-based flag expansion | `hug-cli-flags:parse_common_flags` — same pattern Task 4 uses |

### Dream state delta

```
CURRENT                          THIS PLAN →                      12-MONTH IDEAL
─────────                        ───────────                       ──────────────
hug rb has 4 bugs +              All 6 issues closed;              Every destructive hug command:
2 latent defects.                plan→render→execute pattern;       - shared plan/render helpers
Untestable backup naming.        collision-proof + testable        - HUG_FAKE_CLOCK-deterministic
Zero test coverage for rb.       naming; faithful --dry-run;       - --dry-run on every destructive cmd
Dead conflict-guidance branch.   resurrected conflict guidance;    - unified backup lib across cmds
--quiet authorizes.              D7 in-progress guard;             - tier matrix documented per cmd
                                 first-ever test_rb.bats           - generic --with-backup flag
```

This plan moves toward the ideal but does NOT overreach into other commands.

### Error & Rescue Registry (CEO Section 2)

| Codepath | Failure | Rescue | User sees |
|---|---|---|---|
| `git rebase "$target"` | non-zero (conflict) | `rebase_status=$?`, guidance printed, `return $rebase_status` | conflict message + `hug rbc`/`hug rba` hints |
| `create_backup_branch` | `git branch` fails | retry loop (100x), re-resolve name | `error` after 100 attempts |
| `resolve_backup_name` | 100 attempts exhausted | `error`, `return 1` | clear internal error |
| `rb_assert_no_rebase_in_progress` | dir exists | `error`, `return 1` | "rebase already in progress" + rbc/rba |
| `prompt_confirm_danger` + `-y` | dangerous op + insufficient auth | `error`, exit `$HUG_EX_BLOCKED` (3) | "requires --force (not -y)" |

### Failure Modes Registry

| Failure mode | Severity | Mitigated? | Where |
|---|---|---|---|
| Lying exit code (#3b) | Critical | YES | Task 5 (`return 0` explicit) |
| Orphan backup on cancel (#2) | High | YES | Task 5 (backup after auth, D2) |
| Same-minute collision (#2) | High | YES | Task 1 (collision ladder) |
| Non-interactive cancel with no opt-in (#1) | Med | YES | Task 5 (warn-tier honors -y) |
| Ad-hoc --no-backup guard (#3a) | Med | YES | Task 5 (dynamic tier routing) |
| Dead conflict guidance | High | YES | Task 5 (status-safe rebase) |
| --quiet authorizes | Med | YES | Task 5 (confirm unconditional) |
| In-progress rebase orphan | Med | YES | Task 4+5 (D7 guard) |
| Backup-name doc drift | Med | YES (expanded Task 6) | Task 6 (now updates branching.md + brestore) |
| Tier-matrix user confusion | Low | PARTIAL (show_help carries matrix) | Task 5 help text |

### Premises (user gate — Phase 1 STOP)

The plan's load-bearing premises:
1. `hug rb` has 4 real sub-bugs + 2 latent defects worth fixing together (validated against issue #205).
2. The right framing is "trustworthy and script-safe" — UX + correctness, not just exit-code.
3. A single unifying refactor (plan→render→execute) beats 4 point fixes (shared root causes).
4. Doing nothing is unacceptable (real automation pain).

Codex contested P3 (scope size) and the warn-tier semantics. Neither contest is a User Challenge (the user's direction stands; the critiques are scope/taste). Premises confirmed.

### CEO Completion Summary

| Section | Findings | Auto-decided | Taste (→gate) |
|---|---|---|---|
| 0C-bis Alternatives | 3 approaches | B chosen | — |
| 0D Scope | 6 candidates | 1 accepted, 3 deferred, 2 no-op | — |
| 1 Architecture | 2 | 2 kept-as-is | TD1 (plan-object pattern) |
| 2 Error/Rescue | 0 gaps | — | — |
| 3 Security | 0 | — | — |
| 4 Data flow/edges | 2 (both no-op after verification) | — | — |
| 5 Code quality | 2 (both no-op) | — | — |
| 6 Tests | 0 (comprehensive) | — | — |
| 7 Performance | 0 | — | — |
| 8 Observability | 0 | — | — |
| 9 Deployment | 0 (5/5 reversibility) | — | — |
| 10 Trajectory | 0 | — | — |
| 11 Design/UX | skipped (no UI scope) | — | — |
| **Total** | **13 findings** | **8 auto-decided** | **3 taste decisions** |

### Taste decisions surfaced at final gate

- **TD1 (CEO Sec 1, Codex #8 + Claude):** Plan-object pattern (`eval rb_build_plan`) vs. flat orchestrator. Recommend keep (matches existing pattern; kills duplicated-preview bug class).
- **TD2 (Codex #4 + #10):** Single PR (Tasks 1-6 together) vs. split Task 5 into 5a (minimal #3b fix) + 5b (full rewrite). Recommend single PR (shared root causes; strong tests; small CLI).
- **TD3 (Codex #2 + #6):** warn-tier-on-backup semantics + tier-matrix complexity. Recommend keep (tier system is the documented contract; help text carries the matrix).

> **Phase 2 (Design Review) skipped** — no UI scope detected in Phase 0 (regex matches for "form" were all "name format", verified by inspecting each hit).

---

## /autoplan Eng Review Report

**Voices:** Codex eng (7 findings) + Claude eng subagent (7 findings). Both ran.

### ENG DUAL VOICES — CONSENSUS TABLE

```
═══════════════════════════════════════════════════════════════════════════
  Dimension                                Claude  Codex  Consensus
  ──────────────────────────────────────   ─────── ─────── ───────────────────
  1. Architecture sound?                    YES*    YES*   CONFIRMED
     (* both flagged eval — both rejected after verification)
  2. Test coverage sufficient?              PARTIAL NO     DISAGREE → 6 real bugs found + fixed
  3. Performance risks addressed?           YES     YES    CONFIRMED (subagent misread collision ladder)
  4. Security threats covered?              N/A*    N/A*   CONFIRMED (* both flagged eval; both wrong)
  5. Error paths handled?                   PARTIAL PARTIAL CONFIRMED → collision-vs-failure gap (fixed)
  6. Deployment risk manageable?            YES     YES    CONFIRMED (5/5 reversibility)
═══════════════════════════════════════════════════════════════════════════
```

### Eng findings — resolved

| # | Finding | Severity | Source | Resolution |
|---|---|---|---|---|
| E1 | Worktree guard uses `.git/rebase-merge` (a FILE in worktrees, not a dir) → D7 guard silently fails in linked worktrees, the EXACT environment this development runs in | **CRITICAL** | Codex | **FIXED** — Task 4 now uses `git rev-parse --git-path rebase-{merge,apply}` |
| E2 | Task 3 regex makes seconds group REQUIRED → breaks legacy `DD-HHMM` normalization → `--delete-older-than` under-deletes | **CRITICAL** | Codex | **FIXED** — Task 3 regex now has trailing `?`: `([0-9]{2}(-[0-9]+)?)?` |
| E3 | Task 3 test expectation contradicts impl (`is_older_than_pattern` uses `<=`, test asserts NOT older) | HIGH | Codex | **FIXED** — test expectation corrected to match `<=` semantics |
| E4 | Task 3 test sources `git-bdel-backup` script unsafely (would `exit` the BATS shell) | HIGH | Codex | **FIXED** — switched to `sed`-extract as PRIMARY path |
| E5 | Task 4 test `bash -c "source <(rb_build_plan…); rb_render_plan"` doesn't have functions | HIGH | Codex | **FIXED** — every subshell now sources `hug-common` + `hug-git-kit` first |
| E6 | `create_backup_branch` retries 100x on ANY `git branch` failure (not just collision) | MED | Codex | **FIXED** — now retries only when candidate ref exists (collision); other errors surface immediately |
| E7 | `eval "$(rb_build_plan …)"` claimed unsafe | "CRITICAL" (Claude subagent) + MED (Codex) | both | **REJECTED** — empirically verified `printf %q` escapes `$()`, newlines, unicode correctly; git also rejects malicious branch names at creation |
| E8 | Architecture coupling (`hug-git-rebase` → `hug-git-backup`) | "CRITICAL" (Claude subagent) | subagent | **REJECTED** — one-way dependency, intentional, both aggregated by `hug-git-kit` |
| E9 | Collision ladder 101 git calls worst-case | MED (Claude subagent) | subagent | **REJECTED** — misread the code; while-loop only runs ON collision, breaks on first free name |
| E10 | Concurrent-rebase test missing | HIGH (Claude subagent) | subagent | DEFER — BATS runs sequentially; sequential "two runs same clock" test covers the code path; concurrent test is brittle in CI. → issues |
| E11 | `count_commits_in_range=0` edge case | HIGH (Claude subagent) | subagent | DEFER — `git rebase` handles it ("up to date"), status capture propagates correctly. → issues |

### Architecture ASCII diagram (Eng Section 1)

```
BEFORE                                   AFTER (this plan)
─────────                                ────────────────
git-rb (fat orchestrator)                git-rb (THIN orchestrator)
├─ validate                              ├─ validate
├─ create backup (PRE-auth) ←#2          ├─ rb_assert_no_rebase_in_progress (NEW, D7)
├─ confirm (always danger) ←#3a          │   └─ git rev-parse --git-path (worktree-aware)
├─ git rebase (set -e kills) ←bonus      ├─ eval rb_build_plan (NEW)
├─ [[ -n backup ]] && tip ←#3b           │   └─ calls resolve_backup_name (NEW, pure)
└─ exit 1 on success ←#3b                ├─ rb_render_plan (NEW, →stderr, HUG_QUIET-aware)
                                         ├─ dry-run? → return 0
hug-git-backup (raw date, no loop)       ├─ confirm(tier) ←warn/danger routing (D1)
└─ extract_original_name (HHMM only)     ├─ create_backup_branch (POST-auth, D2)
                                         │   └─ collision ladder + failure-aware retry (NEW)
git-bdel-backup                          ├─ git rebase || rebase_status=$? (status-safe)
└─ normalize_backup_key (HHMM only)      ├─ return 0 | $rebase_status (resurrected branch)
                                         └─ (no more `&& tip` tail)

                                         hug-git-backup (rewritten)
                                         ├─ resolve_backup_name (NEW, pure)
                                         ├─ create_backup_branch (hug_clock_now + retry)
                                         └─ extract_original_name (widened)

                                         hug-git-rebase (helpers appended)
                                         ├─ rb_assert_no_rebase_in_progress (NEW)
                                         ├─ rb_build_plan (NEW)
                                         └─ rb_render_plan (NEW)

                                         git-bdel-backup
                                         └─ normalize_backup_key (widened, seconds OPTIONAL)
```

### Test diagram (Eng Section 3)

```
NEW UX FLOWS:                             COVERED BY:
  hug rb <t> --dry-run                    ✓ "rb: --dry-run changes nothing" + "...shows backup + auth hint"
  hug rb <t> -y (non-TTY)                 ✓ "rb: -y proceeds in non-TTY"
  hug rb <t> --no-backup -f               ✓ "rb: --no-backup -f proceeds with no backup"
  hug rb <t> --no-backup -y (exit 3)      ✓ "rb: --no-backup -y rejects with exit 3"

NEW DATA FLOWS:                           COVERED BY:
  plan → render → execute                 ✓ (covered transitively by every rb test)
  resolve_backup_name → create_backup     ✓ test_hug_git_backup.bats (Task 2)

NEW CODEPATHS:                            COVERED BY:
  collision ladder (3 rungs)              ✓ "resolve_backup_name: widens to seconds" + "...appends -N"
  create_backup retry-on-failure          ✓ "create_backup_branch: two calls same clock distinct"
  rb_assert_no_rebase_in_progress         ✓ 4 tests in test_hug_git_rebase.bats (both backends + rbc/rba)
  rb_build_plan tier routing              ✓ "warn-tier when backup on" + "danger-tier when --no-backup"
  rb_render_plan HUG_QUIET handling       ✓ "rb_render_plan: silent when HUG_QUIET=T"
  resurrected conflict guidance           ✓ "rb: on conflict, exit non-zero AND conflict guidance printed"
  worktree-aware guard                    ✓ (uses git rev-parse --git-path; verified in this worktree)

GAPS (deferred to GitHub issues):         REASON:
  Concurrent rebase processes             BATS sequential; brittle in CI; sequential test covers path
  count_commits_in_range=0 edge case      git rebase handles; status capture propagates
```

### Eng Completion Summary

| Section | Findings | Fixed in plan | Rejected (verified) | Deferred |
|---|---|---|---|---|
| 1 Architecture | 2 (coupling + eval) | 0 | 2 | 0 |
| 2 Code Quality | 2 (minor) | 0 | 2 | 0 |
| 3 Tests | 4 (2 real + 2 deferred) | 4 (E3, E4, E5 + Task 6 doc expansion) | 0 | 2 (E10, E11) |
| 4 Performance | 1 (collision ladder) | 0 | 1 | 0 |
| Security (eval) | 2 (both wrong) | 0 | 2 | 0 |
| Error paths | 2 (worktree guard + failure-vs-collision) | 2 (E1, E6) | 0 | 0 |
| **Total** | **13** | **6 fixed** | **7 rejected** | **2 deferred** |

### NOT in scope (Eng)

- Concurrent `hug rb` test (Claude subagent E10) — BATS runs sequentially; brittle in CI. → issues
- `count_commits_in_range=0` early-return (Claude subagent E11) — `git rebase` handles correctly; status capture propagates. → issues

### What already exists (Eng)

(See CEO report — same leverage map applies.)

### Failure Modes Registry (Eng-augmented)

| Failure mode | Severity | Mitigated? | Where |
|---|---|---|---|
| Worktree D7 guard silently fails | CRITICAL | YES (FIXED) | Task 4 — `git rev-parse --git-path` |
| Legacy `DD-HHMM` names break under new regex | CRITICAL | YES (FIXED) | Task 3 — seconds group optional |
| `--no-backup -y` rejects (exit 3) | HIGH | YES | Task 5 |
| All other CEO-listed failures | HIGH/MED | YES | (see CEO registry) |

---

## /autoplan DX Review Report

**Product type:** CLI Tool. **Persona (auto-decided P6):** Automation-fluent OSS maintainer (matches the #205 reporter).
**Voices:** Codex DX (5 findings) + Claude DX subagent (6 findings). Both ran.

### DX DUAL VOICES — CONSENSUS TABLE

```
═══════════════════════════════════════════════════════════════════════════
  Dimension                                Claude  Codex  Consensus
  ──────────────────────────────────────   ─────── ─────── ───────────────────
  1. TTHW < 5 min?                          NO      NO     CONFIRMED (no copy-paste path)
  2. CLI naming guessable?                  NO(*)   YES    DISAGREE (Claude misread; Codex right)
  3. Error messages actionable?             PARTIAL YES    CONFIRMED (improved; minor gaps)
  4. Docs findable & complete?              NO      NO     CONFIRMED (Task 6 scope expanded)
  5. Upgrade path safe?                     N/A     YES    CONFIRMED (legacy preserved)
  6. Dev environment friction-free?         YES     YES    CONFIRMED
═══════════════════════════════════════════════════════════════════════════
(*) Claude subagent claimed tier matrix breaks family contract — REJECTED after
    verification against hug-confirm:line33. Plan IS consistent with the family.
```

### DX findings — resolved

| # | Finding | Severity | Source | Resolution |
|---|---|---|---|---|
| D1 | No copy-paste "hello world" path for `hug rb` | HIGH | both | **FIXED** — Task 6 Step 3 adds 4 examples + raw-git equivalent to `docs/commands/rebase.md` |
| D2 | Tier matrix breaks family contract | "CRITICAL" (Claude) | Claude | **REJECTED** — verified `hug-confirm:33` says `-y` clears warn, `-f` clears danger; plan follows this exactly |
| D3 | "warn-tier"/"danger-tier" undefined in help | HIGH (Claude) | Claude | **FIXED** — Task 5 show_help now has a 2-line tier gloss |
| D4 | Task 6 docs scope narrow (rebase.md/git-to-hug.md/README missing) | HIGH (Codex) | Codex | **FIXED** — Task 6 expanded to cover rebase.md + git-to-hug.md |
| D5 | "internal" prefix on user-reachable backup errors | MED (Codex) | Codex | NOTED — the 100-attempt exhaustion could theoretically be user-reachable (100 backups in one second). Current prefix is consistent with existing hug-internal-error convention. No change (P3). |
| D6 | Release/migration note for backup-name widening | MED (Codex) | Codex | **FIXED** — Task 6 Step 7 adds a CHANGELOG/migration note with the widened regex |
| D7 | `--no-backup` is a footgun | "CRITICAL" (Claude) | Claude | **REJECTED** — danger-tier IS the escape-hatch pattern; adding `--really-no-backup` is over-engineering (P5) |
| D8 | Add "raw git equivalent" example | LOW (Codex) | Codex | **FIXED** — included in Task 6 Step 3 |

### DX Scorecard

| Dimension | Score (0-10) | Notes |
|---|---|---|
| 1. Time to Hello World | 7 → 9 (after Task 6) | Examples + raw-git equivalent make it copy-paste-fast |
| 2. Error messages | 8 → 9 | Honest exit codes + conflict guidance + in-progress guard; minor "internal" prefix remains |
| 3. CLI ergonomics | 8 | Consistent with family; tier matrix requires reading help once |
| 4. Documentation | 6 → 9 (after Task 6) | All surfaces covered; migration note + examples |
| 5. Upgrade path | 7 → 9 (after Task 6) | Legacy parsing preserved; migration note for script authors |
| 6. Dev environment | 9 | Unchanged (hug install + activate is already clean) |
| 7. API/CLI consistency | 8 | Tier routing matches hug-confirm invariant |
| 8. Escape hatches | 8 | `--no-backup -f` is the documented escape; `-y` is the documented opt-in |
| **Overall** | **7.6 → 8.8** | Strong correctness plan, DX now matches |

### TTHW assessment

- **Current:** ~5-8 minutes (user must read `hug rb -h`, find the tier matrix, look up backup naming in branching.md).
- **After Task 6:** ~2-3 minutes (copy-paste `hug rb main` from rebase.md, see the 4 examples, raw-git equivalent grounds it).
- **Target:** < 5 minutes. ✓ after Task 6.

### DX Implementation Checklist (what Task 5 + Task 6 land)

- [x] Tier gloss in `git-rb` show_help (Task 5, D3 fix)
- [x] 4 copy-paste examples + raw-git equivalent in rebase.md (Task 6 Step 3, D1+D8 fix)
- [x] Tier note in git-to-hug.md (Task 6 Step 4, D4 fix)
- [x] Migration note for script authors (Task 6 Step 7, D6 fix)
- [x] Widened format documented everywhere backup names appear (Task 6 Steps 2+5)






