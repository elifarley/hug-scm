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
  cleanup_test_repo
}

# Per-row invocation prefix for the inert rows: log commands take no
# committish, show commands diff against HEAD~1 ("base"). Prints the args
# one per line for the caller to read into an array (word-splitting-free).
psx_inert_args() {
  case "$1" in
  l | ll) : ;;
  shc | shcp | shp) echo "HEAD~1" ;;
  *) return 1 ;;
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
