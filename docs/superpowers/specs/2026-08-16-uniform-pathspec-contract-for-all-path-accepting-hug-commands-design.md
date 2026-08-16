# Uniform Pathspec Contract — Design

**Date**: 2026-08-16
**PRD**: [elifarley/hug-scm#292](https://github.com/elifarley/hug-scm/issues/292) (user-ratified 2026-08-16)
**Audit**: `mgmt/superpowers/specs/pathscoping-audit.md` (2026-08-15, branch `pathscoping-report`)
**Branch**: `292-uniform-pathspec-contract-for-all-path-accepting-hug-commands`
**Delivery**: ladder of 3 PRs (A/B/C) off `origin/main`, this spec shared by all three

---

## 1. Problem

Every hug command that accepts file paths invents its own rules. Depending on the
command, `--` is a pathspec separator, an interactive-picker trigger, a
silently-discarded token, or — accidentally — a search for a file literally named
`--`. `--help` is swallowed as a pathspec on part of the status-listing family.
`hug w get -u <file>` errors out. Search commands (`lc`/`lcr`/`lf`) drop the `--`
separator before delegating, so a branch or tag named like a path can hijack the
query. Single-file commands accept multiple files silently and then produce broken
`--follow` output. Pathspec support is largely undiscoverable.

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
2. **`--help` / `-h` always shows help** — never swallowed as a pathspec.
   Consequence: every path-accepting command has a `show_help()`;
   `statusbase`, `sls`, `slu`, `slk`, `sli` gain one.
3. **Trailing bare `--` is position-disambiguated:**
   - on **action commands with a meaningful downstream pick** (`a`, `ss`, `su`,
     `sw`, `lc`, `lcr`, `lf`) → interactive file selection (unchanged behavior);
   - on **pure listing commands** (`sl`, `sla`, `sls`, `slu`, `slk`, `sli`, `slc`)
     → inert separator = full listing (git norms).
   - `hug a --` interactive semantics are untouched.
4. **Globs must be quoted** (`hug sla -- '*.md'`). Stated once, canonically, in
   `hug help :pathspec`; each command's help carries a pointer block, not a copy.
5. **Single-file commands** (`fa`, `fb`, `fblame`, `fborn`, `fcon`, `llf`,
     `h-steps`) reject more than one file with a clear, command-naming error.
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
1. trailing bare '--' detected → export HUG_INTERACTIVE_FILE_SELECTION=true, strip it
2. parse_pathspecs "$@"        → _pathspec_pre_args / _pathspec_pathspecs
3. parse_common_flags pre_args → common flags; caller's "$@" = remaining pre-args
```

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
| `-- <path>` | filters output as expected (scoped fixture repo) |
| quoted glob | filters correctly (`'*.md'`-style) |
| cardinality | single-file commands reject 2 files with the error naming the command |
| magic passthrough | `:(glob)` / `:(icase)` / `:(exclude)` smoke-level |

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
`-- "${_pathspec_pathspecs[@]}"` at the `exec hug ll` boundaries. The documented
trailing-`--` interactive picker is preserved. Delegation re-injection also
applies to the `--with-files` and interactive branches.

### 5.2 BUG-3 — `hug w get -u <file>` errors

`git-w-get:367` captures the first positional as `target_identifier` even when
`use_upstream=true`, so a file argument is mistaken for a commit ref and rejected
by the `--upstream`-exclusivity guard (`git-w-get:389-390`).

Fix: when `use_upstream=true`, skip target extraction — all remaining
positionals are files.

### 5.3 BUG-4 — `w get` restore missing `--`

`git-w-get:324`: `git restore --source="$commit" --worktree "${files_to_reset[@]}"`
becomes `... -- "${files_to_reset[@]}"` so files starting with `-` are never
misread as flags.

### 5.4 BUG-6 — `hug sh` silently overwrites the commit ref

`git-sh:86-88`'s `*` catch-all assigns every stray positional to `commit_ref`
(last one wins), so `hug sh HEAD -- src/` shows `src/`'s history instead of
erroring.

Fix in two steps (matching the delivery ladder):
- **PR-A (defect)**: stray positionals after the ref are rejected loudly.
- **PR-C (feature)**: `sh` gains pathspec filtering (§6.1), making the position
  meaningful; the conformance row flips from "rejects" to "filters" as a
  deliberate red→green.

### 5.5 BUG-1 + BUG-5 — `sl*` family batch migration

Affected: `statusbase`, `sl`, `sla` (via statusbase), `sls`, `slu`, `slk`, `sli`,
`slc`. Pattern A today: no `--` case in the arg loop (`git-statusbase:29-51`,
`git-sls:27-43`), no `show_help()` (except `slc`), `--help` swallowed as a
pathspec.

Migration (one batch, after the conformance suite exists):

- Adopt `parse_common_flags_with_pathspecs`; parse each script's custom flags
  (`--json`, `-c/--count`, `-q`, plus statusbase's `--long`/`-u`/`-uno`) from
  pre-args in the script's own loop.
- Pathspecs flow to `list_files_with_status` / `run_count_mode` after the split
  (no bare `--` ever reaches git as a pathspec).
- Trailing bare `--` = inert separator → full listing (git norms).
- Each gains `show_help()` with the PATH FILTERING pointer block (§7).

Batch rather than incremental: they share plumbing, and the suite makes the batch
safe while incremental would churn the same tests repeatedly.

### 5.6 Cardinality adoption

`fa`, `fb`, `fblame`, `fborn`, `fcon`, `llf`, `h-steps` adopt
`reject_multiple_files` (currently they pass multiple files to git where
`--follow` breaks silently).

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

## 7. Documentation layer

- **New article** `git-config/lib/python/articles/pathspec.md` → served as
  `hug help :pathspec` (same mechanism as `agents.md`/`hug-101.md`/`worktree.md`).
  Single source of truth: pathspec syntax, quoting rules and why they matter,
  the positional `--` duality (trailing-bare vs mid-stream), magic-pathspec
  passthrough, per-command support matrix.
- **PATH FILTERING pointer block** (two lines + examples, `git-sw:42-47` style)
  in every path-accepting command's help — points to the article rather than
  duplicating it. `cmod`/`cmoda` help gains it (their pathspec support is
  currently undocumented).
- **Category descriptions** for `@status`, `@show`, `@history` mention path
  filtering (help_search.py metadata) so scoping is discoverable while browsing.
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
change is exactly: valid orderings work, typos error loudly. (The surgical
BUG-3/4 fixes land earlier, in PR-A; convergence is the late-stage refactor.)

## 9. Delivery — the PR ladder

One spec (this document), three PRs off `origin/main`, each with its own
worktree, atomic story-telling commits, and a green conformance suite:

| PR | Contents | Exit criteria |
|---|---|---|
| **A — contract core** | Conformance suite (full matrix + characterization rows) · `parse_common_flags_with_pathspecs` · `reject_multiple_files` + cardinality adoption (§5.6) · BUG-2 (§5.1) · BUG-3/4 (§5.2/5.3) · `sh` loud-rejection (§5.4) | Suite green for already-correct commands; every defect red→green; zero behavior change elsewhere |
| **B — migration + docs** | `sl*` batch migration (§5.5) · `:pathspec` article + help blocks + category/README/completion updates (§7) | Bare `--` on listings = inert (deliberate test flip); docs complete; suite green |
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
   hijacked by a ref named `src/`.
5. Single-file commands teach immediately (`fa` rejects 2 files, naming itself).
6. `hug llu -- src/` and `hug sh HEAD -- src/` filter as documented.
7. A maintainer adding a new path-accepting command gets contract coverage by
   adding one table row — and cannot sequence parsing wrong by accident.
