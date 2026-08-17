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
#   CHAR_SL_EMPTY_ROWS    — sl family where `-- src/` yields empty output;
#                           the info message NAMES the phantom '--'
#   CHAR_SL_SWALLOW_ROWS  — sl family with no flag parser: unknown flags
#                           become pathspecs (exit 0)
#   CHAR_SL_HELP_ROWS     — whole sl family: `--help` never reaches the
#                           script (git man routing)
#   CHAR_FATAL_ROWS       — single-file commands: two files → git FATAL
PATHSPEC_CHAR_SL_FILTER_ROWS=(sl sla sls)
PATHSPEC_CHAR_SL_EMPTY_ROWS=(slu slk sli)
PATHSPEC_CHAR_SL_SWALLOW_ROWS=(sls slu slk sli)
PATHSPEC_CHAR_SL_HELP_ROWS=(sl sla sls slu slk sli)
PATHSPEC_CHAR_FATAL_ROWS=(fa fb fblame fborn fcon llf)

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

@test "characterization sl-family: -- src/ filters by coincidence (sl sla sls)" {
  # characterization: flip target PR-B — after migration the `--` is consumed
  # by a real parser and these keep passing for the RIGHT reason; today the
  # bare `--` is collected as a pathspec and git ORs the phantom away
  # (probed: exit 0, staged src/a.py shown, unstaged docs/note.md filtered
  # out even on sl/sla which would otherwise list it).
  for cmd in "${PATHSPEC_CHAR_SL_FILTER_ROWS[@]}"; do
    psx_setup
    run hug "$cmd" -- src/
    assert_success
    assert_output --partial "src/a.py"
    refute_output --partial "docs/note.md"
    psx_reset
  done
}

@test "characterization sl-family: -- src/ empty + message names phantom '--' (slu slk sli)" {
  # characterization: flip target PR-B — these variants have NO file matching
  # src/, so the phantom `--` pathspec becomes visible in the info message
  # (probed: exit 0, empty stdout, "No <kind> files matching '--' 'src/'
  # found." — the '--' listed AS a filter is the defect's fingerprint).
  local kind
  for cmd in "${PATHSPEC_CHAR_SL_EMPTY_ROWS[@]}"; do
    kind=$(psx_sl_kind "$cmd")
    psx_setup
    run hug "$cmd" -- src/
    assert_success
    refute_output --partial "docs/note.md"
    refute_output --partial "new.txt"
    assert_output --partial "No ${kind} files matching '--' 'src/' found."
    psx_reset
  done
}

@test "characterization sl-family: unknown flag swallowed as pathspec, exit 0 (sls slu slk sli)" {
  # characterization: flip target PR-B — these commands have no flag parser,
  # so `-xX` silently becomes a pathspec (probed: exit 0 + "No <kind> files
  # matching '-xX' found."). Contract column 6 requires non-zero; today it is
  # ZERO — pinned here so the PR-B flip is a deliberate red.
  local kind
  for cmd in "${PATHSPEC_CHAR_SL_SWALLOW_ROWS[@]}"; do
    kind=$(psx_sl_kind "$cmd")
    psx_setup
    run hug "$cmd" -xX
    assert_success
    assert_output --partial "No ${kind} files matching '-xX' found."
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
    assert_equal 16 "$status"
    refute_output --partial "USAGE:"
    psx_reset
  done
}

@test "characterization sl-family: only slc has real -h help; sl/sla -h swallowed" {
  # characterization: flip target PR-B — probed: `slc -h` shows USAGE on
  # stdout (exit 0). `sl`/`sla` are gitconfig aliases to statusbase, which
  # has no -h handling: the flag is swallowed as a pathspec (exit 0 +
  # "matching '-h' found"). The audited spec's "sl/sla have help" holds only
  # for `--help`-adjacent docs, not for the runtime `-h` surface.
  psx_setup
  run hug slc -h
  assert_success
  assert_output --partial "USAGE:"
  psx_reset

  for cmd in sl sla; do
    psx_setup
    run hug "$cmd" -h
    assert_success
    assert_output --partial "matching '-h' found."
    psx_reset
  done
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

@test "characterization w get: -u with a path / -u alone both error (flip: Task 8)" {
  # characterization: flip target THIS PR (Task 8) — probed: with `-u`, the
  # first non-flag arg becomes the TARGET IDENTIFIER, so the file is mistaken
  # for a commit ("Cannot specify --upstream with a specific commit or
  # integer N.", exit 1 — git-w-get:389-390). And `-u` alone dies on the
  # missing-target check ("Missing target argument", exit 1 — the documented
  # `hug w get -u` reset-all form is broken today, git-w-get:371-375).
  psx_setup
  run hug w get -u src/a.py
  assert_failure
  assert_output --partial "Cannot specify --upstream with a specific commit or integer N."
  psx_reset

  psx_setup
  run hug w get -u
  assert_failure
  assert_output --partial "Missing target argument"
  psx_reset
}

@test "characterization sh: trailing positional overwrites the ref, loud error (BUG-6, flip: Task 9)" {
  # characterization: flip target THIS PR (Task 9) — probed: `sh HEAD -- src/`
  # and `sh HEAD src/` BOTH fail with "Invalid commit reference: src/"
  # (exit 1): the LAST positional wins as the ref, so the path is validated
  # as a committish. Loud rejection exists today; the fix must keep rejecting
  # while treating the path as a pathspec filter.
  psx_setup
  run hug sh HEAD -- src/
  assert_failure
  assert_output --partial "Invalid commit reference: src/"
  psx_reset

  psx_setup
  run hug sh HEAD src/
  assert_failure
  assert_output --partial "Invalid commit reference: src/"
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

@test "characterization lc/lf/lcr: mid-stream -- consumed yet filter still applies (BUG-2, flip: Task 7)" {
  # characterization: flip target THIS PR (Task 7) — probed: `lc py -- src/`
  # (and lcr, and `lf guide -- src/`) exit 0 and filter to src/ commits —
  # BUT the separator itself is consumed (BUG-2: it never reaches git), so
  # the two-sided cells still discriminate: lc/lcr keep "base"; lf's term
  # matches the docs-only commit, which the src/ filter must exclude.
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

@test "characterization lc/lf/lcr: branch named like the path hijacks (BUG-2, flip: Task 7)" {
  # characterization: flip target THIS PR (Task 7) — the actual BUG-2 defect
  # surface, probed: with a BRANCH named `src/a.py` in the repo, `lc py --
  # src/a.py` (same for lf/lcr) dies with git's "fatal: ambiguous argument
  # 'src/a.py': both revision and filename" (exit 128) — because the mid-
  # stream `--` was consumed, git cannot disambiguate rev-vs-path. Control
  # in the same repo: `lc py -- src/` still filters fine (no rev collision).
  local cmd
  for cmd in lc lf lcr; do
    psx_setup
    git branch 'src/a.py'
    run hug "$cmd" py -- src/a.py
    assert_equal 128 "$status"
    assert_output --partial "fatal: ambiguous argument 'src/a.py'"
    psx_reset
  done

  psx_setup
  git branch 'src/a.py'
  run hug lc py -- src/
  assert_success
  assert_output --partial "base"
  psx_reset
}

@test "characterization single-file commands: two files → git FATAL 128 (flip: Task 10)" {
  # characterization: flip target THIS PR (Task 10) — probed: every one of
  # these passes BOTH paths straight to git, which fatals (exit 128) with
  # one of two messages: "--follow requires exactly one pathspec" (fa,
  # fborn, fcon) or "bad revision '<second file>'" (fb, fblame, llf). We
  # assert the uniform observable (exit 128 + stderr "fatal:"); Task 10
  # replaces it with hug's own "accepts only one file" rejection.
  for cmd in "${PATHSPEC_CHAR_FATAL_ROWS[@]}"; do
    psx_setup
    run hug "$cmd" src/a.py docs/note.md
    assert_equal 128 "$status"
    assert_output --partial "fatal:"
    psx_reset
  done
}

@test "characterization h steps: extra files silently ignored (flip: Task 10)" {
  # characterization: flip target THIS PR (Task 10) — probed: git-h-steps
  # keeps the FIRST positional only (git-h-steps:62-73): with two files the
  # output is byte-identical to the single-file run (exit 0). Silent ignore
  # pinned via assert_equal so any drift names both sides.
  local single
  psx_setup
  run hug h steps src/a.py
  assert_success
  single="$output"
  run hug h steps src/a.py docs/note.md
  assert_success
  assert_equal "$single" "$output"
  psx_reset
}

@test "characterization stats file: extra files silently ignored (flip: Task 10)" {
  # characterization: flip target THIS PR (Task 10) — probed: `hug stats
  # file a b` churn-analyzes ONLY a (output identical to the single-file
  # run, exit 0); the extras vanish without a word.
  local single
  psx_setup
  run hug stats file src/a.py
  assert_success
  assert_output --partial "Churn analysis for: src/a.py"
  single="$output"
  run hug stats file src/a.py docs/note.md
  assert_success
  assert_equal "$single" "$output"
  refute_output --partial "docs/note.md"
  psx_reset
}
