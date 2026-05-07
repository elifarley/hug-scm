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
    # Normalise once: accept str-typed callers gracefully so that path.stem
    # and every downstream attribute access works without repeated Path() wraps.
    path = Path(path)
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()

    # Strict sentinel match (no .strip()): fences are tokens, not prose.
    # Whitespace tolerance would break the "MUST be exactly +++" contract
    # stated in the docstring and yield confusing error messages on typos.
    if not lines or lines[0] != _FENCE:
        raise ValueError(f"{path}: missing opening +++ frontmatter fence")

    end = None
    for i in range(1, len(lines)):
        if lines[i] == _FENCE:
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
        raise ValueError(f"{path}: 'summary' exceeds {SUMMARY_MAX} chars (got {len(summary)})")

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


def load_articles(directory: str | Path) -> list[ArticleMeta]:
    """Return every <slug>.md under `directory`, sorted by (order, slug).

    Missing or empty directory returns []. Articles are an opt-in CLI
    feature; absence is not an error. Parse errors propagate — strict
    validation per the categories pattern (loud drift, not silent).

    The pre-sort on `glob` results is platform safety: filesystems may
    return directory entries in arbitrary order. The final `(order, slug)`
    sort is what determines the user-facing list order; the pre-sort
    just ensures we visit files in a deterministic sequence (matters
    only if a future refactor decouples slug from path.stem — today they
    are identical, so the final sort would suffice on its own).
    """
    base = Path(directory)
    if not base.is_dir():
        return []
    metas = [parse_article(p) for p in sorted(base.glob("*.md"))]
    metas.sort(key=lambda m: (m.order, m.slug))
    return metas


# ---------------------------------------------------------------------------
# Article lookup: exact slug match + fuzzy fallback
# ---------------------------------------------------------------------------

# Fuzzy threshold: matches MIN_CATEGORY_SCORE in help_search.py.
# Slugs are short, kebab-case, low-noise — strict ratio() with floor 60
# accepts genuine typos ("hug-tst" → "hug-test") while rejecting
# unrelated queries ("zzzzz"). Lowering this would surface noise;
# raising it would miss obvious 1-char typos.
_MIN_FUZZY_SCORE = 60
_MAX_SUGGESTIONS = 3


@dataclass(frozen=True)
class FindResult:
    """Result of looking up an article by slug.

    `found` is the exact-match ArticleMeta or None.
    `suggestions` is fuzzy-matched ArticleMeta when found is None, capped
    to _MAX_SUGGESTIONS. Stored as a tuple so frozen=True actually protects
    against accidental mutation by callers (a list field would be
    mutable-through despite frozen=True).
    """

    found: ArticleMeta | None
    suggestions: tuple[ArticleMeta, ...]


def _ratio(query: str, target: str) -> int:
    """Strict full-string fuzzy ratio (0–100).

    Uses `thefuzz.fuzz.ratio` when available (project's `[search]` extra).
    The substring-only fallback handles exact equality and "query is a
    prefix/substring of target" cases, but does NOT recognise edit-distance
    typos — a one-char delete like "hug-tst" vs "hug-test" returns 0 in the
    fallback path. In practice this means typo-suggestions for `hug help :`
    require the search extra; without it, only exact and substring slug
    matches surface in the suggestion list. Acceptable graceful degradation:
    the user still gets the "no article named X" error, just without the
    "did you mean" hint.

    WHY lazy import: defers thefuzz ImportError to call-time (not module
    import-time), so test failures from missing extras are easy to
    distinguish from genuine code errors. Mirrors help_search.py.
    """
    try:
        from thefuzz import fuzz  # type: ignore[import-not-found]

        return fuzz.ratio(query.lower(), target.lower())
    except ImportError:  # pragma: no cover
        return 100 if query.lower() == target.lower() else (
            80 if query.lower() in target.lower() else 0
        )


def find_article(articles: list[ArticleMeta], query: str) -> FindResult:
    """Look up by slug; on miss, return up to _MAX_SUGGESTIONS fuzzy hits.

    Scoring fields: slug (kebab-case, low-noise) and title (free-form,
    may contain spaces). Each article gets the better of its two field
    scores; suggestions are sorted by score descending. The dual-field
    approach lets queries like `hug-test` (slug-shaped) and `hug test`
    (title-shaped) both land near the right article without forcing
    users to know the canonical kebab-case slug.

    `query.strip()` is applied defensively so callers passing
    whitespace-padded queries (e.g. from sloppy CLI parsing) still hit
    exact matches.
    """
    query = query.strip()  # defensive: tolerate accidental whitespace
    for a in articles:
        if a.slug == query:
            return FindResult(found=a, suggestions=())

    scored: list[tuple[int, ArticleMeta]] = []
    for a in articles:
        score = max(_ratio(query, a.slug), _ratio(query, a.title))
        if score >= _MIN_FUZZY_SCORE:
            scored.append((score, a))
    scored.sort(key=lambda x: x[0], reverse=True)
    return FindResult(
        found=None,
        suggestions=tuple(a for _, a in scored[:_MAX_SUGGESTIONS]),
    )
