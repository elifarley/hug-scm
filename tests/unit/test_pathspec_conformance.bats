#!/usr/bin/env bats
# =============================================================================
# Pathspec Contract Conformance Suite (issue #292, spec §4)
# =============================================================================
# WHY: pathspec handling was audited per-command with no enforcement, so
# regressions (a flag loop swallowing an unknown flag as a path, a trailing
# `--` launching a picker from a listing, pathspecs silently dropped) could
# land green. This suite is THE enforcement artifact: a table-driven contract
# check — one row per path-accepting command, one test per contract column.
#
# HOW: every expectation below was PROBED against the real fixture repo
# before being written (never assumed). The fixture is a known file set so
# each two-sided expectation (matching present AND non-matching absent) is
# derivable:
#   - commits: "base" (touches src/a.py, src/BIG.py, docs/note.md, other.txt)
#              "docs guide only" (touches docs/guide.md ONLY — gives the log
#              commands a discriminating commit: `-- src/` must omit it)
#   - working tree: staged mod on src/a.py, unstaged mod on docs/note.md,
#     untracked new.txt
#
# Row staging (spec §4): this file carries CONTRACT rows for the 10 commands
# that already conform. Task 4 adds characterization rows for un-migrated
# commands (`us`, sl* family, w-get, ...). Adding a command = one line in a
# row list below.
#
# Adding a command later must be a one-line row addition — hence the row
# lists. LESSON (review round 1): the class lists are the SINGLE source of
# membership truth; column tests must iterate them, never re-enumerate
# inline, or the arrays go dead and "one-line row addition" silently turns
# false.
# =============================================================================

load ../test_helper

# Contract rows — these commands conform TODAY and must stay green through the
# whole #292 effort.
PATHSPEC_CONFORMANCE_ROWS=(sw ss su shc shcp shp l ll cmod cmoda)

# Row classes — each command of PATHSPEC_CONFORMANCE_ROWS appears in exactly
# one class; every class array below is consumed by at least one column test:
#   PICKER_ROWS    — action commands whose trailing bare `--` opens the
#                    interactive file picker (spec §2 rule 3, action arm).
#                    They also share the diff-command profile for the filter
#                    columns (ss sees the staged set; su/sw the unstaged set).
#   LOG_ROWS       — log commands: filter columns discriminate via the
#                    docs-only commit; no committish argument.
#   SHOW_ROWS      — show commands: filter columns run against HEAD~1.
#   INERT_ROWS     — LOG_ROWS + SHOW_ROWS: trailing bare `--` is
#                    pass-through/inert for all of them.
#   HISTORY_ROWS   — cmod/cmoda AMEND history: no dry-run exists, so their
#                    filter columns are scoped to help-only (see column tests)
# `a` (Task 9) is the roster's MUTATOR: the filter columns observe it via the
# stage-count summary + porcelain state (each cell's probe state adds an
# unstaged src file so the scope is two-sided), while the capture columns
# (stub gum) are read-only by construction — the cancelling stub stages
# nothing. `a`'s SELECTION semantics get a dedicated standalone test below
# (selecting stub), not a shared-column cell.
PATHSPEC_PICKER_ROWS=(sw ss su a)
# FULL enrollment rosters (membership truth): `llu` and `sh` are enrolled
# here from PR-C Task 2 on — the master membership-diff row (PR-C section,
# bottom of file) counts enrollment via THESE arrays.
PATHSPEC_LOG_ROWS=(l ll llu)
PATHSPEC_SHOW_ROWS=(shc shcp shp sh)
# TWO-PHASE ENROLLMENT (PR-C Tasks 10-11): llu graduated in Task 10 and sh
# in Task 11 — both PENDING subtractions are gone, so the LOG and SHOW
# column loops below now cover every roster member. The PENDING mechanism
# itself stays (it cost zero edits per graduation: the migration task just
# empties its list and the subtractive derivation picks it up).
PATHSPEC_LOG_PENDING_ROWS=() # (landed, Task 10: llu migrated, #292 PR-C)
PATHSPEC_SHOW_PENDING_ROWS=() # (landed, Task 11: sh migrated, #292 PR-C)
PATHSPEC_LOG_ACTIVE_ROWS=()
for _row in "${PATHSPEC_LOG_ROWS[@]}"; do
  if [[ " ${PATHSPEC_LOG_PENDING_ROWS[*]} " != *" $_row "* ]]; then
    PATHSPEC_LOG_ACTIVE_ROWS+=("$_row")
  fi
done
PATHSPEC_SHOW_ACTIVE_ROWS=()
for _row in "${PATHSPEC_SHOW_ROWS[@]}"; do
  if [[ " ${PATHSPEC_SHOW_PENDING_ROWS[*]} " != *" $_row "* ]]; then
    PATHSPEC_SHOW_ACTIVE_ROWS+=("$_row")
  fi
done
unset _row
# Inert rows ride the ACTIVE derivatives: a pending member in the inert loop
# would hit psx_inert_args' unknown-row sentinel before its migration.
PATHSPEC_INERT_ROWS=("${PATHSPEC_LOG_ACTIVE_ROWS[@]}" "${PATHSPEC_SHOW_ACTIVE_ROWS[@]}")
PATHSPEC_HISTORY_ROWS=(cmod cmoda)

# Characterization rows (Task 4) — assertions of TODAY's behavior for the
# commands later PRs migrate (#292 PR-A Tasks 7-10, PR-B, PR-C). Every row
# was PROBED in the fixture before writing (see each test). These commands
# do NOT conform to the contract yet: when a migration flips one, the
# corresponding test here goes red ON PURPOSE — update it in the same PR,
# never before. Do NOT move a command into the contract arrays above until
# its migration lands.
#
# NOTE: unlike the contract classes (exactly-one-class membership above),
# char rows are COLUMN-SCOPED and MAY span arrays — e.g. sls appears in
# FILTER/ SWALLOW/ HELP-rows because different columns probe different
# defects. The overlap is intentional; do not "fix" it.
#
#   CHAR_SL_FILTER_ROWS   — sl family where `-- src/` coincidentally filters
#                           (phantom `--` pathspec OR-ed away by git)
#   CHAR_SL_HELP_ROWS     — whole sl family: `--help` never reaches the
#                           script (git man routing)
#   CHAR_FATAL_ROWS       — single-file commands: two files → git FATAL
#                           (RETIRED by Task 10 → PATHSPEC_SINGLEFILE_ROWS)
# RETIRED by Task 5 (sls/slu/slk/sli migration): CHAR_SL_EMPTY_ROWS and
# CHAR_SL_SWALLOW_ROWS pinned the phantom-'--' info message and the silent
# unknown-flag swallow; both defects are gone, so the rows moved to the
# sls-family conformance section below (never re-add a pin for a fixed
# defect — the conformance rows ARE the pin).
PATHSPEC_CHAR_SL_FILTER_ROWS=(sl sla)
PATHSPEC_CHAR_SL_HELP_ROWS=(sl sla sls slu slk sli)

# Single-file cardinality rows (migrated by Task 10, spec §3.2/§5.6): these
# commands take exactly ONE file; two files → hug's own rejection (exit 2,
# "<cmd> accepts only one file (got N files).") instead of git fatals or silent ignores.
# (Exit flipped 1→2 by the code-roast round: reject_multiple_files now uses
# error_usage — the family's usage-error code.)
#   SINGLEFILE_ROWS       — one-word commands guarded directly via
#                          reject_multiple_files (loop-able as `hug $cmd`)
#   SINGLEFILE_DELEGATE_ROWS — commands delegating to llf; the delegation
#                              inserts a flag before the extras, so post-flag
#                              extras fall through to git (see dedicated test)
# Multi-word commands (h steps, stats file) get dedicated tests below —
# they don't fit the one-word loop.
PATHSPEC_SINGLEFILE_ROWS=(fa fb fblame fborn fcon llf)
PATHSPEC_SINGLEFILE_DELEGATE_ROWS=(llfp llfs)

# TARGET+PATH class (#311): two-positional interface — a <N|commit> target
# plus EXACTLY ONE path from either side of the separator; trailing bare
# '--' opens the picker. Dedicated rows live in the fcat contract section.
PATHSPEC_TARGETPLUSFILE_ROWS=(fcat)

# PR-C rosters (spec §5): ONE roster per behavioral class; a PR-C command
# missing from every column below fails the membership-diff row (PR-C
# section, bottom of file). Names are ROSTER IDENTIFIERS (script suffixes),
# not invocation strings — e.g. w-discard runs as `hug w discard` via the
# w gateway.
PATHSPEC_W_DESTRUCTIVE_ROWS=(w-discard w-purge w-zap w-wipe)
PATHSPEC_W_ALL_ROWS=(w-discard-all w-purge-all w-zap-all w-wipe-all)
PATHSPEC_WIP_ROWS=(w-wip w-unwip w-wipdel)
# The MASTER is a HAND-WRITTEN LITERAL of all 15 PR-C commands — NEVER
# derived from the class arrays above. LESSON (review round 1): a derived
# master makes the membership diff TAUTOLOGICAL — the test's `enrolled` union
# consumes the same class arrays, so deleting a command from its roster
# removes it from BOTH sides and the row stays green (verified red-check:
# deleting w-zap from its roster failed the row by name only AFTER this
# fix). The expected set must be independent of the arrays it checks.
PATHSPEC_PRC_MASTER=(
  w-discard w-purge w-zap w-wipe
  w-discard-all w-purge-all w-zap-all w-wipe-all
  w-wip w-unwip w-wipdel
  w-get sh llu fcat
)
# `sh` and `llu` are enrolled via the SHOW/LOG rosters above (two-phase:
# llu ACTIVE since Task 10, sh ACTIVE since Task 11). `fcat` is enrolled
# via PATHSPEC_TARGETPLUSFILE_ROWS (#311 Task 4 — contract rows already
# ACTIVE from Task 1).

# -----------------------------------------------------------------------------
# Fixture + harness helpers
# -----------------------------------------------------------------------------

# Creates the known-state repo (see header) and echoes its path.
# LESSON: commit ordering matters — the docs-only commit must land BEFORE the
# staged mod on src/a.py is created, or `git add docs/guide.md && git commit`
# sweeps the already-staged src/a.py into the "docs only" commit and every
# log-filter expectation silently breaks (found by probing; raw `git log --
# src/` is the oracle).
setup_pathspec_fixture() {
  local repo log
  repo=$(create_test_repo) || return 1
  log=$(mktemp -t psx-fixture-XXXXXX.log)

  # stdout stays clean (the caller captures `$(...)` for the repo path);
  # setup stderr goes to a log file, not /dev/null — a swallowed fixture
  # failure otherwise surfaces as three confusing assertion failures
  # downstream instead of the real "git commit rejected ..." cause.
  if ! (
    cd "$repo" || exit 1
    mkdir -p src docs

    # Base commit: the full known file set. src/BIG.py is the case-variant
    # partner of src/a.py for the `:(icase)` column.
    echo py1 > src/a.py
    echo big1 > src/BIG.py
    echo note1 > docs/note.md
    echo other > other.txt
    git add -A
    git commit -q -m "base"

    # Discriminating commit: touches docs/ ONLY.
    echo guide > docs/guide.md
    git add docs/guide.md
    git commit -q -m "docs guide only"

    # Working-tree state: staged / unstaged / untracked.
    echo py2 >> src/a.py
    git add src/a.py
    echo note2 >> docs/note.md
    echo new > new.txt

    # Upstream anchor for llu (Task 10): a parentless empty-tree commit on a
    # local branch set as @{u}, UNRELATED to HEAD's history, so @{u}..HEAD =
    # exactly the fixture's two commits (base + "docs guide only") — llu's
    # outgoing set, and the log-filter rows stay two-sided through it (the
    # docs-only commit must vanish under `-- src/`). Same set-upstream-to-
    # <local-branch> technique as the w-get rows below (probed: @{u} resolves
    # local branches; an unrelated anchor counts EVERYTHING reachable from
    # HEAD as outgoing).
    anchor=$(git commit-tree "$(git hash-object -w -t tree /dev/null)" -m "upstream anchor")
    git branch llu-anchor "$anchor"
    git branch --set-upstream-to=llu-anchor >/dev/null
  ) >/dev/null 2>"$log"; then
    echo "psx fixture setup FAILED (repo: $repo) — stderr log: $log" >&2
    cat "$log" >&2
    rm -f "$log"
    return 1
  fi
  rm -f "$log"

  echo "$repo"
}

# Shared setup for every column test: fresh fixture, cd into it.
psx_setup() {
  require_hug
  TEST_REPO=$(setup_pathspec_fixture)
  cd "$TEST_REPO" || return 1
}

# Fixture extension for the separator-aware lib probe: a tracked file
# LITERALLY named '--cwd' carrying a STAGED modification, so the token is
# visible to sl AND sls. `git add -- ./--cwd` (separator form) is mandatory —
# a bare `git add ./--cwd` would parse the filename as a flag. Used by the
# Task 5 conformance rows at three sinks (sls listing, sl listing, count).
psx_setup_optnamed_cwd_file() {
  psx_setup
  echo cwdone > ./--cwd
  git add -- ./--cwd
  git commit -q -m "file literally named --cwd"
  echo cwdtwo >> ./--cwd
  git add -- ./--cwd # staged mod: visible to sl AND sls
}

# Conflict fixture for the slc rows (Task 7): two conflicted files in
# DIFFERENT dirs (src/c.txt, docs/c.txt) so every scope assertion is
# two-sided — 'src/' keeps one and must drop the other. Built from a CLEAN
# repo, NOT psx_setup: the standard fixture's staged mod would BLOCK the
# merge (git >= 2.34 refuses to merge with a dirty index — see
# create_slc_conflict_fixture's GOTCHA note in test_status_staging.bats).
# hug mkeep exits nonzero BECAUSE of the conflicts — that failure is the
# fixture's point, so it is tolerated, not asserted here.
psx_setup_conflict() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO" || return 1
  (
    mkdir -p src docs
    echo base > src/c.txt
    echo base > docs/c.txt
    git add -A
    git commit -q -m "conflict base"
    git switch -q -c side
    echo side > src/c.txt
    echo side > docs/c.txt
    git add -A
    git commit -q -m "side edits"
    git switch -q main
    echo main > src/c.txt
    echo main > docs/c.txt
    git add -A
    git commit -q -m "main edits"
  )
  hug mkeep side -m "merge side" >/dev/null 2>&1 || :
}

# Mid-test reset: leave the repo (cleanup needs a valid cwd), drop it, clear
# the handle — the three-line incantation every loop iteration needs before
# psx_setup can build the next fresh fixture. Extracted so a fix to the reset
# sequence (e.g. a new cleanup guard) lands once, not fifteen times.
psx_reset() {
  cd "${BATS_TEST_TMPDIR:-/tmp}" || cd "$HOME" || true
  cleanup_test_repo
  TEST_REPO=""
}

teardown() {
  # dd/shv argv cells install the git shim (see those tests); a cell that
  # fails mid-run must not leave the shim dir + shim-FIRST PATH behind for
  # the next test (the shim logs EVERY `git difftool`, so a stale shim would
  # poison unrelated cells' git calls).
  teardown_git_shim 2>/dev/null || true
  cleanup_test_repo
}

# Per-row invocation prefix for the inert rows: log commands take no
# committish, show commands diff against HEAD~1 ("base"). Prints the args
# one per line for the caller to read into an array (word-splitting-free).
#
# LESSON (Task 3 review): callers consume this via process substitution
# (`mapfile -t args < <(psx_inert_args "$cmd")`), which SWALLOWS the exit
# status — the old `*) return 1` left args empty and an unknown row would
# run WITHOUT its committish: wrong-but-green. The guard therefore emits a
# stdout sentinel that flows into the hug invocation (failing the column
# test loudly) plus a stderr breadcrumb naming the row.
psx_inert_args() {
  case "$1" in
  l | ll | llu) : ;;
  shc | shcp | shp | sh) echo "HEAD~1" ;;
  *)
    echo "psx_inert_args: unknown row '$1' — add it to the case arms" >&2
    echo "__PSX_UNKNOWN_ROW__"
    ;;
  esac
}

# Relative timestamps ("2 seconds ago") rendered by log/show commands change
# when two captures of the same command straddle a second boundary. The
# inert-rows test below compares two such captures byte-for-byte and flaked
# in CI exactly this way (run 32247705110: "1 second ago" vs "0 seconds
# ago"). Normalizing both sides keeps the byte-identity claim about the
# trailing `--`'s inertness, not about the clock.
psx_strip_reltime() {
  sed -E 's/[0-9]+ (second|minute|hour|day|month|year)s? ago/<reltime> ago/g'
}

# sl-variant → file-kind noun used by the "No <kind> files matching ..."
# info message. Shared by the EMPTY and SWALLOW characterization tests so
# the mapping lives once (a wrong noun would otherwise fail two tests
# identically before anyone notices the duplication).
psx_sl_kind() {
  case "$1" in
  sls) echo "staged" ;;
  slu) echo "unstaged" ;;
  slk) echo "untracked" ;;
  sli) echo "ignored" ;;
  *)
    echo "psx_sl_kind: unknown row '$1' — add it to the case arms" >&2
    echo "__PSX_UNKNOWN_ROW__"
    ;;
  esac
}

# =============================================================================
# COLUMN 1 — `--help` / `-h` shows help (spec §2 rule 2)
# =============================================================================

@test "column help: -h shows USAGE for all contract rows" {
  for cmd in "${PATHSPEC_CONFORMANCE_ROWS[@]}"; do
    psx_setup
    run hug "$cmd" -h
    assert_success
    assert_output --partial "USAGE:"
    psx_reset
  done
}

@test "column help: --help via dispatcher hits git man routing (all rows)" {
  # characterization (Task 4): `hug <cmd> --help` never reaches the script —
  # the dispatcher execs `git <cmd> --help` and git routes to `man git-<cmd>`
  # (observed: exit 16, "No manual entry for git-<cmd>", zero USAGE output,
  # uniformly for all 10 rows). `-h` is the green contract surface today (see
  # test above); the suite's own precedent is test_log_outgoing.bats:28 which
  # skips with the same note. Routing `--help` to show_help is later #292 work.
  skip "characterization (Task 4): --help intercepted by git man routing (exit 16, no USAGE)"
}

# =============================================================================
# COLUMN 2 — `-- <path>` filters output, two-sided (spec §2 rule 1)
# =============================================================================

@test "column pathspec-filter: diff commands (picker rows)" {
  local filter present absent
  for cmd in "${PATHSPEC_PICKER_ROWS[@]}"; do
    # ss sees the STAGED set (src/a.py); su/sw see the UNSTAGED set
    # (docs/note.md). The non-matching marker is the other command's file.
    # a is the roster's MUTATOR: the observable is the stage-count summary —
    # scoped `hug a -- src/` stages ONLY the in-scope unstaged src/BIG.py
    # ("Staged 1 file"); a dropped pathspec would fall back to `git add -u`
    # and stage docs/note.md as well ("Staged 2 files." — the absent
    # marker), so the cell stays two-sided through the count itself.
    case "$cmd" in
    ss) filter="src/" present="src/a.py" absent="docs/note.md" ;;
    su | sw) filter="docs/" present="docs/note.md" absent="src/a.py" ;;
    a) filter="src/" present="Staged 1 file" absent="Staged 2 files" ;;
    *)
      # Sentinel pattern (psx_inert_args): the breadcrumb alone is the
      # contract — an un-armed future row fails HERE with the row named,
      # never as a subtle scope leak three assertions later.
      echo "psx pathspec-filter: unknown row '$cmd' — add it to the case arms" >&2
      return 1
      ;;
    esac
    psx_setup
    # a-probe: an UNSTAGED tracked file under src/ so the staging scope is
    # two-sided (same shape as su's probe in the scoped-picker column).
    case "$cmd" in a) echo big2 >> src/BIG.py ;; esac
    run hug "$cmd" -- "$filter"
    assert_success
    assert_output --partial "$present"
    refute_output --partial "$absent"
    psx_reset
  done
}

@test "column pathspec-filter: log commands (log rows)" {
  for cmd in "${PATHSPEC_LOG_ACTIVE_ROWS[@]}"; do
    psx_setup
    # The docs-only commit is the non-matching marker: it must vanish under
    # `-- src/` while the base commit (which touched src/) stays.
    run hug "$cmd" -- src/
    assert_success
    assert_output --partial "base"
    refute_output --partial "docs guide only"
    psx_reset
  done
}

@test "column pathspec-filter: show commands (show rows)" {
  for cmd in "${PATHSPEC_SHOW_ACTIVE_ROWS[@]}"; do
    psx_setup
    # HEAD~1 is "base" (touched src/); filter to src/, docs/note.md is the
    # non-matching marker.
    run hug "$cmd" HEAD~1 -- src/
    assert_success
    assert_output --partial "src/a.py"
    refute_output --partial "docs/note.md"
    psx_reset
  done
}

@test "column pathspec-filter: history commands (history rows)" {
  # cmod/cmoda amend the last commit — running them with a pathspec in the
  # fixture would mutate history, and neither has --dry-run (probed: help
  # shows no dry-run option). Per spec the row is scoped to help-only.
  skip "characterization (Task 4): ${PATHSPEC_HISTORY_ROWS[*]} mutate history, no --dry-run — row scoped to help-only"
}

# =============================================================================
# COLUMN 3 — quoted glob filters, two-sided (spec §2 rule 4)
# =============================================================================

@test "column glob-filter: diff commands (picker rows)" {
  local glob present absent
  for cmd in "${PATHSPEC_PICKER_ROWS[@]}"; do
    # a (mutator): same count-observable as the pathspec-filter column, but
    # through a GLOB — 'src/*.py' stages only the in-scope unstaged
    # src/BIG.py; an unscoped fallback would also stage docs/note.md.
    case "$cmd" in
    ss) glob='*.py' present="src/a.py" absent="docs/note.md" ;;
    su | sw) glob='*.md' present="docs/note.md" absent="src/a.py" ;;
    a) glob='src/*.py' present="Staged 1 file" absent="Staged 2 files" ;;
    *)
      # Sentinel pattern: breadcrumb + hard fail (see pathspec-filter note).
      echo "psx glob-filter: unknown row '$cmd' — add it to the case arms" >&2
      return 1
      ;;
    esac
    psx_setup
    case "$cmd" in a) echo big2 >> src/BIG.py ;; esac
    run hug "$cmd" -- "$glob"
    assert_success
    assert_output --partial "$present"
    refute_output --partial "$absent"
    psx_reset
  done
}

@test "column glob-filter: log commands (log rows)" {
  for cmd in "${PATHSPEC_LOG_ACTIVE_ROWS[@]}"; do
    psx_setup
    # '*.py' matches base's src files; the docs-only commit has none.
    run hug "$cmd" -- '*.py'
    assert_success
    assert_output --partial "base"
    refute_output --partial "docs guide only"
    psx_reset
  done
}

@test "column glob-filter: show commands (show rows)" {
  for cmd in "${PATHSPEC_SHOW_ACTIVE_ROWS[@]}"; do
    psx_setup
    run hug "$cmd" HEAD~1 -- '*.md'
    assert_success
    assert_output --partial "docs/note.md"
    refute_output --partial "src/a.py"
    psx_reset
  done
}

@test "column glob-filter: history commands (history rows)" {
  skip "characterization (Task 4): ${PATHSPEC_HISTORY_ROWS[*]} mutate history, no --dry-run — row scoped to help-only"
}

# =============================================================================
# COLUMN 4 — trailing bare `--` (spec §2 rule 3)
# =============================================================================

@test "column trailing-dashdash: picker arm for action commands (picker rows)" {
  # Technique from tests/unit/test_status_staging.bats:1500-1517: in CI (no
  # TTY) the picker arm must NOT print the regular diff markers. We also
  # assert the POSITIVE observable — the driver's cancel message — because
  # absence-only passes on a crash. Probed: exit 0 with that message on
  # stderr in BOTH gum branches (gum installed → TTY failure; gum absent →
  # gum-missing error, same message after). a's cancel wording differs
  # ("No files selected." — its own picker branch), so the positive marker
  # is per-row; the negative marker for a is ANY staging (the stage-all arm
  # must never run behind the picker trigger). Both asserts stay deliberately
  # loose (--partial) so a UI copy tweak breaks one place, not N cells.
  local refute_marker cancel_msg
  for cmd in "${PATHSPEC_PICKER_ROWS[@]}"; do
    case "$cmd" in
    ss) refute_marker="Staged diff" cancel_msg="available or cancelled" ;;
    su | sw) refute_marker="Unstaged diff" cancel_msg="available or cancelled" ;;
    a) refute_marker="Staged " cancel_msg="No files selected" ;;
    *)
      # Sentinel pattern: breadcrumb + hard fail (see pathspec-filter note).
      echo "psx trailing-dashdash: unknown row '$cmd' — add it to the case arms" >&2
      return 1
      ;;
    esac
    psx_setup
    run hug "$cmd" --
    assert_success
    refute_output --partial "$refute_marker"
    assert_output --partial "$cancel_msg"
    psx_reset
  done
}

@test "column trailing-dashdash: inert pass-through (inert rows)" {
  # These are not picker commands: a trailing bare `--` reaches git's own
  # separator semantics and is inert. Observable: exit 0 and output IDENTICAL
  # to the no-flag run (probed with diff — byte-identical). assert_equal (not
  # a bare [[ ]]]) so a failure names both sides.
  local plain args
  for cmd in "${PATHSPEC_INERT_ROWS[@]}"; do
    mapfile -t args < <(psx_inert_args "$cmd")
    psx_setup
    run hug "$cmd" "${args[@]}"
    assert_success
    plain="$(printf '%s' "$output" | psx_strip_reltime)"
    run hug "$cmd" "${args[@]}" --
    assert_success
    assert_equal "$plain" "$(printf '%s' "$output" | psx_strip_reltime)"
    psx_reset
  done
}

@test "column trailing-dashdash: history commands (history rows)" {
  # A trailing `--` on cmod/cmoda would perform a real amend (no dry-run).
  skip "characterization (Task 4): ${PATHSPEC_HISTORY_ROWS[*]} trailing -- would amend history — not probed in fixture"
}

# =============================================================================
# COLUMN 4b — scoped picker: `-- <pathspec> --` scopes the interactive picker
# (spec §2 rule 3 — "pathspecs are never silently discarded")
# =============================================================================
# Technique: a stub gum on PATH captures the candidate list it receives on
# STDIN (hug-select-files pipes candidates into `gum filter`; gum's argv
# carries only filter flags and cannot observe scoping — hence stdin, never
# argv). The stub exits 1 (cancelled), so the driver prints "No … available
# or cancelled." and exits 0 — same observable as COLUMN 4. HUG_TEST_MODE=true
# bypasses gum_available's TTY probe so the stub is actually invoked in CI.

# Installs a stub gum that records picker candidates to $GUM_CANDIDATES_FILE.
# MUST be called once per loop iteration, right before `run` — it truncates
# the capture file so a picker that never fires (scoped list empty →
# _handle_no_files_found short-circuits BEFORE gum runs) yields an EMPTY
# capture, not the previous iteration's content (stale-capture false-green;
# same lesson class as the psx_inert_args process-substitution swallow).
# The `filter`-only guard matters: every info/error message ALSO shells out
# to `gum log …`, and an unconditional `cat >` there would clobber the
# capture AFTER the picker ran (found while probing — the file kept ending
# up empty).
psx_install_stub_gum() {
  local stub_dir="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$stub_dir"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ "${1:-}" == filter ]]; then cat > "$GUM_CANDIDATES_FILE"; fi' \
    'exit 1' > "$stub_dir/gum"
  chmod +x "$stub_dir/gum"
  GUM_CANDIDATES_FILE="$BATS_TEST_TMPDIR/gum-candidates.txt"
  export GUM_CANDIDATES_FILE
  # Bypass gum_available's TTY probe so the stub is actually invoked in CI.
  export HUG_TEST_MODE=true
  PATH="$stub_dir:$PATH"
  : > "$GUM_CANDIDATES_FILE"
}

@test "column scoped-picker: -- src/ -- restricts picker candidates (picker rows)" {
  # Two-sided per spec §4: every captured candidate must match the scope
  # (contains $filter) AND the out-of-scope marker must be ABSENT. The base
  # fixture only stages src/a.py and leaves docs/note.md unstaged, so each
  # command's mode needs its own probe state (see the case arms):
  #   su — needs an UNSTAGED change under src/ (echo >> src/BIG.py) beside
  #        the fixture's unstaged docs/note.md
  #   ss — needs a STAGED non-src candidate (git add docs/note.md) beside
  #        the fixture's staged src/a.py
  #   sw — combined mode: staged src/a.py + unstaged docs/note.md is already
  #        two-sided out of the box
  #   a  — picker lists UNSTAGED+UNTRACKED (no staged): same probe as su.
  #        Under the cancelling stub nothing stages — the cell is read-only
  #        by construction; a's SELECTION semantics live in the dedicated
  #        selecting-stub test below, not this shared column.
  local filter="src/" absent="docs/note.md" present candidates cancel_msg
  for cmd in "${PATHSPEC_PICKER_ROWS[@]}"; do
    present="$filter"
    cancel_msg="available or cancelled"
    case "$cmd" in
    su) present="src/BIG.py" ;;
    ss | sw) present="src/a.py" ;;
    a) present="src/BIG.py" cancel_msg="No files selected" ;;
    *)
      # Sentinel pattern (psx_inert_args/psx_sl_kind): a future picker row
      # without a case arm must fail with a breadcrumb, not "empty
      # candidates" three assertions later.
      echo "psx scoped-picker: unknown row '$cmd' — add it to the case arms" >&2
      present="__PSX_UNKNOWN_ROW__"
      ;;
    esac
    psx_setup
    case "$cmd" in
    su | a) echo big2 >> src/BIG.py ;;
    ss) git add docs/note.md ;;
    esac

    psx_install_stub_gum
    run hug "$cmd" -- "$filter" --
    assert_success
    assert_output --partial "$cancel_msg"

    # Strip ANSI status coloring before matching (candidate lines are
    # "<colored status> <plain filename>").
    candidates=$(sed $'s/\033\\[[0-9;]*m//g' "$GUM_CANDIDATES_FILE")
    [[ -n "$candidates" ]]
    grep -qF "$present" <<< "$candidates"
    # Out-of-scope file absent from the candidate list … (NOT `! grep`:
    # commands prepended with ! are exempt from errexit, so BATS would never
    # see the failure — bats file-wide gotcha, probed in the red run)
    if grep -qF "$absent" <<< "$candidates"; then
      fail "out-of-scope candidate leaked into picker: $absent"
    fi
    # … and EVERY candidate line matches the scope.
    local stray
    stray=$(grep -v "$filter" <<< "$candidates" || true)
    [[ -z "$stray" ]]
    psx_reset
  done
}

# =============================================================================
# COLUMN 5 — cardinality (spec §2 rule 5)
# =============================================================================

@test "column cardinality: N/A for all contract rows" {
  # All 10 rows are multi-pathspec commands — the single-file cardinality
  # guard (reject_multiple_files, spec §3.2) targets fa/fb/fblame/fborn/
  # fcon/llf/h-steps/stats-file, none of which are in this row table.
  skip "N/A: all contract rows accept multiple pathspecs (single-file commands are Task 4+ rows)"
}

# =============================================================================
# COLUMN 6 — unknown flag exits non-zero (no silent pathspec swallow)
# =============================================================================

@test "column unknown-flag: non-zero for all contract rows" {
  # Probed behaviors (all non-zero):
  #   sw/ss/su  → exit 1,  "invalid option -- 'x'" (getopt names the flag)
  #   shc/shcp/shp → exit 2, own usage banner (unknown option → help)
  #   l/ll      → exit 128, git's "fatal: unrecognized argument" (pass-through;
  #               git's own error is the observable — spec §4 row staging)
  #   cmod/cmoda → exit 129, git commit's "unknown switch" (pass-through)
  # We assert non-zero for all, and the flag-naming message only where it is
  # deterministic (the diff commands).
  for cmd in "${PATHSPEC_CONFORMANCE_ROWS[@]}"; do
    psx_setup
    run hug "$cmd" -xX
    assert_failure
    case "$cmd" in
    sw | ss | su)
      assert_output --partial "invalid option"
      ;;
    esac
    psx_reset
  done
}

# =============================================================================
# COLUMN 7 — git magic pathspecs pass through verbatim (spec §2 rule 6)
# =============================================================================

@test "column magic-pathspec: diff commands (picker rows)" {
  # :(icase) positive: case-variant spellings still match the changed files.
  # a (mutator): ':(icase)SRC/BIG.PY' stages the in-scope unstaged src/BIG.py
  # ("Staged 1 file"); an unscoped fallback would also stage docs/note.md
  # ("Staged 2 files") and fail the present assert.
  local icase present
  for cmd in "${PATHSPEC_PICKER_ROWS[@]}"; do
    case "$cmd" in
    ss) icase=':(icase)SRC/A.PY' present="src/a.py" ;;
    su | sw) icase=':(icase)DOCS/NOTE.MD' present="docs/note.md" ;;
    a) icase=':(icase)SRC/BIG.PY' present="Staged 1 file" ;;
    *)
      # Sentinel pattern: breadcrumb + hard fail (see pathspec-filter note).
      echo "psx magic-pathspec: unknown row '$cmd' — add it to the case arms" >&2
      return 1
      ;;
    esac
    psx_setup
    case "$cmd" in a) echo big2 >> src/BIG.py ;; esac
    run hug "$cmd" -- "$icase"
    assert_success
    assert_output --partial "$present"
    psx_reset
  done
}

@test "column magic-pathspec: log commands (ll carries the class)" {
  psx_setup
  # :(icase) two-sided: matches the case-variant path of a base file, and the
  # docs-only commit stays absent.
  run hug ll -- ':(icase)src/big.py'
  assert_success
  assert_output --partial "base"
  refute_output --partial "docs guide only"

  psx_reset
  psx_setup
  # :(exclude) two-sided: src/ minus src/a.py still admits base (BIG.py
  # matched), while the docs-only commit stays absent.
  run hug ll -- 'src/' ':(exclude)src/a.py'
  assert_success
  assert_output --partial "base"
}

@test "column magic-pathspec: show commands (show rows)" {
  for cmd in "${PATHSPEC_SHOW_ACTIVE_ROWS[@]}"; do
    psx_setup
    # :(icase): 'src/big.py' must match src/BIG.py in the base commit.
    run hug "$cmd" HEAD~1 -- ':(icase)src/big.py'
    assert_success
    assert_output --partial "src/BIG.py"
    refute_output --partial "src/a.py"
    psx_reset
  done

  psx_setup
  # :(exclude) two-sided on the changed-files list: src/ minus a.py.
  run hug shc HEAD~1 -- 'src/' ':(exclude)src/a.py'
  assert_success
  assert_output --partial "src/BIG.py"
  refute_output --partial "src/a.py"
}

@test "column magic-pathspec: history commands (history rows)" {
  skip "characterization (Task 4): ${PATHSPEC_HISTORY_ROWS[*]} mutate history, no --dry-run — row scoped to help-only"
}

# =============================================================================
# COLUMN 8 — `--json` + pathspec (two-sided where the command has --json)
# =============================================================================

@test "column json-pathspec: ll JSON stays pathspec-filtered" {
  psx_setup
  run hug ll --json -- src/
  assert_success
  # Zero non-JSON bytes: the whole payload must parse.
  echo "$output" | python3 -m json.tool >/dev/null
  # Two-sided: commit inside the pathspecs present, commit outside absent.
  [[ "$output" == *"base"* ]]
  [[ "$output" != *"docs guide only"* ]]
}

@test "column json-pathspec: rows without --json (sw ss su shc shcp shp l cmod cmoda)" {
  # Probed: none of these rows expose a --json flag (only ll in this table
  # does). The --json column activates fully in the Task 4 / PR-B rows
  # (sl* family, lc, lf, llu — spec §4).
  skip "N/A in this row table: no --json flag on these commands (activates in Task 4/PR-B rows)"
}

# =============================================================================
# CHARACTERIZATION ROWS (Task 4) — TODAY's behavior for un-migrated commands
# =============================================================================
# Every test below pins what the PROBE observed, not what the contract wants.
# Flip targets are named per test; when a later PR migrates a command, its
# test here must be updated red→green IN THAT PR (deliberate, never silent).
# =============================================================================

@test "helper guard: psx_inert_args fails loudly on unknown row" {
  # Task 3 review follow-up: process substitution swallows exit statuses, so
  # the guard's contract is a stdout sentinel (flows into the hug invocation
  # and fails the column test) + a stderr breadcrumb naming the row.
  run psx_inert_args totally-bogus-row
  assert_output --partial "unknown row 'totally-bogus-row'"
  assert_output --partial "__PSX_UNKNOWN_ROW__"
}

@test "contract sl-family: -- src/ filters via the split (sl sla; was characterization)" {
  # FLIPPED by PR-B Task 4 (was characterization): sl/sla (statusbase) were
  # migrated onto parse_common_flags_with_pathspecs, so the split consumes the
  # separator and the row now asserts the CONTRACT (filtering via the split),
  # not the pre-PR-B coincidence. See the statusbase conformance tests. sls was
  # retired from this row by Task 5 (migrated — see the sls-family conformance
  # tests).
  for cmd in "${PATHSPEC_CHAR_SL_FILTER_ROWS[@]}"; do
    psx_setup
    run hug "$cmd" -- src/
    assert_success
    assert_output --partial "src/a.py"
    refute_output --partial "docs/note.md"
    psx_reset
  done
}

@test "characterization sl-family: --help hits git man routing, no USAGE (all six)" {
  # characterization: flip target PR-B — `--help` never reaches the script:
  # the dispatcher execs `git <cmd> --help` and git routes to man (probed:
  # exit 16, "No manual entry for git-<cmd>" — or, for the aliased sl/sla,
  # "'sl' is aliased to 'statusbase -uno'" first). NOTE: this contradicts
  # the audited spec's "swallowed as a pathspec" reading — the probe wins.
  for cmd in "${PATHSPEC_CHAR_SL_HELP_ROWS[@]}"; do
    psx_setup
    run hug "$cmd" --help
    # Review fix (pre-landing): pin only FAILURE + no-USAGE. The exact 16 is
    # git's man-routing exit and only holds where man(1) exists; on hosts
    # without it git still fails (nonzero) but with a different code.
    assert_failure
    refute_output --partial "USAGE:"
    if command -v man >/dev/null 2>&1; then
      assert_equal 16 "$status"
    fi
    psx_reset
  done
}

# slc's rows live in the SLC CONFORMANCE section (Task 7): it needs the
# dedicated conflict fixture, so it cannot ride the shared sl-family loops
# (its former "-h shows USAGE" characterization row moved there too).

# =============================================================================
# STATUSBASE CONFORMANCE (PR-B Task 4, #292/#298) — sl/sla flipped rows
# =============================================================================
# `sl`/`sla` are gitconfig aliases (`sl = statusbase -uno`,
# `sla = statusbase --long`) — invoking them IS the smoke test that the
# migrated statusbase code is reached with the alias-passed pre-args.
# =============================================================================

@test "conformance statusbase (Task 4): sl/sla -h shows USAGE" {
  # FLIPPED (Task 4): statusbase defines show_help and parses via
  # parse_common_flags_with_pathspecs, so -h reaches show_help through BOTH
  # aliases' pre-args (-uno / --long). Before: -h was swallowed as a pathspec
  # (probed: exit 0 + "No staged or unstaged files matching '-h' found.").
  for cmd in sl sla; do
    psx_setup
    run hug "$cmd" -h
    assert_success
    assert_output --partial "USAGE:"
    psx_reset
  done
}

@test "conformance statusbase (Task 4): unknown flag loud, exit 2" {
  # FLIPPED (Task 4): flag-shaped unknown tokens error instead of silently
  # becoming pathspecs. Before (probed): exit 0 + "matching '-xX' found." +
  # summary. Exit code 2 = HUG_EX_USAGE (usage error), matching the
  # family-wide error template.
  for cmd in sl sla; do
    psx_setup
    run hug "$cmd" -xX
    assert_failure
    assert_equal 2 "$status"
    assert_output --partial "Unknown option: -xX"
    psx_reset
  done
}

@test "conformance statusbase (Task 4): -- src/ filters and suppresses summary" {
  # FLIPPED (Task 4): the separator is consumed by the split (no phantom
  # '--' pathspec) and the trailing whole-repo `hug s` summary is suppressed
  # iff a real pathspec is active. Before (probed): the listing filtered but
  # the summary line ("HEAD: ...") still printed.
  for cmd in sl sla; do
    psx_setup
    run hug "$cmd" -- src/
    assert_success
    assert_output --partial "src/a.py"
    refute_output --partial "docs/note.md"
    refute_output --partial "HEAD:"
    psx_reset
  done
}

@test "conformance statusbase (Task 4): bare -- inert with summary parity" {
  # FLIPPED (Task 4): a trailing bare '--' is stripped by the split and is
  # fully inert — byte-identical output to the unfiltered run INCLUDING the
  # summary. Before (probed): the bare '--' became a phantom pathspec
  # matching nothing ("No staged or unstaged files matching '--' found.").
  # Both runs share ONE fixture: the summary embeds the HEAD short hash,
  # which differs across fixtures.
  for cmd in sl sla; do
    psx_setup
    run hug "$cmd"
    assert_success
    unfiltered="$output"
    run hug "$cmd" --
    assert_success
    assert_equal "$unfiltered" "$output"
    assert_output --partial "HEAD:"
    psx_reset
  done
}

# =============================================================================
# SLS-FAMILY CONFORMANCE (PR-B Task 5, #292/#298) — sls/slu/slk/sli flipped
# =============================================================================
# The four filtered listings migrated to the uniform pathspec contract
# (split + own-loop), and the shared selector loops in hug-select-files
# (list_files_with_status / count_files_with_status) became separator-aware,
# so a protective '--' at the script→lib boundary is now HONORED: everything
# after it is a pathspec even when it spells '--cwd'/'--staged'.
# =============================================================================

@test "conformance sls-family (Task 5): -h shows USAGE" {
  # FLIPPED (Task 5): the four scripts define show_help and parse via
  # parse_common_flags_with_pathspecs BEFORE check_git_repo, so -h reaches
  # show_help from any cwd. Before (probed): -h was swallowed as a pathspec
  # (exit 0 + "No <kind> files matching '-h' found.").
  for cmd in sls slu slk sli; do
    psx_setup
    run hug "$cmd" -h
    assert_success
    assert_output --partial "USAGE:"
    psx_reset
  done
}

@test "conformance sls-family (Task 5): unknown flag loud, exit 2" {
  # FLIPPED (Task 5): flag-shaped unknown tokens error instead of silently
  # becoming pathspecs. Before (probed): exit 0 + "No <kind> files matching
  # '-xX' found.". Exit 2 = HUG_EX_USAGE, family-wide error template
  # (same shape as statusbase's, naming the fix).
  local kind
  for cmd in sls slu slk sli; do
    kind=$(psx_sl_kind "$cmd")
    psx_setup
    run hug "$cmd" -xX
    assert_failure
    assert_equal 2 "$status"
    assert_output --partial "Unknown option: -xX"
    assert_output --partial "Pathspecs beginning with '-' require '--': hug $cmd -- -xX"
    psx_reset
  done
}

@test "conformance sls-family (Task 5): -- src/ filters; phantom '--' gone from message" {
  # FLIPPED (Task 5): the split consumes the separator, so it never rides in
  # the pathspec list. sls filters two-sided (staged src/a.py is in scope);
  # slu/slk/sli have NO matching file, and their empty-info message now says
  # matching 'src/' WITHOUT the phantom '--' — the "No unstaged files
  # matching '--' 'src/'" fingerprint (probed pre-migration) is gone.
  # Sink 4 (spec §3.1, family-wide — fix landed post-Task-10 spec review):
  # a scoped run also suppresses the trailing whole-repo `hug s` summary —
  # it would misdescribe the scope. The inert bare `--` KEEPS the summary
  # (byte-identical parity, pinned by the next test).
  psx_setup
  run hug sls -- src/
  assert_success
  assert_output --partial "src/a.py"
  refute_output --partial "docs/note.md"
  refute_output --partial "matching '--'"
  refute_output --partial "HEAD:"
  psx_reset

  local kind
  for cmd in slu slk sli; do
    kind=$(psx_sl_kind "$cmd")
    psx_setup
    run hug "$cmd" -- src/
    assert_success
    refute_output --partial "docs/note.md"
    refute_output --partial "new.txt"
    assert_output --partial "No ${kind} files matching 'src/' found."
    refute_output --partial "matching '--'"
    refute_output --partial "HEAD:"
    psx_reset
  done
}

@test "conformance sls-family (Task 5): bare -- inert with summary parity" {
  # FLIPPED (Task 5): a trailing bare '--' is stripped by the split and is
  # fully inert — byte-identical output to the unfiltered run INCLUDING the
  # summary. Before (probed): the bare '--' became a phantom pathspec
  # matching nothing ("No <kind> files matching '--' found."). Both runs
  # share ONE fixture (the summary embeds the HEAD short hash).
  for cmd in sls slu slk sli; do
    psx_setup
    run hug "$cmd"
    assert_success
    unfiltered="$output"
    run hug "$cmd" --
    assert_success
    assert_equal "$unfiltered" "$output"
    assert_output --partial "HEAD:"
    psx_reset
  done
}

@test "conformance sls-family (Task 5): scoped × quiet keeps scope, drops summary" {
  # Mode interaction: -q is consumed by the split (as HUG_QUIET) and
  # rehydrated after it — scoped quiet keeps the pathspec filter and drops
  # BOTH the summary and (slk) the status column. Non-empty scope (sls) and
  # empty scope (slu: no unstaged file under src/) both pinned.
  psx_setup
  run hug sls -q -- src/
  assert_success
  assert_output --partial "S:"
  assert_output --partial "src/a.py"
  refute_output --partial "docs/note.md"
  refute_output --partial "HEAD:"
  psx_reset

  psx_setup
  # Empty scope + quiet: the info message itself is quieted (HUG_QUIET
  # silences info chatter) — an empty stdout IS the pinned behavior.
  run hug slu -q -- src/
  assert_success
  assert_output ""
  psx_reset
}

@test "conformance sls-family (Task 5): scoped × count non-empty and empty" {
  # Mode interaction: count mode is fed from the collected pathspecs (the
  # run_count_mode sink carries the protective '--', honored by the now
  # separator-aware count_files_with_status). count mode also suppresses the
  # trailing summary (run_count_mode exits after printing the number).
  psx_setup
  run hug sls -c -- src/
  assert_success
  assert_output "1"
  refute_output --partial "HEAD:"
  psx_reset

  psx_setup
  run hug slu -c -- src/
  assert_success
  assert_output "0"
  refute_output --partial "HEAD:"
  psx_reset
}

@test "conformance sls-family (Task 6): --json honors pathspecs, empty scope keeps shape" {
  # FLIPPED (Task 6): the --json sink chain (output_json_status →
  # output_json_status_unified → collect_git_files_json → list_*_files)
  # now forwards pathspecs collected after the protective '--'. The
  # out-of-scope unstaged docs/note.md must be ABSENT, and the empty scope
  # (no unstaged file under src/) must keep the envelope shape — zero-length
  # "unstaged" array present, summary count 0. The machine contract must not
  # change shape with scope.
  psx_setup
  run hug slu --json -- src/
  assert_success
  local json_out="$output"
  run bash -c "printf '%s' \"\$1\" | python3 -m json.tool > /dev/null" _ "$json_out"
  assert_success
  [[ "$json_out" != *"docs/note.md"* ]]
  run python3 -c "import json,sys; d=json.loads(sys.argv[1]); print('unstaged' in d, d['unstaged'], d['summary']['unstaged'])" "$json_out"
  assert_output "True [] 0"
  psx_reset
}

# =============================================================================
# SLC CONFORMANCE (PR-B Task 7, #292/#298) — conflicted-files listing flipped
# =============================================================================
# slc migrates last of the sl* family (it already had show_help; only its
# flag loop was pre-contract): unknown flags were silently swallowed as
# pathspecs, and --json dropped pathspecs BY DOCUMENTED CONTRACT (the
# 2026-08-06 slc design spec — since superseded, see the claim-flip sweep).
# Rows run on the dedicated two-dir conflict fixture (psx_setup_conflict)
# so every scope assertion is two-sided: 'src/' keeps src/c.txt and must
# drop docs/c.txt.
# =============================================================================

@test "conformance slc (Task 7): -h shows USAGE" {
  # PIN (moved from the characterization section): slc keeps its show_help
  # and the uniform split routes -h/--help to it BEFORE check_git_repo, so
  # help works from any cwd. Post-flip the help text no longer contradicts
  # the behavior: the --json flag line and DESCRIPTION both state scoping.
  psx_setup
  run hug slc -h
  assert_success
  assert_output --partial "USAGE:"
  refute_output --partial "ignores pathspecs"
  psx_reset
}

@test "conformance slc (Task 7): unknown flag loud, exit 2" {
  # FLIPPED (Task 7): flag-shaped unknown tokens error instead of silently
  # becoming pathspecs. Before (probed shape, same defect as the sls
  # family): exit 0 + "No conflicted files matching '-xX' found." — a
  # typo'd flag looked like an empty answer. Exit 2 = HUG_EX_USAGE,
  # family-wide error template.
  psx_setup_conflict
  run hug slc -xX
  assert_failure
  assert_equal 2 "$status"
  assert_output --partial "Unknown option: -xX"
  assert_output --partial "Pathspecs beginning with '-' require '--': hug slc -- -xX"
  psx_reset
}

@test "conformance slc (Task 7): -- src/ filters two-sided, no phantom '--'" {
  # PIN + hardening (Task 7): filtering already worked by accident of the
  # Task 5 selector surgery (slc's old loop passed '--' through as a
  # pathspec and the separator-aware lib consumed it); the migration makes
  # it contract — the split owns the separator, so it can never ride into
  # the empty-info message as a phantom filter.
  # Sink 4 (spec §3.1, family-wide — gate added post-doc-review): a scoped
  # run also suppresses the trailing whole-repo `hug s` summary; the inert
  # bare '--' KEEPS it (pinned by the next test).
  psx_setup_conflict
  run hug slc -- src/
  assert_success
  assert_output --partial "src/c.txt"
  refute_output --partial "docs/c.txt"
  refute_output --partial "matching '--'"
  refute_output --partial "HEAD:"
  psx_reset
}

@test "conformance slc (Task 7): bare -- inert with summary parity" {
  # PIN (Task 7): a trailing bare '--' is stripped by the split and is
  # fully inert — byte-identical output to the unfiltered run INCLUDING
  # the summary (both runs share ONE fixture; the summary embeds the HEAD
  # short hash).
  psx_setup_conflict
  run hug slc
  assert_success
  unfiltered="$output"
  run hug slc --
  assert_success
  assert_equal "$unfiltered" "$output"
  assert_output --partial "HEAD:"
  psx_reset
}

@test "conformance slc (Task 7): --json honors pathspecs, empty scope keeps shape" {
  # FLIPPED (Task 7): slc now forwards its collected pathspecs into the
  # --json sink chain (output_json_status → … → list_*_files, made
  # pathspec-aware in Task 6) — this is the row that was RED before the
  # migration: the envelope used to describe the FULL conflicted state
  # regardless of pathspecs. Two-sided: src/c.txt in, docs/c.txt out;
  # summary.conflicted matches the scoped array; empty scope keeps the
  # envelope shape (zero-length "conflicted" array present, count 0).
  psx_setup_conflict
  run hug slc --json -- src/
  assert_success
  local json_out="$output"
  run bash -c "printf '%s' \"\$1\" | python3 -m json.tool > /dev/null" _ "$json_out"
  assert_success
  [[ "$json_out" == *"src/c.txt"* ]]
  [[ "$json_out" != *"docs/c.txt"* ]]
  run python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(len(d['conflicted']), d['summary']['conflicted'])" "$json_out"
  assert_output "1 1"
  psx_reset

  psx_setup_conflict
  run hug slc --json -- nomatch/
  assert_success
  json_out="$output"
  run python3 -c "import json,sys; d=json.loads(sys.argv[1]); print('conflicted' in d, d['conflicted'], d['summary']['conflicted'])" "$json_out"
  assert_output "True [] 0"
  psx_reset
}

@test "conformance separator-aware lib (Task 5): pathspec spelled '--cwd' scopes, not toggles" {
  # Lib-surgery acceptance probe (amended Task 4 AC): a file LITERALLY named
  # '--cwd', staged, must be listed/scoped-to by the sl family — the
  # selector-level loops in hug-select-files now honor the protective '--'
  # the scripts append, so the token is DATA, not the scope-to-cwd flag.
  # Before (probed): '--cwd' toggled scope_cwd and the run listed EVERYTHING
  # (the whole-repo, cwd-relative listing — src/a.py included).
  # Covers both boundaries: the listing sink (sl, sls) and the count sink
  # (sls -c → run_count_mode → count_files_with_status).
  psx_setup_optnamed_cwd_file
  run hug sls -- --cwd
  assert_success
  [[ "$output" == *"--cwd"* ]]
  [[ "$output" != *"src/a.py"* ]] # still staged in the fixture — must be filtered out
  psx_reset

  psx_setup_optnamed_cwd_file
  run hug sl -- --cwd
  assert_success
  [[ "$output" == *"--cwd"* ]]
  refute_output --partial "src/a.py"
  refute_output --partial "docs/note.md"
  psx_reset

  psx_setup_optnamed_cwd_file
  run hug sls -c -- --cwd
  assert_success
  assert_output "1"
  psx_reset
}


@test "conformance us (PR-B Task 8): -- src/ filters unstaging, two-sided" {
  # FLIPPED (Task 8, spec §3.1): mid-stream '--' is a pathspec separator —
  # was: "Unknown option: --. See 'hug us --help'." exit 1 (probed).
  # Two-sided: staged mods in BOTH dirs; the 'src/' scope must unstage
  # src/a.py ONLY — docs/note.md (staged, OUT of scope) must survive.
  psx_setup
  git add docs/note.md # second staged file, outside the src/ scope
  run hug us -- src/
  assert_success
  # The report echoes the given pathspec (git restore consumes it natively —
  # dir pathspecs, globs and magic keep git semantics); the behavioral
  # asserts below are the load-bearing two-sided proof.
  assert_output --partial "Unstaged 1 file"
  assert_output --partial "src/"
  run hug sls
  refute_output --partial "src/a.py" # in-scope: unstaged
  assert_output --partial "docs/note.md" # out-of-scope: still staged
  psx_reset
}

@test "conformance us (PR-B Task 8): positional pathspec unstages exactly as today" {
  # Carried over VERBATIM from the characterization row (probed: exit 0,
  # "Unstaged 1 file", and hug sls no longer lists it): the documented
  # no-separator invocation must keep working through the migration.
  psx_setup
  run hug sls
  assert_success
  assert_output --partial "src/a.py"
  run hug us src/a.py
  assert_success
  assert_output --partial "Unstaged 1 file"
  assert_output --partial "src/a.py"
  run hug sls
  refute_output --partial "src/a.py"
  psx_reset
}

@test "conformance us (PR-B Task 8): bare trailing -- inert, zero-args dispatch parity" {
  # FLIPPED (Task 8): a trailing bare '--' is a no-op token — `hug us --`
  # ≡ `hug us` (output equality + exit equality). The split runs WITHOUT
  # --picker (us's selector is the zero-args fallback, not the picker arm),
  # so the consumed '--' leaves NO pathspecs and NO positionals → identical
  # dispatch.
  #
  # Headless observable (per gum-presence — same two-branch technique as the
  # picker-rows column): with gum INSTALLED, `run` still has no TTY, so gum
  # filter fails and the selector lands on "No files selected." (exit 0);
  # with gum ABSENT, gum_available fails → "Interactive mode requires 'gum'"
  # (exit 1). The branch differs by machine — the INVARIANT under test is
  # the `--` parity, so accept either branch marker and then pin equality.
  # The fixture pins ≥1 staged file (src/a.py): both branch markers prove
  # the selector ran — NOT the "No staged files" early exit, so the equality
  # is non-vacuous (an empty staging area would trivially pass).
  psx_setup
  run hug us
  local baseline_status=$status
  local baseline_output="$output"
  [[ "$baseline_output" == *"No files selected"* || "$baseline_output" == *"Interactive mode requires 'gum'"* ]]
  psx_reset

  psx_setup
  run hug us --
  assert_equal "$baseline_status" "$status"
  assert_equal "$baseline_output" "$output"
  refute_output --partial "Unknown option"
  psx_reset
}

@test "conformance us (PR-B Task 8): unknown -* loud, exit 2 (family template)" {
  # FLIPPED (Task 8): unknown dash-tokens exit 2 (HUG_EX_USAGE) with the
  # family error template — was: exit 1, "Unknown option: -xX. See
  # 'hug us --help'." (probed).
  psx_setup
  run hug us -xX
  assert_equal 2 "$status"
  assert_output --partial "Unknown option: -xX. Pathspecs"
  assert_output --partial "hug us -- -xX"
  psx_reset
}

@test "conformance us (PR-B Task 8): -- -foo.txt unstages a file literally named -foo.txt" {
  # Spec-review finding 1 (MEDIUM): the help PROMISES 'hug us -- <path>' for
  # dash-paths — the validation probe must honor it. Was: 'git ls-files
  # --error-unmatch "$file"' without a separator parsed '-foo.txt' as an
  # OPTION → false "File '-foo.txt' is not tracked by git." exit 1 (reviewer
  # probed with a tracked file named -foo.txt). Two-sided: docs/note.md
  # (also staged) must survive.
  psx_setup
  echo dashfile > ./-foo.txt
  git add -- ./-foo.txt # separator form is mandatory — the name looks like a flag
  git commit -q -m "file literally named -foo.txt"
  echo dash2 >> ./-foo.txt
  git add -- ./-foo.txt # staged mod on the dash-named file
  git add docs/note.md # second staged file, must survive
  run hug us -- -foo.txt
  assert_success
  assert_output --partial "Unstaged 1 file"
  assert_output --partial "-foo.txt"
  run hug sls
  refute_output --partial "-foo.txt" # in-scope: unstaged
  assert_output --partial "docs/note.md" # out-of-scope: still staged
  psx_reset
}

@test "conformance us (PR-B Task 8): empty intersection with scope is a no-match message, never the selector" {
  # Spec-review finding 2 (MINOR, safety): when the pathspec scope empties
  # the from-source list, falling through to the zero-args selector would
  # (TTY+gum) offer the FULL staged list, silently ignoring the scope.
  # Contract: scoped-but-empty → family no-match info message, exit 0.
  # Headless observable: the selector NEVER opens (no gum-branch markers).
  psx_setup
  run hug us --from-commit HEAD -- nonexistent/
  assert_success
  assert_output --partial "No files matching 'nonexistent/' to unstage."
  refute_output --partial "Interactive mode requires 'gum'"
  refute_output --partial "No files selected"
  run hug sls # staged state untouched
  assert_output --partial "src/a.py"
  psx_reset
}

@test "conformance us (PR-B Task 8): --from-commit INTERSECTS with pathspecs (not concat)" {
  # FLIPPED (Task 8, contract §3.1): from-source files ∩ scope. Concat is a
  # UNION and would unstage docs/y.txt too — OUTSIDE the 'src/' scope, the
  # exact opposite of the contract (probed union shape: `us --from-commit
  # HEAD` unstages every staged file the commit mentions). Two-sided:
  # src/x.txt unstaged, docs/y.txt stays staged.
  psx_setup
  # LESSON (same as the fixture header): the psx fixture arrives with
  # src/a.py STAGED — any naive commit sweeps it in. Unstage it first, build
  # the discriminating commit (src/x.txt + docs/y.txt ONLY), then re-stage
  # all three mods so the scope assertion is two-sided in BOTH dirs.
  git restore --staged src/a.py
  echo x1 > src/x.txt
  echo y1 > docs/y.txt
  git add src/x.txt docs/y.txt
  git commit -q -m "touch src/x docs/y"
  echo x2 >> src/x.txt
  echo y2 >> docs/y.txt
  git add src/a.py src/x.txt docs/y.txt
  run hug us --from-commit HEAD -- src/
  assert_success
  assert_output --partial "Unstaged 1 file"
  assert_output --partial "src/x.txt"
  refute_output --partial "docs/y.txt"
  run hug sls
  assert_output --partial "docs/y.txt"
  refute_output --partial "src/x.txt"
  psx_reset
}

@test "conformance us (PR-B Task 8): staged deletion in scope is unstaged too (Codex P1)" {
  # Codex review P1: 'git ls-files' misses index-removed (staged-DELETED)
  # entries, so the intersection silently dropped them while reporting
  # success (probed red: "Unstaged 1 file: ✓ src/keep.txt" with
  # 'D src/del.txt' left staged). The scope set must union staged-deletion
  # paths, and the validation probe must accept them (they are in HEAD,
  # just not in the index — also fixes unstaging a deletion BY NAME).
  psx_setup
  git restore --staged src/a.py # commit-sweep lesson: keep the commit discriminating
  echo del > src/del.txt
  echo keep > src/keep.txt
  git add src/del.txt src/keep.txt
  git commit -q -m "add del+keep"
  git rm -q src/del.txt # staged deletion of del.txt
  echo keep2 >> src/keep.txt
  git add src/keep.txt # staged mod of keep.txt
  run hug us --from-commit HEAD -- src/
  assert_success
  assert_output --partial "Unstaged 2 files"
  run git status --porcelain
  refute_output --partial "D  src/del.txt" # staged deletion: GONE
  assert_output --partial " D src/del.txt" # now an UNSTAGED deletion only
  assert_output --partial " M src/keep.txt" # mod unstaged too
  psx_reset
}

@test "conformance us (PR-B Task 8): from-file CWD-relative names match from a subdirectory (Codex P2)" {
  # Codex review P2: from-file lists are commonly CWD-relative ('a.txt'
  # written inside sub/), while the scope set is root-relative — the
  # exact-string membership emptied and 'us --from-file files.txt -- .'
  # reported "No files matching '.' to unstage." (probed red) with
  # sub/a.txt left staged. Sources are canonicalized to root-relative now.
  psx_setup
  git restore --staged src/a.py
  mkdir sub
  echo a1 > sub/a.txt
  git add sub/a.txt
  git commit -q -m "add sub/a"
  echo a2 >> sub/a.txt
  git add sub/a.txt
  printf 'a.txt\n' > sub/files.txt # CWD-relative name
  cd sub || return 1
  run hug us --from-file files.txt -- .
  assert_success
  assert_output --partial "Unstaged 1 file"
  # The report echoes the CWD-relative spelling (same base as the plain
  # branch echoing the user's own spelling); the behavioral assert below
  # is the load-bearing proof.
  assert_output --partial "a.txt"
  cd "$TEST_REPO" || return 1
  run git diff --cached --name-only
  refute_output --partial "sub/a.txt" # unstaged
  psx_reset
}

@test "conformance us (roast): unresolvable from-file lines fail loud, never silent no-match" {
  # Code-roast MAJOR: from src/, a from-file list with ROOT-relative
  # spellings + a scope — the batch canonicalization silently dropped the
  # unresolvable line: "No files matching '.' to unstage." exit 0 while
  # src/a.py stayed staged (probed red). The NO-scope variant of the same
  # bad list fails loud; the scoped variant must mirror that shape.
  psx_setup
  cd src || return 1
  printf 'src/a.py\n' > root-spell.txt
  run hug us --from-file root-spell.txt -- .
  assert_failure
  assert_output --partial "File 'src/a.py' is not tracked by git."
  refute_output --partial "No files matching"
  cd "$TEST_REPO" || return 1
  run git diff --cached --name-only
  assert_output --partial "src/a.py" # untouched — nothing was silently unstaged
  psx_reset
}

@test "conformance us (roast): report lists RESOLVED files, not the raw pathspec" {
  # Code-roast MINOR: ':(exclude)docs/' matched the staged set minus
  # docs/, but the report echoed the pathspec itself ("Unstaged 1 file:
  # ✓ :(exclude)docs/", probed red) — wrong noun and a useless line. The
  # report must name the resolved restore targets.
  psx_setup
  git add docs/note.md # second staged file, excluded by the magic spec
  run hug us -- ':(exclude)docs/'
  assert_success
  assert_output --partial "Unstaged 1 file"
  assert_output --partial "src/a.py" # the RESOLVED target
  refute_output --partial "✓ :(exclude)docs/"
  psx_reset
}

@test "conformance us (roast): unreadable --from-file source is fatal, never falls through" {
  # Code-roast MINOR: read_files_from_source's error() exits only the
  # process-substitution SUBSHELL — mapfile saw empty and the flow fell
  # through to the zero-args selector (probed red: gum error AFTER the
  # source error). The failure must stop the command.
  psx_setup
  run hug us --from-file nonexistent.txt
  assert_failure
  assert_output --partial "not a valid file or '-' for stdin"
  refute_output --partial "Interactive mode requires 'gum'" # selector never opened
  refute_output --partial "No files selected"
  psx_reset
}

@test "conformance us (Codex P1): from-commit sources are ROOT-relative, work from a subdir" {
  # Codex P1: extract_files_from_commit yields ROOT-relative paths by
  # construction, but the canonicalization resolved sources against the
  # CWD — from sub/, 'us --from-commit HEAD -- .' wrongly reported
  # "No files matching '.' to unstage." with sub/a.txt still staged
  # (probed red). This is the LEGITIMATE root-relative case: it must
  # UNSTAGE, not error. Source normalization is origin-based.
  psx_setup
  git restore --staged src/a.py
  mkdir sub
  echo a1 > sub/a.txt
  git add sub/a.txt
  git commit -q -m "add sub/a"
  echo a2 >> sub/a.txt
  git add sub/a.txt
  cd sub || return 1
  run hug us --from-commit HEAD -- .
  assert_success
  assert_output --partial "Unstaged 1 file"
  refute_output --partial "No files matching"
  cd "$TEST_REPO" || return 1
  run git diff --cached --name-only
  refute_output --partial "sub/a.txt" # unstaged
  psx_reset
}

@test "conformance us (Codex P2): :(top) scope from a subdir unstages out-of-CWD files" {
  # Codex P2: the CWD-prefix STRIP assumed every match lives under the
  # CWD — a ':(top)root.txt' scope from sub/ matched root.txt (no
  # prefix), left it spelled 'root.txt', and subdir validation read
  # sub/root.txt → false failure (probed red: "No files matching" with
  # root.txt still staged). Matches must convert to REAL cwd-relative
  # paths ('../root.txt' climbs out of the subdir).
  psx_setup
  git restore --staged src/a.py
  mkdir sub
  echo a1 > sub/a.txt
  echo r1 > root.txt
  git add sub/a.txt root.txt
  git commit -q -m "add sub/a + root"
  echo a2 >> sub/a.txt
  echo r2 >> root.txt
  git add sub/a.txt root.txt
  cd sub || return 1
  run hug us --from-commit HEAD -- ':(top)root.txt'
  assert_success
  assert_output --partial "Unstaged 1 file"
  refute_output --partial "No files matching"
  cd "$TEST_REPO" || return 1
  run git diff --cached --name-only
  refute_output --partial "root.txt" # unstaged
  assert_output --partial "sub/a.txt" # out of scope: still staged
  psx_reset
}

@test "conformance us (#302): scope-shaped success names the full scope set" {
  psx_setup
  git add docs/note.md   # + src/a.py, src/b.py already staged via psx_setup
  run hug us -- src/
  assert_success
  assert_output --partial "matching 'src/':"
  psx_reset
}

@test "conformance us (#302): literal file keeps the bare noun (no clause)" {
  psx_setup
  run hug us -- src/a.py
  assert_success
  assert_output --partial "Unstaged 1 file:"
  refute_output --partial "matching"
  psx_reset
}

@test "conformance us (#302): mixed list names the full set (union semantics)" {
  psx_setup
  git add docs/note.md
  run hug us docs/note.md src/
  assert_success
  assert_output --partial "matching 'docs/note.md' 'src/':"
  psx_reset
}

@test "conformance us (#302): dry-run mirrors the clause" {
  psx_setup
  run hug us --dry-run src/
  assert_success
  assert_output --partial "Would unstage"   # exact: "Dry run: Would unstage N file(s) matching 'src/':"
  assert_output --partial "matching 'src/':"
  psx_reset
}

@test "conformance us (#302): -- invariance — clause identical with and without the separator" {
  # Codex #3829676857: the previous draft captured $output but never compared it, so a bare invocation that
  # diverged from the -- form still passed. Compare both outputs (status + first-line clause) so the
  # stated -- -invariance property is actually pinned.
  psx_setup
  run hug us src/
  assert_success
  local bare_out="$output"
  local bare_status="$status"
  assert_output --partial "matching 'src/':"
  psx_reset
  psx_setup
  run hug us -- src/
  assert_success
  assert_equal "$bare_status" "$status"
  assert_equal "$bare_out" "$output"
  psx_reset
}

@test "conformance us (F-005): subdir run keeps root-relative spelling, clause echoes user spelling" {
  psx_setup
  mkdir -p src/deep && echo z > src/deep/z.py && git add src/deep/z.py
  cd src
  run hug us -- deep/
  assert_success
  assert_output --partial "matching 'deep/':"
  assert_output --partial "src/deep/z.py"   # root-relative ✓ line
  cd - >/dev/null
  psx_reset
}

@test "w get: -u treats positionals as files; -u alone runs documented reset-all (Task 8)" {
  # FLIPPED (Task 8, spec §5.2): with `-u` there is NO target positional —
  # every remaining argument is a FILE (BUG-3). Before the fix, `-u <file>`
  # died on the exclusivity guard ("Cannot specify --upstream with a specific
  # commit or integer N.") and `-u` alone on "Missing target argument", even
  # though help documents `hug w get -u` as reset-all.
  #
  # Upstream fixture: `git branch --set-upstream-to=<local>` — @{u} resolves
  # local branches too, so no remote is needed (probed: get_upstream_commit's
  # `git rev-parse --verify @{u}` accepts it). Each cell that needs a working
  # restore also commits the fixture's dirty state so the tree is CLEAN
  # (3-state gate: dirty would refuse, correctly, before any restore).
  local upstream_and_clean_setup='
    git branch up-ref HEAD~1
    git branch --set-upstream-to=up-ref
    git add -A
    git commit -q -m divergence'

  # Cell 1 — `-u <file>` restores that file from upstream (BUG-3 observable).
  psx_setup
  eval "$upstream_and_clean_setup"
  run hug w get -u src/a.py
  assert_success
  assert_output --partial "Files reset to"
  assert_equal "py1" "$(cat src/a.py)" # reverted to upstream (base) version
  psx_reset

  # Cell 2 — `-u 2` restores a file literally named `2`: the old "-u +
  # integer" guard has no subject anymore (the integer regex never runs under
  # -u). A nonexistent path still fails loudly via check_file_in_commit.
  psx_setup
  echo base-2 > 2
  git add -- 2
  git commit -q -m "file named 2 at base"
  git branch up-ref # upstream HAS file 2 with the base content
  echo diverged-2 > 2
  git commit -q -am "diverge file 2"
  git branch --set-upstream-to=up-ref
  # Probed: check_file_in_commit exits 1 with "File '<path>' does not exist
  # in commit <sha>" — backs the claim in the comment above.
  run hug w get -u no-such-file
  assert_failure
  assert_output --partial "does not exist in commit"
  # Review fix (pre-landing): a 1-2 digit arg under -u is now rejected by
  # the restored shape guard (see the next test) — a file literally named
  # `2` is UNREACHABLE under -u, deliberately: `-u 2` is far more likely a
  # mistyped `w get 2` than a file name, and the old flow's only signal was
  # the misleading "File '2' does not exist" when the file happened to be
  # absent. Cell flipped from the Task-8 assert_success accordingly.
  run hug w get -u 2
  assert_failure
  assert_output --partial "Cannot specify --upstream with a specific commit or integer N."
  psx_reset

  # Cell 3 — `-u` alone with NO upstream: get_upstream_commit's loud error
  # (spec §5.2 lists the no-upstream case explicitly). The shared fixture
  # gained an upstream anchor for llu (Task 10), so "no upstream" is now an
  # explicit precondition of this cell, not the fixture default.
  psx_setup
  git branch --unset-upstream
  run hug w get -u
  assert_failure
  assert_output --partial "No upstream branch configured"
  psx_reset

  # Cell 4 — `-u` alone WITH upstream: the documented reset-all runs, preview
  # shows the reset_all_files category shape, and --dry-run changes nothing.
  psx_setup
  eval "$upstream_and_clean_setup"
  run hug w get -u --dry-run
  assert_success
  assert_output --partial "Files that will be MODIFIED:"
  assert_output --partial "src/a.py"
  assert_output --partial "Dry run — no files were modified."
  grep -q py2 src/a.py # unchanged by the dry run
  psx_reset

  # Cell 5 — BUG-4 (flipped by the uniform pathspec contract, #292 PR-C):
  # the restore KEEPS its explicit `--` so dash-leading PATHS stay data,
  # but a pre-'--' dash token is now a LOUD unknown-option error (exit 2),
  # never a silently-accepted file name — reach such files via the
  # separator form. (Was: `w get HEAD~1 -weird` restored directly, and a
  # TYPO'd flag in that slot was indistinguishable from a file name.)
  psx_setup
  echo wbase > ./-weird
  git add -- -weird
  git commit -q -m "add -weird"
  echo wdiverged > ./-weird
  git commit -q -am "diverge -weird"
  run hug w get HEAD~1 -weird
  assert_equal 2 "$status"
  assert_output --partial "Unknown option: -weird"
  run hug w get HEAD~1 -- -weird
  assert_success
  assert_equal "wbase" "$(cat ./-weird)"
  psx_reset

  # Cell 6 — regression: NON-`-u` behavior unchanged. `w get <commit> <file>`
  # on a clean tree still previews the specific-files shape (spec §5.2).
  psx_setup
  git add -A
  git commit -q -m divergence
  run hug w get HEAD~1 --dry-run src/a.py
  assert_success
  assert_output --partial "Files to be reset:"
  assert_output --partial "src/a.py"
  grep -q py2 src/a.py
  psx_reset

  # Cell 7 — review fix (pre-landing): under -u, a remaining arg that LOOKS
  # like a commit (resolves via rev-parse) or an integer N (1-2 digits) is
  # rejected with the OLD explicit message BEFORE anything prints — the
  # confusing "File 'HEAD~5' does not exist" reclassification is gone.
  psx_setup
  git branch up-ref HEAD~1
  git branch --set-upstream-to=up-ref
  run hug w get -u HEAD~1
  assert_failure
  assert_output --partial "Cannot specify --upstream with a specific commit or integer N."
  refute_output --partial "Will reset"
  psx_reset
}

@test "contract sh (Task 11): pathspecs after the ref scope the details (BUG-6 rows flipped)" {
  # Contract (was the Task-9 BUG-6 rejection, flipped by Task 11, #292
  # PR-C): `sh HEAD~1 -- src/` and the bare-positional spelling
  # `sh HEAD~1 src/` are EQUIVALENT and scope the run — ref + details
  # filtered to the path (two-sided: base's src/a.py in, its docs/note.md
  # out). Was: "hug sh accepts one commit reference; unexpected extra
  # argument: 'src/'", exit 1.
  psx_setup
  run hug sh HEAD~1 -- src/
  assert_success
  assert_output --partial "src/a.py"
  refute_output --partial "docs/note.md"
  refute_output --partial "unexpected extra argument"
  psx_reset

  psx_setup
  run hug sh HEAD~1 src/
  assert_success
  assert_output --partial "src/a.py"
  refute_output --partial "docs/note.md"
  refute_output --partial "unexpected extra argument"
  psx_reset
}

@test "contract sh (Task 11): empty first positional defaults to HEAD, path still scopes (BUG-6 review-fix row flipped)" {
  # Contract (was the BUG-6 review-fix rejection, flipped by Task 11): the
  # positional-COUNT guard lesson survives as bookkeeping only — `hug sh ""
  # src/` (realistic: `hug sh "$ref" -- "$path"` with an unset/empty ref)
  # keeps the EMPTY ref (→ HEAD default via resolve_commit_ref) AND
  # collects the path. HEAD here is the docs-only commit, so a src/ scope
  # leaves its stats empty — pinned honestly: subject present, the
  # out-of-scope docs/guide.md absent.
  psx_setup
  run hug sh "" src/
  assert_success
  assert_output --partial "docs guide only"
  refute_output --partial "docs/guide.md"
  refute_output --partial "unexpected extra argument"
  psx_reset

  psx_setup
  run hug sh ""
  assert_success
  assert_output --partial "Commit info"
  psx_reset
}

@test "contract llu (Task 10): loud rejections — unknown flag and malformed magic, exit 2" {
  # Contract (was characterization, flipped by Task 10, #292 PR-C): the old
  # flags-only loop rejected EVERYTHING it did not know with exit 1 — the
  # separator ("Unknown option: --"), typo'd flags AND malformed magic
  # pathspecs indistinguishably. Now: unknown -* → family usage template
  # (exit 2); ':(bogus)' → validate_pathspecs_or_die (exit 2, "Invalid
  # pathspec"), matching the sl* family shape.
  psx_setup
  run hug llu -xX
  assert_equal 2 "$status"
  assert_output --partial "Unknown option: -xX"
  assert_output --partial "hug llu -- -xX"
  psx_reset

  psx_setup
  run hug llu -- ':(bogus)x/'
  assert_equal 2 "$status"
  assert_output --partial "Invalid pathspec"
  psx_reset
}

@test "contract lc/lf/lcr: mid-stream -- preserved and filter applies two-sided (BUG-2 fixed, Task 7)" {
  # Contract (was characterization, flipped by Task 7): `lc py -- src/` (and
  # lcr, and `lf guide -- src/`) exit 0 and filter to src/ commits — now via
  # a PRESERVED separator (parse_common_flags_with_pathspecs splits, the
  # exec sinks re-inject). Two-sided cells discriminate: lc/lcr keep "base";
  # lf's term matches the docs-only commit, which the src/ filter excludes.
  local cmd
  for cmd in lc lcr; do
    psx_setup
    run hug "$cmd" py -- src/
    assert_success
    assert_output --partial "base"
    refute_output --partial "docs guide only"
    psx_reset
  done

  psx_setup
  run hug lf guide -- src/
  assert_success
  refute_output --partial "docs guide only"
  psx_reset
}

@test "contract lc/lf/lcr: branch named like the path no longer hijacks (BUG-2 fixed, Task 7)" {
  # Contract (was characterization, flipped by Task 7): with a BRANCH named
  # `src/a.py`, `lc py -- src/a.py` (same for lf/lcr) now FILTERS (exit 0,
  # src-scoped results) instead of git's "fatal: ambiguous argument"
  # (exit 128) — the re-injected separator lets git disambiguate rev-vs-path.
  local cmd
  for cmd in lc lcr; do
    psx_setup
    git branch 'src/a.py'
    run hug "$cmd" py -- src/a.py
    assert_success
    assert_output --partial "base"
    refute_output --partial "fatal: ambiguous argument"
    psx_reset
  done

  # lf's term matches ONLY the docs-only commit; the src/a.py filter must
  # exclude it — observable: exit 0 with EMPTY results (previously the
  # ambiguous-argument fatal, exit 128).
  psx_setup
  git branch 'src/a.py'
  run hug lf guide -- src/a.py
  assert_success
  refute_output --partial "fatal:"
  refute_output --partial "docs guide only"
  psx_reset

  # Control in the same repo: directory pathspec still filters fine.
  psx_setup
  git branch 'src/a.py'
  run hug lc py -- src/
  assert_success
  assert_output --partial "base"
  psx_reset
}

@test "contract lc/lf --json: pathspec reaches the JSON sink two-sided (BUG-2 fixed, Task 7)" {
  # The JSON sink is the trap this task exists to close: batch_*_search
  # feeds search_args straight to `git log`, so a dropped separator silently
  # unscopes the JSON results (no fatal to notice). --with-files exposes the
  # per-commit file list so the scope is observable INSIDE the JSON.
  local names
  psx_setup
  # Discriminating fixture (probed, review item 3): `git log -S py
  # --numstat` lists ONLY files whose occurrence count of the term changed,
  # so the base fixture alone can never leak docs/note.md — the negative
  # assertion below would be vacuously green. A commit where the docs file
  # ITSELF pickaxe-matches "py" makes it listable; only the src/ pathspec
  # reaching the JSON sink keeps it out of files[]. Scoped to this cell so
  # the shared fixture (and every other row) is unaffected.
  echo py3 >> src/a.py
  echo "see py usage" >> docs/note.md
  git add src/a.py docs/note.md
  git commit -q -m "pickaxe hits src and docs"
  run hug lc --json py --with-files -- src/
  assert_success
  echo "$output" | jq -e . >/dev/null
  names=$(echo "$output" | jq -r '[.data.results[].files[].filename] | join("\n")')
  grep -qF "src/" <<< "$names"
  if grep -qF "docs/note.md" <<< "$names"; then
    fail "out-of-scope file leaked into lc --json results: docs/note.md"
  fi
  psx_reset

  # lf discrimination: the term matches the docs-only commit, the src/
  # filter must leave ZERO results (count lives in the metadata envelope).
  psx_setup
  run hug lf --json guide --with-files -- src/
  assert_success
  echo "$output" | jq -e . >/dev/null
  [[ "$(echo "$output" | jq '.data.results | length')" == "0" ]]
  [[ "$(echo "$output" | jq '.data.search.results_count')" == "0" ]]
  psx_reset
}

@test "contract lc/lcr: scoped picker — 'py -- src/ --' restricts candidates (Task 7)" {
  # Trailing bare '--' after a pathspec opens the picker SCOPED to that
  # pathspec (helper --picker mode + select_files_with_status pathspecs).
  # Stub gum cancels after capturing candidates (same harness as the
  # picker-rows column). lcr shares the picker code path; lf omitted to
  # keep the cell cheap (identical select_opts construction).
  local cmd candidates
  for cmd in lc lcr; do
    psx_setup
    psx_install_stub_gum
    run hug "$cmd" py -- src/ --
    assert_success
    assert_output --partial "Cancelled."
    candidates=$(sed $'s/\033\\[[0-9;]*m//g' "$GUM_CANDIDATES_FILE")
    [[ -n "$candidates" ]]
    grep -qF "src/" <<< "$candidates"
    if grep -qF "docs/note.md" <<< "$candidates"; then
      fail "out-of-scope candidate leaked into $cmd picker: docs/note.md"
    fi
    psx_reset
  done
}

@test "contract ll/lc/llf: post-'--' bare numbers stay pathspecs, never HEAD~N (review conf 9)" {
  # Review fix (pre-landing, conf 9 — verified repro): git-ll's arg loop
  # used to resolve bare numbers as HEAD~N revisions EVEN AFTER the '--'
  # separator, so the synthesized '-1 HEAD~N' tokens landed post-separator
  # as bogus pathspecs. Probed red in the fixture shape below:
  #   hug lc needle -- 5    → silently EMPTY (pathspecs '-1' and 'HEAD~5')
  #   hug ll -S needle -- 5 → same silent empty
  #   hug llf 5             → 'fatal: --follow requires exactly one
  #                           pathspec' (exit 128) — llf execs ll with
  #                           '--follow -- 5' and ll mangled the 5
  # Post-'--' tokens are pathspecs by git's own grammar: append verbatim.
  # Fixture: a tracked file literally named 5 whose adding commit is the
  # ONLY pickaxe hit for 'needle' (two-sided: present + exit 0).
  psx_setup
  echo needle > 5
  git add -- 5
  git commit -q -m "add file five"

  run hug lc needle -- 5
  assert_success
  assert_output --partial "add file five"
  refute_output --partial "fatal:"
  psx_reset

  psx_setup
  echo needle > 5
  git add -- 5
  git commit -q -m "add file five"
  run hug ll -S needle -- 5
  assert_success
  assert_output --partial "add file five"
  refute_output --partial "fatal:"
  psx_reset

  # llf 5: --follow gets exactly one pathspec → the commit that added the
  # file named 5 IS shown (probed observable: log1 line "add file five").
  psx_setup
  echo needle > 5
  git add -- 5
  git commit -q -m "add file five"
  run hug llf 5
  assert_success
  assert_output --partial "add file five"
  refute_output --partial "--follow requires exactly one pathspec"
  psx_reset
}

@test "contract sw: picker forwarding shields pathspecs named like options (review conf 6)" {
  # Review fix (pre-landing, conf 6 — verified repro): the four picker-
  # forwarding sites (hug-git-diff, lc, lf, lcr) appended the user's
  # pathspecs to select_opts RAW, so a pathspec literally named like a
  # picker option was eaten as an OPTION. Probed red with a staged file
  # named '--staged' and `hug sw -- --staged --`: candidates were
  #   S:Add --staged / S:Mod src/a.py / U:Mod docs/note.md
  # — the requested scope was silently discarded and out-of-scope files
  # leaked in. The sites now append the protective '--' first;
  # select_files_with_status's dedicated separator arm (which exists for
  # exactly this, per its own comment) drains the pathspecs verbatim.
  # One cell proves the round trip (sw carries the shared driver; lc/lf/
  # lcr share the identical select_opts construction).
  psx_setup
  echo x > ./--staged
  git add -- --staged # staged: sw's combined (staged+unstaged) mode lists it
  psx_install_stub_gum
  run hug sw -- --staged --
  assert_success
  local candidates
  candidates=$(sed $'s/\033\\[[0-9;]*m//g' "$GUM_CANDIDATES_FILE")
  grep -qF -- "--staged" <<< "$candidates"
  if grep -qF "src/a.py" <<< "$candidates" || grep -qF "docs/note.md" <<< "$candidates"; then
    fail "out-of-scope candidate leaked into sw picker: pathspec '--staged' was eaten as an option"
  fi
  psx_reset
}

@test "single-file cardinality: two files → hug rejection, not git fatal (Task 10)" {
  # FLIPPED (Task 10, spec §3.2/§5.6): these commands used to pass BOTH
  # paths straight to git, which fataled (exit 128) with "--follow requires
  # exactly one pathspec" (fa, fborn, fcon) or "bad revision" (fb, fblame,
  # llf). They now enforce the one-file contract themselves with hug's own
  # clear, command-naming error (exit 2 — flipped from 1 by the code-roast
  # round: reject_multiple_files now uses error_usage, the family code).
  for cmd in "${PATHSPEC_SINGLEFILE_ROWS[@]}"; do
    psx_setup
    run hug "$cmd" src/a.py docs/note.md
    assert_equal 2 "$status"
    assert_output --partial "hug $cmd accepts only one file (got 2 files)."
    refute_output --partial "fatal:"
    psx_reset
  done
}

@test "single-file cardinality: llf keeps flags flowing after the file (Task 10)" {
  # llf documents `hug llf <file> -N [log options]` — the cardinality guard
  # must count only additional NON-FLAG positionals, so flags after the
  # file keep flowing to the log backend. src/a.py's last touching commit
  # is "base", so that subject must appear (proves the log actually ran
  # rather than the guard eating a valid invocation).
  psx_setup
  run hug llf src/a.py -1
  assert_success
  assert_output --partial "base"
  psx_reset

  # Value-taking log flags are the sharp edge: `-S <term>`, `--author <name>`
  # etc. take their value as a SEPARATE word, and that value token is
  # indistinguishable from a file name by shape alone. The guard must cut at
  # the FIRST flag: everything after it is opaque log-backend args. src/a.py
  # gained "py1" in "base", so -S py1 must still surface that commit.
  psx_setup
  run hug llf src/a.py -S py1
  assert_success
  assert_output --partial "base"
  psx_reset

  psx_setup
  run hug llf src/a.py --author nobody
  assert_success
  psx_reset

  # ...while a second FILE — flag before or after — still rejects.
  psx_setup
  run hug llf src/a.py docs/note.md -1
  assert_equal 2 "$status"
  assert_output --partial "hug llf accepts only one file (got 2 files)."
  psx_reset
}

@test "single-file cardinality: llfp/llfs post-flag extras fall through to git (Task 10 boundary)" {
  # llfp/llfs delegate via `exec hug llf "$file" -p|--stat "$@"` — no direct
  # guard of their own. The delegation inserts the flag BETWEEN file and
  # remaining args, so `hug llfp a b` reaches llf as `a -p b` — and since the
  # llf guard cuts at the FIRST flag (flag VALUES like `-S py`'s term are
  # shape-identical to files; see the llf boundary test above), b is post-flag
  # and flows to git log, which fataled with "bad revision" (probed, exit 128)
  # exactly as it did before the Task 10 guard. Accepted trade-off: the
  # delegate could only keep its clean rejection by counting post-flag
  # positionals — the very thing that broke `hug llf <file> -S <term>`.
  local cmd
  for cmd in "${PATHSPEC_SINGLEFILE_DELEGATE_ROWS[@]}"; do
    psx_setup
    run hug "$cmd" src/a.py docs/note.md
    assert_equal 128 "$status"
    assert_output --partial "fatal:"
    psx_reset
  done
}

@test "single-file cardinality: h steps rejects extra files (Task 10)" {
  # FLIPPED (Task 10): git-h-steps used to keep the FIRST positional only
  # (silent ignore of the second). Now two files → exit 1 + rejection
  # naming the command exactly as invoked.
  psx_setup
  run hug h steps src/a.py docs/note.md
  assert_equal 2 "$status"
  assert_output --partial "hug h steps accepts only one file (got 2 files)."
  psx_reset
}

@test "single-file cardinality: stats file rejects extra files (Task 10)" {
  # FLIPPED (Task 10): `hug stats file a b` used to churn-analyze ONLY a;
  # the extras vanished without a word. Now two files → exit 1 + rejection.
  psx_setup
  run hug stats file src/a.py docs/note.md
  assert_equal 2 "$status"
  assert_output --partial "hug stats file accepts only one file (got 2 files)."
  refute_output --partial "Churn analysis"
  psx_reset
}

@test "single-file cardinality: stats file trailing flag not counted (Task 10/#302)" {
  # #302 overcount: stats-file's own-loop *) arm collects unknown -* tokens
  # into remaining_args; 'hug stats file a b --bogus' tallied 3. The slice fixes it.
  # FLIPPED again (#310 adversarial F3): the unknown -* token is now a LOUD
  # usage error (exit 2, same family contract as fa/fb/fborn/fcon/fblame) —
  # the tally never sees it at all.
  psx_setup
  run hug stats file src/a.py docs/note.md --bogus
  assert_equal 2 "$status"
  assert_output --partial "Unknown option: --bogus"
  refute_output --partial "accepts only one file"
  psx_reset

  # Two real files still hit the truthful cardinality guard.
  psx_setup
  run hug stats file src/a.py docs/note.md
  assert_equal 2 "$status"
  assert_output --partial "hug stats file accepts only one file (got 2 files)."
  psx_reset
}

@test "single-file cardinality: fblame churn mode is guarded too (combo gap, #298 Task 3c)" {
  # fblame's guard sits BEFORE the churn/blame fork (#292), so --churn must
  # not open a bypass: two files under --churn → the same hug rejection the
  # blame mode gets (NOT churn.py silently analyzing only the first file).
  psx_setup
  run hug fblame --churn src/a.py docs/note.md
  assert_equal 2 "$status"
  assert_output --partial "hug fblame accepts only one file (got 2 files)."
  refute_output --partial "Churn analysis"
  psx_reset

  # One file under --churn keeps working: the Python churn backend runs and
  # names the file (proves the guard did not over-reject the valid form).
  psx_setup
  run hug fblame --churn src/a.py
  assert_success
  assert_output --partial "src/a.py"
  psx_reset
}

@test "single-file cardinality: llf trailing flag not counted in the reject tally (Task 10/#302)" {
  # #302 overcount: 'hug llf a b -1' used to pass "$file" "$@" to
  # reject_multiple_files, tallying the -1 flag as a 3rd "file". The slice
  # (collect_positional_args_before_flags) makes the tally files-only.
  psx_setup
  run hug llf src/a.py docs/note.md -1
  assert_equal 2 "$status"
  assert_output --partial "hug llf accepts only one file (got 2 files)."
  refute_output --partial "got 3 files"
  psx_reset
}

@test "single-file cardinality: h steps trailing unknown flag is a loud error, not a false single-file count (#302)" {
  # #302 C-004, codex #3829676849: h-steps's own-loop *) arm collects unknown
  # -* tokens into extra_files (parse_common_flags passes them through), so
  # 'hug h steps a --bogus' used to miscount the flag as a file and fire the
  # cardinality guard. Filtering it from the tally alone would have converted a
  # typo into silent success. The fix is loud: unknown -* after the file is a
  # usage error (path-command contract, exit 2). --raw is consumed by its own
  # arm and is exempted.
  psx_setup
  run hug h steps src/a.py --bogus
  assert_equal 2 "$status"
  assert_output --partial "Unknown option: --bogus"
  refute_output --partial "accepts only one file"
  psx_reset
}

@test "single-file cardinality: h steps dash-leading file via -- is NOT rejected as unknown flag (#302 codex #3830105470)" {
  # Conformance pin: hug h steps -- -foo.txt creates _pathspec_pathspecs[-foo.txt]
  # via parse_common_flags_with_pathspecs — the separator-protected file is
  # pathspec data, not an "unknown option". Must NOT be rejected.
  # (Roast round on #310 dropped the trailing '--raw' this pin used to carry:
  # post-'--' tokens are DATA by the uniform pathspec contract, so
  # 'h steps -- -foo.txt --raw' is TWO file candidates and rejects with the
  # cardinality message — pinned by the row below.)
  psx_setup
  echo pin > ./-foo.txt
  git add -- ./-foo.txt
  git commit -q -m "file literally named -foo.txt"
  run hug h steps -- -foo.txt
  assert_success
  refute_output --partial "Unknown option"
  psx_reset
}

@test "single-file cardinality: h steps treats ALL post-'--' tokens as data — flag-shaped second candidate hits the cardinality guard (#310 F-002)" {
  # Roast F-002/C-001/C-002: the first draft exempted only the FIRST
  # separator-protected token from the unknown-flag check, so both
  # 'h steps -- -foo.txt -bar.txt' and 'h steps -- README.md --bogus' died
  # with "Unknown option" exit 2 even though every post-'--' token is data by
  # the uniform pathspec contract (#292: the separator changes delivery, never
  # meaning). The truthful answer is the cardinality reject: two candidates,
  # one slot.
  psx_setup
  echo pin > ./-foo.txt
  git add -- ./-foo.txt
  run hug h steps -- -foo.txt -bar.txt
  assert_equal 2 "$status"
  assert_output --partial "hug h steps accepts only one file (got 2 files)."
  refute_output --partial "Unknown option"
  psx_reset

  psx_setup
  run hug h steps -- README.md --bogus
  assert_equal 2 "$status"
  assert_output --partial "hug h steps accepts only one file (got 2 files)."
  refute_output --partial "Unknown option"
  psx_reset
}

@test "single-file cardinality: f-family unknown option is loud, not counted as a file (#310 #3834674457)" {
  # The counted message made latent overcounts observable — and exposed that
  # fa/fb/fborn/fcon (raw "$@") and fblame (catch-all *) arm) tallied unknown
  # -* tokens as FILES: 'hug fa src/a.py --bogus' claimed "got 2 files" for
  # one file + one typo. Loud reject per the path-command contract; the
  # truthful count stays correct for genuinely-file-only collections.
  for cmd in fa fb fborn fcon; do
    psx_setup
    run hug "$cmd" src/a.py --bogus
    assert_equal 2 "$status"
    assert_output --partial "Unknown option: --bogus"
    refute_output --partial "got 2 files"
    psx_reset
  done

  psx_setup
  run hug fblame --churn src/a.py --bogus
  assert_equal 2 "$status"
  assert_output --partial "Unknown option: --bogus"
  refute_output --partial "got 2 files"
  psx_reset
}

@test "single-file cardinality: f-family separator data reaches the truthful guard (#310 #3834674457)" {
  # Post-'--' tokens are DATA by contract: a second dash-named candidate via
  # '--' must hit the cardinality message (truthful tally), never an option-
  # parse complaint; a single dash-named file must still analyze.
  # Parameterized over all four copied guard blocks (ship review: a
  # copy-paste divergence in one of them previously stayed green).
  # BARE '-name' spelling (no ./): adversarial F2 — the first cut ran the
  # unknown-option check post-merge and rejected exactly this shape while
  # the './-name' fixtures sailed through, keeping CI green.
  # Empty-string positionals are usage errors (adversarial F1: 'fa "" extra'
  # silently analyzed nothing with exit 0).
  for cmd in fa fb fborn fcon; do
    psx_setup
    run hug "$cmd" -- -foo.txt -bar.txt
    assert_equal 2 "$status"
    assert_output --partial "hug $cmd accepts only one file (got 2 files)."
    refute_output --partial "Unknown option"
    psx_reset

    psx_setup
    echo pin > ./-baz.txt
    git add -- ./-baz.txt
    run hug "$cmd" -- -baz.txt
    assert_success
    refute_output --partial "Unknown option"
    psx_reset

    psx_setup
    run hug "$cmd" "" extra
    assert_equal 2 "$status"
    assert_output --partial "Empty file argument."
    psx_reset
  done
}

@test "single-file cardinality: fblame separator data reaches the truthful guard; lone dash is a filename (#310 ship review)" {
  # fblame's own-loop gained '--)' (drain) and ')' (lone dash = filename
  # candidate) arms; without these pins a revert of either arm stays green.
  psx_setup
  echo pin > ./-baz.txt
  git add -- ./-baz.txt
  run hug fblame -- ./-baz.txt
  assert_success
  refute_output --partial "Unknown option"
  psx_reset

  psx_setup
  run hug fblame -- ./-foo.txt ./-bar.txt
  assert_equal 2 "$status"
  assert_output --partial "hug fblame accepts only one file (got 2 files)."
  refute_output --partial "Unknown option"
  psx_reset

  psx_setup
  echo lone > ./-
  git add -- ./-
  run hug fblame ./-
  assert_success
  refute_output --partial "Unknown option"
  psx_reset
}

@test "single-file cardinality: h steps browse-root still excludes explicit paths post-split (#310 #3834674453)" {
  # Regression pin: the pathspec split hid post-'--' paths from
  # parse_common_flags' --browse-root exclusion, so 'h steps --browse-root --
  # src/a.py' analyzed the file with the flag silently ignored (main rejects
  # this loudly; probed both sides). The command-level check must see the
  # separator data too.
  psx_setup
  run hug h steps --browse-root -- src/a.py
  assert_equal 1 "$status"
  assert_output --partial "--browse-root cannot be used with explicit paths."
  refute_output --partial "steps back from HEAD"
  psx_reset
}

@test "contract h steps: bare '--' routes to the picker (gum disabled → help fallback, exit 1)" {
  # Probed: a trailing bare '--' contributes NO file candidate, so the
  # zero-file arm fires — with gum available that is the interactive picker;
  # with HUG_DISABLE_GUM it degrades to show_help on stdout + exit 1 (never
  # an attempt to analyze a file literally named '--').
  # HUG_DISABLE_GUM, NOT a `command -v gum` skip: test_helper.bash exports
  # HUG_TEST_MODE=true, which makes gum_available() succeed even with no gum
  # binary (hug-gum:22-24) — under a skip guard this row would enter the
  # picker and treat the failed invocation as cancellation (exit 0).
  psx_setup
  export HUG_DISABLE_GUM=true
  run hug h steps --
  assert_equal 1 "$status"; assert_output --partial "hug h steps: Show commit steps"
  psx_reset
}

@test "single-file cardinality: f-family browse-root still excludes explicit paths post-split (#310 ship review)" {
  # Same regression class as the h-steps pin above, found by the coverage
  # audit when fa/fb/fborn/fcon adopted the split WITHOUT the backstop:
  # 'fa --browse-root -- src/a.py' silently analyzed where main rejected
  # exit 1 (probed both sides before fixing).
  for cmd in fa fb fborn fcon; do
    psx_setup
    run hug "$cmd" --browse-root -- src/a.py
    assert_equal 1 "$status"
    assert_output --partial "--browse-root cannot be used with explicit paths."
    refute_output --partial "tester"   # no analysis output leaks
    psx_reset
  done
}

@test "conformance us (#310 #3834674455): short-form magic pathspecs name the scope clause" {
  # Git accepts ':!path' / ':^path' exclusion spellings; the classifier only
  # knew '(' magic, so the dry-run/success clause went missing while git
  # still scoped by the spec. ':<digit>' is a stage number, NOT magic.
  psx_setup
  run hug us --dry-run -- ':!docs/note.md'
  assert_success
  assert_output --partial "matching ':!docs/note.md':"
  psx_reset

  psx_setup
  run hug us --dry-run -- ':^docs/note.md'
  assert_success
  assert_output --partial "matching ':^docs/note.md':"
  psx_reset
}

@test "conformance us (#310 ship review): glob and bracket pathspecs classify as scope" {
  # is_scope_shaped's wildcard arms ('*', '?', '[') had no pin exercising
  # them — a misclassification regression (clause silently missing, noun
  # wrong on the error path) stayed green. One clause-level pin per arm
  # class; the error-path noun rides the same classifier.
  psx_setup
  run hug us --dry-run -- 'src/*.py'
  assert_success
  assert_output --partial "matching 'src/*.py':"
  psx_reset

  psx_setup
  # 'src/??.py' matches nothing staged → the scoped-empty gate answers the
  # no-match message; the CLASSIFIER assertion is that the scope spelling is
  # echoed verbatim (a misclassification as a literal file would instead
  # produce "File 'src/??.py' is not staged." exit 1).
  run hug us --dry-run -- 'src/??.py'
  assert_success
  assert_output --partial "'src/??.py'"
  refute_output --partial "is not staged"
  psx_reset

  psx_setup
  # 'src/[ab].py' DOES match the fixture (a.py) — full clause assertion.
  run hug us --dry-run -- 'src/[ab].py'
  assert_success
  assert_output --partial "matching 'src/[ab].py':"
  psx_reset
}

@test "single-file cardinality: stats file unknown option is loud; separator data analyzes (#310 adversarial F3)" {
  # The slice silently swallowed unknown flags ('stats file star1.txt
  # --bogus' analyzed with exit 0); its own loop now rejects -* loudly and
  # drains post-'--' tokens as data (was: "File not found: --").
  # star1.txt lives at repo ROOT — the fixture seeds src/ and docs/ only,
  # so a src/-relative spelling would be "File not found".
  psx_setup
  run hug stats file star1.txt --bogus
  assert_equal 2 "$status"
  assert_output --partial "Unknown option: --bogus"
  refute_output --partial "Churn analysis"
  psx_reset

  psx_setup
  run hug stats file -- other.txt
  assert_success
  assert_output --partial "Churn analysis for: other.txt"
  psx_reset
}

@test "contract stats file: bare '--' routes to the picker (gum disabled → clean error)" {
  # Probed: a trailing bare '--' strips to zero args, which the '--' arm
  # routes to the zero-args picker path — with gum disabled that lands in
  # the same "File argument required." usage error as a bare 'stats file'.
  # HUG_DISABLE_GUM, NOT a `command -v gum` skip: test_helper.bash exports
  # HUG_TEST_MODE=true, which makes gum_available() succeed even with no gum
  # binary (hug-gum:22-24) — under a skip guard this row would enter the
  # picker and treat the failed invocation as cancellation.
  psx_setup
  export HUG_DISABLE_GUM=true
  run hug stats file --
  assert_equal 1 "$status"; assert_output --partial "File argument required"
  psx_reset
}

# =============================================================================
# CHARACTERIZATION ROWS (closing fix, whole-implementation review) — the 8
# audit-matrix rows the suite was missing (spec §4: ALL matrix rows must have
# a row): shv, dd, fcat, a, w discard, w purge, w wipe, w zap.
#
# Same rules as the Task 4 rows: every cell pins PROBED behavior (probes ran
# in a scratch copy of this file's fixture); flip targets named per cell.
# Destructive commands are characterized ONLY through --dry-run / arg-surface
# invocations — no real destructive op ever runs against the fixture.
#
# dd/shv argv cells invoke git-dd/git-shv DIRECTLY (not via the hug
# dispatcher): `hug` execs `git dd …`, and git prepends its own exec-path to
# PATH when spawning the dashed external — the inner `git difftool` then
# resolves git-core's git, bypassing the PATH shim (probed; same harness
# reason test_shv.bats/test_dd.bats call the scripts directly).
# =============================================================================

@test "characterization shv: -- <path> forwarded verbatim; scoped-empty → no launch" {
  # characterization: shv's hand-rolled `--` split is PROPER (audit row) —
  # probed: difftool argv carries the resolved endpoints AND the pathspecs
  # verbatim. HEAD~1 is "base" (introduced src/); two-sided via
  # refute_shim_logged_exact "docs/" (a dropped separator would show the
  # unscoped diff... and a swallowed pathspec would omit the src/ line).
  psx_setup
  configure_fake_difftool "$PWD"
  setup_git_shim
  run git-shv HEAD~1 -- src/
  assert_success
  assert_shim_logged_exact "HEAD~1"
  assert_shim_logged_exact "--"
  assert_shim_logged_exact "src/"
  refute_shim_logged_exact "docs/"
  psx_reset

  # Scoped-empty: HEAD is "docs guide only" — no src changes → the
  # no-changes guard fires and the tool is NEVER invoked (probed).
  psx_setup
  configure_fake_difftool "$PWD"
  run git-shv HEAD -- src/
  assert_success
  assert_output --partial "No changes introduced"
  assert_fake_tool_not_invoked
  psx_reset
}

@test "characterization shv: second token rejected loudly; -xX → usage; --help → man routing" {
  # characterization: probed — `shv HEAD src/` (no separator) names the stray
  # token (exit 1); `-xX` hits reject_flag_ref's usage banner (exit 2, same
  # profile as shc/shcp/shp); `--help` via the dispatcher never reaches the
  # script (git man routing, exit 16 — the suite-wide characterization).
  psx_setup
  run hug shv HEAD src/
  assert_failure
  assert_output --partial "takes a single commit/range"
  assert_output --partial "src/"
  psx_reset

  psx_setup
  run hug shv -xX
  assert_equal 2 "$status"
  assert_output --partial "USAGE:"
  psx_reset

  psx_setup
  run hug shv --help
  # Exact-16 only where man(1) exists (review fix — see sl-family note).
  assert_failure
  refute_output --partial "USAGE:"
  if command -v man >/dev/null 2>&1; then
    assert_equal 16 "$status"
  fi
  psx_reset
}

@test "contract shv: flag-classification guard kills silent consumption" {
  # #311 spec §2: the shared parser's GNU getopt would CONSUME -q/-f/-y/
  # --dry-run/--browse-root (and combined shorts like -fq) and silently
  # launch a difftool on HEAD — the guard routes every flag-shaped pre-'--'
  # token through reject_flag_ref instead (USAGE banner + exit 2, the same
  # profile today's engine rejection gives `shv -xX`).
  psx_setup
  run hug shv -q
  assert_equal 2 "$status"
  assert_output --partial "USAGE:"
  assert_output --partial "Unknown flag: -q"
  run hug shv -fq
  assert_equal 2 "$status"
  assert_output --partial "Unknown flag: -fq"
  # DELIBERATE FLIP (#311 spec §2, the ONE authorized observable change):
  # a flag AFTER the positional used to die as a second bare token (exit 1
  # `Unexpected: '-q'`); the position-independent guard converges it to the
  # exit-2 flag-naming family.
  run hug shv 3 -q
  assert_equal 2 "$status"
  assert_output --partial "Unknown flag: -q"
  # SECOND deliberate flip, pinned per spec §2 ("either current error is
  # acceptable; the row pins whichever ships"): `--browse-root 3` used to die
  # as `Unexpected: '3'` exit 1; the guard rejects `--browse-root` itself.
  run hug shv --browse-root 3
  assert_equal 2 "$status"
  assert_output --partial "USAGE:"
  assert_output --partial "Unknown flag: --browse-root"
  # `--browse-root` alone already died in reject_flag_ref today — unchanged.
  run hug shv --browse-root
  assert_equal 2 "$status"
  assert_output --partial "Unknown flag: --browse-root"
  # Micro-flip (Task 2 quality review): 'shv -h -q' used to reach the eval's
  # -h arm and exit 0 with help; the position-independent guard now rejects
  # -q FIRST (banner, then exit 2) — help cannot shadow a sibling flag error.
  run hug shv -h -q
  assert_equal 2 "$status"
  assert_output --partial "USAGE:"
  assert_output --partial "Unknown flag: -q"
  psx_reset
}

@test "contract shv: long-digit range data passes the guard to the engine" {
  # reject_flag_ref exempts ^-[0-9]+$ at ANY length, so -1234 is range DATA:
  # it clears the guard, survives getopt's unknown-option fallback, reaches
  # dd_commit_diff and dies THERE — probed today: exit 1 `Not a valid
  # commit: '-1234'.` (the N convention caps at 3 digits; 1234 back does not
  # resolve). The row pins that exact today-observable.
  psx_setup
  run hug shv -1234
  assert_equal 1 "$status"
  assert_output --partial "Not a valid commit: '-1234'."
  psx_reset
}

@test "characterization dd: -- <path> forwarded verbatim (ref, mode, bare forms)" {
  # characterization: dd_dispatch's manual split is PROPER — probed argv:
  #   dd HEAD~1 -- src/ → <empty-tree> HEAD~1 -- src/
  #   dd s -- src/      → --cached -- src/
  #   dd -- src/        → HEAD -- src/   (bare defaults to working mode)
  psx_setup
  configure_fake_difftool "$PWD"
  setup_git_shim
  run git-dd HEAD~1 -- src/
  assert_success
  assert_shim_logged_exact "HEAD~1"
  assert_shim_logged_exact "--"
  assert_shim_logged_exact "src/"
  refute_shim_logged_exact "docs/"
  psx_reset

  psx_setup
  configure_fake_difftool "$PWD"
  setup_git_shim
  run git-dd s -- src/
  assert_success
  assert_shim_logged_exact "--cached"
  assert_shim_logged_exact "src/"
  psx_reset

  psx_setup
  configure_fake_difftool "$PWD"
  setup_git_shim
  run git-dd -- src/
  assert_success
  assert_shim_logged_exact "HEAD"
  assert_shim_logged_exact "src/"
  refute_shim_logged_exact "--cached"
  psx_reset
}

@test "characterization dd: unknown flag → usage banner; --help → man routing" {
  # characterization: probed — `-xX` is rejected as a flag-ref (exit 2 +
  # dd's usage banner, NOT a silent "no ref" launch); `--help` via the
  # dispatcher hits git man routing (exit 16) like every other row.
  psx_setup
  run hug dd -xX
  assert_equal 2 "$status"
  assert_output --partial "USAGE:"
  psx_reset

  psx_setup
  run hug dd --help
  # Exact-16 only where man(1) exists (review fix — see sl-family note).
  assert_failure
  refute_output --partial "USAGE:"
  if command -v man >/dev/null 2>&1; then
    assert_equal 16 "$status"
  fi
  psx_reset
}

@test "characterization fcat: <commit> <path> works; '-- ' form equivalent" {
  # characterization: fcat's DOCUMENTED interface is two positionals
  # (audit "TARGET+PATH" = the internal `git show commit:path`, not CLI
  # colon syntax). Probed: `fcat HEAD src/a.py` prints HEAD's content (py1);
  # the `--` separator form is equivalent (parse_common_flags consumes it).
  psx_setup
  run hug fcat HEAD src/a.py
  assert_success
  assert_output "py1"
  psx_reset

  psx_setup
  run hug fcat HEAD -- src/a.py
  assert_success
  assert_output "py1"
  psx_reset
}

@test "contract fcat: colon syntax rejected; unknown flag dies as usage error" {
  # contract (flipped from characterization, #311): `fcat HEAD:src/a.py`
  # (single colon-arg) is NOT the CLI form — the target slot consumes it,
  # zero file candidates remain, and the loud usage error is now
  # "File argument required" (was "Missing arguments"). `-xX` is rejected
  # by parse_scoped_own_flags arm 2 as a usage error exit 2 with the
  # flag-naming template (was: collected as the target, dying in ref
  # resolution exit 1 — loud but not flag-naming).
  psx_setup
  run hug fcat HEAD:src/a.py
  assert_equal 1 "$status"
  assert_output --partial "File argument required"
  psx_reset

  psx_setup
  run hug fcat -xX src/a.py
  assert_equal 2 "$status"
  assert_output --partial "Unknown option: -xX"
  psx_reset
}

@test "contract fcat: bare and target-only → loud usage errors" {
  psx_setup
  run hug fcat
  assert_equal 1 "$status"; assert_output --partial "Missing target"
  run hug fcat 3
  assert_equal 1 "$status"; assert_output --partial "File argument required"
  run hug fcat --
  assert_equal 1 "$status"; assert_output --partial "Missing target"
  psx_reset
}

@test "contract fcat: cardinality — two candidates exit 2, either side of '--'" {
  psx_setup
  run hug fcat 1 src/a.py docs/note.md
  assert_equal 2 "$status"; assert_output --partial "accepts only one file"
  run hug fcat 1 -- src/a.py docs/note.md
  assert_equal 2 "$status"; assert_output --partial "accepts only one file"
  psx_reset
}

@test "contract fcat: picker arm — gum disabled → clean error; empty arg → file required" {
  psx_setup
  # HUG_DISABLE_GUM, NOT a `command -v gum` skip: test_helper.bash exports
  # HUG_TEST_MODE=true, which makes gum_available() succeed even with no gum
  # binary (hug-gum:27-28) — under a skip guard this row would enter the
  # picker and treat the failed invocation as cancellation (exit 0).
  export HUG_DISABLE_GUM=true
  run hug fcat 3 --
  assert_equal 1 "$status"; assert_output --partial "File argument required"
  run hug fcat 3 -- ''
  assert_equal 1 "$status"; assert_output --partial "File argument required"
  psx_reset
}

@test "contract fcat: picker + no gum + single candidate degrades to the datum" {
  # Task 1 quality review: 'fcat HEAD src/a.py --' scopes the picker to the
  # pathspec (the row above), and when gum is unavailable the single-candidate
  # picker DEGRADES to using the candidate outright — user intent (that file,
  # that version) is fully satisfied without the UI, so content flows and the
  # exit is 0. Probed: prints the file's HEAD content ('py1').
  # HEAD arm, NOT N: the fixture's src/a.py has one commit, so any N>=1 dies
  # earlier in get_commit_n_back ("Could not find N commits in the history").
  psx_setup
  export HUG_DISABLE_GUM=true
  run hug fcat HEAD src/a.py --
  assert_equal 0 "$status"; assert_output --partial "py1"
  psx_reset
}

@test "contract fcat: range rejection unchanged; post-'--' flag spelling exits 2" {
  psx_setup
  run hug fcat -3 src/a.py
  assert_equal 1 "$status"; assert_output --partial "Ranges are not supported"
  run hug fcat 3 -- -q
  assert_equal 2 "$status"; assert_output --partial "Flags must precede '--'"
  psx_reset
}

@test "contract fcat: quoted glob stays literal; --browse-root compositions" {
  psx_setup
  # HEAD (commit arm), not N: with N the resolution order dies earlier in
  # get_commit_n_back ("Could not find N commits in the history of") before
  # check_file_in_commit ever sees the literal path — the commit arm is the
  # one that proves the glob stays a LITERAL file path end-to-end (spec §1a
  # Glob note).
  run hug fcat HEAD -- 'src/*.py'
  assert_equal 1 "$status"; assert_output --partial "does not exist"
  run hug fcat --browse-root 3
  assert_equal 1 "$status"   # parse_common_flags explicit-paths error
  run hug fcat --browse-root
  assert_equal 1 "$status"; assert_output --partial "Missing target"
  run hug fcat --browse-root --
  assert_equal 1 "$status"; assert_output --partial "Missing target"
  psx_reset
}

@test "contract fcat: 'fcat <N> <path> --' scopes the picker to the path" {
  psx_setup
  # psx_install_stub_gum (bats:573), NOT an argv-recording shim: candidates
  # reach `gum filter` on STDIN — argv carries only filter options, so an
  # argv capture can never see the pathspec. The stub records stdin to
  # $GUM_CANDIDATES_FILE and exits 1 (cancelling picker).
  psx_install_stub_gum
  run hug fcat 1 src/a.py --
  assert_success
  assert_output --partial "No file selected or cancelled"
  # Strip ANSI status coloring before matching (suite pattern).
  candidates=$(sed $'s/\033\\[[0-9;]*m//g' "$GUM_CANDIDATES_FILE")
  grep -qF "src/a.py" <<< "$candidates"
  if grep -qF "docs/note.md" <<< "$candidates"; then
    fail "out-of-scope candidate leaked into picker: docs/note.md"
  fi
  psx_reset
}

@test "contract fcat: dash-leading filename is literal data via '--' (datum arm)" {
  # spec §1a: `fcat <N|commit> -- -weird.txt` — the separator keeps a
  # dash-leading filename DATA (vs. the pre-'--' spelling, which arm 2
  # rejects as an unknown option). psx_setup has no dash-named file, so
  # create one in-test (the `w get` datum-row pattern, bats:1663-1676):
  # `git add --` is MANDATORY — a bare `git add ./-weird.txt` would parse
  # the filename as a flag. HEAD (commit arm): an N target would need a
  # second file-specific commit before N=1 resolves.
  psx_setup
  echo weird1 > ./-weird.txt
  git add -- -weird.txt
  git commit -q -m "add -weird.txt"
  run hug fcat HEAD -- -weird.txt
  assert_success
  assert_output "weird1"
  psx_reset
}

@test "characterization a: positional pathspec stages exactly that file" {
  # characterization: the POSITIVE arm — probed: `hug a new.txt` stages only
  # new.txt ("Staged 1 file"; porcelain shows `A`), docs/note.md untouched.
  psx_setup
  run hug a new.txt
  assert_success
  assert_output --partial "Staged 1 file"
  run git status --porcelain -- new.txt
  [[ "$output" == A* ]]
  run git status --porcelain -- docs/note.md
  [[ "$output" == " M"* ]]
  psx_reset
}

@test "contract a: '-- <file>' stages exactly that file (#297, was characterization)" {
  # FLIPPED (#297 fast-follow, delta-spec §3.4): post-'--' positionals are
  # FILES. Before the fix, git-a's loop broke at the FIRST '--' with
  # remaining_args EMPTY, so the no-args arm ran `git add -u` — the
  # pathspec silently discarded and never-named files staged instead
  # (contract §2 rule 1: pathspecs are never silently discarded).
  psx_setup
  run hug a -- new.txt
  assert_success
  assert_output --partial "Staged 1 file"
  run git status --porcelain -- new.txt
  [[ "$output" == A* ]]
  # docs/note.md — never named on the command line — must stay unstaged.
  run git status --porcelain -- docs/note.md
  [[ "$output" == " M"* ]]
  psx_reset
}

@test "contract a: '-- -A' stages a file literally named -A, nothing else (#297)" {
  # The data/option boundary on a MUTATOR: without the protective '--' in
  # hug_add_with_summary's `git add`, a post-separator file named -A would
  # stage the WHOLE TREE (git add -A) — the highest-stakes spoof in the PR.
  psx_setup
  echo dashA > ./-A
  run hug a -- -A
  assert_success
  run git status --porcelain -- -A
  [[ "$output" == A* ]]
  # the never-named unstaged file must remain unstaged
  run git status --porcelain -- docs/note.md
  [[ "$output" == " M"* ]]
  psx_reset
}

@test "characterization a: bare trailing '--' opens the picker (duality exception)" {
  # characterization: the CONTRACT-SANCTIONED duality (audit staging row):
  # a BARE trailing '--' is the interactive picker trigger, not a separator.
  # Headless observable (probed in BOTH gum branches — gum installed: TTY
  # failure; gum absent: install-pointer error): exit 0 + "No files
  # selected.", and the stage-all arm must NOT run (docs/note.md stays
  # unstaged).
  psx_setup
  run hug a --
  assert_success
  assert_output --partial "No files selected."
  run git status --porcelain -- docs/note.md
  [[ "$output" == " M"* ]]
  psx_reset
}

@test "characterization a: unknown flag passes through to git add (exit 129)" {
  # characterization: probed — `-xX` reaches `git add` verbatim and git
  # rejects it (exit 129, "unknown switch"): pass-through-loud, no swallow.
  psx_setup
  run hug a -xX
  assert_equal 129 "$status"
  assert_output --partial "unknown switch"
  psx_reset
}

@test "characterization f-family: '-- <file>' filters exactly that file (fa fb fborn fcon)" {
  # characterization (mirror of the a-command cells): probed — the f-family
  # shares parse_common_flags, so `-- <file>` reaches the exec'd git command
  # as the (sole) pathspec: exit 0, output scoped to src/a.py, no fatal.
  # Per-command observable: fa → the `uniq -c` author tally for src/a.py
  # (one commit in the fixture: a single " 1 <author>" line); fb → blame
  # porcelain for src/a.py; fborn → the "base" commit line; fcon → the
  # author line. Flip target PR-B (uniform pathspec contract).
  psx_setup
  run hug fa -- src/a.py
  assert_success
  assert_output --regexp '^[[:space:]]*1 '
  refute_output --partial "fatal:"
  psx_reset

  psx_setup
  run hug fb -- src/a.py
  assert_success
  refute_output --partial "fatal:"
  psx_reset

  psx_setup
  run hug fborn -- src/a.py
  assert_success
  assert_output --partial "base"
  refute_output --partial "fatal:"
  psx_reset

  psx_setup
  run hug fcon -- src/a.py
  assert_success
  refute_output --partial "fatal:"
  psx_reset
}

@test "characterization f-family: bare trailing '--' opens the picker, never a file (fa fb fborn fcon)" {
  # characterization (mirror of the a-command cells' duality exception —
  # which PARTIALLY holds here): probed per command in the BATS env (gum
  # present, headless): a bare trailing '--' is stripped by
  # parse_common_flags, leaving $# == 0, and then the commands DIVERGE:
  #   fa/fb/fcon — no-file arm opens the PICKER; headless TTY probe fails
  #     → "No file selected or cancelled.", exit 0 (with gum absent the
  #     same arm errors "File argument required...", exit 1 — probed);
  #   fborn — has NO gum branch at all: "File argument required." exit 1
  #     in every environment (probed).
  # Either way NO file argument is consumed: the '--' is a mode trigger,
  # not a pathspec, here. Flip target PR-B: the bare-'--' duality is
  # inconsistent across commands (contrast slu/slk, where '--' was a
  # phantom pathspec).
  local cmd
  for cmd in fa fb fborn fcon; do
    psx_setup
    run hug "$cmd" --
    if [[ "$cmd" == "fborn" ]] || ! command -v gum >/dev/null 2>&1; then
      assert_failure
      assert_output --partial "File argument required"
    else
      assert_success
      assert_output --partial "No file selected or cancelled."
    fi
    psx_reset
  done
}

@test "characterization w discard: pathspec filter + proper '--' (dry-run cells)" {
  # characterization: probed — default (unstaged) scope + `-- docs/` previews
  # exactly docs/note.md; the separator form is equivalent; `-s -- src/`
  # discriminates the staged set (src/a.py, no docs leak). Flip target for
  # full contract conformance: #292 Pattern-A migration follow-up.
  psx_setup
  run hug w discard --dry-run docs/
  assert_success
  assert_output --partial "Unstaged paths"
  assert_output --partial "docs/note.md"
  refute_output --partial "src/a.py"
  psx_reset

  psx_setup
  run hug w discard --dry-run -- docs/
  assert_success
  assert_output --partial "docs/note.md"
  psx_reset

  psx_setup
  run hug w discard -s --dry-run src/
  assert_success
  assert_output --partial "Staged paths"
  assert_output --partial "src/a.py"
  refute_output --partial "docs/note.md"
  psx_reset
}

@test "characterization w discard: unknown flag loud (exit 2); bare '--' opens picker" {
  # FLIPPED in Task 3 (#292 PR-C, with the w-discard migration): `-xX` used
  # to become a pathspec in parse_common_flags' fallback loop, matching
  # nothing, exit 0 "Nothing to discard" (silent swallow). The own-loop's
  # loud -* arm now rejects it, exit 2 family template. The picker arm
  # keeps matching the `a`/sw family: exit 0 + "No files selected."
  psx_setup
  run hug w discard -xX
  assert_equal 2 "$status"
  assert_output --partial "Unknown option: -xX"
  refute_output --partial "Nothing to discard"
  psx_reset

  psx_setup
  run hug w discard --
  assert_success
  assert_output --partial "No files selected."
  psx_reset
}

@test "characterization w purge: untracked pathspec filter + loud tracked-path refusal" {
  # characterization: probed — `--dry-run new.txt` previews exactly the
  # untracked file (separator form equivalent); a pathspec COVERING a tracked
  # file ('.') is refused loudly ("tracked or has staged changes"; exit
  # flipped 1→2 by the Task 4 migration, family usage-error template).
  # `-xX` FLIPPED in Task 4 (#292 PR-C, with the w-purge migration): used
  # to become a pathspec in parse_common_flags' fallback loop, matching
  # nothing, exit 0 "Nothing to purge" (silent swallow). The own-loop's
  # loud -* arm now rejects it, exit 2 family template.
  psx_setup
  run hug w purge --dry-run new.txt
  assert_success
  assert_output --partial "Untracked (1)"
  assert_output --partial "new.txt"
  psx_reset

  psx_setup
  run hug w purge --dry-run -- new.txt
  assert_success
  assert_output --partial "new.txt"
  psx_reset

  psx_setup
  run hug w purge --dry-run .
  assert_failure
  assert_output --partial "tracked or has staged changes"
  psx_reset

  psx_setup
  run hug w purge -xX
  assert_equal 2 "$status"
  assert_output --partial "Unknown option: -xX"
  refute_output --partial "Nothing to purge"
  psx_reset
}

@test "characterization w wipe: delegation to discard — filter + loud rejection inherit" {
  # characterization: probed — wipe = `w discard -u -s "$@`, so the pathspec
  # filter is inherited from discard, and (FLIPPED in Task 3, #292 PR-C) the
  # "-xX → Nothing to discard" swallow inherited the loud exit-2 rejection
  # the same way.
  psx_setup
  run hug w wipe --dry-run docs/
  assert_success
  assert_output --partial "Unstaged paths"
  assert_output --partial "docs/note.md"
  assert_output --partial "Both staged and unstaged would be fully discarded"
  refute_output --partial "src/a.py"
  psx_reset

  psx_setup
  run hug w wipe -xX
  assert_equal 2 "$status"
  assert_output --partial "Unknown option: -xX"
  refute_output --partial "Nothing to discard"
  psx_reset
}

@test "characterization w zap: combined preview, scoped filter, and loud rejection" {
  # characterization: probed — `zap --dry-run .` previews all three buckets
  # (staged src/a.py, unstaged docs/note.md, untracked new.txt); a scoped
  # pathspec narrows to that file only. `-xX` FLIPPED in Task 5 (#292
  # PR-C, with the w-zap migration): used to become a pathspec in
  # parse_common_flags' fallback loop, matching nothing, exit 0 "Nothing
  # to zap" (silent swallow). The shared helper's loud -* arm now rejects
  # it, exit 2 family template.
  psx_setup
  run hug w zap --dry-run .
  assert_success
  assert_output --partial "src/a.py"
  assert_output --partial "docs/note.md"
  assert_output --partial "Untracked (1)"
  assert_output --partial "new.txt"
  psx_reset

  psx_setup
  run hug w zap --dry-run new.txt
  assert_success
  assert_output --partial "new.txt"
  refute_output --partial "src/a.py"
  refute_output --partial "docs/note.md"
  psx_reset

  psx_setup
  run hug w zap -xX
  assert_equal 2 "$status"
  assert_output --partial "Unknown option: -xX"
  refute_output --partial "Nothing to zap"
  psx_reset
}

@test "w get: -u parses order-independently after common flags (review)" {
  # Review fix: '-u' used to be consumed only by a LEADING custom loop, so
  # 'hug w get -f -u <file>' (documented flag order) left '-u' for the
  # common parser, which reclassified it as the target — dying on
  # "Invalid commitish for --target: -u". The custom flag is now extracted
  # wherever it appears BEFORE the '--' separator; after it, '-u' is a file.
  local upstream_and_clean_setup='
    git branch up-ref HEAD~1
    git branch --set-upstream-to=up-ref
    git add -A
    git commit -q -m divergence'

  # Cell 1 — common flag BEFORE -u: same restore as the leading-(-u) cell.
  psx_setup
  eval "$upstream_and_clean_setup"
  run hug w get -f -u src/a.py
  assert_success
  assert_output --partial "Files reset to"
  assert_equal "py1" "$(cat src/a.py)"
  psx_reset

  # Cell 2 — '--dry-run' before '-u': reset-all preview still reachable.
  psx_setup
  eval "$upstream_and_clean_setup"
  run hug w get --dry-run -u
  assert_success
  assert_output --partial "Dry run — no files were modified."
  psx_reset

  # Cell 3 — '-u' AFTER the separator (flipped by the uniform pathspec
  # contract, #292 PR-C): an EXACT own-flag spelling post-'--' is a
  # misordered flag, not data — exit 2 with the family template. (Was:
  # restored a file literally named '-u'; such a file remains reachable
  # ONLY as './-u', the exact-spelling rule's documented escape hatch.)
  psx_setup
  echo ubase > ./-u
  git add -- -u
  git commit -q -m "add file named -u"
  echo udiverged > ./-u
  git commit -q -am "diverge -u"
  run hug w get HEAD~1 -- -u
  assert_equal 2 "$status"
  assert_output --partial "Flags must precede '--': hug w get -u"
  refute_output --partial "Will reset"
  run hug w get HEAD~1 -- ./-u
  assert_success
  assert_equal "ubase" "$(cat ./-u)"
  psx_reset
}

@test "contract lc/lf: picker selection restricts the delegated search to the chosen file (review)" {
  # Review fix: the picker delegation used to forward the user's pathspecs
  # AND the picked file under one '--' — but git UNIONS positive pathspecs,
  # so 'll ... -- . src/a.py' kept matching every file in scope and the
  # selection restricted nothing. The picked file now REPLACES the scope
  # (the pathspecs already did their job: scoping the candidate list).
  #
  # Stub gum SELECTS (prints) the candidate line matching $GUM_PICK instead
  # of cancelling — the driver then execs the delegated search, whose output
  # is the oracle: only the chosen file's commit may appear.
  local cmd
  for cmd in lc lf; do
    psx_setup
    # 'pickterm' appears in BOTH content (lc pickaxe) and messages (lf
    # grep) so one fixture serves both commands.
    echo pickterm > sel-a.py
    git add sel-a.py
    git commit -q -m "chosen pickterm commit"
    echo pickterm > sel-b.py
    git add sel-b.py
    git commit -q -m "other pickterm commit"
    echo dirty >> sel-a.py # both dirty so both are picker candidates
    echo dirty >> sel-b.py

    local stub_dir="$BATS_TEST_TMPDIR/stub"
    mkdir -p "$stub_dir"
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'if [[ "${1:-}" == filter ]]; then' \
      '  sed $'"'"'s/\033\\[[0-9;]*m//g'"'"' | tee "$GUM_CANDIDATES_FILE" | grep -F "$GUM_PICK" | head -1' \
      'fi' \
      'exit 0' > "$stub_dir/gum"
    chmod +x "$stub_dir/gum"
    GUM_CANDIDATES_FILE="$BATS_TEST_TMPDIR/gum-candidates.txt"
    GUM_PICK="sel-a.py"
    export GUM_CANDIDATES_FILE GUM_PICK HUG_TEST_MODE=true
    PATH="$stub_dir:$PATH"
    : > "$GUM_CANDIDATES_FILE"

    if [[ "$cmd" == lc ]]; then
      run hug lc pickterm -- . --
    else
      run hug lf pickterm -- . --
    fi
    assert_success
    assert_output --partial "chosen pickterm commit"
    refute_output --partial "other pickterm commit"
    psx_reset
  done
}

@test "contract a: picker selection stages the chosen file only (Task 9)" {
  # a's SELECTION semantics, standalone by design (Task 9): the shared
  # columns prove SCOPING with a CANCELLING stub (read-only by construction);
  # this cell proves the mutating half with a SELECTING stub (same model as
  # the lc/lf "chosen file" test above) — one candidate is picked from the
  # scoped list and ONLY that file stages. Two-sided: sel-b.py (offered
  # beside the pick) must stay untracked, and the never-named docs/note.md
  # must stay unstaged. Post-pick rule (forward_pathspecs_to_picker
  # contract): the picked file REPLACES the user's pathspecs on the exec
  # line — the '.' scope's job ended at scoping the candidates, and git
  # would union positive pathspecs if both rode along.
  psx_setup
  echo pick > sel-a.py # untracked: a's picker lists --unstaged --untracked
  echo pick > sel-b.py
  local stub_dir="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$stub_dir"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ "${1:-}" == filter ]]; then' \
    '  sed $'"'"'s/\033\\[[0-9;]*m//g'"'"' | tee "$GUM_CANDIDATES_FILE" | grep -F "$GUM_PICK" | head -1' \
    'fi' \
    'exit 0' > "$stub_dir/gum"
  chmod +x "$stub_dir/gum"
  GUM_CANDIDATES_FILE="$BATS_TEST_TMPDIR/gum-candidates.txt"
  GUM_PICK="sel-a.py"
  export GUM_CANDIDATES_FILE GUM_PICK HUG_TEST_MODE=true
  PATH="$stub_dir:$PATH"
  : > "$GUM_CANDIDATES_FILE"

  run hug a -- . --
  assert_success
  assert_output --partial "Staged 1 file"
  # The picked file staged …
  run git status --porcelain -- sel-a.py
  [[ "$output" == A* ]]
  # … the offered sibling did NOT …
  run git status --porcelain -- sel-b.py
  [[ "$output" == "??"* ]]
  # … and the never-named unstaged file stays unstaged.
  run git status --porcelain -- docs/note.md
  [[ "$output" == " M"* ]]
  psx_reset
}

@test "contract lf --json: option-named pathspec after -- stays a pathspec (review)" {
  # Review fix: batch_commit_search/batch_code_search used to interpret
  # EVERY '--no-body'/'--no-files' token as their private flag — a pathspec
  # literally named '--no-body' was consumed (dropping the scope AND
  # flipping body formatting). The parsers are now separator-aware.
  psx_setup
  printf 'jsonterm\n' > --no-body 2>/dev/null || { printf 'jsonterm\n' > './--no-body'; }
  git add -- --no-body
  git commit -q -m "commit with jsonterm in --no-body"
  printf 'jsonterm\n' > plain.txt
  git add plain.txt
  git commit -q -m "commit with jsonterm in plain"

  # Scoped to the file named '--no-body': exactly the one commit.
  run hug lf --json jsonterm -- --no-body
  assert_success
  assert_output --partial "commit with jsonterm in --no-body"
  refute_output --partial "commit with jsonterm in plain"
  psx_reset
}

@test "characterization a: option after a path keeps git semantics (foo -A)" {
  # Review fix (#3800343262): 'hug a foo -A' must match raw git — probed:
  # 'git add new.txt -A' exits 0 and treats -A as an OPTION scoped to the
  # given path (docs/note.md stays UNSTAGED; untracked stays untracked) —
  # NOT as a pathspec and not repo-wide. Before the review fix, a first-arg
  # heuristic inserted '--', making '-A' a filename and changing the staged
  # set (or erroring on a nonexistent pathspec).
  psx_setup
  run hug a new.txt -A
  assert_success
  refute_output --partial "did not match"   # -A was not a pathspec
  run git status --porcelain -- new.txt
  [[ "$output" == A* ]]                      # the NAMED path did stage (roast F-003)
  # git-parity: -A is an option scoped to new.txt — the never-named
  # tracked file must remain UNSTAGED (probed on raw git)
  run git status --porcelain -- docs/note.md
  [[ "$output" == " M"* ]]
  psx_reset
}

@test "contract a: from-file list line named -A is data, never git-add -A (#297 roast)" {
  # Roast F-001 live repro class: a --from-file list containing the line
  # '-A' used to run 'git add -A' (whole tree staged). Source-derived lines
  # are CLASSIFIED data — they stage after the protective separator.
  psx_setup
  echo dashA > ./-A
  printf '%s\n' -A > list.txt
  git add -- list.txt
  git commit -q -m "add list"
  run hug a --from-file list.txt
  assert_success
  run git status --porcelain -- -A
  [[ "$output" == A* ]]
  # the never-named unstaged file must remain unstaged
  run git status --porcelain -- docs/note.md
  [[ "$output" == " M"* ]]
  psx_reset
}

@test "contract a: --browse-root opens the picker, paths error loudly (#297 roast)" {
  # Roast F-002: --browse-root was documented but DEAD (the custom loop
  # swallowed it; 'git add --browse-root' died exit 129). Now: alone → the
  # full-repo picker (headless observable: "No files selected." / cancel);
  # with an explicit path → parse_common_flags' parity error.
  psx_setup
  run hug a --browse-root
  assert_success
  assert_output --partial "No files selected."
  run git status --porcelain -- docs/note.md
  [[ "$output" == " M"* ]]

  run hug a --browse-root new.txt
  assert_failure
  assert_output --partial "--browse-root cannot be used with explicit paths"
  psx_reset
}

###############################################################################
# Roast round 2 (PR-B review, #298): malformed magic pathspecs fail LOUDLY,
# and us scoped-empty has ONE exit contract.
#
# MAJOR 1: ':(bogus)src/' used to be swallowed by every suppressed capture
# in the family — sls answered "No staged files matching ':(bogus)src/'
# found." exit 0, slu --json emitted a zero-count envelope (a machine API
# silently lying), us --from-commit printed git's fatal AND a contradictory
# "No files matching" info. Contract now: git's fatal lands on stderr, hug
# adds "Invalid pathspec: ... See 'hug help :pathspec'." and exits 2
# (HUG_EX_USAGE — same class as the unknown '-*' rejection).
###############################################################################

@test "roast2 M1: sls rejects malformed magic pathspec loudly (exit 2, no empty answer)" {
  psx_setup
  run hug sls -- ':(bogus)src/'
  assert_equal 2 "$status"
  assert_output --partial "Invalid pathspec"
  assert_output --partial "hug help :pathspec"
  refute_output --partial "No staged files matching"
  psx_reset
}

@test "roast2 M1: whole sl* family + count + json reject malformed magic pathspecs" {
  psx_setup
  local cmd
  for cmd in sls slu slk sli slc sl; do
    run hug $cmd -- ':(bogus)src/'
    assert_equal 2 "$status"
    assert_output --partial "Invalid pathspec"
    assert_output --partial "hug help :pathspec"
  done
  run hug sls -c -- ':(bogus)src/'
  assert_equal 2 "$status"
  assert_output --partial "Invalid pathspec"
  psx_reset
}

@test "roast2 M1: --json emits NOTHING on stdout for a malformed magic pathspec" {
  psx_setup
  # zero non-JSON bytes rule: on failure stdout must carry no envelope at
  # all. Separated streams (run merges them, so probe manually).
  local json_out status=0
  json_out=$(hug slu --json -- ':(bogus)src/' 2>/dev/null) || status=$?
  assert_equal 2 "$status"
  assert_equal "" "$json_out"
  psx_reset
}

@test "roast2 M1: us --from-commit with malformed magic pathspec: single loud error, staging untouched" {
  psx_setup
  run hug us --from-commit HEAD -- ':(bogus)src/'
  assert_equal 2 "$status"
  assert_output --partial "Invalid pathspec"
  refute_output --partial "No files matching" # the contradictory info is gone
  run hug sls
  assert_output --partial "src/a.py" # staging untouched
  psx_reset
}

@test "roast2 M1: us plain arm rejects malformed magic pathspec loudly" {
  psx_setup
  run hug us -- ':(bogus)src/'
  assert_equal 2 "$status"
  assert_output --partial "Invalid pathspec"
  run hug sls
  assert_output --partial "src/a.py" # staging untouched
  psx_reset
}

@test "roast2 M1: valid magic pathspecs and the unscoped run are unchanged" {
  psx_setup
  run hug sls -- ':(exclude)docs/'
  assert_success
  assert_output --partial "src/a.py"
  refute_output --partial "docs/"
  run hug us -- ':(top)src/a.py'
  assert_success
  assert_output --partial "Unstaged 1 file"
  # Unscoped + bare '--' stay byte-identical (no validation chatter)
  run hug sls
  local plain="$output"
  run hug sls --
  assert_equal "$plain" "$output"
  psx_reset
}

###############################################################################
# MAJOR 2: us scoped-empty had TWO exit contracts — a pathspec-shaped scope
# matching nothing staged answered the loud "File 'nonexistent/' is not
# tracked by git." exit 1 (wrong noun, wrong class), while the from-source
# arm answered "No files matching ... to unstage." exit 0. One condition,
# one answer: scope-shaped no-match → info + exit 0. The loud error stays
# for LITERAL file arguments (the safety check that names a real file the
# user explicitly asked to unstage).
###############################################################################

@test "roast2 M2: us scoped-empty on a pathspec-shaped scope is a no-match info, exit 0" {
  psx_setup
  run hug us -- nonexistent/
  assert_success
  assert_output --partial "No files matching 'nonexistent/' to unstage."
  refute_output --partial "is not tracked by git"
  run hug sls
  assert_output --partial "src/a.py" # staging untouched
  psx_reset
}

@test "roast2 M2: us literal tracked-but-unstaged file keeps the loud safety error" {
  psx_setup
  # docs/note.md is tracked with an UNSTAGED mod — a literal file the user
  # named; the confusing-silent-no-op safety check must survive unchanged.
  run hug us docs/note.md
  assert_failure
  assert_output --partial "is not staged"
  psx_reset
}

@test "roast2 M2: us directory scope with nothing staged under it is a no-match info" {
  psx_setup
  git restore --staged src/a.py # nothing staged under src/ anymore
  run hug us -- src/
  assert_success
  assert_output --partial "No files matching 'src/' to unstage."
  psx_reset
}

###############################################################################
# PR-C Task 1 (#292): the `w` GATEWAY is a contract pass-through, not a
# pathspec command itself — but its wips arm INJECTED a flag after the user's
# args, past their `--`, so 'w wips -- "draft"' drained the injected --stay
# into the message (branch WIP/….draftstay, stay never applied). Post-
# migration that same order would exit 2 on a flag hug itself injected.
# Gateway rule: injected flags belong in the FLAG ZONE, before the user's
# data. The unknown-subcommand arm printed usage but fell through to exit 0.
###############################################################################

@test "gateway w: wips prepends --stay so post--- data stays the message (#292 PR-C)" {
  psx_setup
  # Fixture has pending changes (staged src/a.py + unstaged docs/note.md),
  # so w-wip has work to park.
  run hug w wips -- "draft"
  assert_success
  refute_output --partial "draftstay"
  # Branch slug carries ONLY the user's message...
  run git branch --list "WIP/*"
  assert_output --partial "draft"
  refute_output --partial "stay"
  # ...and stay semantics applied: we REMAIN on the WIP branch (probed:
  # pre-fix the gateway's trailing --stay was swallowed as message text and
  # w-wip switched back to the original branch).
  [[ "$(git branch --show-current)" == WIP/* ]]
  psx_reset
}

@test "gateway w: unknown subcommand exits 2, not 0 (#292 PR-C)" {
  psx_setup
  run hug w badcmd
  [[ "$status" -eq 2 ]]
  assert_output --partial "Usage: hug w <command>"
  psx_reset
}

@test "gateway w: discard -- <path> passes through to w-discard untouched (#292 PR-C)" {
  psx_setup
  # Characterization: the gateway forwards args verbatim; the pathspec
  # reaches w-discard's listing (non-TTY cancels before mutating, so the
  # unstaged mod survives as the two-sided witness).
  run hug w discard -- docs/note.md
  assert_failure
  assert_output --partial "docs/note.md"
  assert_output --partial "Cancelled."
  run git status --porcelain -- docs/note.md
  [[ "$output" == " M"* ]]
  psx_reset
}

@test "gateway w: --help / -h print usage and exit 0 (#292 PR-C review)" {
  # Review catch: the new unknown-subcommand exit-2 arm also catches
  # -h/--help. Every hug command documents help at exit 0, and the OLD
  # fall-through was exit 0 — help must stay in the success family.
  # GOTCHA: invoked through `hug w`, git itself intercepts `--help`
  # (runs `man git-w`, exit 16 — probed, unchanged by this PR), so the
  # gateway's help arm is only reachable by direct script invocation —
  # hence $HUG_BIN here, matching how test_helper pins the worktree.
  psx_setup
  run "$HUG_BIN/git-w" --help
  [[ "$status" -eq 0 ]]
  assert_output --partial "Usage: hug w <command>"
  run "$HUG_BIN/git-w" -h
  [[ "$status" -eq 0 ]]
  assert_output --partial "Usage: hug w <command>"
  psx_reset
}

###############################################################################
# PR-C ENROLLMENT (Task 2, #292): the w family + llu + sh join the suite
# BEFORE any of them migrates (Tasks 3-11). Two artifacts live here:
#   1. the master membership diff — closes the PR-A under-transcription trap
#      (8 commands silently untested) by RULE: `enrolled` is DERIVED from the
#      same arrays the column loops consume, never a hand-coded copy (a copy
#      stays green when a command falls out of its column; codex #3815936629);
#   2. characterization rows pinning TODAY's correct behavior (green now),
#      plus the staged RED rows at the very bottom (commented out — each
#      migration task uncomments its own rows in ITS commit, so CI never
#      carries a red row).
###############################################################################

@test "PR-C master roster: every command enrolled in >=1 column" {
  # Derived, never copied: the enrolled set is the union of the SAME arrays
  # the column tests above consume (plus w-get's dedicated rows). A PR-C
  # command that falls out of every column fails HERE by name.
  local -a enrolled=("${PATHSPEC_W_DESTRUCTIVE_ROWS[@]}"
                     "${PATHSPEC_W_ALL_ROWS[@]}"
                     "${PATHSPEC_WIP_ROWS[@]}"
                     "${PATHSPEC_SHOW_ROWS[@]}"
                     "${PATHSPEC_LOG_ROWS[@]}"
                     "${PATHSPEC_TARGETPLUSFILE_ROWS[@]}"
                     w-get)
  local -A seen=()
  local c
  for c in "${enrolled[@]}"; do seen["$c"]=1; done
  local orphan=()
  for cmd in "${PATHSPEC_PRC_MASTER[@]}"; do
    [[ -n "${seen[$cmd]:-}" ]] || orphan+=("$cmd")
  done
  [[ ${#orphan[@]} -eq 0 ]] || fail "PR-C roster orphan(s): ${orphan[*]} — enroll in a column loop"
}

@test "TARGET+PATH roster: every member rejects a bare invocation loudly (#311)" {
  # Membership-consumption cell for PATHSPEC_TARGETPLUSFILE_ROWS: the master
  # orphan check above only proves enrollment if the class array is consumed
  # by a REAL column, not just the union. The discriminating behaviors —
  # picker arm, one-file cardinality, flag-naming template — already live in
  # fcat's dedicated contract rows (Task 1), so this cell stays minimal: the
  # one invariant every class member shares regardless of internals — a bare
  # invocation is a LOUD usage error, never a silent success.
  for cmd in "${PATHSPEC_TARGETPLUSFILE_ROWS[@]}"; do
    psx_setup
    run hug "$cmd"
    assert_failure
    assert_output --partial "Missing target"
    psx_reset
  done
}

@test "characterization PR-C: w wipe <file> non-TTY confirm-cancel keeps the file (#292)" {
  # Probed: non-interactive `w wipe root.txt` previews the scoped unstaged
  # path, then cancels (exit 1) — the destructive op NEVER runs. The cancel
  # wording differs by gum branch (gum installed: gum's TTY failure +
  # "Cancelled."; gum absent: "Non-interactive environment: cancelled.") —
  # the shared stem "ancelled" pins BOTH. Two-sided: root.txt survives as an
  # unstaged mod.
  psx_setup
  echo r1 > root.txt
  git add root.txt
  git commit -q -m "add root.txt"
  echo r2 >> root.txt
  run hug w wipe root.txt
  assert_failure
  assert_output --partial "Unstaged paths"
  assert_output --partial "root.txt"
  assert_output --partial "ancelled"
  run git status --porcelain -- root.txt
  [[ "$output" == " M"* ]]
  psx_reset
}

@test "contract w-wipe (Task 6): delegation end-to-end — misordered flag, exact spelling, scoped glob, bare--- disposition (#292)" {
  # wipe is PURE delegation: `exec hug w discard -u -s "$@"`
  # (git-config/bin/git-w-wipe:46) — every arg path flows to discard, so
  # Task 3's discard migration carries wipe's contract flips for free.
  # These rows pin the DELEGATION boundary itself (probed, 152fdf63):
  # discard's parse layer fires with discard's own name in the remedy —
  # RATIFIED note-and-accept (#292 PR-C): the delegation is honest, the
  # message correctly names the command whose parser rejected the input.

  psx_setup
  # Misordered flag: '--dry-run' after the separator is a flag, not data —
  # the message names `hug w discard` (the delegate's parser), pinned as
  # probed. Pre-contract this silently became pathspecs and ran the
  # destructive confirm path (same class as zap's cell above).
  run hug w wipe -- src/ --dry-run
  assert_equal 2 "$status"
  assert_output --partial "Flags must precede '--': hug w discard --dry-run"
  run git status --porcelain -- src/a.py
  [[ "$output" == "M "* ]] # staged mod intact — nothing touched
  psx_reset

  psx_setup
  # EXACT spellings only — a tracked file literally named '--dry-run',
  # spelled './--dry-run' after the separator, is DATA: the preview lists
  # it (discard's row pins the same for discard itself; this proves the
  # delegation does not smuggle it into the engine's flag matcher).
  echo dr1 > ./--dry-run
  git add -- ./--dry-run
  git commit -q -m "file named --dry-run" -- ./--dry-run
  echo dr2 >> ./--dry-run
  run hug w wipe --dry-run -- ./--dry-run
  assert_success
  assert_output --partial "--dry-run"
  refute_output --partial "Flags must precede"
  psx_reset

  psx_setup
  # Scoped GLOB two-sided DESTRUCTION: ':(glob)src/**.py' narrows the wipe
  # to src/a.py — BOTH its deltas (staged + unstaged) go, content returns
  # to committed 'py1', src/ is clean; every out-of-scope change survives
  # (unstaged docs/note.md mod, untracked new.txt).
  run hug w wipe -f -- ':(glob)src/**.py'
  assert_success
  assert_output --partial "src/a.py"
  assert_equal "py1" "$(cat src/a.py)"
  run git status --porcelain -- src/
  [[ -z "$output" ]] # both buckets wiped, no residue
  run git status --porcelain -- docs/note.md
  [[ "$output" == " M"* ]] # out-of-scope unstaged mod survives
  [[ -e new.txt ]] # out-of-scope untracked survives
  psx_reset

  psx_setup
  # Separator-form scoped preview: '--dry-run -- docs/' previews ONLY the
  # unstaged docs/note.md; the staged src/a.py never appears.
  run hug w wipe --dry-run -- docs/
  assert_success
  assert_output --partial "docs/note.md"
  refute_output --partial "src/a.py"
  psx_reset

  # No-args arm and trailing bare '--' share ONE disposition (probed):
  # both open discard's picker; non-TTY the picker yields no selection —
  # "No files selected." (stem covers the cancel branch "or cancelled."),
  # exit 0, tree untouched. The bare '--' never becomes a phantom pathspec
  # and never fires the misordered-flag matcher (contrast the row above).
  psx_setup
  run hug w wipe
  assert_success
  assert_output --partial "No files selected"
  run hug w wipe --
  assert_success
  assert_output --partial "No files selected"
  run git status --porcelain -- src/a.py
  [[ "$output" == "M "* ]] # staged mod intact
  run git status --porcelain -- docs/note.md
  [[ "$output" == " M"* ]] # unstaged mod intact
  psx_reset
}

@test "characterization PR-C: w wip -- '-fix' keeps the message a message (#292)" {
  # Probed: the separator protects the dash-leading MESSAGE from flag
  # parsing — the WIP branch slug ends in '.fix' (slugified '-fix'), exit 0.
  # If the '--' were dropped, '-fix' would die as an unknown option instead.
  psx_setup
  run hug w wip -- "-fix"
  assert_success
  run git branch --list 'WIP/*' --format='%(refname:short)'
  [[ "$output" == WIP/*.fix ]]
  psx_reset
}

@test "characterization PR-C: w unwip -- WIP/... receives the branch name (#292)" {
  # Probed: create a WIP first (`w wip -- unit`), then the separator form
  # delivers the WIP/ branch name as the POSITIONAL (not a flag): the unpark
  # preview names the exact branch and, non-interactively, refuses to apply
  # (exit 1) leaving the WIP branch in place. A dropped '--' would instead
  # error "Branch '-' does not exist"-style or print help.
  psx_setup
  hug w wip -- "unit" >/dev/null 2>&1
  local br
  br=$(git branch --list 'WIP/*' --format='%(refname:short)')
  [[ -n "$br" ]]
  run hug w unwip -- "$br"
  assert_failure
  assert_output --partial "Unparking"
  assert_output --partial "$br"
  run git branch --list 'WIP/*' --format='%(refname:short)'
  [[ "$output" == *"$br"* ]] # not deleted — the cancel path
  psx_reset
}

@test "characterization PR-C: w get HEAD -- src/ scoped flow names scope and target (#292)" {
  # Probed: the separator form runs the scoped restore flow — "Will reset
  # files to commit HEAD" names the target, the scope check names ONLY
  # src/a.py (docs/note.md, out of scope, never appears), and the dirty-tree
  # guard refuses (exit 1) before mutating anything.
  psx_setup
  run hug w get HEAD -- src/
  assert_failure
  assert_output --partial "Will reset files to commit HEAD"
  assert_output --partial "src/a.py"
  refute_output --partial "docs/note.md"
  run git status --porcelain -- src/a.py
  [[ "$output" == "M"* ]] # staging state untouched by the refusal
  psx_reset
}

@test "characterization PR-C: w zap src/ --dry-run honors the flag after the pathspec (#292)" {
  # Probed: position-independent --dry-run — the flag AFTER the positional
  # pathspec is still parsed as a flag (not a second pathspec): dry-run
  # preview scoped to src/ (staged src/a.py only), exit 0, tree untouched.
  psx_setup
  run hug w zap src/ --dry-run
  assert_success
  assert_output --partial "Dry run"
  assert_output --partial "src/a.py"
  refute_output --partial "docs/note.md"
  refute_output --partial "new.txt"
  run git status --porcelain -- src/a.py
  [[ "$output" == "M"* ]]
  psx_reset
}

###############################################################################
# RED rows staged for PR-C migrations (Tasks 3-11) — each row lands in the
# SAME commit as the migration that flips it (landing it early would break
# CI). Landed so far: Task 3 (w-discard; w-wipe flips by delegation), Task
# 4 (w-purge), Task 5 (w-zap, on the shared parse_scoped_own_flags
# helper), Task 7 (the w-*-all whole-tree family — own-loop hygiene, no
# pathspec collection; wipe-all gets its OWN loop so its rejections name
# wipe, not the discard-all engine it execs), the w-get migration (PR-C
# plan Task 9; its staged marker below is numbered 6 and KEEPS that number
# so the guard set {3 4 5 6 10 11} stays stable).
# Remaining staged rows keep the FLIPS-IN-TASK-N prefix; the guard test
# below keeps the block from being lost. Current (probed, pre-migration)
# behavior for each is already pinned green by the characterization rows in
# the closing-fix section above (w discard/purge/zap/wipe) and the
# characterization llu / contract sh rows.
###############################################################################

# FLIPS-IN-TASK-3 (landed, w-discard migration): w-discard/w-wipe unknown
# flag must exit 2 with the family template (was: silently swallowed as a
# pathspec — "Nothing to discard", exit 0). w-wipe flips by delegation
# (wipe = `w discard -u -s "$@"`).
@test "contract w-destructive (Task 3, discard+wipe): -xX loud, exit 2, never a pathspec" {
  local cmd msg
  for cmd in discard wipe; do
    msg="Nothing to discard"
    psx_setup
    run hug w "$cmd" -xX
    assert_equal 2 "$status"
    assert_output --partial "Unknown option: -xX"
    refute_output --partial "$msg"
    psx_reset
  done
}

# FLIPS-IN-TASK-3 remainder (purge landed in Task 4, #292 PR-C, with the
# w-purge migration): same rejection, same template — purge used to
# swallow '-xX' as a pathspec (exit 0 "Nothing to purge").
@test "contract w-destructive (Task 4, purge): -xX loud, exit 2, never a pathspec" {
  psx_setup
  run hug w purge -xX
  assert_equal 2 "$status"
  assert_output --partial "Unknown option: -xX"
  refute_output --partial "Nothing to purge"
  psx_reset
}

# FLIPS-IN-TASK-5 (landed, w-zap migration): zap used to swallow '-xX'
# as a pathspec (exit 0 "Nothing to zap") — the shared helper's loud -*
# arm rejects it, same family template.
@test "contract w-destructive (Task 5, zap): -xX loud, exit 2, never a pathspec" {
  psx_setup
  run hug w zap -xX
  assert_equal 2 "$status"
  assert_output --partial "Unknown option: -xX"
  refute_output --partial "Nothing to zap"
  psx_reset
}

@test "contract w-zap (Task 5): scoped zap — validation, separator, two-sided scope, OQ cells" {
  # Full contract adoption (#292 PR-C Task 5, on the shared
  # parse_scoped_own_flags helper — w-zap has NO own flags, so the helper
  # provides only the loud -* arm and the common-spelling matcher): loud
  # typo'd magic, post-'--' flag rejection (THE dangerous receipt: the
  # dry-run used to be silently swallowed and zap ran the DESTRUCTIVE
  # confirm path — probed pre-migration: exit 1 non-TTY cancel was the
  # only thing that saved the tree), scoped two-sided destruction, and
  # the OQ-1 cell.
  psx_setup
  # Typo'd magic prefix: git's own fatal + hug usage remedy, exit 2 — never
  # a silent "Nothing to zap" (was: exit 0, a silent empty zap set hiding
  # the typo entirely). Nothing removed (untracked file intact).
  run hug w zap -- ':(exlude)x/'
  assert_equal 2 "$status"
  assert_output --partial "Invalid pathspec"
  refute_output --partial "Nothing to zap"
  run git status --porcelain -- new.txt
  [[ "$output" == "??"* ]]
  psx_reset

  psx_setup
  # THE dangerous receipt: '--dry-run' after the separator is a misordered
  # flag, not data. Pre-migration probe: `hug w zap -- src/ --dry-run`
  # silently became pathspecs 'src/ --dry-run', dry_run stayed FALSE, and
  # zap ran the WIPE engine's destructive confirm preview (non-TTY cancel,
  # exit 1) — the preview was not merely skipped, the DESTRUCTIVE path
  # ran. Now: exit 2 before anything touches the tree.
  run hug w zap -- src/ --dry-run
  assert_equal 2 "$status"
  assert_output --partial "Flags must precede '--'"
  run git status --porcelain -- src/a.py
  [[ "$output" == "M "* ]] # staged mod intact
  psx_reset

  # -h/--help post-'--' (same silent-swallow class — 'hug w zap -- --help'
  # used to answer "Nothing to zap" exit 0, probed).
  psx_setup
  run hug w zap -- --help
  assert_equal 2 "$status"
  assert_output --partial "Flags must precede '--'"
  refute_output --partial "Nothing to zap"
  psx_reset

  psx_setup
  run hug w zap -- -h
  assert_equal 2 "$status"
  assert_output --partial "Flags must precede '--'"
  refute_output --partial "Nothing to zap"
  psx_reset

  # EXACT spellings only — composed-contract cell (probed): an untracked
  # file literally named '--dry-run', spelled './--dry-run' after the
  # separator, is DATA at zap's own parse layer (no rejection there), but
  # git porcelain normalizes it to the bare '--dry-run' spelling before
  # the purge-engine delegation — and the ENGINE's matcher (same helper,
  # same invariant) refuses that exact spelling, exit 2, nothing removed.
  # Fail-closed by construction: delegation cannot smuggle a flag-spelled
  # filename past an engine's own matcher.
  psx_setup
  echo dr1 > ./--dry-run
  run hug w zap --dry-run -- ./--dry-run
  assert_equal 2 "$status"
  assert_output --partial "Flags must precede '--': hug w purge --dry-run"
  [[ -e ./--dry-run ]] # nothing removed
  psx_reset

  psx_setup
  # Scoped dry-run preview, two-sided: 'src/' narrows to the staged mod;
  # the unstaged docs/note.md and untracked new.txt never appear.
  run hug w zap --dry-run -- src/
  assert_success
  assert_output --partial "src/a.py"
  refute_output --partial "docs/note.md"
  refute_output --partial "new.txt"
  psx_reset

  psx_setup
  # Two-sided scoped DESTRUCTION: 'docs/' carries an unstaged mod and an
  # untracked file — `zap -f -- docs/` wipes BOTH in-scope buckets (note.md
  # back to its committed content, junk gone) while EVERY out-of-scope
  # change survives (untracked new.txt, staged src/a.py). Both engines
  # (wipe via discard, purge) read the ONE validated pathspec array.
  echo junk > docs/junk.txt
  run hug w zap -f -- docs/
  assert_success
  run cat docs/note.md
  assert_output "note1" # unstaged mod wiped, committed content restored
  [[ ! -e docs/junk.txt ]] # in-scope untracked purged
  [[ -e new.txt ]] # out-of-scope untracked survives
  run git status --porcelain -- src/a.py
  [[ "$output" == "M "* ]] # out-of-scope staged mod survives
  psx_reset

  # OQ-1 cell (probed, pinned): a trailing bare '--' opens the picker arm
  # — non-TTY it answers "Non-interactive mode: Provide files as
  # arguments.", exit 1, IDENTICAL to bare `hug w zap` (the --picker
  # split mode preserves the trigger; the bare '--' never becomes a
  # phantom pathspec).
  psx_setup
  run hug w zap --
  assert_equal 1 "$status"
  assert_output --partial "Non-interactive mode"
  refute_output --partial "Nothing to zap"
  psx_reset
}

@test "contract w-destructive (Task 5, helper): sync-guard across discard/purge/zap" {
  # ONE row set proving the shared parse_scoped_own_flags matcher for all
  # three family commands (supersedes the per-command sync-guard loops —
  # the matcher is helper-owned now, so the invariant is proven at the
  # helper level, once per command): every spelling of own ∪ common flags
  # dies exit 2 post-'--'. w-zap has NO own flags — common set only.
  local cmd f
  local -a spellings
  for cmd in discard purge zap; do
    spellings=(--dry-run -f --force -y --yes --browse-root -q --quiet -h --help)
    case "$cmd" in
    discard) spellings+=(-u --unstaged -s --staged) ;;
    purge) spellings+=(-u --untracked -i --ignored) ;;
    esac
    for f in "${spellings[@]}"; do
      psx_setup
      run hug w "$cmd" -- "$f"
      assert_equal 2 "$status"
      assert_output --partial "Flags must precede '--'"
      psx_reset
    done
  done
}

@test "contract w-purge (Task 4): scoped purge — validation, separator, two-sided scope, OQ cells" {
  # Full contract adoption (#292 PR-C Task 4, family template on
  # git-w-discard, the canonical Task 3 migration): loud typo'd magic,
  # post-'--' flag rejection, scoped exclude dry-run two-sided, and the
  # OQ-1/OQ-2 cells. Excluded dir is 'gen/' not 'build/' — the developer's
  # global gitignore ignores build/ (Task 3 LESSON).
  psx_setup
  # Typo'd magic prefix: git's own fatal + hug usage remedy, exit 2 — never
  # a silent "Nothing to purge" (was: exit 0, a silent empty purge set
  # hiding the typo entirely).
  run hug w purge -- ':(exlude)x/'
  assert_equal 2 "$status"
  assert_output --partial "Invalid pathspec"
  refute_output --partial "Nothing to purge"
  run git status --porcelain -- new.txt
  [[ "$output" == "??"* ]] # nothing removed (untracked file intact)
  psx_reset

  psx_setup
  # Post-'--' flag rejection: '--dry-run' after the separator is a
  # misordered flag, not data (was: silently became a pathspec and the
  # preview answered a false "Nothing to purge"). EXACT spellings only —
  # './--dry-run' stays a filename (pinned in the row below).
  run hug w purge -- src/ --dry-run
  assert_equal 2 "$status"
  assert_output --partial "Flags must precede '--'"
  psx_reset

  # -h/--help post-'--' (same silent-swallow class — 'hug w purge --
  # --help' used to answer "Nothing to purge" exit 0, hiding the
  # misordered flag entirely).
  psx_setup
  run hug w purge -- --help
  assert_equal 2 "$status"
  assert_output --partial "Flags must precede '--'"
  refute_output --partial "Nothing to purge"
  psx_reset

  psx_setup
  run hug w purge -- -h
  assert_equal 2 "$status"
  assert_output --partial "Flags must precede '--'"
  refute_output --partial "Nothing to purge"
  psx_reset

  # Per-command sync-guard loop RETIRED (Task 5): the matcher is
  # helper-owned now (parse_scoped_own_flags) — the invariant is proven
  # once for all three family commands by the tri-command row
  # "contract w-destructive (Task 5, helper): sync-guard across
  # discard/purge/zap" above.

  # EXACT spellings only: an UNTRACKED file literally named '--dry-run',
  # spelled './--dry-run' after the separator, is DATA — the preview lists
  # it, no rejection. (Untracked, not tracked: purge's engine refuses
  # pathspecs covering tracked files — see the OQ-2 refusal cell below.)
  # Oracle strength (Task 4 review): the bare '--dry-run' substring alone
  # is weak — it also appears inside the rejection message. 'Untracked (1)'
  # is the preview's bucket header: it proves the token was LISTED as data.
  psx_setup
  echo dr1 > ./--dry-run
  run hug w purge --dry-run -- ./--dry-run
  assert_success
  assert_output --partial "Untracked (1)"
  assert_output --partial "--dry-run"
  refute_output --partial "Flags must precede"
  refute_output --partial "Nothing to purge"
  psx_reset

  psx_setup
  # Scoped exclude-magic dry-run, two-sided: with untracked junk inside
  # gen/ and new.txt outside it, ':(exclude)gen/' previews ONLY the outside
  # file. src/ and docs/ are ALSO excluded — purge's tracked-path refusal
  # (OQ-2 cell below) fires for ANY pathspec covering a tracked file with
  # changes, and the fixture's staged src/a.py / unstaged docs/note.md
  # mods live there; a purge exclude-scope must carve those out explicitly
  # (probe receipt: single-exclude ':(exclude)gen/' alone → exit 2
  # "path 'docs/note.md' is tracked or has staged changes").
  # FIXTURE COUPLING: this exclude list mirrors setup_pathspec_fixture's
  # dirty tracked dirs (src/, docs/) — extend the exclude list if the
  # fixture gains another dirty tracked dir, or this cell starts dying on
  # the OQ-2 refusal instead of previewing.
  # (Flag BEFORE the separator — the AC's literal '-- <spec> --dry-run'
  # spelling is exactly the misordered-flag form rejected above.)
  mkdir -p gen
  echo g1 > gen/g.txt
  run hug w purge --dry-run -- ':(exclude)gen/' ':(exclude)src/' ':(exclude)docs/'
  assert_success
  assert_output --partial "new.txt"
  refute_output --partial "gen/g.txt"
  psx_reset

  # OQ-1 cell (probed, pinned): a trailing bare '--' opens the picker arm
  # — non-TTY it answers "Non-interactive mode: Provide files as
  # arguments.", exit 1, IDENTICAL to bare `hug w purge` (the --picker
  # split mode preserves the trigger; the bare '--' never becomes a
  # phantom pathspec).
  psx_setup
  run hug w purge --
  assert_equal 1 "$status"
  assert_output --partial "Non-interactive mode"
  refute_output --partial "Nothing to purge"
  psx_reset

  # OQ-2 cell (-i + pathspec on the purge engine, probed): ignored scope
  # intersects the pathspec — cache/x.pyc is removed, the out-of-scope
  # y.pyc survives.
  psx_setup
  echo '*.pyc' >.gitignore
  git add .gitignore
  # Path-limited commit: the fixture's staged src/a.py mod must NOT be
  # swept into this commit (the setup_pathspec_fixture LESSON).
  git commit -q -m gitignore -- .gitignore
  mkdir -p cache
  touch cache/x.pyc y.pyc
  run hug w purge -i -f -- cache/
  assert_success
  assert_output --partial "cache/x.pyc"
  [[ ! -e cache/x.pyc ]] # in-scope ignored file removed
  [[ -e y.pyc ]]         # out-of-scope ignored file survives
  psx_reset

  # OQ-2 refusal cell (probed): a pathspec COVERING a tracked file (the
  # staged src/a.py mod under src/) is a scope mistake — the family
  # usage-error template, exit 2 (was exit 1 pre-migration), and nothing
  # has been removed when it fires (staged mod intact).
  psx_setup
  run hug w purge -i -- src/
  assert_equal 2 "$status"
  assert_output --partial "tracked or has staged changes"
  run git status --porcelain -- src/a.py
  [[ "$output" == "M "* ]] # staged mod intact — nothing discarded
  psx_reset
}

@test "contract w-discard (Task 3): scoped destruction — validation, separator, two-sided scope" {
  # Full contract adoption (#292 PR-C Task 3, family template on git-sls):
  # loud typo'd magic, post-'--' flag rejection, scoped dry-run two-sided,
  # and the OQ-2 cells (-s/-u scoped destruction). Excluded dir is 'gen/'
  # not 'build/' — the developer's global gitignore ignores build/, and a
  # tracked-file fixture there would be rejected by the pre-commit hook.
  psx_setup
  # Typo'd magic prefix: git's own fatal + hug usage remedy, exit 2 — never
  # a silent "Nothing to discard" (was: exit 0, nothing discarded, user
  # none the wiser whether the scope matched).
  run hug w discard -- ':(exlude)x/'
  assert_equal 2 "$status"
  assert_output --partial "Invalid pathspec"
  refute_output --partial "Nothing to discard"
  run git status --porcelain -- src/a.py
  [[ "$output" == "M "* ]] # nothing discarded (staged mod intact — 'M ' porcelain form)
  psx_reset

  psx_setup
  # Post-'--' flag rejection: '--dry-run' after the separator is a
  # misordered flag, not data (was: silently became a pathspec and the
  # preview answered a false "Nothing to discard"). EXACT spellings only —
  # './--dry-run' stays a filename (pinned in the row below).
  run hug w discard -- src/ --dry-run
  assert_equal 2 "$status"
  assert_output --partial "Flags must precede '--'"
  psx_reset

  # -h/--help post-'--' (review IMPORTANT): same silent-swallow class —
  # 'hug w discard -- --help' used to answer "Nothing to discard" exit 0,
  # hiding the misordered flag entirely.
  psx_setup
  run hug w discard -- --help
  assert_equal 2 "$status"
  assert_output --partial "Flags must precede '--'"
  refute_output --partial "Nothing to discard"
  psx_reset

  psx_setup
  run hug w discard -- -h
  assert_equal 2 "$status"
  assert_output --partial "Flags must precede '--'"
  refute_output --partial "Nothing to discard"
  psx_reset

  # Per-command sync-guard loop RETIRED (Task 5): superseded by the
  # tri-command helper row — see the purge row's retirement note.

  # EXACT spellings only (review MINOR — the claim was asserted nowhere):
  # a tracked file literally named '--dry-run', spelled './--dry-run' after
  # the separator, is DATA — the preview lists it, no rejection.
  psx_setup
  echo dr1 > ./--dry-run
  git add -- ./--dry-run
  git commit -q -m "file named --dry-run" -- ./--dry-run
  echo dr2 >> ./--dry-run
  run hug w discard --dry-run -- ./--dry-run
  assert_success
  assert_output --partial "--dry-run"
  refute_output --partial "Flags must precede"
  psx_reset

  psx_setup
  # Scoped exclude-magic dry-run, two-sided: with an unstaged mod inside
  # gen/ and one outside, ':(exclude)gen/' previews ONLY the outside file.
  # (Flag BEFORE the separator — the AC's literal '-- <spec> --dry-run'
  # spelling is exactly the misordered-flag form rejected above.)
  mkdir -p gen
  echo g1 > gen/g.txt
  git add gen/g.txt
  # Path-limited commit: the fixture's staged src/a.py mod must NOT be
  # swept into this commit (the same LESSON setup_pathspec_fixture encodes).
  git commit -q -m gen -- gen/g.txt
  echo g2 >> gen/g.txt
  run hug w discard --dry-run -- ':(exclude)gen/'
  assert_success
  assert_output --partial "docs/note.md"
  refute_output --partial "gen/g.txt"
  refute_output --partial "src/a.py"
  psx_reset

  # OQ-2 cell (-s + pathspec on the discard engine, probed): staged-only
  # scope intersects the pathspec — src/a.py's staged delta is discarded,
  # the unstaged docs/note.md mod and untracked new.txt survive, and the
  # file content returns to its committed state.
  psx_setup
  run hug w discard -s -f -- src/
  assert_success
  assert_output --partial "src/a.py"
  assert_equal "py1" "$(cat src/a.py)"
  run git status --porcelain -- src/a.py
  [[ -z "$output" ]] # staged delta gone, no residual unstaged mod
  run git status --porcelain -- docs/note.md
  [[ "$output" == " M"* ]] # outside scope untouched
  psx_reset

  # OQ-2 cell (-u + pathspec): unstaged scope intersects likewise — only
  # the unstaged mod under src/ goes, the staged delta there survives.
  psx_setup
  echo py3 >> src/a.py # unstaged mod on top of the staged one
  run hug w discard -u -f -- src/
  assert_success
  run git status --porcelain -- src/a.py
  [[ "$output" == "M "* ]] # staged delta preserved, unstaged mod gone
  psx_reset
}

# FLIPS-IN-TASK-4 (landed in Task 7 with the whole w-*-all family): the
# four -all variants join the usage-error family — exit 2 (HUG_EX_USAGE) +
# the family template carrying the WHOLE-TREE pointer (was: exit 1
# "unknown option: -xX" per command — zap-all even reported only the first
# char "-x" via its char-splitting loop; `-- src/` and bare `--` alike died
# as "unknown option: --", exit 1). Design note (Task 5 quality review):
# the -all variants REJECT positionals — parse_scoped_own_flags does NOT
# apply (they collect no pathspecs); their pass is own-loop hygiene only.
@test "contract w-all (Task 7): -xX loud, exit 2, family template + whole-tree pointer" {
  local cmd scoped
  for cmd in discard-all purge-all zap-all wipe-all; do
    scoped="${cmd%-all}"
    psx_setup
    run hug w "$cmd" -xX
    assert_equal 2 "$status"
    assert_output --partial "Unknown option: -xX"
    assert_output --partial "hug w $cmd is whole-tree; use the scoped form to filter: hug w $scoped -- <path>..."
    refute_output --partial "Usage:" # one-line family template, not a help dump
    psx_reset
  done
}

@test "contract w-all (Task 7): -- <path> rejected with the whole-tree pointer" {
  # THE receipt that named this task (probed pre-migration: `purge-all --
  # src/` and `zap-all --` died "unknown option: --", exit 1): a pathspec
  # after the separator is a filter the whole-tree form cannot honor —
  # rejected exit 2, pointing at the scoped sibling with the user's own
  # pathspec echoed back.
  local cmd scoped
  for cmd in discard-all purge-all zap-all wipe-all; do
    scoped="${cmd%-all}"
    psx_setup
    run hug w "$cmd" -- src/
    assert_equal 2 "$status"
    assert_output --partial "hug w $cmd is whole-tree; use the scoped form to filter: hug w $scoped -- src/."
    assert_output --partial "See 'hug help :pathspec'"
    psx_reset
  done
}

@test "contract w-all (Task 7): post-'--' known-flag spellings get the same whole-tree rejection" {
  # They are not paths here (the -all variants collect no pathspecs), so a
  # flag spelling after the separator is the SAME whole-tree rejection —
  # never the scoped family's "Flags must precede '--'" remedy, which would
  # advise reordering a filter the command cannot take anyway.
  local cmd
  for cmd in discard-all purge-all zap-all wipe-all; do
    psx_setup
    run hug w "$cmd" -- --dry-run
    assert_equal 2 "$status"
    assert_output --partial "is whole-tree"
    psx_reset
  done
}

@test "contract w-all (Task 7): bare trailing -- inert (status + output parity)" {
  # Probed pre-migration: bare `--` died "unknown option: --", exit 1 on all
  # four. Contract: the bare separator is consumed and inert — `hug w
  # <cmd>-all --dry-run --` ≡ `hug w <cmd>-all --dry-run` byte-for-byte
  # (the --dry-run sides keep the comparison deterministic headless).
  local base_status base_output
  for cmd in discard-all purge-all zap-all wipe-all; do
    psx_setup
    run hug w "$cmd" --dry-run
    assert_success
    base_status=$status
    base_output=$output
    run hug w "$cmd" --dry-run --
    assert_equal "$base_status" "$status"
    assert_equal "$base_output" "$output"
    psx_reset
  done
}

@test "contract w-all (Task 7): bare positional rejected with the whole-tree pointer (wipe-all names WIPE)" {
  # Positionals are pathspecs without the separator — same whole-tree
  # rejection (was: exit 1 "positional arguments are not accepted"). The
  # wipe-all cell is the wrong-name hazard pin: wipe-all used to delegate
  # its whole parse to discard-all and its rejection said "use 'git w
  # discard'" — the WRONG scoped sibling. Own-loop hygiene: every -all
  # command names its OWN scoped form.
  local cmd scoped
  for cmd in discard-all purge-all zap-all wipe-all; do
    scoped="${cmd%-all}"
    psx_setup
    run hug w "$cmd" src/
    assert_equal 2 "$status"
    assert_output --partial "hug w $cmd is whole-tree; use the scoped form to filter: hug w $scoped -- src/."
    psx_reset
  done
}

@test "contract wip family (Task 8): -xX loud, exit 2 (wip unwip wipdel)" {
  # Landed (Task 8, #292 PR-C): the wip family keeps its `--` DATA semantics
  # (message for wip, branch for unwip/wipdel — spec §2 Class 2b) and only
  # the unknown-option path joined the exit-2 family: flag-shaped tokens are
  # rejected as flags before message/branch resolution.
  local cmd
  for cmd in wip unwip wipdel; do
    psx_setup
    run hug w "$cmd" -xX
    assert_equal 2 "$status"
    assert_output --partial "Unknown option: -xX"
    refute_output --partial "does not exist" # not misread as a branch name
    psx_reset
  done
  # w-wip's pre-migration failure mode was a FULL help dump — the contract
  # error is the one-line family template, not the manual.
  psx_setup
  run hug w wip -xX
  assert_equal 2 "$status"
  refute_output --partial "USAGE:"
  psx_reset
}

# FLIPS-IN-TASK-6 (landed, w-get migration, #292 PR-C plan Task 9): w-get's
# commitish-target slot used to swallow unknown dash tokens — probed
# pre-migration: `w get -xX` → "Invalid commitish for --target: -xX", exit 1
# — and post-'--' flag spellings became file names (`w get HEAD --
# --dry-run` → "File '--dry-run' does not exist in commit", exit 1). The
# family template now rejects both as usage errors (exit 2).
@test "contract w-get (Task 9): -xX is a flag error, not a bad commitish" {
  psx_setup
  run hug w get -xX
  assert_equal 2 "$status"
  assert_output --partial "Unknown option: -xX"
  refute_output --partial "Invalid commitish"
  psx_reset
}

@test "contract w-get (Task 9): misordered post-'--' flags and malformed magic are usage errors (#292)" {
  # Probed pre-migration (all exit 1, all mis-diagnosed):
  #   w get -- --dry-run      → "Invalid commitish for --target: --dry-run"
  #                             (the flag fell into the EMPTY commitish slot)
  #   w get HEAD -- --dry-run → "File '--dry-run' does not exist in commit"
  #   w get HEAD~1 -- -u      → "File '-u' does not exist in commit"
  #   w get HEAD -- ':(bogus)src/' → "File ':(bogus)src/' does not exist"
  #                             (malformed pathspec magic died as a missing
  #                             FILE; ':bogus(' without parens is a LITERAL
  #                             path to git, which is why the fixture uses
  #                             the ':(bogus)src/' form the family shares)
  psx_setup
  run hug w get -- --dry-run
  assert_equal 2 "$status"
  assert_output --partial "Flags must precede '--': hug w get --dry-run"
  refute_output --partial "Invalid commitish"
  psx_reset

  psx_setup
  run hug w get HEAD -- --dry-run
  assert_equal 2 "$status"
  assert_output --partial "Flags must precede '--': hug w get --dry-run"
  psx_reset

  psx_setup
  run hug w get HEAD~1 -- -u
  assert_equal 2 "$status"
  assert_output --partial "Flags must precede '--': hug w get -u"
  psx_reset

  # Entry pathspec validation (validate_pathspecs_or_die, post-check_git_repo):
  # a typo'd magic prefix dies as a usage error BEFORE any "Will reset"
  # chatter or missing-file confusion downstream.
  psx_setup
  run hug w get HEAD -- ':(bogus)src/'
  assert_equal 2 "$status"
  assert_output --partial "Invalid pathspec"
  refute_output --partial "does not exist in commit"
  refute_output --partial "Will reset"
  psx_reset
}

@test "contract w-get (P2 #3820511903): magic pathspecs expand to in-commit files, never flow literally (#292)" {
  # Probed pre-fix: `w get HEAD -- ':(glob)*.py'` passed entry validation
  # (syntax OK) then flowed LITERALLY into the per-file workflow —
  # "File ':(glob)*.py' does not exist in commit HEAD", exit 1. The fix
  # resolves the pathspec set against the TARGET commit's tree and feeds
  # the concrete files into the existing check/preview/restore flow.
  # NON-magic spellings are untouched by construction (byte-identity).

  # Cell 1 — glob magic restores its matches (two-sided scope), preview
  # per-FILE (the expansion yields src/a.py, not the magic text).
  psx_setup
  git add -A
  git commit -q -m divergence
  run hug w get --dry-run HEAD~1 -- ':(glob)**/*.py'
  assert_success
  assert_output --partial "Checking src/a.py"
  assert_output --partial "src/a.py"
  refute_output --partial "docs/"
  refute_output --partial ":(glob)"
  run hug w get HEAD~1 -- ':(glob)**/*.py'
  assert_success
  assert_equal "py1" "$(cat src/a.py)" # restored to the base version
  psx_reset

  # Cell 2 — exclude magic restores everything-but (the whole tree minus
  # docs/), still through the specific-files preview shape.
  psx_setup
  git add -A
  git commit -q -m divergence
  run hug w get --dry-run HEAD~1 -- ':!docs/'
  assert_success
  assert_output --partial "src/a.py"
  refute_output --partial "docs/"
  psx_reset

  # Cell 3 — empty expansion is the honest no-match info (exit 0), not a
  # missing-file error and not a silent success-with-nothing.
  psx_setup
  run hug w get HEAD~1 -- ':(glob)**/*.nomatch'
  assert_success
  assert_output --partial "No files in"
  assert_output --partial "match"
  refute_output --partial "does not exist in commit"
  refute_output --partial "Will reset"
  psx_reset

  # Cell 4 — byte-identity guard: a LITERAL missing file keeps today's
  # loud per-file error (exit 1) — only magic spellings take the
  # expansion branch.
  psx_setup
  run hug w get HEAD no-such-file
  assert_equal 1 "$status"
  assert_output --partial "File 'no-such-file' does not exist in commit"
  psx_reset
}

@test "contract w-get (Task 9): trailing bare '--' keeps the picker; action flags stay position-independent (#292)" {
  # OQ-1 (probed): `w get HEAD --` opens the interactive selector — under
  # BATS (no TTY; gum absent or cancelling) it lands on "No files
  # selected..." exit 0. The --picker split mode preserves that trigger: a
  # bare trailing '--' never becomes a phantom pathspec, so the reset-all
  # arm is NOT reached (refuted by "Will reset"/"Files that will be").
  psx_setup
  run hug w get HEAD --
  assert_success
  assert_output --partial "No files selected"
  refute_output --partial "Will reset"
  refute_output --partial "Files that will be"
  psx_reset

  # Action flags remain position-independent around the target and files
  # (byte-identical to the pre-migration parser, which getopt-permuted
  # them). --dry-run BEFORE the target: same specific-files dry-run shape
  # as the existing HEAD~1 --dry-run cell.
  psx_setup
  git add -A
  git commit -q -m divergence
  run hug w get --dry-run HEAD~1 src/a.py
  assert_success
  assert_output --partial "Files to be reset:"
  assert_output --partial "src/a.py"
  assert_output --partial "Dry run — no files were modified."
  grep -q py2 src/a.py
  psx_reset

  # -y is accepted alongside (a routine-confirm flag, not a force
  # substitute — see help); on the clean path it changes nothing.
  psx_setup
  git add -A
  git commit -q -m divergence
  run hug w get -y --dry-run HEAD~1 src/a.py
  assert_success
  assert_output --partial "Dry run — no files were modified."
  psx_reset
}

# FLIPS-IN-TASK-10 (landed, #292 PR-C): llu honors the separator and filters
# two-sided — was: flags-only parser rejected it ("Unknown option: --", exit
# 1; the characterization llu row above flipped in the same task). The
# fixture's upstream anchor (setup_pathspec_fixture) makes base + "docs guide
# only" exactly the outgoing set, so the rows below are two-sided THROUGH the
# outgoing semantics, not just through path filtering.

@test "contract llu (Task 10): -- src/ filters two-sided, summary suppressed" {
  # Scoped outgoing list: the src commit (base) stays, the docs-only commit
  # vanishes. Summary gate (codex #3815936636): a scoped run must NOT print
  # the whole-repo status after the scoped list.
  psx_setup
  run hug llu -- src/
  assert_success
  assert_output --partial "base"
  refute_output --partial "docs guide only"
  refute_output --partial "HEAD:"
  psx_reset
}

@test "contract llu (Task 10): bare trailing -- inert with summary parity" {
  # The inert duality (llu is a listing, NOT a picker): a trailing bare '--'
  # alone is fully inert — byte-identical to the unfiltered run INCLUDING the
  # summary (both runs share ONE fixture; the summary embeds the HEAD short
  # hash). Proves the summary suppression above is scope-driven, not a
  # blanket removal.
  psx_setup
  run hug llu
  assert_success
  local unfiltered="$output"
  assert_output --partial "HEAD:"
  run hug llu --
  assert_success
  assert_equal "$unfiltered" "$output"
  psx_reset
}

@test "contract llu (Task 10): --json honors pathspecs; empty scope keeps envelope" {
  # Scoped JSON: zero non-JSON bytes (whole payload parses), two-sided
  # through the outgoing semantics (base in, docs-only commit out), and the
  # summary count reflects the SCOPE (1, not the unscoped 2 — the JSON sink
  # must not describe the whole outgoing range). Empty scope keeps the
  # envelope shape (umbrella §6.2: zero-length commits array, count 0).
  psx_setup
  run hug llu --json -- src/
  assert_success
  local json_out="$output"
  run bash -c "printf '%s' \"\$1\" | python3 -m json.tool > /dev/null" _ "$json_out"
  assert_success
  [[ "$json_out" == *"base"* ]]
  [[ "$json_out" != *"docs guide only"* ]]
  run python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(len(d['commits']), d['summary']['total_commits'])" "$json_out"
  assert_output "1 1"
  psx_reset

  psx_setup
  run hug llu --json -- nomatch/
  assert_success
  json_out="$output"
  run bash -c "printf '%s' \"\$1\" | python3 -m json.tool > /dev/null" _ "$json_out"
  assert_success
  run python3 -c "import json,sys; d=json.loads(sys.argv[1]); print('commits' in d, d['commits'], d['summary']['total_commits'])" "$json_out"
  assert_output "True [] 0"
  psx_reset
}

# FLIPS-IN-TASK-11 (landed, #292 PR-C): sh accepts pathspecs after the
# separator — was: ONE commit ref only ("unexpected extra argument:
# 'src/'", exit 1; the two contract-sh BUG-6 rows above flipped in the
# SAME task per the flip rule). The rows below pin the parts the shared
# SHOW column loops cannot express: multi-path union, the -N DATA arm
# (sh is the one PR-C command with legal dash-data, spec Class 3), the
# disambiguation rule (ALL tokens after the first ref are pathspecs), and
# the loud exit-2 rejections.

@test "contract sh (Task 11): HEAD~1 -- src/ filters two-sided" {
  psx_setup
  run hug sh HEAD~1 -- src/
  assert_success
  assert_output --partial "src/a.py"
  refute_output --partial "docs/note.md"
  psx_reset
}

@test "contract sh (Task 11): two pathspecs union — BOTH paths, third path excluded" {
  # codex #3815936643: base (HEAD~1) touched src/, docs/ AND other.txt —
  # a multi-path call must show the UNION (src + docs) and drop the
  # third path. With the old single-file_path library interface this row
  # is red: only the FIRST path survived.
  psx_setup
  run hug sh HEAD~1 -- src/ docs/
  assert_success
  assert_output --partial "src/a.py"
  assert_output --partial "docs/note.md"
  refute_output --partial "other.txt"
  psx_reset
}

@test "contract sh (Task 11): -N range spellings are DATA — never eaten by the -* rejection" {
  # Spec Class 3: sh is the one PR-C command with legal dash-data. The
  # explicit data-arm sits BEFORE the -* rejection arm, so '-3' reaches
  # resolve_commit_ref as HEAD~3..HEAD (not "Unknown flag: -3", exit 2).
  # Fixture depth: base + docs-only + two tests-only commits = 4, so
  # HEAD~3..HEAD spans docs, tests1, tests2; scoped to {src/, docs/} the
  # union keeps ONLY the docs-only commit — the two tests-only commits
  # (third path) must vanish. Two-sided through the range filter itself.
  psx_setup
  mkdir -p tests
  echo t1 > tests/one.t
  git add tests/one.t
  # Path-scoped commit (with -- tests/): the fixture's STAGED src/a.py mod
  # must NOT be swept into the tests-only commit — the setup's own LESSON
  # (see setup_pathspec_fixture), which applies to extensions too: an
  # unscoped `git commit` here would make "tests one" touch src/ and the
  # src/∪docs/ union would legitimately keep it, breaking the row.
  git commit -q -m "tests one" -- tests/one.t
  echo t2 > tests/two.t
  git add tests/two.t
  git commit -q -m "tests two" -- tests/two.t
  run hug sh -3 -- src/ docs/
  assert_success
  assert_output --partial "docs guide only"
  refute_output --partial "tests one"
  refute_output --partial "tests two"
  refute_output --partial "Unknown flag"
  psx_reset
}

@test "contract sh (Task 11): disambiguation — every token after the first ref is a pathspec" {
  # codex #3815936650: no syntactic second-ref detection exists, so none
  # is attempted. `sh HEAD~1 other.txt docs/note.md` treats BOTH trailing
  # tokens as pathspecs (union: other.txt + docs/note.md in, src/a.py
  # out) and exits 0 with whatever matches — pinned honestly.
  psx_setup
  run hug sh HEAD~1 other.txt docs/note.md
  assert_success
  assert_output --partial "other.txt"
  assert_output --partial "docs/note.md"
  refute_output --partial "src/a.py"
  psx_reset
}

@test "contract sh (Task 11): loud rejections — unknown dash token and malformed magic, exit 2" {
  # '-xX' (non-numeric dash) → the family usage error, help + exit 2
  # (pre-migration this already exited 2 via show_single_commit's
  # reject_flag_ref — now at the entry loop, same observable). '-3' is
  # immune (data arm, row above). ':(bogus)' → validate_pathspecs_or_die.
  psx_setup
  run hug sh -xX
  assert_equal 2 "$status"
  assert_output --partial "Unknown flag: -xX"
  psx_reset

  psx_setup
  run hug sh HEAD~1 -- ':(bogus)x/'
  assert_equal 2 "$status"
  assert_output --partial "Invalid pathspec"
  psx_reset
}

@test "contract sh (Task 11): unscoped run and trailing bare -- byte-identical" {
  # Unscoped `hug sh HEAD~1` output must be unchanged by the migration,
  # and a trailing bare '--' inert (sh is a viewer, no picker arm) —
  # asserted as byte-identity between the two invocations of ONE fixture
  # (relative-time normalized: the clock ticks between captures).
  psx_setup
  run hug sh HEAD~1
  assert_success
  local unfiltered
  unfiltered=$(printf '%s' "$output" | psx_strip_reltime)
  run hug sh HEAD~1 --
  assert_success
  assert_equal "$unfiltered" "$(printf '%s' "$output" | psx_strip_reltime)"
  psx_reset
}

@test "PR-C staged red rows: exact marker set (3 4 5 6 10 11)" {
  # Loss guard, EXACT form: an existence-only check stays green when ONE
  # task's staged rows are deleted (review round 1 finding). The observed
  # marker set must equal the literal expectation — built via a loop over
  # task NUMBERS so the expected strings never literally appear in this file
  # (a literal 'FLIPS-IN-TASK-3' here would be grep-matched too, making the
  # check self-fulfilling). Failing output names both sides.
  # Landed tasks (3 discard, 4 purge, 5 zap) keep their markers in the
  # "(landed, ...)" comment lines — the set is the drift alarm, not the
  # pending-work list.
  local self="${BATS_TEST_FILENAME}"
  local expected actual
  expected=$(for n in 3 4 5 6 10 11; do printf 'FLIPS-IN-TASK-%s\n' "$n"; done | sort)
  actual=$(grep -oE 'FLIPS-IN-TASK-[0-9]+' "$self" | sort -u)
  [[ -n "$actual" ]] || fail "no staged FLIPS markers found — the PR-C red rows were lost"
  if [[ "$actual" != "$expected" ]]; then
    fail "staged FLIPS marker set drifted — expected vs actual:
$(printf '%s\n' "$expected" | tr '\n' ' ')
$(printf '%s\n' "$actual" | tr '\n' ' ')"
  fi
  grep -q "RED rows staged for PR-C migrations" "$self" ||
    fail "staged block header comment missing"
}
