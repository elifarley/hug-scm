"""Edge coverage for the desc= exact-substring booster (elifarley/hug-scm#344).

Fills the audit gaps the branch's own tests (TestKeywordSpecs) left open:

- the `.strip()` branch: a whitespace-PADDED query must still hit (a quoted
  `hug help "/merge "` reaches scorers untrimmed), while a whitespace-only
  query scores 0 — run_search's blank-query guard returns first, but the
  scorer must never claim a hit on stripped-empty input either;
- pure-substring semantics: the scorer is `q in target.lower()`, so regex
  metachars in the query are LITERAL, never interpreted;
- the desc= precedence contract: the booster scales to exactly the floor
  (100 × 0.80 = 80) and sits AFTER the fuzzy desc spec, so it annotates a
  match ONLY when it is the sole carrier — a description fuzzy desc already
  passes keeps its fuzzy score and label (the measured /ship red-team
  finding: a stronger constant flattened passing matches into one
  alphabetical tie band and displaced regulars from /stage and /branch).

Path invariance: the precedence assertions hold identically with and
without thefuzz — fuzzy desc scores ≥ the booster's flat 80 whenever the
fuzzy spec passes at all (its 0.90 weight caps at 90; its floor is 80),
and the fallback `_fb_substring` path scores fuzzy desc 100 × 0.90 = 90
on the same shapes. Verified under `uv run --extra search` (thefuzz) and
bare python3 (fallback).
"""

from help_search import (
    KEYWORD_SPECS,
    CommandInfo,
    _exact_substring,
    run_search,
    search_keyword,
)


class TestExactSubstringEdges:
    """_exact_substring's own branches beyond hit/miss/short-gate."""

    def test_whitespace_padded_query_still_hits(self):
        # The .strip() branch: the CLI hands the query through verbatim, so a
        # quoted trailing space must not defeat a deliberate prose hit.
        assert _exact_substring("  merge  ", "Fast-forward merge or move branch pointer") == 100

    def test_whitespace_only_query_scores_zero(self):
        # Stripped to "" → len 0 < MIN_EXACT_QUERY_LEN. run_search never
        # reaches the scorer for blank queries (`not query.strip()` guard),
        # but the scorer is also import-safe for direct callers.
        assert _exact_substring("   ", "merge target") == 0

    def test_query_regex_metachars_are_literal(self):
        # `in` is a substring test, not a pattern search: "m.rge" must NOT
        # match "merge", and must match a literal "m.rge". Pins that the
        # booster can never be turned into an accidental regex engine.
        desc = "Fast-forward merge or move branch pointer"
        assert _exact_substring("m.rge", desc) == 0
        assert _exact_substring("m.rge", "release m.rge target") == 100


class TestBoosterPrecedence:
    """The booster annotates ONLY matches nothing stronger already carries.

    Strictly-additive semantics: a passing fuzzy desc match keeps its own
    (higher) score and label; desc= lands at exactly 80 and wins only when
    fuzzy desc failed the floor. Spec order (desc before desc=) plus
    best-spec-wins makes this hold on thefuzz and fallback paths alike.
    """

    def test_coincidental_substring_keeps_fuzzy_score_and_label(self):
        # The slc shape from the #344 design note: "merge" occurs inside
        # "unmerged". Fuzzy desc passes at 81 (WRatio 90 × 0.90), so the
        # flat 80 must NOT take over — score AND label stay fuzzy.
        slc = CommandInfo(
            command="hug slc",
            description="Show only conflicted (unmerged) files.",
            categories=["status"],
        )
        score, _cmd, spec = run_search("merge", [slc], KEYWORD_SPECS)[0]
        assert (score, spec.label) == (81, "desc")

    def test_exact_equality_description_keeps_fuzzy_max(self):
        # Description equal to the query: fuzzy desc maxes out (100 × 0.90)
        # and outranks the booster's flat 80 — exact substring never
        # inflates what fuzzy scoring already resolved.
        cmd = CommandInfo(command="hug x", description="merge", categories=[])
        score, _cmd, spec = run_search("merge", [cmd], KEYWORD_SPECS)[0]
        assert (score, spec.label) == (90, "desc")

    def test_padded_query_rescued_via_booster_end_to_end(self):
        # Through the full search_keyword pipeline: fuzzy scorers see the
        # raw padded string and fail (WRatio 60 → 54 < 80); the stripping
        # booster is the sole carrier — floor score, desc= label.
        mff = CommandInfo(
            command="hug mff",
            description="Fast-forward merge or move branch pointer",
            categories=["merge"],
        )
        assert [r.command for r in search_keyword([mff], " merge ")] == ["hug mff"]
        score, _cmd, spec = run_search(" merge ", [mff], KEYWORD_SPECS)[0]
        assert (score, spec.label) == (80, "desc=")
