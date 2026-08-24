# Two-Stream Guard Extraction Implementation Plan (#313)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the byte-identical two-stream single-file guard from git-fa/fb/fborn/fcon into `git-config/lib/hug-cli-flags` as `guard_single_file_candidates`, retiring the repeated unknown-option template and nullsafe pathspecs condition via `error_unknown_option` and `pathspecs_nonempty`.

**Architecture:** Three in-process helpers (nameref-free: caller-scalar written via `printf -v`) added to the existing flags lib following its established patterns (`__gsfc_` reserved internal prefix, accessor-based reads of `_pathspec_pathspecs`). Four clone sites collapse from ~40 lines to a guard call + `set --`; h-steps/fblame/stats-file adopt only the small helpers. Pure refactor — no observable change anywhere.

**Tech Stack:** Bash (floor 4.0–4.3), bats test suites (`tests/lib/test_hug-cli-flags.bats`, `tests/unit/test_pathspec_conformance.bats`), Make targets, hug git wrappers.

## Global Constraints

Spec: `docs/superpowers/specs/2026-08-24-313-extract-two-stream-single-file-guard-into-hug-cli-flags-design.md` (commits 3729ee38, aad0b836).

- **Behavior-preserving:** identical messages byte-for-byte, identical exit codes (exit-2 usage family via `error_usage`), identical check precedence per site. Proof = existing conformance rows pass unmodified.
- **Short-form template stays short-form:** `Unknown option: <tok>. See 'hug help :pathspec'.` — NOT the listing-family long form (`Pathspecs beginning with '-' require '--': …`).
- **F2 invariant:** unknown-option checks run on the pre-'--' stream ONLY, before any separator data joins the tally. `hug fa -- -foo.txt -bar.txt` must hit cardinality ("got 2 files"), never an option complaint; `-- -baz.txt` alone must analyze.
- **F1 invariant:** an empty-string pre-'--' positional is a loud usage error (`Empty file argument.`).
- **Nullsafe idiom** everywhere arrays may be empty/unset: `${arr[@]+"${arr[@]}"}` (Bash 4.0–4.3 floor, `set -u`).
- **Reserved prefix** `__gsfc_` for all helper internals (same discipline as `__dps_`/`__pso_`).
- **Git ops through hug only:** `hug c`, `hug bpush`, `hug sw` — never raw `git commit`/`push`.
- **Tests via make:** `make test-unit TEST_FILE=<file>.bats TEST_FILTER="<substring>"`.
- Work happens INSIDE the worktree `~/src/hug-scm.WT.313-extract-two-stream-single-file-guard-into-hug-cli-flags` on branch `313-extract-two-stream-single-file-guard-into-hug-cli-flags`.

---

### Task 1: Add the three helpers to hug-cli-flags (unit-tested first)

**Files:**
- Modify: `git-config/lib/hug-cli-flags` (append after `drain_pathspecs_after_separator`, ~line 478; header Functions list at lines 7–22)
- Test: `tests/lib/test_hug-cli-flags.bats` (append at end; harness at top loads `hug-output`, `hug-gum`, `hug-cli-flags`)

**Interfaces:**
- Consumes: `error_usage` (exit 2, from hug-output chain), `pathspec_pathspecs_into <nameref>` (lib, line ~413), `reject_multiple_files "<cmd>" [files...]` (lib, line ~526), shell-wide global `_pathspec_pathspecs`.
- Produces (later tasks rely on EXACTLY these signatures):
  - `pathspecs_nonempty` — no args; returns 0 iff `_pathspec_pathspecs` is set AND non-empty; `set -u` safe.
  - `error_unknown_option <token>` — one arg; `error_usage "Unknown option: $1. See 'hug help :pathspec'."`
  - `guard_single_file_candidates <cmd-label> <file-var-name> [pre-args...]` — writes the surviving candidate (possibly empty string) into caller scalar `<file-var-name>` via `printf -v`; performs F1/F2 checks, separator-data merge, `reject_multiple_files "<cmd-label>"`. Does NOT touch `$@`.

- [ ] **Step 1: Write the failing unit tests**

Append to `tests/lib/test_hug-cli-flags.bats`:

```bash
@test "pathspecs_nonempty: false when empty, true once the split collects data" {
  eval "$(parse_pathspecs)" # reset shell-wide global to empty
  refute pathspecs_nonempty
  eval "$(parse_pathspecs -- x.txt y.txt)"
  assert pathspecs_nonempty
}

@test "error_unknown_option: short-form template, exit 2" {
  run error_unknown_option --bogus
  assert_equal 2 "$status"
  assert_output --partial "Unknown option: --bogus. See 'hug help :pathspec'."
}

@test "guard_single_file_candidates: single candidate lands in the named var" {
  eval "$(parse_pathspecs)"
  unset file || true
  guard_single_file_candidates "hug t" file src/a.py
  assert_equal "$file" "src/a.py"
}

@test "guard_single_file_candidates: no candidates leaves the named var empty" {
  eval "$(parse_pathspecs)"
  file=""
  guard_single_file_candidates "hug t" file
  assert_equal "$file" ""
}

@test "guard_single_file_candidates: empty positional is loud (F1)" {
  eval "$(parse_pathspecs)"
  run guard_single_file_candidates "hug t" file "" extra
  assert_equal 2 "$status"
  assert_output --partial "Empty file argument."
}

@test "guard_single_file_candidates: pre-'--' unknown flag is loud, not a file" {
  eval "$(parse_pathspecs)"
  run guard_single_file_candidates "hug t" file src/a.py --bogus
  assert_equal 2 "$status"
  assert_output --partial "Unknown option: --bogus"
  refute_output --partial "got 2 files"
}

@test "guard_single_file_candidates: separator data stays data; second dash-named candidate hits cardinality (F2)" {
  eval "$(parse_pathspecs -- -foo.txt -bar.txt)"
  run guard_single_file_candidates "hug t" file
  assert_equal 2 "$status"
  assert_output --partial "hug t accepts only one file (got 2 files)."
  refute_output --partial "Unknown option"
}

@test "guard_single_file_candidates: lone dash-named file via -- survives" {
  eval "$(parse_pathspecs -- -baz.txt)"
  unset file || true
  guard_single_file_candidates "hug t" file
  assert_equal "$file" "-baz.txt"
}

@test "guard_single_file_candidates: mixed streams — pre flag rejected even when separator data exists" {
  eval "$(parse_pathspecs -- ok.txt)"
  run guard_single_file_candidates "hug t" file src/a.py --typo
  assert_equal 2 "$status"
  assert_output --partial "Unknown option: --typo"
  refute_output --partial "got 2 files"
}

@test "guard_single_file_candidates: two unknown flags report the LAST one (precedence parity)" {
  # Byte-order parity with the pre-extraction blocks (pr-fix round 1,
  # codex P2 #3843743270): they scan extras FIRST, survivor LAST, so
  # 'hug fa --bad1 --bad2' names --bad2. This row pins that order.
  eval "$(parse_pathspecs)"
  run guard_single_file_candidates "hug t" file --bad1 --bad2
  assert_equal 2 "$status"
  assert_output --partial "Unknown option: --bad2"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test-unit TEST_FILE=test_hug-cli-flags.bats TEST_FILTER="guard_single_file_candidates"`
Expected: FAIL — `command not found: guard_single_file_candidates` (and likewise for the other two names).

- [ ] **Step 3: Implement the three functions**

In `git-config/lib/hug-cli-flags`, extend the header Functions list (lines 7–22) with:

```
#   - pathspecs_nonempty: predicate — true iff _pathspec_pathspecs holds
#     separator data (the ONE nullsafe emptiness test).
#   - error_unknown_option: short-form unknown-option usage rejection
#     (exit 2 template shared across the single-file family).
#   - guard_single_file_candidates: the two-stream single-file guard —
#     F1/F2 checks + truthful cardinality + survivor out-param.
```

Append after `drain_pathspecs_after_separator` (currently ends ~line 478):

```bash
# Nullsafe emptiness predicate (#313): the ONE place that asks whether the
# shell-wide _pathspec_pathspecs global holds post-'--' separator data.
# Replaces the idiom [[ ${_pathspec_pathspecs[*]+x} &&
# ${#_pathspec_pathspecs[@]} -gt 0 ]] previously pasted at every consumer
# site (14 occurrences across bin at extraction time). Set -u safe: the [*]+x
# probe tolerates the UNSET state (helper consulted before any parse).
#
# Usage: if pathspecs_nonempty; then ...
pathspecs_nonempty() {
  [[ ${_pathspec_pathspecs[*]+x} && ${#_pathspec_pathspecs[@]} -gt 0 ]]
}

# Short-form unknown-option rejection (#313): the template repeated 10x
# (+2 $1 variants) across the single-file family at extraction time.
# Deliberately the SHORT form — the listing/status family long form
# ('Pathspecs beginning with '-'' require '--': <cmd> -- <tok>…') names the
# command, which this helper cannot know; pinned byte-for-byte by the
# conformance rows, so do NOT "enrich" it here.
#
# Usage: error_unknown_option "$1"   (inside a -* case arm)
error_unknown_option() {
  error_usage "Unknown option: $1. See 'hug help :pathspec'."
}

# The two-stream single-file guard (#313, spec §Design): ONE contract for the
# ~40-line block copy-pasted across git-fa/-fb/-fborn/-fcon. Semantics are
# the pre-extraction inline behavior, verified by the parameterized
# conformance rows (test_pathspec_conformance.bats:2183/:2206/:2298):
#   1. Pre-'--' stream over [pre-args...]: an EMPTY STRING is a loud usage
#      error (adversarial F1 — 'fa "" extra' must not silently analyze
#      nothing); first token becomes the survivor, the rest are tallied.
#   2. LOUD unknown-option check on the pre-'--' stream ONLY — EXTRAS
#      first, SURVIVOR last, mirroring the inline blocks' scan order so
#      'fa --bad1 --bad2' names --bad2 exactly as before (pr-fix round 1,
#      codex P2) — and BEFORE any separator data joins (adversarial F2:
#      checking post-merge misclassified separator DATA spelled '-name'
#      as an option).
#   3. Post-'--' stream: EVERY _pathspec_pathspecs token merges into the
#      tally VERBATIM (data by contract, never re-parsed as options).
#   4. reject_multiple_files over survivor + extras (truthful count naming
#      cmd_label).
#   5. Survivor ("" when none) is written to the CALLER-NAMED scalar.
#
# IN-PROCESS BY DESIGN, not eval-emitting like parse_pathspecs: this helper
# CALLS error_usage, and an exit inside $( ) kills only the subshell — the
# violation would not stop the script. Consequence: it cannot re-point the
# caller's $@; every call site keeps its own trailing
#   set -- ${file:+"$file"}
# line. That two-line idiom IS the API.
#
# Usage:
#   guard_single_file_candidates "hug fa" file "$@"
#   set -- ${file:+"$file"}
#
# NOTE: <file-var-name> is dereferenced dynamically (printf -v); a typo'd
# name fails SILENTLY (no set -u protection possible) — the unit row
# "single candidate lands in the named var" pins visibility; keep it green.
# Internal arrays carry the reserved __gsfc_ prefix (same collision
# discipline as drain_pathspecs_after_separator's __dps_).
guard_single_file_candidates() {
  local cmd_label="$1" file_var="$2"
  shift 2
  local survivor="" f
  local -a __gsfc_extras=()

  # Stream 1: pre-'--' tokens from the caller's "$@"
  for f in "$@"; do
    if [[ -z "$f" ]]; then
      error_usage "Empty file argument."
    fi
    if [[ -z "$survivor" ]]; then
      survivor="$f"
    else
      __gsfc_extras+=("$f")
    fi
  done

  # F2: loud option check BEFORE separator data joins.
  # Scan order = extras FIRST, survivor LAST — byte-order parity with the
  # inline blocks this replaces (codex P2 #3843743270: 'fa --bad1 --bad2'
  # must keep naming --bad2).
  for f in ${__gsfc_extras[@]+"${__gsfc_extras[@]}"}; do
    if [[ "$f" == -* ]]; then
      error_unknown_option "$f"
    fi
  done
  if [[ -n "$survivor" && "$survivor" == -* ]]; then
    error_unknown_option "$survivor"
  fi

  # Stream 2: post-'--' tokens are DATA by contract — no option re-parse
  local -a __gsfc_sep=()
  pathspec_pathspecs_into __gsfc_sep
  for f in ${__gsfc_sep[@]+"${__gsfc_sep[@]}"}; do
    if [[ -z "$survivor" ]]; then
      survivor="$f"
    else
      __gsfc_extras+=("$f")
    fi
  done

  reject_multiple_files "$cmd_label" "$survivor" \
    ${__gsfc_extras[@]+"${__gsfc_extras[@]}"}
  printf -v "$file_var" %s "$survivor"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test-unit TEST_FILE=test_hug-cli-flags.bats`
Expected: ALL PASS (new rows green; zero regressions in existing rows — notably the `parse_scoped_own_flags` rows around line 760 stay green).

- [ ] **Step 5: Commit**

```bash
git add git-config/lib/hug-cli-flags tests/lib/test_hug-cli-flags.bats
hug c -F - <<'EOF'
feat(cli-flags): add guard_single_file_candidates + small helpers (#313)

Three in-process helpers behind unit rows (red→green):
- pathspecs_nonempty — single source for the nullsafe separator-data
  test (was pasted 14x across bin);
- error_unknown_option — the SHORT-form template (10+2 sites); kept
  short deliberately: the long form names the command, which a
  token-only helper cannot know;
- guard_single_file_candidates — the whole two-stream single-file
  guard (F1 empty-positional loud reject, F2 pre-'--'-only option
  check, verbatim separator-data merge, truthful cardinality,
  survivor out-param via printf -v).

Why in-process, not eval-emitting: the guard calls error_usage, and an
exit inside $( ) kills only the subshell — violations would NOT stop
the script. Hence the caller keeps its own `set -- ${file:+"$file"}`;
that two-line idiom is the documented API.

Refs elifarley/hug-scm#313

Co-authored-by: CommandCodeBot <noreply@commandcode.ai>
EOF
```

---

### Task 2: Migrate git-fa/fb/fborn/fcon onto the guard

**Files:**
- Modify: `git-config/bin/git-fa` (~99–142), `git-config/bin/git-fb` (~97–137), `git-config/bin/git-fborn` (~94–133), `git-config/bin/git-fcon` (~95–135)
- Test (proof, unmodified): `tests/unit/test_pathspec_conformance.bats` rows at 2183, 2206, 2298

**Interfaces:**
- Consumes: `guard_single_file_candidates <cmd-label> <file-var-name> [pre-args...]`, `pathspecs_nonempty` (both from Task 1).
- Produces: no interface change — commands behave identically; exec lines untouched.

- [ ] **Step 1: Migrate git-fa**

Replace everything from the `# Cardinality + unknown-option guard` comment block through `set -- ${file:+"$file"}` (lines ~99–142) with:

```bash
# Cardinality + unknown-option guard: the two-stream single-file guard,
# extracted to hug-cli-flags (#313) — full WHY in that function's comment
# (unknown -* loud pre-'--'; post-'--' tokens are DATA reaching the
# truthful cardinality reject; survivor re-pointed onto "$@" below).
guard_single_file_candidates "hug fa" file "$@"
set -- ${file:+"$file"}
```

Then replace BOTH remaining nullsafe conditions:
- No-args branch (~line 62): `if [ $# -eq 0 ] && ! { [[ ${_pathspec_pathspecs[*]+x} && ${#_pathspec_pathspecs[@]} -gt 0 ]]; }; then` → `if [ $# -eq 0 ] && ! pathspecs_nonempty; then`
- Browse-root check (~line 95): `if $browse_root && { [[ $# -gt 0 ]] || { [[ ${_pathspec_pathspecs[*]+x} && ${#_pathspec_pathspecs[@]} -gt 0 ]]; }; }; then` → `if $browse_root && { [[ $# -gt 0 ]] || pathspecs_nonempty; }; then`

- [ ] **Step 2: Apply the same three edits to git-fb, git-fborn, git-fcon**

Identical replacement text except the label: `"hug fb"`, `"hug fborn"`, `"hug fcon"`. Anchor each replacement on the file's own `# Cardinality + unknown-option guard` comment block start and its `set -- ${file:+"$file"}` end — do NOT reuse line numbers (they differ per file: fb ~97–137, fborn ~94–133, fcon ~95–135).

- [ ] **Step 3: Prove behavior preservation**

Run: `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER="f-family"`
Expected: ALL PASS, ZERO test-content changes — rows 2183 (loud unknown option, parameterized over all four), 2206 (separator data + F1 empty positional), 2298 (browse-root × separator data) are the preservation contract.

Also run: `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER="single-file cardinality"`
Expected: ALL PASS (covers neighbors: llf, llfp/llfs, stats, fblame, h steps rows).

Sanity-probe one command manually against the fixture repo the suites use (any scratch git repo works):

```bash
cd /tmp && rm -rf gsfc-probe && mkdir gsfc-probe && cd gsfc-probe && git init -q . && echo pin > a.py && git add a.py && git -c user.email=t@t -c user.name=t commit -qm pin
hug fa src/a.py --bogus; echo "exit=$?"   # expect exit=2, Unknown option: --bogus
hug fa -- -dash.txt 2>&1 | head -2        # expect clean analysis attempt, no Unknown option
```

- [ ] **Step 4: Verify no stragglers in the four files**

Run: `grep -n 'file_candidates\|_pathspec_pathspecs\|Unknown option' git-config/bin/git-fa git-config/bin/git-fb git-config/bin/git-fborn git-config/bin/git-fcon`
Expected: ZERO hits for all three patterns in these four files (`_pathspec_pathspecs` is owned by the lib now, `file_candidates` lives inside the helper, `Unknown option` is emitted by the helper). Any hit = a missed edit.

- [ ] **Step 5: Commit**

```bash
git add git-config/bin/git-fa git-config/bin/git-fb git-config/bin/git-fborn git-config/bin/git-fcon
hug c -F - <<'EOF'
refactor(f-family): migrate fa/fb/fborn/fcon onto the extracted guard (#313)

Each ~40-line two-stream block collapses to
  guard_single_file_candidates "hug <cmd>" file "$@"
  set -- ${file:+"$file"}
and both nullsafe separator-data conditions adopt pathspecs_nonempty.

Behavior-preserving by construction: the parameterized conformance rows
(2183 loud unknown-option, 2206 separator-data+F1, 2298 browse-root)
pass UNMODIFIED — they pin messages, exit codes, and precedence for all
four commands. file_candidates/extra_files array names disappear from
the sites into the helper internals (standardization by construction).

Refs elifarley/hug-scm#313

Co-authored-by: CommandCodeBot <noreply@commandcode.ai>
EOF
```

---

### Task 3: Adopt small helpers in h-steps, fblame, stats-file

**Files:**
- Modify: `git-config/bin/git-h-steps` (~101, ~105, ~115, ~122), `git-config/bin/git-fblame` (~105), `git-config/bin/git-stats-file` (~125)
- Test (proof, unmodified): conformance rows 2124, 2141 (h steps), 2060–2118 + 2350 (stats file), 2092 + 2222 (fblame)

**Interfaces:**
- Consumes: `error_unknown_option <token>`, `pathspecs_nonempty` (Task 1).
- Produces: no behavior change; bespoke loops/ordering untouched.

- [ ] **Step 1: git-h-steps — swap the two template literals and two conditions**

Keep the surrounding comments; change only the calls/conditions:
- Line ~101: `error_usage "Unknown option: $f. See 'hug help :pathspec'."` → `error_unknown_option "$f"`
- Line ~105: `error_usage "Unknown option: $file. See 'hug help :pathspec'."` → `error_unknown_option "$file"`
- Line ~115 (browse-root compound): replace ONLY the third operand — `… || ${_pathspec_pathspecs[*]+x} && ${#_pathspec_pathspecs[@]} -gt 0 ]]; then` → `… || pathspecs_nonempty ]]; then`, giving:

```bash
if $browse_root && { [[ -n "$file" || ${#extra_files[@]} -gt 0 ]] || pathspecs_nonempty; }; then
```

⚠️ The function call must sit OUTSIDE `[[ ]]` (pr-fix round 1, codex P2 #3843743263): inside `[[ … ]]` Bash treats `pathspecs_nonempty` as a literal string (always truthy), so bare `h steps --browse-root` would always take the error branch and break interactive root-browsing. The `{ A || B; }` grouping preserves the original precedence `(file‖extras‖sepdata)` → `(file‖extras) ‖ sepdata`.
- Line ~122: `if [[ ${_pathspec_pathspecs[*]+x} && ${#_pathspec_pathspecs[@]} -gt 0 ]]; then` → `if pathspecs_nonempty; then`

Do NOT touch: the `--raw` consuming loop, the check ordering (browse-root sits between unknown-option check and separator merge here — observable and pinned by row 2268), or the `extra_files` naming (this file is NOT part of the four-clone standardization).

- [ ] **Step 2: git-fblame and git-stats-file — swap their `$1` variants**

- `git-fblame` ~105: `error_usage "Unknown option: $1. See 'hug help :pathspec'."` → `error_unknown_option "$1"`
- `git-stats-file` ~125: same replacement.

Leave fblame's bespoke `--churn/--since/--json` loop and stats-file's `collect_positional_args_before_flags` flow completely untouched.

- [ ] **Step 3: Prove behavior preservation for all three**

Run: `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER="h steps"`
Expected: ALL PASS (rows 2124 trailing-flag-loud, 2141 dash-leading-via-`--`, 2225 all-post-tokens-data, 2268 browse-root).

Run: `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER="stats file"`
Expected: ALL PASS (rows include trailing-flag-not-counted, unknown-option-loud F3, bare-`--` picker routing).

Add this pin row (the bot-noted coverage gap — no existing row drives `h steps --browse-root` alone) to the h-steps section of `test_pathspec_conformance.bats`, then re-run the filter above:

```bash
@test "single-file cardinality: h steps --browse-root ALONE still opens interactive browse (pr-fix round 1 pin)" {
  # Codex P2 #3843743263: a [[ ]] -embedded pathspecs_nonempty call would
  # be a constant-truthy string and reject exactly this invocation. The
  # pre-existing rows only cover --browse-root WITH an explicit path.
  psx_setup
  HUG_DISABLE_GUM=true run hug h steps --browse-root
  assert_failure
  refute_output --partial "--browse-root cannot be used with explicit paths."
  psx_reset
}
```

(The row asserts the failure is gum's "argument required" class, NOT the
mis-grouped browse-root rejection; with `HUG_DISABLE_GUM=true` the command
errors cleanly without entering the picker.)

Run: `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER="fblame"`
Expected: ALL PASS (churn-mode cardinality 2092, separator/lone-dash 2222).

- [ ] **Step 4: Verify the template is now single-source**

Run: `grep -rn "See 'hug help :pathspec'\.'$" git-config/bin | grep 'Unknown option'`
Expected: ZERO hits in bin — every unknown-option emission flows through `error_unknown_option` (the lib itself holds the literal once). Any hit = a missed site.

- [ ] **Step 5: Commit**

```bash
git add git-config/bin/git-h-steps git-config/bin/git-fblame git-config/bin/git-stats-file
hug c -F - <<'EOF'
refactor(pathspec): adopt small helpers in h-steps/fblame/stats-file (#313)

error_unknown_option replaces every remaining inline occurrence of the
short-form template (incl. the two $1 variants); pathspecs_nonempty
replaces h-steps' two nullsafe separator-data conditions.

Deliberately NOT migrated onto the shared guard: h-steps consumes --raw
in its own loop and orders the browse-root check between the
unknown-option check and the separator merge (observable, pinned by row
2268); fblame/stats-file keep bespoke collection flows. Their loops and
precedence are byte-preserved; conformance rows for all three pass
unmodified.

Refs elifarley/hug-scm#313

Co-authored-by: CommandCodeBot <noreply@commandcode.ai>
EOF
```

---

### Task 4: Document the new helpers + mutation receipts + sanitize

**Files:**
- Modify: `git-config/lib/README.md` (hug-cli-flags section, uniform-pathspec paragraph ending ~line 53)
- Test (mutation proofs): `tests/unit/test_pathspec_conformance.bats` rows 2183, 2206

**Interfaces:**
- Consumes: the three shipped functions (Tasks 1–3).
- Produces: README lists all public lib functions again; receipts recorded in the commit body.

- [ ] **Step 1: Extend the lib README**

In `git-config/lib/README.md`, extend the sentence enumerating the uniform-pathspec helpers (`…drain_pathspecs_after_separator` (…) — used by output_json_status, hug-git-json, and hug-select-files) so the list continues:

```
…, `pathspecs_nonempty` (predicate — true iff the split collected
  post-`--` pathspec data), `error_unknown_option` (the short-form
  unknown-option usage rejection, exit 2), and
  `guard_single_file_candidates` (the two-stream single-file guard:
  loud empty-positional + pre-`--` unknown-option checks, verbatim
  post-`--` data merge, truthful cardinality, survivor written to a
  caller-named variable — used by git-fa/-fb/-fborn/-fcon)
```

- [ ] **Step 2: Mutation receipt A — unknown-option check**

Temporarily delete the F2 check block from `guard_single_file_candidates` (the `if [[ -n "$survivor" && "$survivor" == -* ]]` + extras loop, ~8 lines). Run: `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER="f-family unknown option"`
Expected: FAIL (row 2183 red — proves the conformance net catches a guard regression). RESTORE the block verbatim; re-run the filter → green.

- [ ] **Step 3: Mutation receipt B — empty-positional check**

Temporarily delete the F1 arm (`if [[ -z "$f" ]]; then error_usage "Empty file argument."; fi`). Run: `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER="f-family separator"`
Expected: FAIL (row 2206's `hug $cmd "" extra` arm red). RESTORE verbatim; re-run → green.

- [ ] **Step 4: Full gate**

Run: `make test-unit` (whole unit suite)
Expected: ALL PASS.
Run: `make sanitize`
Expected: no unresolved findings (fold any formatting it applies into the commit).

- [ ] **Step 5: Commit**

```bash
git add git-config/lib/README.md git-config/lib/hug-cli-flags
hug c -F - <<'EOF'
docs(lib): document the #313 guard helpers; record mutation receipts (#313)

README's hug-cli-flags list gains pathspecs_nonempty /
error_unknown_option / guard_single_file_candidates — the README is the
discovery surface for the extraction pattern; an undocumented guard
would invite a fifth hand-rolled clone (roast F-002).

Mutation receipts (repo convention): dropping the helper's F2
unknown-option check reddens conformance row 2183; dropping the F1
empty-positional arm reddens row 2206 — the preservation net bites.
Both restored verbatim; full unit suite + sanitize green.

Refs elifarley/hug-scm#313

Co-authored-by: CommandCodeBot <noreply@commandcode.ai>
EOF
```

---

## Self-Review

- **Spec coverage:** lib functions + header list (T1), four clone migrations incl. all 12 nullsafe conditions (T2), h-steps/fblame/stats-file adoption (T3), README row (T4, roast F-002), mutation receipts (T4), conformance-as-proof (T2/T3), counts context (global constraints reflect the corrected figures). All spec sections land in a task.
- **Placeholder scan:** none — every code step carries full code; every run step carries the exact command and expected outcome.
- **Type consistency:** signatures match across tasks — `guard_single_file_candidates <cmd-label> <file-var-name> [pre-args...]`, `error_unknown_option <token>`, `pathspecs_nonempty` (no args), used identically in T1 tests, T2/T3 call sites.
