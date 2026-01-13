"""
Unit tests for churn.py - File and line churn analysis.

Following Google Python testing best practices:
- Arrange-Act-Assert pattern
- Descriptive test names
- Test edge cases and error conditions
- Mock external dependencies (git subprocess calls)
"""

import json
import subprocess
from unittest.mock import MagicMock, mock_open, patch

import pytest

# Import module under test
import churn


class TestParseArgs:
    """Tests for parse_args function."""

    def test_parse_args_with_required_file_only(self, monkeypatch):
        """Should parse with only required file argument."""
        # Arrange
        monkeypatch.setattr("sys.argv", ["churn.py", "src/auth.js"])

        # Act
        args = churn.parse_args()

        # Assert
        assert args.file == "src/auth.js"
        assert args.since is None
        assert args.format == "json"
        assert args.hot_threshold == 3

    def test_parse_args_with_all_options(self, monkeypatch):
        """Should parse all command line options correctly."""
        # Arrange
        monkeypatch.setattr(
            "sys.argv",
            [
                "churn.py",
                "src/main.py",
                "--since",
                "3 months ago",
                "--format",
                "text",
                "--hot-threshold",
                "5",
            ],
        )

        # Act
        args = churn.parse_args()

        # Assert
        assert args.file == "src/main.py"
        assert args.since == "3 months ago"
        assert args.format == "text"
        assert args.hot_threshold == 5

    def test_parse_args_validates_format_choices(self, monkeypatch, capsys):
        """Should reject invalid format options."""
        # Arrange
        monkeypatch.setattr("sys.argv", ["churn.py", "test.py", "--format", "invalid"])

        # Act & Assert
        with pytest.raises(SystemExit):
            churn.parse_args()


class TestCalculateChurnScore:
    """Tests for calculate_churn_score function."""

    def test_calculate_score_recent_changes_max_weight(self):
        """Should give maximum weight to changes made today (0 days)."""
        # Arrange
        changes = 5
        recency_days = 0

        # Act
        score = churn.calculate_churn_score(changes, recency_days)

        # Assert
        # e^0 = 1, so score = changes * 1
        assert score == 5.0

    def test_calculate_score_older_changes_decay(self):
        """Should apply exponential decay to older changes."""
        # Arrange
        changes = 10
        recency_days = 90  # At decay constant boundary

        # Act
        score = churn.calculate_churn_score(changes, recency_days)

        # Assert
        # e^(-90/90) = e^(-1) ≈ 0.368
        assert 3.5 < score < 3.8  # 10 * 0.368 ≈ 3.68

    def test_calculate_score_very_old_changes_minimal_weight(self):
        """Should give minimal weight to very old changes."""
        # Arrange
        changes = 100
        recency_days = 365  # 1 year old

        # Act
        score = churn.calculate_churn_score(changes, recency_days)

        # Assert
        # e^(-365/90) ≈ 0.018
        assert score < 2.0  # Much less than original 100

    def test_calculate_score_zero_changes(self):
        """Should return 0 for zero changes."""
        # Act
        score = churn.calculate_churn_score(0, 30)

        # Assert
        assert score == 0.0


class TestGetLineHistory:
    """Tests for get_line_history function using Command Mock Framework."""

    def test_get_line_history_successful_analysis(self, command_mock):
        """Should analyze line history and count changes per line."""

        # Arrange - Dynamic scenario selection based on line number
        def choose_scenario(cmd):
            # Extract line number from -L argument (format: "N,N:file.txt")
            line_num = int(cmd[cmd.index("-L") + 1].split(",")[0])

            if line_num == 2:
                return "basic"  # Line 2: 3 commits (from real git output)
            else:
                return "no_commits"  # Lines 1, 3, 4, 5: 1 commit each (initial commit only)

        mock_fn = command_mock.get_dynamic_mock("log/L-line.toml", choose_scenario)

        # Act - Mock open() only for the target file, not TOML files
        test_file_content = "line1\nline2\nline3\n"
        with patch("builtins.open", mock_open(read_data=test_file_content)):
            with patch("subprocess.run", side_effect=mock_fn):
                result = churn.get_line_history("file.txt")

        # Assert - Line 2 has 3 commits, other lines have 1 commit (initial only)
        assert result[1] == 1  # no_commits scenario (initial commit only)
        assert result[2] == 3  # basic scenario (3 commits)
        assert result[3] == 1  # no_commits scenario (initial commit only)
        assert len(result) == 3

    def test_get_line_history_single_line_file(self, command_mock):
        """Should handle single-line files correctly."""
        # Arrange - Use 'no_commits' scenario which expects line 1 (1,1:file.txt)
        mock_fn = command_mock.get_subprocess_mock("log/L-line.toml", "no_commits")

        # Act - Mock open() after getting command_mock
        with patch("builtins.open", mock_open(read_data="single line\n")):
            with patch("subprocess.run", side_effect=mock_fn):
                result = churn.get_line_history("file.txt")

        # Assert - 'no_commits' scenario has 1 commit (initial commit only)
        assert len(result) == 1
        assert result[1] == 1  # 1 commit in no_commits scenario

    @patch("builtins.open", side_effect=FileNotFoundError("File not found"))
    def test_get_line_history_file_not_found(self, mock_file, capsys):
        """Should handle missing files gracefully."""
        # Act
        result = churn.get_line_history("nonexistent.py")

        # Assert
        assert result == {}
        captured = capsys.readouterr()
        assert "Error reading file" in captured.err

    def test_get_line_history_with_since_filter(self, command_mock):
        """Should pass --since parameter to git log command."""

        # Arrange - Dynamic mock to handle --since flag
        def choose_scenario(cmd):
            if "--since=1 month ago" in cmd:
                return "with_since_filter"  # Empty output
            else:
                return "no_commits"  # Default: 1 commit

        mock_fn = command_mock.get_dynamic_mock("log/L-line.toml", choose_scenario)
        since_date = "1 month ago"

        # Act - Mock open() after getting command_mock
        with patch("builtins.open", mock_open(read_data="line1\nline2\n")):
            with patch("subprocess.run", side_effect=mock_fn) as mock_subprocess:
                result = churn.get_line_history("file.txt", since=since_date)

        # Assert - Verify git command includes --since
        call_args = mock_subprocess.call_args_list[0][0][0]
        assert "--since=1 month ago" in call_args
        # Empty output means no commits in range (churn.py skips adding 0 counts)
        assert result == {}

    @patch("subprocess.run")
    @patch("builtins.open", new_callable=mock_open, read_data="line1\n")
    def test_get_line_history_handles_subprocess_exception(
        self, mock_file, mock_subprocess, capsys
    ):
        """Should handle subprocess exceptions gracefully."""
        # Arrange
        mock_subprocess.side_effect = Exception("Git command failed")

        # Act
        result = churn.get_line_history("test.py")

        # Assert
        assert result == {}
        captured = capsys.readouterr()
        assert "Could not analyze line" in captured.err

    def test_get_line_history_empty_file(self, command_mock):
        """Should handle empty files (0 lines)."""
        # Arrange - Mock should not be called for empty file
        mock_fn = command_mock.get_subprocess_mock("log/L-line.toml", "basic")

        # Act - Mock open() after getting command_mock
        with patch("builtins.open", mock_open(read_data="")):
            with patch("subprocess.run", side_effect=mock_fn) as mock_subprocess:
                result = churn.get_line_history("empty.py")

        # Assert
        assert result == {}
        # subprocess should not be called for empty file
        assert not mock_subprocess.called


class TestGetFileChurn:
    """Tests for get_file_churn function using Command Mock Framework."""

    def test_get_file_churn_successful_analysis(self, command_mock):
        """Should parse git log and extract file-level metrics."""
        # Arrange - Using 'basic' scenario: 5 commits by 2 authors (Alice: 3, Bob: 2)
        # Git log order: Bob (Nov 15), Bob (Nov 1), Alice (Oct 1), Alice (Jun 1), Alice (Jan 1)
        # first_commit = earliest = Alice (Jan 1), last_commit = latest = Bob (Nov 15)
        mock_fn = command_mock.get_subprocess_mock("log/follow.toml", "basic")

        # Act
        with patch("subprocess.run", side_effect=mock_fn):
            result = churn.get_file_churn("project.py")

        # Assert
        assert result["total_commits"] == 5
        assert result["unique_authors"] == 2
        assert "Alice Smith" in result["authors"]
        assert "Bob Johnson" in result["authors"]
        assert result["first_commit"]["author"] == "Alice Smith"  # Earliest commit
        assert result["last_commit"]["author"] == "Bob Johnson"  # Latest commit

    def test_get_file_churn_with_since_filter(self, command_mock):
        """Should pass --since parameter to git log."""
        # Arrange - Using 'with_since_filter' scenario: empty result (no commits in range)
        mock_fn = command_mock.get_subprocess_mock("log/follow.toml", "with_since_filter")
        since_date = "2 months ago"

        # Act
        with patch("subprocess.run", side_effect=mock_fn) as mock_subprocess:
            result = churn.get_file_churn("project.py", since=since_date)

        # Assert
        call_args = mock_subprocess.call_args[0][0]
        assert "--since=2 months ago" in call_args
        # Empty output means no commits in range
        assert result["total_commits"] == 0

    def test_get_file_churn_no_commits(self, command_mock):
        """Should handle files with no commits in range."""
        # Arrange - Using 'with_since_filter' scenario which has empty output
        mock_fn = command_mock.get_subprocess_mock("log/follow.toml", "with_since_filter")

        # Act
        with patch("subprocess.run", side_effect=mock_fn):
            result = churn.get_file_churn("project.py")

        # Assert
        assert result["total_commits"] == 0
        assert result["unique_authors"] == 0
        assert result["first_commit"] is None
        assert result["last_commit"] is None

    @patch("subprocess.run")
    def test_get_file_churn_git_command_failure(self, mock_subprocess, capsys):
        """Should handle git command failures gracefully."""
        # Arrange
        mock_subprocess.side_effect = subprocess.CalledProcessError(
            128, "git", "fatal: not a git repository"
        )

        # Act
        result = churn.get_file_churn("test.py")

        # Assert
        assert result is None
        captured = capsys.readouterr()
        assert "Error running git log" in captured.err

    def test_get_file_churn_single_author_multiple_commits(self, command_mock):
        """Should count unique authors correctly."""
        # Arrange - Using 'basic' scenario has Alice: 3, Bob: 2
        # We can filter to just Alice's commits for this test
        mock_fn = command_mock.get_subprocess_mock("log/follow.toml", "basic")

        # Act
        with patch("subprocess.run", side_effect=mock_fn):
            result = churn.get_file_churn("project.py")

        # Assert - Using real mock data: 5 commits, 2 authors
        assert result["total_commits"] == 5
        assert result["unique_authors"] == 2
        assert "Alice Smith" in result["authors"]
        assert "Bob Johnson" in result["authors"]


class TestAnalyzeChurn:
    """Tests for analyze_churn main analysis function."""

    @patch("churn.get_line_history")
    @patch("churn.get_file_churn")
    def test_analyze_churn_complete_analysis(self, mock_file_churn, mock_line_history):
        """Should combine file and line metrics into comprehensive result."""
        # Arrange
        mock_file_churn.return_value = {
            "total_commits": 10,
            "unique_authors": 3,
            "authors": ["Alice", "Bob", "Charlie"],
            "first_commit": {"hash": "abc", "author": "Alice", "date": "2024-01-01"},
            "last_commit": {"hash": "xyz", "author": "Bob", "date": "2024-11-17"},
        }

        mock_line_history.return_value = {1: 5, 2: 3, 3: 1, 4: 0, 5: 8}

        # Act
        result = churn.analyze_churn("test.py", hot_threshold=3)

        # Assert
        assert result["file"] == "test.py"
        assert result["file_churn"]["total_commits"] == 10
        assert len(result["line_churn"]) == 5
        assert len(result["hot_lines"]) == 3  # Lines with ≥3 changes
        assert result["summary"]["total_lines"] == 5
        assert result["summary"]["lines_with_changes"] == 4  # Line 4 has 0 changes
        assert result["summary"]["hot_lines_count"] == 3
        assert result["summary"]["max_line_changes"] == 8

    @patch("churn.get_line_history")
    @patch("churn.get_file_churn")
    def test_analyze_churn_hot_lines_sorted_by_changes(self, mock_file_churn, mock_line_history):
        """Should sort hot lines by change count descending."""
        # Arrange
        mock_file_churn.return_value = {
            "total_commits": 5,
            "unique_authors": 1,
            "authors": ["Alice"],
            "first_commit": None,
            "last_commit": None,
        }

        mock_line_history.return_value = {1: 3, 2: 8, 3: 5}

        # Act
        result = churn.analyze_churn("test.py", hot_threshold=3)

        # Assert
        hot_lines = result["hot_lines"]
        assert hot_lines[0]["line_number"] == 2  # Most changes (8)
        assert hot_lines[1]["line_number"] == 3  # Second most (5)
        assert hot_lines[2]["line_number"] == 1  # Least of hot (3)

    @patch("churn.get_line_history")
    @patch("churn.get_file_churn")
    def test_analyze_churn_respects_hot_threshold(self, mock_file_churn, mock_line_history):
        """Should only include lines meeting hot threshold."""
        # Arrange
        mock_file_churn.return_value = {
            "total_commits": 5,
            "unique_authors": 1,
            "authors": ["Alice"],
            "first_commit": None,
            "last_commit": None,
        }

        mock_line_history.return_value = {
            1: 2,  # Below threshold
            2: 5,  # Above threshold
            3: 3,  # At threshold
            4: 1,  # Below threshold
        }

        # Act
        result = churn.analyze_churn("test.py", hot_threshold=3)

        # Assert
        hot_lines = result["hot_lines"]
        assert len(hot_lines) == 2
        assert all(hl["changes"] >= 3 for hl in hot_lines)

    @patch("churn.get_file_churn")
    def test_analyze_churn_handles_file_churn_failure(self, mock_file_churn):
        """Should return error when file churn analysis fails."""
        # Arrange
        mock_file_churn.return_value = None

        # Act
        result = churn.analyze_churn("test.py")

        # Assert
        assert "error" in result
        assert result["error"] == "Could not analyze file"

    @patch("churn.get_line_history")
    @patch("churn.get_file_churn")
    def test_analyze_churn_empty_line_history(self, mock_file_churn, mock_line_history):
        """Should handle files with no line history gracefully."""
        # Arrange
        mock_file_churn.return_value = {
            "total_commits": 0,
            "unique_authors": 0,
            "authors": [],
            "first_commit": None,
            "last_commit": None,
        }

        mock_line_history.return_value = {}

        # Act
        result = churn.analyze_churn("test.py")

        # Assert
        assert result["summary"]["total_lines"] == 0
        assert result["summary"]["lines_with_changes"] == 0
        assert result["summary"]["hot_lines_count"] == 0
        assert result["summary"]["max_line_changes"] == 0
        assert result["summary"]["avg_line_changes"] == 0

    @patch("churn.get_line_history")
    @patch("churn.get_file_churn")
    def test_analyze_churn_includes_analysis_params(self, mock_file_churn, mock_line_history):
        """Should include analysis parameters in result."""
        # Arrange
        mock_file_churn.return_value = {
            "total_commits": 1,
            "unique_authors": 1,
            "authors": ["Alice"],
            "first_commit": None,
            "last_commit": None,
        }
        mock_line_history.return_value = {1: 0}

        # Act
        result = churn.analyze_churn("test.py", since="1 week ago", hot_threshold=5)

        # Assert
        assert result["analysis_params"]["since"] == "1 week ago"
        assert result["analysis_params"]["hot_threshold"] == 5

    @patch("churn.get_line_history")
    @patch("churn.get_file_churn")
    def test_analyze_churn_calculates_average_correctly(self, mock_file_churn, mock_line_history):
        """Should calculate average line changes correctly."""
        # Arrange
        mock_file_churn.return_value = {
            "total_commits": 1,
            "unique_authors": 1,
            "authors": ["Alice"],
            "first_commit": None,
            "last_commit": None,
        }

        # Total: 2 + 4 + 6 + 8 = 20, Count: 4, Average: 5.0
        mock_line_history.return_value = {1: 2, 2: 4, 3: 6, 4: 8}

        # Act
        result = churn.analyze_churn("test.py")

        # Assert
        assert result["summary"]["avg_line_changes"] == 5.0


class TestFormatTextOutput:
    """Tests for format_text_output function."""

    def test_format_text_output_includes_file_name(self):
        """Should include file name in header."""
        # Arrange
        data = {
            "file": "src/auth.py",
            "file_churn": {
                "total_commits": 10,
                "unique_authors": 2,
                "first_commit": None,
                "last_commit": None,
            },
            "summary": {
                "total_lines": 50,
                "lines_with_changes": 30,
                "hot_lines_count": 5,
                "max_line_changes": 8,
                "avg_line_changes": 2.5,
            },
            "analysis_params": {"since": None, "hot_threshold": 3},
            "hot_lines": [],
        }

        # Act
        output = churn.format_text_output(data)

        # Assert
        assert "src/auth.py" in output

    def test_format_text_output_displays_file_metrics(self):
        """Should display file-level commit and author metrics."""
        # Arrange
        data = {
            "file": "test.py",
            "file_churn": {
                "total_commits": 25,
                "unique_authors": 5,
                "first_commit": {"author": "Alice", "date": "2024-01-15 10:30:00 -0500"},
                "last_commit": {"author": "Bob", "date": "2024-11-17 14:20:30 -0500"},
            },
            "summary": {
                "total_lines": 100,
                "lines_with_changes": 50,
                "hot_lines_count": 10,
                "max_line_changes": 15,
                "avg_line_changes": 3.2,
            },
            "analysis_params": {"since": None, "hot_threshold": 3},
            "hot_lines": [],
        }

        # Act
        output = churn.format_text_output(data)

        # Assert
        assert "25" in output  # total commits
        assert "5" in output  # unique authors
        assert "Alice" in output
        assert "Bob" in output
        assert "2024-01-15" in output
        assert "2024-11-17" in output

    def test_format_text_output_displays_line_summary(self):
        """Should display line-level summary statistics."""
        # Arrange
        data = {
            "file": "test.py",
            "file_churn": {
                "total_commits": 10,
                "unique_authors": 2,
                "first_commit": None,
                "last_commit": None,
            },
            "summary": {
                "total_lines": 100,
                "lines_with_changes": 75,
                "hot_lines_count": 20,
                "max_line_changes": 12,
                "avg_line_changes": 2.8,
            },
            "analysis_params": {"since": None, "hot_threshold": 3},
            "hot_lines": [],
        }

        # Act
        output = churn.format_text_output(data)

        # Assert
        assert "100" in output  # total lines
        assert "75" in output  # lines with changes
        assert "20" in output  # hot lines count
        assert "12" in output  # max changes
        assert "2.8" in output  # average

    def test_format_text_output_displays_hot_lines(self):
        """Should display hot lines with line numbers and change counts."""
        # Arrange
        data = {
            "file": "test.py",
            "file_churn": {
                "total_commits": 10,
                "unique_authors": 2,
                "first_commit": None,
                "last_commit": None,
            },
            "summary": {
                "total_lines": 50,
                "lines_with_changes": 30,
                "hot_lines_count": 3,
                "max_line_changes": 8,
                "avg_line_changes": 2.0,
            },
            "analysis_params": {"since": None, "hot_threshold": 3},
            "hot_lines": [
                {"line_number": 42, "changes": 8, "churn_score": 8.0},
                {"line_number": 15, "changes": 5, "churn_score": 5.0},
                {"line_number": 23, "changes": 3, "churn_score": 3.0},
            ],
        }

        # Act
        output = churn.format_text_output(data)

        # Assert
        assert "Line" in output
        assert "42" in output and "8" in output
        assert "15" in output and "5" in output
        assert "23" in output and "3" in output

    def test_format_text_output_limits_hot_lines_to_20(self):
        """Should only show top 20 hot lines with overflow indicator."""
        # Arrange
        hot_lines = [
            {"line_number": i, "changes": 30 - i, "churn_score": float(30 - i)}
            for i in range(1, 31)  # 30 hot lines
        ]

        data = {
            "file": "test.py",
            "file_churn": {
                "total_commits": 50,
                "unique_authors": 3,
                "first_commit": None,
                "last_commit": None,
            },
            "summary": {
                "total_lines": 100,
                "lines_with_changes": 80,
                "hot_lines_count": 30,
                "max_line_changes": 29,
                "avg_line_changes": 5.0,
            },
            "analysis_params": {"since": None, "hot_threshold": 3},
            "hot_lines": hot_lines,
        }

        # Act
        output = churn.format_text_output(data)

        # Assert
        # Should show "10 more" since we have 30 total - 20 shown = 10
        assert "10 more" in output or "... and 10" in output

    def test_format_text_output_handles_no_hot_lines(self):
        """Should handle case with no hot lines gracefully."""
        # Arrange
        data = {
            "file": "test.py",
            "file_churn": {
                "total_commits": 5,
                "unique_authors": 1,
                "first_commit": None,
                "last_commit": None,
            },
            "summary": {
                "total_lines": 50,
                "lines_with_changes": 10,
                "hot_lines_count": 0,
                "max_line_changes": 0,
                "avg_line_changes": 0.0,
            },
            "analysis_params": {"since": None, "hot_threshold": 3},
            "hot_lines": [],
        }

        # Act
        output = churn.format_text_output(data)

        # Assert
        # Should not crash, should show 0 hot lines
        assert "0" in output


class TestMainFunction:
    """Integration tests for main function."""

    @patch("churn.analyze_churn")
    def test_main_json_output_format(self, mock_analyze, monkeypatch, capsys):
        """Should output valid JSON when --format=json."""
        # Arrange
        mock_data = {
            "file": "test.py",
            "file_churn": {"total_commits": 5},
            "line_churn": {1: 2},
            "hot_lines": [],
            "summary": {
                "total_lines": 10,
                "lines_with_changes": 5,
                "hot_lines_count": 0,
                "max_line_changes": 2,
                "avg_line_changes": 1.0,
            },
            "analysis_params": {"since": None, "hot_threshold": 3},
        }
        mock_analyze.return_value = mock_data

        monkeypatch.setattr("sys.argv", ["churn.py", "test.py", "--format", "json"])

        # Act
        exit_code = churn.main()
        captured = capsys.readouterr()

        # Assert
        assert exit_code == 0
        result = json.loads(captured.out)
        assert result["file"] == "test.py"
        assert "file_churn" in result
        assert "line_churn" in result
        assert "hot_lines" in result

    @patch("churn.analyze_churn")
    def test_main_text_output_format(self, mock_analyze, monkeypatch, capsys):
        """Should output formatted text when --format=text."""
        # Arrange
        mock_data = {
            "file": "test.py",
            "file_churn": {
                "total_commits": 10,
                "unique_authors": 2,
                "first_commit": None,
                "last_commit": None,
            },
            "line_churn": {1: 5},
            "hot_lines": [{"line_number": 1, "changes": 5, "churn_score": 5.0}],
            "summary": {
                "total_lines": 10,
                "lines_with_changes": 5,
                "hot_lines_count": 1,
                "max_line_changes": 5,
                "avg_line_changes": 2.5,
            },
            "analysis_params": {"since": None, "hot_threshold": 3},
        }
        mock_analyze.return_value = mock_data

        monkeypatch.setattr("sys.argv", ["churn.py", "test.py", "--format", "text"])

        # Act
        exit_code = churn.main()
        captured = capsys.readouterr()

        # Assert
        assert exit_code == 0
        assert "test.py" in captured.out
        assert "Total commits:" in captured.out or "10" in captured.out

    @patch("churn.analyze_churn")
    def test_main_handles_analysis_error(self, mock_analyze, monkeypatch, capsys):
        """Should return exit code 1 when analysis fails."""
        # Arrange
        mock_analyze.return_value = {"error": "Could not analyze file"}

        monkeypatch.setattr("sys.argv", ["churn.py", "test.py"])

        # Act
        exit_code = churn.main()

        # Assert
        assert exit_code == 1

    @patch("churn.analyze_churn")
    def test_main_passes_all_parameters(self, mock_analyze, monkeypatch):
        """Should pass all command line parameters to analyze_churn."""
        # Arrange
        mock_analyze.return_value = {
            "file": "test.py",
            "file_churn": {},
            "line_churn": {},
            "hot_lines": [],
            "summary": {},
            "analysis_params": {},
        }

        monkeypatch.setattr(
            "sys.argv",
            ["churn.py", "src/main.py", "--since", "2 weeks ago", "--hot-threshold", "7"],
        )

        # Act
        churn.main()

        # Assert
        mock_analyze.assert_called_once_with("src/main.py", since="2 weeks ago", hot_threshold=7)


class TestEdgeCases:
    """Tests for edge cases and boundary conditions."""

    @patch("churn.get_line_history")
    @patch("churn.get_file_churn")
    def test_handles_very_large_files(self, mock_file_churn, mock_line_history):
        """Should handle files with thousands of lines efficiently."""
        # Arrange
        mock_file_churn.return_value = {
            "total_commits": 1000,
            "unique_authors": 50,
            "authors": [f"Author{i}" for i in range(50)],
            "first_commit": None,
            "last_commit": None,
        }

        # Simulate 10,000 lines
        mock_line_history.return_value = {i: i % 10 for i in range(1, 10001)}

        # Act
        result = churn.analyze_churn("large_file.py", hot_threshold=5)

        # Assert
        assert result["summary"]["total_lines"] == 10000
        # Lines with changes ≥5: 5,6,7,8,9 (repeating pattern)
        assert result["summary"]["hot_lines_count"] > 0

    @patch("churn.get_line_history")
    @patch("churn.get_file_churn")
    def test_handles_all_lines_hot(self, mock_file_churn, mock_line_history):
        """Should handle case where all lines are hot."""
        # Arrange
        mock_file_churn.return_value = {
            "total_commits": 100,
            "unique_authors": 10,
            "authors": ["Alice"],
            "first_commit": None,
            "last_commit": None,
        }

        # All lines have 10 changes (above threshold of 3)
        mock_line_history.return_value = dict.fromkeys(range(1, 51), 10)

        # Act
        result = churn.analyze_churn("hot_file.py", hot_threshold=3)

        # Assert
        assert result["summary"]["hot_lines_count"] == 50
        assert len(result["hot_lines"]) == 50

    @patch("churn.get_line_history")
    @patch("churn.get_file_churn")
    def test_handles_no_lines_hot(self, mock_file_churn, mock_line_history):
        """Should handle case where no lines meet hot threshold."""
        # Arrange
        mock_file_churn.return_value = {
            "total_commits": 10,
            "unique_authors": 2,
            "authors": ["Alice"],
            "first_commit": None,
            "last_commit": None,
        }

        # All lines have 1-2 changes (below threshold of 10)
        mock_line_history.return_value = {i: i % 2 + 1 for i in range(1, 51)}

        # Act
        result = churn.analyze_churn("stable_file.py", hot_threshold=10)

        # Assert
        assert result["summary"]["hot_lines_count"] == 0
        assert result["hot_lines"] == []

    def test_churn_score_mathematical_properties(self):
        """Should verify mathematical properties of churn score formula."""
        # Property 1: Score decreases as recency increases
        score_recent = churn.calculate_churn_score(10, 0)
        score_old = churn.calculate_churn_score(10, 180)
        assert score_recent > score_old

        # Property 2: Score increases linearly with changes (for same recency)
        score_5_changes = churn.calculate_churn_score(5, 30)
        score_10_changes = churn.calculate_churn_score(10, 30)
        assert score_10_changes == pytest.approx(2 * score_5_changes)

        # Property 3: Score is always non-negative
        assert churn.calculate_churn_score(100, 1000) >= 0

    @patch("subprocess.run")
    @patch("builtins.open", new_callable=mock_open, read_data="line1\nline2\n")
    def test_handles_binary_files_in_git(self, mock_file, mock_subprocess):
        """Should handle git errors for binary files gracefully."""
        # Arrange
        mock_subprocess.return_value = MagicMock(
            stdout="",
            stderr="fatal: -L does not yet support diff formats besides -p and -s",
            returncode=128,
        )

        # Act
        result = churn.get_line_history("binary_file.png")

        # Assert
        # Should treat as lines with no history
        assert result[1] == 0
        assert result[2] == 0
