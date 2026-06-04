# `hug help :<article>` Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add a `:` sigil to `hug help` so users can read terminal-tuned mini-guides (`hug help :hug-101` renders an article; `hug help :` lists them).

**Architecture:** Approach A from the design — a Python module mirroring the existing categories pattern. Articles are markdown files with TOML `+++` frontmatter under `git-config/lib/python/articles/`. A new `articles_loader.py` (parallel to `category_meta.py`) parses, lists, finds, and renders them. The `git-hughelp` dispatcher gets one extra `:*)` case forwarding to `help_search.py`, which adds `:` as a fourth mode.

**Tech Stack:** Python 3.8+ (uses stdlib `tomllib` ≥ 3.11, `tomli` backport otherwise — already pinned). Bash 5+. `gum format` for rendering when available, `less -RFX` for paging when content exceeds the screen. No new dependencies.

**Source design:** [`docs/plans/2026-05-06-help-articles-design.md`](./2026-05-06-help-articles-design.md)

---

## Tasks at a glance

| # | Task | Layer | Depends on |
|---|------|-------|------------|
| 0 | Test fixtures | Python tests | — |
| 1 | `ArticleMeta` + frontmatter parser | `articles_loader.py` | 0 |
| 2 | `load_articles(dir)` listing + sort | `articles_loader.py` | 1 |
| 3 | `find_article` exact + fuzzy fallback | `articles_loader.py` | 2 |
| 4 | `format_article_list` (listing renderer) | `articles_loader.py` | 2 |
| 5 | `render_article` (TTY pipeline) | `articles_loader.py` | 1 |
| 6 | Wire `:` mode in `help_search.py main()` | `help_search.py` | 3, 4, 5 |
| 7 | Wire `:*)` in `git-hughelp` + top-level help text | `git-hughelp` | 6 |
| 8 | Author the first article: `hug-101.md` | content | 7 |
| 9 | BATS end-to-end coverage | tests | 8 |
| 10 | Lint, format, full test suite | sanitize | 9 |

Frequent commits: every task ends with a commit. TDD throughout — failing test before code.

---

### Task 0: Set up test fixtures

**Files:**
- Create: `git-config/lib/python/tests/fixtures/articles/hug-test.md`
- Create: `git-config/lib/python/tests/fixtures/articles/zzz-second.md`
- Create: `git-config/lib/python/tests/fixtures/articles_bad/no_fences.md`
- Create: `git-config/lib/python/tests/fixtures/articles_bad/missing_title.md`
- Create: `git-config/lib/python/tests/fixtures/articles_bad/long_summary.md`

**Step 1: Create fixture articles**

`tests/fixtures/articles/hug-test.md`:
````markdown
+++
title   = "Hug test article"
summary = "Fixture article for unit tests."
order   = 10
+++

# Hug test article

Body paragraph one.

## Subsection

More body content.
````

`tests/fixtures/articles/zzz-second.md`:
````markdown
+++
title   = "Second test article"
summary = "Sorts after hug-test by order."
order   = 20
+++

# Second
````

**Step 2: Create malformed fixtures**

`tests/fixtures/articles_bad/no_fences.md`:
````markdown
title = "Missing fences"

Just a plain markdown file with no frontmatter fences.
````

`tests/fixtures/articles_bad/missing_title.md`:
````markdown
+++
summary = "No title field at all."
+++

# Body
````

`tests/fixtures/articles_bad/long_summary.md`:
````markdown
+++
title   = "Too long summary"
summary = "This summary intentionally exceeds the seventy character cap by being verbose and rambling on and on."
+++

# Body
````

**Step 3: Commit**

```bash
hug a git-config/lib/python/tests/fixtures/articles/ git-config/lib/python/tests/fixtures/articles_bad/
hug c -m "test: add article fixtures for articles_loader tests"
```

---

### Task 1: `ArticleMeta` dataclass + frontmatter parser

**Files:**
- Create: `git-config/lib/python/articles_loader.py`
- Test: `git-config/lib/python/tests/test_articles_loader.py`

**Step 1: Write failing tests**

```python
# tests/test_articles_loader.py
"""Tests for articles_loader.py — `hug help :<article>` engine."""

from pathlib import Path

import pytest

from articles_loader import (
    ArticleMeta,
    SUMMARY_MAX,
    parse_article,
)

FIXTURES = Path(__file__).parent / "fixtures" / "articles"
BAD = Path(__file__).parent / "fixtures" / "articles_bad"


class TestParseArticle:
    """Frontmatter parser: +++ TOML +++ then markdown body."""

    def test_happy_path(self):
        meta = parse_article(FIXTURES / "hug-test.md")
        assert isinstance(meta, ArticleMeta)
        assert meta.slug == "hug-test"
        assert meta.title == "Hug test article"
        assert meta.summary == "Fixture article for unit tests."
        assert meta.order == 10
        assert meta.body.startswith("# Hug test article")
        assert "Subsection" in meta.body

    def test_default_order_is_100(self):
        # zzz-second has order=20; build a fixture without order to test default.
        # Inline construction beats another fixture file for one test.
        # (skipped here — use tmp_path)
        pass

    def test_missing_fences_raises(self):
        with pytest.raises(ValueError, match="frontmatter"):
            parse_article(BAD / "no_fences.md")

    def test_missing_title_raises(self):
        with pytest.raises(ValueError, match="title"):
            parse_article(BAD / "missing_title.md")

    def test_long_summary_raises(self):
        with pytest.raises(ValueError, match="summary"):
            parse_article(BAD / "long_summary.md")

    def test_default_order_when_absent(self, tmp_path):
        p = tmp_path / "x.md"
        p.write_text(
            '+++\ntitle   = "X"\nsummary = "S"\n+++\n\n# X\n'
        )
        meta = parse_article(p)
        assert meta.order == 100
        assert meta.slug == "x"
```

**Step 2: Run tests to verify they fail**

```bash
make test-lib-py TEST_FILTER=test_articles_loader
```

Expected: ImportError on `articles_loader` (module not yet created).

**Step 3: Implement `articles_loader.py` minimum**

```python
"""Article loader for `hug help :<slug>` — terminal-tuned mini-guides.

Articles are markdown files with TOML frontmatter fenced by '+++':

    +++
    title   = "Hug 101"
    summary = "Quickstart…"        # ≤ SUMMARY_MAX chars
    order   = 10                    # optional sort key (default 100)
    +++

    # Body markdown follows…

WHY a separate module: keeps the article concerns (parse, list, find,
render) out of help_search.py, which stays focused on search. Mirrors
the categories/category_meta.py split for the same reason — clean
boundary, easy to test in isolation.

WHY +++ over --- fences: avoids YAML confusion and signals "TOML inside"
visually. Matches Hugo/Zola conventions; not gratuitous novelty.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

if sys.version_info >= (3, 11):
    import tomllib  # type: ignore[import-not-found]
else:
    import tomli as tomllib  # type: ignore[no-redef]


# Mirrors CategoryMeta.summary cap so listing columns line up consistently.
SUMMARY_MAX = 70

# Default sort key when an article omits `order`. 100 leaves room for
# curated articles to slot before (e.g. hug-101 with order=10) and
# after (e.g. an appendix with order=200) without renumbering.
DEFAULT_ORDER = 100

_FENCE = "+++"


@dataclass(frozen=True)
class ArticleMeta:
    """Parsed article: filesystem path + frontmatter fields + raw body.

    `slug` is the filename stem (without `.md`) and is the canonical
    identifier — what users type after `:`.

    `body` is the markdown after the closing fence, with one leading
    blank line stripped if present (so `# Title` starts cleanly).
    """

    slug: str
    title: str
    summary: str
    order: int
    body: str
    path: Path


def parse_article(path: Path) -> ArticleMeta:
    """Parse one article file. Raises ValueError on schema violations.

    The contract: opening line MUST be exactly `+++`. The next `+++`
    line closes the frontmatter. Everything between is TOML; everything
    after (minus one optional blank line) is the markdown body.
    """
    text = Path(path).read_text(encoding="utf-8")
    lines = text.splitlines()

    if not lines or lines[0].strip() != _FENCE:
        raise ValueError(f"{path}: missing opening +++ frontmatter fence")

    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == _FENCE:
            end = i
            break
    if end is None:
        raise ValueError(f"{path}: missing closing +++ frontmatter fence")

    fm_text = "\n".join(lines[1:end])
    try:
        data = tomllib.loads(fm_text)
    except tomllib.TOMLDecodeError as exc:
        raise ValueError(f"{path}: invalid TOML in frontmatter: {exc}") from exc

    if "title" not in data:
        raise ValueError(f"{path}: missing 'title' in frontmatter")
    if "summary" not in data:
        raise ValueError(f"{path}: missing 'summary' in frontmatter")
    summary = str(data["summary"])
    if len(summary) > SUMMARY_MAX:
        raise ValueError(
            f"{path}: 'summary' exceeds {SUMMARY_MAX} chars (got {len(summary)})"
        )

    # Body: lines after the closing fence; strip one leading blank line
    # so authors can write `+++\n\n# Title` and have it render cleanly.
    body_lines = lines[end + 1 :]
    if body_lines and body_lines[0].strip() == "":
        body_lines = body_lines[1:]
    body = "\n".join(body_lines)

    return ArticleMeta(
        slug=path.stem,
        title=str(data["title"]),
        summary=summary,
        order=int(data.get("order", DEFAULT_ORDER)),
        body=body,
        path=path,
    )
```

**Step 4: Run tests to verify they pass**

```bash
make test-lib-py TEST_FILTER=test_articles_loader
```

Expected: all `TestParseArticle` tests pass.

**Step 5: Commit**

```bash
hug a git-config/lib/python/articles_loader.py git-config/lib/python/tests/test_articles_loader.py
hug c -m "feat: add ArticleMeta + parse_article frontmatter loader"
```

---

### Task 2: `load_articles(dir)` — directory listing + sort

**Files:**
- Modify: `git-config/lib/python/articles_loader.py`
- Modify: `git-config/lib/python/tests/test_articles_loader.py`

**Step 1: Add failing tests**

```python
class TestLoadArticles:
    """Loader returns ArticleMeta list sorted by order, then slug."""

    def test_loads_all_md_files(self):
        articles = load_articles(FIXTURES)
        slugs = [a.slug for a in articles]
        assert slugs == ["hug-test", "zzz-second"]  # order=10 then order=20

    def test_default_order_falls_back_to_alpha(self, tmp_path):
        # Two articles with same default order → alphabetical by slug.
        (tmp_path / "bbb.md").write_text(
            '+++\ntitle = "B"\nsummary = "b"\n+++\n\n# B\n'
        )
        (tmp_path / "aaa.md").write_text(
            '+++\ntitle = "A"\nsummary = "a"\n+++\n\n# A\n'
        )
        articles = load_articles(tmp_path)
        assert [a.slug for a in articles] == ["aaa", "bbb"]

    def test_empty_dir(self, tmp_path):
        assert load_articles(tmp_path) == []

    def test_missing_dir(self, tmp_path):
        # Missing dir is treated as empty (articles are an opt-in feature).
        assert load_articles(tmp_path / "nope") == []

    def test_propagates_parse_errors(self):
        with pytest.raises(ValueError, match="missing 'title'"):
            load_articles(BAD)
```

Update the imports at top of the test file:

```python
from articles_loader import (
    ArticleMeta,
    SUMMARY_MAX,
    load_articles,
    parse_article,
)
```

**Step 2: Run tests to verify they fail**

```bash
make test-lib-py TEST_FILTER=test_articles_loader
```

Expected: `ImportError: cannot import name 'load_articles'`.

**Step 3: Implement `load_articles`**

Append to `articles_loader.py`:

```python
def load_articles(directory: str | Path) -> list[ArticleMeta]:
    """Return every <slug>.md under `directory`, sorted by (order, slug).

    Missing or empty directory returns []. Articles are an opt-in CLI
    feature; absence is not an error. Parse errors propagate — strict
    validation per the categories pattern (loud drift, not silent).
    """
    base = Path(directory)
    if not base.is_dir():
        return []
    metas = [parse_article(p) for p in sorted(base.glob("*.md"))]
    metas.sort(key=lambda m: (m.order, m.slug))
    return metas
```

**Step 4: Run tests to verify they pass**

```bash
make test-lib-py TEST_FILTER=test_articles_loader
```

Expected: all `TestLoadArticles` tests pass.

**Step 5: Commit**

```bash
hug a git-config/lib/python/articles_loader.py git-config/lib/python/tests/test_articles_loader.py
hug c -m "feat: add load_articles directory loader with order/slug sort"
```

---

### Task 3: `find_article` — exact match + fuzzy fallback

**Files:**
- Modify: `git-config/lib/python/articles_loader.py`
- Modify: `git-config/lib/python/tests/test_articles_loader.py`

**Step 1: Add failing tests**

```python
class TestFindArticle:
    """Lookup: exact slug match, else fuzzy suggestions."""

    def test_exact_match(self):
        articles = load_articles(FIXTURES)
        result = find_article(articles, "hug-test")
        assert result.found is not None
        assert result.found.slug == "hug-test"
        assert result.suggestions == []

    def test_no_match_returns_suggestions(self):
        articles = load_articles(FIXTURES)
        result = find_article(articles, "hug-tst")  # typo
        assert result.found is None
        assert any(a.slug == "hug-test" for a in result.suggestions)

    def test_unrelated_query_returns_empty_suggestions(self):
        articles = load_articles(FIXTURES)
        result = find_article(articles, "zzzzzzzzzzz")
        assert result.found is None
        # No fuzzy hits — empty suggestions, caller renders generic
        # "no article" message.
        assert result.suggestions == []
```

**Step 2: Run tests to verify they fail**

```bash
make test-lib-py TEST_FILTER=test_articles_loader
```

Expected: ImportError on `find_article` / `FindResult`.

**Step 3: Implement `find_article`**

The fuzzy match reuses the same scorer family `help_search.py` already
wires up (`thefuzz.fuzz.ratio` or substring fallback). To avoid a tight
coupling, articles_loader gets its own thin wrapper that imports lazily.

Append to `articles_loader.py`:

```python
# Fuzzy threshold: matches MIN_CATEGORY_SCORE in help_search.py.
# Slugs are short, kebab-case, low-noise — strict ratio() with floor 60
# accepts genuine typos ("hug-tst" → "hug-test") while rejecting
# unrelated queries ("zzzzz").
_MIN_FUZZY_SCORE = 60
_MAX_SUGGESTIONS = 3


@dataclass(frozen=True)
class FindResult:
    """Result of looking up an article by slug.

    `found` is the exact-match ArticleMeta or None.
    `suggestions` is a list of fuzzy-matched ArticleMeta when found is
    None — capped to _MAX_SUGGESTIONS so the error UI stays scannable.
    """

    found: ArticleMeta | None
    suggestions: list[ArticleMeta]


def _ratio(query: str, target: str) -> int:
    """Strict full-string fuzzy ratio (0–100). Substring-only fallback.

    Lazy import keeps articles_loader importable in environments without
    thefuzz (the `--extra search` flag isn't passed). The fallback gives
    a binary 0/100 signal — enough to gate suggestions when the optional
    dep is absent.
    """
    try:
        from thefuzz import fuzz  # type: ignore[import-not-found]

        return fuzz.ratio(query.lower(), target.lower())
    except ImportError:
        return 100 if query.lower() == target.lower() else (
            80 if query.lower() in target.lower() else 0
        )


def find_article(articles: list[ArticleMeta], query: str) -> FindResult:
    """Look up by slug; on miss, return up to _MAX_SUGGESTIONS fuzzy hits.

    Scoring fields: slug (primary, low-noise) + title (secondary, may
    contain spaces). Take the better of the two per article. Suggestions
    are sorted by score descending.
    """
    for a in articles:
        if a.slug == query:
            return FindResult(found=a, suggestions=[])

    scored: list[tuple[int, ArticleMeta]] = []
    for a in articles:
        score = max(_ratio(query, a.slug), _ratio(query, a.title))
        if score >= _MIN_FUZZY_SCORE:
            scored.append((score, a))
    scored.sort(key=lambda x: x[0], reverse=True)
    return FindResult(found=None, suggestions=[a for _, a in scored[:_MAX_SUGGESTIONS]])
```

Update test imports:

```python
from articles_loader import (
    ArticleMeta,
    FindResult,
    SUMMARY_MAX,
    find_article,
    load_articles,
    parse_article,
)
```

**Step 4: Run tests to verify they pass**

```bash
make test-lib-py TEST_FILTER=test_articles_loader
```

Expected: all `TestFindArticle` tests pass.

**Step 5: Commit**

```bash
hug a git-config/lib/python/articles_loader.py git-config/lib/python/tests/test_articles_loader.py
hug c -m "feat: add find_article exact + fuzzy-fallback lookup"
```

---

### Task 4: `format_article_list` — listing renderer

**Files:**
- Modify: `git-config/lib/python/articles_loader.py`
- Modify: `git-config/lib/python/tests/test_articles_loader.py`

**Step 1: Add failing tests**

```python
class TestFormatArticleList:
    """Listing format: stdout-safe slug column + summary, stderr chatter separate."""

    def test_listing_includes_slugs_and_summaries(self):
        articles = load_articles(FIXTURES)
        header, body, footer = format_article_list(articles, width=72)
        assert ":hug-test" in body
        assert "Fixture article for unit tests." in body
        assert "Articles" in header
        assert "hug help :" in footer

    def test_empty_listing_message(self):
        header, body, footer = format_article_list([], width=72)
        assert body == ""
        assert "No articles available yet" in header

    def test_slug_column_aligns(self):
        articles = load_articles(FIXTURES)
        _, body, _ = format_article_list(articles, width=72)
        # Both lines should have the em-dash separator at the same column.
        lines = [ln for ln in body.split("\n") if " — " in ln]
        positions = {ln.index(" — ") for ln in lines}
        assert len(positions) == 1, f"slug columns misaligned: {positions}"
```

**Step 2: Run tests to verify they fail**

Expected: ImportError on `format_article_list`.

**Step 3: Implement `format_article_list`**

Append to `articles_loader.py`:

```python
def format_article_list(
    articles: list[ArticleMeta],
    width: int = 72,
) -> tuple[str, str, str]:
    """Render the `hug help :` listing as (header, body, footer) strings.

    Returning three strings (instead of one) lets the caller route them
    across stderr/stdout per the project discipline — `body` (the slug
    lines) goes to stdout (pipe-safe, scriptable); `header` and `footer`
    (chatter) go to stderr.

    Empty list: header carries "No articles available yet."; body is "";
    footer is "". Caller still emits exit 0 — empty articles dir isn't
    an error.
    """
    width = max(40, min(width, 100))
    rule = "── Articles " + "─" * max(0, width - len("── Articles "))

    if not articles:
        return ("No articles available yet.", "", "")

    name_w = max(len(a.slug) + 1 for a in articles)  # +1 for leading ':'
    body_lines = [
        f"  :{a.slug:<{name_w - 1}}  — {a.summary}" for a in articles
    ]
    body = "\n".join(body_lines)
    footer = "Tip: `hug help :<title>` to read an article."
    return (rule, body, footer)
```

**Step 4: Run tests to verify they pass**

```bash
make test-lib-py TEST_FILTER=test_articles_loader
```

Expected: all `TestFormatArticleList` tests pass.

**Step 5: Commit**

```bash
hug a git-config/lib/python/articles_loader.py git-config/lib/python/tests/test_articles_loader.py
hug c -m "feat: add format_article_list listing renderer"
```

---

### Task 5: `render_article` — TTY-aware rendering pipeline

**Files:**
- Modify: `git-config/lib/python/articles_loader.py`
- Modify: `git-config/lib/python/tests/test_articles_loader.py`

**Step 1: Add failing tests**

```python
class TestRenderArticle:
    """Rendering pipeline: gum format if TTY+available, else raw markdown."""

    def test_non_tty_emits_raw_markdown(self, capsys, monkeypatch):
        # Force stdout.isatty() False so the function takes the pipe-safe path.
        monkeypatch.setattr("sys.stdout.isatty", lambda: False)
        articles = load_articles(FIXTURES)
        render_article(articles[0])  # hug-test
        captured = capsys.readouterr()
        # Body is markdown source — heading marker visible.
        assert "# Hug test article" in captured.out
        # No ANSI escape sequences in pipe-safe path.
        assert "\x1b[" not in captured.out

    def test_tty_without_gum_or_less_falls_back_to_print(
        self, capsys, monkeypatch
    ):
        monkeypatch.setattr("sys.stdout.isatty", lambda: True)
        # No gum, no less → just prints body.
        monkeypatch.setattr("shutil.which", lambda name: None)
        articles = load_articles(FIXTURES)
        render_article(articles[0])
        captured = capsys.readouterr()
        assert "# Hug test article" in captured.out
```

**Step 2: Run tests to verify they fail**

Expected: ImportError on `render_article`.

**Step 3: Implement `render_article`**

Append to `articles_loader.py`:

```python
import shutil
import subprocess


def _gum_format(markdown: str) -> str | None:
    """Run `gum format` on markdown; return rendered ANSI or None on failure.

    Returning None on failure (rather than raising) lets the caller fall
    through to the next strategy — the project's stance is graceful
    degradation when optional polish tools are absent.
    """
    if not shutil.which("gum"):
        return None
    try:
        result = subprocess.run(
            ["gum", "format"],
            input=markdown,
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (subprocess.TimeoutExpired, OSError):
        return None
    if result.returncode != 0:
        return None
    return result.stdout


def render_article(meta: ArticleMeta) -> None:
    """Render `meta.body` to stdout with TTY-aware polish.

    Pipe-safe: when stdout is not a TTY (piped, captured), emit raw
    markdown — predictable for `hug help :hug-101 | grep workflow`.

    On a TTY: try `gum format` for polished ANSI output; pipe through
    `less -RFX` so short articles print directly (`-F` quits if it fits)
    and long articles get paged with colors preserved (`-R`) and the
    screen not cleared on exit (`-X`, content stays in scrollback).
    """
    body = meta.body
    if not sys.stdout.isatty():
        sys.stdout.write(body)
        if not body.endswith("\n"):
            sys.stdout.write("\n")
        return

    rendered = _gum_format(body) or body

    if shutil.which("less"):
        try:
            subprocess.run(
                ["less", "-RFX"],
                input=rendered,
                text=True,
                check=False,
            )
            return
        except OSError:
            pass  # Fall through to direct write.

    sys.stdout.write(rendered)
    if not rendered.endswith("\n"):
        sys.stdout.write("\n")
```

**Step 4: Run tests to verify they pass**

```bash
make test-lib-py TEST_FILTER=test_articles_loader
```

Expected: all `TestRenderArticle` tests pass.

**Step 5: Commit**

```bash
hug a git-config/lib/python/articles_loader.py git-config/lib/python/tests/test_articles_loader.py
hug c -m "feat: add render_article TTY-aware pipeline (gum + less + raw)"
```

---

### Task 6: Wire `:` mode into `help_search.py main()`

**Files:**
- Modify: `git-config/lib/python/help_search.py`
- Modify: `git-config/lib/python/tests/test_help_search.py`

**Step 1: Add failing tests**

```python
# Append to tests/test_help_search.py:

class TestArticleMode:
    """`:` mode dispatches to articles_loader."""

    def test_bare_colon_lists_articles(self, capsys, monkeypatch, tmp_path):
        # Stand up a minimal articles dir.
        adir = tmp_path / "articles"
        adir.mkdir()
        (adir / "demo.md").write_text(
            '+++\ntitle = "Demo"\nsummary = "Demo article."\n+++\n\n# Demo\n'
        )
        monkeypatch.setattr("sys.argv", [
            "help_search.py", ":", "",
            "--bin-dir", str(tmp_path),  # not used by : mode
            "--articles-dir", str(adir),
            "--cache-dir", str(tmp_path / "cache"),
            "--categories-dir", str(tmp_path / "cats"),  # empty, that's fine
        ])
        # Empty categories dir: validate_against_scripts gets {} vs {},
        # which is fine — no scripts to validate.
        (tmp_path / "cats").mkdir()

        from help_search import main
        main()
        out = capsys.readouterr()
        # Slug appears on stdout (body); chatter on stderr.
        assert ":demo" in out.out
        assert "Articles" in out.err

    def test_colon_slug_renders_article(self, capsys, monkeypatch, tmp_path):
        adir = tmp_path / "articles"
        adir.mkdir()
        (adir / "demo.md").write_text(
            '+++\ntitle = "Demo"\nsummary = "Demo."\n+++\n\n# Demo\n\nBody.\n'
        )
        (tmp_path / "cats").mkdir()
        monkeypatch.setattr("sys.argv", [
            "help_search.py", ":", "demo",
            "--bin-dir", str(tmp_path),
            "--articles-dir", str(adir),
            "--cache-dir", str(tmp_path / "cache"),
            "--categories-dir", str(tmp_path / "cats"),
        ])
        # Force non-TTY so render_article emits raw markdown to stdout.
        monkeypatch.setattr("sys.stdout.isatty", lambda: False)

        from help_search import main
        main()
        out = capsys.readouterr()
        assert "# Demo" in out.out
        assert "Body." in out.out

    def test_colon_unknown_slug_suggests(self, capsys, monkeypatch, tmp_path):
        adir = tmp_path / "articles"
        adir.mkdir()
        (adir / "hug-101.md").write_text(
            '+++\ntitle = "Hug 101"\nsummary = "Quickstart."\n+++\n\n# Hug 101\n'
        )
        (tmp_path / "cats").mkdir()
        monkeypatch.setattr("sys.argv", [
            "help_search.py", ":", "hug101",
            "--bin-dir", str(tmp_path),
            "--articles-dir", str(adir),
            "--cache-dir", str(tmp_path / "cache"),
            "--categories-dir", str(tmp_path / "cats"),
        ])
        from help_search import main
        with pytest.raises(SystemExit) as exc:
            main()
        assert exc.value.code == 1
        out = capsys.readouterr()
        assert "no article named" in out.err
        assert ":hug-101" in out.err
```

**Step 2: Run tests to verify they fail**

```bash
make test-lib-py TEST_FILTER=test_help_search
```

Expected: failures — `:` not a valid choice, `--articles-dir` unknown.

**Step 3: Modify `help_search.py main()`**

Add `:` to mode choices and a new dispatch branch. Inside `main()` near
the existing argparse block (around line 714):

```python
parser.add_argument("mode", choices=["/", "@", "!", ":"], help="Search mode")
# ... existing args ...
parser.add_argument(
    "--articles-dir",
    default=os.path.join(os.path.dirname(__file__), "articles"),
    help="Directory containing article markdown files",
)
```

Add a new branch after the `elif args.mode == "!":` block (around line 807):

```python
    elif args.mode == ":":
        # Article mode: load articles, dispatch by query presence.
        from articles_loader import (
            find_article,
            format_article_list,
            load_articles,
            render_article,
        )

        try:
            articles = load_articles(args.articles_dir)
        except ValueError as exc:
            print(f"error: {exc}", file=sys.stderr)
            sys.exit(1)

        if not args.query:
            # Listing: route streams per stdout/stderr discipline.
            header, body, footer = format_article_list(
                articles, width=_terminal_width()
            )
            print(header, file=sys.stderr, flush=True)
            if body:
                print(body, flush=True)
            if footer:
                print(footer, file=sys.stderr, flush=True)
            return

        result = find_article(articles, args.query)
        if result.found is not None:
            render_article(result.found)
            return

        print(f"error: no article named ':{args.query}'", file=sys.stderr)
        if result.suggestions:
            print("", file=sys.stderr)
            print("Did you mean:", file=sys.stderr)
            for s in result.suggestions:
                print(f"  :{s.slug}  — {s.summary}", file=sys.stderr)
        sys.exit(1)
```

**Step 4: Run tests to verify they pass**

```bash
make test-lib-py TEST_FILTER=test_help_search
```

Expected: all `TestArticleMode` tests pass; pre-existing tests stay green.

**Step 5: Commit**

```bash
hug a git-config/lib/python/help_search.py git-config/lib/python/tests/test_help_search.py
hug c -m "feat: wire : mode into help_search.py for article dispatch"
```

---

### Task 7: Wire `:*)` dispatch + update top-level help text

**Files:**
- Modify: `git-config/bin/git-hughelp`

**Step 1: Inspect current dispatcher state**

```bash
sed -n '20,45p' git-config/bin/git-hughelp
```

Expected: lines 22–26 list `@`, `/`, `!` tips; lines 36–40 the `case "$prefix"` block.

**Step 2: Add `:*)` case to the dispatcher**

In `git-config/bin/git-hughelp`, modify the `case "$prefix"` block (lines 36–40) to:

```bash
case "$prefix" in
/*) exec uv run --directory "$dir/../lib/python" --extra search help_search.py "/" "${prefix#/}" "${@:2}" ;;
@*) exec uv run --directory "$dir/../lib/python" --extra search help_search.py "@" "${prefix#@}" "${@:2}" ;;
!*) exec uv run --directory "$dir/../lib/python" --extra search help_search.py "!" "${prefix#!}" "${@:2}" ;;
:*) exec uv run --directory "$dir/../lib/python" --extra search help_search.py ":" "${prefix#:}" "${@:2}" ;;
esac
```

**Step 3: Add `:` tip to top-level help text**

In the same file, modify the topic-search tips block (lines 22–26) to:

```bash
  echo 'Topic search:'
  echo '  hug help @           - List all categories'
  echo '  hug help @<category> - Learn about a category and list its commands'
  echo '  hug help /<keyword>  - Search commands by keyword (fuzzy)'
  echo '  hug help '\''!<intent>'\''   - Find commands by what you want to do'
  echo '  hug help :           - List articles (mini-guides)'
  echo '  hug help :<title>    - Read an article'
```

**Step 4: Smoke-test the dispatcher manually**

```bash
# Without an articles dir yet, : returns "No articles available yet."
hug help :
# Expected: stderr "No articles available yet.", exit 0
```

```bash
hug help :nope
# Expected: stderr "error: no article named ':nope'", exit 1
```

**Step 5: Commit**

```bash
hug a git-config/bin/git-hughelp
hug c -m "feat: dispatch :<title> sigil through help_search.py"
```

---

### Task 8: Author the first article — `:hug-101`

**Files:**
- Create: `git-config/lib/python/articles/hug-101.md`

**Step 1: Write the article**

Target ~250 lines following the outline from the design doc.

```markdown
+++
title   = "Hug 101: Your first 10 minutes"
summary = "Quickstart for the canonical add → commit → push workflow."
order   = 10
+++

# Hug 101

**Hug** is a humane CLI on top of Git. Same semantics, friendlier surface:
short prefixes (`h*`, `w*`, `s*`, `b*`, `c*`, `l*`), aggressive defaults
for common cases, and confirmations on anything destructive. Every git
operation has a hug equivalent — and the most useful ones are one or
two letters.

This article gets you from "I just installed it" to "I can do my
day-to-day work" in about ten minutes.

## Mental model

Four ideas that pay back across the whole CLI:

1. **Commands are organized by semantic prefix.** `h*` operates on HEAD,
   `w*` on the working directory, `s*` on staging/status, `b*` on
   branches, `c*` on commits, `l*` on logs. When you forget a name,
   `hug help <prefix>` lists everything in the family.
2. **Shorter is safer.** `hug a` stages tracked files only; `hug aa`
   stages everything including untracked. `hug w discard` reverts one
   file; `hug w wipe` wipes all unstaged changes. The longer you type,
   the more powerful (and dangerous) the command.
3. **Destructive ops are guarded.** They print what they're about to do,
   ask for confirmation, and support `--dry-run` for preview. Pass
   `--force` (or set `HUG_FORCE=true`) to skip the prompt.
4. **`hug help` is your friend.** Bare `hug help` lists prefixes;
   `hug help <prefix>` lists commands; `hug help <command>` shows full
   usage; `hug help @category`, `/keyword`, `!intent`, and `:article`
   discover by topic.

## The five-minute path

### 1. Start a project

    hug init               # new repo in current dir
    hug clone <url>        # existing remote (auto-detects Git/Mercurial)

### 2. The daily loop

    hug s                  # what changed (status summary)
    hug a <files>          # stage specific files
    hug c -m "message"     # commit
    hug bpush              # push (auto -u tracking on first push)

That's it. Four commands cover 80 % of day-to-day work.

`hug bpush` is the right way to push: it auto-sets the upstream on
first push, supports `--force-with-lease` (safe force-push), and never
needs you to type the remote/branch by hand. Plain `git push` and
`hug push` are both discouraged in favor of `hug bpush`.

### 3. Look at history

    hug ll -10             # last 10 commits, oneline
    hug sh HEAD            # details on the last commit
    hug shp HEAD           # last commit + patch
    hug ll main..HEAD      # commits on this branch not yet on main

### 4. When something goes wrong

    hug w discard <file>   # revert one file's unstaged changes
    hug h back             # move HEAD back one, keep staged changes
    hug h undo             # move HEAD back one, unstage too
    hug h rollback         # undo last commit, preserve local work

Each of these confirms before doing anything destructive. Read the
prompt; type `delete` (or whatever it asks) to proceed.

## The shorter-is-safer principle

Two examples that anchor the whole CLI:

**Staging:**

    hug a <files>          # stage specific files (precise)
    hug a                  # stage all tracked changes (medium)
    hug aa                 # stage everything, including untracked (broad)

The two-letter form is broader and rarer. Reach for it deliberately.

**Discarding work:**

    hug w discard <file>   # revert one file (smallest blast radius)
    hug w wipe             # wipe all unstaged changes (full reset)
    hug w purge            # wipe + remove untracked files (nuclear)

Same shape: more letters → more power. Both `wipe` and `purge` confirm
before acting; neither is a one-keystroke accident waiting to happen.

## Discover more

    hug help               # category overview
    hug help @             # all categories with summaries
    hug help @branching    # learn one category's commands
    hug help /undo         # fuzzy keyword search
    hug help '!save my work in progress'  # natural-language search
    hug help :             # more articles like this one

For full help on any command:

    hug help <command>     # e.g. hug help bpush

## Next steps

- `hug help :cookbook` — recipes for common scenarios *(coming soon)*
- `hug help :undoing-changes` — the full undo toolkit *(coming soon)*
- `hug help :branching-101` — branches and merges *(coming soon)*

For now: pick a real task you'd normally do with git, and try the
hug version. `hug help <command>` is one keystroke away if you get
stuck.
```

**Step 2: Run the live command to confirm it renders**

```bash
hug help :
hug help :hug-101
hug help :hug-101 | head -5         # pipe-safe: raw markdown
```

Expected: listing shows `:hug-101`; rendered article shows H1 and body;
piped output is raw markdown starting with `+++` stripped, `# Hug 101`
visible.

**Step 3: Run python tests against the real article**

The python integrity tests should still pass — `parse_article` succeeds
on `hug-101.md` because frontmatter is well-formed.

```bash
make test-lib-py TEST_FILTER=test_articles_loader
```

**Step 4: Commit**

```bash
hug a git-config/lib/python/articles/hug-101.md
hug c -m "feat: add :hug-101 article (mid-form CLI quickstart)"
```

---

### Task 9: BATS end-to-end coverage

**Files:**
- Create: `tests/integration/test_help_articles.bats`

**Step 1: Write the BATS file**

```bash
#!/usr/bin/env bats
# End-to-end tests for `hug help :` article system.

load ../test_helper

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

@test "hug help : lists hug-101 article" {
  run hug help :
  assert_success
  # Slug + summary land on stdout (combined output).
  assert_output --partial ":hug-101"
  assert_output --partial "Quickstart"
}

@test "hug help : header lands on stderr (stdout-only is pipe-safe)" {
  # Capturing only stdout: header rule should NOT appear there.
  run bash -c 'hug help : 2>/dev/null'
  assert_success
  refute_output --partial "── Articles"
  # But slug lines still come through stdout.
  assert_output --partial ":hug-101"
}

@test "hug help :hug-101 renders the article" {
  run hug help :hug-101
  assert_success
  # Either rendered (gum) or raw markdown — both contain the heading text.
  assert_output --partial "Hug 101"
  assert_output --partial "five-minute path"
}

@test "hug help :hug-101 is pipe-safe (raw markdown when not TTY)" {
  run bash -c "hug help :hug-101 | grep -E '^# ' | head -1"
  assert_success
  assert_output --partial "# Hug 101"
}

@test "hug help :unknown-slug exits 1 and suggests" {
  run hug help :hug-tst
  assert_failure
  assert_output --partial "no article named"
  assert_output --partial ":hug-101"
}

@test "hug help :totallyunrelatedquery exits 1 with no suggestions" {
  run hug help :zzzzzzzzzz
  assert_failure
  assert_output --partial "no article named"
  refute_output --partial "Did you mean"
}

@test "hug help mentions : in top-level tips" {
  run hug help
  assert_success
  assert_output --partial "hug help :"
}
```

**Step 2: Run the BATS file**

```bash
make test-integration TEST_FILE=test_help_articles.bats TEST_SHOW_ALL_RESULTS=1
```

Expected: all 7 tests pass.

**Step 3: Run the full BATS suite to catch regressions**

```bash
make test-bash
```

Expected: green. Pre-existing help tests
(`tests/integration/test_help_topic_search.bats`,
`tests/unit/test_gateway_help_forwarding.bats`) stay passing.

**Step 4: Commit**

```bash
hug a tests/integration/test_help_articles.bats
hug c -m "test: BATS end-to-end coverage for hug help : sigil"
```

---

### Task 10: Format, lint, and full test suite

**Files:** none (verification only)

**Step 1: Run sanitize**

```bash
make sanitize
```

Expected: ruff/black/mypy/shellcheck all green. Per project conventions
this is the only way to format/lint/typecheck.

**Step 2: Run the full test suite**

```bash
make test
```

Expected: every BATS + pytest test passes.

**Step 3: If anything fails**

- Lint failures: read the diff `make sanitize` produced, accept the
  reformat, or fix the noted ruff codes.
- Test failures: read the failure output, fix the source, repeat
  the relevant `make test-*` until green, then re-run `make test`.

**Step 4: Final commit (only if `make sanitize` produced changes)**

```bash
hug s
# If anything was modified by sanitize:
hug a <modified files>
hug c -m "style: apply sanitize pass for help articles feature"
```

---

## Done criteria

- ✅ `hug help :` lists `:hug-101` with summary, exit 0
- ✅ `hug help :hug-101` renders the article (gum-formatted on TTY, raw markdown when piped)
- ✅ `hug help :unknown` returns exit 1 with fuzzy suggestions
- ✅ `hug help` top-level tips mention the `:` sigil
- ✅ `make test` green
- ✅ `make sanitize` green
- ✅ Stdout/stderr discipline preserved — `hug help : 2>/dev/null` shows only data lines

## Out of scope (deferred)

- Mercurial parity (`hg-config/`) — follow-up plan.
- Additional articles (`:cookbook`, `:undoing-changes`, etc.) — content can land independently as soon as the system ships.
- Search integration — `hug help /word` does not surface articles in v1.

## Files touched (summary)

**Create:**
- `git-config/lib/python/articles_loader.py`
- `git-config/lib/python/articles/hug-101.md`
- `git-config/lib/python/tests/test_articles_loader.py`
- `git-config/lib/python/tests/fixtures/articles/hug-test.md`
- `git-config/lib/python/tests/fixtures/articles/zzz-second.md`
- `git-config/lib/python/tests/fixtures/articles_bad/no_fences.md`
- `git-config/lib/python/tests/fixtures/articles_bad/missing_title.md`
- `git-config/lib/python/tests/fixtures/articles_bad/long_summary.md`
- `tests/integration/test_help_articles.bats`

**Modify:**
- `git-config/bin/git-hughelp` (add `:*)` case + `:` tip line)
- `git-config/lib/python/help_search.py` (add `:` mode + `--articles-dir` arg + dispatch branch)
- `git-config/lib/python/tests/test_help_search.py` (extend with `TestArticleMode`)
