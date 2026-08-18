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
PATHSPEC_PICKER_ROWS=(sw ss su)
PATHSPEC_LOG_ROWS=(l ll)
PATHSPEC_SHOW_ROWS=(shc shcp shp)
PATHSPEC_INERT_ROWS=("${PATHSPEC_LOG_ROWS[@]}" "${PATHSPEC_SHOW_ROWS[@]}")
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
# commands take exactly ONE file; two files → hug's own rejection (exit 1,
# "<cmd> accepts only one file.") instead of git fatals or silent ignores.
#   SINGLEFILE_ROWS       — one-word commands guarded directly via
#                          reject_multiple_files (loop-able as `hug $cmd`)
#   SINGLEFILE_DELEGATE_ROWS — commands delegating to llf; the delegation
#                              inserts a flag before the extras, so post-flag
#                              extras fall through to git (see dedicated test)
# Multi-word commands (h steps, stats file) get dedicated tests below —
# they don't fit the one-word loop.
PATHSPEC_SINGLEFILE_ROWS=(fa fb fblame fborn fcon llf)
PATHSPEC_SINGLEFILE_DELEGATE_ROWS=(llfp llfs)

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
  l | ll) : ;;
  shc | shcp | shp) echo "HEAD~1" ;;
  *)
    echo "psx_inert_args: unknown row '$1' — add it to the case arms" >&2
    echo "__PSX_UNKNOWN_ROW__"
    ;;
  esac
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
    case "$cmd" in
    ss) filter="src/" present="src/a.py" absent="docs/note.md" ;;
    su | sw) filter="docs/" present="docs/note.md" absent="src/a.py" ;;
    esac
    psx_setup
    run hug "$cmd" -- "$filter"
    assert_success
    assert_output --partial "$present"
    refute_output --partial "$absent"
    psx_reset
  done
}

@test "column pathspec-filter: log commands (log rows)" {
  for cmd in "${PATHSPEC_LOG_ROWS[@]}"; do
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
  for cmd in "${PATHSPEC_SHOW_ROWS[@]}"; do
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
    case "$cmd" in
    ss) glob='*.py' present="src/a.py" absent="docs/note.md" ;;
    su | sw) glob='*.md' present="docs/note.md" absent="src/a.py" ;;
    esac
    psx_setup
    run hug "$cmd" -- "$glob"
    assert_success
    assert_output --partial "$present"
    refute_output --partial "$absent"
    psx_reset
  done
}

@test "column glob-filter: log commands (log rows)" {
  for cmd in "${PATHSPEC_LOG_ROWS[@]}"; do
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
  for cmd in "${PATHSPEC_SHOW_ROWS[@]}"; do
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
  # assert the POSITIVE observable — the diff driver's "No … available or
  # cancelled." message — because absence-only passes on a crash. Probed:
  # exit 0 with that message on stderr in BOTH gum branches (gum installed →
  # TTY failure; gum absent → gum-missing error, same message after). The
  # message assert is deliberately loose (--partial "available or cancelled")
  # so a UI copy tweak breaks one place, not three cells.
  local refute_marker
  for cmd in "${PATHSPEC_PICKER_ROWS[@]}"; do
    case "$cmd" in
    ss) refute_marker="Staged diff" ;;
    su | sw) refute_marker="Unstaged diff" ;;
    esac
    psx_setup
    run hug "$cmd" --
    assert_success
    refute_output --partial "$refute_marker"
    assert_output --partial "available or cancelled"
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
    plain="$output"
    run hug "$cmd" "${args[@]}" --
    assert_success
    assert_equal "$plain" "$output"
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
  local filter="src/" absent="docs/note.md" present candidates
  for cmd in "${PATHSPEC_PICKER_ROWS[@]}"; do
    present="$filter"
    case "$cmd" in
    su) present="src/BIG.py" ;;
    ss | sw) present="src/a.py" ;;
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
    su) echo big2 >> src/BIG.py ;;
    ss) git add docs/note.md ;;
    esac

    psx_install_stub_gum
    run hug "$cmd" -- "$filter" --
    assert_success
    assert_output --partial "available or cancelled"

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
  local icase present
  for cmd in "${PATHSPEC_PICKER_ROWS[@]}"; do
    case "$cmd" in
    ss) icase=':(icase)SRC/A.PY' present="src/a.py" ;;
    su | sw) icase=':(icase)DOCS/NOTE.MD' present="docs/note.md" ;;
    esac
    psx_setup
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
  for cmd in "${PATHSPEC_SHOW_ROWS[@]}"; do
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

@test "characterization sl-family: -- src/ filters by coincidence (sl sla)" {
  # characterization: flip target PR-B — sl/sla (statusbase) were migrated by
  # PR-B Task 4 and now filter for the RIGHT reason (the split consumes the
  # separator; see the statusbase conformance tests). sls was retired from
  # this row by Task 5 (migrated — see the sls-family conformance tests).
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

@test "characterization sl-family: slc -h shows USAGE" {
  # characterization (sl/sla arm FLIPPED by PR-B Task 4 — see the statusbase
  # conformance tests below): probed: `slc -h` shows USAGE on stdout (exit 0).
  # The former sl/sla arm asserted the swallow ("matching '-h' found."),
  # which statusbase's show_help + uniform parse replaced.
  psx_setup
  run hug slc -h
  assert_success
  assert_output --partial "USAGE:"
  psx_reset
}

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
    assert_output --partial "see 'hug $cmd -h'"
    psx_reset
  done
}

@test "conformance sls-family (Task 5): -- src/ filters; phantom '--' gone from message" {
  # FLIPPED (Task 5): the split consumes the separator, so it never rides in
  # the pathspec list. sls filters two-sided (staged src/a.py is in scope);
  # slu/slk/sli have NO matching file, and their empty-info message now says
  # matching 'src/' WITHOUT the phantom '--' — the "No unstaged files
  # matching '--' 'src/'" fingerprint (probed pre-migration) is gone.
  psx_setup
  run hug sls -- src/
  assert_success
  assert_output --partial "src/a.py"
  refute_output --partial "docs/note.md"
  refute_output --partial "matching '--'"
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


@test "characterization us: bare/trailing -- rejected loudly" {
  # characterization: flip target PR-B — probed: git-us's flag loop hits the
  # `-*` arm and errors on `--` BEFORE any pathspec logic ("Unknown option:
  # --. See 'hug us --help'.", exit 1) for BOTH `us --` and `us -- src/`.
  # Contract column 4 (trailing `--` = picker/inert) does not hold today.
  psx_setup
  run hug us -- src/
  assert_failure
  assert_output --partial "Unknown option: --. See 'hug us --help'."
  psx_reset

  psx_setup
  run hug us --
  assert_failure
  assert_output --partial "Unknown option: --. See 'hug us --help'."
  psx_reset
}

@test "characterization us: positional pathspec unstages (works today)" {
  # characterization: flip target PR-B — the POSITIVE arm that must survive
  # the migration: `us src/a.py` (no separator) unstages exactly that file
  # (probed: exit 0, "Unstaged 1 file", and hug sls no longer lists it).
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
  # (spec §5.2 lists the no-upstream case explicitly).
  psx_setup
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

  # Cell 5 — BUG-4: a file literally named `-weird` restores safely (the
  # restore gains an explicit `--` so dash-leading paths are never flags).
  psx_setup
  echo wbase > ./-weird
  git add -- -weird
  git commit -q -m "add -weird"
  echo wdiverged > ./-weird
  git commit -q -am "diverge -weird"
  run hug w get HEAD~1 -weird
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

@test "contract sh: second positional rejected loudly, naming the argument (BUG-6 fixed, Task 9)" {
  # Contract (was characterization, flipped by Task 9): `sh HEAD -- src/`
  # and `sh HEAD src/` are rejected because hug sh accepts ONE commit
  # reference. The error must name the stray argument ("unexpected extra
  # argument: 'src/'") and must NOT fall back to the old confusing
  # "Invalid commit reference" ref-validation failure.
  psx_setup
  run hug sh HEAD -- src/
  assert_failure
  assert_output --partial "unexpected extra argument"
  assert_output --partial "src/"
  refute_output --partial "Invalid commit reference"
  psx_reset

  psx_setup
  run hug sh HEAD src/
  assert_failure
  assert_output --partial "unexpected extra argument"
  assert_output --partial "src/"
  refute_output --partial "Invalid commit reference"
  psx_reset
}

@test "contract sh: empty first positional + path still rejected loudly (BUG-6, review fix)" {
  # Contract (added after dual review): the guard must count POSITIONALS,
  # not ref content. `hug sh "" src/` (realistic: `hug sh "$ref" -- "$path"`
  # with an unset/empty ref) previously slipped past the -n guard, let the
  # path overwrite the empty ref, and died with the old confusing
  # "Invalid commit reference". Must get the named rejection instead.
  # Companion invariant: `hug sh ""` ALONE still defaults to HEAD (probed).
  psx_setup
  run hug sh "" src/
  assert_failure
  assert_output --partial "unexpected extra argument"
  assert_output --partial "src/"
  refute_output --partial "Invalid commit reference"
  psx_reset

  psx_setup
  run hug sh ""
  assert_success
  assert_output --partial "Commit info"
  psx_reset
}

@test "characterization llu: -- rejected loudly by flags-only parser (flip: PR-C)" {
  # characterization: flip target PR-C — probed: git-llu's flags-only loop
  # (git-llu:104) rejects the separator it should honor: "Unknown option:
  # --" + usage hint, exit 1. Pathspec filtering is unreachable today.
  psx_setup
  run hug llu -- src/
  assert_failure
  assert_output --partial "Unknown option: --"
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
  # clear, command-naming error (exit 1).
  for cmd in "${PATHSPEC_SINGLEFILE_ROWS[@]}"; do
    psx_setup
    run hug "$cmd" src/a.py docs/note.md
    assert_equal 1 "$status"
    assert_output --partial "hug $cmd accepts only one file."
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
  assert_equal 1 "$status"
  assert_output --partial "hug llf accepts only one file."
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
  assert_equal 1 "$status"
  assert_output --partial "hug h steps accepts only one file."
  psx_reset
}

@test "single-file cardinality: stats file rejects extra files (Task 10)" {
  # FLIPPED (Task 10): `hug stats file a b` used to churn-analyze ONLY a;
  # the extras vanished without a word. Now two files → exit 1 + rejection.
  psx_setup
  run hug stats file src/a.py docs/note.md
  assert_equal 1 "$status"
  assert_output --partial "hug stats file accepts only one file."
  refute_output --partial "Churn analysis"
  psx_reset
}

@test "single-file cardinality: fblame churn mode is guarded too (combo gap, #298 Task 3c)" {
  # fblame's guard sits BEFORE the churn/blame fork (#292), so --churn must
  # not open a bypass: two files under --churn → the same hug rejection the
  # blame mode gets (NOT churn.py silently analyzing only the first file).
  psx_setup
  run hug fblame --churn src/a.py docs/note.md
  assert_equal 1 "$status"
  assert_output --partial "hug fblame accepts only one file."
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

@test "characterization fcat: colon syntax rejected; unknown flag dies as ref error" {
  # characterization: probed — `fcat HEAD:src/a.py` (single colon-arg) is
  # NOT the CLI form: loud "Missing arguments" (exit 1). `-xX` is collected
  # as a positional target and dies in ref resolution (exit 1, "Unable to
  # resolve reference '-xX'") — loud but not flag-naming; flip target:
  # #292 follow-up (column 6 wants a flag-naming rejection).
  psx_setup
  run hug fcat HEAD:src/a.py
  assert_failure
  assert_output --partial "Missing arguments"
  psx_reset

  psx_setup
  run hug fcat -xX src/a.py
  assert_failure
  assert_output --partial "Unable to resolve reference '-xX'"
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

@test "characterization w discard: unknown flag swallowed (exit 0); bare '--' opens picker" {
  # characterization — column-6 defect: probed — `-xX` becomes a pathspec in
  # parse_common_flags' fallback loop, matches nothing, exit 0 "Nothing to
  # discard" (silent swallow; flip target: #292). The picker arm matches the
  # `a`/sw family: exit 0 + "No files selected."
  psx_setup
  run hug w discard -xX
  assert_success
  assert_output --partial "Nothing to discard"
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
  # file ('.') is refused loudly (exit 1, "tracked or has staged changes");
  # `-xX` is swallowed as a path (exit 0 "Nothing to purge"; flip: #292).
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
  assert_success
  assert_output --partial "Nothing to purge"
  psx_reset
}

@test "characterization w wipe: delegation to discard — filter + swallow inherit" {
  # characterization: probed — wipe = `w discard -u -s "$@`, so the pathspec
  # filter and the "-xX → Nothing to discard" swallow are BOTH inherited
  # from discard (flip: #292, with discard).
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
  assert_success
  assert_output --partial "Nothing to discard"
  psx_reset
}

@test "characterization w zap: combined preview, scoped filter, and swallow" {
  # characterization: probed — `zap --dry-run .` previews all three buckets
  # (staged src/a.py, unstaged docs/note.md, untracked new.txt); a scoped
  # pathspec narrows to that file only; `-xX` is swallowed (exit 0 "Nothing
  # to zap"; flip: #292).
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
  assert_success
  assert_output --partial "Nothing to zap"
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

  # Cell 3 — '-u' AFTER the separator is a FILE name, not the flag: the
  # non-upstream specific-files restore proceeds for a file literally
  # named '-u' (same shape as the '-weird' regression cell).
  psx_setup
  echo ubase > ./-u
  git add -- -u
  git commit -q -m "add file named -u"
  echo udiverged > ./-u
  git commit -q -am "diverge -u"
  run hug w get HEAD~1 -- -u
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
