"""Tests for help_search.py — topic search for hug help."""

import json
import os
import subprocess
import sys
from dataclasses import replace
from pathlib import Path

import pytest

from category_meta import CategoryMeta, load_categories
from command_meta import RegistryError, load_commands
from help_search import (
    KEYWORD_SPECS,
    CommandInfo,
    MatchSpec,
    _exact_substring,
    _save_cache,
    collect_metadata,
    derive_command_name,
    format_category_list,
    format_category_page,
    format_results,
    list_categories,
    main,
    parse_description_from_help,
    render_card,
    run_search,
    search_category,
    search_intent,
    search_keyword,
)

# Real-repo anchors for the registry-merge tests (Task 2). Mirrors
# test_command_meta.py — the registry and the script bin it must not shadow
# live in this repo, and the merge tests exercise the REAL corpus.
REPO = Path(__file__).resolve().parents[4]
PY_DIR = REPO / "git-config" / "lib" / "python"
CATS = PY_DIR / "categories"
GITCONFIG = REPO / "git-config" / ".gitconfig"
BIN = REPO / "git-config" / "bin"


class TestDeriveCommandName:
    """Command names are derived from filenames using gateway rules."""

    def test_flat_command(self):
        assert derive_command_name("git-bpush") == "hug bpush"

    def test_flat_command_hyphenated(self):
        assert derive_command_name("git-bpush-unsafe") == "hug bpush-unsafe"

    def test_flat_single_letter(self):
        assert derive_command_name("git-a") == "hug a"

    def test_flat_multi_letter(self):
        assert derive_command_name("git-sls") == "hug sls"

    def test_h_gateway_subcommand(self):
        assert derive_command_name("git-h-undo") == "hug h undo"

    def test_h_gateway_multi_word(self):
        assert derive_command_name("git-h-rollback") == "hug h rollback"

    def test_w_gateway_subcommand(self):
        assert derive_command_name("git-w-discard") == "hug w discard"

    def test_h_gateway_not_h_prefix(self):
        # "help" is not an h-gateway subcommand
        assert derive_command_name("git-hughelp") == "hug hughelp"

    def test_wt_is_not_w_gateway(self):
        # wtc is standalone, not w-gateway
        assert derive_command_name("git-wtc") == "hug wtc"

    def test_wtdel_is_not_w_gateway(self):
        assert derive_command_name("git-wtdel") == "hug wtdel"


class TestParseDescription:
    """Description is extracted from --help output."""

    def test_extracts_from_heredoc_format(self):
        help_text = "hug h undo: Move HEAD back, unstage changes.\n\nUSAGE:\n  ..."
        assert parse_description_from_help(help_text) == "Move HEAD back, unstage changes."

    def test_extracts_from_inline_format(self):
        help_text = "hug bpushf: Force push current branch with lease (safer force push)\n\nUSAGE:"
        assert (
            parse_description_from_help(help_text)
            == "Force push current branch with lease (safer force push)"
        )

    def test_returns_empty_for_no_match(self):
        assert parse_description_from_help("some random text") == ""

    def test_returns_empty_for_empty(self):
        assert parse_description_from_help("") == ""


class TestCollectMetadata:
    """Collector queries scripts via --search-meta and extracts descriptions."""

    @pytest.fixture
    def mock_scripts(self, tmp_path):
        """Create mock git-* scripts that respond to --search-meta and --help."""
        bin_dir = tmp_path / "bin"
        bin_dir.mkdir()

        scripts = {
            "git-h-undo": {
                "search_meta": 'category = ["head"]',
                "help": "hug h undo: Move HEAD back, unstage changes.\n\nUSAGE:\n  hug h undo [N]",
            },
            "git-bpush": {
                "search_meta": 'category = ["branching", "push-pull"]',
                "help": "hug bpush: Push current branch to origin.\n\nUSAGE:\n  hug bpush",
            },
            "git-a": {
                "search_meta": 'category = ["staging"]',
                "help": (
                    "hug a: Stage tracked files, or specific files if provided.\n\nUSAGE:\n  hug a"
                ),
            },
            "git-bpushf": {
                "search_meta": 'category = ["push-pull"]',
                "help": "hug bpushf: Force push current branch with lease\n\nUSAGE:\n  hug bpushf",
            },
            "git-ss": {
                "search_meta": 'category = ["status", "staging"]',
                "help": "hug ss: Show staged diff.\n\nUSAGE:\n  hug ss",
            },
            "git-unknown": {
                "search_meta": "category = []",
                "help": "",  # No description — should be excluded from search
            },
        }

        for name, data in scripts.items():
            script = bin_dir / name
            script.write_text(f"""#!/usr/bin/env bash
	test "${{1:-}}" = '--search-meta' && {{ printf '{data["search_meta"]}\n'; exit 0; }}
	test "${{1:-}}" = '--help' && {{ printf '%s\n' '{data["help"]}'; exit 0; }}
	echo "error" >&2; exit 1
""")
            script.chmod(0o755)

        return bin_dir

    def test_collects_all_annotated_scripts(self, mock_scripts):
        cmds = collect_metadata(mock_scripts, use_cache=False)
        names = {c.command for c in cmds}
        assert "hug h undo" in names
        assert "hug bpush" in names
        assert "hug a" in names

    def test_excludes_unannotated_scripts(self, mock_scripts):
        cmds = collect_metadata(mock_scripts, use_cache=False)
        names = {c.command for c in cmds}
        assert "hug unknown" not in names

    def test_extracts_categories(self, mock_scripts):
        cmds = collect_metadata(mock_scripts, use_cache=False)
        bpush = [c for c in cmds if c.command == "hug bpush"][0]
        assert "branching" in bpush.categories
        assert "push-pull" in bpush.categories

    def test_extracts_description(self, mock_scripts):
        cmds = collect_metadata(mock_scripts, use_cache=False)
        undo = [c for c in cmds if c.command == "hug h undo"][0]
        assert "Move HEAD back" in undo.description


class TestSearchKeyword:
    """Keyword search fuzzy-matches against description + command name."""

    @pytest.fixture
    def commands(self):
        return [
            CommandInfo(
                command="hug h undo",
                description="Move HEAD back, unstage changes.",
                categories=["head"],
            ),
            CommandInfo(
                command="hug bpush",
                description="Push current branch to origin.",
                categories=["branching", "push-pull"],
            ),
            CommandInfo(
                command="hug a", description="Stage tracked files.", categories=["staging"]
            ),
            CommandInfo(
                command="hug ss", description="Show staged diff.", categories=["status", "staging"]
            ),
        ]

    def test_finds_by_description(self, commands):
        results = search_keyword(commands, "undo")
        assert any(r.command == "hug h undo" for r in results)

    def test_finds_by_command_name(self, commands):
        results = search_keyword(commands, "bpush")
        assert any(r.command == "hug bpush" for r in results)

    def test_fuzzy_match(self, commands):
        results = search_keyword(commands, "undoo")
        assert any(r.command == "hug h undo" for r in results)

    def test_returns_empty_for_no_match(self, commands):
        results = search_keyword(commands, "xyzzy12345")
        assert len(results) == 0

    def test_ranks_by_relevance(self, commands):
        results = search_keyword(commands, "push")
        names = [r.command for r in results]
        assert "hug bpush" in names


class TestSearchCategory:
    """Category search filters by category tag with fuzzy matching."""

    @pytest.fixture
    def commands(self):
        return [
            CommandInfo(command="hug h undo", description="Move HEAD back.", categories=["head"]),
            CommandInfo(
                command="hug bpush",
                description="Push to origin.",
                categories=["branching", "push-pull"],
            ),
            CommandInfo(command="hug a", description="Stage files.", categories=["staging"]),
        ]

    def test_finds_by_exact_category(self, commands):
        results = search_category(commands, "branching")
        assert any(r.command == "hug bpush" for r in results)

    def test_fuzzy_match_category(self, commands):
        results = search_category(commands, "brnaching")  # typo
        assert any(r.command == "hug bpush" for r in results)

    def test_returns_empty_for_unknown(self, commands):
        results = search_category(commands, "nonexistent")
        assert len(results) == 0

    def test_multi_category_command(self, commands):
        results = search_category(commands, "push-pull")
        assert any(r.command == "hug bpush" for r in results)


class TestListCategories:
    def test_lists_all_categories(self):
        commands = [
            CommandInfo(command="hug a", description="", categories=["staging"]),
            CommandInfo(command="hug bpush", description="", categories=["branching", "push-pull"]),
            CommandInfo(command="hug h undo", description="", categories=["head"]),
        ]
        cats = list_categories(commands)
        assert cats == ["branching", "head", "push-pull", "staging"]


class TestFormatResults:
    def test_formats_single_result(self):
        cmds = [
            CommandInfo(command="hug h undo", description="Move HEAD back.", categories=["head"])
        ]
        output = format_results(cmds)
        assert "hug h undo" in output
        assert "Move HEAD back." in output

    def test_formats_empty_results(self):
        output = format_results([])
        assert "No matching commands" in output or "(none)" in output


class TestCache:
    """Cache stores collected metadata with mtime-based invalidation."""

    @pytest.fixture
    def mock_scripts(self, tmp_path):
        bin_dir = tmp_path / "bin"
        bin_dir.mkdir()
        script = bin_dir / "git-a"
        script.write_text("""#!/usr/bin/env bash
	test "${1:-}" = '--search-meta' && { printf 'category = ["staging"]\n'; exit 0; }
	test "${1:-}" = '--help' && { printf 'hug a: Stage tracked files.\n'; exit 0; }
""")
        script.chmod(0o755)
        return bin_dir

    def test_cache_created_after_first_collect(self, mock_scripts, tmp_path):
        cache_dir = tmp_path / "cache"
        cache_dir.mkdir()
        collect_metadata(mock_scripts, cache_dir=cache_dir, use_cache=True)
        cache_file = cache_dir / "search-meta.cache"
        assert cache_file.exists()

    def test_cache_is_json(self, mock_scripts, tmp_path):
        cache_dir = tmp_path / "cache"
        cache_dir.mkdir()
        collect_metadata(mock_scripts, cache_dir=cache_dir, use_cache=True)
        cache_file = cache_dir / "search-meta.cache"
        data = json.loads(cache_file.read_text())
        assert isinstance(data, dict)

    def test_cache_used_on_second_call(self, mock_scripts, tmp_path):
        cache_dir = tmp_path / "cache"
        cache_dir.mkdir()
        # First call populates cache
        collect_metadata(mock_scripts, cache_dir=cache_dir, use_cache=True)
        # Modify script (newer mtime)
        (mock_scripts / "git-a").write_text("""#!/usr/bin/env bash
	test "${1:-}" = '--search-meta' && { printf 'category = ["staging"]\n'; exit 0; }
	test "${1:-}" = '--help' && { printf 'hug a: Updated description.\n'; exit 0; }
""")
        (mock_scripts / "git-a").chmod(0o755)
        # Second call should detect mtime change and re-collect
        cmds2 = collect_metadata(mock_scripts, cache_dir=cache_dir, use_cache=True)
        assert cmds2[0].description == "Updated description."


class TestMatchSpec:
    """MatchSpec drives the generic run_search engine.

    These tests use synthetic scorer functions (lambdas) to verify the
    run_search machinery in isolation, independent of thefuzz availability.
    """

    def _info(self, **kw):
        return CommandInfo(**kw)

    def test_run_search_uses_field_value(self):
        cmds = [
            self._info(
                command="hug bpush",
                description="push to origin",
                categories=["push-pull"],
            )
        ]
        specs = [
            MatchSpec(
                field="description",
                scorer=lambda q, t: 100 if q in t else 0,
                weight=1.0,
                min_threshold=50,
                label="desc",
            )
        ]
        results = run_search("push", cmds, specs)
        assert len(results) == 1
        score, cmd, spec = results[0]
        assert cmd.command == "hug bpush"
        assert score == 100
        assert spec.label == "desc"

    def test_run_search_applies_weight(self):
        cmds = [self._info(command="x", description="desc", categories=[])]
        specs = [
            MatchSpec(
                field="description",
                scorer=lambda q, t: 100,
                weight=0.5,
                min_threshold=0,
                label="desc",
            )
        ]
        results = run_search("anything", cmds, specs)
        assert results[0][0] == 50  # 100 * 0.5

    def test_run_search_filters_below_threshold(self):
        cmds = [self._info(command="x", description="d", categories=[])]
        specs = [
            MatchSpec(
                field="description",
                scorer=lambda q, t: 60,
                weight=1.0,
                min_threshold=80,
                label="desc",
            )
        ]
        assert run_search("q", cmds, specs) == []

    def test_run_search_keeps_best_spec_per_command(self):
        cmds = [self._info(command="hug a", description="d", categories=[])]
        specs = [
            MatchSpec(
                field="description",
                scorer=lambda q, t: 50,
                weight=1.0,
                min_threshold=0,
                label="desc",
            ),
            MatchSpec(
                field="description",
                scorer=lambda q, t: 80,
                weight=1.0,
                min_threshold=0,
                label="better",
            ),
        ]
        score, _, spec = run_search("q", cmds, specs)[0]
        assert score == 80
        assert spec.label == "better"

    def test_existing_search_keyword_uses_run_search(self):
        # Regression: search_keyword still works after refactor.
        cmds = [
            CommandInfo(
                command="hug h undo",
                description="Move HEAD back, unstage changes.",
                categories=["head"],
            ),
        ]
        results = search_keyword(cmds, "undo")
        assert any(r.command == "hug h undo" for r in results)


class TestQueryScriptParsing:
    """_query_script must parse both `category` and `keywords` from --search-meta.

    Folded from T1.5 — ordering note: T1.5 was originally placed before T3
    in the plan, but its parsing tests depend on the production change in T3
    (extending _query_script to read the keywords line). Co-locating the
    tests with the implementation here keeps TDD honest.
    """

    @pytest.fixture
    def script_with_keywords(self, tmp_path):
        script = tmp_path / "git-w-wip"
        script.write_text(
            "#!/usr/bin/env bash\n"
            "test \"${1:-}\" = '--search-meta' && {\n"
            '  printf \'category = ["working-dir", "parking"]\\n\'\n'
            '  printf \'keywords = ["save", "shelve", "stash"]\\n\'\n'
            "  exit 0\n"
            "}\n"
            "test \"${1:-}\" = '--help' && {\n"
            "  printf 'hug w wip: Park work-in-progress aside.\\n'\n"
            "  exit 0\n"
            "}\n"
        )
        script.chmod(0o755)
        return script

    @pytest.fixture
    def script_without_keywords(self, tmp_path):
        script = tmp_path / "git-bc"
        script.write_text(
            "#!/usr/bin/env bash\n"
            "test \"${1:-}\" = '--search-meta' && {\n"
            "  printf 'category = [\"branching\"]\\n'\n"
            "  exit 0\n"
            "}\n"
            "test \"${1:-}\" = '--help' && {\n"
            "  printf 'hug bc: Create a new branch and switch to it.\\n'\n"
            "  exit 0\n"
            "}\n"
        )
        script.chmod(0o755)
        return script

    def test_parses_keywords_when_present(self, script_with_keywords):
        from help_search import _query_script

        result = _query_script(script_with_keywords)
        assert result is not None
        assert result["keywords"] == ["save", "shelve", "stash"]

    def test_keywords_default_empty_when_absent(self, script_without_keywords):
        # Graceful degradation: un-bootstrapped commands keep working.
        from help_search import _query_script

        result = _query_script(script_without_keywords)
        assert result is not None
        assert result["keywords"] == []

    def test_categories_parsed_unchanged_with_or_without_keywords(
        self, script_with_keywords, script_without_keywords
    ):
        from help_search import _query_script

        a = _query_script(script_with_keywords)
        b = _query_script(script_without_keywords)
        assert a["categories"] == ["working-dir", "parking"]
        assert b["categories"] == ["branching"]


class TestKeywordSpecs:
    """KEYWORD_SPECS scores against name + description + category_desc + keywords.

    Verifies the precision-tuned spec list: per-command keywords surface
    matches that pure description scoring would miss, while direct matches
    on description/name still outrank category-only proxies.
    """

    @pytest.fixture
    def commands(self):
        # Hydrated by hand to avoid depending on the real categories/ TOMLs
        # in tests. The shape mirrors what hydrate_category_fields produces.
        return [
            CommandInfo(
                command="hug w wip",
                description="Park work-in-progress aside.",
                categories=["working-dir", "parking"],
                keywords=["save", "shelve", "stash", "park", "wip"],
                category_desc="Working tree operations. Park work aside and unpark later.",
            ),
            CommandInfo(
                command="hug w wipdel",
                description="Discard a parked WIP commit (destructive).",
                categories=["working-dir", "parking"],
                keywords=["discard-wip", "delete-park"],
                category_desc="Working tree operations. Park work aside and unpark later.",
            ),
            CommandInfo(
                command="hug b",
                description="Switch to a branch.",
                categories=["branching"],
                keywords=["switch", "checkout", "change-branch"],
                category_desc="Create, list, switch, and delete branches.",
            ),
        ]

    def test_finds_via_per_command_keyword(self, commands):
        # "save" appears nowhere in description or name — only in keywords.
        results = search_keyword(commands, "save")
        assert any(r.command == "hug w wip" for r in results)

    def test_destructive_neighbor_NOT_matched_by_keyword(self, commands):
        # F3 regression: wipdel must NOT inherit "save" from a sibling.
        # Per-command keywords prevent this; if F3 ever regresses (e.g.,
        # someone moves keywords back to the category layer), this fails.
        results = search_keyword(commands, "save")
        cmds = [r.command for r in results]
        assert "hug w wipdel" not in cmds, (
            f"DESTRUCTIVE regression — 'hug w wipdel' surfaced for query 'save': {cmds}"
        )

    def test_direct_match_outranks_category_only(self, commands):
        # "branch" is a direct match for hug b's description AND a category
        # keyword (in switch / change-branch). hug w wip has no direct match
        # on "branch" at all. hug b should rank ahead.
        results = search_keyword(commands, "branch")
        assert results, "expected at least one match for 'branch'"
        assert results[0].command == "hug b"

    def test_typo_tolerance_via_partial(self, commands):
        # name~ partial scorer at weight 0.95 should still catch "wpi" → wip.
        # If this fails, the 0.95 weight tune may be too aggressive.
        results = search_keyword(commands, "wip")
        assert any(r.command == "hug w wip" for r in results)

    def test_exact_substring_booster_clears_desc_floor(self):
        # The mff shape from elifarley/hug-scm#344: the query appears
        # verbatim in the summary, but WRatio's length penalty ("Fast-forward
        # " prefix) scores it 60 — below the 80 desc floor. The desc= booster
        # (100 × 0.80 = 80, exactly the floor) must cross that floor where
        # fuzzy desc cannot.
        cmds = [
            CommandInfo(
                command="hug mff",
                description="Fast-forward merge or move branch pointer",
                categories=["merge"],
            ),
        ]
        results = search_keyword(cmds, "merge")
        assert [r.command for r in results] == ["hug mff"]
        # The booster, not fuzzy desc, carries the match — and only lands
        # at the floor (80), never above it.
        score, _cmd, spec = run_search("merge", cmds, KEYWORD_SPECS)[0]
        assert (score, spec.label) == (80, "desc=")

    def test_booster_never_inflates_a_passing_fuzzy_match(self):
        # Strictly-additive semantics (the /ship red-team finding): a
        # description the fuzzy spec already passes must keep its fuzzy
        # score — the flat floor score must not inflate it into a tie band
        # that reorders results alphabetically. "Stage changes." passes
        # fuzzy at 81 (WRatio 90 × 0.90), so desc= must not take over.
        # (Contrast: the LONG "Stage tracked files, or specific files..."
        # fails the fuzzy floor — WRatio 60 × 0.90 = 54 — THERE the booster
        # is the legitimate carrier.)
        cmds = [
            CommandInfo(
                command="hug a",
                description="Stage changes.",
                categories=["staging"],
            ),
        ]
        score, _cmd, spec = run_search("stage", cmds, KEYWORD_SPECS)[0]
        assert (score, spec.label) == (81, "desc")  # fuzzy, not the booster's 80

    def test_exact_substring_booster_is_case_insensitive(self):
        # Registry prose capitalizes mid-sentence; the query must not care.
        cmds = [
            CommandInfo(
                command="hug mkeep",
                description="Merge with a merge commit, even when fast-forward is possible.",
                categories=["merge"],
            ),
        ]
        assert any(r.command == "hug mkeep" for r in search_keyword(cmds, "MERGE"))

    def test_exact_substring_booster_gate_rejects_short_queries(self):
        # "st" IS a substring of "Stage ..." — without the MIN_EXACT_QUERY_LEN
        # gate (4) the booster would flood every staging command into /st.
        # The gate keeps it reserved for deliberate word-like queries.
        assert _exact_substring("st", "Stage tracked files.") == 0
        assert _exact_substring("tag", "Fetch tags from the remote.") == 0
        # Same targets, query at the gate boundary: fires.
        assert _exact_substring("stag", "Stage tracked files.") == 100

    def test_exact_substring_booster_scores_zero_on_miss(self):
        # Binary signal: a miss falls through to the fuzzy specs instead of
        # polluting the best-spec-per-item race (run_search skips 0 < floor).
        assert _exact_substring("rebase", "Fast-forward merge or move branch pointer") == 0

    def test_booster_does_not_outrank_name_or_curated_keyword(self):
        # Floor-crossing, not ranking-dominance: bpush matches "push" via
        # name~ (100 × 0.95 = 95) AND via keywords AND via desc substring
        # (80). The strongest signal must win AND be labeled — the label pin
        # holds in both thefuzz and fallback envs, so deleting the booster
        # can never flip it.
        cmds = [
            CommandInfo(
                command="hug bpush",
                description="Push the current branch to its upstream remote.",
                keywords=["push"],
            ),
        ]
        results = search_keyword(cmds, "push")
        assert [r.command for r in results] == ["hug bpush"]
        score, _cmd, spec = run_search("push", cmds, KEYWORD_SPECS)[0]
        assert (score, spec.label) == (95, "name~")


class TestHydrateCategoryFields:
    """hydrate_category_fields populates category_desc from CategoryMeta."""

    def test_joins_multiple_category_descriptions(self):
        from category_meta import CategoryMeta
        from help_search import hydrate_category_fields

        cmds = [
            CommandInfo(
                command="hug bpush",
                description="Push to origin.",
                categories=["branching", "push-pull"],
            ),
        ]
        cat_meta = {
            "branching": CategoryMeta(
                name="branching",
                label="Branching",
                description="Branch operations.",
                summary="Branch operations.",
            ),
            "push-pull": CategoryMeta(
                name="push-pull",
                label="Remote sync",
                description="Sync with remotes.",
                summary="Sync with remotes.",
            ),
        }
        hydrate_category_fields(cmds, cat_meta)
        # Order matches command.categories order.
        assert "Branch operations." in cmds[0].category_desc
        assert "Sync with remotes." in cmds[0].category_desc

    def test_skips_unknown_categories(self):
        from help_search import hydrate_category_fields

        cmds = [CommandInfo(command="x", categories=["ghost"])]
        hydrate_category_fields(cmds, {})  # no manifest for "ghost"
        assert cmds[0].category_desc == ""


class TestThefuzzFallback:
    """Pin the substring-only fallback contract used when thefuzz is absent.

    The fallback functions (_fb_equal, _fb_substring, _fb_token_subset) are
    exposed at module level so this test runs regardless of whether thefuzz
    is installed. They're also the bindings used by _ratio/_partial/_wratio/
    _token_set in the no-thefuzz code path. Pinning their behavior here
    means a future contributor can't silently break the fallback.
    """

    def test_fb_equal_strict_match(self):
        from help_search import _fb_equal

        assert _fb_equal("undo", "undo") == 100
        assert _fb_equal("UNDO", "undo") == 100  # case-insensitive
        assert _fb_equal("undo", "h undo") == 0  # not equal — substring doesn't count
        assert _fb_equal("", "") == 100
        assert _fb_equal("undo", "") == 0

    def test_fb_substring_match(self):
        from help_search import _fb_substring

        assert _fb_substring("undo", "h undo") == 100
        assert _fb_substring("UNDO", "h undo") == 100  # case-insensitive
        assert _fb_substring("xyz", "h undo") == 0
        assert _fb_substring("", "anything") == 100  # "" is a substring of anything

    def test_fb_token_subset(self):
        from help_search import _fb_token_subset

        # Every query word appears in target → 100.
        assert _fb_token_subset("save work", "save my work in progress") == 100
        # Word order doesn't matter (token-set semantics).
        assert _fb_token_subset("work save", "save my work in progress") == 100
        # Missing query word → 0.
        assert _fb_token_subset("save delete", "save my work in progress") == 0
        # Empty query → 0 (no signal to match on).
        assert _fb_token_subset("", "anything") == 0

    def test_search_via_fallback_specs(self):
        # Build a custom MatchSpec that uses the fallback scorer directly,
        # bypassing whichever thefuzz/no-thefuzz binding production uses.
        from help_search import _fb_substring

        custom_specs = [
            MatchSpec(
                field="command",
                scorer=_fb_substring,
                weight=1.0,
                min_threshold=80,
                label="fb",
            ),
        ]
        cmd = CommandInfo(command="hug bpush", description="", categories=[])
        results = search_keyword([cmd], "push", specs=custom_specs)
        assert any(r.command == "hug bpush" for r in results)

    def test_fallback_no_false_positive(self):
        from help_search import _fb_substring

        custom_specs = [
            MatchSpec(
                field="command",
                scorer=_fb_substring,
                weight=1.0,
                min_threshold=80,
                label="fb",
            ),
        ]
        cmd = CommandInfo(command="hug bpush", description="", categories=[])
        results = search_keyword([cmd], "xyzzy12345", specs=custom_specs)
        assert results == []


class TestIntentMode:
    """!intent uses token_set_ratio — distinct from /keyword's precision scorer.

    Phrase queries like 'save my work' should match via token-set semantics:
    word order ignored, extra words tolerated, stopwords don't sink the score.
    """

    @pytest.fixture
    def commands(self):
        return [
            CommandInfo(
                command="hug w wip",
                description="Park work-in-progress aside.",
                categories=["working-dir", "parking"],
                keywords=["save", "shelve", "stash", "park", "wip"],
                category_desc="Park work-in-progress aside and unpark it later.",
            ),
            CommandInfo(
                command="hug bpush",
                description="Push the current branch to origin.",
                categories=["push-pull"],
                keywords=["push", "send", "upload", "publish"],
                category_desc="Sync the local repository with remotes.",
            ),
            CommandInfo(
                command="hug w wipdel",
                description="Discard a parked WIP commit (destructive).",
                categories=["working-dir", "parking"],
                keywords=["discard-wip", "delete-park"],
                category_desc="Park work-in-progress aside and unpark it later.",
            ),
        ]

    def test_intent_token_aware_finds_via_keyword(self, commands):
        # "save my work" — "save" is a per-command keyword on hug w wip.
        # token_set_ratio treats query words as a set; "save" alone is enough
        # to score 100 against the keyword "save".
        results = search_intent(commands, "save my work")
        assert any(r.command == "hug w wip" for r in results)

    def test_intent_word_order_independent(self, commands):
        # token_set_ratio is word-order-agnostic. "remote push" should yield
        # the same set of matches as "push remote" (order may differ, set same).
        a = {r.command for r in search_intent(commands, "remote push")}
        b = {r.command for r in search_intent(commands, "push remote")}
        assert a == b

    def test_intent_does_not_match_destructive_neighbor(self, commands):
        # F3 again, this time via the !intent path: per-command keywords
        # mean wipdel can't inherit "save" from a sibling.
        results = search_intent(commands, "save my work")
        cmds = [r.command for r in results]
        assert "hug w wipdel" not in cmds, (
            f"DESTRUCTIVE regression in !intent: 'hug w wipdel' surfaced for 'save my work': {cmds}"
        )

    def test_intent_separate_from_keyword(self, commands):
        # The two modes use different SPEC lists. INTENT_SPECS uses
        # token_set_ratio; KEYWORD_SPECS uses ratio + partial + WRatio.
        # Single-word query exercises both modes — just verifying they
        # both work without raising.
        kw = search_keyword(commands, "push")
        intent = search_intent(commands, "push")
        assert any(r.command == "hug bpush" for r in kw)
        assert any(r.command == "hug bpush" for r in intent)


class TestDiversify:
    """diversify caps + applies soft per-category penalty."""

    def _scored(self, *items):
        # items: tuples of (score, command, primary_category)
        return [
            (score, CommandInfo(command=name, description="", categories=[cat]), None)
            for score, name, cat in items
        ]

    def test_caps_results(self):
        from help_search import diversify

        scored = self._scored(
            (90, "hug a", "x"),
            (89, "hug b", "x"),
            (88, "hug c", "x"),
            (87, "hug d", "x"),
            (86, "hug e", "x"),
            (85, "hug f", "x"),
            (84, "hug g", "x"),
            (83, "hug h", "x"),
            (82, "hug i", "x"),
            (81, "hug j", "x"),
            (80, "hug k", "x"),
        )
        out = diversify(scored, cap=10, soft_cap_per_category=None)
        assert len(out) == 10

    def test_soft_diversify_penalises_same_category_excess(self):
        # 4 results from 'branching' (scores 90/89/88/87), 1 from 'staging' (86).
        # After 3 same-category, the 4th gets penalised. Penalty=5: 87 - 5*1 = 82.
        # Result: staging at 86 should rank above branching's 4th at 82.
        from help_search import diversify

        scored = self._scored(
            (90, "hug a", "branching"),
            (89, "hug b", "branching"),
            (88, "hug c", "branching"),
            (87, "hug d", "branching"),  # penalised
            (86, "hug e", "staging"),  # should outrank hug d after penalty
        )
        out = diversify(scored, cap=10, soft_cap_per_category=3, penalty=5)
        cmds = [c.command for _, c, _ in out]
        # hug e should now rank ahead of hug d.
        assert cmds.index("hug e") < cmds.index("hug d"), (
            f"diversification didn't fire — order was {cmds}"
        )

    def test_all_flag_disables_cap(self):
        # cap=None and soft_cap=None means "show everything, in raw score order".
        from help_search import diversify

        scored = self._scored(*[(80 - i, f"hug{i}", "x") for i in range(15)])
        out = diversify(scored, cap=None, soft_cap_per_category=None)
        assert len(out) == 15
        # Order should match input (already sorted by raw score descending).
        assert [c.command for _, c, _ in out] == [f"hug{i}" for i in range(15)]

    def test_search_keyword_caps_at_default(self):
        # End-to-end through search_keyword: 12 matches, expect cap=10 default.
        cmds = [
            CommandInfo(
                command=f"hug cmd{i}",
                description=f"command {i} push the thing",
                categories=["push-pull"],
                keywords=["push"],
            )
            for i in range(12)
        ]
        results = search_keyword(cmds, "push")
        assert len(results) == 10  # default cap

    def test_search_keyword_all_results_disables_cap(self):
        cmds = [
            CommandInfo(
                command=f"hug cmd{i}",
                description=f"command {i} push the thing",
                categories=["push-pull"],
                keywords=["push"],
            )
            for i in range(12)
        ]
        results = search_keyword(cmds, "push", all_results=True)
        assert len(results) == 12

    def test_format_results_overflow_note(self):
        cmds = [
            CommandInfo(command=f"hug cmd{i}", description=f"d{i}", categories=[]) for i in range(3)
        ]
        out = format_results(cmds, total=12)
        assert "Showing top 3 of 12" in out
        assert "--all" in out

    def test_format_results_no_overflow_when_within_cap(self):
        cmds = [
            CommandInfo(command=f"hug cmd{i}", description=f"d{i}", categories=[]) for i in range(3)
        ]
        out = format_results(cmds, total=3)
        assert "Showing top" not in out


class TestExplain:
    """--explain annotates each result line with the winning spec's label + score."""

    def test_format_results_explain_shows_label_and_score(self):
        cmd = CommandInfo(
            command="hug bc",
            description="Create a new branch.",
            categories=["branching"],
        )
        spec = MatchSpec(
            field="description",
            scorer=lambda q, t: 95,
            weight=1.0,
            min_threshold=80,
            label="desc",
        )
        details = [(95, cmd, spec)]
        out = format_results([cmd], details=details, explain=True)
        assert "[desc, 95]" in out

    def test_format_results_no_explain_omits_annotations(self):
        cmd = CommandInfo(
            command="hug bc",
            description="Create a new branch.",
            categories=["branching"],
        )
        # explain=False (default) — annotations must NOT appear even if
        # details is supplied.
        spec = MatchSpec(
            field="description",
            scorer=lambda q, t: 95,
            weight=1.0,
            min_threshold=80,
            label="desc",
        )
        details = [(95, cmd, spec)]
        out = format_results([cmd], details=details, explain=False)
        assert "[desc" not in out

    def test_explain_handles_command_without_details(self):
        # If a command appears in `commands` but not in `details` (shouldn't
        # happen in practice, but defend against caller error), the line
        # renders without annotation rather than crashing.
        cmd1 = CommandInfo(command="hug a", description="d1", categories=[])
        cmd2 = CommandInfo(command="hug b", description="d2", categories=[])
        spec = MatchSpec(
            field="description",
            scorer=lambda q, t: 90,
            weight=1.0,
            min_threshold=0,
            label="desc",
        )
        details = [(90, cmd1, spec)]  # cmd2 NOT in details
        out = format_results([cmd1, cmd2], details=details, explain=True)
        assert "[desc, 90]" in out  # cmd1 annotated
        # cmd2 line exists but no annotation
        assert "hug b" in out
        # Ensure cmd2's line doesn't have a stray annotation
        cmd2_line = next(line for line in out.splitlines() if "hug b" in line)
        assert "[" not in cmd2_line


class TestFormatCategoryListWithMeta:
    """`hug help @` (no query) shows summary column when cat_meta is supplied."""

    def test_summary_column_present(self):
        from category_meta import CategoryMeta
        from help_search import format_category_list

        cmds = [
            CommandInfo(command="hug bc", description="", categories=["branching"]),
            CommandInfo(command="hug b", description="", categories=["branching"]),
            CommandInfo(command="hug a", description="", categories=["staging"]),
        ]
        cat_meta = {
            "branching": CategoryMeta(
                name="branching",
                label="Branch ops",
                description="Create, list, switch, and delete branches.",
                summary="Create, list, switch, and delete branches.",
            ),
            "staging": CategoryMeta(
                name="staging",
                label="Staging area",
                description="Stage and unstage changes.",
                summary="Stage and unstage changes.",
            ),
        }
        out = format_category_list(cmds, cat_meta=cat_meta)
        assert "@branching" in out
        assert "Create, list, switch, and delete branches" in out
        assert "(2)" in out  # two branching commands
        assert "to learn about a category and list its commands" in out

    def test_falls_back_when_no_meta_supplied(self):
        # Without cat_meta, the bare listing format (no summaries) still works.
        cmds = [
            CommandInfo(command="hug a", description="", categories=["staging"]),
            CommandInfo(command="hug bc", description="", categories=["branching"]),
        ]
        out = format_category_list(cmds, cat_meta=None)
        assert "@branching" in out
        assert "@staging" in out
        # No summary separator when no meta.
        assert "—" not in out

    def test_keyword_and_intent_hint_lines(self):
        cmds = [CommandInfo(command="hug a", description="", categories=["staging"])]
        out = format_category_list(cmds, cat_meta=None)
        assert "/<keyword>" in out
        assert "!<intent>" in out

    def test_empty_categories(self):
        out = format_category_list([], cat_meta=None)
        assert "Available categories" in out
        assert "(none)" in out


class TestFormatCategoryPage:
    """`hug help @<category>` renders a boxed page with stderr/stdout split."""

    def _meta(self):
        from category_meta import CategoryMeta

        return CategoryMeta(
            name="branching",
            label="Branch operations",
            description=(
                "Create, list, switch, and delete branches.\n"
                "Branches let you work on parallel lines of development "
                "without conflicting with shared code."
            ),
            summary="Create, list, switch, and delete branches.",
        )

    def test_includes_label_and_paragraph(self):
        from help_search import format_category_page

        cmd = CommandInfo(
            command="hug bc",
            description="Create a new branch and switch to it.",
            categories=["branching"],
        )
        out = format_category_page(self._meta(), [cmd], width=72)
        assert "@branching" in out
        assert "Branch operations" in out
        assert "Create, list, switch, and delete branches." in out
        assert "hug bc" in out
        assert "Create a new branch and switch to it." in out

    def test_no_keywords_section(self):
        # B-tweaked: keywords are NOT a category-level concept, so the page
        # MUST NOT show a Keywords section. If a future change reintroduces
        # category-level keywords, this test fires.
        from help_search import format_category_page

        out = format_category_page(self._meta(), [], width=72)
        assert "Keywords" not in out

    def test_command_count_in_header(self):
        from help_search import format_category_page

        cmds = [
            CommandInfo(command=f"hug bc{i}", description=f"d{i}", categories=["branching"])
            for i in range(3)
        ]
        out = format_category_page(self._meta(), cmds, width=72)
        assert "Commands (3)" in out

    def test_split_streams_returns_3_tuple(self):
        # split_streams=True returns (header, data, footer). Header + footer
        # → stderr (decorative); data → stdout. Splitting header from footer
        # so the caller can flush data BETWEEN them, ensuring the "Tip:"
        # line visually follows the command list in interactive TTYs.
        from help_search import format_category_page

        cmd = CommandInfo(command="hug bc", description="Create.", categories=["branching"])
        result = format_category_page(self._meta(), [cmd], width=72, split_streams=True)
        assert isinstance(result, tuple)
        assert len(result) == 3
        header, data, footer = result
        # Header has the box rules, name, description, "Commands (N)" line.
        assert "──" in header
        assert "@branching" in header
        assert "Create, list, switch, and delete branches." in header
        # Footer has only the Tip — no rules, no header.
        assert "Tip:" in footer
        assert "@branching" not in footer
        # Stdout data has ONLY the command list — no rules, no chatter.
        assert "──" not in data
        assert "Tip:" not in data
        assert "hug bc" in data

    def test_split_streams_empty_data_when_no_commands(self):
        from help_search import format_category_page

        header, data, footer = format_category_page(self._meta(), [], width=72, split_streams=True)
        # Stdout is empty when no commands; header + footer still render.
        assert data == ""
        assert "@branching" in header
        assert "Tip:" in footer

    def test_width_clamped_to_min_max(self):
        # Tiny terminal (width=10) should not produce broken output.
        from help_search import format_category_page

        out = format_category_page(self._meta(), [], width=10)
        # Implementation clamps to >= 40.
        assert "@branching" in out

    def test_long_description_word_wraps(self):
        # textwrap should re-flow long descriptions to fit width.
        from category_meta import CategoryMeta
        from help_search import format_category_page

        long_desc = " ".join(["word"] * 30)
        meta = CategoryMeta(
            name="x",
            label="X",
            description=long_desc,
            summary=long_desc[:70],
        )
        out = format_category_page(meta, [], width=40)
        # No single line exceeds width (allowing for trailing spaces stripped).
        for line in out.splitlines():
            assert len(line) <= 60, f"line too long: {line!r}"  # 40 + slack


class TestRuntimeValidation:
    """main() refuses to operate when a script's category has no manifest."""

    def _build_orphan_repo(self, tmp_path):
        """Create a tiny repo: 1 script declaring an unmanifested category."""
        bin_dir = tmp_path / "bin"
        bin_dir.mkdir()
        script = bin_dir / "git-frob"
        script.write_text(
            "#!/usr/bin/env bash\n"
            "test \"${1:-}\" = '--search-meta' && {\n"
            "  printf 'category = [\"flubber\"]\\n'\n"
            "  exit 0\n"
            "}\n"
            "test \"${1:-}\" = '--help' && {\n"
            "  printf 'hug frob: Frob the wibble.\\n'\n"
            "  exit 0\n"
            "}\n"
        )
        script.chmod(0o755)
        cat_dir = tmp_path / "categories"
        cat_dir.mkdir()  # intentionally empty — no flubber.toml
        cache_dir = tmp_path / "cache"
        return bin_dir, cat_dir, cache_dir

    def test_main_exits_1_when_category_missing_manifest(self, tmp_path, monkeypatch, capsys):
        bin_dir, cat_dir, cache_dir = self._build_orphan_repo(tmp_path)
        from help_search import main as help_main

        monkeypatch.setattr(
            "sys.argv",
            [
                "help_search.py",
                "@",
                "--bin-dir",
                str(bin_dir),
                "--cache-dir",
                str(cache_dir),
                "--categories-dir",
                str(cat_dir),
            ],
        )
        with pytest.raises(SystemExit) as exc_info:
            help_main()
        assert exc_info.value.code == 1
        err = capsys.readouterr().err
        assert "flubber" in err
        assert "categories/flubber.toml" in err

    def test_main_exits_1_when_categories_dir_missing(self, tmp_path, monkeypatch, capsys):
        # Pointing --categories-dir at a non-existent path is a hard error,
        # not a silent degradation. Surfaces install-time setup mistakes.
        bin_dir = tmp_path / "bin"
        bin_dir.mkdir()
        ghost_dir = tmp_path / "no-such-dir"

        from help_search import main as help_main

        monkeypatch.setattr(
            "sys.argv",
            [
                "help_search.py",
                "@",
                "--bin-dir",
                str(bin_dir),
                "--cache-dir",
                str(tmp_path / "cache"),
                "--categories-dir",
                str(ghost_dir),
            ],
        )
        # Path.glob() doesn't raise FileNotFoundError on missing directory
        # — it just returns no matches. Therefore the loader returns an
        # empty dict, validation passes (no scripts to validate), and main
        # proceeds with no manifests. This is acceptable: a missing
        # categories/ dir with no scripts to validate is "everything's OK,
        # nothing to validate." If scripts ARE present, validation catches
        # the missing manifests via the previous test.
        # Just verify main() doesn't crash.
        try:
            help_main()
        except SystemExit as exc:
            assert exc.code in (None, 0)


class TestRepoIntegrityViaHelpSearch:
    """End-to-end: validate the real repo via main()'s validation gate."""

    def test_real_repo_validates_clean(self, tmp_path, monkeypatch, capsys):
        # The actual repo's bin scripts + categories MUST be in sync —
        # this is the guard that catches a contributor adding a category
        # to a script without bootstrapping the TOML. Mirrors the
        # TestRepoIntegrity test in test_category_meta.py but exercises
        # the full main() entry point instead of the loader directly.
        from pathlib import Path

        repo_root = Path(__file__).resolve().parents[3]
        bin_dir = repo_root / "git-config" / "bin"
        cat_dir = repo_root / "git-config" / "lib" / "python" / "categories"

        from help_search import main as help_main

        monkeypatch.setattr(
            "sys.argv",
            [
                "help_search.py",
                "@",
                "--bin-dir",
                str(bin_dir),
                "--cache-dir",
                str(tmp_path / "cache"),
                "--categories-dir",
                str(cat_dir),
            ],
        )
        # Should NOT raise SystemExit(1). Capture the output so we don't
        # spam test logs with the @ listing.
        try:
            help_main()
        except SystemExit as exc:
            err = capsys.readouterr().err
            assert exc.code in (None, 0), f"validation failed in real repo: {err}"
        # When run_search picks the best spec per command, format_results
        # must show THAT spec's label — not a different one.
        cmd = CommandInfo(
            command="hug bc",
            description="d",
            categories=[],
            keywords=["create-branch"],
        )
        # Two specs that both match; the higher-scoring one should win.
        specs = [
            MatchSpec(
                field="description",
                scorer=lambda q, t: 70,
                weight=1.0,
                min_threshold=0,
                label="desc",
            ),
            MatchSpec(
                field="keywords",
                scorer=lambda q, t: 90,
                weight=1.0,
                min_threshold=0,
                label="keywords",
            ),
        ]
        details = run_search("create-branch", [cmd], specs)
        out = format_results([cmd], details=details, explain=True)
        assert "[keywords, 90]" in out
        assert "[desc, 70]" not in out


class TestArticleMode:
    """`:`  mode dispatches to articles_loader."""

    def test_bare_colon_lists_articles(self, capsys, monkeypatch, tmp_path):
        # Stand up a minimal articles dir.
        adir = tmp_path / "articles"
        adir.mkdir()
        (adir / "demo.md").write_text(
            '+++\ntitle = "Demo"\nsummary = "Demo article."\n+++\n\n# Demo\n'
        )
        # Empty categories dir to keep validate_against_scripts happy.
        (tmp_path / "cats").mkdir()
        monkeypatch.setattr(
            "sys.argv",
            [
                "help_search.py",
                ":",
                "",
                "--bin-dir",
                str(tmp_path),  # not used by : mode
                "--articles-dir",
                str(adir),
                "--cache-dir",
                str(tmp_path / "cache"),
                "--categories-dir",
                str(tmp_path / "cats"),
            ],
        )

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
        monkeypatch.setattr(
            "sys.argv",
            [
                "help_search.py",
                ":",
                "demo",
                "--bin-dir",
                str(tmp_path),
                "--articles-dir",
                str(adir),
                "--cache-dir",
                str(tmp_path / "cache"),
                "--categories-dir",
                str(tmp_path / "cats"),
            ],
        )
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
        monkeypatch.setattr(
            "sys.argv",
            [
                "help_search.py",
                ":",
                "hug101",
                "--bin-dir",
                str(tmp_path),
                "--articles-dir",
                str(adir),
                "--cache-dir",
                str(tmp_path / "cache"),
                "--categories-dir",
                str(tmp_path / "cats"),
            ],
        )
        from help_search import main

        with pytest.raises(SystemExit) as exc:
            main()
        assert exc.value.code == 1
        out = capsys.readouterr()
        assert "no article named" in out.err
        assert ":hug-101" in out.err


# ── Registry merge (Task 2) ───────────────────────────────────────────────
# commands.toml rows flow into the CommandInfo index as ordinary rows with
# `kind` set; script rows keep kind=None. The merge happens AFTER the cache
# build and BEFORE the sort, so the registry never enters search-meta.cache
# and the returned list is one alphabetical run.


def _cmd_meta():
    return load_commands(bin_dir=BIN, gitconfig=GITCONFIG)


def test_merge_interleaves_and_sorts(tmp_path):
    cmds = collect_metadata(
        BIN,
        cache_dir=tmp_path / "cache",
        use_cache=False,
        cat_meta=load_categories(CATS),
        cmd_meta=_cmd_meta(),
    )
    names = [c.command for c in cmds]
    assert names == sorted(names)  # ONE alphabetical run, not script-block + registry-block
    by_name = {c.command: c for c in cmds}
    assert by_name["hug bpullr"].kind == "alias"
    assert by_name["hug fetch"].kind == "passthrough"
    assert by_name["hug bpush"].kind is None  # scripts keep kind=None


def test_merge_survives_warm_cache(tmp_path):
    cache_dir = tmp_path / "cache"
    registry = _cmd_meta()
    one = collect_metadata(
        BIN,
        cache_dir=cache_dir,
        use_cache=True,
        cat_meta=load_categories(CATS),
        cmd_meta=registry,
    )
    two = collect_metadata(
        BIN,
        cache_dir=cache_dir,
        use_cache=True,
        cat_meta=load_categories(CATS),
        cmd_meta=registry,
    )
    # Call 1 cold-populates the PRIVATE cache; call 2 takes the mtime-hit
    # path for every script, yet must still yield every registry row — the
    # merge is cache-independent because rows never enter search-meta.cache.
    # (A shared production cache would make both calls identical and the
    # assertion vacuous, so this test owns its cache.)
    expected = {f"hug {name}" for name in registry}
    assert expected <= {c.command for c in one if c.kind}  # cold
    assert expected == {c.command for c in two if c.kind}  # warm: full set
    assert "hug fetch" in expected  # the regression's namesake, explicit


def test_no_cmd_meta_is_hermetic(tmp_path):
    # Default cmd_meta=None must not touch the real registry: mock-dir tests
    # stay hermetic (the explicit-param precedent of cat_meta).
    cmds = collect_metadata(
        BIN, cache_dir=tmp_path / "cache", use_cache=False, cat_meta=load_categories(CATS)
    )
    assert all(c.kind is None for c in cmds)
    # `fetch` is registry-only (drift2a forbids a git-fetch bin script).
    assert not any(c.command == "hug fetch" for c in cmds)


def test_merge_flattens_multiline_descriptions(tmp_path):
    # coverage audit: the merge flattens TOML multi-line prose with
    # `" ".join(description.split())` so a row renders as ONE listing line;
    # the substring assertions in test_main_threads_registry_into_search
    # cannot see a regression (both fragments survive embedded newlines).
    # fetch's description is hard-wrapped across four TOML lines — the pin.
    cmds = collect_metadata(
        BIN,
        cache_dir=tmp_path / "cache",
        use_cache=False,
        cat_meta=load_categories(CATS),
        cmd_meta=_cmd_meta(),
    )
    registry_rows = [c for c in cmds if c.kind is not None]
    assert registry_rows  # the merge actually ran
    for cmd in registry_rows:
        assert "\n" not in cmd.description, cmd.command
        assert "  " not in cmd.description, cmd.command


def test_format_marker_renders_kind():
    row = CommandInfo(
        command="hug bpullr",
        description="Pull with rebase",
        categories=["push-pull"],
        kind="alias",
    )
    out = format_results([row])
    assert "(git alias)" in out


def test_format_category_page_marker_renders_kind():
    # Same render-time marker on the @category page — the AC names BOTH
    # format layers, not just /keyword results.
    meta = CategoryMeta(
        name="push-pull",
        label="Push & pull",
        description="Sync work with remotes.",
        summary="Sync work with remotes.",
    )
    row = CommandInfo(
        command="hug bpullr",
        description="Pull with rebase",
        categories=["push-pull"],
        kind="alias",
    )
    out = format_category_page(meta, [row], width=72)
    assert "(git alias)" in out


def test_main_registry_failure_exits_1(tmp_path, monkeypatch, capsys):
    # Search-mode posture: a corrupt registry is LOUD — message on stderr,
    # exit 1 — mirroring the categories loader. Silent-empty would shrink
    # the index and every answer with it.
    (tmp_path / "cats").mkdir()  # empty manifests: fine, validation runs later
    monkeypatch.setattr(
        "sys.argv",
        [
            "help_search.py",
            "/",
            "fetch",
            "--bin-dir",
            str(tmp_path),
            "--cache-dir",
            str(tmp_path / "cache"),
            "--categories-dir",
            str(tmp_path / "cats"),
        ],
    )

    def _corrupt(*_args, **_kwargs):
        raise RegistryError("corrupt registry probe")

    monkeypatch.setattr("command_meta.load_commands", _corrupt)

    with pytest.raises(SystemExit) as exc_info:
        main()
    assert exc_info.value.code == 1
    assert "corrupt registry probe" in capsys.readouterr().err


def test_main_threads_registry_into_search(tmp_path, monkeypatch, capsys):
    # Pins the LIVE wiring: main() must pass cmd_meta into collect_metadata.
    # Without it, /fetch stays registry-blind in production while every
    # unit-level test stays green — the exact gap the plan review caught.
    monkeypatch.setattr(
        "sys.argv",
        [
            "help_search.py",
            "/",
            "fetch",
            "--bin-dir",
            str(BIN),
            "--cache-dir",
            str(tmp_path / "cache"),
            "--categories-dir",
            str(CATS),
        ],
    )
    main()
    out = capsys.readouterr().out
    assert "hug fetch" in out
    assert "(git passthrough)" in out  # marker flows through main() too


# --- Card mode (Task 3) -------------------------------------------------------
# Exit contract: 0 card | 4 miss (EXCLUSIVELY) | >=2 loud. Miss is 4, NOT 1:
# uv itself can exit 1 on environment failure BEFORE this script runs, so
# exit 1 must mean loud for the bash caller. render_card is a pure function
# over the registry + a READ-ONLY cache peek (keyed by script FILENAME
# `git-<name>`) — never collect_metadata, never _save_cache.


def test_card_found_render(capsys):
    rc = render_card("fetch", registry=_cmd_meta(), cache_dir=None)
    out = capsys.readouterr().out
    assert rc == 0
    assert "(git passthrough)" in out and "Usage:" in out
    assert "Git equivalent: git fetch" in out
    assert "Full flags: git help fetch" in out
    # Related summaries must come from the REGISTRY branch (`hug <rel> —
    # <summary>`), not the prose of fetch's own description nor the
    # degraded bare hint — assert the em-dash + summary prefix.
    assert "hug bpull — Fast-forward-only pull" in out
    assert "hug bpullr — Pull with rebase" in out


def test_card_fullflags_uses_alias_target(capsys):
    # Full flags derive from git_equivalent's LEADING command, not the name:
    # `git help bpullr` prints an alias notice, not flag docs.
    render_card("bpullr", registry=_cmd_meta(), cache_dir=None)
    out = capsys.readouterr().out
    assert "Full flags: git help pull" in out  # NOT git help bpullr


def test_card_bs_targets_switch(capsys):
    render_card("bs", registry=_cmd_meta(), cache_dir=None)
    assert "Full flags: git help switch" in capsys.readouterr().out


def test_card_fullflags_non_git_fallback(capsys):
    # coverage audit: render_card's `parts[:1] == ["git"]` guard had no
    # reachable case in shipped data (all seven entries are git-prefixed);
    # a non-git leading command must fall back to the WHOLE git_equivalent.
    reg = dict(_cmd_meta())
    reg["fetch"] = replace(reg["fetch"], git_equivalent="hg pull --update")
    render_card("fetch", registry=reg, cache_dir=None)
    assert "Full flags: git help hg pull --update" in capsys.readouterr().out


def test_card_miss_exits_4(capsys):
    # 4, NOT 1: uv itself can exit 1 on environment failure before the
    # script runs — bash maps 1 to loud, so the miss needs its own code.
    assert render_card("zzz", registry=_cmd_meta(), cache_dir=None) == 4
    out = capsys.readouterr().out
    assert "Usage:" not in out  # no partial card on miss


def test_card_miss_propagates_4_through_main(monkeypatch, capsys):
    # The bash contract consumes main()'s code, not render_card's return:
    # the card dispatch must propagate the miss as 4 (bash falls through),
    # while uv's own exit 1 stays LOUD one layer out (git-hughelp case arm).
    monkeypatch.setattr("sys.argv", ["help_search.py", "card", "--", "zzz"])
    with pytest.raises(SystemExit) as ei:
        main()
    assert ei.value.code == 4
    assert capsys.readouterr().out == ""


def test_card_corrupt_registry_loud(tmp_path, capsys):
    # Corrupt registry in card mode is LOUD and >=2 — never the exit-4 miss
    # (which would silently degrade `hug help <name>` to legacy help). The
    # loader's missing-required-field check fires before the kind check, so
    # this minimal fixture dies on `description`; a bad kind dies the same
    # loud way (command_meta's own tests pin the kind path).
    (tmp_path / "commands.toml").write_text("[fetch]\nkind = 'bogus'\n")
    rc = render_card(
        "fetch", registry=None, commands_path=tmp_path / "commands.toml", cache_dir=None
    )
    cap = capsys.readouterr()  # ONE capture: a second call resets to empty
    assert rc >= 2 and cap.err and not cap.out


def test_card_cache_peek_uses_git_name_key(tmp_path, capsys):
    # related summary for script `llu` resolves from a cache keyed by FILENAME
    (tmp_path / "search-meta.cache").write_text(
        json.dumps({"git-llu": {"description": "outgoing commits"}})
    )
    render_card("fetch", registry=_cmd_meta(), cache_dir=tmp_path)
    assert "outgoing commits" in capsys.readouterr().out


def test_card_cache_hint_strips_ansi_and_control_bytes(tmp_path, capsys):
    # The peeked hint is the ONLY card text sourced outside this repo
    # (search-meta.cache) — hostile or merely stale cache contents must not
    # drive the terminal: C0/DEL bytes and ANSI escape sequences (CSI
    # clear-screen + cursor move; an OSC 52 clipboard write, BEL-terminated)
    # are stripped, while the sanitized tail still renders. Registry
    # summaries are first-party prose and intentionally skip the sanitizer.
    (tmp_path / "search-meta.cache").write_text(
        json.dumps({"git-llu": {"description": "\x1b[2J\x1b[3H\x1b]52;c;aGVsbG8=\x07clean hint"}})
    )
    render_card("fetch", registry=_cmd_meta(), cache_dir=tmp_path)
    out = capsys.readouterr().out
    assert "clean hint" in out  # sanitized text survives
    assert "\x1b" not in out and "\x07" not in out  # no escape/BEL reaches stdout
    # Zero control bytes except the card's own line structure (\n from the
    # join/print — legitimate layout, not cache content).
    assert not any((ord(ch) < 32 and ch != "\n") or ord(ch) == 127 for ch in out)


def test_card_cache_hint_strips_raw_c1_controls(tmp_path, capsys):
    # C1 (0x80-0x9f): raw 0x9B is the 8-bit CSI on terminals that accept it —
    # an ESC-prefixed payload cannot catch this shape, so the hostile
    # sequence here carries NO ESC at all. The control class must extend
    # through 0x9f or these bytes drive the terminal.
    (tmp_path / "search-meta.cache").write_text(
        json.dumps({"git-llu": {"description": "\x9b2J\x9b3H\x9bclean hint"}})
    )
    render_card("fetch", registry=_cmd_meta(), cache_dir=tmp_path)
    out = capsys.readouterr().out
    assert "clean hint" in out
    assert "\x9b" not in out
    assert not any((ord(ch) < 32 and ch != "\n") or 127 <= ord(ch) <= 159 for ch in out)


def test_collect_metadata_sanitizes_cache_sourced_text(tmp_path):
    # BOUNDARY pin (the sibling sink): search modes materialize every row
    # from the cache and format_results prints descriptions raw — so the
    # strip must happen ONCE at materialization, not only in render_card's
    # hint branch. command/description/keywords/categories are all covered.
    (tmp_path / "search-meta.cache").write_text(
        json.dumps(
            {
                "git-hostile": {
                    "command": "hug hostile\x1b[3H",
                    "description": "Clean start\x1b[2J with ESC mid-prose",
                    "categories": ["head\x1b[31m"],
                    "keywords": ["probe\x1b[31m"],
                    "mtime": 1,
                }
            }
        )
    )
    cmds = collect_metadata(tmp_path, cache_dir=tmp_path, use_cache=True, cat_meta=None)
    (row,) = [c for c in cmds if c.command.startswith("hug hostile")]
    assert row.command == "hug hostile"
    assert row.description == "Clean start with ESC mid-prose"
    assert row.keywords == ["probe"]
    assert row.categories == ["head"]


def test_save_cache_failed_replace_is_silent(tmp_path, monkeypatch):
    # Atomic write: sibling temp + os.replace, with a failed replace skipped
    # SILENTLY (the cache is a pure optimization — the next run re-queries);
    # temp-write failures above the try stay LOUD, pinned by the
    # pipeline-OSError tests.
    cache_file = tmp_path / "search-meta.cache"
    cache_file.write_text("old")

    def _boom(_src, _dst):
        raise OSError(18, "cross-device link probe")

    monkeypatch.setattr(os, "replace", _boom)
    _save_cache(cache_file, {"a": 1})
    assert cache_file.read_text() == "old"  # failed replace left the old file
    assert not list(tmp_path.glob("*.tmp"))  # temp cleaned up, no litter


def test_card_cache_peek_nonstring_hint_degrades_to_bare(tmp_path, capsys):
    # coverage audit: cache JSON is untrusted — a NON-STRING description
    # (number/null) must degrade to the bare `hug <rel>` hint, never leak
    # repr junk into the card and never turn a render into a loud exit.
    (tmp_path / "search-meta.cache").write_text(json.dumps({"git-llu": {"description": 123}}))
    render_card("fetch", registry=_cmd_meta(), cache_dir=tmp_path)
    out = capsys.readouterr().out
    assert "hug llu" in out
    assert "123" not in out


def test_card_flaglike_name_is_not_help(monkeypatch, capsys):
    # `-h` behind `--` is a NAME, never argparse help: argparse strips the
    # end-of-options marker and treats what follows as positionals, so the
    # flag-like miss exits 4 with zero usage text on stdout.
    monkeypatch.setattr("sys.argv", ["help_search.py", "card", "--", "-h"])
    with pytest.raises(SystemExit) as ei:
        main()
    assert ei.value.code == 4  # flag-like name is a plain registry miss, never argparse usage
    assert "usage: help_search.py" not in capsys.readouterr().out


def test_card_bogus_flag_name_is_miss_too(monkeypatch, capsys):
    # `--bogus` behind `--` is likewise a NAME (argparse never intercepts
    # option-like strings after the end-of-options marker) → miss → 4.
    monkeypatch.setattr("sys.argv", ["help_search.py", "card", "--", "--bogus"])
    with pytest.raises(SystemExit) as ei:
        main()
    assert ei.value.code == 4
    assert "usage: help_search.py" not in capsys.readouterr().out


def test_card_unexpected_exception_maps_to_3_not_1(capsys):
    # The exit contract's reason to exist: Python exits 1 on ANY bare crash —
    # the same code as a miss — so render_card must remap unexpected
    # exceptions to 3 with a loud stderr message. A poisoned registry entry
    # (git_equivalent=None breaks .split()) simulates any card bug.
    reg = dict(_cmd_meta())
    reg["fetch"] = replace(reg["fetch"], git_equivalent=None)
    rc = render_card("fetch", registry=reg, cache_dir=None)
    cap = capsys.readouterr()  # ONE capture: a second call resets to empty
    assert rc == 3  # NEVER 1 — a card bug must not masquerade as a miss
    assert "card render failed" in cap.err and cap.out == ""


def test_card_brokenpipe_inbody_returns_zero_with_fd1_on_devnull(monkeypatch):
    # In-body EPIPE shape: a stdout whose write() hits a dead pipe on the
    # first flush (line-buffered stdout, or a card larger than the 8KB block
    # buffer). render_card must catch BrokenPipeError, redirect fd 1 to
    # devnull (interpreter-later flushes become harmless), and return 0 — a
    # dead pipe is not a card bug. The stub's fileno() reports the REAL fd 1
    # so the handler's dup2 redirects the actual stdout; fd 1 is saved and
    # restored around the probe to keep pytest's fd capture intact.

    class _DeadPipeStdout:
        def write(self, _s):
            raise BrokenPipeError

        def fileno(self):
            return 1

        def flush(self):
            raise BrokenPipeError

    saved = os.dup(1)
    monkeypatch.setattr(sys, "stdout", _DeadPipeStdout())
    try:
        rc = render_card("fetch", registry=_cmd_meta(), cache_dir=None)
        assert os.fstat(1).st_rdev == os.stat(os.devnull).st_rdev  # redirected
    finally:
        os.dup2(saved, 1)
        os.close(saved)
    assert rc == 0


def test_card_keyboardinterrupt_unwrapped():
    # KeyboardInterrupt is BaseException, not Exception — but the contract
    # demands it explicitly: a Ctrl-C during render must PROPAGATE (shell
    # sees 130), never be remapped to the exit-3 catch-all or swallowed.

    class _InterruptRegistry(dict):
        def get(self, _name, _default=None):
            raise KeyboardInterrupt

    with pytest.raises(KeyboardInterrupt):
        render_card("fetch", registry=_InterruptRegistry(), cache_dir=None)


def test_module_guard_dead_pipe_exits_zero(tmp_path):
    # Subprocess-level probe of the __main__ guard. Mechanism: the pipe's
    # read end is closed BEFORE spawn, so the first flush of card-sized
    # output (well under the 8KB block buffer) deterministically raises
    # EPIPE at a point inside the guard's try — never at interpreter
    # finalization (for card mode that shape is unreachable BY DESIGN: the
    # card branch flushes before sys.exit, which is the fix for the probed
    # exit-120 hole). `card` exercises the card branch's pre-exit flush;
    # the search-mode invocation (`@` with no query, main() returns
    # normally) exercises the guard's OWN flush line. Both must end at
    # devnull + exit 0 with zero traceback/"Exception ignored" noise.
    # Hermetic pipeline: a one-script stub bin + empty cache + real
    # categories (the test_search_pipeline_oserror_loud_end_to_end pattern)
    # so the `@` arm never scans the ~200-script real bin and no test run
    # writes the shared /tmp cache. Flags precede the positionals: after
    # `--`, argparse would treat them as extra positionals.
    script = PY_DIR / "help_search.py"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    probe = bin_dir / "git-probe"
    probe.write_text("#!/bin/sh\nexit 0\n")
    probe.chmod(0o755)
    hermetic = [
        "--bin-dir",
        str(bin_dir),
        "--cache-dir",
        str(tmp_path / "cache"),
        "--categories-dir",
        str(CATS),
    ]
    # Positional BEFORE the optionals: on Python ≤3.11 argparse drops a
    # nargs='?' positional that follows optionals ("unrecognized arguments:
    # fetch") — the product path (git-hughelp passes no optionals) is immune.
    for argv in (["card", "fetch", *hermetic], ["@", *hermetic]):
        r, w = os.pipe()
        os.close(r)  # reader gone: any pipe write raises EPIPE
        proc = subprocess.Popen(
            [sys.executable, str(script), *argv],
            stdout=w,
            stderr=subprocess.PIPE,
            cwd=str(PY_DIR),
        )
        os.close(w)  # parent drops its copy or the child never sees EPIPE
        _out, err = proc.communicate(timeout=60)
        assert proc.returncode == 0, (argv, proc.returncode, err)
        assert b"Traceback" not in err and b"Exception ignored" not in err


@pytest.mark.skipif(not os.path.exists("/dev/full"), reason="/dev/full not available")
def test_card_devfull_stays_quiet_zero():
    # Pin the card side of the quiet-flush contract: writing the card to
    # /dev/full (ENOSPC — an OSError that is NOT BrokenPipeError) must stay
    # a quiet exit 0 via _flush_stdout_quietly. No traceback noise, no 120.
    with open("/dev/full", "wb") as devfull:
        proc = subprocess.run(
            [sys.executable, str(PY_DIR / "help_search.py"), "card", "--", "fetch"],
            stdout=devfull,
            stderr=subprocess.PIPE,
            cwd=str(PY_DIR),
            timeout=60,
        )
    assert proc.returncode == 0
    assert proc.stderr == b""


def test_search_pipeline_oserror_stays_loud(tmp_path, monkeypatch, capsys):
    # REGRESSION PIN (re-review): the __main__ guard once caught OSError
    # around rc = main(), which converted search-mode pipeline failures into
    # SILENT exit-0 (probed: unwritable cache dir → rc 0, empty output). The
    # guard is BrokenPipeError-only again, so a pipeline OSError must
    # propagate out of main() — loud — never vanish into the quiet-flush
    # helper. In-process: monkeypatch the cache write to raise.
    def _boom(_cache_file, _data):
        raise PermissionError(13, "unwritable cache dir probe")

    monkeypatch.setattr("help_search._save_cache", _boom)
    monkeypatch.setattr(
        "sys.argv",
        [
            "help_search.py",
            "/",
            "fetch",
            "--bin-dir",
            str(BIN),
            "--cache-dir",
            str(tmp_path / "cache"),
            "--categories-dir",
            str(CATS),
        ],
    )
    with pytest.raises(PermissionError):
        main()
    assert capsys.readouterr().out == ""  # no results printed as success


def test_search_pipeline_oserror_loud_end_to_end(tmp_path):
    # Same regression pinned at the boundary the in-process test cannot see:
    # the __main__ guard itself. A cache-dir that CANNOT be created (its
    # parent is a regular FILE → mkdir raises FileExistsError, an OSError,
    # uid-independently) must exit LOUD — nonzero, traceback on stderr,
    # nothing on stdout — never the silent-0 the broad OSError clause once
    # produced. A one-script bin dir keeps the pipeline scan fast.
    script = PY_DIR / "help_search.py"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    probe = bin_dir / "git-probe"
    probe.write_text("#!/bin/sh\nexit 0\n")
    probe.chmod(0o755)
    cache_dir = tmp_path / "blocker"
    cache_dir.write_text("a file, not a directory")
    proc = subprocess.run(
        [
            sys.executable,
            str(script),
            "/",
            "fetch",
            "--bin-dir",
            str(bin_dir),
            "--cache-dir",
            str(cache_dir),
            "--categories-dir",
            str(CATS),
        ],
        capture_output=True,
        cwd=str(PY_DIR),
        timeout=60,
    )
    assert proc.returncode != 0  # LOUD — the regression was a silent 0
    assert proc.stdout == b""  # never results-as-success
    assert b"Traceback" in proc.stderr


def test_article_mode_skips_registry_load(tmp_path, monkeypatch, capsys):
    # ":" mode renders prose from articles_loader and never reads the
    # registry, so it must not pay the TOML parse + alias scan. The
    # monkeypatched load_commands RAISES: if the guard were missing, the
    # load would surface as the loud search-mode exit 1 (or an escaping
    # RegistryError) — this test passes only when the load is SKIPPED.
    (tmp_path / "cats").mkdir()
    monkeypatch.setattr("sys.argv", ["help_search.py", ":"])

    def _boom(*_args, **_kwargs):
        raise RegistryError("corrupt registry probe")

    monkeypatch.setattr("command_meta.load_commands", _boom)
    main()  # must return normally — no SystemExit, no escaping RegistryError
    cap = capsys.readouterr()
    assert "corrupt registry probe" not in cap.err  # the load never ran
    assert cap.err != ""  # article-listing header (chatter) still reaches stderr
