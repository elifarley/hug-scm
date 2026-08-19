# Uniform Pathspec Contract — PR-B Design (migration + docs + follow-ups)

> Delta-spec under the ratified parent: `docs/superpowers/specs/2026-08-16-uniform-pathspec-contract-for-all-path-accepting-hug-commands-design.md` (§5.5, §7, §9 PR-B row). The parent's contract (§2), helper semantics (§3), and suite shape (§4) govern unchanged; this document adds PR-B's execution decisions and the post-parent-scope items. Tracking: elifarley/hug-scm#298 (checklist), elifarley/hug-scm#297, umbrella elifarley/hug-scm#292. PR-A landed as elifarley/hug-scm#296 (v1.11.0.0).

## 1. Scope decisions (user-ratified this session)

- **Full batch**: parent §9's PR-B row + all of #298 (review follow-ups, coverage combo-gaps, nullsafe sweep) + #297, in one PR. One review cycle; the conformance suite carries the safety.
- **ERRATUM (autoplan gate, 2026-08-17 — user decision):** the #297 FIX itself moves to a small fast-follow PR off main (both review models challenged batching a live bug behind the migration; user accepted). This spec's §3.4 semantics still govern that PR; PR-B keeps `a`'s scoped-picker arm + roster enrollment (its Task 9 CHANGED accordingly).
- **#297 semantics — pinned**: `hug a -- <file>` stages exactly the post-`--` positionals (git-compatible data/option boundary, matching the PR-A review invariant); a bare trailing `--` alone keeps today's `HUG_INTERACTIVE_FILE_SELECTION` picker unchanged. Parent §11 excludes changing `a`'s interactive semantics — respected: the picker trigger is untouched; only the silent drop (≡ `git add -u`) is fixed.

## 2. Commit order (refactor-first)

Six stages, atomic commits each; every stage leaves the full suite green:

1. **#298 refactors + coverage** (pure moves, no behavior change):
   - picker-forwarding DRY helper — one shared function for the `--`+pathspecs forwarding idiom repeated across `hug-select-files`, `hug-git-diff`, and the `lc`/`lf`/`lcr` pickers;
   - contract-comment dedup — one canonical parsing-order/pathspec comment in `hug-cli-flags`, referenced (not duplicated) at call sites;
   - non-flag-filter helper — the "count positionals only up to the first flag" cut currently encoded 2× (`llf`, `stats-file`); `w-get`'s shape guard is a DIFFERENT cut (rev-parse/integer classification of each arg under `-u`) and stays command-owned — it shares the helper only if the helper parameterizes the classifier, which is not required;
   - cross-module `_pathspec_pathspecs` accessor — ONE API, not alternatives: `pathspec_pathspecs_into <nameref>` in `hug-cli-flags`, populating a caller-named array nameref (empty array when none collected), so modules other than the parsing script (`hug-select-files` forwarding, delegation sinks) read the split through one function instead of touching the global array directly;
   - nullsafe-idiom consistency sweep, **bounded** (roast round 3: the repo-wide sweep is ~530 bare expansions across 86 files — an unbounded sub-project, not a "pure moves" stage item): qualifying sites = files touched by PR-B's stages or their directly-sourced libs, where the array is reachable-empty under `set -u`. The repo-wide remainder is NOT in PR-B — it stays a tracked follow-up note on elifarley/hug-scm#298 (closes the checklist item as "bounded sweep done, remainder tracked"). Stages 2–4 use the idiom at write time for every NEW array site they create;
   - the 3 remaining combo-gap tests: `--cwd`+pathspec on `list_tracked_files`, ignored-files pathspec forwarding, fblame churn-mode guard. (GAP-1, the lf picker cell, closed in PR-A `4f730e7`.)
2. **`sl*` + `us` batch migration** (§5.5) — onto the stage-1 helpers.
3. **`output_json_status` pathspec plumbing** + the pinned flips.
4. **#297 `hug a` fix**.
5. **Doc perimeter** (§7).
6. **Version/CHANGELOG** at ship time.

Rationale: migration consumes exactly the stage-1 helpers; refactoring after migration would re-touch every freshly migrated command and churn the same tests twice — the double-touch risk spec §10 flags for the most-used family.

## 3. Stage details

### 3.1 `sl*` migration (§5.5 mechanics, verbatim from parent)

Affected: `statusbase`, `sl`, `sla` (via statusbase), `sls`, `slu`, `slk`, `sli`, `slc`.

- Adopt `parse_common_flags_with_pathspecs`; each script's own loop keeps its custom flags (`--json`, `-c/--count`, `-q`, statusbase's `--long`/`-u`/`-uno`) parsed from pre-args.
- Own-loops **reject unknown flag tokens loudly** — today's `*) → pathspecs+=("$arg")` swallow (`git-sls:38-41`) is what lets `-x` masquerade as a pathspec.
- Pathspecs flow to **all four sinks** — the original three plus the trailing summary:
  1. human listing (`list_files_with_status`),
  2. `-c` count (`run_count_mode`),
  3. `--json` (`output_json_status` — stage 3.3),
  4. **the trailing `exec hug s` summary** (`git-statusbase:106`, `git-sls:81`): `git-s` has no pathspec support, so a scoped listing would end with a WHOLE-REPO summary ball — decided: **the summary is suppressed when pathspecs are active**. "Active" is pinned to **the collected pathspec array being non-empty** (NOT "`--` was seen" — the `--`-seen reading would suppress the summary on the inert bare `--`, breaking its equivalence with the unfiltered run). Conformance rows: summary present for bare `hug sls --` (≡ `hug sls`), absent for `hug sls -- src/`; suppression matches the existing `-q`/count-mode precedent of no trailing summary.
- Trailing bare `--` = inert separator → full listing. Migrated listings call the helper **without** `--picker`, so nothing exports and the `exec hug s` summary boundary is safe by construction.
- No trailing bare `--` ever reaches git as a pathspec.

### 3.2 `us` migration (§5.5)

Split hoisted above `us`'s custom loop. Mid-stream `--` error → filter. Trailing bare `--` becomes a no-op token in every position: alone → stripped, dispatches identically to zero args (the existing staged-file selector; `us` demands ≥1 path so it is NOT on the scoped-picker list); after pathspecs → paths win. Both `files_to_unstage` branches (plain `git-us:129-133` + from-file/from-commit concat `git-us:117-126`) fed by the split. Conformance row: `hug us --` ≡ `hug us` output equality, pinned per gum-presence — **fixture pinned to ≥1 staged file** (on an empty index both sides reduce to "No staged files to unstage." and the equality assert passes vacuously).

### 3.3 `output_json_status` plumbing + flips

- The status-JSON chain is **pure Bash end to end** (`output_json_status` → `output_json_status_unified` → `collect_git_files_json` → `list_*_files`) — there is no Python layer to plumb into. **This corrects parent §9's PR-B wording** ("into the Python layer"), which predates verification of the chain; the sink table below is authoritative. Every discard point gets a `--`-aware collector, mirroring `list_staged_files`' `--)` arm at `hug-git-files:40-49`:

  | Sink | Where | Pathspec status today | Fix |
  |---|---|---|---|
  | `output_json_status` parse loop | catch-all `*) shift ;;` (`output_json_status:45-47`) | discarded | collect pathspecs; own a `--` arm |
  | `output_json_status_unified` parse loop | unnamed catch-all `*) shift ;;` (`hug-git-json:141-144`) | discarded | same: `--` arm + collector |
  | `collect_git_files_json` → `list_*_files` | list calls | `--`-capable since PR-A | forward collected pathspecs after a protective `--` |

  The call boundary carries the same contract: `hug sls --json -- --cwd` (a file named `--cwd`) must scope, not toggle the scope flag — PR-A's data/option-boundary invariant applied to this chain.
- Flip `tests/unit/test_status_staging.bats:1855` ("hug slc --json: pathspecs are ignored") to assert scoping, **in the same commit as the behavior change** (a green-but-stale test asserting the old contract is a false oracle).
- **Claim-flip table** — every artifact asserting the old "slc --json ignores pathspecs" contract flips in that same commit (a deletion sweep, not a spot fix; help must not contradict the new behavior):

  | Artifact | Stale identifier | Edit |
  |---|---|---|
  | `git-config/bin/git-slc:31` | help flag line "(ignores pathspecs)" | remove the parenthetical |
  | `git-config/bin/git-slc:38-39` | help DESCRIPTION "with --json they are ignored by contract — the envelope always describes the full conflicted state" | rewrite: the envelope is pathspec-scoped |
  | `docs/commands/status-staging.md:138` | "`--json` emits the unified status envelope … Pathspecs scope the text listing (`--json` ignores them)" | rewrite the parenthetical to scoped |
  | `docs/superpowers/plans/2026-08-06-slc-conflicted-files.md:672` | unchecked box "Pathspec scoping works in text mode; `--json` ignores pathspecs (documented contract)" | check the box and annotate: flipped by PR-B (elifarley/hug-scm#298), scoping now applies to `--json` too |
  | `docs/superpowers/plans/2026-08-06-slc-conflicted-files.md:880` | verbatim embedded copy of the old-contract test ("hug slc --json: pathspecs are ignored (documented contract)") | annotate as historical: the embedded test text is the pre-PR-B quote of `test_status_staging.bats:1855`, flipped by PR-B — do NOT rewrite the historical quote itself |
  | `docs/superpowers/specs/2026-08-06-slc-conflicted-files-design.md:56` + `:131` | the RATIFIED slc design spec asserting the old contract twice — ":56 "explicit contract … deliberately not plumbed"" and ":131 "assert the full set, not the scoped one"" (the §10 rejection it cites is superseded by the parent PRD's §5.5 decision) | annotate as superseded by the parent spec + PR-B (elifarley/hug-scm#292 §5.5, elifarley/hug-scm#298): pathspecs now scope `--json`; annotate-don't-rewrite, same treatment as plan:880 |
- Two-sided JSON tests per migrated command: parses via `python3 -m json.tool`, no file outside the pathspecs AND at least one inside; `summary.*` counts must match the scoped array (the v1.7.0 comma-fragment lesson).

### 3.4 #297 — `hug a -- <file>`

Route `git-a` through the helper's split: pre-`--` behavior byte-identical; post-`--` positionals stage as explicit paths (`git add -- <paths>` with the protective separator); bare trailing `--` alone → the existing picker, unchanged. Red baseline: today `hug a -- file` stages `-u` (tracked-modified) instead — characterization row flips red→green. The post-stage summary line (`Staged N file(s). M staged total now.`) continues to print the TRUE count of what was staged.

**Scoped-picker arm (roast round 2 — the fourth arm §3.4 originally omitted):** `hug a -- src/ --` must open the picker SCOPED to `src/` (parent §2 rule 3 — `a` is on the picker list, and it is the highest-traffic command). Today `git-a`'s picker branch (`git-a:203-222`) builds `select_opts` without pathspecs, so the mixed arm opens an unscoped picker and silently discards `src/`. Fix: the picker branch reads the collected pathspecs via the stage-1 accessor `pathspec_pathspecs_into` (NOT the `_pathspec_pathspecs` global — stage 1's own rule) and appends them to `select_opts` behind a protective `--` using the stage-1 picker-forwarding helper; `a` joins `PATHSPEC_PICKER_ROWS` in the conformance suite (`tests/unit/test_pathspec_conformance.bats:52`, currently `(sw ss su)`) with a scoped-picker row — the roster under-transcription failure mode is this project's recorded PR-A lesson, so the row IS the deliverable, not an afterthought.

**Roster-enrollment mechanics (roast round 3):** 4 of the 5 picker column loops (`:252`, `:305`, `:356`, `:532`) dispatch per-command expectations through case arms with NO unknown-row sentinel — adding `a` without arming those loops makes the cells red or vacuously green on unset variables. Enrollment therefore carries, in the same commit: (1) `*)` sentinel arms (`__PSX_UNKNOWN_ROW__` breadcrumb, same idiom as the scoped-picker loop) in all four loops; (2) `a` case arms in the candidate-capture columns — safe there because the cancelling stub gum stages nothing (`a` is a mutator; the capture columns are read-only by construction, and `a`'s *selection* semantics get a dedicated standalone test, not a shared-column cell, precisely because selecting would mutate the fixture).

### 3.5 Doc perimeter (§7)

- New article `git-config/lib/python/articles/pathspec.md` → `hug help :pathspec`: syntax, quoting rules and why, the positional `--` duality (trailing-bare vs mid-stream), magic passthrough, per-command support matrix, edge cases (mid-stream second `--` = harmless phantom under OR semantics; trailing `--` never a phantom; files named `--`/`--help` unreachable pre-separator, verbatim data after it; scoped picker covers the separator spelling only — `hug su src/ --` is NOT a picker scope, use `hug su -- src/ --`). Does NOT document `HUG_INTERACTIVE_FILE_SELECTION`.
- PATH FILTERING pointer block (two lines + examples, `git-sw:42-47` style) — **pinned roster** (the literal "every path-accepting command" would enroll single-file and PR-C commands whose help would lie): the 7 existing carriers (`shc`, `dd`, `shcp`, `shp`, `sw`, `su`, `ss`) keep theirs; PR-B ADDS blocks to the migrated family (`statusbase`, `sl`, `sla`, `sls`, `slu`, `slk`, `sli`, `slc`), `us`, `a`, `lc`/`lf`/`lcr` (pathspec-supporting since PR-A, block never added), and `cmod`/`cmoda` (their pathspec support is undocumented). NOT enrolled: single-file commands (`fa`, `fb`, `fblame`, `fborn`, `fcon`, `llf`, `h-steps`, `stats-file` — they take a file argument, not pathspecs) and PR-C commands (`w-*`, `sh`, `llu` — their blocks land with their features).
- README `sl`/`sla` rows gain `[-- <path>...]`, matching the sibling `shc`/`shcp`/`shv` rows that already show the surface (`sh` row + new `llu` row are PR-C's, per parent §7).
- `docs/commands/status-staging.md`: inert trailing `--`, new `--help`, `us` flips land here.
- `docs/git-to-hug.md` translation rows; category TOMLs (`status`/`show`/`history`) mention path filtering; `git-config/lib/README.md` documents the parsing-order rule; `docs/meta/hug-completion-reference.md` re-grepped wherever flag surfaces changed; completions re-grepped at `completions/hug-completion.bash` + `completions/hug.fish`.
- CHANGELOG entry at release (repo norm), incl. the deliberate flips: listings' inert trailing `--`, **unknown-flag swallow → loud rejection across `sl*`** (a silent-to-loud flip on the most-used family — unlisted, it is indistinguishable from a regression at triage time), `us` flips, `slc --json` scoping, `a -- <file>` fix.

## 4. Testing strategy

- Every PR-B behavior change has an existing red baseline: PR-A's characterization rows (sl*/us/`a`) flip red→green stage by stage; `test_status_staging.bats:1855` flips with stage 3.3.
- New tests: #297 cells (file-after-`--` stages that file; bare `--` still picks; pre-`--` unchanged), the 3 combo-gap cells, JSON two-sided scoping across the family, unknown-flag loud rejection rows for each migrated script.
- Unknown-row sentinels and stub-gum harness reuse PR-A's `psx_*` helpers unchanged.

## 5. Exit criteria (parent §9 PR-B, verbatim)

Bare `--` on listings = inert; unknown flag tokens on `sl*` rejected loudly (was: silent pathspec swallow); `us`: mid-stream `--` error→filter, trailing error→zero-args dispatch; `hug sls --json -- src/` scoped correctly; all deliberate test flips land in the same commit as their behavior change, against true baselines; the §3.3 claim-flip table fully swept; docs complete; suite green. Plus: #298 checklist fully closed, #297 closed, `hug a -- <file>` stages exactly the named files.

## 6. Out of scope (unchanged from parent §11)

PR-C's `w-*` convergence, `sh`/`llu` pathspec features, README `sh`/`llu` rows; #293 metadata middleware; #294 focus groups; Mercurial behavior; completion generation; magic-pathspec reimplementation; `h back`/`h files` pathspecs.

## 7. Risks

- `sl*` is the most-used family → batch-only-after-suite (satisfied: PR-A landed the suite), CI arbiter, characterization flips red-first.
- Python envelope change (`output_json_status_unified`) → two-sided JSON tests + summary-count assertions on every migrated command.
- Stage-1 refactors touch picker plumbing used by PR-A commands → pure-move discipline, suite green between every commit, mutation-check the new helpers' tests.
- `a` is the highest-traffic command → #297 fix scoped to the post-`--` arm only; pre-`--` path byte-compared in tests.
