# us Scope-Block Extraction + sl* Family Templating — Design

Issue: elifarley/hug-scm#303. Motivating PR: elifarley/hug-scm#299. Second-roast finding F-003 (report 1013.pr299) folds the from-file batching into this extraction.

## Problem

Two simplification targets flagged by the code-roasts of elifarley/hug-scm#299:

1. **us scope block** (~200 lines inline in `git-config/bin/git-us`, lines ~187–388): origin-based normalization, staged-deletion union, root→CWD relpath climbing. The most intricate new logic in PR-B, currently testable only end-to-end.
2. **sl\* family boilerplate**: five near-identical scripts (`git-sls`, `git-slu`, `git-slk`, `git-sli`, `git-slc`, each ~180 lines) are a hand-copied template; every hand-copied comment block is future drift as the family grows.
3. **F-003 perf bug** (from the second roast): the from-file per-line canonicalization spawns one `git ls-files` process per list line — a 1000-line list costs 1000 subprocesses.

Timing note: the issue suggested landing alongside PR-C so new family members would be born on the template, but PR-C already landed (elifarley/hug-scm#292 closed); its spec defers "us-extraction + sl\* templating" to this cleanup. This work is now free-standing.

## Decisions (user-approved)

- **sl\* templating: shared entrypoint**, not a code generator or doc-only note. A `sl_family_main` function in a lib module; each script shrinks to help text + one call. Matches the repo's existing source-a-lib culture and keeps a single runtime source of truth.
- **us extraction target: new `hug-pathspec` lib module**, not an extension of `hug-git-files` (already 539 lines) and not in-script functions (no direct unit tests). Registered in `hug-git-kit`'s source list like every other module.

## Part 1 — `hug-pathspec`: extract the us scope block (+ F-003 batching)

### Module

New file `git-config/lib/hug-pathspec`. Registered in `hug-git-kit`'s source loop (one line, alongside `hug-git-files`). Double-load guard `_HUG_PATHSPEC_LOADED=1` per house style. Header comment states the module's concern: pathspec scope-set construction, source-list canonicalization, and root↔CWD relpath conversion.

### Functions

Nameref-out convention throughout (matches `pathspec_pathspecs_into` in hug-cli-flags).

#### `build_scope_set <out_arr> <pathspec...>`

Builds the ROOT-relative scope set for `<out_arr>`:

- tracked paths: `git ls-files --full-name -- <pathspecs>` (resolves CWD-relative input to root-relative output)
- ∪ staged deletions: `git diff --cached --name-only --diff-filter=D --no-renames -- <pathspecs>`
  - `--diff-filter=D`: index entries for staged deletions are gone from `ls-files`
  - `--no-renames`: with rename detection ON, a staged `git mv old new` is one R-status change whose D half never emits `old`; splitting it puts `old` back in the set
- Join without trailing blank line (a phantom empty element is a bad assoc-array subscript under `set -u`)
- Invalid pathspec → `error_usage "Invalid pathspec in unstage scope. See 'hug help :pathspec'."` (same die-loudly convention as `validate_pathspecs_or_die`)
- The unborn-HEAD guard for `--with-tree=HEAD` lives inside this function (probed: unborn HEAD makes `--with-tree` fatal)

#### `canonicalize_source_lines <out_resolved> <out_unresolved> [--from-commit] <line...>`

Canonicalizes source-list lines (from `--from-file` / `--from-commit`) to root-relative paths.

- `--from-commit`: lines pass through untouched (root-relative BY CONSTRUCTION — `extract_files_from_commit` diffs from the repo root). Resolving them against CWD wrongly rejected the legitimate case `us --from-commit HEAD -- .` run from sub/.
- `--from-file` (default): **THE F-003 FIX** — the list resolves through ONE
  batched call, `git ls-files -z --full-name ${tree_opt[@]+"${tree_opt[@]}"}`
  with the input lines as its pathspec arguments, collected via NUL-delimited
  mapfile (the reference strategy below adds per-line calls ONLY for
  directory/glob-shaped lines). Plain-filename lists: one git process total.
  The collector DROPS empty records (a trailing
  NUL yields a final empty element under bash's NUL-delimited read; an empty
  element would become `in_scope[""]` / "File '' is not tracked" — the exact
  phantom-subscript class git-us already guards at lines 238–245).
- **Unresolved-line detection is a SET DIFFERENCE over RAW INPUT LINES, not over
  git's output paths** — this representation choice is load-bearing (roast C-001,
  probed on git 2.43.1): one input line can produce MANY output paths (a
  directory spec `docs/` fans out to every file under it; a glob line expands),
  and duplicate input lines collapse to one output line (`git ls-files --full-name
  -- tracked.txt tracked.txt` emits one). A difference computed against OUTPUT
  paths would mark legitimately-resolving directory/glob lines "unresolved" —
  resurrecting false failures on exactly the scoped-input forms PR-B fought for.
  Implementation contract: feed the lines as pathspec arguments of the ONE
  batched call; a line is RESOLVED iff it contributes ≥1 output path, UNRESOLVED
  otherwise; unresolved lines land in `<out_unresolved>` so they still die loud
  downstream ("File 'X' is not tracked by git."), never vanish into a misleading
  no-match. Git attributes outputs to pathspecs nowhere in its porcelain output,
  so per-line attribution needs a strategy chosen at implementation time; the
  reference strategy keeps the common case at ONE git call: classify each line
  locally as LITERAL-SHAPED (no glob metachars `*?[`, not a directory spelling,
  normalized spelling — strip `./`, collapse `//`) or FREE (everything else);
  LITERAL lines resolve-by-membership against the batched NUL-delimited output
  set (zero extra processes); FREE lines (directory/glob spellings — rare in
  from-file lists) keep today's per-line `git ls-files --full-name` call so their
  fan-out resolves exactly as now. A list of 1000 plain filenames = exactly one
  git invocation plus local set lookups.

#### `root_to_cwd_relpath <path>`

Prints the CWD-relative spelling of a root-relative path:

- prefix-strip when under `$(git rev-parse --show-prefix)`
- else `../`-climb, one level per prefix component (real relpath conversion, NOT prefix-stripping alone — a `:(top)` scope from sub/ must produce `../root.txt`, not bare `root.txt`)
- identity at repo root (`show-prefix` = '')

Pure string logic over two inputs (path, prefix) → directly unit-testable.

### git-us after extraction

The intersection block reduces to orchestration glue that stays in git-us:

1. `build_scope_set scope_files ...`
2. assoc membership filter (O(n+m), stays — it's glue)
3. `canonicalize_source_lines canonical_source unresolved_source ...`
4. per-line `root_to_cwd_relpath` loop
5. `files_from_source=(cwd... unresolved...)` (unresolved appended last — pinned ordering)
6. scoped-but-empty gate: empty source → "Source list is empty - nothing to unstage."; else no-match message with quoted pathspecs; both exit 0

All user-visible behavior pinned unchanged: exact messages, exit codes, empty-source vs no-match attribution, unresolved-append-last ordering.

### Tests (Part 1)

New `tests/lib/test_hug-pathspec.bats` covering:

- deletion union: staged `rm` appears in scope set; `--no-renames` splits a staged rename's D half
- unborn HEAD: build works, no `--with-tree` fatal
- batched canonicalization: mixed resolvable/unresolvable lines split correctly; a 500-line list of PLAIN FILENAMES triggers exactly ONE real `git ls-files` call (assert via a PATH-stub `git` wrapper that increments a counter file, delegating to the real git)
- representation pins (roast C-001): a directory-spec line (`docs/`) and a glob line (`docs/*.md`) RESOLVE (never land in `<out_unresolved>`); an unknown literal file lands unresolved; trailing-NUL/empty-record input yields no empty array elements
- `root_to_cwd_relpath`: strip case, climb case (`:(top)` spelling from sub/), identity at root
- invalid pathspec dies with usage error

Plus a red-first characterization pass on git-us before rewiring (existing `tests/unit/test_us_interactive.bats` covers much of the surface; extend where gaps exist).

## Part 2 — `hug-status-listing`: template the sl* family

### Module

New file `git-config/lib/hug-status-listing` exporting ONE function plus its private mode table:

```bash
sl_family_main <mode> <display_name> "$@"
```

The five scripts' shared skeleton moves into `sl_family_main` step-for-step, with the per-mode deltas expressed as table columns (see below) rather than left as hand-copies: pathspec split (`parse_common_flags_with_pathspecs`), `reject_action_flags "<display_name>"`, quiet rehydrate (`[[ ${HUG_QUIET:-} == T ]] && quiet=true`), `pathspec_pathspecs_into`, the own-loop (`--json` / `-c|--count` / unreachable-but-symmetric `-q` / loud `-*` rejection using `<display_name>`), `check_git_repo`, `validate_pathspecs_or_die`, the quiet-extra list_opts mutation (table column), count dispatch (`run_count_mode [--json] <count_token> ${pathspecs[@]+"--" ...}`), JSON vs listing arm (`output_json_status` / `list_files_with_status`), no-match messages, summary gate (`exec hug s` when not quiet and no pathspecs).

`show_help` resolves from the caller's script scope at call time — `-h` keeps working because each script still defines its own `show_help`.

### Mode table

| `<mode>` | list flag | count token | no-match noun | quiet extra |
|---|---|---|---|---|
| `staged` | `--staged` | `staged` | staged | (none) |
| `unstaged` | `--unstaged` | `unstaged` | unstaged | (none) |
| `untracked` | `--untracked` | `untracked` | untracked | append `--suppress-status` to list_opts when quiet |
| `ignored` | `--ignored` | `ignored` | ignored | append `--suppress-status` to list_opts when quiet |
| `conflicts` | `--conflicts` | `conflicted` | conflicted | append `--suppress-status` to list_opts when quiet |

The table is the COMPLETE behavioral contract for LIB-side per-mode variance (roast C-003/C-004): it pins today's flag-vs-noun asymmetry (`--conflicts` lists, `conflicted` counts/says) and the quiet-column suppression that slk/sli/slc implement today (`git-slk:129–132` appends `--suppress-status`; sls/slu do not — their help texts promise the status prefixes stay). The quiet-extra column is what keeps the migration honest: an implementer following only the first four columns would silently drop `hug slk -q`'s status-column suppression — pinned byte-for-byte by red-first tests BEFORE migration.

Script-local surfaces (roast C-005/C-008), pinned here so none is rediscovered or lost, but NEVER entering the lib: `_hug_category` and the whole `--search-meta` block stay in each script preamble exactly as today; slc ALONE additionally carries `_hug_keywords='["conflict","unmerged","merge","rebase"]'` and prints a `keywords = …` line from its `--search-meta` arm (verified: `grep -l _hug_keywords` matches only git-slc among the five). Unknown `<mode>` is a programming error → `error` loudly.

### Script shape after (~35 lines each)

Shebang; `_hug_category` + `--search-meta` block; CMD_BASE resolution + source loop (gains `hug-status-listing`); `set -euo pipefail`; purpose comment; its OWN `show_help` heredoc (per-command wording stays put — slu's `-q` parenthetical about status prefixes and sli's `*.log` example differ); then:

```bash
sl_family_main <mode> "hug <name>" "$@"
```

Zero behavioral change: every message byte-identical (the `-*` rejection text interpolates `<display_name>` exactly as today).

### Tests (Part 2)

- Audit existing coverage first: `tests/unit/test_status_staging.bats`, `test_status_json.bats`, `test_status_query_flags.bats`, and the conformance suite already characterize the family. Add missing pins red-first BEFORE migrating (each variant × {plain, scoped, count, json, quiet, unknown-flag exit 2}).
- Quiet-column pins (roast C-003/C-004): `hug slk -q`, `hug sli -q`, AND `hug slc -q` suppress the status column (`--suppress-status`); `hug sls -q` / `hug slu -q` PRESERVE status prefixes — byte-pinned both directions before any migration.
- Search-meta pin (roast C-005/C-008): `git slc --search-meta` prints category AND keywords lines; the other four print category only.
- Drift guard: assert each sl\* script contains `sl_family_main` and contains no own-loop marker (e.g. the `for arg in "$@"` pattern), so nobody reintroduces a hand-copy.

## Sequencing & risk

Two INDEPENDENT extractions — Part 1 (hug-pathspec/us) and Part 2 (family template) share no code paths; either can land first, as separate commits on the same branch. F-003 batching is the only output-visible delta, and it is perf-only (identical stdout/stderr/exit codes). Rollback: single revert per part.

## Non-goals

- No changes to `parse_common_flags_with_pathspecs` / hug-cli-flags internals.
- No new flags or behavior changes in any sl\* script or git-us.
- No migration of other families (w-\*, etc.) onto the template — sl\* only, per the issue.
