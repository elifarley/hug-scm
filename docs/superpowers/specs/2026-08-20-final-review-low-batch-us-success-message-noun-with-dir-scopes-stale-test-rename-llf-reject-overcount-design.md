# Design: final-review LOW batch — `us` success-message scope naming, stale conformance-test rename, `llf` reject-tally overcount (elifarley/hug-scm#302)

**Date:** 2026-08-20
**Branch:** `302-final-review-low-batch-us-success-message-noun-with-dir-scopes-stale-test-rename-llf-reject-overcount` (base `origin/main` @ d01fe10c, verified via `hug s -b -H`)
**Issue:** elifarley/hug-scm#302 — the remaining LOW findings from the final review of PR elifarley/hug-scm#299 (PR-B of the uniform pathspec contract, elifarley/hug-scm#292). The fourth finding (us scoped-empty exit harmonization) already landed in f2771623 and is NOT in scope.
**Ratified:** user-approved brainstorm, 2026-08-20 — approach "Observable truth" (section §Approach) and all four design sections.

---

## 1. Context and ground truth

All claims below were verified at HEAD (d01fe10c) by reading the cited sites and by live probe (scratch repo `/tmp/usprobe.vJWHow`, 2026-08-20), not inferred from the (unrecoverable) final-review notes.

### 1.1 What the final review flagged vs what HEAD already contains

- **Finding 1 (us success noun).** The issue quotes the motivating shape `Unstaged 1 file: ✓ src/a.py` and asks that a directory/glob scope not be reported with a noun implying a file argument, "mirror the Path-vs-File noun fix from f2771623 on the success path too", and — crucially — "Verify current wording at fix time." Probed at HEAD: the success path already reports **resolved** files (`hug us -- src/` → `Unstaged 2 files: ✓ src/a.py ✓ src/b.py`). The raw-pathspec echo that made the noun misleading (`✓ src/`, `✓ :(exclude)docs/`) was killed by 7f8ee973 ("resolved report") and is pinned by the conformance roast row at test_pathspec_conformance.bats:1429. The surviving gap is a **scope-naming** gap, not a noun error: the summary never says what the user scoped by.
- **Finding 2 (stale test names).** The issue cites two conformance/status_staging tests whose names assert the pre-PR-B coincidence while their bodies assert the post-PR-B contract. Exactly ONE is identifiable at HEAD: test_pathspec_conformance.bats:797 `characterization sl-family: -- src/ filters by coincidence (sl sla)` — its own comment says sl/sla "now filter for the RIGHT reason". The second could not be located; §5 records the search trail.
- **Finding 3 (llf reject overcount).** The issue points to "final-review notes" in the PR-B plan for the exact detail; those notes are not in the merged plan file (verified by grep) and are unrecoverable (§5). Derived from HEAD code: git-llf:70 passes `reject_multiple_files "hug llf" "$file" "$@"` and `$@` **includes flags** — `hug llf a.txt b.txt -1` tallies 3 "files" (a.txt, b.txt, -1) where only 2 are files. The current message (`hug llf accepts only one file.`, hug-cli-flags:531) carries no count, so the overcount is latent: the gate alone decides firing (git-llf:69, gate comment: "The GATE is authoritative; reject_multiple_files' tally only triggers the same message"). The finding is fixed by making the tally truthful **and** observable (§4.3).
- **F-005 (issue comment, 2026-08-19).** `us` run from a subdirectory reports matches root-relative (`✓ src/deep/z.py` from inside `src/`); the comment asks to "decide one spelling convention when touching this code". Decision: §2.5.

### 1.2 Anchors (verified file:line at d01fe10c)

| Anchor | Site |
|---|---|
| us success message | git-us:541-549 (`success "Unstaged $count $file_word:"` + ✓ lines) |
| us dry-run message | git-us:527-534 (`Dry run: Would unstage ${#report_targets[@]} file(s):`) |
| us error-path noun rule (f2771623) | git-us:485-488 (inline shape test: trailing `/`, `(`, `*`, `?`, `[`) |
| us report_targets (resolved report, 7f8ee973) | git-us:507-524 |
| us scoped-empty gate (`-f` disk test) | git-us:361-388 |
| us no-match info messages | git-us:331-340 (from-source arm), git-us:382-385 (plain arm) |
| one pathspec collection | git-us:104-108 (split seeds, positional own-loop joins) + git-us:117-139 (`*) pathspecs+=` git-parity arm) |
| count helper | hug-cli-flags:487-504 (`count_positional_args_before_flags`; `--` ends the count) |
| reject helper + message | hug-cli-flags:510-533 (`reject_multiple_files`, message at :531) |
| llf gate + reject | git-llf:63-73 |
| stats-file gate + reject | git-stats-file:121-134 (own-loop `*)` collects `remaining_args`; gate `-gt 1`) |
| h-steps own-loop (collects unknown `-*` into `file`/`extra_files`) | git-h-steps:60-86 (`--raw` arm + `*)` catch-all; parse_common_flags passes unknown flags through, hug-cli-flags:150-223) |
| f-family reject sites | git-fa:85, git-fb:85, git-fborn:82, git-fcon:83, git-fblame:98 |
| rename target | test_pathspec_conformance.bats:797 |
| resolved-report pin | test_pathspec_conformance.bats:1429 |
| cardinality pins (message flips) | test_pathspec_conformance.bats:1911, 1949, 1980, 1990, 2002; tests/lib/test_hug-cli-flags.bats:661 |
| flip-naming precedent | test_pathspec_conformance.bats:2197 (`contract a: … (#297, was characterization)`) |

---

## 2. Finding 1 — `us` success message names the scope (+ F-005)

### 2.1 The change

When at least one given pathspec argument is **scope-shaped**, the success and dry-run summaries name the scope set:

```
hug us -- src/     → ✅ Unstaged 2 files matching 'src/':     (+ ✓ resolved lines)
hug us src/a.py    → ✅ Unstaged 1 file:                      (unchanged — literal file)
```

### 2.2 Clause rule (corrected by worked examples)

- **Classifier — one function, two consumers.** Extract the f2771623 inline shape test (git-us:486) to a git-us-local `is_scope_shaped()` and use it at BOTH sites: the error-loop noun and the summary clause. The two sites must classify identically; one function makes that structural. The classifier stays git-us-local (rule of three — no second command needs it yet).
- **Emission rule:** emit the clause naming the **FULL scope set** when at least one member is scope-shaped; omit it entirely for all-literal invocations. (Initial draft said "name only the scope-shaped members" — worked examples refuted it: `us docs/note.md src/` unstages 3 files, and `matching 'src/'` would claim all 3 match `'src/'`. Git unions pathspecs, so "matching 'X' 'Y'" = matching ANY of the set = exactly what the count counts.)
- **Source of the clause:** the one `pathspecs` array — never `files_to_unstage` (which holds filtered source FILENAMES in the from-source arm; reading it would print source lines as the scope). `pathspecs` is the user's scope in every arm, including `us --from-commit HEAD -- src/`.
- **Quoting/order:** each scope single-quoted, space-separated, same `printf -v list "'%s' "` idiom as the no-match messages (consistency, display-only). Order = array order: post-`--` entries seed first, pre-`--` positionals join after (git-us:104-108) — deterministic; no sorting logic (YAGNI). Mixed placement `us a.py -- src/` → `matching 'src/' 'a.py':`.
- **Dry-run mirrors** from the same built clause string (one builder, two consumers — they cannot diverge): `Dry run: Would unstage 2 file(s) matching 'src/':`.
- **Zero-args/selector and from-source-without-scope runs print no clause.**

### 2.3 The `--`-invariance property

Classification rides **argument shape, never spelling**: both delivery paths (split post-`--` seeding vs own-loop positional arm) converge into the one `pathspecs` array before any sink reads it, so every with-`--` form is byte-identical to its bare twin. The separator changes delivery, never meaning — the uniform pathspec contract's core promise, made visible in the message layer.

### 2.4 Worked examples (fixture: staged `src/a.py`, `src/b.py`, `docs/note.md`; CWD = repo root unless noted)

**A — literal files, no clause (unchanged surface):**

| Command | Output |
|---|---|
| `hug us src/a.py` | `✅ Unstaged 1 file:` + `✓ src/a.py` |
| `hug us src/a.py src/b.py` | `✅ Unstaged 2 files:` + both ✓ lines |
| `hug us -- src/a.py` / `hug us -- src/a.py src/b.py` | identical to the bare twins |
| `hug us -- -foo.txt` | `✅ Unstaged 1 file:` + `✓ -foo.txt` |

**B — scope-shaped args, clause (the new surface):**

| Command | Output |
|---|---|
| `hug us src/` ≡ `hug us -- src/` | `✅ Unstaged 2 files matching 'src/':` |
| `hug us 'src/*.py'` ≡ `hug us -- 'src/*.py'` | `✅ Unstaged 2 files matching 'src/*.py':` |
| `hug us ':(exclude)docs/'` ≡ `hug us -- ':(exclude)docs/'` | `✅ Unstaged 2 files matching ':(exclude)docs/':` (magic matches via `(`) |
| `hug us src/ docs/` ≡ `hug us -- src/ docs/` | `✅ Unstaged 3 files matching 'src/' 'docs/':` |

**C — mixed literal + scope (full-set rule):**

| Command | Output |
|---|---|
| `hug us docs/note.md src/` ≡ `hug us -- docs/note.md src/` | `✅ Unstaged 3 files matching 'docs/note.md' 'src/':` + 3 ✓ lines |

**D — from-source:**

| Command | Output |
|---|---|
| `hug us --from-commit HEAD` / `hug us --from-file files.txt` | `✅ Unstaged N files:` — no scope given, no clause |
| `hug us --from-commit HEAD -- src/` / `hug us --from-file files.txt -- src/` | `✅ Unstaged N files matching 'src/':` — intersection result, scope named |

**E — zero-args:** `hug us` and `hug us --` both open the selector (bare trailing `--` inert, pinned) — no message, no clause.

**F — empty/error forms (UNCHANGED message families; they precede success, carry no clause):**

| Command | Output |
|---|---|
| `hug us src/` / `hug us -- src/` (nothing staged under it) | `ℹ️ No files matching 'src/' to unstage.` exit 0 |
| `hug us missing.txt` (absent on disk) | `ℹ️ No files matching 'missing.txt' to unstage.` exit 0 |
| `hug us real-but-unstaged.txt` | `❌ File 'real-but-unstaged.txt' is not staged.` exit 1 |
| `hug us real.txt nodir/` (nothing staged) | `❌ File 'real.txt' is not staged.` — mixed list keeps the loud per-file safety check (the gate requires a WHOLY shape-only scope for the polite arm) |
| `hug us -- ':(bogus)src/'` | exit 2 — `Invalid pathspec …` (the f2771623 gate) |
| `hug us --from-commit HEAD` (commit touches nothing staged) | `ℹ️ Source list is empty - nothing to unstage.` |

**G — dry-run:** `hug us --dry-run src/` → `ℹ️ Dry run: Would unstage 2 file(s) matching 'src/':` (+ `- file` lines, existing preview line). Literal-only dry-run wording unchanged.

**H — F-005 subdir spelling:** from inside `src/`, `hug us -- deep/` → `✅ Unstaged 1 file matching 'deep/':` + `✓ src/deep/z.py` — clause echoes the user's spelling, ✓ lines stay root-relative.

### 2.5 F-005 decision: root-relative kept

Matches are reported root-relative (`✓ src/deep/z.py` from inside `src/`): it is git's own spelling, the resolved-report roast already chose it, and one convention means CWD-independent output for scripters. Pinned by a new subdir probe row (§6).

---

## 3. Finding 2 — rename the confirmed stale test

- **Rename** test_pathspec_conformance.bats:797, following the repo's flip precedent at :2197:
  - old: `characterization sl-family: -- src/ filters by coincidence (sl sla)`
  - new: `contract sl-family: -- src/ filters via the split (sl sla; was characterization)`
- **Comment rewrite:** from "flip target PR-B" future-tense to flipped past-tense — PR-B Task 4 migrated sl/sla onto `parse_common_flags_with_pathspecs`; the split consumes the separator, so the row asserts the contract itself. The `sls` retirement note stays (it explains the `(sl sla)` row scope).
- **Body: byte-identical** — the two-sided filter assertions already assert the new contract; only the framing was stale.
- **Placement stays put** under the characterization section header — the flipped-a row precedent keeps flipped rows in place with a `was characterization` marker, and the neighboring `--help` row (:812) still genuinely characterizes dispatcher-level behavior.
- **The unlocatable second name:** §5 records the search trail; this task renames the one confirmed test. If the notes resurface, the second rename is a follow-up.

---

## 4. Finding 3 — class fix, observable ("Observable truth")

### 4.1 The class audit (all 8 reject_multiple_files call sites at HEAD)

| Call site | Collection passed | Verdict |
|---|---|---|
| git-llf:70 | `"$file" "$@"` — `$@` includes flags | **OVERCOUNTS** — fixed (§4.3) |
| git-stats-file:133 | `remaining_args` — own-loop `*)` also collects unknown `-*` tokens | **OVERCOUNTS** (shape `hug stats file a b --bogus` → tally 3, files 2) — fixed (§4.3) |
| git-h-steps:86 | `"$file" + extra_files` — own-loop `*)` collects unknown `-*` tokens (parse_common_flags passes them through, hug-cli-flags:150-223) | **OVERCOUNTS** (verified live: `hug h steps a.txt --bogus` fires the reject on 1 file + 1 flag) — fixed (§4.3) |
| git-fa:85 / git-fb:85 / git-fborn:82 / git-fcon:83 / git-fblame:98 | `"$@"` / `remaining_args` — every member flows to git after `--` as pathspec data | correct BY SEMANTICS (every token IS a candidate file there) — no change, message gains the truthful count via §4.2 |

### 4.2 Helper changes (hug-cli-flags)

1. **`reject_multiple_files` message gains a truthful count:** `error_usage "${cmd_name} accepts only one file (got ${#files[@]} files)."` — the helper only fires at ≥2 non-empty args, so plural is always right. Docstring flips to an explicit caller contract: pass candidate FILE arguments only, never flags.
2. **New shared slice helper:** `collect_positional_args_before_flags <out-array-name> [args...]` — collects leading non-`-*` tokens, cuts at the first flag (`--` included — it matches `-*`, matching the count helper's documented rule), reserved-prefix nameref discipline per module convention.
3. **One engine for the cut rule:** `count_positional_args_before_flags` is reimplemented as collect-then-count. The cut rule lives in exactly one place — duplicating it is precisely what the #298 extraction was created to kill.

### 4.3 Call-site adoptions

- **git-llf:** `extra_files=()` ← `collect_positional_args_before_flags extra_files "$@"`; gate `${#extra_files[@]} -ge 1` (same semantics: `$file` already shifted out); reject with `"$file"` + the slice only (nullsafe `${extra_files[@]+...}`). The `exec hug ll "$@" --follow -- "$file"` path is untouched — flags keep flowing to the log backend. The gate comment's "tally only triggers" caveat is deleted: gate and tally are now the SAME collection.
- **git-stats-file:** same slice pattern over `remaining_args`; gate stays `-gt 1` (its first file is still inside the array). **Delete its twin "tally only triggers" comment at git-stats-file:127-128** (F-004) — same rationale as llf: after the slice, gate and tally are the same collection there too, so the "do not simplify the gate away" comment's premise is false.
- **git-h-steps:** NOT the pre-loop slice — `--raw` legitimately follows the file (`hug h steps README.md --raw`, help:44) and is consumed by the own-loop's `--raw` arm, so the loop must run in full. Instead **loud unknown-flag + cardinality** after the own-loop: first reject every unknown `-*` with `error_usage "Unknown option: $f. See 'hug help :pathspec'."` (exit 2), then build the reject input for `reject_multiple_files` (codex #3829676849: filtering from the tally alone would have turned `--bogus` into silent success). A dash-leading file protected by `--` (`hug h steps -- -foo.txt`) is NOT an unknown flag — the check exempts the separator-protected `file` (visible via `parse_common_flags_with_pathspecs` / `_pathspec_pathspecs`; see plan Task 4, codex #3830105470). `--raw` stays consumed before either guard. The remaining `--bogus a.txt`-as-filename edge is the ordinary one-file-slot contract (first trailing `-*` is loud), orthogonal to the tally.

### 4.4 Deliberate pin flips (red→green, named in the commit body)

The message change turns six existing partial-match assertions red (the old trailing `.` stops being a substring): test_pathspec_conformance.bats:1911, 1949, 1980, 1990, 2002 and tests/lib/test_hug-cli-flags.bats:661. Each flips to the counted form, e.g. `assert_output --partial "hug llf accepts only one file (got 2 files)."`.

**Proof rows (the mutation tests for the finding — one per overcount site, so each fix is independently neuter-testable):**
- **llf:** `hug llf src/a.py docs/note.md -1` asserts `(got 2 files)`. Neuter (pass `"$@"` again) → `(got 3 files)` → red.
- **stats-file:** `hug stats file src/a.py docs/note.md --bogus` asserts `(got 2 files)`. Neuter (pass raw `remaining_args`) → `(got 3 files)` → red. (F-002 — the original spec had only the llf proof row; stats-file's identical-class fix was untestable in isolation.)
- **h-steps:** `hug h steps src/a.py --bogus` asserts LOUD `Unknown option: --bogus` exit 2 (codex #3829676849: the earlier draft asserted silent success after filtering the flag from the tally, which would hide the typo — now loud per the path-command contract). Neuter (drop the unknown-flag guard) → silent success or false cardinality → red. Separator-protected `hug h steps -- -foo.txt` pins that dash-leading files via `--` are NOT rejected (#3830105470).

Observable by construction; the pre-fix code had no observable surface for this finding at all (no count anywhere, gate alone decided firing) — which is why the message change is part of the fix, not scope creep.

### 4.5 New lib tests

`collect_positional_args_before_flags`: flag cut, `--` cut, empty input, dash-shaped tokens after a flag are NOT collected; count↔collect parity; `reject_multiple_files` counted-message shape at the helper level.

---

## 5. Recorded limitations and search trail

- **Second stale test name (finding 2):** searched — merged PR-B plan (no final-review section; grep for overcount/coincidence/final-review: zero hits), PR elifarley/hug-scm#299 reviews + issue comments via pr-status/gh (only codex P1/P2 threads + one cross-ref comment), issue elifarley/hug-scm#298 comments (closing note only), gstack project artifacts (autoplan restore is pre-implementation), session scratch dirs under /tmp/claude-1000 (no PR-B session), omnibrain dev+docs. The PR-B worktree and its session artifacts are deleted. Conclusion: the notes lived in the PR-B session and were never persisted. The spec scopes finding 2 to the one confirmed rename.
- **llf overcount detail (finding 3):** same notes, same fate — §4 derives the mechanism from HEAD code instead (issue said "Verify current wording at fix time" only of finding 1, but the same discipline applied).

## 6. Testing strategy

**Red-first sequence:**
1. Finding 1: clause pins first (red at HEAD), then implement. New conformance rows beside the existing `us (roast)` rows: dir scope, glob scope, multi-scope, mixed full-set rule, plain-literal-no-clause, from-source-with-scope, dry-run clause, subdir spelling (F-005 pin: clause echoes user spelling, ✓ lines root-relative).
2. Finding 3: lib tests red first, then helper + call-site adoptions; the six pin flips land in the same commit as the message change.
3. Finding 2: rename + comment rewrite; receipt = suite green + zero grep hits for the old name.

**Mutation receipts:** revert the clause → clause pins red; revert llf to `"$@"` → llf proof row red (`got 3 files`); revert stats-file to raw `remaining_args` → stats-file proof row red (`got 3 files`); revert h-steps tally-filter → h-steps proof row red (false reject returns); rename has no mutation analog (framing change — suite green + grep is the receipt).

**Verification (Makefile targets only, per project CLAUDE.md):** `make test-unit TEST_FILE=test_pathspec_conformance.bats`, `make test-lib TEST_FILE=test_hug-cli-flags.bats`, `make test-unit TEST_FILE=test_status_staging.bats`, then full `make test` before commit.

**Docs perimeter — Finding 3 (`accepts only one file`):** the repo-wide grep at d01fe10c hits, besides the six living assertions (conformance 1911/1949/1980/1990/2002 + lib 661), one in-suite prose site (conformance:118 section-header comment) and eight FROZEN historical records: CHANGELOG.md:74, docs/superpowers/plans/2026-08-17-…-pr-a.md:142/156/182/474, docs/superpowers/specs/2026-08-16-…-design.md:142, mgmt/superpowers/specs/pathscoping-audit.md:567. Policy: **living artifacts (the test suite) flip in the same commit**; **frozen records (CHANGELOG entries for shipped versions, ratified specs/plans, the audit) stay as-written** — rewriting them is churn on history that records what was true at the time. A NEW CHANGELOG entry documents the message change forward. (F-001 — the original spec's "one prose site" claim was based on a grep scoped to `git-config/`+`tests/` only; corrected.)

**Docs perimeter — Finding 1 (`Unstaged N files` / `Would unstage` message shapes):** grep across `docs/`, README, and tapes — zero stale hits at d01fe10c (every `Unstaged ` hit is the concept/flag, not the message form; no hug-us tape exists). (F-003 — receipt recorded; the perimeter is clean, this is record-keeping discipline for the next message-shape change.)

## 7. Error handling, stdout discipline, performance

- No new error paths: pure argument surgery; every gate, exit code, and validation order preserved. The f2771623 validation gate, the scoped-empty gate, and the per-file safety checks are untouched.
- Stdout discipline untouched: all changed messages ride stderr helpers (`success`/`info`/`error_usage`); no `--json` surface in this batch; zero non-JSON-bytes contracts unaffected.
- No new git calls, no new processes (the collect slice is a pure Bash loop; count's collect-then-count adds one array allocation — µs, same class as the plan's own perf review for these helpers).

## 8. Out of scope (recorded, not silently dropped)

- Second stale test name — §5; follow-up if the notes resurface.
- `us` scoped-empty exit harmonization — already f2771623. Raw-pathspec echo — already 7f8ee973.
- stats-file's downstream handling of unknown flags that survive its gate (`hug stats file a --bogus`) — pre-existing, orthogonal to the reject tally.
- Pre-existing classifier divergence in git-us: the scoped-empty GATE tests disk existence (`-f`, git-us:376), the NOUN/CLAUSE test shape chars. They diverge only for a file literally named with glob chars (e.g. existing `foo*`): gate treats it as a literal file (correct for safety), the clause names it as a scope (correct for intent — the spelling IS glob-shaped). Documented boundary, not resolved here.
- Clause ordering for mixed placement — post-`--` entries first (array order, §2.2); deterministic, no sort logic.
- h-steps file-slot ambiguity for `--bogus a.txt` (first trailing `-*` is now loud per §4.3; `hug h steps -- -foo.txt` stays data via the separator exemption) — orthogonal to the tally fix (§4.3).

## 9. Approach rationale (ratified)

Chosen: **Observable truth** — class input-hygiene fix + truthful count in the shared message. Rejected alternatives: *Silent hygiene* (input fix only) — zero observable diff means no pin can go red when the fix is neutered, violating this repo's probe-grounded, mutation-tested culture; *helper-level `-*` filter* — gate count and tally classification must stay in sync everywhere or a real second file can slip past the message (`hug llf -foo.txt extra.txt` shapes); disproportionate for a LOW batch.

Commits: atomic per finding (three implementation commits), flips named in commit bodies.
