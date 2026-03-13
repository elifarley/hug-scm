"""Unit tests for tag_select.py - Tag selection with type safety.

Following Google Python testing best practices:
- Arrange-Act-Assert pattern
- Descriptive test names
- Test edge cases and error conditions
- Mock subprocess calls to avoid external dependencies
"""

import subprocess
from unittest.mock import patch

import pytest

from git.tag_select import (
    TagFilterOptions,
    TagInfo,
    TagSelectionResult,
    _bash_escape,
    _cmd_prepare,
    _cmd_select,
    _run_git,
    filter_tags,
    format_display_rows,
    load_tags,
    parse_numbered_input,
    tags_to_bash_declare,
    to_bash_declare,
)

################################################################################
# Test Fixtures
################################################################################


@pytest.fixture
def sample_tags():
    """A small set of TagInfo records for pure-logic tests."""
    return [
        TagInfo(
            name="v2.0.0",
            hash="abc1234",
            tag_type="annotated",
            subject="Release 2.0",
            date="2026-03-10 12:00:00 +0000",
            signature="",
            is_current=True,
        ),
        TagInfo(
            name="v1.1.0",
            hash="def5678",
            tag_type="lightweight",
            subject="Quick patch",
            date="",
            signature="",
            is_current=False,
        ),
        TagInfo(
            name="v1.0.0",
            hash="789abcd",
            tag_type="signed",
            subject="First stable release",
            date="2026-01-01 10:00:00 +0000",
            signature="verified",
            is_current=False,
        ),
    ]


################################################################################
# TestTagInfo — data model construction
################################################################################


class TestTagInfo:
    """Tests for the TagInfo dataclass."""

    def test_basic_construction(self):
        """Should store all fields exactly as given."""
        tag = TagInfo(
            name="v1.0.0",
            hash="abc1234",
            tag_type="lightweight",
            subject="Initial",
            date="",
            signature="",
            is_current=False,
        )
        assert tag.name == "v1.0.0"
        assert tag.hash == "abc1234"
        assert tag.tag_type == "lightweight"
        assert tag.subject == "Initial"
        assert tag.date == ""
        assert tag.signature == ""
        assert tag.is_current is False

    def test_annotated_tag_with_date(self):
        """Annotated tags carry a tagger date and can be current."""
        tag = TagInfo(
            name="v2.0.0",
            hash="def5678",
            tag_type="annotated",
            subject="Release",
            date="2026-03-10 12:00:00 +0000",
            signature="",
            is_current=True,
        )
        assert tag.date == "2026-03-10 12:00:00 +0000"
        assert tag.is_current is True

    def test_signed_tag_with_signature(self):
        """Signed tags carry a 'verified' signature field."""
        tag = TagInfo(
            name="v3.0.0",
            hash="ghi9012",
            tag_type="signed",
            subject="Signed release",
            date="2026-03-11 09:00:00 +0000",
            signature="verified",
            is_current=False,
        )
        assert tag.signature == "verified"
        assert tag.tag_type == "signed"


################################################################################
# TestTagFilterOptions
################################################################################


class TestTagFilterOptions:
    """Tests for the TagFilterOptions dataclass."""

    def test_defaults_to_no_filters(self):
        """Default construction should have no active filters."""
        opts = TagFilterOptions()
        assert opts.type_filter is None
        assert opts.pattern is None

    def test_type_filter_set(self):
        """Should accept a type filter string."""
        opts = TagFilterOptions(type_filter="annotated")
        assert opts.type_filter == "annotated"

    def test_pattern_set(self):
        """Should accept a regex pattern string."""
        opts = TagFilterOptions(pattern=r"v1\.")
        assert opts.pattern == r"v1\."


################################################################################
# TestTagSelectionResult
################################################################################


class TestTagSelectionResult:
    """Tests for the TagSelectionResult dataclass."""

    def test_selected_status(self):
        """Selected result should carry the selected tag names."""
        result = TagSelectionResult(status="selected", tags=["v1.0.0", "v2.0.0"], indices=[0, 1])
        assert result.status == "selected"
        assert len(result.tags) == 2
        assert result.indices == [0, 1]

    def test_cancelled_status(self):
        """Cancelled result should have empty tags and indices."""
        result = TagSelectionResult(status="cancelled", tags=[], indices=[])
        assert result.status == "cancelled"
        assert result.tags == []
        assert result.indices == []

    def test_no_tags_status(self):
        """no_tags status indicates an empty repository."""
        result = TagSelectionResult(status="no_tags", tags=[], indices=[])
        assert result.status == "no_tags"

    def test_no_matches_status(self):
        """no_matches status indicates filters produced no results."""
        result = TagSelectionResult(status="no_matches", tags=[], indices=[])
        assert result.status == "no_matches"


################################################################################
# TestBashEscape
################################################################################


class TestBashEscape:
    """Tests for _bash_escape() — safe single-quote wrapping."""

    def test_simple_string(self):
        """Plain alphanumeric strings should be wrapped in single quotes."""
        assert _bash_escape("hello") == "'hello'"

    def test_string_with_single_quote(self):
        """Embedded single quotes should be escaped with the '\\'' idiom."""
        assert _bash_escape("it's") == "'it'\\''s'"

    def test_string_with_backslash(self):
        """Backslashes should be doubled so bash sees a literal backslash."""
        assert _bash_escape("path\\to") == "'path\\\\to'"

    def test_empty_string(self):
        """Empty string should produce two adjacent single quotes."""
        assert _bash_escape("") == "''"

    def test_string_with_spaces(self):
        """Spaces are safe inside single quotes."""
        assert _bash_escape("hello world") == "'hello world'"

    def test_string_with_special_shell_chars(self):
        """Characters like $, !, *, ? are safe inside single quotes."""
        result = _bash_escape("$HOME/*.txt")
        assert result == "'$HOME/*.txt'"


################################################################################
# TestFilterTags
################################################################################


class TestFilterTags:
    """Tests for filter_tags() — pure filtering logic."""

    def test_no_filters_returns_all(self, sample_tags):
        """Empty TagFilterOptions should return all tags unchanged."""
        options = TagFilterOptions()
        result = filter_tags(sample_tags, options)
        assert len(result) == 3

    def test_type_filter_annotated(self, sample_tags):
        """type_filter='annotated' should return only annotated tags."""
        options = TagFilterOptions(type_filter="annotated")
        result = filter_tags(sample_tags, options)
        assert len(result) == 1
        assert result[0].name == "v2.0.0"

    def test_type_filter_lightweight(self, sample_tags):
        """type_filter='lightweight' should return only lightweight tags."""
        options = TagFilterOptions(type_filter="lightweight")
        result = filter_tags(sample_tags, options)
        assert len(result) == 1
        assert result[0].name == "v1.1.0"

    def test_type_filter_signed(self, sample_tags):
        """type_filter='signed' should return only signed tags."""
        options = TagFilterOptions(type_filter="signed")
        result = filter_tags(sample_tags, options)
        assert len(result) == 1
        assert result[0].name == "v1.0.0"

    def test_pattern_filter(self, sample_tags):
        """Regex pattern should match tag names."""
        options = TagFilterOptions(pattern=r"v1\.")
        result = filter_tags(sample_tags, options)
        assert len(result) == 2
        assert {t.name for t in result} == {"v1.1.0", "v1.0.0"}

    def test_combined_filters(self, sample_tags):
        """Both type_filter and pattern should be applied (AND logic)."""
        options = TagFilterOptions(type_filter="lightweight", pattern=r"v1\.")
        result = filter_tags(sample_tags, options)
        assert len(result) == 1
        assert result[0].name == "v1.1.0"

    def test_no_matches(self, sample_tags):
        """Pattern that matches nothing should return empty list."""
        options = TagFilterOptions(pattern=r"v99\.")
        result = filter_tags(sample_tags, options)
        assert len(result) == 0

    def test_empty_input(self):
        """Empty tag list should return empty list regardless of options."""
        options = TagFilterOptions()
        result = filter_tags([], options)
        assert result == []

    def test_invalid_regex_treated_as_literal(self, sample_tags):
        """Invalid regex patterns should fall back to literal substring matching.

        '[invalid' is not a valid regex, so it falls back to checking whether
        '[invalid' is a substring of any tag name (it isn't → empty result).
        """
        options = TagFilterOptions(pattern="[invalid")
        result = filter_tags(sample_tags, options)
        assert len(result) == 0

    def test_invalid_regex_literal_match(self):
        """Invalid regex that IS a literal substring should still match.

        '[invalid' is not a valid regex (unmatched bracket).  The fallback
        checks whether the raw pattern string is a substring of the tag name.
        A tag literally named '[invalid-release' should therefore be matched.
        """
        tags = [
            TagInfo(
                name="[invalid-release",
                hash="abc1234",
                tag_type="lightweight",
                subject="special",
                date="",
                signature="",
                is_current=False,
            )
        ]
        # '[invalid' is an invalid regex (unclosed bracket); as a literal
        # substring it does appear inside '[invalid-release', so it should match.
        options = TagFilterOptions(pattern="[invalid")
        result = filter_tags(tags, options)
        assert len(result) == 1

    def test_preserves_input_order(self, sample_tags):
        """Filtering should preserve the original ordering of tags."""
        options = TagFilterOptions(pattern=r"v")
        result = filter_tags(sample_tags, options)
        assert [t.name for t in result] == ["v2.0.0", "v1.1.0", "v1.0.0"]


################################################################################
# TestFormatDisplayRows
################################################################################


class TestFormatDisplayRows:
    """Tests for format_display_rows() — display row construction."""

    def test_basic_formatting(self, sample_tags):
        """Should produce one formatted row per tag."""
        rows = format_display_rows(sample_tags)
        assert len(rows) == 3

    def test_current_tag_has_star_prefix(self, sample_tags):
        """Current tag should start with '* tagname'."""
        rows = format_display_rows(sample_tags)
        # v2.0.0 has is_current=True
        assert rows[0].startswith("* v2.0.0")

    def test_non_current_tag_no_star(self, sample_tags):
        """Non-current tags should NOT start with '*'."""
        rows = format_display_rows(sample_tags)
        # v1.1.0 has is_current=False
        assert not rows[1].startswith("*")
        assert "v1.1.0" in rows[1]

    def test_type_indicator_lightweight(self, sample_tags):
        """Lightweight tags should show [L] indicator."""
        rows = format_display_rows(sample_tags)
        assert "[L]" in rows[1]  # v1.1.0 is lightweight

    def test_type_indicator_annotated(self, sample_tags):
        """Annotated tags should show [A] indicator."""
        rows = format_display_rows(sample_tags)
        assert "[A]" in rows[0]  # v2.0.0 is annotated

    def test_type_indicator_signed(self, sample_tags):
        """Signed tags should show [S] indicator."""
        rows = format_display_rows(sample_tags)
        assert "[S]" in rows[2]  # v1.0.0 is signed

    def test_hash_included(self, sample_tags):
        """Row should include the short commit hash."""
        rows = format_display_rows(sample_tags)
        assert "abc1234" in rows[0]

    def test_subject_included(self, sample_tags):
        """Row should include the tag/commit subject."""
        rows = format_display_rows(sample_tags)
        assert "Release 2.0" in rows[0]

    def test_empty_list(self):
        """Empty input should produce empty list."""
        rows = format_display_rows([])
        assert rows == []

    def test_unknown_type_produces_no_indicator(self):
        """Tags with an unrecognized type should omit the type indicator."""
        tag = TagInfo(
            name="old-style",
            hash="aaa1111",
            tag_type="unknown",
            subject="Legacy",
            date="",
            signature="",
            is_current=False,
        )
        rows = format_display_rows([tag])
        assert len(rows) == 1
        # Should not contain any of the known indicators
        assert "[L]" not in rows[0]
        assert "[A]" not in rows[0]
        assert "[S]" not in rows[0]
        assert "old-style" in rows[0]


################################################################################
# TestParseNumberedInput
################################################################################


class TestParseNumberedInput:
    """Tests for parse_numbered_input() — user selection input parsing."""

    def test_single_number(self):
        """Single 1-based number should return corresponding 0-based index."""
        assert parse_numbered_input("3", 10) == [2]

    def test_comma_separated(self):
        """Comma-separated numbers should return all corresponding indices."""
        assert parse_numbered_input("1,3,5", 10) == [0, 2, 4]

    def test_range(self):
        """Inclusive range '2-4' should expand to [1, 2, 3]."""
        assert parse_numbered_input("2-4", 10) == [1, 2, 3]

    def test_mixed(self):
        """Mixed format with commas and ranges should be parsed correctly."""
        assert parse_numbered_input("1,3-5,7", 10) == [0, 2, 3, 4, 6]

    def test_all_keyword(self):
        """'all' should select all available items."""
        assert parse_numbered_input("all", 3) == [0, 1, 2]

    def test_a_keyword(self):
        """'a' should select all available items."""
        assert parse_numbered_input("a", 3) == [0, 1, 2]

    def test_ALL_uppercase(self):
        """'ALL' (uppercase) should also select all items."""
        assert parse_numbered_input("ALL", 3) == [0, 1, 2]

    def test_empty_string(self):
        """Empty string should produce no selection."""
        assert parse_numbered_input("", 10) == []

    def test_whitespace_only(self):
        """Whitespace-only string should produce no selection."""
        assert parse_numbered_input("  ", 10) == []

    def test_out_of_bounds_ignored(self):
        """Numbers outside [1, num_items] should be silently ignored.

        '0' is below the 1-based minimum; '99' exceeds num_items=5.
        Only '1' (index 0) is valid.
        """
        assert parse_numbered_input("0,1,99", 5) == [0]

    def test_invalid_text_ignored(self):
        """Non-numeric tokens should be silently ignored."""
        assert parse_numbered_input("abc,2", 10) == [1]

    def test_duplicates_removed(self):
        """Duplicate selections should be deduplicated."""
        assert parse_numbered_input("1,1,1", 10) == [0]

    def test_sorted_output(self):
        """Output indices should always be sorted ascending."""
        assert parse_numbered_input("5,1,3", 10) == [0, 2, 4]

    def test_spaces_around_numbers(self):
        """Spaces around numbers and around commas should be trimmed."""
        assert parse_numbered_input(" 1 , 3 ", 10) == [0, 2]

    def test_malformed_range_skipped(self):
        """Range tokens with non-numeric endpoints should be silently skipped."""
        # "a-b" contains a "-" but neither side is an integer
        assert parse_numbered_input("a-b,2", 10) == [1]

    def test_range_clamped_to_bounds(self):
        """Range endpoint beyond num_items should be clamped to num_items-1."""
        # Range 3-99 with num_items=5 should yield [2, 3, 4]
        assert parse_numbered_input("3-99", 5) == [2, 3, 4]

    def test_number_one_yields_index_zero(self):
        """'1' in 1-based input should always map to 0-based index 0."""
        assert parse_numbered_input("1", 1) == [0]


################################################################################
# TestToBashDeclare
################################################################################


class TestToBashDeclare:
    """Tests for to_bash_declare() — TagSelectionResult → bash variables."""

    def test_selected_result(self):
        """Selected result should output array and status variables."""
        result = TagSelectionResult(status="selected", tags=["v1.0.0", "v2.0.0"], indices=[0, 1])
        output = to_bash_declare(result)
        assert "declare -a selected_tags=(" in output
        assert "'v1.0.0'" in output
        assert "'v2.0.0'" in output
        assert "selection_status='selected'" in output

    def test_cancelled_result(self):
        """Cancelled result should output empty array and cancelled status."""
        result = TagSelectionResult(status="cancelled", tags=[], indices=[])
        output = to_bash_declare(result)
        assert "declare -a selected_tags=()" in output
        assert "selection_status='cancelled'" in output

    def test_custom_array_name(self):
        """array_name parameter should rename the output array variable."""
        result = TagSelectionResult(status="selected", tags=["v1.0.0"], indices=[0])
        output = to_bash_declare(result, array_name="my_tags")
        assert "declare -a my_tags=(" in output
        assert "selected_tags" not in output

    def test_tag_with_special_characters(self):
        """Tags with single quotes should be properly escaped."""
        result = TagSelectionResult(status="selected", tags=["release/v1.0's"], indices=[0])
        output = to_bash_declare(result)
        # The escaped form should appear; the raw single quote should not
        assert "release/v1.0" in output
        assert "selection_status='selected'" in output

    def test_no_tags_result(self):
        """no_tags status should be faithfully serialized."""
        result = TagSelectionResult(status="no_tags", tags=[], indices=[])
        output = to_bash_declare(result)
        assert "selection_status='no_tags'" in output

    def test_no_matches_result(self):
        """no_matches status should be faithfully serialized."""
        result = TagSelectionResult(status="no_matches", tags=[], indices=[])
        output = to_bash_declare(result)
        assert "selection_status='no_matches'" in output

    def test_multiple_tags_all_present(self):
        """All selected tag names should appear in the output array."""
        tags = ["v1.0.0", "v2.0.0", "v3.0.0"]
        result = TagSelectionResult(status="selected", tags=tags, indices=[0, 1, 2])
        output = to_bash_declare(result)
        for t in tags:
            assert f"'{t}'" in output


################################################################################
# TestTagsToBashDeclare
################################################################################


class TestTagsToBashDeclare:
    """Tests for tags_to_bash_declare() — prepare-mode bash variable output."""

    def test_prepare_output(self, sample_tags):
        """Should emit filtered_tags, formatted_options, status, and count."""
        formatted = [
            "* v2.0.0 [A] abc1234 Release 2.0",
            "v1.1.0 [L] def5678 Quick patch",
            "v1.0.0 [S] 789abcd First stable release",
        ]
        output = tags_to_bash_declare(sample_tags, formatted)
        assert "declare -a filtered_tags=(" in output
        assert "declare -a formatted_options=(" in output
        assert "selection_status='ready'" in output
        assert "tag_count=3" in output

    def test_empty_tags(self):
        """Empty tag list should produce no_tags status with count=0."""
        output = tags_to_bash_declare([], [])
        assert "selection_status='no_tags'" in output
        assert "tag_count=0" in output

    def test_tag_names_in_filtered_array(self, sample_tags):
        """Tag names should appear in the filtered_tags array."""
        formatted = ["row1", "row2", "row3"]
        output = tags_to_bash_declare(sample_tags, formatted)
        assert "'v2.0.0'" in output
        assert "'v1.1.0'" in output
        assert "'v1.0.0'" in output

    def test_formatted_options_in_array(self, sample_tags):
        """Formatted display rows should appear in the formatted_options array."""
        formatted = ["* v2.0.0 [A] abc1234 Release 2.0"]
        single_tag = [sample_tags[0]]
        output = tags_to_bash_declare(single_tag, formatted)
        # The formatted row (escaped) should be inside formatted_options
        assert "formatted_options" in output
        assert "Release 2.0" in output

    def test_empty_tags_also_has_empty_arrays(self):
        """Empty tags should still declare the arrays (just empty)."""
        output = tags_to_bash_declare([], [])
        assert "declare -a filtered_tags=()" in output
        assert "declare -a formatted_options=()" in output


################################################################################
# TestRunGit — subprocess helper
################################################################################


class TestRunGit:
    """Tests for _run_git() — subprocess helper with timeout / not-found handling."""

    @patch("git.tag_select.subprocess.run")
    def test_successful_command_returns_stripped_stdout(self, mock_run):
        """Successful git call should return stripped stdout."""

        mock_run.return_value.returncode = 0
        mock_run.return_value.stdout = "  v1.0.0\n"
        result = _run_git(["tag"])
        assert result == "v1.0.0"

    @patch("git.tag_select.subprocess.run")
    def test_non_zero_exit_without_check_returns_empty(self, mock_run):
        """Non-zero exit without check=True should return empty string, not raise."""

        mock_run.return_value.returncode = 1
        mock_run.return_value.stdout = ""
        result = _run_git(["describe", "--tags", "--exact-match"])
        assert result == ""

    @patch("git.tag_select.subprocess.run")
    def test_non_zero_exit_with_check_raises(self, mock_run):
        """Non-zero exit with check=True should raise RuntimeError."""

        mock_run.return_value.returncode = 128
        mock_run.return_value.stdout = ""
        mock_run.return_value.stderr = "not a git repository"
        with pytest.raises(RuntimeError, match="failed"):
            _run_git(["tag"], check=True)

    @patch("git.tag_select.subprocess.run", side_effect=subprocess.TimeoutExpired(["git"], 10))
    def test_timeout_without_check_returns_empty(self, mock_run):
        """TimeoutExpired without check should return empty string."""

        result = _run_git(["tag"])
        assert result == ""

    @patch("git.tag_select.subprocess.run", side_effect=subprocess.TimeoutExpired(["git"], 10))
    def test_timeout_with_check_raises(self, mock_run):
        """TimeoutExpired with check=True should raise RuntimeError."""

        with pytest.raises(RuntimeError, match="git command failed"):
            _run_git(["tag"], check=True)

    @patch("git.tag_select.subprocess.run", side_effect=FileNotFoundError("git not found"))
    def test_git_not_found_without_check_returns_empty(self, mock_run):
        """FileNotFoundError (git not installed) without check should return empty."""

        result = _run_git(["tag"])
        assert result == ""

    @patch("git.tag_select.subprocess.run", side_effect=FileNotFoundError("git not found"))
    def test_git_not_found_with_check_raises(self, mock_run):
        """FileNotFoundError with check=True should raise RuntimeError."""

        with pytest.raises(RuntimeError, match="git command failed"):
            _run_git(["tag"], check=True)


################################################################################
# TestLoadTags — git subprocess integration (mocked)
################################################################################


class TestLoadTags:
    """Tests for load_tags() — git subprocess integration.

    All git calls are mocked through _run_git so tests remain hermetic.
    """

    @patch("git.tag_select._run_git")
    def test_empty_repo_no_tags(self, mock_run):
        """Should return empty list when git tag produces no output."""
        mock_run.return_value = ""
        result = load_tags()
        assert result == []

    @patch("git.tag_select._run_git")
    def test_lightweight_tag(self, mock_run):
        """Lightweight tag (cat-file → 'commit') should produce tag_type='lightweight'."""

        def side_effect(args, check=False):
            if args == ["tag", "--sort=-version:refname"]:
                return "v1.0.0"
            elif args[:2] == ["cat-file", "-t"]:
                return "commit"  # lightweight points directly to commit
            elif args[:2] == ["rev-parse", "--short"]:
                return "abc1234"
            elif args[:3] == ["log", "-n", "1"]:
                return "Initial commit"
            elif args[:2] == ["describe", "--tags"]:
                return ""
            return ""

        mock_run.side_effect = side_effect
        result = load_tags()
        assert len(result) == 1
        assert result[0].tag_type == "lightweight"
        assert result[0].name == "v1.0.0"
        assert result[0].hash == "abc1234"

    @patch("git.tag_select._run_git")
    def test_annotated_tag(self, mock_run):
        """Annotated tag (cat-file 'tag', verify-tag fails) is 'annotated'."""

        def side_effect(args, check=False):
            if args == ["tag", "--sort=-version:refname"]:
                return "v2.0.0"
            elif args[:2] == ["cat-file", "-t"]:
                return "tag"  # annotated or signed
            elif args[:2] == ["tag", "-l"] and any("taggerdate" in a for a in args):
                return "2026-03-10 12:00:00 +0000"
            elif args[:2] == ["tag", "-l"] and any("subject" in a for a in args):
                return "Release 2.0"
            elif args[:2] == ["rev-list", "-n"]:
                return "abc1234def5678901234567890123456789012345"
            elif args[:2] == ["verify-tag", "--quiet"]:
                if check:
                    raise RuntimeError("not a signed tag")
                return ""
            elif args[:2] == ["describe", "--tags"]:
                return ""
            return ""

        mock_run.side_effect = side_effect
        result = load_tags()
        assert len(result) == 1
        assert result[0].tag_type == "annotated"

    @patch("git.tag_select._run_git")
    def test_signed_tag(self, mock_run):
        """Signed tag (cat-file → 'tag', verify-tag succeeds) should produce tag_type='signed'."""

        def side_effect(args, check=False):
            if args == ["tag", "--sort=-version:refname"]:
                return "v3.0.0"
            elif args[:2] == ["cat-file", "-t"]:
                return "tag"
            elif args[:2] == ["tag", "-l"] and any("taggerdate" in a for a in args):
                return "2026-03-11 09:00:00 +0000"
            elif args[:2] == ["tag", "-l"] and any("subject" in a for a in args):
                return "Signed release"
            elif args[:2] == ["rev-list", "-n"]:
                return "abc1234def5678"
            elif args[:2] == ["verify-tag", "--quiet"]:
                return ""  # success = signed
            elif args[:2] == ["describe", "--tags"]:
                return ""
            return ""

        mock_run.side_effect = side_effect
        result = load_tags()
        assert len(result) == 1
        assert result[0].tag_type == "signed"
        assert result[0].signature == "verified"

    @patch("git.tag_select._run_git")
    def test_current_tag_detected(self, mock_run):
        """is_current should be True when HEAD exactly matches the tag."""

        def side_effect(args, check=False):
            if args == ["tag", "--sort=-version:refname"]:
                return "v1.0.0"
            elif args[:2] == ["describe", "--tags"]:
                return "v1.0.0"  # HEAD is on this tag
            elif args[:2] == ["cat-file", "-t"]:
                return "commit"
            elif args[:2] == ["rev-parse", "--short"]:
                return "abc1234"
            elif args[:3] == ["log", "-n", "1"]:
                return "Initial"
            return ""

        mock_run.side_effect = side_effect
        result = load_tags()
        assert result[0].is_current is True

    @patch("git.tag_select._run_git")
    def test_non_current_tag(self, mock_run):
        """is_current should be False when HEAD is not on this tag."""

        def side_effect(args, check=False):
            if args == ["tag", "--sort=-version:refname"]:
                return "v1.0.0"
            elif args[:2] == ["describe", "--tags"]:
                return "v2.0.0"  # HEAD is on a different tag
            elif args[:2] == ["cat-file", "-t"]:
                return "commit"
            elif args[:2] == ["rev-parse", "--short"]:
                return "abc1234"
            elif args[:3] == ["log", "-n", "1"]:
                return "Initial"
            return ""

        mock_run.side_effect = side_effect
        result = load_tags()
        assert result[0].is_current is False

    @patch("git.tag_select._run_git")
    def test_multiple_tags_preserve_sort_order(self, mock_run):
        """Tags should be returned in the order git tag outputs them."""

        def side_effect(args, check=False):
            if args == ["tag", "--sort=-version:refname"]:
                return "v2.0.0\nv1.1.0\nv1.0.0"
            elif args[:2] == ["cat-file", "-t"]:
                return "commit"
            elif args[:2] == ["rev-parse", "--short"]:
                return "abc1234"
            elif args[:3] == ["log", "-n", "1"]:
                return "Commit msg"
            elif args[:2] == ["describe", "--tags"]:
                return ""
            return ""

        mock_run.side_effect = side_effect
        result = load_tags()
        assert len(result) == 3
        assert [t.name for t in result] == ["v2.0.0", "v1.1.0", "v1.0.0"]

    @patch("git.tag_select._run_git")
    def test_tag_names_with_newlines_sanitized(self, mock_run):
        """Newlines in tag name/hash/subject should be stripped defensively."""

        def side_effect(args, check=False):
            if args == ["tag", "--sort=-version:refname"]:
                return "v1.0.0"
            elif args[:2] == ["cat-file", "-t"]:
                return "commit"
            elif args[:2] == ["rev-parse", "--short"]:
                return "abc1234\n"  # trailing newline from git
            elif args[:3] == ["log", "-n", "1"]:
                return "Message\r\n"
            elif args[:2] == ["describe", "--tags"]:
                return ""
            return ""

        mock_run.side_effect = side_effect
        result = load_tags()
        assert "\n" not in result[0].hash
        assert "\r" not in result[0].subject


################################################################################
# TestCLIPrepare — _cmd_prepare internal function
################################################################################


class TestCLIPrepare:
    """Tests for _cmd_prepare() — the 'prepare' CLI command implementation."""

    @patch("git.tag_select.load_tags")
    def test_prepare_outputs_bash_declares(self, mock_load, sample_tags):
        """prepare should emit all four required bash variables."""
        mock_load.return_value = sample_tags

        output = _cmd_prepare(type_filter=None, pattern=None)
        assert "declare -a filtered_tags=" in output
        assert "declare -a formatted_options=" in output
        assert "selection_status='ready'" in output
        assert "tag_count=3" in output

    @patch("git.tag_select.load_tags")
    def test_prepare_with_type_filter(self, mock_load, sample_tags):
        """prepare with type_filter='annotated' should exclude other types."""
        mock_load.return_value = sample_tags

        output = _cmd_prepare(type_filter="annotated", pattern=None)
        assert "'v2.0.0'" in output
        assert "'v1.1.0'" not in output
        assert "'v1.0.0'" not in output

    @patch("git.tag_select.load_tags")
    def test_prepare_no_tags(self, mock_load):
        """prepare with no tags should report no_tags status."""
        mock_load.return_value = []

        output = _cmd_prepare(type_filter=None, pattern=None)
        assert "selection_status='no_tags'" in output

    @patch("git.tag_select.load_tags")
    def test_prepare_no_matches(self, mock_load, sample_tags):
        """prepare with pattern that matches nothing should report no_matches."""
        mock_load.return_value = sample_tags

        output = _cmd_prepare(type_filter=None, pattern="v99")
        assert "selection_status='no_matches'" in output


################################################################################
# TestCLISelect — _cmd_select internal function
################################################################################


class TestCLISelect:
    """Tests for _cmd_select() — the 'select' CLI command implementation."""

    @patch("git.tag_select.load_tags")
    @patch("builtins.input", return_value="1")
    def test_select_single(self, mock_input, mock_load, sample_tags):
        """Single-select mode should return the first-selected tag."""
        mock_load.return_value = sample_tags

        output = _cmd_select(type_filter=None, pattern=None, multi=False, prompt="Pick")
        assert "selection_status='selected'" in output
        assert "'v2.0.0'" in output

    @patch("git.tag_select.load_tags")
    @patch("builtins.input", return_value="1,3")
    def test_select_multi(self, mock_input, mock_load, sample_tags):
        """Multi-select mode should return all selected tags."""
        mock_load.return_value = sample_tags

        output = _cmd_select(type_filter=None, pattern=None, multi=True, prompt="Pick")
        assert "selection_status='selected'" in output
        assert "'v2.0.0'" in output
        assert "'v1.0.0'" in output

    @patch("git.tag_select.load_tags")
    @patch("builtins.input", return_value="")
    def test_select_empty_input_cancels(self, mock_input, mock_load, sample_tags):
        """Empty user input should produce cancelled status."""
        mock_load.return_value = sample_tags

        output = _cmd_select(type_filter=None, pattern=None, multi=True, prompt="Pick")
        assert "selection_status='cancelled'" in output

    @patch("git.tag_select.load_tags")
    def test_select_no_tags(self, mock_load):
        """Select with no tags should report no_tags without prompting the user."""
        mock_load.return_value = []

        output = _cmd_select(type_filter=None, pattern=None, multi=False, prompt="Pick")
        assert "selection_status='no_tags'" in output

    @patch("git.tag_select.load_tags")
    @patch("builtins.input", return_value="invalid")
    def test_select_invalid_input_cancels(self, mock_input, mock_load, sample_tags):
        """Invalid (non-numeric) user input should produce cancelled status."""
        mock_load.return_value = sample_tags

        output = _cmd_select(type_filter=None, pattern=None, multi=False, prompt="Pick")
        assert "selection_status='cancelled'" in output

    @patch("git.tag_select.load_tags")
    @patch("builtins.input", side_effect=EOFError)
    def test_select_eof_cancels(self, mock_input, mock_load, sample_tags):
        """EOFError (non-interactive environment) should produce cancelled status."""
        mock_load.return_value = sample_tags

        output = _cmd_select(type_filter=None, pattern=None, multi=False, prompt="Pick")
        assert "selection_status='cancelled'" in output

    @patch("git.tag_select.load_tags")
    @patch("builtins.input", return_value="1")
    def test_select_single_mode_returns_only_first(self, mock_input, mock_load, sample_tags):
        """Single-select mode should take only the first index even if multiple are parsed.

        In single mode, input '1' yields index [0] which maps to v2.0.0 only.
        """
        mock_load.return_value = sample_tags

        output = _cmd_select(type_filter=None, pattern=None, multi=False, prompt="Pick")
        # Only v2.0.0 should be selected
        assert "'v2.0.0'" in output
        assert "'v1.1.0'" not in output

    @patch("git.tag_select.load_tags")
    @patch("builtins.input", return_value="1,2")
    def test_select_single_mode_discards_extra_indices(self, mock_input, mock_load, sample_tags):
        """Single-select with multi-token input ('1,2') should keep only the first."""
        mock_load.return_value = sample_tags

        output = _cmd_select(type_filter=None, pattern=None, multi=False, prompt="Pick")
        assert "selection_status='selected'" in output
        assert "'v2.0.0'" in output
        # Second selection should be discarded in single-select mode
        assert "'v1.1.0'" not in output
