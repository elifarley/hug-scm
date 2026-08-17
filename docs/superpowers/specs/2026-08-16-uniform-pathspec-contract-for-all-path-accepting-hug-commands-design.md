# Uniform Pathspec Contract — Design

**Date**: 2026-08-16
**PRD**: [elifarley/hug-scm#292](https://github.com/elifarley/hug-scm/issues/292) (user-ratified 2026-08-16)
**Audit**: `mgmt/superpowers/specs/pathscoping-audit.md` (2026-08-15; landed on this branch — commit `852b601`, cherry-picked from `pathscoping-report` — so the conformance row set and the Pattern A/B vocabulary resolve on-branch, not off a dangling reference)
**Branch**: `292-uniform-pathspec-contract-for-all-path-accepting-hug-commands`
**Delivery**: ladder of 3 PRs (A/B/C) off `origin/main`, this spec shared by all three

---

## 1. Problem

Every hug command that accepts file paths invents its own rules. Depending on the
command, `--` is a pathspec separator, an interactive-picker trigger, a
silently-discarded token, or — accidentally — a search for a file literally named
`--`. `--help` is swallowed as a pathspec on part of the status-listing family.
`hug w get -u <file>` errors out. Search commands (`lc`/`lcr`/`lf`) drop the `--`
separator before delegating, so when a branch or tag is named like a path the
invocation dies with git's "ambiguous argument … both revision and filename"
fatal (exit 128) instead of filtering (probe-verified: the failure is a loud
fatal, not a silent redirect — the consumed `--` is still the root cause)
query. Single-file commands accept multiple files and then fail confusingly —
mostly with raw git fatals, and on `stats-file` silently — instead of a clear,
command-naming error. Pathspec support is largely undiscoverable.

Users and agents cannot form one mental model of "how do I scope this command to
paths?" Every command is a small surprise, and surprises in a VCS front-end erode
trust.

All six audited defects were verified against source in this session (anchors in
§5); the status-listing family currently has **zero** `--` test coverage.

## 2. The Contract (normative)

Every path-accepting hug command obeys exactly these rules:

1. **`-- <path>...` filters output** with git-compatible semantics. The first `--`
   splits flags/refs from pathspecs; everything after it is path data, passed
   through verbatim.
2. **`-h` always shows help** — never swallowed as a pathspec *before the
   separator* (after it, `-h`/`--help` is path data by design, rule 1 — git
   norm). Consequence: every path-accepting command has a `show_help()`;
   `statusbase`, `sls`, `slu`, `slk`, `sli` gain one. **Scope note
   (probe-verified in PR-A's characterization)**: the `--help` LONG FORM on
   script-backed commands routes through git's man mechanism (exit 16, "No
   manual entry for git-<cmd>") — the guaranteed help surfaces are `-h` and
   `hug help <cmd>` (the repo's own CLAUDE.md documents this workaround).
   The conformance column asserts the `-h` surface; making `--help` print
   help directly would be a dispatcher-level change, out of scope here.
3. **Trailing bare `--` is position-disambiguated:**
   - on **action commands with a meaningful downstream pick** (`a`, `ss`, `su`,
     `sw`, `lc`, `lcr`, `lf`) → interactive file selection (unchanged behavior);
   - **with pathspecs present** (`hug su -- src/ --`), the picker is **scoped
     to those pathspecs** — it offers only matching files, and pathspecs are
     never silently discarded. (Today the reference recipe opens the picker
     over all files and drops `src/`; see §3.1.)
   - on **pure listing commands** (`sl`, `sla`, `sls`, `slu`, `slk`, `sli`, `slc`)
     → inert separator; any paths given still filter (`hug sls -- src/ --`
     lists files under `src/`).
   - **`us` is the exception that proves the taxonomy**: its selector is the
     zero-args fallback (it demands ≥1 path), not a `--` trigger — the
     trailing bare `--` is a no-op token for `us` in every position (§5.5).
   - `hug a --` interactive semantics are untouched. **PR-A probe finding**
     (characterization row, 2026-08-17): the PRD premise that `a -- <file>`
     was "verified already git-compatible" is REFUTED — `hug a -- new.txt`
     silently drops the pathspec and runs `git add -u`, staging files the
     user never named (git-a's loop breaks at the first `--` with empty
     remaining args). Pinned as a characterization row; fix (adopt the
     helper, keep the bare-`--` picker) filed as its own issue and slated
     for the PR-B migration batch.
4. **Globs must be quoted** (`hug sla -- '*.md'`). Stated once, canonically, in
   `hug help :pathspec`; each command's help carries a pointer block, not a copy.
5. **Single-file commands** (`fa`, `fb`, `fblame`, `fborn`, `fcon`, `llf`,
     `h-steps`, `stats-file`) reject more than one file with a clear,
     command-naming error.
6. **Git magic pathspecs** (`:(glob)`, `:(icase)`, `:(exclude)`) pass through to
   git verbatim — documented and smoke-tested, never re-validated or reimplemented.
7. **stdout/stderr discipline** holds on every touched command: data on stdout,
   human chatter on stderr.

## 3. Library: unified parser + cardinality guard (`git-config/lib/hug-cli-flags`)

### 3.1 `parse_common_flags_with_pathspecs`

One eval-able entry point lifting the sequence proven in production by the shared
diff driver (`_diff_cmd_setup`, `git-config/lib/hug-git-diff:464-483`) into the
common library. Fixed order:

```
1. trailing bare '--' detected → if caller declared picker mode, export HUG_INTERACTIVE_FILE_SELECTION=true;
                                  strip it either way
2. parse_pathspecs "$@"        → _pathspec_pre_args / _pathspec_pathspecs
3. parse_common_flags pre_args → common flags; caller's "$@" = remaining separator-free pre-args (positionals may still be paths when no `--` was given — e.g. `hug us src/`)
```

The helper **owns the picker-export lifecycle**: it takes a leading `--picker`
mode token — action commands pass it, listings do not. Without `--picker`,
a trailing bare `--` is consumed inertly and **nothing is exported** — the
export-leak class (a listing's delegation crossing `exec hug s` with the
variable set, `git-statusbase:106`) is deleted by construction rather than
guarded by an `unset` every listing must remember. The §4 inert-arm column
stays as the enforcement that listings were migrated without `--picker`.
`--picker` is a reserved first token: a pathspec literally named `--picker`
is unreachable before the separator (write `-- --picker`) — the same
git-norm reservation the article documents for files named `--` and
`--help`.

Step 1 strips only the trailing `--` token; step 2 still splits any mid-stream
`--`, so `_pathspec_pathspecs` survives alongside the picker flag. Callers
that act on the picker must pass those pathspecs into their selection call —
the scoped-picker clause of §2 rule 3. NOTE: `select_files_with_status`
**errors on positionals today** (`hug-select-files:654-655`, `error()` exits
1) — it must be **extended** to accept pathspecs: a dedicated `--)` arm
consumes everything after the separator verbatim, and the collected
pathspecs are forwarded through the selector's actual list calls — it
invokes `list_tracked_files`/`list_staged_files`/`list_unstaged_files`/
`list_untracked_files`/`list_ignored_files` directly
(`hug-select-files:690-755`; it does NOT call `list_files_with_status`,
which is the separate non-interactive function). This extension is
load-bearing: via `git-lc:149`'s
`if file=$(select_files_with_status ...)` the failure would otherwise be
silently swallowed as "Cancelled." with exit 0 — a no-op picker on the exact
command the scoped-picker feature exists for.

Callers then run their own command-flag loop on the (already path-free) `"$@"`.
The parsing-order invariant ("split pathspecs **before** parsing common flags",
currently only a comment at `git-config/lib/hug-cli-flags:21-23`) becomes
structural: the split lives inside the helper, so it cannot be sequenced wrong.

Constraints:

- **SCM-agnostic**: pure argument surgery — no git invocations, no git-specific
  assumptions. The library is symlinked into `hg-config/lib/`; the VCS boundary
  must hold. Mercurial command behavior is unchanged by this effort.
- **No observable change** to `parse_common_flags` or `parse_pathspecs`
  themselves: existing signatures and behavior are untouched; all adoption
  happens at call sites.

### 3.2 `reject_multiple_files`

Same library. Usage: `reject_multiple_files "<cmd-name>" "${files[@]}"` — errors
with `"<cmd-name> accepts only one file."` (exit 1) when given more than one
non-empty file argument. One-line adoption per single-file command (§5.5).

Unit tests for both functions go in `tests/lib/test_hug-cli-flags.bats` (the
existing CLI-flags suite already covers `parse_pathspecs`).

## 4. Conformance suite (the enforcement)

New `tests/unit/test_pathspec_conformance.bats`, table-driven — one row per
path-accepting command from the audit matrix (**all** of them, not only touched
ones; adding a command later is a one-line row):

| Column | Asserts |
|---|---|
| `--help` | shows help (contains `USAGE:`), exit 0 |
| `-- <path>` | filters output — per-test fixture repo via `create_test_repo` with a known file set, so each row's expectation (matching files present, non-matching absent) is derivable from the fixture |
| quoted glob | filters correctly (`'*.md'`-style, same fixture) |
| trailing `--` | **listing commands**: output equals the unfiltered run, exit 0, no picker — and with paths + trailing `--` (`hug sls -- src/ --`, rule 3's own example): output equals the path-filtered run, no picker (the exact cell where the export and filtering coexist); **action commands** (`a`, `ss`, `su`, `sw`, `lc`, `lcr`, `lf`): picker arm — regular output absent AND a positive picker observable (each row names the command's actual message: `a` → "No files selected." `git-a:217`; diff-driver commands → "No … available or cancelled." `hug-git-diff:525`; `lc`/`lcr`/`lf` → "Cancelled."), not absence-only, via the no-TTY technique at `tests/unit/test_status_staging.bats:1500-1517` (absence alone also passes on a crash) |
| cardinality | single-file commands reject 2 files with the error naming the command; **per-row expectation wins** over the audit matrix where this contract re-decides it (`lc`/`lcr`/`lf` rows expect multi-accept, `shp` expects its existing warning) |
| unknown flag | `hug <cmd> -xX` exits non-zero naming the flag — no silent `*) → pathspecs+=(...)` swallow |
| magic passthrough | `:(glob)` / `:(icase)` / `:(exclude)` smoke-level with named observables: `:(icase)` matches a case-variant file the bare glob does not; `:(exclude)` omits a file the base pathspec includes — "smoke-level" alone cannot fail a regression that mangles the magic into a literal while exiting 0 |
| `--json` + pathspec | where the command has `--json` (sl\* family, `lc`, `lf`, `llu`): parsed JSON on stdout (`python3 -m json.tool`) contains no file outside the pathspecs **and at least one file inside them** (the fixture guarantees matches exist) — two-sided, mirroring the `-- <path>` column; absence-only passes vacuously on an empty-but-valid envelope, the exact under-inclusive regression class |
| scoped picker | action commands (`a`, `ss`, `su`, `sw`, `lc`, `lcr`, `lf`): with pathspecs + trailing `--`, a stub `gum` first on PATH captures the candidate list it receives on **stdin** to a file (candidates flow via stdin, `hug-select-files:811`; gum's argv carries only filter/presentation flags and cannot observe scoping); assert **two-sided**: every captured candidate matches the pathspec scope AND at least one matching candidate is present (`candidates ⊆ matching(files) ∧ \|candidates\| ≥ 1`). External-behavior (process boundary), no internal variables — an "includes the pathspecs" assertion passes for the unscoped superset too, which is the pathspec-dropping regression this column exists to catch |

**Row staging** (the reconciliation between "all of them" and per-PR green):
each PR lands contract rows only for commands whose contract behavior it
completes; earlier PRs carry **characterization rows** capturing current
behavior, which flip red→green in the migrating PR. Pattern C/D/pass-through
rows (`shv`, `dd`, `l`, `ll`, `llf/`llfp`/`llfs`) carry per-row expectations
(`shv`/`dd` are ad-hoc but `--`-proper — own splits that pass pathspecs
through, so their rows assert current-correct behavior; the audit's Pattern A
roster entry for `shv` is amended accordingly):
`l`/`ll` forward unknown flags to git (git's own error is the observable)
and their trailing-`--` arm asserts pass-through to git's separator
semantics. Per-row expectations override stale audit marks — same latitude
as cardinality. The picker-arm observable is pinned per gum-presence (gum
installed → "No files selected." cancellation, exit 0; gum absent → the
error path, exit 1 — CI installs gum via `bin/optional-deps-install.sh:78`;
assert the deterministic branch for the environment the suite runs in).

The trailing-`--` column is load-bearing: the unified helper exports
`HUG_INTERACTIVE_FILE_SELECTION` unconditionally on a trailing bare `--`.
Nothing sets that variable in a listing command's tree today (setters are
only `parse_common_flags` and `_diff_cmd_setup`, neither called by Pattern A
scripts) — but the moment listings adopt the helper, the export WILL cross an
exec boundary (`git-statusbase:106` and `git-slc:123` both end with
`exec hug s`; seven scripts read the variable — `git-a`, `git-h-files`,
`git-lc`, `git-lcr`, `git-lf`, `git-w-get`, `git-wtsh`). Without the inert
arm, a migrated listing that honors the exported variable launches a picker
and still scores green on every other column; the `unset`-before-delegation
rule (§3.1) and this column together close it.

Testing decisions (from the PRD):

- **External behavior only** — exit codes, stdout data content, stderr chatter
  presence; never internal variables or call sequences.
- **Characterization before migration**: current behavior of the status-listing
  family is captured first (zero `--` coverage today), then the migration turns
  red tests green deliberately — the one intended behavior change (bare trailing
  `--` becomes inert on listings) lands as a visible test update.
- **Red-first for every bug fix**: each defect gets a failing test before its fix.
- All runs via `make` targets; CI is the arbiter for green (the local
  environment has known environment-dependent failures unrelated to this work).

## 5. Defect fixes and migrations (adopt the helper, keep behavior)

### 5.1 BUG-2 — `lc` / `lcr` / `lf` drop the `--` separator

`git-lc:58` runs `parse_common_flags "$@"` directly; the separator is consumed
and the exec boundary (`git-lc:151-171`) never re-injects it.

Fix: adopt `parse_common_flags_with_pathspecs`; re-inject
`-- "${_pathspec_pathspecs[@]}"` at **every delegation sink**. The documented
trailing-`--` interactive picker is preserved (and scoped to the pathspecs,
§2 rule 3). Prose enumerations are how branches get lost — the sinks, per
command, exhaustively:

| Command | Every sink that must receive `-- "${_pathspec_pathspecs[@]}"` |
|---|---|
| `lc` | JSON: `search_args` feed → `batch_code_search` (`git-lc:117-120`) · picker: `exec hug ll` (`git-lc:151`, `:153`) · `--with-files`: (`git-lc:168`) · plain: (`git-lc:170`) |
| `lf` | JSON: `search_args` feed → `batch_commit_search` (`git-lf:121-125`) · picker: (`git-lf:156`, `:158`) · `--with-files`: (`git-lf:173`) · plain: (`git-lf:175`) |
| `lcr` | picker: (`git-lcr:87`) · plain: (`git-lcr:99`) — no JSON branch |

The JSON branches are the trap: after the fix, `"$@"` there holds only
pre-args, and nothing else references `_pathspec_pathspecs` — implemented
without this table, `hug lc --json "term" -- src/` returns whole-repo results
while the human path filters correctly. Existing coverage: no test covers the
combination for `lc`/`lf`, but exactly **one** covers it for the family and
pins the **opposite** behavior — `tests/unit/test_status_staging.bats:1855`
("hug slc --json: pathspecs are ignored (documented contract)", green today,
plus `git-slc:31`'s help line "--json … (ignores pathspecs)"). PR-B flips
both; see §9. The guard idiom:

```bash
search_args+=("$@")
(( ${#_pathspec_pathspecs[@]} )) && search_args+=("--" "${_pathspec_pathspecs[@]}")
```

The `--json + pathspec` conformance column (§4) is the enforcement.

### 5.2 BUG-3 — `hug w get -u <file>` errors

`git-w-get:367` captures the first positional as `target_identifier` even when
`use_upstream=true`, so a file argument is mistaken for a commit ref and rejected
by the `--upstream`-exclusivity guard (`git-w-get:389-390`).

Fix: when `use_upstream=true`, skip target extraction — all remaining
positionals are files.

Two consequences, stated deliberately:

- The old `-u` + commit/integer combination guard (`git-w-get:389-390`) has no
  subject anymore: under `-u` every positional is a file, so
  `hug w get -u 2` restores a file literally named `2` from upstream. If no
  such file exists, git's "pathspec '2' did not match" error is the loud
  failure — replacing the old combination message.
- `hug w get -u` with **no** files restores **all** files — the semantics the
  help already documents ("Reset ALL files to the upstream branch state").
  Today this documented form actually errors: the flag is consumed by the
  custom-flag loop, so target extraction finds nothing and the commit-oriented
  "Missing target" error fires (`git-w-get:371-375`), leaving the
  `target_identifier == "-u"` branch at `git-w-get:379-381` unreachable for
  leading flags. Under the fix, the missing-target error applies only when
  `-u` is absent. The safety net for this destructive-adjacent disposition is
  the flow `-u`-alone actually dispatches to: zero positionals route to
  `reset_all_files` (`git-w-get:438-440`), whose preview prints the
  MODIFIED/RESTORED/REMOVED category lists (`:171-193`, `--dry-run` honored)
  before executing `git restore --staged --worktree .` (`:202`) plus removal
  of upstream-absent files (`:199-201`) — materially heavier than the
  per-file preview of the specific-files path (`:305-319`), and that is the
  shape its characterization test must expect. The `-u`-alone characterization
  set also covers a repo with **no upstream** (`get_upstream_commit` errors
  loudly, `:396`) — the form only becomes reachable after this fix.

### 5.3 BUG-4 — `w get` restore missing `--`

`git-w-get:324`: `git restore --source="$commit" --worktree "${files_to_reset[@]}"`
becomes `... -- "${files_to_reset[@]}"` so files starting with `-` are never
misread as flags.

### 5.4 BUG-6 — `hug sh` overwrites the commit ref with stray positionals

`git-sh:86-88`'s `*` catch-all assigns every stray positional to `commit_ref`
(last one wins). Probe-verified observable (PR-A characterization): `hug sh
HEAD -- src/` exits 1 with "Invalid commit reference: src/" — LOUD but
confusing: the user asked for HEAD scoped to `src/`, and the error names
their path as a bad ref. (The original audit's "silently shows the wrong
history" framing was wrong: ref validation catches the overwrite.)

Fix in two steps (matching the delivery ladder):
- **PR-A (defect)**: stray positionals after the ref are rejected loudly.
- **PR-C (feature)**: `sh` gains pathspec filtering (§6.1), making the position
  meaningful; the conformance row flips from "rejects" to "filters" as a
  deliberate red→green.

### 5.5 BUG-1 + BUG-5 — `sl*` family batch migration

Affected: `statusbase`, `sl`, `sla` (via statusbase), `sls`, `slu`, `slk`, `sli`,
`slc`. Pattern A today: no `--` case in the arg loop (`git-statusbase:29-51`,
`git-sls:27-43`), no `show_help()` (except `slc`), `--help` swallowed as a
pathspec. Probe nuances (PR-A characterization): the "filters by coincidence"
framing holds for `sl`/`sla`/`sls`; `slu`/`slk`/`sli` with `-- <path>` yield
empty output whose info message names the phantom pathspec ("No unstaged
files matching '--' 'src/' found.") — same root cause, different observable.
And the `--help` long form never reaches these scripts at all (git man
routing, rule 2); `-h` is the swallowed form.

Migration (one batch, after the conformance suite exists):

- Adopt `parse_common_flags_with_pathspecs`; parse each script's custom flags
  (`--json`, `-c/--count`, `-q`, plus statusbase's `--long`/`-u`/`-uno`) from
  pre-args in the script's own loop.
- The own-loops must **reject unknown flag tokens loudly** (consistent with §8
  and the conformance `unknown flag` column) — today's silent
  `*) → pathspecs+=("$arg")` swallow (`git-sls:38-41`) is what lets `-x`
  masquerade as a pathspec.
- Pathspecs flow to **every sink** after the split — same rigor as §5.1's
  table, because the sl\* batch has the same JSON trap `lc`/`lf` had:

  | Sink | Where | Pathspec status today |
  |---|---|---|
  | `list_files_with_status` | human listing arm (e.g. `git-sls:69`) | forwards pathspecs (works) |
  | `run_count_mode` | `-c/--count` arm (e.g. `git-sls:58-61`) | forwards pathspecs (works) |
  | `output_json_status "${list_opts[@]}"` | `--json` arm (e.g. `git-sls:66`) | **silently dropped** — its parse loop's catch-all is `*) shift ;;` (`output_json_status:45-47`), and the unified call builds args from filter types + `--cwd-only` only, so `hug sls --json -- src/` returns ALL staged files while the human path filters |

  The third sink is one of the ladder's **two** pieces of genuine **library
  work** (the other is the `select_files_with_status` pathspec extension,
  §3.1) — "adopt the helper at call sites" is not enough: `output_json_status`
  must collect pathspecs instead of discarding them, and plumb them through
  `output_json_status_unified` into the Python layer. **PR-B owns this fix
  explicitly** (contents and exit criteria below); without it the
  `--json + pathspec` column is red across the whole family and the likely
  improvised outcome is a loosened column shipping silent unscoped JSON.
  Note the flip target: for `slc` specifically the drop is not silent but
  **documented and pinned** — the green test at
  `tests/unit/test_status_staging.bats:1855` and `git-slc:31`'s help line
  "(ignores pathspecs)" both assert today's behavior and must be flipped
  with it (§9 PR-B).
  No trailing bare `--` ever reaches git as a pathspec (a mid-stream second
  `--` does — phantom, harmless under OR semantics, §7).
- Trailing bare `--` = inert separator → full listing (git norms). Migrated
  listings call the helper **without** `--picker`, so nothing is exported
  and there is nothing to unset before the `exec hug s` summary (§3.1 —
  the helper owns the picker-export lifecycle).
- Each gains `show_help()` with the PATH FILTERING pointer block (§7).
- **`us` joins the batch** (staging sibling). Its current behavior differs
  from the sl\* family and must be characterized as it actually is: `git-us`
  already has a two-stage parser with **loud unknown-flag rejection** — a
  `-*` case errors ("Unknown option: … See 'hug us --help'.",
  `git-us:92-94`) — so today `hug us -- src/` and `hug us --` both ERROR
  LOUDLY; `--` is not an accidental pathspec (the audit's staging row was
  mismarked "Pattern A / N/A" on this point — amended in the landed audit;
  the audit's §1 Pattern A roster, `pathscoping-audit.md:29-33`, correctly
  excludes `us`). **`us`'s selector is the zero-args fallback, not a
  trailing-`--` trigger**: `us` demands at least one path, and with none it
  opens the staged-file selector (`git-us:144-158`; empty staging → "No
  staged files to unstage.", exit 0) — which is why `us` is absent from
  rule 3's `--`-trigger list by design (its sibling `a` reaches its picker
  the other way, via `HUG_INTERACTIVE_FILE_SELECTION`, `git-a:199`).
  Migration hoists the split above the custom loop, and the trailing bare
  `--` becomes a **no-op token in every position**: alone → stripped,
  dispatches identically to zero args (the existing selector); after
  pathspecs → paths win (`us` is not on the scoped-picker list). The
  conformance row asserts output equality with the bare invocation
  (`hug us --` ≡ `hug us`), pinned per gum-presence (§4). Listed in §9
  PR-B's intended-change inventory: mid-stream `--` error → filter;
  trailing bare `--` error → zero-args dispatch. Pathspec sinks: the
  from-file/from-commit concat branch (`git-us:112-124`) and the plain
  branch both build `files_to_unstage` from the remaining args — the split
  must feed both.

Batch rather than incremental: they share plumbing, and the suite makes the batch
safe while incremental would churn the same tests repeatedly.

### 5.6 Cardinality adoption

`fa`, `fb`, `fblame`, `fborn`, `fcon`, `llf`, `h-steps`, **and `stats-file`**
adopt `reject_multiple_files`. Current behaviors differ and the red-first
characterization tests must expect the right one: the file-inspection family
passes extras straight to git, which **fatals loudly** — `--follow` commands
(`fa`/`fborn`/`fcon`/`llf`, e.g. `git-fa:81`) with "fatal: --follow requires
exactly one pathspec" (exit 128), and blame commands (`fb`/`fblame`) with a
bad-revision fatal — so their characterizations assert the fatal
(`assert_failure` + the message), not silent breakage; while `stats-file`
alone has a collect-all loop (`git-stats-file:115`) that **silently
ignores** extras (`file="${remaining_args[0]}"` at `git-stats-file:145`;
`remaining_args` is used nowhere after) — its characterization expects
silent-ignore. The rejection fix upgrades both classes from loud-fatal or
silent-ignore to a clear, command-naming error.

Closure over the audit's remaining SINGLE rows, so §4's "all of them" matrix
assigns every row:

- `llfp` / `llfs` inherit the rejection via their `exec hug llf` delegation
  (`git-llfp:61`) — no direct change needed.
- `shp` already warns on multiple files; the suite asserts the existing
  warning.
- `lc` / `lcr` / `lf` are **multi-pathspec delegators by design** (PRD story
  6: they delegate to `ll`, which handles pathspecs natively). The audit's
  SINGLE mark reflects their documented `<file>` shape, not the contract.

## 6. Features

### 6.1 `hug sh [ref] -- <path>...`

Pathspecs flow into `show_commits` (`git-config/lib/hug-git-show`) and from
there to the underlying `git show`/`git log` invocations with `--` appended.
Composes with `--llm`, `--stat`, `--no-stat`, and the N/-N syntax
(`hug sh 2 -- src/`). Sibling parity with `shc`/`shcp`/`shp`.

### 6.2 `hug llu -- <path>...`

The outgoing range `@{u}..HEAD` stays fixed; separator + paths are appended to
both the JSON path (`batch_log_output`, `git-llu:150-154`) and the human path
(`git log --graph ... @{u}..HEAD`, `git-llu:158`). Use case: "what is about to
be pushed for this subtree?"

The early-exit guard becomes pathspec-aware too, or the feature's flagship
path breaks: with 2 outgoing commits that don't touch `docs/`,
`hug llu -- docs/` would pass the unfiltered count check
(`git-llu:126`), print an empty log, then dump the full-repo status via
`exec hug s`. Instead: the count query becomes
`git rev-list --count @{u}..HEAD -- "${pathspecs[@]}"` (with the §10
empty-array guard); at zero matches with pathspecs present, emit a scoped
message ("📭 No outgoing commits touching \<paths\>") to **stderr** (rule 7)
and exit — never the full-repo status dump after an empty log. JSON mode
keeps its existing empty envelope (`{"commits":[],"summary":{"total_commits":0}}`,
`git-llu:129-130`) — no human message ever enters the JSON stream. Without
pathspecs, current behavior is unchanged. `hug llu --` (bare trailing) is
inert — `llu` is a listing, so the migrated script unsets the picker export
before its `exec hug s` (`git-llu:161`) exactly like the sl\* family.

## 7. Documentation layer

- **New article** `git-config/lib/python/articles/pathspec.md` → served as
  `hug help :pathspec` (same mechanism as `agents.md`/`hug-101.md`/`worktree.md`).
  Single source of truth: pathspec syntax, quoting rules and why they matter,
  the positional `--` duality (trailing-bare vs mid-stream), magic-pathspec
  passthrough, per-command support matrix, and the edge cases, scoped
  precisely: a **mid-stream** second `--` becomes a phantom (harmless)
  pathspec under git's OR semantics (`hug sl -- a -- b`) — but a **trailing**
  `--` is never a phantom: on action commands it triggers the picker (scoped
  to any pathspecs given, §2 rule 3 — never silently discarding them), and on
  listings it is inert. A file literally named `--` or `--help` is unreachable
  as a pathspec before the separator (git norm — after the separator it is
  path data, verbatim). The scoped picker covers the **separator spelling
  only**: `hug su src/ --` (a positional before the trailing `--`) is NOT a
  picker scope — the article says to use `hug su -- src/ --`. The article
  does **not** document the
  `HUG_INTERACTIVE_FILE_SELECTION` environment variable — it is an internal
  plumbing detail, and advertising it invites shell pre-exports that flip
  every reader script interactive.
- **Completions**: verified clean at the real locations —
  `completions/hug-completion.bash` and `completions/hug.fish` (repo root;
  there is no `git-config/completions/`): `sl*`/`sla` appear only in
  flag-completion lists (`hug.fish:234-241`) whose flag sets this effort
  does not change. Re-grep both files wherever a flag surface changes.
- **`CHANGELOG.md`**: the ladder's deliberate behavior flips (listings'
  inert trailing `--`, `us` flips, `w get -u` dispositions, scoped picker)
  land as entries at release time (repo norm: CHANGELOG bumps per release).
- **PATH FILTERING pointer block** (two lines + examples, `git-sw:42-47` style)
  in every path-accepting command's help — points to the article rather than
  duplicating it. `cmod`/`cmoda` help gains it (their pathspec support is
  currently undocumented).
- **`README.md` quick reference**: the `sl`, `sla`, and `sh` rows gain the
  `[-- <path>...]` surface — `README.md:546-548` currently omit it while
  their neighbors `shc`/`shcp`/`shv` at :550-552 already show it. There is
  **no `llu` row in README.md today** (zero grep hits) — PR-C **adds** one,
  with the pathspec surface.
- **`docs/commands/` VitePress pages**: `status-staging.md` (the `sl*`
  family's `-c`/pathspec composition note at `:143` and per-command entries
  at `:112`/`:122` — PR-B's inert trailing `--`, new `--help`, and the `us`
  flips land squarely here) and `logging.md` (the real `llu` row at `:13` —
  stale the moment PR-C lands). `sh` has no dedicated page; its new surface
  is carried by the README row, the translation table, and the article's
  support matrix. **`git-slc:31`'s help line "--json … (ignores
  pathspecs)" is removed** when PR-B makes it false — otherwise slc's help
  would say both "pathspecs filter" (pointer block) and "--json ignores
  pathspecs" (stale line).
- **`docs/git-to-hug.md` translation table**: add
  `git show <commit> -- <path>` → `hug sh <commit> -- <path>` and
  `git log @{u}..HEAD -- <path>` → `hug llu -- <path>` (the `git show` rows at
  `docs/git-to-hug.md:50-51` currently map only to `shp`/`shv`).
- **Category descriptions** for `@status`, `@show`, `@history` mention path
  filtering — they live in `git-config/lib/python/categories/{status,show,history}.toml`
  (loaded via `category_meta.py`), not in help_search.py — so scoping is
  discoverable while browsing.
- **`git-config/lib/README.md`**: document the parsing-order rule now that it is
  structural.
- **`docs/meta/hug-completion-reference.md`**: updated wherever a command's flag
  surface changes (standing repo norm).

## 8. `w-*` parsing convergence

`w-discard`, `w-purge`, `w-zap`, `w-get` currently mix break-early and
collect-all custom-flag parsing: on break-early scripts, custom flags must
precede common flags or are silently missed.

Converge on the repo's proven two-stage pattern: common flags via the shared
parser first, then a command-owned loop that **loudly rejects any unrecognized
flag token** (`Unknown option: -x`, exit non-zero). Custom flags
(`-u`/`--upstream`, `--mine`, …) become position-independent. Intended behavior
change is exactly: valid orderings work, typos error loudly — and
position-independence retires the old trailing-`-u` parsing branch
(`git-w-get:379-381`): post-convergence `hug w get HEAD -u` treats `HEAD`
as a file pathspec under the §5.2 rule ("under `-u`, positionals are
files"), which the `w get` help must state plainly. (The surgical
BUG-3/4 fixes land earlier, in PR-A; convergence is the late-stage refactor.)

## 9. Delivery — the PR ladder

One spec (this document), three PRs off `origin/main`, each with its own
worktree, atomic story-telling commits, and a green conformance suite. Rows
are staged per §4's row-staging policy: a PR lands contract rows only for
commands whose contract behavior it completes; earlier PRs carry
characterization rows that flip red→green in the migrating PR.

| PR | Contents | Exit criteria |
|---|---|---|
| **A — contract core** | Conformance suite (all matrix rows, staged per §4: contract rows for already-correct commands, characterization rows for the rest) · **lands the audit matrix** (`mgmt/superpowers/specs/pathscoping-audit.md` with the `us` staging row and the `shv` roster entry amended, so the row-set source matches §5.5's corrected understanding) · `parse_common_flags_with_pathspecs` (+ its `--picker` mode) · **`select_files_with_status` extended to accept pathspecs** (§3.1 — it errors on positionals today, `hug-select-files:654-655`; the second of the ladder's two library changes) · picker scoping on action commands (§2 rule 3: `_diff_cmd_setup`'s picker branch and the search-command pickers pass pathspecs into the extended `select_files_with_status`) · `reject_multiple_files` + cardinality adoption (§5.6) · BUG-2 (§5.1) · BUG-3/4 (§5.2/5.3) · `sh` loud-rejection (§5.4) | Suite green on every landed contract row (characterization rows record current behavior); every defect red→green; zero *unintended* behavior change (the intended ones being cardinality rejection §5.6, `sh` loud rejection §5.4, the `w get -u` dispositions §5.2, and picker scoping §2 rule 3) |
| **B — migration + docs** | `sl*` batch migration + `us` migration (§5.5) · **`output_json_status` pathspec plumbing through `output_json_status_unified` into the Python layer (§5.5 sink table — the ladder's second library change; the `--json + pathspec` column cannot go green without it)** · **flip the pinned old behavior**: `tests/unit/test_status_staging.bats:1855` ("hug slc --json: pathspecs are ignored (documented contract)") is updated to assert scoping, and `git-slc:31`'s "(ignores pathspecs)" help line is removed · `:pathspec` article + help blocks + category/docs updates (§7) | Bare `--` on listings = inert; `us`: mid-stream `--` error→filter, trailing error→zero-args dispatch (§5.5); `hug sls --json -- src/` scoped correctly; all deliberate test flips against true baselines; docs complete; suite green |
| **C — convergence + features** | `w-*` two-stage convergence (§8) · `sh` pathspec (§6.1) · `llu` pathspec (§6.2) | Position-independent flags + loud unknown-flag rejection; both features filter correctly; suite green |

## 10. Risks & guards

- **Regression risk in `sl*`** (most-used commands) → characterization before
  migration; batch only after the suite exists; CI is the arbiter.
- **getopt fallback path** (`parse_common_flags` passes unknown options through
  rather than erroring) → command-owned loops must still reject unknown flags
  loudly; the conformance `--help` row catches swallowing.
- **SCM boundary** → new helpers are pure argument surgery; no git calls.
- **Empty-array expansions under `set -u`** → use the repo's
  `"${arr[@]+…}"`-style guard at re-injection sites.
- **Exported picker flag crossing exec boundaries** → the helper owns the
  export lifecycle via its `--picker` mode (§3.1): listings call it without
  the mode, so a trailing bare `--` is consumed inertly and **nothing is
  exported** — the leak class (`git-statusbase:106` and `git-slc:123` both
  end with `exec hug s`) is deleted by construction. The trailing-`--`
  inert-arm conformance column stays as the backstop: it catches a listing
  wrongly migrated with `--picker` (or hand-setting the variable).
- **Doc perimeter is wider than command help** (lesson from the slc roast):
  articles, `docs/git-to-hug.md` translation tables, README code blocks, and the
  completion reference all enumerate command behavior and go stale — sweep them
  where flag surfaces change.

## 11. Out of scope

- `declare_pathspec_mode` metadata middleware → [elifarley/hug-scm#293](https://github.com/elifarley/hug-scm/issues/293)
  (revisit only if conformance drift recurs).
- Named persistent focus groups (`hug focus`) → [elifarley/hug-scm#294](https://github.com/elifarley/hug-scm/issues/294)
  (needs its own RFC; sketch has word-splitting and storage gaps).
- Any Mercurial-side command behavior change beyond keeping the shared library
  SCM-agnostic.
- Shell-completion generation from command declarations.
- Deep validation/reimplementation of git magic pathspec semantics (passthrough +
  smoke tests only).
- Changing `hug a --` interactive semantics or the position-disambiguated `--`
  duality itself.
- Extending pathspec support to further HEAD-movement commands (`h back`,
  `h files`) — flagged as debatable in the audit; deferred.

## 12. Success criteria

1. `hug <any-path-command> -- <path>` means the same thing everywhere; the
   conformance suite is green across the full audit matrix.
2. `hug <any-path-command> --help` shows help, everywhere.
3. `hug sla -- '*.md'` works first try; `hug help :pathspec` explains why the
   quotes matter.
4. `hug w get -u <file>` restores from upstream; `hug lc "x" -- src/` cannot be
   hijacked by a ref named `src/` — probe-verified shape: git fatals with
   "ambiguous argument 'src/a.py': both revision and filename" (exit 128),
   a broken invocation the separator preservation removes.
5. Single-file commands teach immediately (`fa` rejects 2 files, naming itself).
6. `hug llu -- src/` and `hug sh HEAD -- src/` filter as documented.
7. A maintainer adding a new path-accepting command gets **full-contract**
   coverage (all nine columns, rule 3's duality, JSON-scope purity, and
   picker scoping included) by adding one table row — and cannot sequence
   parsing wrong by accident.
