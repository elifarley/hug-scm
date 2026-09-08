# Design: Fetch-discovery registry for the hug help system

- **Date:** 2026-09-08
- **Branch:** `fetch-discovery-registry-for-help-search`
- **Status:** Approved (brainstorming session, Approach A); roast round 1
  applied (C-001..C-006 chain redesign + de-exec, F-001..F-007; all findings
  verified against live code before adoption)

## Problem

Agents (and humans) search hug's help system for `fetch` and find nothing — yet
`hug fetch` works. Every discovery path dead-ends:

| Path | Today |
|---|---|
| `hug fetch origin --tags` | ✅ Works — `bin/hug:221` passes unknown commands to `git` |
| `hug help /fetch` | ❌ `(none)` |
| `hug help /pull` | ❌ `(none)` |
| `hug help /bs` | ❌ `(none)` — same defect, non-sync member (README-documented command) |
| `hug help '@push-pull'` | ⚠️ Description promises "fetch updates, pull and rebase"; lists only 4 push/outgoing commands |
| `hug help bpullr` | ⚠️ Alias-expands to raw `git pull` usage, then "(none)" |
| `hug help fetch` | ⚠️ `command -v git-fetch` resolves git's exec-path builtin (`/usr/lib/git-core/git-fetch`, git 2.34.1 here) → prints the full GIT-FETCH(1) man page (36 KB of generic git prose, zero hug context) |
| `hug help :agents` translation table | ❌ Has `push → bpush`; no fetch row at all |

**Root cause:** the help index is built exclusively from the 107 `git-config/bin/`
scripts via their `--search-meta` protocol (`help_search.collect_metadata`). Commands
that are not scripts are invisible to all four discovery sigils (`/keyword`,
`'!intent'`, `@category`, and exact-name help):

- `fetch` — pure dispatcher passthrough
- `bpull` = `pull --ff-only` (`.gitconfig:514`)
- `bpullr` = `pull --rebase` (`.gitconfig:518`)
- `pullall` = `pull --all` (`.gitconfig:522`)
- `tpull` = `fetch --tags` (`.gitconfig:306`) — fetch semantics, "pull" name
- `tpullf` = `fetch --tags --prune --prune-tags --force` (`.gitconfig:310`)
- `bs` = `switch -` (`.gitconfig:368`) — switch back to the previous branch;
  documented in README (incl. a wip/pause/resume workflow) yet `/bs` → `(none)`

The most common sync primitive an agent needs (`fetch` before
`hug wtc --base origin/main`, per the `:worktree` article's "base off an UP-TO-DATE
integration branch") is precisely the one the help system cannot surface.

## Goals

1. All four discovery sigils answer "fetch" (and "pull", "tags fetch", …).
2. `hug help <name>` renders a hug-flavored card for registry entries instead of
   falling through to raw git alias expansion.
3. `@push-pull` lists the existing sync surface so the category's promise matches
   its contents.
4. `:agents` article teaches `git fetch → hug fetch`.
5. Regression-pin the whole behavior in the help-search quality corpus.

## Non-goals

- **No first-class `git-fetch` script.** `hug fetch` stays a passthrough.
- **No shell-completion changes.** A third consumer can ride the same registry later.
- **No Mercurial-mode help changes.** The registry lives in `git-config/`; hg help
  remains the dispatcher's static text.
- **No behavior change to any existing command** — this is metadata + help display only.
- Not indexed: `push` (the right answer is `bpush`, already searchable — indexing raw
  push would be a footgun); `brr` (branch helper `b -R`, `.gitconfig:364`, not a sync
  primitive — may appear in a Related block); naked `pull` (can merge unexpectedly;
  the `bpull*` cards teach the safe forms).

## Architecture (Approach A: static registry + loader)

Two new pieces, three thin integration points.

### New: `git-config/lib/python/commands.toml`

One table per non-script command. Schema:

```toml
[fetch]
kind = "passthrough"          # "alias" | "passthrough"
description = """
Download new commits and refs from remotes without merging.
Multi-line prose used by /keyword + !intent search and the help card.
Speaks the user's vocabulary (download, sync, update, remote).
"""
keywords = ["fetch", "download", "sync", "update", "remote"]
categories = ["push-pull"]     # every value must exist in categories/
git_equivalent = "git fetch"
usage = "hug fetch [--tags] [--prune] [<remote> [<refspec>...]]"
related = ["bpull", "bpullr", "tpull", "llu"]
```

Field rules:
- **No `summary` field.** The listing/search one-liner is DERIVED from
  `description`'s first sentence via `category_meta.derive_summary`
  (same `SUMMARY_MAX = 70` budget) — the exact pattern `categories/*.toml`
  already uses. One prose source, one derivation, no second summary format to
  keep in sync and no length rule left unenforced. Write descriptions so the
  first sentence stands alone as the listing line.
- `description` feeds fuzzy scoring (WRatio/token-set) and the card body.
- `keywords` is the registry analog of the per-script `_hug_keywords` protocol
  (see `git-config/bin/CLAUDE.md`); each keyword is an independent match unit.
- `categories` values are validated against `categories/*.toml` at load.
- Table names (the command names) are validated against hug's command grammar:
  `^[a-z][a-z0-9]*(-[a-z0-9]+)*$` — a name with spaces, capitals, or a
  gateway-style form like `h fetch` fails at load instead of flowing unchecked
  into card headers, drift tests, and command strings.
- `related` entries are validated at load: each must resolve to a registry
  sibling, a `git-config/bin/git-*` script, or a `.gitconfig` alias (one
  `git config --file … --get-regexp '^alias\.'` call per load, not per name).
  A dead `hug <name>` hint on a card is the same discovery dead-end this
  feature fixes.

### New: `git-config/lib/python/command_meta.py`

Loader mirroring `category_meta.py`: frozen dataclass, schema validation
(table-name grammar, required fields, `kind` enum, unknown-category rejection,
`related` resolvability), derives the listing summary from `description` via
`category_meta.derive_summary`, and raises loudly on a missing or corrupt
`commands.toml` (same failure posture as `categories/` — the file ships with the
repo; silent-empty would silently break the corpus).

### Integration 1 — `help_search.py` index merge

`collect_metadata()` merges registry entries as `CommandInfo` rows after the
script-cache load and **before** the `sorted(...)` that closes the function
(help_search.py:418) — so the returned list is one uniformly sorted index.
Appending after the sort would leave script rows sorted and registry rows
appended; `@push-pull`'s page renders in input order, so it would list four
push scripts, then the six sync entries, instead of one alphabetical list.
Registry rows never enter `search-meta.cache` — the cache is keyed by script
filename and written only inside the script loop, so no invalidation logic is
needed.

`CommandInfo` gains one optional field: `kind: str | None = None`
(`None` = script; fully backward-compatible with all existing constructions).

Because the merge happens upstream of `search_keyword`, `search_intent`,
`search_category`, and `list_categories`, **all four sigils surface registry
entries with zero search-engine changes**.

### Integration 2 — `git-hughelp` exact-help precedence

Current resolution (lines 46–53): script `--help`, else raw alias expansion.
New strict chain:

1. **Hug's own script exists** → run `git-$prefix --help`.
   The existence test MUST be `[[ -x "$dir/git-$prefix" ]]` (the directory
   git-hughelp itself lives in) — **not** the current `command -v "git-$prefix"`.
   WHY: when git dispatches an external subcommand it prepends its exec-path to
   PATH, and Debian/Ubuntu-family git ships dashed builtins there
   (`/usr/lib/git-core/git-fetch` on git 2.34.1 — verified live: `hug help fetch`
   prints the GIT-FETCH(1) man page today). A PATH lookup makes branch ① win for
   `fetch` and the card unreachable — the exact regression this design exists to
   prevent. Behavior change vs today, accepted: for git-core-named names, the
   hug card + "Full flags: git help fetch" line replaces git's man page dump.
2. **Registry has `$prefix`** → `uv run --directory "$dir/../lib/python"
   --extra search help_search.py card "$prefix"` — **no `exec`** (an `exec`
   replaces the shell, making the exit-1 fall-through below impossible and
   killing every non-registry alias's help, e.g. `hug help bs` which today
   prints alias help + listing, exit 0). Exit-code contract:
   - `0` → card printed; exit 0 (the card's Related block replaces the
     prefix listing).
   - `1` → name not owned by the registry; fall through to ③/④.
   - `≥2` → environment failure (uv missing, venv broken): print a loud error
     and exit with that code — never silently degrade to legacy behavior.
3. Alias exists → `git $prefix -h` (unchanged fallback).
4. Prefix listing (unchanged).

Property: registry names are never executable scripts anywhere branch ① or git's
exec-path can see (enforced by drift test 2), so branch ② only ever claims names
that no `git-*` executable owns. If hug ever ships a real `git-fetch` script, it
lands in branch ①'s bin dir and the card is shadowed automatically — the desired
direction (scripts beat cards). Bash stays a thin dispatcher (per
`git-config/bin/CLAUDE.md`).

Accepted cost: every non-script exact-help lookup (registry miss → ③) now pays
one `uv run` venv resolution before falling through — pure bash today. The sigil
modes already require `uv run`, so this adds no new dependency, only latency on
a human-interactive path.

### Integration 3 — card mode in `help_search.py`

`help_search.py card <name>`: renders and exits 0 when the registry owns the name;
exits 1 otherwise (bash falls through to ③/④); exits ≥2 with a loud message on
environment failure. The card is a **pure function over the loaded registry
dict** — it must NOT run `collect_metadata()`. Related lines resolve their
one-line summaries from (in order): the registry itself, a **read-only** peek at
`search-meta.cache`; if neither has the name, render the bare `hug <name>` hint.
Rationale: `collect_metadata` scans/execs every script on a cold cache, so an
exact-name card would pay a 107-script sweep per call — a discovery win with a
performance footgun.

Card layout:

```
hug fetch — (git passthrough)
Download new commits and refs from remotes without merging

<description body>

Usage: hug fetch [--tags] [--prune] [<remote> [<refspec>...]]
Git equivalent: git fetch
Full flags: git help fetch

Related:
  hug bpull    — fast-forward-only pull (safe default)
  hug bpullr   — pull with rebase (linear history)
  hug tpull    — fetch tags
  hug llu      — verify what came in (behind count)
```

Related lines pull each entry's/script's one-line summary where available; kind
shown as `(git alias)` or `(git passthrough)`.

### Display markers

In `@category` pages and `/keyword` / `!intent` results, registry rows render a
trailing marker derived from `kind`: `hug bpullr — Pull with rebase (git alias)`.
Summaries in the TOML stay pure prose; the marker is added by the format layer
(`format_results`, `format_category_page`) when `cmd.kind` is set — so a reader
sees immediately why `hug bpullr -h` isn't hug-flavored.

## Registry contents (initial)

Seven entries: six sync commands in `@push-pull` (`tpull`/`tpullf` additionally
in `@tags`) plus `bs` in `@branching` — the first non-sync member, included
deliberately (user-directed 2026-09-08): it is documented in README, used in a
README workflow, and equally invisible to search. It also proves the registry
generalizes beyond one category. Systematic coverage of the remaining non-script
commands (index or consciously exclude, per command) is tracked in
[elifarley/hug-scm#338](https://github.com/elifarley/hug-scm/issues/338).

| name | kind | description's first sentence (= derived listing summary) | extra keywords | related |
|---|---|---|---|---|
| `fetch` | passthrough | download commits/refs from remotes, no merge | download, sync, update, remote, refs | bpull, bpullr, tpull, llu |
| `bpull` | alias | fast-forward-only pull; fails if merge/rebase needed | update, integrate | fetch, bpullr, mff |
| `bpullr` | alias | pull with rebase (linear history) | rebase, update, integrate | fetch, bpull, rb |
| `pullall` | alias | fetch from all remotes, then update the current branch's upstream | all, every, remote | fetch, bpull |
| `tpull` | alias | fetch tags from the remote | tag, download | fetch, tpullf, t |
| `tpullf` | alias | force fetch + prune stale tags | tag, prune, force | tpull, fetch |
| `bs` | alias | switch back to the previous branch | previous, back, toggle, last | b, bc |

Note on `pullall`: `git pull --all` fetches all remotes but integrates only the
current branch's upstream (per `git help pull`) — the description must not teach
"pulls every branch", which the `.gitconfig` comment's own phrasing invites.

## Testing

### Quality corpus (the regression net for the reported complaint)

`git-config/lib/python/tests/test_quality_corpus.py` gains rows in the existing
top-N-membership style:

- `/fetch` top-5 ⊇ {fetch, tpull, tpullf}
- `/pull` top-5 ⊇ {bpull, bpullr, pullall}
- `/bs` top-5 ⊇ {bs}
- intent `update my repo from the remote` top-5 ⊇ {fetch, bpull, bpullr}
- intent `go back to the previous branch` top-5 ⊇ {bs}
- Destructive-sibling guard style: `/fetch` must NOT surface `h-rewind`/
  `w-zap`-class commands (inherits the corpus's F3 guarantee pattern).

### pytest unit tests (`git-config/lib/python/tests/`)

- Loader: valid file → entries; missing required field → error; bad `kind` → error;
  unknown category → error; table name failing the command grammar → error;
  `related` entry resolving to nothing → error; missing file → error.
- Derived summary: first sentence of `description` becomes the summary; a
  description whose first sentence exceeds 70 chars is truncated by the same
  rule as `category_meta.derive_summary` (one pinned test, not a silent guess).
- Merge: `collect_metadata` output contains registry rows with correct `kind`;
  script rows keep `kind=None`; the merged list is fully sorted (registry names
  interleaved alphabetically, not appended); cache still bypasses registry
  (second call with warm cache still includes registry rows).
- Card: found name → card text contains kind, git-equivalent, related, usage;
  unknown name → exit 1, no partial card; related summary resolution order
  (registry → read-only cache → bare hint).

### Drift tests (the two consistency guarantees)

1. **Alias resolution:** every `kind = "alias"` entry resolves via
   `git config --file git-config/.gitconfig --get alias.<name>` (non-empty).
2. **No shadowing (full scope):** for each registry name N, assert N matches
   NEITHER a hug bin script (`git-config/bin/git-N`) NOR any dashed executable
   git dispatch could put on branch ①'s lookup path — check
   `$(git --exec-path)/git-N` and `command -v git-N` in the test environment.
   Scope note: checking only hug's bin dir would pass `fetch` today while
   `/usr/lib/git-core/git-fetch` exists — the exact shadowing this test exists
   to catch. This keeps the chain's "scripts beat cards" property honest.

### BATS integration (`tests/integration/test_help_articles.bats` + additions)

- `hug help /fetch` → output contains `hug fetch` and `hug tpull`.
- `hug help fetch` → card (contains "git passthrough"); does NOT contain
  "Commands starting with"; does NOT contain the GIT-FETCH man-page banner.
- `hug help bpullr` → card; does NOT contain git's raw `usage: git pull` banner.
- `hug help bs` (non-registry alias) → alias help + prefix listing still work,
  exit 0 (regression pin for the no-`exec` fall-through contract).
- `hug help zzz` (unknown name) → prefix listing "(none)", exit 0.
- `hug help s` → unchanged script help (precedence regression: branch ① wins).
- `hug help '@push-pull'` → lists `bpull`, `bpullr`, `fetch` with kind markers,
  in one alphabetical run (no script-block-then-registry-block split).
- `hug help bpush` (a script name, unaffected by registry) → unchanged.

## Error handling

- **One contract: registry failure is loud everywhere.** A bad or missing
  `commands.toml` exits 1 with a clear message in EVERY mode — `/keyword`,
  `!intent`, `@category`, and card alike — mirroring how `help_search.main()`
  hard-fails on `categories/` errors. No catch-and-continue: silent degradation
  would quietly shrink the index and the corpus, the exact outcome the loader
  exists to prevent.
- Cache integrity (the narrow sense of "script search survives"): registry rows
  never enter `search-meta.cache` and are merged only after the cache is read,
  so a corrupt registry cannot alter or invalidate cached script metadata — but
  the process still exits 1 before printing anything.
- Card mode for a name owned by BOTH registry and an executable script cannot
  happen (drift test 2's full PATH ∪ exec-path scope); if it somehow does, bash
  branch ① still wins — scripts beat cards.

## Docs change-set (per DOCS_ORGANIZATION.md)

1. `git-config/lib/python/articles/agents.md`:
   - Translation table gains: `git fetch` → `hug fetch` (passthrough note).
   - New short "Fetching & pulling" block beside Pushing: `hug fetch` (safe, no
     merge), `hug bpull` (safe default), `hug bpullr` (linear history), `tpull`
     for tags; reminder to fetch before `hug wtc --base origin/main`.
2. `docs/git-to-hug.md` — the PUBLIC translation guide: add `git fetch → hug
   fetch` rows to both the quick table and the detailed section (it already
   documents `git pull → hug bpull` / `--rebase → hug bpullr` with no fetch
   row — the same dead-end this feature fixes, in the artifact agents
   actually read).
3. `docs/command-map.md`: add `fetch` to the push/pull tree beside
   `bpull`/`bpullr` (passthrough note).
4. `README.md` command reference: add `hug fetch` row beside the existing
   `bpull`/`bpullr` rows.
5. Authoring homes for the registry (so the second contributor knows where
   metadata lives):
   - `git-config/bin/CLAUDE.md`: extend the `_hug_keywords` note — bin scripts
     declare keywords in `_hug_keywords`; non-script commands declare them in
     `commands.toml`.
   - `git-config/lib/python/README.md` (Module Organization): add
     `command_meta.py` / `commands.toml`.

No new docs pages; no VitePress sidebar changes.

## Success criteria

- `hug help /fetch`, `hug help /pull` return the family (no more `(none)`).
- `hug help bpullr` renders the card; raw `git pull` usage no longer appears.
- `hug help '@push-pull'` lists the six sync entries (bs renders under
  `@branching`); category promise matches contents.
- `:agents` article shows the fetch translation.
- Corpus rows + drift tests + BATS cases green; full `make test` green.

## References

- `bin/hug:217-221` — git-repo dispatch (`exec git "$@"` passthrough)
- `git-config/bin/git-hughelp:38-53` — sigil dispatch + exact-help resolution
- `git-config/lib/python/help_search.py` — `CommandInfo`, `collect_metadata`,
  `search_*`, `format_*`, cache
- `git-config/lib/python/category_meta.py` — loader pattern to mirror
- `git-config/.gitconfig:306,310,368,514,518,522` — the seven aliases
- Shadowing receipt: `/usr/lib/git-core/git-fetch -> git` (git 2.34.1,
  exec-path `/usr/lib/git-core` first on PATH inside git-dispatched scripts;
  live: `hug help fetch` prints the GIT-FETCH(1) man page today)
- Prior art: `categories/*.toml` + `category_meta.py` (chosen over category-level
  keyword pollution — see `category_meta.py` docstring, /autoplan F3)
