# Design: Fetch-discovery registry for the hug help system

- **Date:** 2026-09-08
- **Branch:** `fetch-discovery-registry-for-help-search`
- **Status:** Approved (brainstorming session, Approach A)

## Problem

Agents (and humans) search hug's help system for `fetch` and find nothing — yet
`hug fetch` works. Every discovery path dead-ends:

| Path | Today |
|---|---|
| `hug fetch origin --tags` | ✅ Works — `bin/hug:221` passes unknown commands to `git` |
| `hug help /fetch` | ❌ `(none)` |
| `hug help /pull` | ❌ `(none)` |
| `hug help '@push-pull'` | ⚠️ Description promises "fetch updates, pull and rebase"; lists only 4 push/outgoing commands |
| `hug help bpullr` | ⚠️ Alias-expands to raw `git pull` usage, then "(none)" |
| `hug help :agents` translation table | ❌ Has `push → bpush`; no fetch row at all |

**Root cause:** the help index is built exclusively from the 109 `git-config/bin/`
scripts via their `--search-meta` protocol (`help_search.collect_metadata`). Commands
that are not scripts are invisible to all four discovery sigils (`/keyword`,
`'!intent'`, `@category`, and exact-name help):

- `fetch` — pure dispatcher passthrough
- `bpull` = `pull --ff-only` (`.gitconfig:513`)
- `bpullr` = `pull --rebase` (`.gitconfig:518`)
- `pullall` = `pull --all` (`.gitconfig:522`)
- `tpull` = `fetch --tags` (`.gitconfig:306`) — fetch semantics, "pull" name
- `tpullf` = `fetch --tags --prune --prune-tags --force` (`.gitconfig:310`)

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
summary = "Download new commits and refs from remotes without merging"  # ≤70 chars
description = """
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
- `summary` follows the existing `SUMMARY_MAX = 70` column budget
  (`category_meta.py`); it feeds listing columns and search scoring.
- `description` feeds fuzzy scoring (WRatio/token-set) and the card body.
- `keywords` is the registry analog of the per-script `_hug_keywords` protocol
  (see `git-config/bin/CLAUDE.md`); each keyword is an independent match unit.
- `categories` values are validated against `categories/*.toml` at load.
- `related` entries may be any hug command (bin script or registry name);
  rendered as `hug <name>` hints, not validated at load (the Drift tests cover
  the two guarantees that ARE validated: alias resolution and no-shadowing).

### New: `git-config/lib/python/command_meta.py`

Loader mirroring `category_meta.py`: frozen dataclass, schema validation
(required fields, `kind` enum, unknown-category rejection), loud error on missing
or corrupt `commands.toml` (same failure posture as `categories/` — the file ships
with the repo; silent-empty would silently break the corpus).

### Integration 1 — `help_search.py` index merge

`collect_metadata()` appends registry entries as `CommandInfo` rows **after** the
script-cache load. Registry rows never enter `search-meta.cache` — the cache stays
mtime-keyed over scripts only, so no invalidation logic is needed.

`CommandInfo` gains one optional field: `kind: str | None = None`
(`None` = script; fully backward-compatible with all existing constructions).

Because the merge happens upstream of `search_keyword`, `search_intent`,
`search_category`, and `list_categories`, **all four sigils surface registry
entries with zero search-engine changes**.

### Integration 2 — `git-hughelp` exact-help precedence

Current resolution (lines 45–53): script `--help`, else raw alias expansion.
New strict chain:

1. `git-$prefix` script exists → run `git-$prefix --help` (unchanged).
2. Registry has `$prefix` → `exec uv run … help_search.py card "$prefix"` and stop
   (exit 0 ends help; the card's Related block replaces the prefix listing).
3. Alias exists → `git $prefix -h` (unchanged fallback).
4. Prefix listing (unchanged).

Property: registry names are never scripts (enforced by test), so this is purely
additive — and if a real `git-fetch` script ever lands, branch ① shadows the card
automatically. Bash stays a thin dispatcher (per `git-config/bin/CLAUDE.md`).

### Integration 3 — card mode in `help_search.py`

`help_search.py card <name>`: renders and exits 0 when the registry owns the name;
exits 1 otherwise (bash falls through to ③). Card layout:

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

All six in `@push-pull`; `tpull`/`tpullf` additionally in `@tags`.

| name | kind | summary (gist) | extra keywords | related |
|---|---|---|---|---|
| `fetch` | passthrough | download commits/refs from remotes, no merge | download, sync, update, remote, refs | bpull, bpullr, tpull, llu |
| `bpull` | alias | fast-forward-only pull; fails if merge/rebase needed | update, integrate | fetch, bpullr, mff |
| `bpullr` | alias | pull with rebase (linear history) | rebase, update, integrate | fetch, bpull, rb |
| `pullall` | alias | pull across all remotes / update all tracking refs | all, every | fetch, bpull |
| `tpull` | alias | fetch tags from the remote | tag, download | fetch, tpullf, t |
| `tpullf` | alias | force fetch + prune stale tags | tag, prune, force | tpull, fetch |

## Testing

### Quality corpus (the regression net for the reported complaint)

`git-config/lib/python/tests/test_quality_corpus.py` gains rows in the existing
top-N-membership style:

- `/fetch` top-5 ⊇ {fetch, tpull, tpullf}
- `/pull` top-5 ⊇ {bpull, bpullr, pullall}
- intent `update my repo from the remote` top-5 ⊇ {fetch, bpull, bpullr}
- Destructive-sibling guard style: `/fetch` must NOT surface `h-rewind`/
  `w-zap`-class commands (inherits the corpus's F3 guarantee pattern).

### pytest unit tests (`git-config/lib/python/tests/`)

- Loader: valid file → entries; missing required field → error; bad `kind` → error;
  unknown category → error; missing file → error.
- Merge: `collect_metadata` output contains registry rows with correct `kind`;
  script rows keep `kind=None`; cache still bypasses registry (second call with
  warm cache still includes registry rows).
- Card: found name → card text contains kind, git-equivalent, related, usage;
  unknown name → exit 1, no partial card.

### Drift tests (the two consistency guarantees)

1. **Alias resolution:** every `kind = "alias"` entry resolves via
   `git config --file git-config/.gitconfig --get alias.<name>` (non-empty).
2. **No shadowing:** no registry name matches an existing
   `git-config/bin/git-*` script (keeps branch ① authoritative forever).

### BATS integration (`tests/integration/test_help_articles.bats` + additions)

- `hug help /fetch` → output contains `hug fetch` and `hug tpull`.
- `hug help fetch` → card (contains "git passthrough"); does NOT contain
  "Commands starting with".
- `hug help bpullr` → card; does NOT contain git's raw `usage: git pull` banner.
- `hug help s` → unchanged script help (precedence regression).
- `hug help '@push-pull'` → lists `bpull`, `bpullr`, `fetch` with kind markers.
- `hug help bpush` (a name in neither script-branch conflict nor registry) → unchanged.

## Error handling

- Bad/missing `commands.toml` → loader raises loudly with the offending key/file
  (same posture as `categories/` loaders). No silent-empty degradation.
- Loader failure never corrupts script-only search: merge is append-only, after
  cache load; a corrupt registry surfaces as an error, not as vanished scripts.
- Card mode for a name owned by BOTH registry and a script cannot happen (drift
  test 2); if it somehow does, bash branch ① still wins — scripts beat cards.

## Docs change-set (minimal, per DOCS_ORGANIZATION.md)

1. `git-config/lib/python/articles/agents.md`:
   - Translation table gains: `git fetch` → `hug fetch` (passthrough note).
   - New short "Fetching & pulling" block beside Pushing: `hug fetch` (safe, no
     merge), `hug bpull` (safe default), `hug bpullr` (linear history), `tpull`
     for tags; reminder to fetch before `hug wtc --base origin/main`.
2. `README.md` command reference: add `hug fetch` row beside the existing
   `bpull`/`bpullr` rows.

No new docs pages; no VitePress sidebar changes.

## Success criteria

- `hug help /fetch`, `hug help /pull` return the family (no more `(none)`).
- `hug help bpullr` renders the card; raw `git pull` usage no longer appears.
- `hug help '@push-pull'` lists the six entries; category promise matches contents.
- `:agents` article shows the fetch translation.
- Corpus rows + drift tests + BATS cases green; full `make test` green.

## References

- `bin/hug:217-221` — git-repo dispatch (`exec git "$@"` passthrough)
- `git-config/bin/git-hughelp:38-53` — sigil dispatch + exact-help resolution
- `git-config/lib/python/help_search.py` — `CommandInfo`, `collect_metadata`,
  `search_*`, `format_*`, cache
- `git-config/lib/python/category_meta.py` — loader pattern to mirror
- `git-config/.gitconfig:306,310,513,518,522` — the six aliases
- Prior art: `categories/*.toml` + `category_meta.py` (chosen over category-level
  keyword pollution — see `category_meta.py` docstring, /autoplan F3)
