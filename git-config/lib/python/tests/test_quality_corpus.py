"""Quality regression corpus for help_search.

Pinned golden queries with expected top-N results, run against the real
repo's bin/ scripts and categories/ manifests. The corpus is the contract:
when threshold/weight tuning is needed, contributors run the corpus,
adjust KEYWORD_SPECS / INTENT_SPECS, and ensure all assertions still pass.

The corpus also doubles as a regression net for the F3 architectural
guarantee — destructive commands (wipdel, w-discard, h-rewind) MUST NOT
surface for queries about saving / undoing work.

Note on top-N: assertions check membership in top-N rather than exact
rank because:
- WRatio scores are sensitive to small description edits
- Multiple commands may legitimately match a query at similar scores
- Exact-rank assertions would create constant friction for content edits

The relaxed bar still catches real regressions: if a tuning change drops
"hug bpush" out of top-5 for "push", that's a real quality problem.
"""

from pathlib import Path

import pytest

from category_meta import load_categories
from help_search import collect_metadata, search_intent, search_keyword

# Path math: __file__ is .../<repo>/git-config/lib/python/tests/<this>.
# parents[3] is .../git-config; parents[4] is the repo root.
REPO = Path(__file__).resolve().parents[4]
BIN = REPO / "git-config" / "bin"
CATS = REPO / "git-config" / "lib" / "python" / "categories"


@pytest.fixture(scope="module")
def commands():
    """Real repo commands, hydrated with real category metadata."""
    cats = load_categories(CATS)
    return collect_metadata(BIN, use_cache=False, cat_meta=cats)


# -----------------------------------------------------------------------------
# /keyword corpus — exact / near-exact term queries
# -----------------------------------------------------------------------------


@pytest.mark.parametrize(
    "query,expected_in_top5",
    [
        # Direct keyword matches (per-command _hug_keywords)
        ("undo", ["hug h undo"]),
        ("save", ["hug w wip"]),
        ("push", ["hug bpush"]),
        ("commit", ["hug c"]),
        ("amend", ["hug cmod"]),
        ("rollback", ["hug h rollback"]),
        ("rewind", ["hug h rewind"]),
        ("squash", ["hug h squash"]),
        # Direct name / description matches
        ("worktree", ["hug wtc"]),
        ("branch", ["hug b", "hug bc"]),
    ],
)
def test_keyword_corpus(commands, query, expected_in_top5):
    """Top-5 results for each query must include the listed commands."""
    results = [c.command for c in search_keyword(commands, query, all_results=True)][:5]
    for cmd in expected_in_top5:
        assert cmd in results, f"/{query}: expected {cmd!r} in top-5, got {results}"


# -----------------------------------------------------------------------------
# !intent corpus — natural-language phrase queries
# -----------------------------------------------------------------------------


@pytest.mark.parametrize(
    "query,expected_in_top5",
    [
        # Token-aware keyword discovery: "save" is a curated keyword on hug w wip.
        ("save my work in progress", ["hug w wip"]),
        # "push to remote" — direct match via keyword + description.
        ("push to remote", ["hug bpush"]),
    ],
)
def test_intent_corpus(commands, query, expected_in_top5):
    """!intent token-aware mode finds curated-keyword commands via phrases."""
    results = [c.command for c in search_intent(commands, query, all_results=True)][:5]
    for cmd in expected_in_top5:
        assert cmd in results, f"!{query!r}: expected {cmd!r} in top-5, got {results}"


# -----------------------------------------------------------------------------
# F3 destructive-command regression — both modes
# -----------------------------------------------------------------------------


@pytest.mark.parametrize(
    "query,must_not_appear",
    [
        # `save` keyword should ONLY surface hug w wip — never destructive
        # siblings that would discard / delete WIP.
        ("save", ["hug w wipdel", "hug w discard", "hug w purge"]),
        # `stash` is a parking-flavour keyword; same precision required.
        ("stash", ["hug w wipdel", "hug w purge"]),
        # `undo` should find h-undo / h-rollback, not destructive purge.
        ("undo", ["hug w wipdel", "hug w purge", "hug h rewind"]),
    ],
)
def test_keyword_destructive_isolation(commands, query, must_not_appear):
    """Per-command keywords prevent destructive-sibling pollution.

    F3 from /autoplan dual-voice review: a category-level `save` keyword
    on `parking` would propagate to every parking command, including
    destructive ones like `wipdel`. Per-command keywords make each match
    unit precise. If this regresses (e.g., someone moves keywords back
    to the category layer), this test fires.
    """
    results = [c.command for c in search_keyword(commands, query, all_results=True)]
    for cmd in must_not_appear:
        assert cmd not in results, (
            f"/{query}: destructive command {cmd!r} surfaced — F3 regressed. Got: {results}"
        )


@pytest.mark.parametrize(
    "query,must_not_appear",
    [
        # Same protection on the !intent path.
        ("save my work", ["hug w wipdel", "hug w discard", "hug w purge"]),
        ("undo last change", ["hug w wipdel", "hug h rewind"]),
    ],
)
def test_intent_destructive_isolation(commands, query, must_not_appear):
    """!intent's token-aware mode also respects per-command keyword precision."""
    results = [c.command for c in search_intent(commands, query, all_results=True)]
    for cmd in must_not_appear:
        assert cmd not in results, (
            f"!{query!r}: destructive command {cmd!r} surfaced — F3 regressed. Got: {results}"
        )
