"""
Unit tests for activity.py - Temporal commit activity analysis.

Following Google Python testing best practices:
- Arrange-Act-Assert pattern
- Descriptive test names
- Test edge cases and error conditions
"""

import json
from io import StringIO
from unittest.mock import patch

# Import module under test
import activity


class TestParseGitLog:
    """Tests for parse_git_log function."""

    def test_parse_valid_log_with_multiple_commits(self, sample_git_log_activity):
        """Should parse git log with timestamp and author."""
        # Act
        result = activity.parse_git_log(sample_git_log_activity)

        # Assert
        assert len(result) == 8
        assert result[0]["author"] == "Alice Smith"
        assert "hour" in result[0]
        assert "day_of_week" in result[0]
        assert "datetime" in result[0]

    def test_parse_extracts_hour_correctly(self):
        """Should extract hour from timestamp."""
        # Arrange
        log = "2024-11-17 14:30:15 -0500|Alice Smith"

        # Act
        result = activity.parse_git_log(log)

        # Assert
        assert len(result) == 1
        assert result[0]["hour"] == 14

    def test_parse_extracts_day_of_week_correctly(self):
        """Should extract day of week as abbreviated string."""
        # Arrange - 2024-11-17 is a Sunday
        log = "2024-11-17 10:00:00 -0500|Alice Smith"

        # Act
        result = activity.parse_git_log(log)

        # Assert
        assert len(result) == 1
        assert result[0]["day_of_week"] == "Sun"

    def test_parse_handles_different_timezones(self):
        """Should handle different timezone offsets."""
        # Arrange
        logs = [
            "2024-11-17 10:00:00 -0500|Alice",
            "2024-11-17 10:00:00 +0000|Bob",
            "2024-11-17 10:00:00 +0900|Charlie",
        ]

        # Act
        for log_line in logs:
            result = activity.parse_git_log(log_line)

            # Assert
            assert len(result) == 1
            assert result[0]["hour"] == 10  # All should parse the hour correctly

    def test_parse_handles_malformed_lines(self):
        """Should skip malformed log lines gracefully."""
        # Arrange
        log = """2024-11-17 09:30:15 -0500|Alice Smith
invalid_line_without_pipe
2024-11-17 10:45:22 -0500|Bob Johnson
"""

        # Act
        result = activity.parse_git_log(log)

        # Assert
        # Should parse only valid lines
        assert len(result) == 2

    def test_parse_empty_log(self, empty_git_log):
        """Should return empty list for empty log."""
        # Act
        result = activity.parse_git_log(empty_git_log)

        # Assert
        assert result == []


class TestAnalyzeByHour:
    """Tests for analyze_by_hour function."""

    def test_analyze_groups_commits_by_hour(self, sample_git_log_activity):
        """Should group commits into hour buckets."""
        # Arrange
        commits = activity.parse_git_log(sample_git_log_activity)

        # Act
        result = activity.analyze_by_hour(commits, by_author=False)

        # Assert
        assert result["type"] == "by_hour"
        assert "data" in result
        # Should have hour buckets
        assert any(hour in result["data"] for hour in range(24))

    def test_analyze_counts_commits_per_hour(self):
        """Should count commits correctly for each hour."""
        # Arrange
        log = """2024-11-17 09:00:00 -0500|Alice
2024-11-17 09:30:00 -0500|Bob
2024-11-17 14:00:00 -0500|Charlie
2024-11-17 14:15:00 -0500|Alice
2024-11-17 14:45:00 -0500|Bob
"""
        commits = activity.parse_git_log(log)

        # Act
        result = activity.analyze_by_hour(commits, by_author=False)

        # Assert
        assert result["data"][9] == 2  # 9am: 2 commits
        assert result["data"][14] == 3  # 2pm: 3 commits

    def test_analyze_by_hour_and_author(self, sample_git_log_activity):
        """Should break down hour activity by author."""
        # Arrange
        commits = activity.parse_git_log(sample_git_log_activity)

        # Act
        result = activity.analyze_by_hour(commits, by_author=True)

        # Assert
        assert result["type"] == "by_hour_and_author"
        assert "Alice Smith" in result["data"]
        assert "Bob Johnson" in result["data"]
        # Each author should have hour buckets
        assert isinstance(result["data"]["Alice Smith"], dict)

    def test_analyze_handles_empty_commits(self):
        """Should handle empty commit list."""
        # Act
        result = activity.analyze_by_hour([], by_author=False)

        # Assert
        assert result["type"] == "by_hour"
        assert result["data"] == {}


class TestAnalyzeByDay:
    """Tests for analyze_by_day function."""

    def test_analyze_groups_commits_by_day_of_week(self, sample_git_log_activity):
        """Should group commits into day of week buckets."""
        # Arrange
        commits = activity.parse_git_log(sample_git_log_activity)

        # Act
        result = activity.analyze_by_day(commits, by_author=False)

        # Assert
        assert result["type"] == "by_day"
        assert "data" in result
        assert "day_order" in result
        assert result["day_order"] == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    def test_analyze_counts_commits_per_day(self):
        """Should count commits correctly for each day."""
        # Arrange - Mon=2024-11-18, Tue=2024-11-19, Wed=2024-11-20
        log = """2024-11-18 09:00:00 -0500|Alice
2024-11-18 10:00:00 -0500|Bob
2024-11-19 09:00:00 -0500|Charlie
2024-11-20 09:00:00 -0500|Alice
2024-11-20 10:00:00 -0500|Bob
2024-11-20 11:00:00 -0500|Charlie
"""
        commits = activity.parse_git_log(log)

        # Act
        result = activity.analyze_by_day(commits, by_author=False)

        # Assert
        assert result["data"]["Mon"] == 2  # Monday: 2 commits
        assert result["data"]["Tue"] == 1  # Tuesday: 1 commit
        assert result["data"]["Wed"] == 3  # Wednesday: 3 commits

    def test_analyze_by_day_and_author(self, sample_git_log_activity):
        """Should break down day activity by author."""
        # Arrange
        commits = activity.parse_git_log(sample_git_log_activity)

        # Act
        result = activity.analyze_by_day(commits, by_author=True)

        # Assert
        assert result["type"] == "by_day_and_author"
        assert "Alice Smith" in result["data"]
        assert "day_order" in result
        # Each author should have day buckets
        assert isinstance(result["data"]["Alice Smith"], dict)

    def test_analyze_handles_empty_commits(self):
        """Should handle empty commit list."""
        # Act
        result = activity.analyze_by_day([], by_author=False)

        # Assert
        assert result["type"] == "by_day"
        assert result["data"] == {}


class TestDetectPatterns:
    """Tests for detect_patterns function."""

    def test_detects_late_night_work_by_hour(self):
        """Should detect late night commits (10pm-4am)."""
        # Arrange - Heavy late night activity
        analysis = {
            "type": "by_hour",
            "data": {
                0: 5,  # midnight
                1: 3,  # 1am
                22: 8,  # 10pm
                23: 6,  # 11pm
                9: 10,  # 9am
                14: 15,  # 2pm
            },
        }

        # Act
        observations = activity.detect_patterns(analysis)

        # Assert
        # Late night commits: 5+3+8+6 = 22 out of 47 total = 46.8%
        assert any("late night" in obs.lower() for obs in observations)
        assert any("⚠️" in obs for obs in observations)

    def test_detects_peak_hour(self):
        """Should identify peak activity hour."""
        # Arrange
        analysis = {
            "type": "by_hour",
            "data": {
                9: 10,
                10: 25,  # Peak
                14: 15,
            },
        }

        # Act
        observations = activity.detect_patterns(analysis)

        # Assert
        assert any("Peak activity: 10:00" in obs for obs in observations)
        assert any("25 commits" in obs for obs in observations)

    def test_detects_weekend_work_by_day(self):
        """Should detect weekend commits."""
        # Arrange - Heavy weekend activity
        analysis = {
            "type": "by_day",
            "data": {
                "Mon": 20,
                "Tue": 18,
                "Wed": 22,
                "Thu": 19,
                "Fri": 21,
                "Sat": 15,  # Saturday
                "Sun": 12,  # Sunday
            },
        }

        # Act
        observations = activity.detect_patterns(analysis)

        # Assert
        # Weekend: 15+12 = 27 out of 127 total = 21.3%
        assert any("weekend" in obs.lower() for obs in observations)
        assert any("⚠️" in obs for obs in observations)

    def test_detects_most_active_day(self):
        """Should identify most active day of week."""
        # Arrange
        analysis = {
            "type": "by_day",
            "data": {
                "Mon": 10,
                "Wed": 25,  # Peak
                "Fri": 15,
            },
        }

        # Act
        observations = activity.detect_patterns(analysis)

        # Assert
        assert any("Most active day: Wed" in obs for obs in observations)

    def test_no_warnings_for_healthy_patterns(self):
        """Should not generate warnings for healthy work patterns."""
        # Arrange - Normal work hours, weekdays only
        analysis = {"type": "by_hour", "data": {9: 10, 10: 15, 14: 12, 15: 8}}

        # Act
        observations = activity.detect_patterns(analysis)

        # Assert
        warnings = [obs for obs in observations if "⚠️" in obs]
        # No late night work, so no late night warnings
        late_night_warnings = [obs for obs in warnings if "late night" in obs.lower()]
        assert len(late_night_warnings) == 0

    def test_handles_empty_data(self):
        """Should handle empty analysis data."""
        # Arrange
        analysis = {"type": "by_hour", "data": {}}

        # Act
        observations = activity.detect_patterns(analysis)

        # Assert
        # Should not crash, may return empty or minimal observations
        assert isinstance(observations, list)


class TestCreateHistogram:
    """Tests for create_histogram function."""

    def test_creates_bars_proportional_to_counts(self):
        """Should create bars scaled to maximum value."""
        # Arrange
        data = {
            9: 10,
            10: 20,  # Maximum
            14: 15,
        }

        # Act
        result = activity.create_histogram(data, max_width=40)

        # Assert
        assert len(result) == 3
        # Hour 10 should have longest bar (full width)
        hour_10_line = next(line for line in result if line.startswith("10:00"))
        assert "█" * 40 in hour_10_line
        assert "20" in hour_10_line

    def test_formats_hours_with_leading_zeros(self):
        """Should format single-digit hours with leading zeros."""
        # Arrange
        data = {5: 10, 15: 20}

        # Act
        result = activity.create_histogram(data, max_width=20)

        # Assert
        assert any(line.startswith("05:00") for line in result)
        assert any(line.startswith("15:00") for line in result)

    def test_handles_empty_data(self):
        """Should return empty list for no data."""
        # Act
        result = activity.create_histogram({}, max_width=40)

        # Assert
        assert result == []


class TestCreateDayHistogram:
    """Tests for create_day_histogram function."""

    def test_creates_bars_for_days_in_order(self):
        """Should display days in Monday-Sunday order."""
        # Arrange
        data = {"Mon": 10, "Wed": 20, "Fri": 15}
        day_order = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

        # Act
        result = activity.create_day_histogram(data, day_order, max_width=40)

        # Assert
        assert len(result) == 7  # All 7 days
        # First line should be Monday
        assert result[0].startswith("Mon")
        # Last line should be Sunday
        assert result[6].startswith("Sun")

    def test_shows_zero_for_missing_days(self):
        """Should show 0 count for days with no commits."""
        # Arrange
        data = {"Mon": 10}
        day_order = ["Mon", "Tue", "Wed"]

        # Act
        result = activity.create_day_histogram(data, day_order, max_width=20)

        # Assert
        tue_line = next(line for line in result if line.startswith("Tue"))
        assert "0" in tue_line

    def test_handles_empty_data(self):
        """Should return empty list for no data."""
        # Arrange
        day_order = ["Mon", "Tue", "Wed"]

        # Act
        result = activity.create_day_histogram({}, day_order, max_width=20)

        # Assert
        assert result == []


class TestFormatTextOutput:
    """Tests for format_text_output function."""

    def test_format_by_hour_includes_histogram(self, sample_git_log_activity):
        """Should include hour histogram in output."""
        # Arrange
        commits = activity.parse_git_log(sample_git_log_activity)
        analysis = activity.analyze_by_hour(commits, by_author=False)

        # Act
        output = activity.format_text_output(analysis, len(commits))

        # Assert
        assert "Commits by Hour" in output
        assert "█" in output  # Histogram bars
        assert "commits" in output.lower()

    def test_format_by_day_includes_histogram(self, sample_git_log_activity):
        """Should include day histogram in output."""
        # Arrange
        commits = activity.parse_git_log(sample_git_log_activity)
        analysis = activity.analyze_by_day(commits, by_author=False)

        # Act
        output = activity.format_text_output(analysis, len(commits))

        # Assert
        assert "Commits by Day" in output
        assert any(day in output for day in ["Mon", "Tue", "Wed", "Thu", "Fri"])

    def test_format_includes_observations(self, sample_git_log_activity):
        """Should include pattern observations in output."""
        # Arrange
        commits = activity.parse_git_log(sample_git_log_activity)
        analysis = activity.analyze_by_hour(commits, by_author=False)

        # Act
        output = activity.format_text_output(analysis, len(commits))

        # Assert
        assert "Observations" in output or "Peak" in output

    def test_format_handles_time_range(self):
        """Should display time range if provided."""
        # Arrange
        analysis = {"type": "by_hour", "data": {9: 10, 14: 15}}

        # Act
        output = activity.format_text_output(analysis, 25, time_range="since 3 months ago")

        # Assert
        assert "since 3 months ago" in output


class TestMainFunction:
    """Integration tests for main function."""

    def test_main_json_output(self, sample_git_log_activity, monkeypatch, capsys):
        """Should output valid JSON when --format=json."""
        # Arrange
        import sys

        monkeypatch.setattr(sys, "stdin", StringIO(sample_git_log_activity))
        monkeypatch.setattr(sys, "argv", ["activity.py", "--by-hour", "--format", "json"])

        # Act
        exit_code = activity.main()
        captured = capsys.readouterr()

        # Assert
        assert exit_code == 0
        result = json.loads(captured.out)
        assert "commits_analyzed" in result
        assert "analysis" in result

    def test_main_text_output(self, sample_git_log_activity, monkeypatch, capsys):
        """Should output formatted text when --format=text."""
        # Arrange
        import sys

        monkeypatch.setattr(sys, "stdin", StringIO(sample_git_log_activity))
        monkeypatch.setattr(sys, "argv", ["activity.py", "--by-day", "--format", "text"])

        # Act
        exit_code = activity.main()
        captured = capsys.readouterr()

        # Assert
        assert exit_code == 0
        assert "Commits by Day" in captured.out

    def test_main_default_shows_both(self, sample_git_log_activity, monkeypatch, capsys):
        """Should show both hour and day analysis by default."""
        # Arrange
        import sys

        monkeypatch.setattr(sys, "stdin", StringIO(sample_git_log_activity))
        monkeypatch.setattr(sys, "argv", ["activity.py", "--format", "text"])

        # Act
        exit_code = activity.main()
        captured = capsys.readouterr()

        # Assert
        assert exit_code == 0
        assert "Commits by Hour" in captured.out
        assert "Commits by Day" in captured.out

    def test_main_handles_empty_input(self, empty_git_log, monkeypatch, capsys):
        """Should handle empty stdin gracefully."""
        # Arrange
        import sys

        monkeypatch.setattr(sys, "stdin", StringIO(empty_git_log))
        monkeypatch.setattr(sys, "argv", ["activity.py"])

        # Act
        exit_code = activity.main()
        captured = capsys.readouterr()

        # Assert
        assert exit_code == 1
        assert "Error" in captured.err or "No" in captured.err


class TestEdgeCases:
    """Tests for edge cases and boundary conditions."""

    def test_handles_midnight_hour(self):
        """Should correctly handle hour 0 (midnight)."""
        # Arrange
        log = "2024-11-17 00:15:00 -0500|Alice Smith"
        commits = activity.parse_git_log(log)

        # Act
        result = activity.analyze_by_hour(commits, by_author=False)

        # Assert
        assert 0 in result["data"]
        assert result["data"][0] == 1

    def test_handles_all_hours_of_day(self):
        """Should handle commits across all 24 hours."""
        # Arrange
        log_lines = [f"2024-11-17 {h:02d}:00:00 -0500|Alice" for h in range(24)]
        log = "\n".join(log_lines)
        commits = activity.parse_git_log(log)

        # Act
        result = activity.analyze_by_hour(commits, by_author=False)

        # Assert
        assert len(result["data"]) == 24
        for hour in range(24):
            assert hour in result["data"]

    def test_handles_all_days_of_week(self):
        """Should handle commits across all 7 days."""
        # Arrange - 2024-11-18 is Monday, so next 7 days cover full week
        log_lines = [f"2024-11-{18 + d} 10:00:00 -0500|Alice" for d in range(7)]
        log = "\n".join(log_lines)
        commits = activity.parse_git_log(log)

        # Act
        result = activity.analyze_by_day(commits, by_author=False)

        # Assert
        day_order = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        for day in day_order:
            assert day in result["data"]

    def test_handles_single_author(self):
        """Should handle commits from single author."""
        # Arrange
        log = """2024-11-17 09:00:00 -0500|Alice Smith
2024-11-17 10:00:00 -0500|Alice Smith
2024-11-17 14:00:00 -0500|Alice Smith
"""
        commits = activity.parse_git_log(log)

        # Act
        result = activity.analyze_by_hour(commits, by_author=True)

        # Assert
        assert len(result["data"]) == 1
        assert "Alice Smith" in result["data"]
        assert len(result["data"]["Alice Smith"]) == 3  # 3 different hours

    def test_handles_many_authors(self):
        """Should handle commits from many different authors."""
        # Arrange
        log_lines = [f"2024-11-17 10:00:00 -0500|Author{i}" for i in range(50)]
        log = "\n".join(log_lines)
        commits = activity.parse_git_log(log)

        # Act
        result = activity.analyze_by_hour(commits, by_author=True)

        # Assert
        assert len(result["data"]) == 50  # 50 different authors


class TestGetActivityCommits:
    """Tests for get_activity_commits using Command Mock Framework."""

    def test_get_activity_commits_burst(self, command_mock):
        """Test activity commits with burst pattern."""
        mock_fn = command_mock.get_subprocess_mock("log/activity.toml", "burst")
        with patch("activity.subprocess.run", side_effect=mock_fn):
            commits = activity.get_activity_commits("file.py", since="1 day ago")

            # Assert
            assert len(commits) == 11
            assert commits[0]["author"] == "Alice Smith"
            assert commits[0]["hour"] == 9
            assert commits[0]["day_of_week"] == "Fri"

            # Check burst pattern (multiple commits from same author)
            alice_commits = [c for c in commits if c["author"] == "Alice Smith"]
            assert len(alice_commits) == 6

    def test_get_activity_commits_weekend(self, command_mock):
        """Test activity commits including weekend work."""
        mock_fn = command_mock.get_subprocess_mock("log/activity.toml", "weekend")
        with patch("activity.subprocess.run", side_effect=mock_fn):
            commits = activity.get_activity_commits("src/main.py", since="3 days ago")

            # Assert - script creates 9 commits: 6 weekday, 3 weekend
            assert len(commits) == 9

            # Check weekend commits (Saturday and Sunday)
            weekend_commits = [c for c in commits if c["day_of_week"] in ["Sat", "Sun"]]
            assert len(weekend_commits) == 3

    def test_get_activity_commits_empty(self, command_mock):
        """Test activity commits with no results."""
        mock_fn = command_mock.get_subprocess_mock("log/activity.toml", "empty")
        with patch("activity.subprocess.run", side_effect=mock_fn):
            commits = activity.get_activity_commits("nonexistent.txt", since="1 week ago")

            # Assert
            assert len(commits) == 0

    def test_get_activity_commits_no_since(self, command_mock):
        """Test activity commits without since parameter."""
        mock_fn = command_mock.get_subprocess_mock("log/activity.toml", "burst")
        with patch("activity.subprocess.run", side_effect=mock_fn):
            commits = activity.get_activity_commits("file.py")

            # Assert - should still work, just without --since flag
            assert len(commits) == 11
