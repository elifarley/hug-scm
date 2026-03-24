"""Unit tests for selection_core.py — shared selection infrastructure.

Tests for:
  - bash_escape: canonical single-quote escaping for bash eval
  - BashDeclareBuilder: fluent builder for bash declare statements

Following Google Python testing best practices:
- Arrange-Act-Assert pattern
- Descriptive test names (test_<subject>_<condition>_<expected_outcome>)
- Test edge cases and error conditions
"""

import pytest

from git.selection_core import BashDeclareBuilder, bash_escape


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
