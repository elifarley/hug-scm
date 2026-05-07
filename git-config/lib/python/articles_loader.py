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
