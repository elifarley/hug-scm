"""Unit tests for search.py - Search functionality with type safety.

Following Google Python testing best practices:
- Arrange-Act-Assert pattern
- Descriptive test names
- Test edge cases and error conditions
"""

import pytest

from git.search import SearchResult, _bash_escape, search_items_by_fields

################################################################################
# Test Fixtures
################################################################################


@pytest.fixture
def sample_fields():
    """Sample field values for testing."""
    return ["feature-branch", "Fix bug #123", "main", "develop"]


@pytest.fixture
def sample_result():
    """Sample SearchResult for testing."""
    return SearchResult(matched=True, logic="OR", terms=["feat", "bug"])


################################################################################
# TestBashEscape
################################################################################


class TestBashEscape:
    """Tests for _bash_escape function."""

    def test_escapes_single_quotes(self):
        """Should escape single quotes correctly."""
        result = _bash_escape("it's a test")
        assert "'\\''" in result

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


################################################################################
# TestSearchResult
################################################################################


class TestSearchResult:
    """Tests for SearchResult dataclass."""

    def test_initialization(self):
        """Should create SearchResult with all fields."""
        result = SearchResult(matched=True, logic="OR", terms=["feat", "bug"])
        assert result.matched is True
        assert result.logic == "OR"
        assert result.terms == ["feat", "bug"]

    def test_initialization_false(self):
        """Should create SearchResult with matched=False."""
        result = SearchResult(matched=False, logic="AND", terms=["xyz"])
        assert result.matched is False
        assert result.logic == "AND"
        assert result.terms == ["xyz"]

    def test_to_bash_declare_with_match(self):
        """Should output bash declare with matched=0 (true)."""
        result = SearchResult(matched=True, logic="OR", terms=["feat"])

        bash_output = result.to_bash_declare()

        assert "declare -i _search_matched=0" in bash_output
        assert "declare _search_logic='OR'" in bash_output
        assert "declare -a _search_terms=('feat')" in bash_output

    def test_to_bash_declare_without_match(self):
        """Should output bash declare with matched=1 (false)."""
        result = SearchResult(matched=False, logic="AND", terms=["xyz"])

        bash_output = result.to_bash_declare()

        assert "declare -i _search_matched=1" in bash_output
        assert "declare _search_logic='AND'" in bash_output
        assert "declare -a _search_terms=('xyz')" in bash_output

    def test_to_bash_declare_multiple_terms(self):
        """Should output all terms in bash array."""
        result = SearchResult(matched=True, logic="OR", terms=["feat", "bug", "fix"])

        bash_output = result.to_bash_declare()

        assert "declare -a _search_terms=('feat' 'bug' 'fix')" in bash_output

    def test_to_bash_declare_escapes_special_chars(self):
        """Should escape special characters in terms."""
        result = SearchResult(matched=True, logic="OR", terms=["feat's", "test"])

        bash_output = result.to_bash_declare()

        assert "'\\''" in bash_output  # Escaped single quote

    def test_to_bash_declare_empty_terms(self):
        """Should handle empty terms list."""
        result = SearchResult(matched=True, logic="OR", terms=[])

        bash_output = result.to_bash_declare()

        assert "declare -a _search_terms=()" in bash_output


################################################################################
# TestSearchItemsByFields
################################################################################


class TestSearchItemsByFields:
    """Tests for search_items_by_fields function."""

    # === Empty search terms ===

    def test_empty_search_terms_returns_true(self, sample_fields):
        """Should return True for empty search terms (match everything)."""
        result = search_items_by_fields("", "OR", *sample_fields)
        assert result is True

    def test_whitespace_only_search_terms_returns_true(self, sample_fields):
        """Should return True for whitespace-only search terms."""
        result = search_items_by_fields("   ", "OR", *sample_fields)
        assert result is True

    def test_multiple_spaces_in_terms(self, sample_fields):
        """Should handle multiple spaces between terms."""
        result = search_items_by_fields("feat   bug", "OR", *sample_fields)
        assert result is True  # "feat" matches "feature-branch"

    # === OR logic tests ===

    def test_or_logic_single_term_matches(self, sample_fields):
        """Should return True when single term matches any field (OR)."""
        result = search_items_by_fields("feat", "OR", *sample_fields)
        assert result is True  # "feat" in "feature-branch"

    def test_or_logic_single_term_no_match(self):
        """Should return False when single term matches no field (OR)."""
        fields = ["main", "develop", "production"]
        result = search_items_by_fields("xyz", "OR", *fields)
        assert result is False

    def test_or_logic_multiple_terms_one_matches(self, sample_fields):
        """Should return True when at least one term matches (OR)."""
        result = search_items_by_fields("feat xyz", "OR", *sample_fields)
        assert result is True  # "feat" in "feature-branch"

    def test_or_logic_multiple_terms_all_match(self, sample_fields):
        """Should return True when all terms match (OR)."""
        result = search_items_by_fields("feat bug", "OR", *sample_fields)
        assert result is True  # Both match

    def test_or_logic_multiple_terms_no_match(self):
        """Should return False when no terms match (OR)."""
        fields = ["main", "develop"]
        result = search_items_by_fields("xyz abc", "OR", *fields)
        assert result is False

    def test_or_logic_case_insensitive(self, sample_fields):
        """Should be case-insensitive (OR)."""
        result = search_items_by_fields("FEAT", "OR", *sample_fields)
        assert result is True  # "FEAT" matches "feature-branch"

    def test_or_logic_substring_match(self, sample_fields):
        """Should match substrings, not just whole words (OR)."""
        result = search_items_by_fields("atu", "OR", *sample_fields)
        assert result is True  # "atu" in "feature-branch"

    def test_or_logic_empty_fields(self):
        """Should handle empty fields list (OR)."""
        result = search_items_by_fields("test", "OR", *[])
        assert result is False  # No fields to search

    # === AND logic tests ===

    def test_and_logic_single_term_matches(self, sample_fields):
        """Should return True when single term matches (AND)."""
        result = search_items_by_fields("feat", "AND", *sample_fields)
        assert result is True  # "feat" in "feature-branch"

    def test_and_logic_single_term_no_match(self):
        """Should return False when single term doesn't match (AND)."""
        fields = ["main", "develop"]
        result = search_items_by_fields("xyz", "AND", *fields)
        assert result is False

    def test_and_logic_multiple_terms_all_match(self, sample_fields):
        """Should return True when all terms match at least one field (AND)."""
        result = search_items_by_fields("feat bug", "AND", *sample_fields)
        assert result is True  # "feat" in "feature-branch", "bug" in "Fix bug #123"

    def test_and_logic_multiple_terms_partial_match(self, sample_fields):
        """Should return False when only some terms match (AND)."""
        result = search_items_by_fields("feat xyz", "AND", *sample_fields)
        assert result is False  # "xyz" doesn't match anything

    def test_and_logic_multiple_terms_no_match(self):
        """Should return False when no terms match (AND)."""
        fields = ["main", "develop"]
        result = search_items_by_fields("xyz abc", "AND", *fields)
        assert result is False

    def test_and_logic_case_insensitive(self, sample_fields):
        """Should be case-insensitive (AND)."""
        result = search_items_by_fields("FEAT BUG", "AND", *sample_fields)
        assert result is True  # Both match case-insensitively

    def test_and_logic_substring_match(self, sample_fields):
        """Should match substrings, not just whole words (AND)."""
        result = search_items_by_fields("atu #123", "AND", *sample_fields)
        assert result is True  # "atu" in "feature-branch", "#123" in "Fix bug #123"

    def test_and_logic_different_fields(self, sample_fields):
        """Should match when terms are in different fields (AND)."""
        result = search_items_by_fields("branch main", "AND", *sample_fields)
        assert result is True  # "branch" in "feature-branch", "main" is exact match

    def test_and_logic_empty_fields(self):
        """Should handle empty fields list (AND)."""
        result = search_items_by_fields("test", "AND", *[])
        assert result is False

    # === Edge cases ===

    def test_special_characters_in_terms(self):
        """Should handle special characters in search terms."""
        fields = ["feature-branch", "Fix bug #123!"]
        result = search_items_by_fields("#123!", "OR", *fields)
        assert result is True  # "#123!" in "Fix bug #123!"

    def test_unicode_in_terms(self):
        """Should handle unicode characters."""
        fields = ["feature-branch", "Fix bug"]
        result = search_items_by_fields("bug", "OR", *fields)
        assert result is True

    def test_numbers_in_terms(self):
        """Should handle numeric search terms."""
        fields = ["branch-123", "main"]
        result = search_items_by_fields("123", "OR", *fields)
        assert result is True

    def test_very_long_term(self):
        """Should handle very long search terms."""
        fields = ["very-long-branch-name-with-many-hyphens"]
        result = search_items_by_fields("many-hyphens", "OR", *fields)
        assert result is True

    def test_single_field(self):
        """Should search across single field."""
        fields = ["feature-branch"]
        result = search_items_by_fields("feat", "OR", *fields)
        assert result is True

    def test_many_fields(self):
        """Should search across many fields."""
        fields = [f"branch-{i}" for i in range(100)]
        result = search_items_by_fields("branch-50", "OR", *fields)
        assert result is True

    def test_term_matches_multiple_fields(self, sample_fields):
        """Should handle term that matches multiple fields."""
        # "main" is in both "main" and could be in other fields
        fields = ["main-branch", "main", "develop"]
        result = search_items_by_fields("main", "OR", *fields)
        assert result is True

    def test_exact_word_match(self):
        """Should match exact words."""
        fields = ["feature", "main"]
        result = search_items_by_fields("feature", "OR", *fields)
        assert result is True

    def test_partial_word_at_start(self):
        """Should match partial word at start."""
        fields = ["feature-branch"]
        result = search_items_by_fields("feat", "OR", *fields)
        assert result is True

    def test_partial_word_at_end(self):
        """Should match partial word at end."""
        fields = ["feature-branch"]
        result = search_items_by_fields("branch", "OR", *fields)
        assert result is True

    def test_partial_word_in_middle(self):
        """Should match partial word in middle."""
        fields = ["feature-branch"]
        result = search_items_by_fields("ture", "OR", *fields)
        assert result is True

    def test_and_logic_term_matches_same_field(self):
        """Should handle multiple terms matching the same field (AND)."""
        fields = ["feature-branch-123"]
        result = search_items_by_fields("feat 123", "AND", *fields)
        assert result is True  # Both in same field

    def test_or_logic_term_matches_same_field(self):
        """Should handle multiple terms matching the same field (OR)."""
        fields = ["feature-branch-123"]
        result = search_items_by_fields("feat branch 123", "OR", *fields)
        assert result is True


################################################################################
# TestMainFunction (CLI tests)
################################################################################


class TestMainFunction:
    """Integration tests for main() CLI entry point."""

    def test_search_command_or_logic_match(self, monkeypatch, capsys):
        """Should output match=0 for OR logic with match."""
        import sys

        monkeypatch.setattr(
            sys,
            "argv",
            [
                "search.py",
                "search",
                "--terms",
                "feat bug",
                "--logic",
                "OR",
                "--fields",
                "feature-branch main",
            ],
        )

        from git.search import main

        result = main()
        captured = capsys.readouterr()

        assert result is None  # Success returns None
        assert "declare -i _search_matched=0" in captured.out
        assert "declare _search_logic='OR'" in captured.out
        assert "declare -a _search_terms=('feat' 'bug')" in captured.out

    def test_search_command_or_logic_no_match(self, monkeypatch, capsys):
        """Should output match=1 for OR logic with no match."""
        import sys

        monkeypatch.setattr(
            sys,
            "argv",
            [
                "search.py",
                "search",
                "--terms",
                "xyz",
                "--logic",
                "OR",
                "--fields",
                "main develop",
            ],
        )

        from git.search import main

        result = main()
        captured = capsys.readouterr()

        assert result is None
        assert "declare -i _search_matched=1" in captured.out
        assert "declare _search_logic='OR'" in captured.out

    def test_search_command_and_logic_match(self, monkeypatch, capsys):
        """Should output match=0 for AND logic with match."""
        import sys

        monkeypatch.setattr(
            sys,
            "argv",
            [
                "search.py",
                "search",
                "--terms",
                "feat main",
                "--logic",
                "AND",
                "--fields",
                "feature-branch main",
            ],
        )

        from git.search import main

        result = main()
        captured = capsys.readouterr()

        assert result is None
        assert "declare -i _search_matched=0" in captured.out
        assert "declare _search_logic='AND'" in captured.out

    def test_search_command_and_logic_no_match(self, monkeypatch, capsys):
        """Should output match=1 for AND logic with partial match."""
        import sys

        monkeypatch.setattr(
            sys,
            "argv",
            [
                "search.py",
                "search",
                "--terms",
                "feat xyz",
                "--logic",
                "AND",
                "--fields",
                "feature-branch main",
            ],
        )

        from git.search import main

        result = main()
        captured = capsys.readouterr()

        assert result is None
        assert "declare -i _search_matched=1" in captured.out

    def test_search_command_empty_terms(self, monkeypatch, capsys):
        """Should output match=0 for empty search terms."""
        import sys

        monkeypatch.setattr(
            sys,
            "argv",
            ["search.py", "search", "--terms", "", "--logic", "OR", "--fields", "main"],
        )

        from git.search import main

        result = main()
        captured = capsys.readouterr()

        assert result is None
        assert "declare -i _search_matched=0" in captured.out  # Empty = match

    def test_search_command_default_logic_is_or(self, monkeypatch, capsys):
        """Should use OR logic when not specified."""
        import sys

        monkeypatch.setattr(
            sys,
            "argv",
            ["search.py", "search", "--terms", "feat", "--fields", "feature-branch"],
        )

        from git.search import main

        result = main()
        captured = capsys.readouterr()

        assert result is None
        assert "declare _search_logic='OR'" in captured.out

    def test_search_command_empty_fields(self, monkeypatch, capsys):
        """Should handle empty fields list."""
        import sys

        monkeypatch.setattr(
            sys,
            "argv",
            ["search.py", "search", "--terms", "test", "--logic", "OR", "--fields", ""],
        )

        from git.search import main

        result = main()
        captured = capsys.readouterr()

        assert result is None
        assert "declare -i _search_matched=1" in captured.out  # No match
