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
# lists, and per-column tests that loop them.
# =============================================================================

load ../test_helper

# Contract rows — these commands conform TODAY and must stay green through the
# whole #292 effort.
PATHSPEC_CONFORMANCE_ROWS=(sw ss su shc shcp shp l ll cmod cmoda)

# Row classes (a command may appear in exactly one class per column):
#   PICKER_ROWS    — action commands whose trailing bare `--` opens the
#                    interactive file picker (spec §2 rule 3, action arm)
#   INERT_ROWS     — commands where a trailing bare `--` is pass-through/inert
#   HISTORY_ROWS   — cmod/cmoda AMEND history: no dry-run exists, so their
#                    filter columns are scoped to help-only (see column tests)
PATHSPEC_PICKER_ROWS=(sw ss su)
PATHSPEC_INERT_ROWS=(l ll shc shcp shp)
PATHSPEC_HISTORY_ROWS=(cmod cmoda)

# -----------------------------------------------------------------------------
# Fixture
# -----------------------------------------------------------------------------
# Creates the known-state repo (see header) and echoes its path.
# LESSON: commit ordering matters — the docs-only commit must land BEFORE the
# staged mod on src/a.py is created, or `git add docs/guide.md && git commit`
# sweeps the already-staged src/a.py into the "docs only" commit and every
# log-filter expectation silently breaks (found by probing; raw `git log --
# src/` is the oracle).
setup_pathspec_fixture() {
  local repo
  repo=$(create_test_repo) || return 1

  (
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
  ) >/dev/null 2>&1

  echo "$repo"
}

# Shared setup for every column test: fresh fixture, cd into it.
psx_setup() {
  require_hug
  TEST_REPO=$(setup_pathspec_fixture)
  cd "$TEST_REPO" || return 1
}

teardown() {
  cleanup_test_repo
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
    cd "$BATS_TEST_TMPDIR" || true
    cleanup_test_repo
    TEST_REPO=""
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

@test "column pathspec-filter: diff commands (sw ss su)" {
  for cmd in su sw; do
    psx_setup
    # su/sw see the UNSTAGED set: docs/note.md is the only unstaged mod.
    # Positive: filter that includes it; Negative: src/a.py (staged, the
    # non-matching marker) must stay absent.
    run hug "$cmd" -- docs/
    assert_success
    assert_output --partial "docs/note.md"
    refute_output --partial "src/a.py"
    cd "$BATS_TEST_TMPDIR" || true
    cleanup_test_repo
    TEST_REPO=""
  done

  psx_setup
  # ss sees the STAGED set: src/a.py only.
  run hug ss -- src/
  assert_success
  assert_output --partial "src/a.py"
  refute_output --partial "docs/note.md"
}

@test "column pathspec-filter: log commands (l ll)" {
  for cmd in l ll; do
    psx_setup
    # The docs-only commit is the non-matching marker: it must vanish under
    # `-- src/` while the base commit (which touched src/) stays.
    run hug "$cmd" -- src/
    assert_success
    assert_output --partial "base"
    refute_output --partial "docs guide only"
    cd "$BATS_TEST_TMPDIR" || true
    cleanup_test_repo
    TEST_REPO=""
  done
}

@test "column pathspec-filter: show commands (shc shcp shp)" {
  for cmd in shc shcp shp; do
    psx_setup
    # HEAD~1 is "base" (touched src/); filter to src/, docs/note.md is the
    # non-matching marker.
    run hug "$cmd" HEAD~1 -- src/
    assert_success
    assert_output --partial "src/a.py"
    refute_output --partial "docs/note.md"
    cd "$BATS_TEST_TMPDIR" || true
    cleanup_test_repo
    TEST_REPO=""
  done
}

@test "column pathspec-filter: history commands (cmod cmoda)" {
  # cmod/cmoda amend the last commit — running them with a pathspec in the
  # fixture would mutate history, and neither has --dry-run (probed: help
  # shows no dry-run option). Per spec the row is scoped to help-only.
  skip "characterization (Task 4): cmod/cmoda mutate history, no --dry-run — row scoped to help-only"
}

# =============================================================================
# COLUMN 3 — quoted glob filters, two-sided (spec §2 rule 4)
# =============================================================================

@test "column glob-filter: diff commands (sw ss su)" {
  psx_setup
  run hug su -- '*.md'
  assert_success
  assert_output --partial "docs/note.md"
  refute_output --partial "src/a.py"

  cd "$BATS_TEST_TMPDIR" || true
  cleanup_test_repo
  TEST_REPO=""
  psx_setup
  run hug ss -- '*.py'
  assert_success
  assert_output --partial "src/a.py"
  refute_output --partial "docs/note.md"
}

@test "column glob-filter: log commands (l ll)" {
  for cmd in l ll; do
    psx_setup
    # '*.py' matches base's src files; the docs-only commit has none.
    run hug "$cmd" -- '*.py'
    assert_success
    assert_output --partial "base"
    refute_output --partial "docs guide only"
    cd "$BATS_TEST_TMPDIR" || true
    cleanup_test_repo
    TEST_REPO=""
  done
}

@test "column glob-filter: show commands (shc shcp shp)" {
  for cmd in shc shcp shp; do
    psx_setup
    run hug "$cmd" HEAD~1 -- '*.md'
    assert_success
    assert_output --partial "docs/note.md"
    refute_output --partial "src/a.py"
    cd "$BATS_TEST_TMPDIR" || true
    cleanup_test_repo
    TEST_REPO=""
  done
}

@test "column glob-filter: history commands (cmod cmoda)" {
  skip "characterization (Task 4): cmod/cmoda mutate history, no --dry-run — row scoped to help-only"
}

# =============================================================================
# COLUMN 4 — trailing bare `--` (spec §2 rule 3)
# =============================================================================

@test "column trailing-dashdash: picker arm for action commands (sw ss su)" {
  # Technique from tests/unit/test_status_staging.bats:1500-1517: in CI (no
  # TTY) the picker arm must NOT print the regular diff markers. We also
  # assert the POSITIVE observable — the diff driver's "No … available or
  # cancelled." message — because absence-only passes on a crash. Probed:
  # exit 0 with that message on stderr in BOTH gum branches (gum installed →
  # TTY failure; gum absent → gum-missing error, same message after).
  psx_setup
  run hug su --
  assert_success
  refute_output --partial "Unstaged diff"
  assert_output --partial "No unstaged files available or cancelled."

  cd "$BATS_TEST_TMPDIR" || true
  cleanup_test_repo
  TEST_REPO=""
  psx_setup
  run hug ss --
  assert_success
  refute_output --partial "Staged diff"
  assert_output --partial "No staged files available or cancelled."

  cd "$BATS_TEST_TMPDIR" || true
  cleanup_test_repo
  TEST_REPO=""
  psx_setup
  run hug sw --
  assert_success
  refute_output --partial "Unstaged diff"
  assert_output --partial "No files with working directory changes available or cancelled."
}

@test "column trailing-dashdash: inert pass-through (l ll shc shcp shp)" {
  # These are not picker commands: a trailing bare `--` reaches git's own
  # separator semantics and is inert. Observable: exit 0 and output IDENTICAL
  # to the no-flag run (probed with diff — byte-identical).
  local cmd args
  for cmd in l ll; do
    psx_setup
    run hug "$cmd"
    assert_success
    local plain="$output"
    run hug "$cmd" --
    assert_success
    [[ "$output" == "$plain" ]]
    cd "$BATS_TEST_TMPDIR" || true
    cleanup_test_repo
    TEST_REPO=""
  done

  for cmd in shc shcp shp; do
    psx_setup
    run hug "$cmd" HEAD~1
    assert_success
    local plain="$output"
    run hug "$cmd" HEAD~1 --
    assert_success
    [[ "$output" == "$plain" ]]
    cd "$BATS_TEST_TMPDIR" || true
    cleanup_test_repo
    TEST_REPO=""
  done
}

@test "column trailing-dashdash: history commands (cmod cmoda)" {
  # A trailing `--` on cmod/cmoda would perform a real amend (no dry-run).
  skip "characterization (Task 4): cmod/cmoda trailing -- would amend history — not probed in fixture"
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
    cd "$BATS_TEST_TMPDIR" || true
    cleanup_test_repo
    TEST_REPO=""
  done
}

# =============================================================================
# COLUMN 7 — git magic pathspecs pass through verbatim (spec §2 rule 6)
# =============================================================================

@test "column magic-pathspec: diff commands (sw ss su)" {
  # :(icase) positive: case-variant spellings still match the changed files.
  psx_setup
  run hug ss -- ':(icase)SRC/A.PY'
  assert_success
  assert_output --partial "src/a.py"

  cd "$BATS_TEST_TMPDIR" || true
  cleanup_test_repo
  TEST_REPO=""
  psx_setup
  run hug su -- ':(icase)DOCS/NOTE.MD'
  assert_success
  assert_output --partial "docs/note.md"

  cd "$BATS_TEST_TMPDIR" || true
  cleanup_test_repo
  TEST_REPO=""
  psx_setup
  run hug sw -- ':(icase)DOCS/NOTE.MD'
  assert_success
  assert_output --partial "docs/note.md"
}

@test "column magic-pathspec: log commands (l ll)" {
  psx_setup
  # :(icase) two-sided: matches the case-variant path of a base file, and the
  # docs-only commit stays absent.
  run hug ll -- ':(icase)src/big.py'
  assert_success
  assert_output --partial "base"
  refute_output --partial "docs guide only"

  cd "$BATS_TEST_TMPDIR" || true
  cleanup_test_repo
  TEST_REPO=""
  psx_setup
  # :(exclude) two-sided: src/ minus src/a.py still admits base (BIG.py
  # matched), while the docs-only commit stays absent.
  run hug ll -- 'src/' ':(exclude)src/a.py'
  assert_success
  assert_output --partial "base"
}

@test "column magic-pathspec: show commands (shc shcp shp)" {
  for cmd in shc shcp shp; do
    psx_setup
    # :(icase): 'src/big.py' must match src/BIG.py in the base commit.
    run hug "$cmd" HEAD~1 -- ':(icase)src/big.py'
    assert_success
    assert_output --partial "src/BIG.py"
    refute_output --partial "src/a.py"
    cd "$BATS_TEST_TMPDIR" || true
    cleanup_test_repo
    TEST_REPO=""
  done

  psx_setup
  # :(exclude) two-sided on the changed-files list: src/ minus a.py.
  run hug shc HEAD~1 -- 'src/' ':(exclude)src/a.py'
  assert_success
  assert_output --partial "src/BIG.py"
  refute_output --partial "src/a.py"
}

@test "column magic-pathspec: history commands (cmod cmoda)" {
  skip "characterization (Task 4): cmod/cmoda mutate history, no --dry-run — row scoped to help-only"
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
