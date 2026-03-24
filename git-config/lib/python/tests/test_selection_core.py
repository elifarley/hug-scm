"""Unit tests for selection_core.py — shared selection infrastructure.

Tests for:
  - bash_escape: canonical single-quote escaping for bash eval
  - BashDeclareBuilder: fluent builder for bash declare statements
  - parse_numbered_input: user selection parsing (numbers, ranges, "all")
  - get_selection_input: input precedence (test_selection > env var > stdin)
  - add_common_cli_args: shared argparse configuration
  - ANSI color constants: YELLOW, BLUE, GREY, CYAN, GREEN, NC

Following Google Python testing best practices:
- Arrange-Act-Assert pattern
- Descriptive test names (test_<subject>_<condition>_<expected_outcome>)
- Test edge cases and error conditions
"""

import argparse
import os

import pytest

from git.selection_core import (
    BLUE,
    CYAN,
    GREEN,
    GREY,
    NC,
    YELLOW,
    BashDeclareBuilder,
    add_common_cli_args,
    bash_escape,
    get_selection_input,
    parse_numbered_input,
)


################################################################################
# TestBashEscape
################################################################################


class TestBashEscape:
    """Tests for bash_escape() — safe single-quote wrapping for bash eval.

    The canonical implementation lives here; tag_select.py, worktree_select.py,
    and branch_select.py all previously duplicated it as _bash_escape().
    """

    def test_simple_string_is_wrapped_in_single_quotes(self):
        """Plain alphanumeric strings should be wrapped in single quotes."""
        assert bash_escape("hello") == "'hello'"

    def test_empty_string_produces_adjacent_single_quotes(self):
        """Empty string should produce two adjacent single quotes — valid bash empty string."""
        assert bash_escape("") == "''"

    def test_single_quote_is_escaped_with_backslash_idiom(self):
        """Embedded single quotes use the '\\'' idiom: end-quote, escaped-quote, re-open."""
        # "it's" → 'it'\''s'
        assert bash_escape("it's") == "'it'\\''s'"

    def test_multiple_single_quotes_each_escaped(self):
        """Every single quote in the input gets the idiom applied."""
        # "a'b'c" → 'a'\''b'\''c'
        assert bash_escape("a'b'c") == "'a'\\''b'\\''c'"

    def test_backslash_is_doubled_before_quote_escaping(self):
        """Backslashes must be doubled so bash sees a literal backslash.

        Order matters: escape backslashes FIRST, then single quotes.
        If we did it in reverse order we would double-escape our own
        introduced backslashes.
        """
        # "path\\to" → 'path\\\\to' (bash sees: path\\to)
        assert bash_escape("path\\to") == "'path\\\\to'"

    def test_backslash_before_single_quote_both_escaped(self):
        """A backslash immediately before a single quote needs both transformations."""
        # Input: \' → after backslash doubling: \\' → after quote escaping: \\'\'
        # Wrapped: '\\'\'', which bash interprets as: \'
        assert bash_escape("\\'") == "'\\\\'\\'''"

    def test_spaces_are_safe_inside_single_quotes(self):
        """Spaces need no escaping — single-quoting handles them."""
        assert bash_escape("hello world") == "'hello world'"

    def test_newline_is_preserved_in_single_quotes(self):
        """Newlines inside single quotes are literal — bash preserves them."""
        result = bash_escape("line1\nline2")
        assert result == "'line1\nline2'"

    def test_special_shell_chars_are_safe_inside_single_quotes(self):
        """$, !, *, ?, ;, &, | are not interpreted inside single quotes."""
        assert bash_escape("$HOME/*.txt") == "'$HOME/*.txt'"

    def test_dollar_variable_not_expanded(self):
        """Dollar signs are literal inside single quotes — no variable expansion."""
        assert bash_escape("${VAR}") == "'${VAR}'"

    def test_tab_character_preserved(self):
        """Tab characters inside single quotes are literal."""
        assert bash_escape("col1\tcol2") == "'col1\tcol2'"


################################################################################
# TestBashDeclareBuilder
################################################################################


class TestBashDeclareBuilder:
    """Tests for BashDeclareBuilder — fluent builder for bash declare statements.

    Each add_* method appends one declare line; build() returns newline-joined
    output suitable for bash eval.
    """

    # --------------------------------------------------------------------------
    # add_array
    # --------------------------------------------------------------------------

    def test_add_array_with_two_elements(self):
        """add_array should emit declare -a name=('v1' 'v2')."""
        builder = BashDeclareBuilder()
        builder.add_array("items", ["v1", "v2"])
        assert builder.build() == "declare -a items=('v1' 'v2')"

    def test_add_array_with_empty_list(self):
        """Empty array should produce declare -a name=()."""
        builder = BashDeclareBuilder()
        builder.add_array("items", [])
        assert builder.build() == "declare -a items=()"

    def test_add_array_with_single_element(self):
        """Single-element array should work correctly."""
        builder = BashDeclareBuilder()
        builder.add_array("tags", ["v1.0.0"])
        assert builder.build() == "declare -a tags=('v1.0.0')"

    def test_add_array_escapes_values_with_single_quotes(self):
        """Values containing single quotes must be escaped."""
        builder = BashDeclareBuilder()
        builder.add_array("notes", ["it's here"])
        assert builder.build() == "declare -a notes=('it'\\''s here')"

    def test_add_array_escapes_values_with_backslashes(self):
        """Values containing backslashes must be doubled."""
        builder = BashDeclareBuilder()
        builder.add_array("paths", ["path\\to\\file"])
        assert builder.build() == "declare -a paths=('path\\\\to\\\\file')"

    def test_add_array_escapes_special_shell_chars(self):
        """Special characters are safe inside single-quoted array elements."""
        builder = BashDeclareBuilder()
        builder.add_array("globs", ["$HOME/*.txt"])
        assert builder.build() == "declare -a globs=('$HOME/*.txt')"

    # --------------------------------------------------------------------------
    # add_scalar
    # --------------------------------------------------------------------------

    def test_add_scalar_simple_value(self):
        """add_scalar should emit declare name='val'."""
        builder = BashDeclareBuilder()
        builder.add_scalar("status", "ready")
        assert builder.build() == "declare status='ready'"

    def test_add_scalar_escapes_single_quotes(self):
        """Values with single quotes must be escaped."""
        builder = BashDeclareBuilder()
        builder.add_scalar("msg", "it's done")
        assert builder.build() == "declare msg='it'\\''s done'"

    def test_add_scalar_empty_value(self):
        """Empty value should produce declare name=''."""
        builder = BashDeclareBuilder()
        builder.add_scalar("msg", "")
        assert builder.build() == "declare msg=''"

    # --------------------------------------------------------------------------
    # add_int
    # --------------------------------------------------------------------------

    def test_add_int_positive_value(self):
        """add_int should emit declare -i name=42 (no quoting — integers are safe)."""
        builder = BashDeclareBuilder()
        builder.add_int("count", 42)
        assert builder.build() == "declare -i count=42"

    def test_add_int_zero(self):
        """Zero should work correctly."""
        builder = BashDeclareBuilder()
        builder.add_int("count", 0)
        assert builder.build() == "declare -i count=0"

    def test_add_int_negative_value(self):
        """Negative integers should be emitted without quoting."""
        builder = BashDeclareBuilder()
        builder.add_int("offset", -5)
        assert builder.build() == "declare -i offset=-5"

    # --------------------------------------------------------------------------
    # build() — multi-line output
    # --------------------------------------------------------------------------

    def test_build_multiple_declarations_newline_separated(self):
        """build() should join all declarations with newlines."""
        builder = BashDeclareBuilder()
        builder.add_array("tags", ["v1", "v2"])
        builder.add_scalar("status", "ready")
        builder.add_int("count", 2)
        lines = builder.build().split("\n")
        assert lines[0] == "declare -a tags=('v1' 'v2')"
        assert lines[1] == "declare status='ready'"
        assert lines[2] == "declare -i count=2"

    def test_build_empty_builder_returns_empty_string(self):
        """A builder with no declarations should produce an empty string."""
        builder = BashDeclareBuilder()
        assert builder.build() == ""

    def test_build_preserves_insertion_order(self):
        """Declarations should appear in the order they were added."""
        builder = BashDeclareBuilder()
        builder.add_scalar("first", "a")
        builder.add_scalar("second", "b")
        builder.add_scalar("third", "c")
        lines = builder.build().split("\n")
        assert "first" in lines[0]
        assert "second" in lines[1]
        assert "third" in lines[2]

    # --------------------------------------------------------------------------
    # Fluent API — method chaining
    # --------------------------------------------------------------------------

    def test_add_methods_return_self_for_chaining(self):
        """Each add_* method must return self to enable fluent chaining."""
        builder = BashDeclareBuilder()
        result = builder.add_array("a", []).add_scalar("b", "x").add_int("c", 1)
        # Returns the same builder instance
        assert result is builder

    def test_fluent_chain_produces_correct_output(self):
        """Chained calls should behave identically to sequential calls."""
        output = (
            BashDeclareBuilder()
            .add_array("filtered_tags", ["v1.0", "v2.0"])
            .add_scalar("selection_status", "ready")
            .add_int("tag_count", 2)
            .build()
        )
        expected = (
            "declare -a filtered_tags=('v1.0' 'v2.0')\n"
            "declare selection_status='ready'\n"
            "declare -i tag_count=2"
        )
        assert output == expected

    # --------------------------------------------------------------------------
    # Variable name validation
    # --------------------------------------------------------------------------

    def test_invalid_name_with_leading_digit_raises_value_error(self):
        """Variable names starting with a digit are invalid in bash."""
        builder = BashDeclareBuilder()
        with pytest.raises(ValueError, match="Invalid bash variable name"):
            builder.add_scalar("1invalid", "val")

    def test_invalid_name_with_hyphen_raises_value_error(self):
        """Hyphens are not valid in bash variable names."""
        builder = BashDeclareBuilder()
        with pytest.raises(ValueError, match="Invalid bash variable name"):
            builder.add_array("my-var", [])

    def test_invalid_name_with_space_raises_value_error(self):
        """Spaces are not valid in bash variable names."""
        builder = BashDeclareBuilder()
        with pytest.raises(ValueError, match="Invalid bash variable name"):
            builder.add_int("my var", 0)

    def test_invalid_empty_name_raises_value_error(self):
        """Empty string is not a valid bash variable name."""
        builder = BashDeclareBuilder()
        with pytest.raises(ValueError, match="Invalid bash variable name"):
            builder.add_scalar("", "val")

    def test_valid_name_with_leading_underscore(self):
        """Variable names may start with an underscore."""
        builder = BashDeclareBuilder()
        builder.add_scalar("_private", "val")  # Should not raise
        assert "'val'" in builder.build()

    def test_valid_name_with_digits_after_first_char(self):
        """Digits are allowed after the first character."""
        builder = BashDeclareBuilder()
        builder.add_int("count2", 5)  # Should not raise
        assert "count2" in builder.build()

    def test_invalid_name_error_raised_immediately_not_at_build(self):
        """ValueError must be raised at add_* time, not deferred to build()."""
        builder = BashDeclareBuilder()
        with pytest.raises(ValueError):
            builder.add_scalar("bad-name", "val")
        # build() is never called, but that's the point — fail fast


################################################################################
# TestInvalidVarNameParametrized (Code review finding I1)
################################################################################


class TestInvalidVarNameParametrized:
    """Parametrized tests verifying all add_* methods reject invalid variable names.

    Code review finding I1: the original tests validated each invalid-name case
    against a single add_* method, leaving gaps where a name-validation bug in
    add_array or add_int would go undetected.  This class closes that gap by
    driving the same set of invalid names through all three methods in one sweep.
    """

    # The invalid names to test.  Each entry exercises a different violation of
    # the [a-zA-Z_][a-zA-Z0-9_]* rule so that we catch both "wrong first char"
    # and "wrong body char" defects independently.
    INVALID_NAMES = [
        "1leading_digit",    # starts with digit
        "my-var",            # contains hyphen
        "my var",            # contains space
        "",                  # empty string
        "dot.name",          # contains dot
        "dollar$sign",       # contains dollar sign
    ]

    @pytest.mark.parametrize("invalid_name", INVALID_NAMES)
    def test_add_scalar_rejects_invalid_name(self, invalid_name: str):
        """add_scalar must raise ValueError for any invalid variable name."""
        builder = BashDeclareBuilder()
        with pytest.raises(ValueError, match="Invalid bash variable name"):
            builder.add_scalar(invalid_name, "val")

    @pytest.mark.parametrize("invalid_name", INVALID_NAMES)
    def test_add_array_rejects_invalid_name(self, invalid_name: str):
        """add_array must raise ValueError for any invalid variable name."""
        builder = BashDeclareBuilder()
        with pytest.raises(ValueError, match="Invalid bash variable name"):
            builder.add_array(invalid_name, [])

    @pytest.mark.parametrize("invalid_name", INVALID_NAMES)
    def test_add_int_rejects_invalid_name(self, invalid_name: str):
        """add_int must raise ValueError for any invalid variable name."""
        builder = BashDeclareBuilder()
        with pytest.raises(ValueError, match="Invalid bash variable name"):
            builder.add_int(invalid_name, 0)


################################################################################
# TestParseNumberedInput
################################################################################


class TestParseNumberedInput:
    """Tests for parse_numbered_input() — user selection string → 0-based index list.

    The canonical reference implementation is branch_select.parse_user_input().
    This test suite mirrors its documented behaviour, including edge cases that
    have historically tripped up reimplementations:
      - 1-based display indices ↔ 0-based return indices
      - Out-of-bounds numbers are silently ignored (not an error)
      - Reverse ranges (e.g. "5-3") produce no results rather than crashing
      - Duplicates across parts collapse to a single entry (set semantics)
      - allow_all=False makes "a"/"all" fall through to the number parser
        (returning [] because "a" is not a valid integer)
    """

    # ------------------------------------------------------------------
    # Empty / whitespace input
    # ------------------------------------------------------------------

    def test_empty_string_returns_empty_list(self):
        """Empty input means no selection — return []."""
        assert parse_numbered_input("", 5) == []

    def test_whitespace_only_returns_empty_list(self):
        """Input containing only whitespace is treated as empty."""
        assert parse_numbered_input("   ", 5) == []

    # ------------------------------------------------------------------
    # Single numbers
    # ------------------------------------------------------------------

    def test_single_number_returns_zero_based_index(self):
        """User types '1' → index 0 (1-based display → 0-based return)."""
        assert parse_numbered_input("1", 5) == [0]

    def test_single_number_last_item(self):
        """User types the last item number — correctly returns last index."""
        assert parse_numbered_input("5", 5) == [4]

    def test_single_number_out_of_bounds_ignored(self):
        """Numbers beyond num_items are silently ignored (no error)."""
        assert parse_numbered_input("6", 5) == []

    def test_single_number_zero_ignored(self):
        """'0' converts to index -1 which is out of bounds, so it is ignored."""
        assert parse_numbered_input("0", 5) == []

    def test_single_number_negative_ignored(self):
        """Negative numbers produce out-of-bounds indices and are ignored."""
        assert parse_numbered_input("-1", 5) == []

    # ------------------------------------------------------------------
    # Comma-separated numbers
    # ------------------------------------------------------------------

    def test_comma_separated_numbers(self):
        """'1,2,3' → [0, 1, 2] (0-based, sorted)."""
        assert parse_numbered_input("1,2,3", 5) == [0, 1, 2]

    def test_comma_separated_with_spaces(self):
        """Spaces around commas are tolerated."""
        assert parse_numbered_input("1, 2, 3", 5) == [0, 1, 2]

    def test_comma_separated_out_of_order(self):
        """Results are always sorted regardless of input order."""
        assert parse_numbered_input("3,1,2", 5) == [0, 1, 2]

    def test_comma_separated_duplicates_collapsed(self):
        """Duplicate entries in input collapse to a single index."""
        assert parse_numbered_input("2,2,2", 5) == [1]

    # ------------------------------------------------------------------
    # Ranges
    # ------------------------------------------------------------------

    def test_range_1_to_3(self):
        """'1-3' → [0, 1, 2] inclusive."""
        assert parse_numbered_input("1-3", 5) == [0, 1, 2]

    def test_range_covers_all_items(self):
        """Range wider than the list is clamped to valid indices."""
        assert parse_numbered_input("1-10", 5) == [0, 1, 2, 3, 4]

    def test_range_starting_beyond_num_items_returns_empty(self):
        """Range entirely outside num_items → empty list."""
        assert parse_numbered_input("6-8", 5) == []

    def test_reverse_range_produces_no_results(self):
        """'5-3': start > end after 0-based conversion → empty range.

        The canonical implementation uses range(start_idx, end_idx + 1) which
        produces an empty sequence when start_idx > end_idx.  We document this
        explicitly rather than silently relying on Python range semantics.
        """
        assert parse_numbered_input("5-3", 5) == []

    def test_single_item_range(self):
        """'2-2' is a valid single-item range."""
        assert parse_numbered_input("2-2", 5) == [1]

    # ------------------------------------------------------------------
    # Mixed numbers and ranges
    # ------------------------------------------------------------------

    def test_mixed_numbers_and_ranges(self):
        """'1,3-5,7' with num_items=10 → [0, 2, 3, 4, 6]."""
        assert parse_numbered_input("1,3-5,7", 10) == [0, 2, 3, 4, 6]

    def test_mixed_with_duplicates_across_parts(self):
        """Overlap between a range and a single number is deduplicated."""
        # "2,1-3" → indices 0,1,2 — '2' overlaps with range 1-3
        assert parse_numbered_input("2,1-3", 5) == [0, 1, 2]

    # ------------------------------------------------------------------
    # "all" / "a" shortcuts
    # ------------------------------------------------------------------

    def test_all_lowercase_selects_every_item(self):
        """'all' → all indices [0, 1, 2] when allow_all=True (default)."""
        assert parse_numbered_input("all", 3) == [0, 1, 2]

    def test_all_uppercase_selects_every_item(self):
        """'ALL' is accepted (case-insensitive)."""
        assert parse_numbered_input("ALL", 3) == [0, 1, 2]

    def test_a_lowercase_selects_every_item(self):
        """Single 'a' is the short alias for 'all'."""
        assert parse_numbered_input("a", 3) == [0, 1, 2]

    def test_a_uppercase_selects_every_item(self):
        """'A' (uppercase) is also accepted."""
        assert parse_numbered_input("A", 3) == [0, 1, 2]

    def test_all_with_zero_items_returns_empty(self):
        """'all' with num_items=0 should return [] — there is nothing to select."""
        assert parse_numbered_input("all", 0) == []

    def test_allow_all_false_disables_all_shortcut(self):
        """When allow_all=False, 'a'/'all' is not treated specially.

        It falls through to the number parser, which cannot parse 'a' as an
        integer, so the part is silently skipped → empty list.
        """
        assert parse_numbered_input("a", 3, allow_all=False) == []
        assert parse_numbered_input("all", 3, allow_all=False) == []

    # ------------------------------------------------------------------
    # Invalid / non-numeric input
    # ------------------------------------------------------------------

    def test_invalid_text_returns_empty(self):
        """Non-numeric, non-'all' input is silently ignored."""
        assert parse_numbered_input("foo", 5) == []

    def test_invalid_range_format_skipped(self):
        """Malformed range (non-integer endpoints) is silently skipped."""
        assert parse_numbered_input("a-b", 5) == []

    def test_mixed_valid_and_invalid_parts(self):
        """Valid parts are returned even when the input contains invalid parts."""
        # "1,foo,3" → [0, 2] (foo is skipped)
        assert parse_numbered_input("1,foo,3", 5) == [0, 2]


################################################################################
# TestGetSelectionInput
################################################################################


class TestGetSelectionInput:
    """Tests for get_selection_input() — input source precedence.

    The canonical precedence, ported from branch_select.multi_select_branches():
      1. test_selection argument (if not None)     — highest priority
      2. env_var environment variable (if set)
      3. input() from stdin
      4. Empty string on EOFError                  — lowest priority

    Each test isolates a single level of the precedence stack so regressions
    are unambiguous.
    """

    # ------------------------------------------------------------------
    # test_selection argument (level 1 — highest priority)
    # ------------------------------------------------------------------

    def test_test_selection_arg_wins_over_env_var(self, monkeypatch):
        """When test_selection is provided, it beats the environment variable."""
        monkeypatch.setenv("HUG_TEST_NUMBERED_SELECTION", "env_value")
        result = get_selection_input(test_selection="arg_value")
        assert result == "arg_value"

    def test_test_selection_empty_string_still_wins(self, monkeypatch):
        """An empty string for test_selection is a deliberate choice, not 'not set'.

        Passing test_selection="" should return "", not fall through to the env var.
        The sentinel for "not set" is None, not "".
        """
        monkeypatch.setenv("HUG_TEST_NUMBERED_SELECTION", "env_value")
        result = get_selection_input(test_selection="")
        assert result == ""

    def test_test_selection_none_falls_through_to_env_var(self, monkeypatch):
        """None is the sentinel for 'no test_selection'; env var is checked next."""
        monkeypatch.setenv("HUG_TEST_NUMBERED_SELECTION", "env_value")
        result = get_selection_input(test_selection=None)
        assert result == "env_value"

    # ------------------------------------------------------------------
    # env_var (level 2)
    # ------------------------------------------------------------------

    def test_env_var_wins_over_stdin(self, monkeypatch):
        """When env_var is set (and test_selection is None), it beats stdin."""
        monkeypatch.setenv("HUG_TEST_NUMBERED_SELECTION", "2,3")
        # stdin is not patched; if it were read we'd get an error in CI
        result = get_selection_input(test_selection=None)
        assert result == "2,3"

    def test_custom_env_var_name_is_respected(self, monkeypatch):
        """The caller can specify a custom environment variable name."""
        monkeypatch.setenv("MY_CUSTOM_SEL", "42")
        result = get_selection_input(
            test_selection=None,
            env_var="MY_CUSTOM_SEL",
        )
        assert result == "42"

    def test_unset_env_var_falls_through_to_stdin(self, monkeypatch):
        """When the env var is absent, stdin is used."""
        monkeypatch.delenv("HUG_TEST_NUMBERED_SELECTION", raising=False)
        # Patch builtins.input so we don't block on actual stdin
        monkeypatch.setattr("builtins.input", lambda _prompt="": "stdin_value")
        result = get_selection_input(test_selection=None)
        assert result == "stdin_value"

    # ------------------------------------------------------------------
    # stdin / EOFError (levels 3 and 4)
    # ------------------------------------------------------------------

    def test_eoferror_on_stdin_returns_empty_string(self, monkeypatch):
        """EOFError from input() (non-interactive environment) returns ""."""
        monkeypatch.delenv("HUG_TEST_NUMBERED_SELECTION", raising=False)

        def raise_eof(_prompt=""):
            raise EOFError

        monkeypatch.setattr("builtins.input", raise_eof)
        result = get_selection_input(test_selection=None)
        assert result == ""

    def test_default_env_var_name(self, monkeypatch):
        """Default env_var name is HUG_TEST_NUMBERED_SELECTION."""
        monkeypatch.setenv("HUG_TEST_NUMBERED_SELECTION", "default_env")
        # Do NOT pass env_var; rely on the default
        result = get_selection_input(test_selection=None)
        assert result == "default_env"


################################################################################
# TestAddCommonCliArgs
################################################################################


class TestAddCommonCliArgs:
    """Tests for add_common_cli_args() — shared argparse argument registration.

    This helper adds --placeholder and --selection to any ArgumentParser.
    The --no-gum argument is optional and only added when include_no_gum=True.

    Design: parameterizing --no-gum avoids forcing callers that don't interact
    with gum to accept an irrelevant flag.  Only modules that drive gum should
    advertise it.
    """

    def _make_parser(self) -> argparse.ArgumentParser:
        """Return a fresh parser for each test."""
        return argparse.ArgumentParser()

    def test_placeholder_arg_has_default(self):
        """--placeholder should default to an empty string or sensible default."""
        parser = self._make_parser()
        add_common_cli_args(parser)
        args = parser.parse_args([])
        # The default is an empty string — callers supply their own text
        assert args.placeholder == ""

    def test_placeholder_arg_can_be_set(self):
        """--placeholder accepts a custom value."""
        parser = self._make_parser()
        add_common_cli_args(parser)
        args = parser.parse_args(["--placeholder", "Select items"])
        assert args.placeholder == "Select items"

    def test_selection_arg_default_is_none(self):
        """--selection defaults to None (not provided)."""
        parser = self._make_parser()
        add_common_cli_args(parser)
        args = parser.parse_args([])
        assert args.selection is None

    def test_selection_arg_can_be_set(self):
        """--selection accepts a test value."""
        parser = self._make_parser()
        add_common_cli_args(parser)
        args = parser.parse_args(["--selection", "1,2"])
        assert args.selection == "1,2"

    def test_no_gum_not_added_by_default(self):
        """--no-gum should NOT appear when include_no_gum is omitted (default False)."""
        parser = self._make_parser()
        add_common_cli_args(parser)
        with pytest.raises(SystemExit):
            # argparse exits with code 2 for unknown args
            parser.parse_args(["--no-gum"])

    def test_no_gum_added_when_include_no_gum_true(self):
        """--no-gum IS present when include_no_gum=True."""
        parser = self._make_parser()
        add_common_cli_args(parser, include_no_gum=True)
        args = parser.parse_args(["--no-gum"])
        assert args.no_gum is True

    def test_no_gum_default_false_when_included(self):
        """When --no-gum is registered but not passed, it defaults to False."""
        parser = self._make_parser()
        add_common_cli_args(parser, include_no_gum=True)
        args = parser.parse_args([])
        assert args.no_gum is False

    def test_all_common_args_together(self):
        """All common args can be provided simultaneously."""
        parser = self._make_parser()
        add_common_cli_args(parser, include_no_gum=True)
        args = parser.parse_args(["--placeholder", "Pick one", "--selection", "3"])
        assert args.placeholder == "Pick one"
        assert args.selection == "3"
        assert args.no_gum is False


################################################################################
# TestAnsiColorConstants
################################################################################


class TestAnsiColorConstants:
    """Tests for ANSI color constant values exported from selection_core.

    These constants must match the values used in branch_select.py so that all
    modules sharing selection_core produce visually consistent output.

    ANSI escape sequences:
        \x1b[  = ESC [  (Control Sequence Introducer)
        33m    = yellow foreground
        34m    = blue foreground
        90m    = bright black / dark grey foreground
        36m    = cyan foreground
        32m    = green foreground
        0m     = reset all attributes
    """

    def test_yellow_is_correct_ansi_code(self):
        """YELLOW must be the standard ANSI yellow escape sequence."""
        assert YELLOW == "\x1b[33m"

    def test_blue_is_correct_ansi_code(self):
        """BLUE must be the standard ANSI blue escape sequence."""
        assert BLUE == "\x1b[34m"

    def test_grey_is_correct_ansi_code(self):
        """GREY must be the ANSI bright-black (dark grey) escape sequence."""
        assert GREY == "\x1b[90m"

    def test_cyan_is_correct_ansi_code(self):
        """CYAN must be the standard ANSI cyan escape sequence."""
        assert CYAN == "\x1b[36m"

    def test_green_is_correct_ansi_code(self):
        """GREEN must be the standard ANSI green escape sequence."""
        assert GREEN == "\x1b[32m"

    def test_nc_resets_all_attributes(self):
        """NC (No Color) must be the ANSI reset sequence."""
        assert NC == "\x1b[0m"

    def test_constants_are_strings(self):
        """All constants must be str (not bytes or other types)."""
        for constant in (YELLOW, BLUE, GREY, CYAN, GREEN, NC):
            assert isinstance(constant, str), f"Expected str, got {type(constant)}"
