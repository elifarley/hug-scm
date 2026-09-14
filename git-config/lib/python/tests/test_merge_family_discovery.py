"""Discovery pins for the merge family onboarding (elifarley/hug-scm#343).

The shared corpus (test_quality_corpus.py) pins /merge and !combine — but
its "merge" row passes with mff's keywords line BROKEN: mff would still
clear the floor via the desc= substring rescue (its summary contains
"merge" verbatim). These rows pin the git-mff `--search-meta` keyword
VALUES directly, choosing queries whose trigrams appear in NO other field:

- "ff-only"  → only mff's keywords ("ff-only"); no description, name, or
  category_desc contains it. If the printf line breaks, this finds nothing.
- "no-ff"    → only mkeep's curated keyword.
- "fast-forward" / "abort" → the whole family stays discoverable by the
  words users actually type.

Runs against the real repo's bin/ + categories/ + commands.toml, same
fixture shape as the quality corpus.
"""

from pathlib import Path

import pytest

from category_meta import load_categories
from command_meta import load_commands
from help_search import collect_metadata, search_keyword

# __file__ is .../<repo>/git-config/lib/python/tests/<this>; parents[3] is
# git-config (tests → python → lib → git-config).
GC = Path(__file__).resolve().parents[3]
CATS = GC / "lib" / "python" / "categories"


@pytest.fixture(scope="module")
def commands():
    """Real repo index: scripts (incl. git-mff's live --search-meta output)
    merged with the commands.toml registry — what `hug help /query` serves."""
    cats = load_categories(CATS)
    return collect_metadata(
        GC / "bin",
        use_cache=False,
        cat_meta=cats,
        cmd_meta=load_commands(bin_dir=GC / "bin", gitconfig=GC / ".gitconfig"),
    )


@pytest.mark.parametrize(
    "query,expected_in_top5",
    [
        # git-mff's _hug_keywords VALUE "ff-only": unreachable through any
        # other field — the strongest pin that the keywords line parses.
        ("ff-only", ["hug mff"]),
        # mkeep's curated "no-ff": same single-source property.
        ("no-ff", ["hug mkeep"]),
        # mff's and mkeep's shared "fast-forward" value (mff via keywords,
        # mkeep via keywords + description).
        ("fast-forward", ["hug mff", "hug mkeep"]),
        # ma's "abort" keyword: the abort flow must surface the family's
        # dedicated abort alias, not only the rebase aborts (rb/rbc-*).
        ("abort", ["hug ma"]),
    ],
)
def test_merge_family_keyword_corpus(commands, query, expected_in_top5):
    """Top-5 for each merge-family query must include the listed commands."""
    results = [c.command for c in search_keyword(commands, query, all_results=True)][:5]
    for cmd in expected_in_top5:
        assert cmd in results, f"/{query}: expected {cmd!r} in top-5, got {results}"
