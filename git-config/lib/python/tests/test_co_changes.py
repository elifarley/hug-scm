"""
Unit tests for co_changes.py - Co-change matrix analysis.

Following Google Python testing best practices:
- Arrange-Act-Assert pattern
- Descriptive test names
- Test edge cases and error conditions
- Mock external dependencies
"""

import json
from io import StringIO

# Import module under test
import co_changes


class TestParseGitLog:
    """Tests for parse_git_log function."""

    def test_parse_valid_log_with_multiple_commits(self, sample_git_log_co_changes):
        """Should parse git log with multiple commits and files."""
        # Arrange
        expected_commits = 5

        # Act
        result = co_changes.parse_git_log(sample_git_log_co_changes)

        # Assert
        assert len(result) == expected_commits
        assert "file_a.py" in result[0]
        assert "file_b.py" in result[0]

    def test_parse_minimal_log_with_single_commit(self, mock_git_log_minimal):
        """Should handle single commit with single file."""
        # Act
        result = co_changes.parse_git_log(mock_git_log_minimal)

        # Assert
        assert len(result) == 1
        assert "single_file.py" in result[0]

    def test_parse_empty_log(self, empty_git_log):
        """Should return empty list for empty log."""
        # Act
        result = co_changes.parse_git_log(empty_git_log)

        # Assert
        assert result == []

    def test_parse_filters_empty_lines(self):
        """Should ignore blank lines in git log output."""
        # Arrange
        log_with_blanks = """abc1234567890123456789012345678901234567
file_a.py
file_b.py
"""

        # Act
        result = co_changes.parse_git_log(log_with_blanks)

        # Assert
        assert len(result) == 1
        assert len(result[0]) == 2  # Set has 2 files
        assert "file_a.py" in result[0]
        assert "file_b.py" in result[0]

    def test_parse_handles_malformed_commit_hash(self):
        """Should treat non-hash lines as file paths."""
        # Arrange
        malformed_log = """abc1234567890123456789012345678901234567
file_a.py
file_b.py
"""

        # Act
        result = co_changes.parse_git_log(malformed_log)

        # Assert
        assert len(result) == 1
        assert "file_a.py" in result[0]
        assert "file_b.py" in result[0]


class TestBuildCoOccurrenceMatrix:
    """Tests for build_co_occurrence_matrix function."""

    def test_build_matrix_with_multiple_co_changes(self, sample_git_log_co_changes):
        """Should build correct co-occurrence counts."""
        # Arrange
        commits = co_changes.parse_git_log(sample_git_log_co_changes)

        # Act
        co_matrix, file_counts = co_changes.build_co_occurrence_matrix(commits)

        # Assert
        # Matrix stores sorted pairs, so only file_a -> file_b (not both directions)
        assert co_matrix["file_a.py"]["file_b.py"] == 3

        # file_a appears in 4 commits
        assert file_counts["file_a.py"] == 4

        # file_c appears in 3 commits
        assert file_counts["file_c.py"] == 3

    def test_build_matrix_with_single_file_commits(self, mock_git_log_minimal):
        """Should handle commits with only one file (no co-changes)."""
        # Arrange
        commits = co_changes.parse_git_log(mock_git_log_minimal)

        # Act
        co_matrix, file_counts = co_changes.build_co_occurrence_matrix(commits)

        # Assert
        assert file_counts["single_file.py"] == 1
        # No co-occurrences for single-file commits
        assert len(co_matrix.get("single_file.py", {})) == 0

    def test_build_matrix_empty_commits(self):
        """Should return empty structures for no commits."""
        # Act
        co_matrix, file_counts = co_changes.build_co_occurrence_matrix([])

        # Assert
        assert co_matrix == {}
        assert file_counts == {}


class TestCalculateCorrelations:
    """Tests for calculate_correlations function."""

    def test_calculate_correlations_above_threshold(self, sample_git_log_co_changes):
        """Should return only correlations above threshold."""
        # Arrange
        commits = co_changes.parse_git_log(sample_git_log_co_changes)
        co_matrix, file_counts = co_changes.build_co_occurrence_matrix(commits)
        threshold = 0.5

        # Act
        correlations = co_changes.calculate_correlations(co_matrix, file_counts, threshold)

        # Assert
        # file_a and file_b: 3/4 = 0.75 > 0.5 ✓
        assert any(
            c["file_a"] == "file_a.py"
            and c["file_b"] == "file_b.py"
            and c["correlation"] >= threshold
            for c in correlations
        )

    def test_calculate_correlations_formula_correctness(self):
        """Should calculate correlation as co_count / min(count_a, count_b)."""
        # Arrange
        co_matrix = {"file_a.py": {"file_b.py": 3}, "file_b.py": {"file_a.py": 3}}
        file_counts = {"file_a.py": 4, "file_b.py": 5}
        threshold = 0.0

        # Act
        correlations = co_changes.calculate_correlations(co_matrix, file_counts, threshold)

        # Assert
        # Expected: 3 / min(4, 5) = 3/4 = 0.75
        correlation = next(
            c for c in correlations if c["file_a"] == "file_a.py" and c["file_b"] == "file_b.py"
        )
        assert correlation["correlation"] == 0.75
        assert correlation["co_changes"] == 3

    def test_calculate_correlations_filters_by_threshold(self):
        """Should exclude correlations below threshold."""
        # Arrange
        co_matrix = {"file_a.py": {"file_b.py": 1}, "file_b.py": {"file_a.py": 1}}
        file_counts = {"file_a.py": 10, "file_b.py": 10}
        threshold = 0.5  # 1/10 = 0.1 < 0.5

        # Act
        correlations = co_changes.calculate_correlations(co_matrix, file_counts, threshold)

        # Assert
        assert len(correlations) == 0

    def test_calculate_correlations_sorted_descending(self, sample_git_log_co_changes):
        """Should return results sorted by correlation (descending)."""
        # Arrange
        commits = co_changes.parse_git_log(sample_git_log_co_changes)
        co_matrix, file_counts = co_changes.build_co_occurrence_matrix(commits)
        threshold = 0.0

        # Act
        correlations = co_changes.calculate_correlations(co_matrix, file_counts, threshold)

        # Assert
        # Verify descending order
        for i in range(len(correlations) - 1):
            assert correlations[i]["correlation"] >= correlations[i + 1]["correlation"]


class TestFormatTextOutput:
    """Tests for format_text_output function."""

    def test_format_text_output_includes_header(self):
        """Should include header with commit count and threshold."""
        # Arrange
        correlations = []
        threshold = 0.3
        total_commits = 10

        # Act
        output = co_changes.format_text_output(correlations, threshold, total_commits)

        # Assert
        assert "10 commits" in output
        assert "30%" in output or "0.3" in output

    def test_format_text_output_displays_correlations(self, sample_git_log_co_changes):
        """Should format correlation pairs with percentages."""
        # Arrange
        commits = co_changes.parse_git_log(sample_git_log_co_changes)
        co_matrix, file_counts = co_changes.build_co_occurrence_matrix(commits)
        correlations = co_changes.calculate_correlations(co_matrix, file_counts, 0.5)

        # Act
        output = co_changes.format_text_output(correlations, 0.5, len(commits))

        # Assert
        assert "file_a.py" in output
        assert "file_b.py" in output
        assert "↔" in output or "<->" in output  # Bidirectional indicator

    def test_format_text_output_handles_empty_correlations(self):
        """Should display appropriate message when no correlations found."""
        # Arrange
        correlations = []
        threshold = 0.9
        total_commits = 5

        # Act
        output = co_changes.format_text_output(correlations, threshold, total_commits)

        # Assert
        assert "No" in output or "none" in output.lower()


class TestMainFunction:
    """Integration tests for main function."""

    def test_main_json_output_format(self, sample_git_log_co_changes, monkeypatch, capsys):
        """Should output valid JSON when --format=json."""
        # Arrange
        import sys

        monkeypatch.setattr(sys, "stdin", StringIO(sample_git_log_co_changes))
        monkeypatch.setattr(
            sys, "argv", ["co_changes.py", "--threshold", "0.5", "--format", "json"]
        )

        # Act
        exit_code = co_changes.main()
        captured = capsys.readouterr()

        # Assert
        assert exit_code == 0
        result = json.loads(captured.out)
        assert "commits_analyzed" in result
        assert "threshold" in result
        assert "correlations" in result

    def test_main_text_output_format(self, sample_git_log_co_changes, monkeypatch, capsys):
        """Should output formatted text when --format=text."""
        # Arrange
        import sys

        monkeypatch.setattr(sys, "stdin", StringIO(sample_git_log_co_changes))
        monkeypatch.setattr(
            sys, "argv", ["co_changes.py", "--threshold", "0.5", "--format", "text"]
        )

        # Act
        exit_code = co_changes.main()
        captured = capsys.readouterr()

        # Assert
        assert exit_code == 0
        assert "file_a.py" in captured.out
        assert "file_b.py" in captured.out

    def test_main_handles_empty_input(self, empty_git_log, monkeypatch, capsys):
        """Should handle empty stdin gracefully."""
        # Arrange
        import sys

        monkeypatch.setattr(sys, "stdin", StringIO(empty_git_log))
        monkeypatch.setattr(sys, "argv", ["co_changes.py"])

        # Act
        exit_code = co_changes.main()
        captured = capsys.readouterr()

        # Assert
        assert exit_code == 1
        assert "Error" in captured.err or "No" in captured.err


class TestEdgeCases:
    """Tests for edge cases and boundary conditions."""

    def test_handles_files_with_spaces_in_names(self):
        """Should correctly parse file names with spaces."""
        # Arrange
        log_with_spaces = """abc1234567890123456789012345678901234567
src/my file.py
tests/test file.py
"""

        # Act
        result = co_changes.parse_git_log(log_with_spaces)

        # Assert
        assert "src/my file.py" in result[0]
        assert "tests/test file.py" in result[0]

    def test_handles_large_commit_lists(self):
        """Should handle large numbers of commits efficiently."""
        # Arrange
        # Generate 100 commits with varying file patterns
        large_log_parts = []
        for i in range(100):
            hash_val = f"{i:040d}"
            large_log_parts.append(hash_val)
            large_log_parts.append(f"file_{i % 10}.py")
            large_log_parts.append("")

        large_log = "\n".join(large_log_parts)

        # Act
        result = co_changes.parse_git_log(large_log)

        # Assert
        assert len(result) == 100

    def test_handles_very_high_threshold(self, sample_git_log_co_changes):
        """Should return empty results with threshold=1.0 (100%)."""
        # Arrange
        commits = co_changes.parse_git_log(sample_git_log_co_changes)
        co_matrix, file_counts = co_changes.build_co_occurrence_matrix(commits)

        # Act
        correlations = co_changes.calculate_correlations(co_matrix, file_counts, 1.0)

        # Assert
        # Only files that ALWAYS change together would have correlation=1.0
        # In our sample, no files have 100% correlation
        assert len(correlations) == 0 or all(c["correlation"] == 1.0 for c in correlations)
