# Design: `hug help :<article>` — mini-guides & cookbooks

**Date:** 2026-05-06
**Status:** Approved
**Author:** brainstorming session

## Context

`hug help` already exposes four discovery sigils:

- `hug help` — category prefix overview
- `hug help <prefix>` — list commands with that prefix
- `hug help <command>` — full help for a command
- `hug help @[query]` — categories listing or one-category boxed page
- `hug help /<keyword>` — fuzzy keyword search across descriptions/names
- `hug help '!<intent>'` — token-aware natural-language search

What's missing: long-form prose. There's no way to surface a beginner's
quickstart, a workflow recipe, or a concept primer from inside the CLI.
The repository already ships such content (`docs/hug-for-beginners.md`,
`docs/cookbook.md`) but it lives in VitePress and is invisible to a user
sitting at a terminal.

This design introduces a fifth sigil — `:` — for **articles** (mini-guides /
cookbook-style content authored specifically for terminal consumption,
separate from the VitePress docs).

## Goals

1. `hug help :` lists available articles (titles + summaries).
2. `hug help :<title>` renders an article in the terminal.
3. Authoring stays as low-friction as writing a markdown file.
4. The implementation mirrors the existing `categories/` pattern so future
   maintainers don't have to learn a second metadata model.
5. Stdout/stderr discipline preserved — articles are pipe-safe.

## Non-goals (v1)

- **No search integration.** `:` is its own namespace; articles do not
  appear in `/keyword` or `!intent` results. Promotable later if value
  emerges.
- **No syncing with `docs/`.** The CLI articles are independently
  authored, terminal-tuned prose. VitePress content stays as-is.
- **No tags / levels / see-also fields.** YAGNI — add when a real
  cross-reference need surfaces.
- **No Mercurial parity in v1.** `hg-config/` follows separately if/when
  needed; the dispatcher pattern transfers cleanly.

## Approach

**Approach A** (chosen): Python module mirroring the categories pattern.

Considered alternatives:

| | A — Python module (chosen) | B — Pure Bash | C — Hybrid |
|---|---|---|---|
| Startup cost | ~150ms (`uv run`) | ~5ms | ~150ms |
| Frontmatter parsing | `tomllib` (clean) | awk/sed (fragile if grows) | `tomllib` |
| Symmetry with `categories/` | High | Low | Medium |
| Future extensibility (tags etc.) | Easy | Painful | Easy |
| Test infrastructure | Reuse `python/tests/` | Bash-only | Split |

A wins because users already accept the same `uv run` cost on `hug help
@branching`; consistency with the categories tooling pays back the
startup cost in maintainability.

## Architecture

### Invocation surface

```
hug help :              → list articles (titles + summaries + tip)
hug help :<title>       → render article <title>
hug help :<bad-title>   → friendly error + closest fuzzy matches
```

`:` joins `@`, `/`, `!` without colliding — `:` is not a valid character
in any `git-*` script name, so the dispatcher case is unambiguous.

### File layout

```
git-config/lib/python/
├── articles/
│   └── hug-101.md
├── articles_loader.py        ← new
├── categories/               ← existing
├── category_meta.py          ← existing
└── help_search.py            ← extended with `:` mode
```

### Frontmatter schema

TOML fenced by `+++` (chosen over YAML for consistency with the project's
`tomllib` dependency and to visually distinguish from YAML's `---`):

```markdown
+++
title   = "Hug 101: Your first 10 minutes"
summary = "Quickstart for the canonical add → commit → push workflow."
order   = 10
+++

# Hug 101

Markdown body here…
```

**Required fields:** `title`, `summary` (≤ 70 chars — same column-budget
constraint as `CategoryMeta.summary`).
**Optional fields (v1):** `order` (sort key for listing, ascending;
default 100; ties break alphabetically by slug).

**Slug = filename stem.** `articles/hug-101.md` → `:hug-101`. No separate
slug field — single source of truth, matches the `categories/` convention.

### Validation policy

Strict, surfaced as load-time hard failures (mirrors
`category_meta.load_categories`):

- Missing or malformed `+++` fences → `ValueError`
- Missing required field → `ValueError` naming the field
- `summary` > 70 chars → `ValueError`
- TOML parse error → `ValueError` with file path

Drift is loud, not silent.

## Dispatch & rendering

### Dispatcher delta — `git-hughelp`

One new case in the existing sigil switch:

```bash
case "$prefix" in
/*) exec uv run … help_search.py "/" "${prefix#/}" "${@:2}" ;;
@*) exec uv run … help_search.py "@" "${prefix#@}" "${@:2}" ;;
!*) exec uv run … help_search.py "!" "${prefix#!}" "${@:2}" ;;
:*) exec uv run … help_search.py ":" "${prefix#:}" "${@:2}" ;;   # NEW
esac
```

`help_search.py main()` adds `:` to the mode `choices`; the parsing and
rendering work lives in `articles_loader.py` to keep `help_search.py`
focused on search.

### Rendering pipeline (TTY-aware, pipe-safe)

```python
def render_article(meta: ArticleMeta) -> None:
    body = strip_frontmatter(meta.path.read_text())
    if not sys.stdout.isatty():
        sys.stdout.write(body)            # pipe-safe: raw markdown
        return
    rendered = gum_format(body) if gum_available() else body
    if shutil.which("less"):
        subprocess.run(["less", "-RFX"], input=rendered, text=True, check=False)
    else:
        sys.stdout.write(rendered)
```

**Why `less -RFX`:**
- `-R` preserves ANSI colors from `gum format`
- `-F` quits immediately if content fits one screen — short articles
  never see the pager
- `-X` doesn't clear the screen on exit, so the article stays visible
  in scrollback

**Why TTY gating:** piping (`hug help :hug-101 | grep workflow`) yields
raw markdown, which is grep-friendly. Stdout/stderr discipline applies —
rendered body to stdout, "Article not found, did you mean…?" chatter to
stderr.

`gum_available()` and `gum_format` invocations follow the same gating
the rest of the project uses; gum's absence is graceful (raw markdown is
still readable).

## Listing layout (`hug help :`)

Mirrors `format_category_list`. Stdout/stderr split per project
discipline — slug lines on stdout (scriptable), chatter on stderr.

**Stderr:**
```
── Articles ────────────────────────────────────────────
```

**Stdout (pipe-safe, scriptable):**
```
  :hug-101    — Quickstart for the canonical add → commit → push workflow.
```

**Stderr:**
```
Tip: `hug help :<title>` to read an article.
```

Sort: `order` ascending, then alphabetical by slug. Slug column
auto-fits like `format_category_list`. Summary wraps to terminal width
via the existing `_terminal_width()` helper.

**Empty articles dir:** "No articles available yet." → stderr, exit 0.

## Error handling

| Failure | Behavior | Exit |
|---|---|---|
| `articles/` missing or empty | "No articles available yet." → stderr | 0 |
| Slug not found | Fuzzy-match titles + slugs; suggest top 3 → stderr | 1 |
| Malformed frontmatter | Hard load failure with file path → stderr | 1 |
| Missing required field | Hard load failure naming the field → stderr | 1 |
| Unreadable article file | OS error → stderr | 1 |
| `gum` not on PATH | Silent fallback to raw markdown | 0 |
| `less` not on PATH | Silent fallback to direct print | 0 |
| Stdout not a TTY | Raw markdown, no pager, no rendering | 0 |

**Slug typo example:**
```
$ hug help :hug101
error: no article named ':hug101'

Did you mean:
  :hug-101  — Quickstart for the canonical add → commit → push workflow.
```

Fuzzy slug suggestion reuses the scoring shape from `search_category`
(strict `ratio()` against curated short strings; `MIN_CATEGORY_SCORE`-style
floor).

## Content: `:hug-101` outline

Target ~250 lines. Outline (one `##` per section):

```markdown
+++
title   = "Hug 101: Your first 10 minutes"
summary = "Quickstart for the canonical add → commit → push workflow."
order   = 10
+++

# Hug 101

Tagline + one-paragraph intro: hug is a humane git wrapper.
Prefix-based commands; shorter = safer.

## Mental model
- Commands are organized by semantic prefix (h*, w*, s*, b*, c*…).
- Shorter commands are safer; longer commands are more powerful.
- Every destructive op supports --dry-run and confirmation.
- `hug help` is your friend.

## The five-minute path
### 1. Start a project
    hug init                 # new repo
    hug clone <url>          # existing remote

### 2. The daily loop
    hug s                    # what changed
    hug a <files>            # stage
    hug c -m "message"       # commit
    hug bpush                # push (auto -u tracking)

### 3. Look at history
    hug ll -10               # last 10 commits, oneline
    hug sh HEAD              # details on the last commit

### 4. When something goes wrong
    hug w discard <file>     # revert one file's unstaged changes
    hug h back               # move HEAD back, keep staged changes
    hug h undo               # move HEAD back, unstage too

## The shorter-is-safer principle
Brief callout with two examples: `hug a` vs `hug aa`,
`hug w discard` vs `hug w wipe`.

## Discover more
    hug help                 # category overview
    hug help @               # all categories
    hug help @branching      # learn one category
    hug help /undo           # fuzzy keyword search
    hug help '!save my work' # natural-language intent search
    hug help :               # more articles like this one

## Next steps
Pointers to (future) articles: `:cookbook`, `:undoing-changes`,
`:branching-101`. For now: `hug help <command>` for full help on
any command.
```

Three reasons this scope is right:

1. Lands within ~250 lines — fits the chosen mid-form target.
2. Every command shown is real and runnable today; no aspirational examples.
3. Ends pointing at the discovery surface (`@`, `/`, `!`, `:`) — the
   article seeds the habit of using `hug help`.

## Testing strategy

Two layers, mirroring the categories tests.

### Python unit tests
**File:** `git-config/lib/python/tests/test_articles_loader.py` (new)

- `parse_article` happy path: `+++ … +++` → `ArticleMeta(title, summary, order, body, slug, path)`
- Missing `+++` fence → `ValueError` with file path
- Missing required field → `ValueError` naming the field
- `summary` > 70 chars → `ValueError`
- TOML parse error → `ValueError`
- `list_articles(dir)` returns sorted by `order` then slug
- `find_article("hug-101")` exact match returns one
- `find_article("hug101")` exact miss → returns suggestions list
- `format_article_list` width-bounded, slugs aligned, summaries wrapped
- Empty dir → empty list, no error

### BATS end-to-end
**File:** extend `tests/unit/test_help.bats` (or new `test_help_articles.bats`)

- `hug help :` → lists `:hug-101`, contains "Articles" header, contains "Tip:"
- `hug help :hug-101` → exit 0, body contains "# Hug 101" or rendered equivalent
- `hug help :bad-slug` → exit 1, stderr contains "Did you mean", suggests `:hug-101`
- Pipe safety: `hug help :hug-101 | grep '^# '` → finds the H1 (raw markdown when non-TTY)
- Stdout/stderr split: `hug help : 2>/dev/null` shows only article slug lines (no header/tip)
- No-`gum` path: simulate restricted PATH — should still succeed with raw markdown

### Test fixtures
`tests/fixtures/articles/` — small fixture articles so unit tests don't
depend on the production `:hug-101` content. Mirrors how
`tests/fixtures/categories/` (or equivalent) is used for the categories
tests.

### Quality regression corpus
No corpus changes for v1. `:` is its own namespace; the existing
`/keyword` and `!intent` corpora stay untouched. If articles later get
integrated into search, add a corpus entry then.

## Open questions / deferred

- **Mercurial parity (`hg-config/`):** can be added in a follow-up by
  copying the dispatcher delta and reusing the same Python loader. Not
  in v1 scope.
- **Future articles:** `:cookbook`, `:undoing-changes`, `:branching-101`,
  `:worktrees-101` are obvious next candidates. The `:hug-101` outline
  references them; create files when written.
- **VitePress integration:** if/when valuable, a follow-up could mirror
  CLI articles into a docs/articles/ section, or vice-versa. Out of v1.

## Files to create / modify

**Create:**
- `git-config/lib/python/articles_loader.py` — parser, finder, formatters
- `git-config/lib/python/articles/hug-101.md` — first article
- `git-config/lib/python/tests/test_articles_loader.py` — unit tests
- `tests/unit/test_help_articles.bats` (or extend `test_help.bats`) — BATS tests
- Test fixtures under `tests/fixtures/articles/`

**Modify:**
- `git-config/bin/git-hughelp` — add `:*)` dispatch case
- `git-config/lib/python/help_search.py` — add `:` to mode choices,
  delegate to `articles_loader`; update top-level help text on bare
  `hug help` to mention the `:` sigil
- (optional) `docs/plans/` index / `DOCS_ORGANIZATION.md` if used to
  track active plans
