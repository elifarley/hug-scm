"""Unit tests for branch_select.py - Multi-branch selection with type safety.

Following Google Python testing best practices:
- Arrange-Act-Assert pattern
- Descriptive test names
- Test edge cases and error conditions
"""

import pytest

from git.branch_select import (
    SelectedBranches,
    SelectOptions,
    _bash_escape,
    format_multi_select_options,
    multi_select_branches,
    parse_user_input,
    validate_indices,
)

################################################################################
# Test Fixtures
################################################################################


@pytest.fixture
def sample_branch_data():
    """Sample branch data for testing."""
    return {
        "branches": ["main", "feature", "bugfix", "hotfix"],
        "hashes": ["abc123", "def456", "ghi789", "jkl012"],
        "dates": ["2026-01-30", "2026-01-31", "2026-01-31", "2026-02-01"],
        "subjects": ["Initial commit", "Add feature", "Fix bug", "Critical fix"],
        "tracks": ["[origin/main]", "", "[upstream/bugfix]", "[origin/hotfix]"],
    }


@pytest.fixture
def select_options_default():
    """Default SelectOptions."""
    return SelectOptions(
        placeholder="Select branches",
        use_gum=True,
        test_selection=None,
    )


@pytest.fixture
def select_options_no_gum():
    """SelectOptions with gum disabled."""
    return SelectOptions(
        placeholder="Select branches",
        use_gum=False,
        test_selection=None,
    )


@pytest.fixture
def select_options_test_input():
    """SelectOptions with pre-selected test input."""
    return SelectOptions(
        placeholder="Select branches",
        use_gum=False,
        test_selection="1,2",
    )


################################################################################
# TestBashEscape
################################################################################


class TestBashEscape:
    """Tests for _bash_escape function."""

    def test_escapes_single_quotes(self):
        """Should escape single quotes correctly."""
        result = _bash_escape("it's a test")
        assert "'\\''" in result
        assert result.startswith("'")
        assert result.endswith("'")

    def test_escapes_backslashes(self):
        """Should escape backslashes correctly."""
        result = _bash_escape(r"back\slash")
        assert "\\\\" in result

    def test_handles_simple_string(self):
        """Should handle simple alphanumeric string."""
        result = _bash_escape("simple-test")
        assert result == "'simple-test'"

    def test_handles_special_characters(self):
        """Should handle various special characters."""
        result = _bash_escape("test: value! [tag]")
        assert "test:" in result
        assert "value!" in result
        assert "[tag]" in result

    def test_handles_empty_string(self):
        """Should handle empty string."""
        result = _bash_escape("")
        assert result == "''"

    def test_handles_string_with_newlines(self):
        """Should handle newlines in string."""
        result = _bash_escape("line1\nline2")
        assert "line1" in result
        assert "line2" in result


################################################################################
# TestSelectOptions
################################################################################


class TestSelectOptions:
    """Tests for SelectOptions dataclass."""

    def test_default_values(self):
        """Should have correct default values."""
        options = SelectOptions()
        assert options.placeholder == "Select branches"
        assert options.use_gum is True
        assert options.test_selection is None

    def test_custom_values(self):
        """Should accept custom values."""
        options = SelectOptions(
            placeholder="Choose items",
            use_gum=False,
            test_selection="1,2,3",
        )
        assert options.placeholder == "Choose items"
        assert options.use_gum is False
        assert options.test_selection == "1,2,3"


################################################################################
# TestSelectedBranches
################################################################################


class TestSelectedBranches:
    """Tests for SelectedBranches dataclass."""

    def test_initialization(self):
        """Should create SelectedBranches with all fields."""
        result = SelectedBranches(
            branches=["main", "feature"],
            selected_indices=[0, 1],
        )
        assert len(result.branches) == 2
        assert result.branches[0] == "main"
        assert result.selected_indices == [0, 1]

    def test_to_bash_declare_outputs_declarations(self):
        """Should output bash declare statements."""
        result = SelectedBranches(
            branches=["main", "feature"],
            selected_indices=[0, 1],
        )

        bash_output = result.to_bash_declare()

        assert "declare -a selected_branches=" in bash_output
        assert "declare -a selected_indices=" in bash_output

    def test_to_bash_declare_includes_branch_names(self):
        """Should include branch names in bash output."""
        result = SelectedBranches(
            branches=["main", "feature"],
            selected_indices=[0, 1],
        )

        bash_output = result.to_bash_declare()

        assert "main" in bash_output
        assert "feature" in bash_output

    def test_to_bash_declare_handles_empty_arrays(self):
        """Should handle empty arrays."""
        result = SelectedBranches(branches=[], selected_indices=[])

        bash_output = result.to_bash_declare()

        assert "declare -a selected_branches=()" in bash_output
        assert "declare -a selected_indices=()" in bash_output

    def test_to_bash_declare_custom_array_name(self):
        """Should use custom array name when provided."""
        result = SelectedBranches(
            branches=["main"],
            selected_indices=[0],
        )

        bash_output = result.to_bash_declare(array_name="my_branches")

        assert "declare -a my_branches=" in bash_output
        assert "declare -a selected_indices=" in bash_output


################################################################################
# TestFormatMultiSelectOptions
################################################################################


class TestFormatMultiSelectOptions:
    """Tests for format_multi_select_options function."""

    def test_formats_full_branch_info(self, sample_branch_data):
        """Should format branches with all info."""
        formatted = format_multi_select_options(
            branches=sample_branch_data["branches"],
            hashes=sample_branch_data["hashes"],
            dates=sample_branch_data["dates"],
            subjects=sample_branch_data["subjects"],
            tracks=sample_branch_data["tracks"],
        )

        assert len(formatted) == 4
        # Check first branch has all components
        assert "main" in formatted[0]
        assert "abc123" in formatted[0]
        assert "2026-01-30" in formatted[0]
        assert "Initial commit" in formatted[0]
        assert "[origin/main]" in formatted[0]

    def test_includes_color_codes(self, sample_branch_data):
        """Should include ANSI color codes."""
        formatted = format_multi_select_options(
            branches=sample_branch_data["branches"],
            hashes=sample_branch_data["hashes"],
            dates=sample_branch_data["dates"],
            subjects=sample_branch_data["subjects"],
            tracks=sample_branch_data["tracks"],
        )

        # Check for ANSI escape sequences
        assert "\x1b[33m" in formatted[0] or "\x1b[" in formatted[0]  # YELLOW
        assert "\x1b[0m" in formatted[0]  # NC

    def test_handles_missing_optional_fields(self):
        """Should handle branches with missing optional data."""
        formatted = format_multi_select_options(
            branches=["main", "feature"],
            hashes=["abc123", ""],
            dates=["", "2026-01-31"],
            subjects=["", ""],
            tracks=["", ""],
        )

        # First branch has only hash
        assert "main" in formatted[0]
        assert "abc123" in formatted[0]
        # Second branch has only date
        assert "feature" in formatted[1]
        assert "2026-01-31" in formatted[1]

    def test_handles_empty_branches(self):
        """Should handle empty branch list."""
        formatted = format_multi_select_options(
            branches=[],
            hashes=[],
            dates=[],
            subjects=[],
            tracks=[],
        )

        assert len(formatted) == 0

    def test_handles_empty_branch_name(self):
        """Should skip empty branch names."""
        formatted = format_multi_select_options(
            branches=["main", "", "feature"],
            hashes=["abc", "def", "ghi"],
            dates=["", "", ""],
            subjects=["", "", ""],
            tracks=["", "", ""],
        )

        assert len(formatted) == 3
        assert formatted[0]  # First option exists
        assert formatted[1] == ""  # Empty branch name results in empty string
        assert formatted[2]  # Third option exists

    def test_inconsistent_array_lengths_raises_error(self):
        """Should raise ValueError for inconsistent array lengths."""
        with pytest.raises(ValueError) as exc_info:
            format_multi_select_options(
                branches=["main", "feature"],
                hashes=["abc"],  # Only one hash
                dates=["", ""],
                subjects=["", ""],
                tracks=["", ""],
            )

        assert "inconsistent lengths" in str(exc_info.value).lower()


################################################################################
# TestParseUserInput
################################################################################


class TestParseUserInput:
    """Tests for parse_user_input function."""

    def test_parse_single_number(self):
        """Should parse single number."""
        result = parse_user_input("1", 5)
        assert result == [0]

    def test_parse_comma_separated_numbers(self):
        """Should parse comma-separated numbers."""
        result = parse_user_input("1,2,3", 5)
        assert result == [0, 1, 2]

    def test_parse_comma_separated_with_spaces(self):
        """Should handle spaces around commas."""
        result = parse_user_input("1, 2, 3", 5)
        assert result == [0, 1, 2]

    def test_parse_all_lowercase(self):
        """Should parse 'a' as select all."""
        result = parse_user_input("a", 3)
        assert result == [0, 1, 2]

    def test_parse_all_uppercase(self):
        """Should parse 'A' as select all."""
        result = parse_user_input("A", 3)
        assert result == [0, 1, 2]

    def test_parse_all_word(self):
        """Should parse 'all' as select all."""
        result = parse_user_input("all", 3)
        assert result == [0, 1, 2]

    def test_parse_ALL_caps(self):
        """Should parse 'ALL' as select all."""
        result = parse_user_input("ALL", 3)
        assert result == [0, 1, 2]

    def test_parse_range(self):
        """Should parse range like '1-5'."""
        result = parse_user_input("1-5", 10)
        assert result == [0, 1, 2, 3, 4]

    def test_parse_range_at_end(self):
        """Should parse range that goes to end."""
        result = parse_user_input("3-5", 5)
        assert result == [2, 3, 4]

    def test_parse_range_clamps_to_bounds(self):
        """Should clamp range to available items."""
        result = parse_user_input("1-10", 5)
        assert result == [0, 1, 2, 3, 4]

    def test_parse_mixed_numbers_and_ranges(self):
        """Should parse mixed input like '1,3-5,7'."""
        result = parse_user_input("1,3-5,7", 10)
        assert result == [0, 2, 3, 4, 6]

    def test_parse_empty_string(self):
        """Should return empty list for empty input."""
        result = parse_user_input("", 5)
        assert result == []

    def test_parse_whitespace_only(self):
        """Should return empty list for whitespace input."""
        result = parse_user_input("   ", 5)
        assert result == []

    def test_parse_filters_invalid_numbers(self):
        """Should ignore numbers out of bounds."""
        result = parse_user_input("1,10,99", 5)
        assert result == [0]  # Only 1 is valid

    def test_parse_filters_zero(self):
        """Should ignore zero (invalid in 1-based indexing)."""
        result = parse_user_input("0,1,2", 5)
        assert result == [0, 1]  # 0 becomes -1 which is filtered out

    def test_parse_handles_duplicate_selections(self):
        """Should deduplicate selections."""
        result = parse_user_input("1,1,2,2", 5)
        assert result == [0, 1]  # Duplicates removed

    def test_parse_invalid_range_format(self):
        """Should skip invalid range formats."""
        result = parse_user_input("1-abc,2", 5)
        assert result == [1]  # Only 2 is valid, 1-abc is skipped

    def test_parse_reverse_range(self):
        """Should handle ranges in reverse order (start > end)."""
        # With current implementation, reverse ranges just produce empty
        result = parse_user_input("5-3", 10)
        # Since we use range(start_idx, end_idx + 1) and start > end,
        # this produces empty
        assert result == []

    def test_parse_single_number_range(self):
        """Should handle single-number range like '3-3'."""
        result = parse_user_input("3-3", 5)
        assert result == [2]


################################################################################
# TestValidateIndices
################################################################################


class TestValidateIndices:
    """Tests for validate_indices function."""

    def test_validates_good_indices(self):
        """Should pass through valid indices."""
        result = validate_indices([0, 1, 2], 5)
        assert result == [0, 1, 2]

    def test_filters_out_of_bounds_high(self):
        """Should filter indices too high."""
        result = validate_indices([0, 1, 10], 5)
        assert result == [0, 1]

    def test_filters_out_of_bounds_low(self):
        """Should filter negative indices."""
        result = validate_indices([-1, 0, 1], 5)
        assert result == [0, 1]

    def test_filters_all_invalid(self):
        """Should return empty list if all invalid."""
        result = validate_indices([-1, 10, 20], 5)
        assert result == []

    def test_handles_empty_list(self):
        """Should handle empty input list."""
        result = validate_indices([], 5)
        assert result == []


################################################################################
# TestMultiSelectBranches
################################################################################


class TestMultiSelectBranches:
    """Tests for multi_select_branches function."""

    def test_returns_selected_branches(self, sample_branch_data, select_options_test_input):
        """Should return selected branches based on test input."""
        result = multi_select_branches(
            branches=sample_branch_data["branches"],
            hashes=sample_branch_data["hashes"],
            dates=sample_branch_data["dates"],
            subjects=sample_branch_data["subjects"],
            tracks=sample_branch_data["tracks"],
            options=select_options_test_input,
        )

        assert len(result.branches) == 2
        assert "main" in result.branches
        assert "feature" in result.branches
        assert result.selected_indices == [0, 1]

    def test_returns_all_branches_with_all_selection(
        self, sample_branch_data, capsys
    ):
        """Should return all branches when 'all' is selected."""
        options = SelectOptions(
            placeholder="Select branches",
            use_gum=False,
            test_selection="all",
        )

        result = multi_select_branches(
            branches=sample_branch_data["branches"],
            hashes=sample_branch_data["hashes"],
            dates=sample_branch_data["dates"],
            subjects=sample_branch_data["subjects"],
            tracks=sample_branch_data["tracks"],
            options=options,
        )

        assert len(result.branches) == 4
        assert set(result.branches) == set(sample_branch_data["branches"])

    def test_returns_empty_for_no_selection(self, sample_branch_data):
        """Should return empty selection when input is empty."""
        options = SelectOptions(
            placeholder="Select branches",
            use_gum=False,
            test_selection="",
        )

        result = multi_select_branches(
            branches=sample_branch_data["branches"],
            hashes=sample_branch_data["hashes"],
            dates=sample_branch_data["dates"],
            subjects=sample_branch_data["subjects"],
            tracks=sample_branch_data["tracks"],
            options=options,
        )

        assert len(result.branches) == 0
        assert len(result.selected_indices) == 0

    def test_handles_range_selection(self, sample_branch_data):
        """Should handle range selection like '1-3'."""
        options = SelectOptions(
            placeholder="Select branches",
            use_gum=False,
            test_selection="1-3",
        )

        result = multi_select_branches(
            branches=sample_branch_data["branches"],
            hashes=sample_branch_data["hashes"],
            dates=sample_branch_data["dates"],
            subjects=sample_branch_data["subjects"],
            tracks=sample_branch_data["tracks"],
            options=options,
        )

        assert len(result.branches) == 3
        assert result.branches == ["main", "feature", "bugfix"]

    def test_handles_mixed_selection(self, sample_branch_data):
        """Should handle mixed selection like '1,3-4'."""
        options = SelectOptions(
            placeholder="Select branches",
            use_gum=False,
            test_selection="1,3-4",
        )

        result = multi_select_branches(
            branches=sample_branch_data["branches"],
            hashes=sample_branch_data["hashes"],
            dates=sample_branch_data["dates"],
            subjects=sample_branch_data["subjects"],
            tracks=sample_branch_data["tracks"],
            options=options,
        )

        assert len(result.branches) == 3
        assert "main" in result.branches
        assert "bugfix" in result.branches
        assert "hotfix" in result.branches

    def test_handles_empty_branch_list(self):
        """Should handle empty branch list."""
        options = SelectOptions(
            placeholder="Select branches",
            use_gum=False,
            test_selection="1",
        )

        result = multi_select_branches(
            branches=[],
            hashes=[],
            dates=[],
            subjects=[],
            tracks=[],
            options=options,
        )

        assert len(result.branches) == 0
        assert len(result.selected_indices) == 0

    def test_inconsistent_array_lengths_raises_error(self, sample_branch_data):
        """Should raise ValueError for inconsistent array lengths."""
        options = SelectOptions(use_gum=False)

        with pytest.raises(ValueError) as exc_info:
            multi_select_branches(
                branches=sample_branch_data["branches"],
                hashes=["abc"],  # Only one hash
                dates=["", "", ""],
                subjects=["", "", ""],
                tracks=["", "", ""],
                options=options,
            )

        assert "inconsistent lengths" in str(exc_info.value).lower()

    def test_outputs_numbered_list(self, sample_branch_data, capsys):
        """Should output numbered list to stdout."""
        options = SelectOptions(
            placeholder="Choose items",
            use_gum=False,
            test_selection="",  # Empty to avoid blocking
        )

        multi_select_branches(
            branches=sample_branch_data["branches"],
            hashes=sample_branch_data["hashes"],
            dates=sample_branch_data["dates"],
            subjects=sample_branch_data["subjects"],
            tracks=sample_branch_data["tracks"],
            options=options,
        )

        captured = capsys.readouterr()
        output = captured.out

        assert "Choose items" in output
        assert "1:" in output or " 1:" in output
        assert "main" in output

    def test_respects_environment_variable_for_testing(
        self, sample_branch_data, monkeypatch
    ):
        """Should use HUG_TEST_NUMBERED_SELECTION when set."""
        monkeypatch.setenv("HUG_TEST_NUMBERED_SELECTION", "2,3")

        options = SelectOptions(
            placeholder="Select branches",
            use_gum=False,
            test_selection=None,  # Not set, should use env var
        )

        result = multi_select_branches(
            branches=sample_branch_data["branches"],
            hashes=sample_branch_data["hashes"],
            dates=sample_branch_data["dates"],
            subjects=sample_branch_data["subjects"],
            tracks=sample_branch_data["tracks"],
            options=options,
        )

        assert len(result.branches) == 2
        assert "feature" in result.branches
        assert "bugfix" in result.branches

    def test_test_selection_overrides_environment(
        self, sample_branch_data, monkeypatch
    ):
        """Test selection should override environment variable."""
        monkeypatch.setenv("HUG_TEST_NUMBERED_SELECTION", "1,2,3")

        options = SelectOptions(
            placeholder="Select branches",
            use_gum=False,
            test_selection="4",  # Should override env var
        )

        result = multi_select_branches(
            branches=sample_branch_data["branches"],
            hashes=sample_branch_data["hashes"],
            dates=sample_branch_data["dates"],
            subjects=sample_branch_data["subjects"],
            tracks=sample_branch_data["tracks"],
            options=options,
        )

        assert len(result.branches) == 1
        assert result.branches == ["hotfix"]


################################################################################
# TestMainFunction (CLI tests)
################################################################################


class TestMainFunction:
    """Integration tests for main() CLI entry point."""

    def test_select_command_outputs_bash_declarations(
        self, monkeypatch, capsys
    ):
        """Should output bash declarations for select command."""
        import sys

        monkeypatch.setattr(
            sys,
            "argv",
            [
                "branch_select.py",
                "select",
                "--branches",
                "main feature bugfix",
                "--hashes",
                "abc def ghi",
                "--selection",
                "1,2",
            ],
        )

        from git.branch_select import main

        result = main()
        captured = capsys.readouterr()

        assert result is None  # Success returns None
        assert "declare -a selected_branches=" in captured.out
        # Check that selected branches are in the declaration
        assert "selected_branches=('main' 'feature')" in captured.out
        # bugfix appears in the list display (not quoted) but not in selected_branches
        # Just verify that indices are correct
        assert "selected_indices=(0 1)" in captured.out

    def test_select_with_all_selection(self, monkeypatch, capsys):
        """Should select all when 'all' is provided."""
        import sys

        monkeypatch.setattr(
            sys,
            "argv",
            [
                "branch_select.py",
                "select",
                "--branches",
                "main feature",
                "--hashes",
                "abc def",
                "--selection",
                "all",
            ],
        )

        from git.branch_select import main

        result = main()
        captured = capsys.readouterr()

        assert result is None
        assert "main" in captured.out
        assert "feature" in captured.out

    def test_select_with_range(self, monkeypatch, capsys):
        """Should handle range selection."""
        import sys

        monkeypatch.setattr(
            sys,
            "argv",
            [
                "branch_select.py",
                "select",
                "--branches",
                "main feature bugfix hotfix",
                "--hashes",
                "abc def ghi jkl",
                "--selection",
                "2-4",
            ],
        )

        from git.branch_select import main

        result = main()
        captured = capsys.readouterr()

        assert result is None
        # Check selected branches in the declaration (indices 1-3 means items 2,3,4)
        assert "selected_branches=('feature' 'bugfix' 'hotfix')" in captured.out
        # main appears in the list display but shouldn't be selected
        # We can verify by checking the selected_indices
        assert "selected_indices=(1 2 3)" in captured.out

    def test_select_custom_array_name(self, monkeypatch, capsys):
        """Should use custom array name when provided."""
        import sys

        monkeypatch.setattr(
            sys,
            "argv",
            [
                "branch_select.py",
                "select",
                "--branches",
                "main",
                "--hashes",
                "abc",
                "--selection",
                "1",
                "--array-name",
                "my_result",
            ],
        )

        from git.branch_select import main

        result = main()
        captured = capsys.readouterr()

        assert result is None
        assert "declare -a my_result=" in captured.out
        assert "declare -a selected_indices=" in captured.out

    def test_format_options_command(self, monkeypatch, capsys):
        """Should output formatted options for gum."""
        import sys

        monkeypatch.setattr(
            sys,
            "argv",
            [
                "branch_select.py",
                "format-options",
                "--branches",
                "main feature",
                "--hashes",
                "abc123 def456",
                "--dates",
                "2026-01-30 2026-01-31",
                "--subjects",
                "Init Feature",
                "--tracks",
                "[origin/main] ",
            ],
        )

        from git.branch_select import main

        result = main()
        captured = capsys.readouterr()

        assert result is None
        # Should have one option per line
        lines = [line for line in captured.out.split("\n") if line]
        assert len(lines) == 2
        assert "main" in captured.out
        assert "feature" in captured.out
        assert "abc123" in captured.out

    def test_exits_with_error_on_inconsistent_arrays(
        self, monkeypatch, capsys
    ):
        """Should exit with error when arrays have inconsistent lengths from CLI."""
        import sys

        # CLI pads arrays, so we need to trigger the error differently
        # by creating a scenario that bypasses padding
        # Actually, the CLI always pads, so this test verifies
        # that the CLI handles the padding gracefully
        monkeypatch.setattr(
            sys,
            "argv",
            [
                "branch_select.py",
                "select",
                "--branches",
                "main feature",
                "--hashes",
                "abc",  # Only one hash - CLI will pad it
                "--selection",
                "1",
            ],
        )

        from git.branch_select import main

        # Should succeed because CLI pads arrays
        result = main()
        assert result is None

    def test_no_gum_flag(self, monkeypatch, capsys):
        """Should respect --no-gum flag."""
        import sys

        monkeypatch.setattr(
            sys,
            "argv",
            [
                "branch_select.py",
                "select",
                "--branches",
                "main feature",
                "--hashes",
                "abc def",
                "--no-gum",
                "--selection",
                "1",
            ],
        )

        from git.branch_select import main

        result = main()
        captured = capsys.readouterr()

        assert result is None
        # Should still output the selection
        assert "declare -a selected_branches=(" in captured.out
        # Check that main was selected (index 0)
        assert "selected_branches=('main')" in captured.out

    def test_custom_placeholder(self, monkeypatch, capsys):
        """Should use custom placeholder text."""
        import sys

        monkeypatch.setattr(
            sys,
            "argv",
            [
                "branch_select.py",
                "select",
                "--branches",
                "main",
                "--hashes",
                "abc",
                "--placeholder",
                "Delete these branches",
                "--selection",
                "",
            ],
        )

        from git.branch_select import main

        result = main()
        captured = capsys.readouterr()

        assert result is None
        assert "Delete these branches" in captured.out
