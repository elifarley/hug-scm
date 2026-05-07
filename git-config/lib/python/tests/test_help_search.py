"""Tests for help_search.py — topic search for hug help."""

import json

import pytest

from help_search import (
    CommandInfo,
    MatchSpec,
    collect_metadata,
    derive_command_name,
    format_category_list,
    format_results,
    list_categories,
    parse_description_from_help,
    run_search,
    search_category,
    search_intent,
    search_keyword,
)


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
            "  printf 'category = [\"working-dir\", \"parking\"]\\n'\n"
            "  printf 'keywords = [\"save\", \"shelve\", \"stash\"]\\n'\n"
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
            f"DESTRUCTIVE regression in !intent: 'hug w wipdel' surfaced for "
            f"'save my work': {cmds}"
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
            CommandInfo(command=f"hug cmd{i}", description=f"d{i}", categories=[])
            for i in range(3)
        ]
        out = format_results(cmds, total=12)
        assert "Showing top 3 of 12" in out
        assert "--all" in out

    def test_format_results_no_overflow_when_within_cap(self):
        cmds = [
            CommandInfo(command=f"hug cmd{i}", description=f"d{i}", categories=[])
            for i in range(3)
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

        header, data, footer = format_category_page(
            self._meta(), [], width=72, split_streams=True
        )
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
