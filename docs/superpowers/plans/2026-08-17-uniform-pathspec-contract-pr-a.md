# Uniform Pathspec Contract — PR-A (contract core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the pathspec contract core — the conformance suite, the unified parser helper, both library extensions, the scoped picker, and the six defect fixes (BUG-2/3/4/6-minimal + cardinality) — per spec §9 PR-A.

**Architecture:** A shared `hug-cli-flags` entry point (`parse_common_flags_with_pathspecs`, with a `--picker` mode that owns the `HUG_INTERACTIVE_FILE_SELECTION` lifecycle) makes the parsing-order invariant structural; a table-driven BATS conformance suite enforces the contract's nine columns; two library extensions (`select_files_with_status` pathspecs, cardinality guard) plus per-command call-site fixes complete the core. Everything is red-first: characterization rows and failing tests land before their fixes.

**Tech Stack:** Bash (GNU getopt), BATS test framework, Makefile targets (`make test-unit TEST_FILE=…`, `make test-lib TEST_FILE=…`).

**Spec:** `docs/superpowers/specs/2026-08-16-uniform-pathspec-contract-for-all-path-accepting-hug-commands-design.md` (§3, §4, §5.1–5.4, §5.6, §9 PR-A row).

**Worktree:** `~/src/hug-scm.WT.292-uniform-pathspec-contract-for-all-path-accepting-hug-commands` (all paths below are worktree-relative).

**Conventions:** Run tests only via Makefile targets. Commit via `hug -C <wt> c -F -` with WHY/WHAT/HOW/IMPACT messages (skill `commit-message`). Never `git worktree`/raw git for repo ops — use `hug`. After each subagent write-task, run `make sanitize` and fold into the commit.

---

### Task 1: `parse_common_flags_with_pathspecs` (+ `--picker` mode)

**Goal:** One eval-able library entry point that structurally encodes the parsing order: strip trailing bare `--` (picker-mode-aware) → split at first `--` → parse common flags from pre-args only.

**Files:**
- Modify: `git-config/lib/hug-cli-flags` (append after `parse_common_flags`, ~line 254)
- Test: `tests/lib/test_hug-cli-flags.bats` (append; suite already sources the lib)

**Acceptance Criteria:**
- [ ] `eval "$(parse_common_flags_with_pathspecs HEAD --stat -- '*.java' src/)"` leaves `$@`=(HEAD --stat… common flags consumed per parse_common_flags) and `_pathspec_pathspecs=('*.java' src/)`
- [ ] Without `--picker`, a trailing bare `--` is consumed and `HUG_INTERACTIVE_FILE_SELECTION` is NOT exported
- [ ] With `--picker` and trailing bare `--`, `HUG_INTERACTIVE_FILE_SELECTION=true` is exported
- [ ] `-h/--help` in pre-args emits the show_help/exit path (parse_common_flags behavior, unchanged)
- [ ] Empty-args and empty-pathspec cases are `set -u`-safe (guarded expansions)
- [ ] No git invocations; no change to `parse_pathspecs`/`parse_common_flags` themselves

**Verify:** `make test-lib TEST_FILE=test_hug-cli-flags.bats` → all pass, including the new cases

**Steps:**

- [ ] **Step 1: Write failing tests** (append to `tests/lib/test_hug-cli-flags.bats`, following the suite's existing style):

```bash
@test "parse_common_flags_with_pathspecs: splits pathspecs and parses pre-args" {
  eval "$(parse_common_flags_with_pathspecs --dry-run HEAD --stat -- '*.java' 'src/')" || return 1
  [[ "${_pathspec_pathspecs[0]}" == '*.java' ]]
  [[ "${_pathspec_pathspecs[1]}" == 'src/' ]]
  [[ "${dry_run:-}" == true ]]
}

@test "parse_common_flags_with_pathspecs: without --picker, trailing bare -- is inert" {
  unset HUG_INTERACTIVE_FILE_SELECTION || true
  eval "$(parse_common_flags_with_pathspecs --)" || return 1
  [[ -z "${HUG_INTERACTIVE_FILE_SELECTION:-}" ]]
  [[ ${#_pathspec_pathspecs[@]} -eq 0 ]]
}

@test "parse_common_flags_with_pathspecs: with --picker, trailing bare -- exports the flag" {
  unset HUG_INTERACTIVE_FILE_SELECTION || true
  eval "$(parse_common_flags_with_pathspecs --picker --)" || return 1
  [[ "${HUG_INTERACTIVE_FILE_SELECTION:-}" == true ]]
}

@test "parse_common_flags_with_pathspecs: empty args are set -u safe" {
  eval "$(parse_common_flags_with_pathspecs)" || return 1
  [[ ${#_pathspec_pathspecs[@]} -eq 0 ]]
}
```

- [ ] **Step 2:** `make test-lib TEST_FILE=test_hug-cli-flags.bats` → new tests FAIL (function undefined)
- [ ] **Step 3: Implement** (append to `git-config/lib/hug-cli-flags`):

```bash
# Unified entry point for every command that accepts -- <pathspec>...
# Fixes the parsing order STRUCTURALLY: trailing bare '--' handling first,
# then the pathspec split, then common-flag parsing on pre-args only —
# the sequence proven by _diff_cmd_setup (hug-git-diff:464-483), lifted here.
#
# Usage: eval "$(parse_common_flags_with_pathspecs [--picker] "$@")"
#
# Caller-scope effects (in addition to everything parse_common_flags emits):
#   "$@"                    → remaining separator-free pre-args (positionals may
#                            still be paths when no -- was given)
#   _pathspec_pathspecs[]   → everything after the first --
#   HUG_INTERACTIVE_FILE_SELECTION → exported ONLY with --picker and a trailing
#                            bare '--'. The helper OWNS the export lifecycle:
#                            listings call it without --picker, so nothing is
#                            exported and no unset-before-exec rule is needed
#                            (the leak class is deleted by construction).
parse_common_flags_with_pathspecs() {
  local picker_mode=false
  if [[ "${1:-}" == "--picker" ]]; then
    picker_mode=true
    shift
  fi

  local trailing_picker=false
  if [[ $# -gt 0 && "${!#}" = "--" ]]; then
    $picker_mode && trailing_picker=true
    set -- "${@:1:$(($# - 1))}"
  fi

  # Split at the first '--' (function-local; re-emitted for the caller below)
  eval "$(parse_pathspecs "$@")"

  {
    # Restore pre-args as the caller's "$@", then delegate common-flag parsing
    # (its 'set --' therefore applies to the CALLER's scope).
    printf 'set -- '
    if [[ ${#_pathspec_pre_args[@]} -gt 0 ]]; then
      printf '%q ' "${_pathspec_pre_args[@]}"
    fi
    printf '\n'
    printf 'eval "$(parse_common_flags "$@")"\n'

    printf '_pathspec_pathspecs=('
    if [[ ${#_pathspec_pathspecs[@]} -gt 0 ]]; then
      printf ' %q' "${_pathspec_pathspecs[@]}"
    fi
    printf ' )\n'

    if $trailing_picker; then
      printf 'export HUG_INTERACTIVE_FILE_SELECTION=true\n'
    fi
  }
}
```

- [ ] **Step 4:** `make test-lib TEST_FILE=test_hug-cli-flags.bats` → PASS
- [ ] **Step 5:** Commit: `feat(cli-flags): parse_common_flags_with_pathspecs — structural parsing order + picker lifecycle (#292 PR-A)`

---

### Task 2: `reject_multiple_files` cardinality guard

**Goal:** Library validator that rejects >1 file argument with a clear, command-naming error.

**Files:**
- Modify: `git-config/lib/hug-cli-flags` (append after Task 1's function)
- Test: `tests/lib/test_hug-cli-flags.bats`

**Acceptance Criteria:**
- [ ] `reject_multiple_files "hug fa" a.txt b.txt` prints `hug fa accepts only one file.` to stderr and exits 1
- [ ] Single file and zero files pass silently (exit 0)
- [ ] Empty-string arguments are ignored (not counted)

**Verify:** `make test-lib TEST_FILE=test_hug-cli-flags.bats` → pass

**Steps:**

- [ ] **Step 1: Failing tests:**

```bash
@test "reject_multiple_files: rejects two files naming the command" {
  run reject_multiple_files "hug fa" a.txt b.txt
  assert_failure
  assert_output --partial "hug fa accepts only one file."
}

@test "reject_multiple_files: one file, zero files, and empty strings pass" {
  run reject_multiple_files "hug fa" a.txt
  assert_success
  run reject_multiple_files "hug fa"
  assert_success
  run reject_multiple_files "hug fa" a.txt ""
  assert_success
}
```

- [ ] **Step 2:** Verify FAIL, then **implement** (append to `hug-cli-flags`):

```bash
# Cardinality guard for single-file commands (spec §3.2 / §5.6).
# Usage: reject_multiple_files "<cmd-name>" [file...]
reject_multiple_files() {
  local cmd_name="$1"; shift
  local -a files=()
  local f
  for f in "$@"; do
    [[ -n "$f" ]] && files+=("$f")
  done
  if [[ ${#files[@]} -gt 1 ]]; then
    error "${cmd_name} accepts only one file."
  fi
}
```

(`error` comes from `hug-output`, already sourced by every consumer of this lib.)

- [ ] **Step 3:** Verify PASS; commit: `feat(cli-flags): reject_multiple_files cardinality guard (#292 PR-A)`

---

### Task 3: Conformance suite — skeleton + contract rows (already-correct commands)

**Goal:** The table-driven `tests/unit/test_pathspec_conformance.bats` with the fixture builder and contract rows for commands already conforming today (they must stay green through the whole ladder).

**Files:**
- Create: `tests/unit/test_pathspec_conformance.bats`

**Acceptance Criteria:**
- [ ] Fixture builder creates a repo with a KNOWN file set (per spec §4: expectations derivable): `src/a.py` + `src/BIG.py` (case-variant for `:(icase)`), `docs/note.md`, `other.txt`; one commit; then stage `src/a.py` mod, leave `docs/note.md` mod unstaged, add untracked `new.txt`
- [ ] Contract rows exist and PASS for: `sw`, `ss`, `su`, `shc`, `shcp`, `shp`, `l`, `ll`, `cmod`, `cmoda`, `us` (per-row: `--help` shows USAGE; `-- <path>` filters; quoted glob filters; unknown-flag loud where applicable; magic smoke; `--json` where present)
- [ ] Table-driven: one bash-array row per command; adding a command is one line
- [ ] JSON column is two-sided: parses via `python3 -m json.tool`, no file outside pathspecs AND at least one inside
- [ ] Magic observables: `:(icase)` matches `src/BIG.py` when queried as `src/big.py`; `:(exclude)` omits a file the base pathspec includes
- [ ] Trailing-`--` column cells per row class: listings inert (output equals unfiltered run); action commands picker-arm (regular output absent + per-row message: diff-driver → "No … available or cancelled." `hug-git-diff:525`; `lc`/`lcr`/`lf` → "Cancelled." — Task 7 lands those rows)

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats` → all rows green

**Steps:**

- [ ] **Step 1:** Write the suite. Skeleton (executor completes each row with the same shape):

```bash
#!/usr/bin/env bash
# Pathspec conformance suite (spec §4, nine columns).
# One row per path-accepting command from mgmt/superpowers/specs/pathscoping-audit.md.
# Row staging: PR-A lands contract rows for already-correct commands; commands
# migrated in later PRs carry characterization rows there.
load ../test_helper

# Fixture: known file set so every row's expectation is derivable.
setup_pathspec_fixture() {
  create_test_repo
  mkdir -p src docs
  echo py > src/a.py; echo big > src/BIG.py; echo note > docs/note.md; echo other > other.txt
  git add -A && git commit -qm "base"
  echo py2 >> src/a.py && git add src/a.py          # staged mod
  echo note2 >> docs/note.md                         # unstaged mod
  echo new > new.txt                                 # untracked
}

# Row table: cmd|help|filter_probe|extra (extra: class-specific cells)
# Contract rows (green today, must STAY green):
#   sw ss su shc shcp shp l ll cmod cmoda us
CONFORMANCE_ROWS=(
  "sw"
  "ss"
  "su"
  "shc"
  "shcp"
  "shp"
  "l"
  "ll"
  "cmod"
  "cmoda"
  "us"
)

@test "conformance: {cmd} --help shows help" {
  setup_pathspec_fixture
  run hug sw --help   # expanded per row via a loop or generated test per row
  assert_success
  assert_output --partial "USAGE:"
}

# ... one @test per column, looping CONFORMANCE_ROWS; per-row class map for
# trailing-`--` (listing vs action) and --json presence follows the audit
```

Execute as a loop pattern (BATS-friendly): write one `@test` per column that iterates the row array and `skip`s N/A cells, OR generate one `@test` per (row × column) via a helper function the file defines — follow the existing table-driven style in `tests/lib/test_hug-select-files.bats` (state-machine loops) if simpler.

- [ ] **Step 2:** `make test-unit TEST_FILE=test_pathspec_conformance.bats` → all green. Any row that is NOT green today is a discovered defect: do NOT loosen the column — file the row as characterization (record actual behavior in the test with a `# characterization:` comment) and report it in the task output.
- [ ] **Step 3:** Commit: `test(conformance): pathspec contract suite — contract rows (#292 PR-A)`

---

### Task 4: Conformance suite — characterization rows (commands PR-A/B/C migrate)

**Goal:** Capture TODAY's behavior of every not-yet-migrated command so later flips are deliberate red→green updates, never surprises.

**Files:**
- Modify: `tests/unit/test_pathspec_conformance.bats`

**Acceptance Criteria:**
- [ ] Characterization rows (marked `# characterization:`) for: `sl`, `sla`, `sls`, `slu`, `slk`, `sli`, `slc` (current: bare `--` collected as pathspec — full listing by coincidence; `sls/slu/slk/sli` `--help` swallowed), `us` (`hug us -- src/` errors "Unknown option: --"; `hug us --` errors), `w get` (`-u <file>` errors "Cannot specify --upstream…"), `sh` (stray positional silently overwrites ref — assert `hug sh HEAD -- src/` shows `src/`-filtered output, BUG-6 baseline), `llu` (flags-only; `-- src/` → "Unknown option: --"), `lc`/`lf` (mid-stream `--` dropped: filtered result WITHOUT separator — assert the current filtered-but-separatorless behavior), `lcr`, `fa`/`fb`/`fblame`/`fborn`/`fcon`/`llf` (2 files → git fatal, exit ≠ 0), `h-steps` (2 files → SILENT IGNORE of the second file, exit as with one file — `git-h-steps:62-73` stores the first and `break`s on the second; the second never reaches git), `stats-file` (2 files → silent ignore, exit 0)
- [ ] Every characterization row documents the CONTRACT row it will become (comment: `# flips in PR-B|PR-C to: …`)

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats` → all green (characterizations assert CURRENT behavior)

**Steps:**

- [ ] **Step 1:** Add the rows with exact expected strings (probe each command in the fixture repo first — line anchors for expected messages: `git-us:93-94` "Unknown option: --", `git-w-get:390` "Cannot specify --upstream…", `git-llu:104` "Unknown option:").
- [ ] **Step 2:** Verify all green; any red means the characterization is wrong — fix the characterization, never the command.
- [ ] **Step 3:** Commit: `test(conformance): characterization rows for un-migrated commands (#292 PR-A)`

---

### Task 5: `select_files_with_status` pathspec extension

**Goal:** The interactive file selector accepts pathspecs and offers only matching files (foundation for the scoped picker; today it errors on positionals).

**Files:**
- Modify: `git-config/lib/hug-select-files:600-680` (parse loop; `*)` case at `:654-655` errors)
- Test: `tests/lib/test_hug-select-files.bats`

**Acceptance Criteria:**
- [ ] The parse loop gains a dedicated separator arm that treats everything after `--` as verbatim pathspec data (a bare `*)` collector would make `--` itself a literal pathspec and keep option-parsing alive for post-separator args — a file literally named `--staged` must not be eaten as an option):

```bash
      --)
        shift
        pathspecs+=("$@")
        break
        ;;
      *)
        pathspecs+=("$1")
        shift
        ;;
```

- [ ] Pathspecs are forwarded through the selector's ACTUAL list calls — `select_files_with_status` invokes `list_tracked_files`, `list_staged_files`, `list_unstaged_files`, `list_untracked_files`, and `list_ignored_files` directly (`hug-select-files:690-755`; it does NOT call `list_files_with_status` — that is the separate non-interactive function at `:312`). Append `"${pathspecs[@]+…}"` at each of the five sites; each `list_*_files` already accepts trailing pathspecs (same pattern as `list_files_with_status:409-465`)
- [ ] Flags-only invocation is unchanged (regression: existing selector tests stay green)
- [ ] Spec §3.1's swallow hazard is covered by a test: a caller capturing via `if file=$(select_files_with_status --staged -- src/)` gets a scoped, working selection (mock gum per the suite's existing mock pattern) — not "Cancelled."

**Verify:** `make test-lib TEST_FILE=test_hug-select-files.bats` → pass

**Steps:**

- [ ] **Step 1: Failing test:**

```bash
@test "select_files_with_status: accepts pathspecs and scopes the candidate list" {
  # mock gum to capture the rendered candidate list (existing mock pattern in this suite)
  …existing mock setup…
  run select_files_with_status --staged -- src/a.py
  assert_success
  # captured candidates contain src/a.py and NOT docs/note.md
}
```

- [ ] **Step 2:** Verify FAIL (current: "Unknown option … select_files_with_status"), then **implement**: add `local -a pathspecs=()` to the locals block (`hug-select-files:606-614`), change the `*)` case to collect (`pathspecs+=("$1"); shift`), and append `"${pathspecs[@]+"${pathspecs[@]}"}"` to the internal `list_files_with_status` call.
- [ ] **Step 3:** Verify PASS + full file green; commit: `feat(select-files): select_files_with_status accepts pathspecs — scoped picker foundation (#292 PR-A)`

---

### Task 6: Scoped picker on action commands (`su`/`ss`/`sw`)

**Goal:** `_diff_cmd_setup`'s picker branch passes `_pathspec_pathspecs` into the selection call — `hug su -- src/ --` picks only among changed files under `src/` (spec §2 rule 3).

**Files:**
- Modify: `git-config/lib/hug-git-diff:508-517` (picker branch, before the `select_opts` are built)
- Test: `tests/unit/test_pathspec_conformance.bats` (scoped-picker column cells for su/ss/sw)

**Acceptance Criteria:**
- [ ] With pathspecs + trailing `--`, the selection options include the pathspecs: append after the `--prompt` line —

```bash
    if [[ ${#_pathspec_pathspecs[@]} -gt 0 ]]; then
      select_opts+=("${_pathspec_pathspecs[@]}")
    fi
```

- [ ] Scoped-picker conformance cell (two-sided, spec §4): a stub `gum` first on PATH captures its STDIN to a file (`cat > "$GUM_CANDIDATES_FILE"; exit 1` — candidates flow to gum via stdin, `hug-select-files:811`; gum's argv carries only filter/presentation flags, so argv cannot observe scoping); assert every captured candidate line matches `src/` AND at least one matching candidate is present
- [ ] Bare `hug su --` (no pathspecs) behavior unchanged (existing no-TTY test stays green)

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats` + `make test-unit TEST_FILE=test_status_staging.bats` → green

**Steps:**

- [ ] **Step 1:** Write the scoped-picker stub-gum test (stub script: `#!/usr/bin/env bash; cat > "$GUM_CANDIDATES_FILE"; exit 1` on PATH first — it captures the candidate list gum receives on stdin (`hug-select-files:811`); run `hug su -- src/ --`; assert captured lines ⊆ `src/*` and non-empty).
- [ ] **Step 2:** Verify FAIL (today the picker ignores pathspecs — argv contains files outside `src/`).
- [ ] **Step 3:** Apply the 3-line change above; verify both files green.
- [ ] **Step 4:** Commit: `feat(diff): scoped interactive picker — pathspecs are never silently discarded (#292 PR-A)`

---

### Task 7: BUG-2 — `lc`/`lf`/`lcr` separator re-injection at every sink

**Goal:** The three search commands adopt the unified helper and re-inject `-- "${_pathspec_pathspecs[@]}"` at ALL delegation sinks (spec §5.1 table — including the JSON branches).

**Files:**
- Modify: `git-config/bin/git-lc` (`:58` parse; sinks `:117-120` JSON, `:151`/`:153` picker, `:168` with-files, `:170` plain)
- Modify: `git-config/bin/git-lf` (`:121-125` JSON, `:156`/`:158` picker, `:173`, `:175`)
- Modify: `git-config/bin/git-lcr` (`:87` picker, `:99` plain — no JSON branch)
- Test: `tests/unit/test_pathspec_conformance.bats` (flip lc/lf/lcr characterization rows to contract)

**Acceptance Criteria:**
- [ ] Each script's `eval "$(parse_common_flags "$@")"` becomes `eval "$(parse_common_flags_with_pathspecs --picker "$@")"` (delete the now-redundant `: "${browse_root:=false}"` only if parse_common_flags still sets it — it does; keep)
- [ ] JSON branches append pathspecs with the nullsafe guard:

```bash
  search_args+=("$@")
  (( ${#_pathspec_pathspecs[@]} )) && search_args+=("--" "${_pathspec_pathspecs[@]}")
```

- [ ] Exec boundaries re-inject: `exec hug ll -S "$search_term" "$@"` → `… "$@" ${_pathspec_pathspecs[@]+"--" "${_pathspec_pathspecs[@]}"}`
- [ ] Picker branches scope via Task 5's extension (pathspecs already flow — verify the picker `select_opts` gain them like Task 6)
- [ ] Contract rows green: `hug lc "term" -- src/a.py` filters; `hug lc --json "term" -- src/` returns ONLY src files (two-sided JSON check); trailing `hug lc "term" --` picker arm ("Cancelled." observable)
- [ ] A branch/tag named like the path no longer hijacks (fixture: create branch `src/a.py`; `hug lc term -- src/a.py` still filters by path)

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats` → lc/lf/lcr rows green (characterizations flipped)

**Steps:**

- [ ] **Step 1:** Flip the three commands' characterization rows to contract expectations; verify RED.
- [ ] **Step 2:** Apply the edits above to all three scripts (10 sinks total per the table).
- [ ] **Step 3:** Verify green; `make test-unit TEST_FILE=test_history.bats` (or the suite covering lc/lf) for regressions.
- [ ] **Step 4:** Commit: `fix(lc,lf,lcr): preserve -- separator at every delegation sink, scope pickers and JSON (#292 PR-A)`

---

### Task 8: BUG-3/4 — `w get -u` file handling + restore separator

**Goal:** `hug w get -u <file>` restores that file from upstream; `hug w get -u` alone runs the documented reset-all; the restore call passes an explicit `--`.

**Files:**
- Modify: `git-config/bin/git-w-get` (`:344-395` parse flow; `:324` restore call)
- Test: `tests/unit/test_pathspec_conformance.bats` (w get rows) or the existing w-get test file if one exists (check `tests/unit/` — else conformance rows only)

**Acceptance Criteria:**
- [ ] When `use_upstream=true`: skip target extraction AND the missing-target error (`:367-375`) — positionals are files; `-u` alone proceeds to `get_upstream_commit` and dispatches (`:438-440`) to `reset_all_files`
- [ ] The `target_identifier == "-u"` dead branch (`:379-381`) is removed
- [ ] `git-w-get:324`: `git restore --source="$commit" --worktree -- "${files_to_reset[@]}"`
- [ ] Characterization → contract flips: `w get -u file.txt` restores file.txt content from upstream (exit 0); `w get -u` shows the reset_all_files preview ("Files that will be MODIFIED:" category lists, `:171-193`) and with `--dry-run` makes no changes; a file named `-weird` is not misread as a flag
- [ ] No-upstream case: `w get -u` in a repo without upstream errors loudly (`get_upstream_commit`, `:396`)
- [ ] Non-`-u` behavior unchanged: `w get <commit> <file>` paths and the specific-files preview (`:305-319`) untouched

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats` → w get rows green

**Steps:**

- [ ] **Step 1:** Flip characterization rows to contract; verify RED.
- [ ] **Step 2:** In `main()`: guard steps 3–4 with `if ! $use_upstream; then … fi`; delete the `:379-381` branch; add `--` at `:324`.
- [ ] **Step 3:** Verify green + existing w-get tests (grep `tests/unit/` for w-get coverage) stay green.
- [ ] **Step 4:** Commit: `fix(w-get): -u treats positionals as files; reset-all form works; restore passes -- (#292 PR-A)`

---

### Task 9: `sh` loud rejection of stray positionals

**Goal:** BUG-6 interim fix — a second positional after the commit ref errors loudly instead of silently overwriting it.

**Files:**
- Modify: `git-config/bin/git-sh:74-90` (arg loop)
- Test: `tests/unit/test_pathspec_conformance.bats` (sh characterization row flips)

**Acceptance Criteria:**
- [ ] The `*)` case rejects a second positional:

```bash
  *)
    if [[ -n "$commit_ref" ]]; then
      error "hug sh accepts one commit reference; unexpected extra argument: '$arg'. (Path filtering lands with 'hug sh <ref> -- <path>' in a later PR.)"
    fi
    commit_ref="$arg"
    ;;
```

- [ ] `hug sh HEAD src/` exits non-zero naming the extra argument; `hug sh`, `hug sh 2`, `hug sh abc123`, `hug sh --llm HEAD` all unchanged (existing sh tests green)

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats` + sh coverage → green

**Steps:**

- [ ] **Step 1:** Flip the sh characterization row (`hug sh HEAD -- src/` currently filters by the last positional) to expect the loud error; verify RED.
- [ ] **Step 2:** Apply the guard; verify green.
- [ ] **Step 3:** Commit: `fix(sh): reject stray positionals loudly instead of overwriting the ref (#292 PR-A)`

---

### Task 10: Cardinality adoption on single-file commands

**Goal:** `fa`, `fb`, `fblame`, `fborn`, `fcon`, `llf`, `h-steps`, `stats-file` reject multiple file arguments via `reject_multiple_files`; `llfp`/`llfs` inherit via delegation.

**Files:**
- Modify: `git-config/bin/git-fa` (before `:81` exec), `git-fb`, `git-fblame`, `git-fborn`, `git-fcon`, `git-llf` (after `:60-61`), `git-h-steps`, `git-stats-file` (replace the silent-ignore at `:145`)
- Test: `tests/unit/test_pathspec_conformance.bats` (cardinality rows)

**Acceptance Criteria:**
- [ ] Each command calls `reject_multiple_files "<hug cmd>" <files…>` where it collects file args; flags/`-N` numerics are NOT counted as files for `llf` (guard only additional non-`-` positionals)
- [ ] `hug fa a.txt b.txt` → exit 1, "hug fa accepts only one file."; same shape per command
- [ ] `stats-file`'s silent-ignore is REPLACED by the rejection (its characterization row flips)
- [ ] `hug llfp a.txt b.txt` errors (delegated to llf's guard)

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats` → cardinality rows green

**Steps:**

- [ ] **Step 1:** Flip the family's characterization rows (fatal/silent-ignore baselines) to the rejection expectation; verify RED.
- [ ] **Step 2:** Insert the one-line guard at each collection point (probe each script's arg handling first — all follow the `file="$1"; shift` or `"$@"` patterns seen at `git-fa:81`, `git-llf:60-61`, `git-stats-file:145`).
- [ ] **Step 3:** Verify green + `make test-unit TEST_FILE=test_file_inspection.bats` if present (check `tests/unit/` for the family's coverage) stays green.
- [ ] **Step 4:** Commit: `fix(file-inspection): single-file commands reject multiple files with a clear error (#292 PR-A)`

---

### Task 11: Full-suite validation + PR readiness

**Goal:** Whole-repo test run green (modulo documented environmental failures); conformance suite green on every landed contract row; the branch is ready for review.

**Files:** none (validation only)

**Acceptance Criteria:**
- [ ] `make test` → all pass except the two documented environment-dependent failures (test_hug-file-input.bats .env gitignore; hug c git-identity) — any OTHER failure blocks
- [ ] `make sanitize` clean
- [ ] `hug -C <wt> ll` shows atomic commits, one per task
- [ ] Spec §9 PR-A exit criteria restated in the final commit/task output: contract rows green; every defect red→green (BUG-2/3/4, sh rejection, cardinality); intended changes list (cardinality, sh rejection, w get dispositions, picker scoping) — nothing else changed behavior

**Verify:** `make test` + `make sanitize` → clean

**Steps:**

- [ ] **Step 1:** `make sanitize` → clean (fold any reformatting into the last code commit).
- [ ] **Step 2:** `make test` → record output; classify failures against the documented environmental list.
- [ ] **Step 3:** Final task output summarizes red→green flips per defect (the convergence record).

---

## Self-Review (done at write time)

- **Spec coverage:** §3.1→Task 1; §3.2→Task 2; §4→Tasks 3/4 (+6/7 column cells); §5.1→Task 7; §5.2/5.3→Task 8; §5.4→Task 9; §5.6→Task 10; §9 PR-A "lands the audit matrix" — already on branch (`8527a05` series); picker scoping→Tasks 5/6; exit criteria→Task 11. PR-B/PR-C items are deliberately NOT here (they get their own plans).
- **Type consistency:** `parse_common_flags_with_pathspecs`/`reject_multiple_files` names identical across tasks; `_pathspec_pathspecs` used consistently.
- **Placeholders:** Task 3's row loop is specified by pattern + reference file (`test_hug-select-files.bats` table style) with concrete examples — the executor completes the mechanical expansion; no TBDs.
