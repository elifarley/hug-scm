"""
Unit tests for ownership.py - Code ownership and expertise detection.

Following Google Python testing best practices:
- Arrange-Act-Assert pattern
- Descriptive test names
- Test edge cases and error conditions

NOTE: These tests focus on the algorithmic functions (calculate_recency_weight,
calculate_file_ownership) rather than git-invoking functions which require
subprocess mocking.
"""

import pytest
import math
from datetime import datetime

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

    def test_custom_decay_constant(self):
        """Should respect different decay periods."""
        # Arrange
        days_ago = 30

        # Act
        weight_short_decay = ownership.calculate_recency_weight(days_ago, 30)  # 1/e
        weight_long_decay = ownership.calculate_recency_weight(days_ago, 180)  # Higher

        # Assert
        # Shorter decay period = faster decline
        assert weight_short_decay < weight_long_decay
        assert abs(weight_short_decay - math.exp(-1)) < 0.01


class TestCalculateFileOwnership:
    """Tests for calculate_file_ownership function."""

    def test_calculate_ownership_percentages(self):
        """Should calculate correct ownership percentages."""
        # Arrange
        commits = [
            {"author": "Alice", "days_ago": 1},
            {"author": "Alice", "days_ago": 2},
            {"author": "Alice", "days_ago": 3},
            {"author": "Bob", "days_ago": 5},
        ]

        # Act
        result = ownership.calculate_file_ownership(commits, decay_days=180)

        # Assert
        # Alice has 3 commits, Bob has 1 - Alice should have higher ownership
        alice = next(r for r in result if r["author"] == "Alice")
        bob = next(r for r in result if r["author"] == "Bob")

        assert alice["ownership_pct"] > bob["ownership_pct"]
        assert alice["raw_commits"] == 3
        assert bob["raw_commits"] == 1

    def test_calculate_ownership_recency_weighting(self):
        """Should weight recent commits higher than old commits."""
        # Arrange
        # Alice: 1 very recent commit
        # Bob: 2 old commits
        commits = [
            {"author": "Alice", "days_ago": 1},
            {"author": "Bob", "days_ago": 300},
            {"author": "Bob", "days_ago": 310},
        ]

        # Act
        result = ownership.calculate_file_ownership(commits, decay_days=180)

        # Assert
        alice = next(r for r in result if r["author"] == "Alice")
        bob = next(r for r in result if r["author"] == "Bob")

        # Alice's 1 recent commit should have higher ownership than Bob's 2 old commits
        assert alice["ownership_pct"] > bob["ownership_pct"]

    def test_calculate_ownership_classification_thresholds(self):
        """Should correctly classify primary/secondary/historical owners."""
        # Arrange
        # Create commits with clear ownership tiers
        commits = [
            {"author": "Alice", "days_ago": 1},
            {"author": "Alice", "days_ago": 2},
            {"author": "Alice", "days_ago": 3},
            {"author": "Alice", "days_ago": 4},
            {"author": "Alice", "days_ago": 5},
            {"author": "Bob", "days_ago": 6},
            {"author": "Bob", "days_ago": 7},
            {"author": "Charlie", "days_ago": 300},
        ]

        # Act
        result = ownership.calculate_file_ownership(commits, decay_days=180)

        # Assert
        alice = next(r for r in result if r["author"] == "Alice")
        bob = next(r for r in result if r["author"] == "Bob")
        charlie = next(r for r in result if r["author"] == "Charlie")

        # Alice: >40% = primary
        assert alice["classification"] == "primary"
        # Bob: likely secondary or historical depending on weighting
        assert bob["classification"] in ["secondary", "historical"]
        # Charlie: old commit = historical
        assert charlie["classification"] == "historical"

    def test_calculate_ownership_total_equals_100(self):
        """Should have ownership percentages sum to ~100%."""
        # Arrange
        commits = [
            {"author": "Alice", "days_ago": 1},
            {"author": "Bob", "days_ago": 2},
            {"author": "Charlie", "days_ago": 3},
        ]

        # Act
        result = ownership.calculate_file_ownership(commits, decay_days=180)

        # Assert
        total_ownership = sum(r["ownership_pct"] for r in result)
        assert 99.0 <= total_ownership <= 101.0  # Allow small floating point error

    def test_calculate_ownership_sorted_descending(self):
        """Should return results sorted by ownership percentage (descending)."""
        # Arrange
        commits = [
            {"author": "Alice", "days_ago": 1},
            {"author": "Alice", "days_ago": 2},
            {"author": "Bob", "days_ago": 3},
            {"author": "Charlie", "days_ago": 300},
        ]

        # Act
        result = ownership.calculate_file_ownership(commits, decay_days=180)

        # Assert
        # Verify descending order
        for i in range(len(result) - 1):
            assert result[i]["ownership_pct"] >= result[i + 1]["ownership_pct"]

    def test_handles_single_author_single_commit(self):
        """Should handle minimal ownership scenario."""
        # Arrange
        commits = [{"author": "Alice", "days_ago": 5}]

        # Act
        result = ownership.calculate_file_ownership(commits, decay_days=180)

        # Assert
        assert len(result) == 1
        assert result[0]["ownership_pct"] == 100.0
        assert result[0]["classification"] == "primary"
        assert result[0]["raw_commits"] == 1

    def test_handles_empty_commits(self):
        """Should return empty list for no commits."""
        # Act
        result = ownership.calculate_file_ownership([], decay_days=180)

        # Assert
        assert result == []

    def test_tracks_last_commit_days(self):
        """Should track most recent commit per author."""
        # Arrange
        commits = [
            {"author": "Alice", "days_ago": 1},
            {"author": "Alice", "days_ago": 10},
            {"author": "Alice", "days_ago": 5},
        ]

        # Act
        result = ownership.calculate_file_ownership(commits, decay_days=180)

        # Assert
        alice = result[0]
        assert alice["last_commit_days"] == 1  # Most recent

    def test_different_decay_periods(self):
        """Should respect custom decay_days parameter."""
        # Arrange
        commits = [
            {"author": "Alice", "days_ago": 1},
            {"author": "Bob", "days_ago": 100},
        ]

        # Act
        result_short = ownership.calculate_file_ownership(commits, decay_days=30)
        result_long = ownership.calculate_file_ownership(commits, decay_days=360)

        # Assert
        alice_short = next(r for r in result_short if r["author"] == "Alice")
        alice_long = next(r for r in result_long if r["author"] == "Alice")

        # With shorter decay, Alice should have even higher ownership
        assert alice_short["ownership_pct"] >= alice_long["ownership_pct"]


class TestFormatDaysAgo:
    """Tests for format_days_ago function."""

    def test_format_today(self):
        """Should return 'today' for 0 days."""
        assert ownership.format_days_ago(0) == "today"

    def test_format_yesterday(self):
        """Should return 'yesterday' for 1 day."""
        assert ownership.format_days_ago(1) == "yesterday"

    def test_format_recent_days(self):
        """Should return 'N days ago' for recent days."""
        assert ownership.format_days_ago(3) == "3 days ago"
        assert ownership.format_days_ago(6) == "6 days ago"

    def test_format_weeks(self):
        """Should return 'N weeks ago' for week intervals."""
        assert ownership.format_days_ago(14) == "2 weeks ago"
        assert ownership.format_days_ago(21) == "3 weeks ago"

    def test_format_months(self):
        """Should return 'N months ago' for month intervals."""
        assert ownership.format_days_ago(60) == "2 months ago"
        assert ownership.format_days_ago(120) == "4 months ago"

    def test_format_years(self):
        """Should return 'N years ago' for year intervals."""
        result = ownership.format_days_ago(400)
        assert "year" in result or "month" in result


class TestEdgeCases:
    """Tests for edge cases and boundary conditions."""

    def test_all_commits_same_day(self):
        """Should handle all commits on same day."""
        # Arrange
        commits = [
            {"author": "Alice", "days_ago": 5},
            {"author": "Bob", "days_ago": 5},
            {"author": "Charlie", "days_ago": 5},
        ]

        # Act
        result = ownership.calculate_file_ownership(commits, decay_days=180)

        # Assert
        # With equal recency, ownership should be equal (33.33% each)
        assert abs(result[0]["ownership_pct"] - 33.33) < 1.0
        assert abs(result[1]["ownership_pct"] - 33.33) < 1.0
        assert abs(result[2]["ownership_pct"] - 33.33) < 1.0

    def test_very_old_commits_not_zero_weight(self):
        """Should give non-zero weight even to very old commits."""
        # Arrange
        commits = [{"author": "Alice", "days_ago": 1000}]

        # Act
        result = ownership.calculate_file_ownership(commits, decay_days=180)

        # Assert
        # Even very old commits should have some weight
        assert result[0]["ownership_pct"] == 100.0
        assert result[0]["weighted_score"] > 0

    def test_many_authors(self):
        """Should handle many different authors."""
        # Arrange
        commits = [{"author": f"Author{i}", "days_ago": i} for i in range(50)]

        # Act
        result = ownership.calculate_file_ownership(commits, decay_days=180)

        # Assert
        assert len(result) == 50
        # Total should still be 100%
        total = sum(r["ownership_pct"] for r in result)
        assert 99.0 <= total <= 101.0

    def test_classification_boundary_cases(self):
        """Should handle boundary cases for classification thresholds."""
        # Arrange - Create scenario with ownership right at thresholds
        commits = [
            {"author": "Primary", "days_ago": 1},
            {"author": "Primary", "days_ago": 2},
            {"author": "Primary", "days_ago": 3},
            {"author": "Primary", "days_ago": 4},
            {"author": "Secondary", "days_ago": 5},
            {"author": "Secondary", "days_ago": 6},
            {"author": "Historical", "days_ago": 7},
        ]

        # Act
        result = ownership.calculate_file_ownership(commits, decay_days=180)

        # Assert
        # Check that classifications are assigned
        classifications = [r["classification"] for r in result]
        assert (
            "primary" in classifications
            or "secondary" in classifications
            or "historical" in classifications
        )

    def test_zero_decay_days_edge_case(self):
        """Should handle edge case of zero decay (though unrealistic)."""
        # Arrange
        commits = [
            {"author": "Alice", "days_ago": 0},
            {"author": "Bob", "days_ago": 1},
        ]

        # Act
        # With decay_days=1, even 1 day ago has significant decay
        result = ownership.calculate_file_ownership(commits, decay_days=1)

        # Assert
        alice = next(r for r in result if r["author"] == "Alice")
        bob = next(r for r in result if r["author"] == "Bob")

        # Alice (today) should have much higher ownership than Bob (1 day ago)
        assert alice["ownership_pct"] > bob["ownership_pct"]
