# PR-C — Uniform Pathspec Contract, Final Rung (w-* family, llu, sh) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the w-* working-directory family (gateway + 4 scoped destructives + 4 whole-tree variants + 3 wip commands + w-get) and the log viewers `llu`/`sh` onto the ratified `-- <path>...` contract, closing elifarley/hug-scm#292.

**Architecture:** Family template replay of PR-B (approved office-hours approach A): each command adopts `parse_common_flags_with_pathspecs` → quiet rehydrate → own-loop with loud `-*` rejection → `validate_pathspecs_or_die` at entry → scoped summary gate. No new abstractions. Spec: `docs/superpowers/specs/2026-08-19-uniform-pathspec-contract-pr-c-w-family-llu-sh-design.md` (READ IT FIRST — its §2 per-class contract, §3 spike receipts, §4 registry, §6 flip table are this plan's source of truth).

**Tech Stack:** Bash (git-config/bin + lib), BATS conformance suite (tests/unit/test_pathspec_conformance.bats), Makefile targets only (`make test-unit TEST_FILE=…`, `make sanitize`).

**Standing rules for every task (repeat-on-purpose):** work ONLY in the worktree; mutations via hug (`hug a`, `hug c -F -`, never raw git); `make sanitize` before every commit; new commits never amend; tests via Makefile only; probes invoke worktree scripts directly (`export HUG_HOME=<worktree>; export PATH="$HUG_HOME/git-config/bin:$PATH"`) in a scratch repo — NEVER the installed `hug` dispatcher (stale binaries). Red-first: pin today's broken behavior with a failing test BEFORE the fix.

---

### Task 1: Class 0 — gateway `w`: fix the `wips` arm, exit 2 on unknown subcommand

**Goal:** `git-w` becomes a correct contract pass-through: the `wips` arm prepends its injected `--stay`, and the unknown-subcommand arm exits 2.

**Files:**
- Modify: `git-config/bin/git-w` (wips arm ~line 73; `*)` arm ~lines 83-99)
- Test: `tests/unit/test_pathspec_conformance.bats`

**Acceptance Criteria:**
- [ ] Red-first row: `hug w wips -- "draft"` today pollutes the branch name (`WIP/….draftSTAY`, stay not applied) — pinned failing before the fix, green after (branch slug contains `draft` only; the wip branch IS checked out when TTY-less flow allows, or verify via `--stay` reaching w-wip: probe `bash -x git-w wips -- msg 2>&1 | grep -e '--stay.*--'` shows `--stay` BEFORE the separator)
- [ ] `hug w badcmd` exits 2 with the usage text on stderr (today: exit 0)
- [ ] `hug w discard -- src/` still passes through untouched (characterization row)

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats` → all pass including the 3 new rows.

**Steps:**

- [ ] Write the failing tests (append to conformance suite; use the existing psx fixtures):

```bash
@test "gateway: w wips prepends --stay so post--- data stays the message" {
  # Spike receipt (spec §3): today the gateway appends --stay AFTER the
  # user's args, so 'w wips -- "draft"' drains --stay into the message
  # (branch WIP/….draftstay, stay never applies).
  local repo; repo=$(create_test_repo); cd "$repo"
  echo a > a.txt; hug a -- a.txt; hug c -m base >/dev/null 2>&1
  run hug w wips -- "draft"
  assert_success
  refute_output --partial "draftstay"   # the injected flag must not pollute
  run bash -c 'git branch --list "WIP/*"'
  refute_output --partial "stay"        # branch slug carries only 'draft'
}

@test "gateway: unknown subcommand exits 2, not 0" {
  local repo; repo=$(create_test_repo); cd "$repo"
  run hug w badcmd
  [[ "$status" -eq 2 ]]
}
```

- [ ] Run: `make test-unit TEST_FILE=test_pathspec_conformance.bats` → the two new rows FAIL (red confirmed).
- [ ] Fix `git-w`. The `wips` arm becomes (flag PREPENDED — injected flags are hug's, so they belong before the user's data zone):

```bash
wips)
  shift
  # PREPEND the injected flag (spec §2 Class 0): appending AFTER the
  # user's args put it past their '--' — it drained into the message
  # ('w wips -- "draft"' → branch WIP/….draftstay, stay never applied;
  # probed 2026-08-19) and post-PR-C would trip the known-flag-after--
  # rejection on a flag HUG injected.
  dispatch_w_subcommand "wip" --stay "$@"
  ;;
```

The `*)` arm: keep the usage print, end it with `exit 2` (find the current fall-through; the last `printf`'s status currently propagates as 0).

- [ ] Re-run the suite → green. `make sanitize`, commit:

```bash
hug a -- git-config/bin/git-w tests/unit/test_pathspec_conformance.bats
hug c -F - <<'MSG'
fix(w): gateway wips arm prepends --stay; unknown subcommand exits 2 (#292 PR-C)

WHY: probed live, 'w wips -- "draft"' polluted the branch name with the
gateway-injected flag (WIP/….draftstay) and stay never applied — and
post-migration the known-flag-after--- rejection would exit 2 on a flag
hug itself injected. 'w badcmd' printed usage but exited 0.

WHAT: wips arm prepends --stay before the user's args; unknown-subcommand
arm exits 2 (usage-error family). Red-first rows pin both.

HOW: flag injection belongs in the flag zone (before the user's data),
per the ratified contract. MSG
```

---

### Task 2: Rosters + red-first receipt rows for the whole family

**Goal:** Conformance suite gains the PR-C rosters, the master-roster membership diff, and every §3 spike receipt as a red-first row — BEFORE any command migrates.

**Files:**
- Modify: `tests/unit/test_pathspec_conformance.bats` (roster arrays near the existing PATHSPEC_* definitions; new @test blocks)
- Read: `docs/superpowers/specs/2026-08-19-...-design.md` §3 (receipt table — copy the probes verbatim)

**Acceptance Criteria:**
- [ ] Arrays added: `PATHSPEC_W_DESTRUCTIVE_ROWS=(w-discard w-purge w-zap w-wipe)`, `PATHSPEC_W_ALL_ROWS=(w-discard-all w-purge-all w-zap-all w-wipe-all)`, `PATHSPEC_WIP_ROWS=(w-wip w-unwip w-wipdel)`; `sh` appended to `PATHSPEC_SHOW_ROWS`, `llu` appended to `PATHSPEC_LOG_ROWS`
- [ ] Membership-diff row: every command in the three new arrays + `w-get` appears in ≥1 column test (a diff-style check that fails with a breadcrumb naming the missing command)
- [ ] Red rows pinning today's broken behavior (they FAIL now, flip green per-command as Tasks 3-11 land — mark each with the task that flips it in a comment): `w-discard -xX` silent exit 0; `w-wipe -xX` silent exit 0; `w-purge -xX` silent exit 0; `w-zap -- src/ --dry-run` preview-skip; `w-discard -- ':(exclude)build/' --dry-run` wrong no-match; `w-get -- --dry-run` commitish-swallow; `w-purge-all -- src/` and `w-zap-all --` "unknown option: --" exit 1; `wipdel -xX` exit 1; `llu -- src/` exit 1; `sh HEAD -- src/` exit 1
- [ ] Characterization rows pinning behavior that must NOT change: `w-wipe root.txt` confirm-cancel; `w wip -- "-fix"` message delimiter; `w-unwip -- WIP/…` branch delimiter; `w-get HEAD -- src/` scoped flow; `w zap src/ --dry-run` position-independent flag

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats` → the suite shows the new red rows failing (expected; they are the task-3-11 flip targets) and zero NEW failures among existing rows. NOTE: to keep CI green per-commit, land each red row in the SAME task/commit that flips it — the array definitions, membership diff, and characterization rows land here; the flip rows move with their migration tasks (write them in this task's branch of the worktree, then `hug w discard`-style stash-split is NOT needed: simply append each flip row inside its migration task).

**Steps:**

- [ ] Add the arrays beside the existing rosters (top of file, near `PATHSPEC_LOG_ROWS`):

```bash
# PR-C rosters (spec §5): ONE roster per behavioral class; the MASTER
# list is the single enrollment point — a PR-C command missing from every
# column below fails the membership-diff row.
PATHSPEC_W_DESTRUCTIVE_ROWS=(w-discard w-purge w-zap w-wipe)
PATHSPEC_W_ALL_ROWS=(w-discard-all w-purge-all w-zap-all w-wipe-all)
PATHSPEC_WIP_ROWS=(w-wip w-unwip w-wipdel)
PATHSPEC_PRC_MASTER=("${PATHSPEC_W_DESTRUCTIVE_ROWS[@]}" "${PATHSPEC_W_ALL_ROWS[@]}" "${PATHSPEC_WIP_ROWS[@]}" w-get sh llu)
```

- [ ] Append `sh` to `PATHSPEC_SHOW_ROWS` and `llu` to `PATHSPEC_LOG_ROWS` (existing arrays).
- [ ] Membership-diff row:

```bash
@test "PR-C master roster: every command enrolled in >=1 column" {
  # The PR-A under-transcription trap, closed by rule (spec §5): a command
  # that migrated silently untested. Each column loop below consumes one
  # roster; this row diffs master vs consumed and names the orphan.
  local enrolled
  enrolled="$(cat <<'EOF'
w-discard w-purge w-zap w-wipe
w-discard-all w-purge-all w-zap-all w-wipe-all
w-wip w-unwip w-wipdel
w-get
sh
llu
EOF
)"
  local orphan=()
  for cmd in "${PATHSPEC_PRC_MASTER[@]}"; do
    grep -qw "$cmd" <<<"$enrolled" || orphan+=("$cmd")
  done
  [[ ${#orphan[@]} -eq 0 ]] || fail "PR-C roster orphan(s): ${orphan[*]} — enroll in a column loop"
}
```

(When the real column loops exist per later tasks, replace the heredoc with the actual rosters the loops consume — the invariant is the diff, not the heredoc.)

- [ ] Characterization rows per the acceptance list (use `create_test_repo` fixtures; `run hug <cmd>` + `assert_*`; model after the existing inert/characterization blocks).
- [ ] `make sanitize`, commit: `test: PR-C rosters, membership diff, and characterization rows (#292 PR-C)`.

---

### Task 3: `w-discard` — full scoped-destructive migration

**Goal:** `w-discard` adopts the full contract: scoped destruction with validation, loud typos, post-`--` flag rejection, scoped dry-run/confirm flow, scoped summary suppression.

**Files:**
- Modify: `git-config/bin/git-w-discard` (parsing section; dry-run/confirm list build; the final summary)
- Test: `tests/unit/test_pathspec_conformance.bats` (flip the w-discard red rows + add two-sided scope rows)

**Acceptance Criteria:**
- [ ] `hug w discard -xX` → exit 2 family template (red row flips)
- [ ] `hug w discard -- ':(exlude)x/'` → exit 2 Invalid pathspec, nothing discarded
- [ ] `hug w discard -- ':(exclude)build/' --dry-run` → dry-run lists ONLY out-of-build unstaged changes (two-sided: change inside build/ absent, change outside present)
- [ ] `hug w discard -- src/ --dry-run` → exit 2 "flags must precede '--'"
- [ ] `hug w discard -s -- src/` → discards staged changes under src/ only; `-u` intersects likewise (OQ-2 cell: probe FIRST, pin what git does, encode exactly)
- [ ] Trailing bare `--` (OQ-1 cell): w-discard's interactive flow is confirm-based (no gum picker on the file list — verify by probe); if no picker, bare `--` is INERT — pin it
- [ ] Scoped invocation suppresses the trailing `hug s` summary; unscoped unchanged (byte-compare `hug w discard` before/after on a clean fixture)

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats` → w-discard rows green, nothing else regressed.

**Steps:**

- [ ] **Probe first** (scratch repo; `HUG_HOME` pinned): `w-discard -- src/` (trailing `--`), `w-discard -s -- src/`, `w-discard -u -- ':(glob)*'`, `w-discard -- ':(exclude)build/'` — record today's exact behavior; the acceptance rows encode the TARGET, the probe confirms the current parse shape (how flags are currently consumed) so the edit lands in the right place.
- [ ] **Write the failing rows** per the acceptance list (red-first).
- [ ] **Migrate the parse block** onto the template (model: git-sls:60-120, adapted — no `--picker` in the split call unless Task-3's probe found a picker; action flags are KEPT):

```bash
# Uniform pathspec split (#292 PR-C): flags before '--', pathspecs after.
eval "$(parse_common_flags_with_pathspecs "$@")"
# w-discard is an ACTION: -f/--dry-run/-y are its contract (no
# reject_action_flags — that helper is listing-only).
[[ ${HUG_QUIET:-} == T ]] && quiet=true
pathspec_pathspecs_into pathspecs
for arg in "$@"; do
  case "$arg" in
  -u | --unstaged) unstaged_only=true ;;
  -s | --staged)   staged_only=true ;;
  -*)
    error_usage "Unknown option: $arg. Pathspecs beginning with '-' require '--': hug w discard -- $arg. See 'hug help :pathspec'." ;;
  *)
    pathspecs+=("$arg") ;;
  esac
done
check_git_repo
validate_pathspecs_or_die ${pathspecs[@]+"${pathspecs[@]}"}
# A post-'--' token that EXACTLY spells one of OUR flags is a user error
# (spec §4): probed, 'w zap -- src/ --dry-run' silently SKIPPED the
# preview. Exact spelling only — './--dry-run' is a filename.
for p in ${pathspecs[@]+"${pathspecs[@]}"}; do
  case "$p" in
  --dry-run|-f|--force|-y|--yes|-u|--unstaged|-s|--staged|--browse-root)
    error_usage "Flags must precede '--': hug w discard $p -- <path>.... See 'hug help :pathspec'." ;;
  esac
done
```

Adapt the existing per-flag bodies (they carry the real semantics — keep each flag's current effect verbatim; the loop only relocates them). Route EVERY downstream sink (dry-run preview list, confirm list, the discard git call) through `${pathspecs[@]+"${pathspecs[@]}"}` behind a protective `--` — ONE validated set, so what was previewed is what is discarded.

- [ ] Scoped summary gate at the end:

```bash
if ! $quiet && [[ ${#pathspecs[@]} -eq 0 ]]; then
  exec hug s
fi
```

(No `local` at script scope — the PR-B Bash rule.)

- [ ] Flip the red rows green; add the two-sided exclude row; `make sanitize`; commit `feat(w-discard): uniform pathspec contract — scoped destruction, loud usage errors (#292 PR-C)` with WHY/WHAT/HOW/IMPACT.

---

### Task 4: `w-purge` — full scoped-destructive migration

**Goal:** Same contract as Task 3 for `w-purge` (categories: `-u` untracked, `-i` ignored).

**Files:** Modify `git-config/bin/git-w-purge`; test rows in conformance suite.

**Acceptance Criteria:**
- [ ] `hug w purge -xX` → exit 2 (red row flips)
- [ ] `hug w purge -- ':(exclude)build/' --dry-run` → lists untracked outside build/ only, excludes build/junk (two-sided)
- [ ] `hug w purge -i -- build/` → ignored files under build/ only (OQ-2 cell — probe the tracked-path refusal first: spike showed `purge -i -- src/` erroring "tracked or has staged change"; the scoped form must keep refusing tracked paths, with the family template)
- [ ] Post-`--` known-flag rejection; scoped summary suppression; bare trailing `--` disposition probed and pinned (purge HAS a browse-root picker flow — if the interactive arm uses gum, trailing `--` is PICKER: add `--picker` to the split call for the interactive arm only if today's no-args behavior is already interactive; otherwise inert. Probe decides; pin it.)
- [ ] Unscoped `hug w purge` byte-identical to today on the same fixture (capture before/after)

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats` → purge rows green, no regressions.

**Steps:** identical shape to Task 3 (repeat the template code with purge's flag arms `-u | --untracked`, `-i | --ignored` and the purge-specific post-`--` rejection list `--dry-run|-f|--force|-y|--yes|-u|--untracked|-i|--ignored|--browse-root`; the destructive call is the purge engine with `"${pathspecs[@]}"` behind `--`). Probe first, red rows first, migrate, flip green, sanitize, commit `feat(w-purge): …` same structure.

---

### Task 5: `w-zap` — full scoped-destructive migration

**Goal:** Same contract for `w-zap` (discard+purge combined; no category flags).

**Files:** Modify `git-config/bin/git-w-zap`; conformance rows.

**Acceptance Criteria:**
- [ ] THE dangerous receipt flips: `hug w zap -- src/ --dry-run` → exit 2 "flags must precede '--'" (today: preview silently skipped, one Enter from real destruction)
- [ ] `hug w zap --dry-run -- src/` → scoped preview (the safe spelling works; `w zap src/ --dry-run` position-independent form keeps working)
- [ ] `hug w zap -xX` → exit 2; malformed magic → exit 2; scoped summary suppression; unscoped byte-identical
- [ ] OQ-1 cell probed and pinned for zap's interactive flow

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats` → zap rows green.

**Steps:** Task-3 shape; flag arms are zap's own (`-f/--force`, `--dry-run`, `--browse-root`); the destructive engine routes through the one validated pathspec set. Probe first, red-first, migrate, sanitize, commit `feat(w-zap): …`.

---

### Task 6: `w-wipe` — full scoped-destructive migration

**Goal:** Same contract for `w-wipe` (worktree+index wipe; `<files...>` positional today).

**Files:** Modify `git-config/bin/git-w-wipe`; conformance rows.

**Acceptance Criteria:**
- [ ] `hug w wipe file.js` compat: bare positional still wipes exactly that file (characterization row stays green)
- [ ] `hug w wipe -xX` → exit 2 (red row flips); `hug w wipe -- ':(glob)src/**.py'` wipes only matches (two-sided row: in-scope wiped, out-of-scope untouched)
- [ ] Post-`--` known-flag rejection (`--dry-run`, `-f/--force`); scoped summary suppression; `w-wipe-all` NOT touched here (Task 7)
- [ ] `hug w wipe -- ./--dry-run` wipes the FILE named --dry-run (exact-spelling row from spec edge 6 — `./`-prefixed is not a spelling)

**Verify:** conformance suite green for wipe rows.

**Steps:** Task-3 shape; flag arms `-f/--force`, `--dry-run`; the wipe engine (checkout/restore + clean per its current implementation) takes the validated pathspecs behind `--`. Probe first, red-first, migrate, sanitize, commit `feat(w-wipe): …`.

---

### Task 7: Class 2a — the four `-all` variants

**Goal:** `w-discard-all`, `w-purge-all`, `w-zap-all`, `w-wipe-all` gain parsing hygiene: loud unknown dash-tokens exit 2, pathspec-after-`--` rejected with the whole-tree pointer, bare `--` inert.

**Files:** Modify the four `git-config/bin/git-w-*-all` scripts; conformance rows.

**Acceptance Criteria:**
- [ ] `hug w purge-all -- src/` → exit 2 `whole-tree command; use the non-scoped form to scope: hug w purge -- src/. See 'hug help :pathspec'.` (flips the "unknown option: --" exit 1 receipt)
- [ ] `hug w zap-all --` → INERT (≡ `zap-all`, pinned)
- [ ] `hug w <any>-all -xX` → exit 2 family template
- [ ] Unscoped behavior of all four byte-identical to today (fixture capture before/after)

**Verify:** conformance rows green; `make test-unit TEST_FILE=test_worktree*` unrelated suites still green (the -all commands appear in other suites — run the full `make test-unit` once here).

**Steps:** per script: locate its current arg loop; add the split + own-loop hygiene (no pathspec collection — post-`--` tokens are the rejection above, except a single bare trailing `--` which is dropped as inert); keep every existing flag arm verbatim. Red rows first per command. Sanitize, one commit `feat(w-*-all): whole-tree variants join the usage-error family (#292 PR-C)`.

---

### Task 8: Class 2b — wip family exit normalization (ONLY)

**Goal:** `w-wip`, `w-unwip`, `w-wipdel`: unknown dash-token rejection normalized from exit 1 to exit 2 + family template. NOTHING else changes — their `--` data semantics are preserved by design (spec §2 Class 2b, roast Major 2).

**Files:** Modify the three scripts' unknown-option arms; conformance rows.

**Acceptance Criteria:**
- [ ] `hug w wipdel -xX` → exit 2 family template (flips the exit-1 receipt); same for `wip`/`unwip`
- [ ] Characterization rows stay green: `w wip -- "-fix"` message delimiter; `w unwip -- WIP/…` branch delimiter; `w wips -- "draft"` from Task 1
- [ ] NO pathspec split added; no compliant loop rewritten (the existing loops already reject `-*` — only the exit code and message change)

**Verify:** conformance rows green; `make test-unit TEST_FILE=test_wip*` if such a file exists (check `ls tests/unit | grep -i wip`; if the wip tests live in another file, run that one).

**Steps:** per script, replace the unknown-option error path (e.g. w-wipdel:79's current exit-1 print) with `error_usage "Unknown option: $arg. … See 'hug help :pathspec'."`. Red rows first. Sanitize, commit `fix(w-wip family): unknown options join the exit-2 usage family (#292 PR-C)`.

---

### Task 9: `w-get` — finish the contract

**Goal:** `w-get` gains entry validation, post-`--` known-flag rejection, and the scoped summary gate (scope flow already works — characterization).

**Files:** Modify `git-config/bin/git-w-get`; conformance rows.

**Acceptance Criteria:**
- [ ] `hug w-get -- --dry-run` → exit 2 "flags must precede '--'" (flips the commitish-swallow receipt: today "Invalid commitish for --target: --dry-run" exit 1)
- [ ] `hug w-get HEAD -- src/` keeps working (characterization green); malformed magic → exit 2
- [ ] `-u/--upstream`, `-f`, `--dry-run`, `-y` remain action flags, position-independent
- [ ] Scoped invocation suppresses the trailing summary; unscoped byte-identical

**Verify:** conformance rows green; run the w-get-related suites (`grep -rl "w get\|w-get" tests/unit | xargs -I{} make test-unit TEST_FILE={}`).

**Steps:** locate w-get's existing pathspec plumbing (PR-A); add `validate_pathspecs_or_die` at entry (post-`check_git_repo`) and the post-`--` exact-spelling rejection list (`--dry-run|-f|--force|-y|--yes|-u|--upstream|--browse-root|--target`); summary gate as Task 3. Red rows first. Sanitize, commit `feat(w-get): complete the uniform pathspec contract (#292 PR-C)`.

---

### Task 10: `llu` — outgoing-commits pathspec filtering

**Goal:** `hug llu -- src/` lists outgoing commits touching src/; `--json` pathspec-aware; malformed magic and unknown dash-tokens exit 2.

**Files:** Modify `git-config/bin/git-llu`; conformance rows (llu enrolled in LOG rows per Task 2).

**Acceptance Criteria:**
- [ ] `hug llu -- src/` → only commits touching src/ in the outgoing range (two-sided: a commit touching only docs/ is absent; one touching src/ present — fixture with two commits)
- [ ] Flips the receipt: today "Unknown option: --" exit 1 → scoped list exit 0
- [ ] `hug llu --json -- src/` → valid JSON envelope scoped (counts reflect the scope; empty-envelope shape on zero matches — umbrella §6.2; validate `| python3 -m json.tool`)
- [ ] `hug llu -- ':(bogus)x/'` → exit 2; `hug llu -xX` → exit 2; outgoing RANGE computation unchanged (characterization: unscoped output byte-identical on the same fixture)

**Verify:** conformance rows green.

**Steps:** adopt the template (llu's flags: `--json`, `-q` per its current help — probe `git-llu --help` first and keep its real flag set); the range computation stays verbatim; separator + pathspecs append to the log invocation behind a protective `--`; trailing bare `--` inert (LOG-row behavior). Red rows first. Sanitize, commit `feat(llu): outgoing commits gain uniform pathspec filtering (#292 PR-C)`.

---

### Task 11: `sh` — commit details pathspec filtering

**Goal:** `hug sh <ref> -- src/a.py` shows the commit's details filtered to the path; range syntax (`-3`) stays DATA.

**Files:** Modify `git-config/bin/git-sh`; conformance rows (sh enrolled in SHOW rows per Task 2).

**Acceptance Criteria:**
- [ ] Flips the receipt: `sh HEAD -- src/` today "accepts one commit reference" exit 1 → ref + scoped details exit 0
- [ ] `hug sh HEAD src/a.py` bare positional ≡ scoped form (compat rule)
- [ ] `hug sh -3 -- src/` works: `-3` is range DATA, never eaten by the `-*` rejection (the one PR-C command with legal dash-data — spec Class 3; pin with a row)
- [ ] Malformed magic → exit 2; second non-path positional → the one-reference error at exit 2 (registry row); unscoped `sh HEAD` byte-identical

**Verify:** conformance rows green; run existing sh suites (`grep -rl "hug sh " tests/unit | xargs -I{} make test-unit TEST_FILE={}`).

**Steps:** template with an explicit data-arm for `-N`/`N` committish spellings BEFORE the `-*` rejection arm (probe `git-sh --help` and its current ref parsing; keep the existing detail renderer verbatim; append `"${pathspecs[@]}"` behind `--` to the underlying git show/diff calls). Red rows first. Sanitize, commit `feat(sh): commit details gain uniform pathspec filtering (#292 PR-C)`.

---

### Task 12: Documentation claim-flip sweep + CHANGELOG

**Goal:** Every artifact in spec §6 flips in this PR, mechanically from the flip table.

**Files:**
- Modify: `git-config/lib/python/articles/pathspec.md` (matrix loses all `not yet` rows; w-*/llu/sh sections; migration notes)
- Modify: `README.md` (sh/llu pathspec rows — umbrella user stories 16-17)
- Modify: `docs/commands/working-dir.md` (scoped destruction + narrowing-only property)
- Modify: `docs/commands/logging.md` (llu/sh rows — umbrella §7 "stale the moment PR-C lands")
- Modify: `docs/git-to-hug.md` (translation rows for scoped w-*/llu/sh forms)
- Modify: every migrated script's `show_help` (`:pathspec` pointer block — PR-B deferred these to "land with their features")
- Modify: `CHANGELOG.md` (script-migration section carrying the flip table verbatim)

**Acceptance Criteria:**
- [ ] Support matrix in the article has ZERO `not yet` rows; every PR-C command has a row with real worked examples
- [ ] The 10-row flip table from spec §6 appears in CHANGELOG's migration section verbatim
- [ ] Each migrated script's help shows the `hug help :pathspec` pointer (spot-check via `git-<cmd> --help | grep pathspec` for all 13+2 commands)
- [ ] `make docs-build` succeeds

**Verify:** `make docs-build` → success; the greps above non-empty.

**Steps:** work the file list top-down; each edit cites its flip-table row in the commit body. `make sanitize`, commit `docs: PR-C claim-flip sweep — article matrix complete, flip table, help pointers (#292 PR-C)`.

---

### Task 13: Full gate + membership re-check + PR readiness

**Goal:** Everything green; the ladder-close invariant verified.

**Files:** none modified (verification task; fix-forward if anything regresses).

**Acceptance Criteria:**
- [ ] `make test` → ALL green (BATS + pytest)
- [ ] `make sanitize` clean
- [ ] Conformance: zero red rows left; membership-diff row green (no orphan)
- [ ] The spec's §3 receipt table: every row's PR-C target column now describes observed behavior (spot-probe 5 rows in a fresh scratch repo through the WORKTREE binaries)
- [ ] `grep -c "not yet" git-config/lib/python/articles/pathspec.md` → 0

**Verify:** the commands above with their expected outputs.

**Steps:** run the gate; fix-forward anything found (each fix its own commit); final `make sanitize`; commit (if fixes) or no-op. The branch is then ready for `/code-roast` + codex review rounds before ship.
