"""Tests for help_search.py — topic search for hug help."""

import json

import pytest

from help_search import (
    CommandInfo,
    MatchSpec,
    collect_metadata,
    derive_command_name,
    format_results,
    list_categories,
    parse_description_from_help,
    run_search,
    search_category,
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
