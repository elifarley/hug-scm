"""
Unit tests for ownership.py - Code ownership and expertise detection.

Following Google Python testing best practices:
- Arrange-Act-Assert pattern
- Descriptive test names
- Test edge cases and error conditions
"""

import json
import pytest
import math
from datetime import datetime, timedelta
from io import StringIO

# Import module under test
import ownership


class TestCalculateRecencyWeight:
    """Tests for calculate_recency_weight function."""

    def test_recent_commit_has_high_weight(self):
        """Should return weight near 1.0 for recent commits."""
        # Arrange
        days_ago = 1
        decay_days = 180

        # Act
        weight = ownership.calculate_recency_weight(days_ago, decay_days)

        # Assert
        assert 0.99 < weight <= 1.0

    def test_old_commit_has_low_weight(self):
        """Should return weight near 0.0 for old commits."""
        # Arrange
        days_ago = 720  # 2 years
        decay_days = 180

        # Act
        weight = ownership.calculate_recency_weight(days_ago, decay_days)

        # Assert
        assert 0.0 <= weight < 0.02

    def test_half_life_at_decay_constant(self):
        """Should have weight ~0.37 at decay_days (1/e)."""
        # Arrange
        decay_days = 180

        # Act
        weight = ownership.calculate_recency_weight(decay_days, decay_days)

        # Assert
        expected = math.exp(-1)  # ~0.368
        assert abs(weight - expected) < 0.01

    def test_zero_days_ago_returns_one(self):
        """Should return exactly 1.0 for today's commits."""
        # Act
        weight = ownership.calculate_recency_weight(0, 180)

        # Assert
        assert weight == 1.0


class TestParseGitLogFileMode:
    """Tests for parse_git_log_file_mode function."""

    def test_parse_valid_log_with_multiple_authors(self, sample_git_log_ownership_file):
        """Should parse git log with multiple commits by different authors."""
        # Arrange
        today = datetime.now()

        # Act
        result = ownership.parse_git_log_file_mode(sample_git_log_ownership_file, today)

        # Assert
        assert len(result) == 7
        assert result[0]['author'] == 'Alice Smith'
        assert result[1]['author'] == 'Bob Johnson'
        assert 'days_ago' in result[0]

    def test_parse_calculates_days_ago_correctly(self):
        """Should calculate correct days_ago from dates."""
        # Arrange
        log = "abc1234|Alice Smith|2024-11-01 10:00:00 -0500"
        reference_date = datetime(2024, 11, 11, 10, 0, 0)

        # Act
        result = ownership.parse_git_log_file_mode(log, reference_date)

        # Assert
        assert len(result) == 1
        assert result[0]['days_ago'] == 10

    def test_parse_handles_malformed_lines(self):
        """Should skip malformed log lines gracefully."""
        # Arrange
        log = """abc1234|Alice Smith|2024-11-01 10:00:00 -0500
invalid_line_without_pipes
def5678|Bob Johnson|2024-11-02 11:00:00 -0500
"""
        today = datetime.now()

        # Act
        result = ownership.parse_git_log_file_mode(log, today)

        # Assert
        # Should parse only valid lines
        assert len(result) == 2

    def test_parse_empty_log(self, empty_git_log):
        """Should return empty list for empty log."""
        # Act
        result = ownership.parse_git_log_file_mode(empty_git_log, datetime.now())

        # Assert
        assert result == []


class TestCalculateFileOwnership:
    """Tests for calculate_file_ownership function."""

    def test_calculate_ownership_percentages(self, sample_git_log_ownership_file):
        """Should calculate correct ownership percentages."""
        # Arrange
        today = datetime(2024, 11, 17, 12, 0, 0)
        commits = ownership.parse_git_log_file_mode(sample_git_log_ownership_file, today)

        # Act
        result = ownership.calculate_file_ownership(commits, decay_days=180)

        # Assert
        # Alice has 4 commits (most recent), should have highest ownership
        alice_data = result['Alice Smith']
        assert alice_data['commits'] == 4
        assert alice_data['ownership'] > 40  # Should be primary owner

    def test_calculate_ownership_recency_weighting(self):
        """Should weight recent commits higher than old commits."""
        # Arrange
        today = datetime(2024, 11, 17, 12, 0, 0)

        # Alice: 1 very recent commit
        # Bob: 2 old commits
        log = """abc1234|Alice Smith|2024-11-16 10:00:00 -0500
def5678|Bob Johnson|2024-01-01 10:00:00 -0500
ghi9012|Bob Johnson|2024-01-02 10:00:00 -0500
"""
        commits = ownership.parse_git_log_file_mode(log, today)

        # Act
        result = ownership.calculate_file_ownership(commits, decay_days=180)

        # Assert
        # Alice's 1 recent commit should have higher ownership than Bob's 2 old commits
        assert result['Alice Smith']['ownership'] > result['Bob Johnson']['ownership']

    def test_calculate_ownership_classification_thresholds(self):
        """Should correctly classify primary/secondary/historical owners."""
        # Arrange
        today = datetime(2024, 11, 17, 12, 0, 0)

        # Create scenario with clear ownership tiers
        log = """abc1234|Alice Smith|2024-11-16 10:00:00 -0500
def5678|Alice Smith|2024-11-15 10:00:00 -0500
ghi9012|Alice Smith|2024-11-14 10:00:00 -0500
jkl3456|Bob Johnson|2024-11-13 10:00:00 -0500
mno7890|Charlie Brown|2024-01-01 10:00:00 -0500
"""
        commits = ownership.parse_git_log_file_mode(log, today)

        # Act
        result = ownership.calculate_file_ownership(commits, decay_days=180)

        # Assert
        # Alice: >40% = primary
        # Bob: >20% but <40% = secondary
        # Charlie: <20% = historical
        assert result['Alice Smith']['classification'] == 'primary'
        assert result['Bob Johnson']['classification'] in ['secondary', 'historical']
        assert result['Charlie Brown']['classification'] == 'historical'

    def test_calculate_ownership_total_equals_100(self, sample_git_log_ownership_file):
        """Should have ownership percentages sum to ~100%."""
        # Arrange
        today = datetime.now()
        commits = ownership.parse_git_log_file_mode(sample_git_log_ownership_file, today)

        # Act
        result = ownership.calculate_file_ownership(commits, decay_days=180)

        # Assert
        total_ownership = sum(data['ownership'] for data in result.values())
        assert 99.0 <= total_ownership <= 101.0  # Allow small floating point error


class TestParseGitLogAuthorMode:
    """Tests for parse_git_log_author_mode function."""

    def test_parse_author_mode_with_multiple_files(self, sample_git_log_ownership_author):
        """Should parse commits and track file modifications."""
        # Act
        result = ownership.parse_git_log_author_mode(sample_git_log_ownership_author)

        # Assert
        assert len(result) > 0
        # src/auth/login.py appears in 2 commits
        assert result['src/auth/login.py'] == 2
        # src/auth/session.py appears in 2 commits
        assert result['src/auth/session.py'] == 2

    def test_parse_author_mode_counts_file_occurrences(self):
        """Should count how many commits each file appears in."""
        # Arrange
        log = """abc1234567890123456789012345678901234567
file_a.py
file_b.py

def4567890123456789012345678901234567890
file_a.py
file_c.py

ghi7890123456789012345678901234567890123
file_a.py
"""

        # Act
        result = ownership.parse_git_log_author_mode(log)

        # Assert
        assert result['file_a.py'] == 3
        assert result['file_b.py'] == 1
        assert result['file_c.py'] == 1

    def test_parse_author_mode_handles_empty_log(self, empty_git_log):
        """Should return empty dict for empty log."""
        # Act
        result = ownership.parse_git_log_author_mode(empty_git_log)

        # Assert
        assert result == {}

    def test_parse_author_mode_ignores_blank_lines(self):
        """Should skip blank lines in commit blocks."""
        # Arrange
        log = """abc1234567890123456789012345678901234567

file_a.py


file_b.py

"""

        # Act
        result = ownership.parse_git_log_author_mode(log)

        # Assert
        assert result['file_a.py'] == 1
        assert result['file_b.py'] == 1


class TestCalculateAuthorExpertise:
    """Tests for calculate_author_expertise function."""

    def test_calculate_expertise_ranks_by_commit_count(self, sample_git_log_ownership_author):
        """Should rank files by number of commits."""
        # Arrange
        file_commits = ownership.parse_git_log_author_mode(sample_git_log_ownership_author)

        # Act
        result = ownership.calculate_author_expertise(file_commits)

        # Assert
        # Verify descending order
        for i in range(len(result) - 1):
            assert result[i]['commits'] >= result[i + 1]['commits']

    def test_calculate_expertise_includes_all_files(self, sample_git_log_ownership_author):
        """Should include all files touched by author."""
        # Arrange
        file_commits = ownership.parse_git_log_author_mode(sample_git_log_ownership_author)

        # Act
        result = ownership.calculate_author_expertise(file_commits)

        # Assert
        file_paths = [item['file'] for item in result]
        assert 'src/auth/login.py' in file_paths
        assert 'src/auth/session.py' in file_paths
        assert 'src/api/users.py' in file_paths

    def test_calculate_expertise_with_single_file(self):
        """Should handle author with single file."""
        # Arrange
        file_commits = {'single_file.py': 5}

        # Act
        result = ownership.calculate_author_expertise(file_commits)

        # Assert
        assert len(result) == 1
        assert result[0]['file'] == 'single_file.py'
        assert result[0]['commits'] == 5

    def test_calculate_expertise_empty_input(self):
        """Should return empty list for no files."""
        # Act
        result = ownership.calculate_author_expertise({})

        # Assert
        assert result == []


class TestFormatTextOutput:
    """Tests for format_text_output function."""

    def test_format_file_mode_includes_classifications(self, sample_git_log_ownership_file):
        """Should display primary/secondary/historical sections."""
        # Arrange
        today = datetime.now()
        commits = ownership.parse_git_log_file_mode(sample_git_log_ownership_file, today)
        ownership_data = ownership.calculate_file_ownership(commits, decay_days=180)

        analysis = {
            'mode': 'file',
            'target': 'test_file.py',
            'ownership': ownership_data
        }

        # Act
        output = ownership.format_text_output(analysis)

        # Assert
        assert 'test_file.py' in output
        assert 'Primary' in output or 'Secondary' in output or 'Historical' in output

    def test_format_author_mode_shows_file_list(self, sample_git_log_ownership_author):
        """Should list files with commit counts for author mode."""
        # Arrange
        file_commits = ownership.parse_git_log_author_mode(sample_git_log_ownership_author)
        expertise = ownership.calculate_author_expertise(file_commits)

        analysis = {
            'mode': 'author',
            'target': 'Alice Smith',
            'expertise': expertise,
            'total_files': len(expertise)
        }

        # Act
        output = ownership.format_text_output(analysis)

        # Assert
        assert 'Alice Smith' in output
        assert 'src/auth/login.py' in output
        assert 'commits' in output.lower()

    def test_format_handles_stale_contributors(self):
        """Should mark contributors with old commits as stale."""
        # Arrange
        today = datetime(2024, 11, 17, 12, 0, 0)

        # Old commit from 1 year ago
        log = "abc1234|Charlie Brown|2023-11-01 10:00:00 -0500"
        commits = ownership.parse_git_log_file_mode(log, today)
        ownership_data = ownership.calculate_file_ownership(commits, decay_days=180)

        analysis = {
            'mode': 'file',
            'target': 'test_file.py',
            'ownership': ownership_data
        }

        # Act
        output = ownership.format_text_output(analysis)

        # Assert
        assert '⚠️' in output or 'Stale' in output or 'stale' in output


class TestMainFunction:
    """Integration tests for main function."""

    def test_main_file_mode_json_output(self, sample_git_log_ownership_file, monkeypatch, capsys):
        """Should output valid JSON for file mode."""
        # Arrange
        import sys
        monkeypatch.setattr(sys, 'stdin', StringIO(sample_git_log_ownership_file))
        monkeypatch.setattr(
            sys, 'argv',
            ['ownership.py', '--file', 'test.py', '--format', 'json']
        )

        # Act
        exit_code = ownership.main()
        captured = capsys.readouterr()

        # Assert
        assert exit_code == 0
        result = json.loads(captured.out)
        assert result['mode'] == 'file'
        assert 'ownership' in result

    def test_main_author_mode_text_output(self, sample_git_log_ownership_author, monkeypatch, capsys):
        """Should output formatted text for author mode."""
        # Arrange
        import sys
        monkeypatch.setattr(sys, 'stdin', StringIO(sample_git_log_ownership_author))
        monkeypatch.setattr(
            sys, 'argv',
            ['ownership.py', '--author', 'Alice Smith', '--format', 'text']
        )

        # Act
        exit_code = ownership.main()
        captured = capsys.readouterr()

        # Assert
        assert exit_code == 0
        assert 'Alice Smith' in captured.out
        assert 'src/auth/login.py' in captured.out


class TestEdgeCases:
    """Tests for edge cases and boundary conditions."""

    def test_handles_single_author_single_commit(self):
        """Should handle minimal ownership scenario."""
        # Arrange
        log = "abc1234|Alice Smith|2024-11-17 10:00:00 -0500"
        today = datetime(2024, 11, 17, 12, 0, 0)
        commits = ownership.parse_git_log_file_mode(log, today)

        # Act
        result = ownership.calculate_file_ownership(commits, decay_days=180)

        # Assert
        assert len(result) == 1
        assert result['Alice Smith']['ownership'] == 100.0
        assert result['Alice Smith']['classification'] == 'primary'

    def test_handles_files_with_special_characters(self):
        """Should correctly parse file paths with special characters."""
        # Arrange
        log = """abc1234567890123456789012345678901234567
src/file-with-dashes.py
src/file_with_underscores.py
src/file.with.dots.py
"""

        # Act
        result = ownership.parse_git_log_author_mode(log)

        # Assert
        assert 'src/file-with-dashes.py' in result
        assert 'src/file_with_underscores.py' in result
        assert 'src/file.with.dots.py' in result

    def test_handles_very_long_file_paths(self):
        """Should handle long file paths without truncation."""
        # Arrange
        long_path = "src/" + "/".join(["very"] * 20) + "/deep/file.py"
        log = f"""abc1234567890123456789012345678901234567
{long_path}
"""

        # Act
        result = ownership.parse_git_log_author_mode(log)

        # Assert
        assert long_path in result

    def test_custom_decay_constant(self):
        """Should respect custom decay_days parameter."""
        # Arrange
        today = datetime(2024, 11, 17, 12, 0, 0)
        log = """abc1234|Alice Smith|2024-11-16 10:00:00 -0500
def5678|Bob Johnson|2024-01-01 10:00:00 -0500
"""
        commits = ownership.parse_git_log_file_mode(log, today)

        # Act - Short decay period (30 days)
        result_short = ownership.calculate_file_ownership(commits, decay_days=30)

        # Act - Long decay period (360 days)
        result_long = ownership.calculate_file_ownership(commits, decay_days=360)

        # Assert
        # With shorter decay, Alice should have even higher ownership
        assert result_short['Alice Smith']['ownership'] > result_long['Alice Smith']['ownership']
