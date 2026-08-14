"""Unit tests for co_changes.py - repo-wide and file-focused co-change analysis."""

import json
import sys
from io import StringIO

import co_changes


class TestParseGitLog:
    """Tests for parse_git_log function."""

    def test_parse_valid_log_with_multiple_commits(self, sample_git_log_co_changes):
        result = co_changes.parse_git_log(sample_git_log_co_changes)

        assert len(result) == 5
        assert result[0] == {"file_a.py", "file_b.py"}

    def test_parse_minimal_log_with_single_commit(self, mock_git_log_minimal):
        result = co_changes.parse_git_log(mock_git_log_minimal)

        assert len(result) == 1
        assert result[0] == {"single_file.py"}

    def test_parse_empty_log(self, empty_git_log):
        assert co_changes.parse_git_log(empty_git_log) == []

    def test_parse_handles_file_names_with_spaces(self):
        log_with_spaces = """abc1234567890123456789012345678901234567
src/my file.py
tests/test file.py
"""

        result = co_changes.parse_git_log(log_with_spaces)

        assert result[0] == {"src/my file.py", "tests/test file.py"}


class TestRepoWideAnalysis:
    """Tests for repo-wide pair analysis."""

    def test_build_matrix_with_multiple_co_changes(self, sample_git_log_co_changes):
        commits = co_changes.parse_git_log(sample_git_log_co_changes)

        co_matrix, file_counts = co_changes.build_co_occurrence_matrix(commits)

        assert co_matrix["file_a.py"]["file_b.py"] == 3
        assert co_matrix["file_a.py"]["file_c.py"] == 2
        assert file_counts == {"file_a.py": 4, "file_b.py": 4, "file_c.py": 3}

    def test_calculate_correlations_returns_expected_pairs(self, sample_git_log_co_changes):
        commits = co_changes.parse_git_log(sample_git_log_co_changes)
        co_matrix, file_counts = co_changes.build_co_occurrence_matrix(commits)

        correlations = co_changes.calculate_correlations(co_matrix, file_counts, 0.65)

        assert [item["file_a"] for item in correlations] == ["file_a.py", "file_a.py", "file_b.py"]
        assert [item["file_b"] for item in correlations] == ["file_b.py", "file_c.py", "file_c.py"]
        assert correlations[0]["correlation"] == 0.75
        assert correlations[1]["correlation"] == 2 / 3
        assert correlations[2]["correlation"] == 2 / 3

    def test_limit_correlations_preserves_existing_order(self):
        correlations = [
            {
                "file_a": "a",
                "file_b": "b",
                "correlation": 0.9,
                "co_changes": 3,
                "changes_a": 3,
                "changes_b": 3,
            },
            {
                "file_a": "a",
                "file_b": "c",
                "correlation": 0.8,
                "co_changes": 2,
                "changes_a": 3,
                "changes_b": 2,
            },
        ]

        assert co_changes.limit_correlations(correlations, 1) == correlations[:1]


class TestFileModeAnalysis:
    """Tests for target-file co-change analysis."""

    def test_calculate_target_correlations_focuses_on_one_file(self, sample_git_log_co_changes):
        commits = co_changes.parse_git_log(sample_git_log_co_changes)

        correlations = co_changes.calculate_target_correlations(commits, "file_a.py", 0.50)

        assert correlations == [
            {
                "file_a": "file_a.py",
                "file_b": "file_b.py",
                "correlation": 0.75,
                "co_changes": 3,
                "changes_a": 4,
                "changes_b": 4,
            },
            {
                "file_a": "file_a.py",
                "file_b": "file_c.py",
                "correlation": 2 / 3,
                "co_changes": 2,
                "changes_a": 4,
                "changes_b": 3,
            },
        ]

    def test_calculate_target_correlations_returns_empty_when_target_missing(
        self, sample_git_log_co_changes
    ):
        commits = co_changes.parse_git_log(sample_git_log_co_changes)

        correlations = co_changes.calculate_target_correlations(commits, "missing.py", 0.0)

        assert correlations == []


class TestFormatting:
    """Tests for text and JSON formatting."""

    def test_format_text_output_includes_repo_header(self):
        output = co_changes.format_text_output([], 0.3, 10)

        assert "10 commits" in output
        assert "30%" in output
        assert "No file pairs found above threshold." in output

    def test_format_target_text_output_includes_target_context(self):
        correlations = [
            {
                "file_a": "file_a.py",
                "file_b": "file_b.py",
                "correlation": 0.75,
                "co_changes": 3,
                "changes_a": 4,
                "changes_b": 4,
            }
        ]

        output = co_changes.format_target_text_output("file_a.py", correlations, 0.5, 5, 4)

        assert "Related files for file_a.py" in output
        assert "Target file changed in 4 analyzed commits." in output
        assert "file_b.py" in output
        assert "↔" not in output

    def test_format_json_output_includes_file_mode_metadata(self):
        output = co_changes.format_json_output(
            mode="file",
            correlations=[],
            total_commits=5,
            threshold=0.4,
            target_file="file_a.py",
            target_changes=2,
        )

        result = json.loads(output)
        assert result == {
            "mode": "file",
            "commits_analyzed": 5,
            "threshold": 0.4,
            "result_count": 0,
            "correlations": [],
            "target_file": "file_a.py",
            "target_changes": 2,
        }


class TestMainFunction:
    """Integration tests for main() argument modes."""

    def test_main_outputs_file_mode_json(self, sample_git_log_co_changes, monkeypatch, capsys):
        monkeypatch.setattr(sys, "stdin", StringIO(sample_git_log_co_changes))
        monkeypatch.setattr(
            sys,
            "argv",
            [
                "co_changes.py",
                "--target-file",
                "file_a.py",
                "--threshold",
                "0.5",
                "--format",
                "json",
            ],
        )

        exit_code = co_changes.main()
        captured = capsys.readouterr()

        assert exit_code == 0
        result = json.loads(captured.out)
        assert result["mode"] == "file"
        assert result["target_file"] == "file_a.py"
        assert result["result_count"] == 2

    def test_main_outputs_repo_wide_text(self, sample_git_log_co_changes, monkeypatch, capsys):
        monkeypatch.setattr(sys, "stdin", StringIO(sample_git_log_co_changes))
        monkeypatch.setattr(
            sys,
            "argv",
            ["co_changes.py", "--all", "--threshold", "0.5", "--format", "text"],
        )

        exit_code = co_changes.main()
        captured = capsys.readouterr()

        assert exit_code == 0
        assert "Co-change Analysis" in captured.out
        assert "file_a.py ↔ file_b.py" in captured.out

    def test_main_handles_empty_input(self, empty_git_log, monkeypatch, capsys):
        monkeypatch.setattr(sys, "stdin", StringIO(empty_git_log))
        monkeypatch.setattr(sys, "argv", ["co_changes.py", "--all"])

        exit_code = co_changes.main()
        captured = capsys.readouterr()

        assert exit_code == 1
        assert "Error: No input provided" in captured.err


class TestEdgeCases:
    """Boundary-condition tests."""

    def test_handles_large_commit_lists(self):
        large_log_parts = []
        for i in range(100):
            hash_val = f"{i:040x}"
            large_log_parts.append(hash_val)
            large_log_parts.append(f"file_{i % 10}.py")
            large_log_parts.append("")

        large_log = "\n".join(large_log_parts)

        result = co_changes.parse_git_log(large_log)

        assert len(result) == 100

    def test_handles_very_high_threshold(self, sample_git_log_co_changes):
        commits = co_changes.parse_git_log(sample_git_log_co_changes)
        co_matrix, file_counts = co_changes.build_co_occurrence_matrix(commits)

        correlations = co_changes.calculate_correlations(co_matrix, file_counts, 1.0)

        assert correlations == []
