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
from command_meta import load_commands
from help_search import collect_metadata, search_intent, search_keyword

# Path math: __file__ is .../<repo>/git-config/lib/python/tests/<this>.
# parents[3] is .../git-config; parents[4] is the repo root.
REPO = Path(__file__).resolve().parents[4]
BIN = REPO / "git-config" / "bin"
CATS = REPO / "git-config" / "lib" / "python" / "categories"
GITCONFIG = REPO / "git-config" / ".gitconfig"


@pytest.fixture(scope="module")
def commands():
    """Real repo commands, hydrated with real category + registry metadata.

    cmd_meta threads the commands.toml registry (Task 2 merge) so corpus
    rows exercise the same index `hug help /query` and `hug help !query`
    serve in production — without it, registry-only commands (fetch,
    bpull, bs, ...) would be invisible to every assertion below.
    """
    cats = load_categories(CATS)
    cmds = collect_metadata(
        BIN,
        use_cache=False,
        cat_meta=cats,
        cmd_meta=load_commands(bin_dir=BIN, gitconfig=GITCONFIG),
    )
    return cmds


# -----------------------------------------------------------------------------
# /keyword corpus — exact / near-exact term queries
# -----------------------------------------------------------------------------


@pytest.mark.parametrize(
    "query,expected_in_top5",
    [
        # Direct keyword matches (per-command _hug_keywords)
        ("undo", ["hug h undo"]),
        ("save", ["hug w wip"]),
        ("conflict", ["hug slc"]),
        ("push", ["hug bpush"]),
        ("commit", ["hug c"]),
        ("amend", ["hug cmod"]),
        ("rollback", ["hug h rollback"]),
        ("rewind", ["hug h rewind"]),
        ("squash", ["hug h squash"]),
        # Direct name / description matches
        ("worktree", ["hug wtc"]),
        ("branch", ["hug b", "hug bc"]),
        # Registry-only commands (the reported complaint: "agents search for
        # fetch, the help system finds nothing") — these rows ARE that net.
        ("fetch", ["hug fetch", "hug tpull", "hug tpullf"]),
        ("pull", ["hug bpull", "hug bpullr", "hug pullall"]),
        ("bs", ["hug bs"]),
        # Exact-substring booster (elifarley/hug-scm#344): "merge" appears
        # verbatim in mff's summary ("Fast-forward merge or move branch
        # pointer"), yet plain WRatio scored it 60 — below the 80 desc floor —
        # because the length penalty on "Fast-forward " out-weighed the direct
        # hit, while slc's COINCIDENTAL "un**merged**" substring passed at 81.
        # A direct prose hit must never lose to a coincidental one.
        #
        # Merge family onboarding (elifarley/hug-scm#343): the aliases carry
        # "merge" as a curated keyword (95) and mff via desc= booster (90),
        # so the whole family outranks the coincidental 90-club (bpull,
        # fetch, slc, w unwip — all containing "merge" in their prose).
        ("merge", ["hug m", "hug ma", "hug mff", "hug mkeep", "hug slc"]),
        # Single-letter command discoverability: /squash must surface the
        # squash-merge alias beside the HEAD-operation classic.
        ("squash", ["hug h squash", "hug m"]),
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
        # Natural-language phrasings of the same complaint: intent mode must
        # surface the registry rows too (fetch / bpull / bpullr / bs).
        ("update my repo from the remote", ["hug fetch", "hug bpull", "hug bpullr"]),
        ("go back to the previous branch", ["hug bs"]),
        # Merge family intent (elifarley/hug-scm#343): "combine" appears in
        # no command description — the curated "combine" keyword on m/mkeep
        # is what lets this phrasing find the merge family at all.
        ("merge my feature branch", ["hug m", "hug mkeep"]),
        ("combine my feature branch", ["hug m", "hug mkeep"]),
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
