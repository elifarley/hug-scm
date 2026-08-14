# Help Category Metadata + Search Quality Overhaul

**Date**: 2026-05-06
**Status**: Approved (revised after /autoplan dual-voice review)
**Supersedes**: extends `2026-05-06-topic-search-design.md`
**Revision note**: Original design placed keywords on per-category TOML
manifests. Dual-voice review (Codex + Claude subagent) flagged that
category-level keywords pollute precise commands (e.g. a `save` keyword on
`parking` matches the destructive `wipdel`). Keywords are now per-command,
declared via the existing `--search-meta` protocol. See
`2026-05-06-help-category-meta-impl-autoplan-review.md` for the full review.

## Problem

Two related gaps in the current `hug help` topic search:

1. **`hug help @` and `hug help @<category>` are bare.** The catalog lists category
   names + counts only; the per-category page lists commands only. Users get no
   guidance on what a category covers, no curated keywords to search by, and the
   tip line ("Use 'hug help @<category>' to see commands in a category") under-sells
   what `@` is good for.

2. **`/keyword` and `!intent` results are noisy.** Three root causes:
   - One scorer (`partial_ratio`) for every field — too loose for short queries,
     too narrow for natural-language phrases.
   - The haystack is just `description + command name`. A user thinking
     "save my work" can't find `hug w wip` because "save" isn't in either field.
   - No score discrimination, no top-N cap, no diversification — every result
     above the threshold floods the screen.

This design fixes both, treating them as one feature: a per-category metadata
layer that doubles as the discovery surface AND the relevance signal.

## Solution Summary

| Change | Purpose |
|---|---|
| Per-category TOML manifests (`git-config/lib/python/categories/<name>.toml`) | Source of truth for each category's label, description, keywords |
| New `category_meta.py` module | Load + validate manifests; expose `CategoryMeta` dataclass |
| `help_search.py` adopts a `MatchSpec` scoring model | Per-field scorer + weight + threshold; replaces ad-hoc loops |
| `!intent` becomes a real token-aware mode | `token_set_ratio` for phrase queries; no longer an alias of `/` |
| Top-10 result cap + soft diversification | Caps noise; nudges variety across categories |
| Strict validation | Script declaring an unmanifested category fails CI and `hug help @*` at runtime |
| New `--explain` flag | Shows which field/scorer produced each hit; aids tuning |
| Updated `hug help @` listing | Adds a one-line summary column per category |
| Updated `hug help @<category>` page | Boxed header + paragraph description + keywords + command list |

## Per-Category TOML Schema

One file per category, filename = canonical category name. Categories now hold
**only `label` + `description`** — keywords moved to per-command metadata
(see "Per-Command Keywords" below).

```toml
# git-config/lib/python/categories/branching.toml
label       = "Branch operations"
description = """
Create, list, switch, and delete branches.
Branches let you work on parallel lines of development without
conflicting with shared code.
"""
```

| Field | Required | Notes |
|---|---|---|
| `label` | yes | Short title for the boxed header (e.g. `── @branching — Branch operations ──`) |
| `description` | yes | Multi-line paragraph. First sentence ≤ 70 chars is shown in `@` listing |

WHY no `keywords` here: a category-level keyword would propagate to every
command in that category — including destructive siblings. Listing `save` on
`parking` would make a `/save` query match `wipdel` (delete WIP) and `unpark`,
not just `wip`. Keywords belong on the command they describe, not on the
category bucket. See the dual-voice review in
`2026-05-06-help-category-meta-impl-autoplan-review.md` (F3).

## Per-Command Keywords

Each script's existing `--search-meta` output is extended with a `keywords`
TOML key alongside the existing `category` key:

```bash
# git-config/bin/git-w-wip
_hug_category='["working-dir", "parking"]'
_hug_keywords='["save", "shelve", "stash", "park", "wip"]'
test "${1:-}" = '--search-meta' && {
  printf 'category = %s\nkeywords = %s\n' "$_hug_category" "$_hug_keywords"
  exit 0
}
```

```bash
# git-config/bin/git-w-wipdel  (destructive — note absence of "save")
_hug_keywords='["discard-wip", "delete-park"]'
```

| Field | Required | Notes |
|---|---|---|
| `_hug_keywords` | optional | List of curated terms specific to this command. Empty/absent → no keyword-driven matches; falls back to description + category-description scoring |
| `_hug_category` | required (existing) | Unchanged from prior design |

Bootstrap target: the ~20 highest-traffic commands ship with `_hug_keywords`
in the same commit that lands the architecture (T0.5). The remaining commands
can be annotated incrementally — empty keywords gracefully degrade to
description-only scoring.

The 19 canonical categories from the prior design doc each get one file in the
bootstrap commit: `analysis`, `branching`, `committing`, `files`, `garbage`,
`head`, `history`, `merge`, `parking`, `push-pull`, `rebase`, `show`, `staging`,
`statistics`, `status`, `tags`, `utilities`, `working-dir`, `worktrees`.

## `category_meta.py` Loader Contract

```python
@dataclass(frozen=True)
class CategoryMeta:
    name: str                  # filename stem
    label: str
    description: str           # full paragraph as written
    summary: str               # first sentence, derived; ≤ 70 chars when feasible
    keywords: tuple[str, ...]

def load_categories(path: Path) -> dict[str, CategoryMeta]: ...

def validate_against_scripts(
    categories: dict[str, CategoryMeta],
    used_categories: set[str],
) -> list[str]:  # returns list of error strings; empty == OK
```

WHY a dedicated module: keeps loader/validator/IO out of `help_search.py`,
which stays focused on search. Easier to test in isolation; clear boundary
when other tooling (e.g. a future `hug help-meta lint` command) wants to
reuse the loader.

## Validation Policy (Strict)

| Failure mode | Severity | Surfaced where |
|---|---|---|
| Script declares category with no `.toml` manifest | **Error** | `pytest test_category_meta.py` (blocks CI) and `hug help @*` (exits 1 with stderr message) |
| Manifest exists but no script uses it | Warning | Same call paths, but warning only — placeholder manifests are allowed |
| Manifest missing required field | **Error** | Loader raises during parse |
| Manifest keyword count < 3 | **Error** | Loader raises during parse |

Both call paths share one validator — no test/runtime drift.

## Display Layouts

### `hug help @` (no query)

```
Available categories:

  @branching     (9)  — Create, list, switch, and delete branches
  @committing    (7)  — Create, modify, and rewrite commits
  @files         (6)  — Inspect and diff specific files
  @head          (7)  — Move HEAD around safely
  ...

Use `hug help @<category>` to learn about a category and list its commands.
Use `hug help /<keyword>` for keyword search, or `hug help !<intent>` for
natural-language search.
```

- Padding: `@<name>` column to longest name; count column to longest count.
- Summary = first sentence of `description`, truncated to ≤ 70 chars on a word
  boundary if longer.
- Trailing tip lines → **stderr** (per stdout/stderr discipline; the data is
  the catalog itself).

### `hug help @<category>`

```
── @branching — Branch operations ──────────────────────

Create, list, switch, and delete branches.
Branches let you work on parallel lines of development without
conflicting with shared code.

── Keywords ────────────────────────────────────────────

branch, switch, checkout, tracking, upstream, head, ref, rename

── Commands (9) ────────────────────────────────────────

  hug b           - Switch to a branch, with interactive menu
  hug bc          - Create a new branch and switch to it
  ...

Tip: `hug help <command>` for full help on any command.
```

- Box rule width = `min(terminal_width, 72)`; trailing rule fills with `─`.
- Description and keywords word-wrapped to the same width.
- Decorative chatter (rules, headings, tips) → **stderr**; command list → **stdout**
  so `hug help @branching | grep bpush` still works.

### `hug help /<keyword>` and `hug help !<intent>`

Format unchanged structurally. New: top-10 cap with overflow note, plus
optional `--explain` flag for a third "match source" column.

```
Keyword search for 'branch':

  hug bc          - Create a new branch and switch to it
  hug b           - Switch to a branch, with interactive menu
  ...

  Showing top 8 of 12. Pass --all to see all matches.
```

### Updated tip line in `git-hughelp` (no args)

Replace the single line:

```
  hug help @category  - Browse commands by category
```

with:

```
  hug help @           - List all categories
  hug help @<category> - Learn about a category and list its commands
```

## Search Engine: the `MatchSpec` Model

```python
@dataclass(frozen=True)
class MatchSpec:
    field: str          # which attribute to read from CommandInfo / CategoryMeta
    scorer: Callable[[str, str], int]
    weight: float       # 0..1, multiplies the raw score
    min_threshold: int  # 0..100; result discarded if scaled score < this
    label: str          # short tag for --explain output
```

`run_search(query, commands, specs)` walks every command × every spec, computes
`weight * scorer(query, field_value)`, keeps the best spec per command, and
returns a sorted list with each result's winning spec attached.

### Spec lists per mode

**`/keyword` (precision):**

| field | scorer | weight | min |
|---|---|---|---|
| `name_exact` | `ratio` | 1.00 | 90 |
| `name_partial` | `partial_ratio` | 0.85 | 80 |
| `description` | `WRatio` | 0.90 | 80 |
| `category_desc` | `WRatio` | 0.80 | 80 |
| `keywords` | `ratio` | 0.95 | 88 |

**`!intent` (phrase):**

| field | scorer | weight | min |
|---|---|---|---|
| `description` | `token_set_ratio` | 0.95 | 75 |
| `category_desc` | `token_set_ratio` | 0.90 | 75 |
| `keywords` | `token_set_ratio` | 0.80 | 75 |

`keywords` is the per-command list parsed from `_hug_keywords`. Each keyword
is a separate string read by `_read_field`, so `_ratio(query, "branch")` fires
when the query equals one keyword exactly — no joined-string blunting.

**`@category`:** unchanged scorer (`ratio` against category name, `MIN_CATEGORY_SCORE=60`),
but output now hydrates label / description / keywords from `CategoryMeta`.

WHY per-field thresholds: `partial_ratio>=70` on a description is a noisier
signal than `ratio>=88` on a curated keyword. Letting each scorer carry its
own floor lets us tighten precision on noisy fields without losing recall on
curated ones.

WHY `WRatio` for descriptions: it's a hybrid scorer that internally combines
`partial_ratio`, `token_sort_ratio`, and length normalization. Empirically far
better than `partial_ratio` for free-text matching, with no manual tuning.

WHY `token_set_ratio` for `!intent`: phrase queries like
`!save my work in progress` should ignore word order and stopwords. Token-set
matching handles this without us building a stopword list.

### Result cap + soft diversification

```python
def diversify(scored, cap=10, soft_cap_per_category=3, penalty=5):
    seen: dict[str, int] = {}
    out = []
    for score, cmd, spec in scored:
        cat = cmd.categories[0] if cmd.categories else ""
        n = seen.get(cat, 0)
        if n >= soft_cap_per_category:
            score = max(0, score - penalty * (n - soft_cap_per_category + 1))
        out.append((score, cmd, spec))
        seen[cat] = n + 1
    out.sort(key=lambda x: x[0], reverse=True)
    return out[:cap]
```

After 3 results from the same category, a small per-extra penalty nudges
later same-category hits down so other categories surface. Strong direct
matches still beat weak cross-category matches; the penalty is gentle.

`--all` flag bypasses both `cap` and `soft_cap_per_category`.

### `--explain` flag

When set (or `HUG_HELP_EXPLAIN=1`), each result gets a trailing column
showing the winning spec's label and final score:

```
  hug bc       - Create a new branch and switch to it       [desc, 95]
  hug brestore - Restore a branch from a backup             [@cat-kw, 88]
```

Off by default. Invaluable when tuning weights/thresholds — you can see exactly
which field caused a result to surface.

## Cache Invalidation

The existing `/tmp/cache/hug/search-meta.cache` is extended with one new field:

```json
{
  "<script-name>": { ... existing ... },
  "_meta": { "categories_mtime_max": 1730000000.0 }
}
```

If any `categories/*.toml` is newer than `categories_mtime_max`, the cache is
treated as cold and the search re-collects. Bash CLI sees no behavior change.

## File Layout

```
git-config/lib/python/
├── help_search.py            # Modified — MatchSpec, consumes category_meta
├── category_meta.py          # NEW — loader + validator + dataclass
├── categories/               # NEW — 19 manifests
│   ├── analysis.toml
│   ├── branching.toml
│   ├── committing.toml
│   ├── files.toml
│   ├── garbage.toml
│   ├── head.toml
│   ├── history.toml
│   ├── merge.toml
│   ├── parking.toml
│   ├── push-pull.toml
│   ├── rebase.toml
│   ├── show.toml
│   ├── staging.toml
│   ├── statistics.toml
│   ├── status.toml
│   ├── tags.toml
│   ├── utilities.toml
│   ├── working-dir.toml
│   └── worktrees.toml
└── tests/
    ├── test_help_search.py   # Extended
    └── test_category_meta.py # NEW
```

`git-config/bin/git-hughelp` stays thin: only the no-arg tip lines change.
All formatting stays in Python (per `git-config/bin/CLAUDE.md`: scripts are a
thin layer; library does the work).

## Test Plan

| File | Coverage |
|---|---|
| `tests/test_category_meta.py` (new) | Loader parses TOML; missing required field → error; bad keyword count → error; summary truncation correctness; filename ≠ name detected; `validate_against_scripts` flags missing manifests as errors and orphans as warnings |
| `tests/test_help_search.py` (extended) | `MatchSpec.run` applies weight + threshold; per-mode spec lists wire correctly; `!intent` is token-aware (e.g. `"save my work"` finds `wip` via category keyword); diversification penalty triggers after 3 same-category; cap respected; `--all` bypasses cap; `--explain` annotation matches winning spec |
| `tests/integration/test_help_topic_search.bats` (extended) | `hug help @` shows summary column; `hug help @branching` shows boxed header + keywords + commands; missing manifest causes `hug help @` exit 1 with stderr; `hug help /branch --explain` shows match-source column; `hug help !save my work` finds `wip`-class command; `--all` flag works |

## What's NOT Changing

- Existing `--search-meta` per-script protocol (still emits `category = [...]`).
- `hug help <prefix>` listing for non-`@/!/?` queries.
- Cache file location (`/tmp/cache/hug/search-meta.cache`).
- Bash CLI surface area: only the no-arg tip lines change in `git-hughelp`.
- Existing `MIN_KEYWORD_SCORE` / `MIN_CATEGORY_SCORE` constants stay as
  module-level documented defaults; new per-spec thresholds override per field.

## Migration Path

Single bootstrap commit creates all 19 manifests at once → strict validation
enabled in the same commit → no transitional period during which manifests
might be missing. Future categories require their `.toml` in the same PR.

## Open Tuning Knobs

These are configurable via module constants — not user-facing — but should be
tuned during implementation against the existing 100-script corpus:

- `KEYWORD_SPECS` / `INTENT_SPECS` thresholds
- `diversify(cap=10, soft_cap_per_category=3, penalty=5)`
- Summary truncation length (default 70 chars)

A pytest test (`test_quality_corpus.py`) holds a small set of golden queries
+ expected top-3 results, so threshold tuning has a regression net.
