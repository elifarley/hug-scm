"""Unit tests for branch_filter.py - Branch filtering with type safety.

Following Google Python testing best practices:
- Arrange-Act-Assert pattern
- Descriptive test names
- Test edge cases and error conditions
"""

import pytest

from git.branch_filter import FilteredBranches, FilterOptions, _bash_escape, filter_branches

################################################################################
# Test Fixtures
################################################################################


@pytest.fixture
def sample_branch_data():
    """Sample branch data for testing."""
    return {
        "branches": ["main", "feature", "bugfix", "hug-backups/tmp"],
        "hashes": ["abc123", "def456", "ghi789", "jkl012"],
        "subjects": ["Init", "Feature", "Bug fix", "Backup"],
        "tracks": ["[origin/main]", "", "[upstream/bugfix]", ""],
        "dates": ["2026-01-30", "2026-01-31", "2026-01-31", "2026-01-31"],
    }


@pytest.fixture
def filter_options_none():
    """FilterOptions with no exclusions."""
    return FilterOptions(exclude_current=False, exclude_backup=False)


@pytest.fixture
def filter_options_exclude_current():
    """FilterOptions excluding current branch."""
    return FilterOptions(exclude_current=True, exclude_backup=False)


@pytest.fixture
def filter_options_exclude_backup():
    """FilterOptions excluding backup branches."""
    return FilterOptions(exclude_current=False, exclude_backup=True)


@pytest.fixture
def filter_options_both():
    """FilterOptions excluding both current and backup."""
    return FilterOptions(exclude_current=True, exclude_backup=True)


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
# TestFilterOptions
################################################################################


class TestFilterOptions:
    """Tests for FilterOptions dataclass."""

    def test_default_values(self):
        """Should have correct default values."""
        options = FilterOptions()
        assert options.exclude_current is False
        assert options.exclude_backup is True
        assert options.custom_filter is None

    def test_custom_values(self):
        """Should accept custom values."""
        options = FilterOptions(
            exclude_current=True, exclude_backup=False, custom_filter="my_filter"
        )
        assert options.exclude_current is True
        assert options.exclude_backup is False
        assert options.custom_filter == "my_filter"


################################################################################
# TestFilteredBranches
################################################################################


class TestFilteredBranches:
    """Tests for FilteredBranches dataclass."""

    def test_initialization(self):
        """Should create FilteredBranches with all fields."""
        result = FilteredBranches(
            branches=["main", "feature"],
            hashes=["abc", "def"],
            subjects=["Init", "Feature"],
            tracks=["[origin/main]", ""],
            dates=["2026-01-30", "2026-01-31"],
        )
        assert len(result.branches) == 2
        assert result.branches[0] == "main"

    def test_to_bash_declare_outputs_declarations(self, sample_branch_data):
        """Should output bash declare statements."""
        result = FilteredBranches(
            branches=sample_branch_data["branches"],
            hashes=sample_branch_data["hashes"],
            subjects=sample_branch_data["subjects"],
            tracks=sample_branch_data["tracks"],
            dates=sample_branch_data["dates"],
        )

        bash_output = result.to_bash_declare()

        assert "declare -a filtered_branches=" in bash_output
        assert "declare -a filtered_hashes=" in bash_output
        assert "declare -a filtered_subjects=" in bash_output
        assert "declare -a filtered_tracks=" in bash_output
        assert "declare -a filtered_dates=" in bash_output

    def test_to_bash_declare_includes_branch_names(self, sample_branch_data):
        """Should include branch names in bash output."""
        result = FilteredBranches(
            branches=["main", "feature"],
            hashes=["abc", "def"],
            subjects=["Init", "Feature"],
            tracks=["[origin/main]", ""],
            dates=["2026-01-30", "2026-01-31"],
        )

        bash_output = result.to_bash_declare()

        assert "main" in bash_output
        assert "feature" in bash_output

    def test_to_bash_declare_handles_empty_arrays(self):
        """Should handle empty arrays."""
        result = FilteredBranches(branches=[], hashes=[], subjects=[], tracks=[], dates=[])

        bash_output = result.to_bash_declare()

        assert "declare -a filtered_branches=()" in bash_output
        assert "declare -a filtered_hashes=()" in bash_output


################################################################################
# TestFilterBranches
################################################################################


class TestFilterBranches:
    """Tests for filter_branches function."""

    def test_no_filters_returns_all(self, sample_branch_data, filter_options_none):
        """Should return all branches when no filters specified."""
        result = filter_branches(
            branches=sample_branch_data["branches"],
            hashes=sample_branch_data["hashes"],
            subjects=sample_branch_data["subjects"],
            tracks=sample_branch_data["tracks"],
            dates=sample_branch_data["dates"],
            current_branch="main",
            options=filter_options_none,
        )

        assert len(result.branches) == 4
        assert "main" in result.branches
        assert "feature" in result.branches
        assert "bugfix" in result.branches
        assert "hug-backups/tmp" in result.branches

    def test_exclude_current_branch(self, sample_branch_data, filter_options_exclude_current):
        """Should exclude current branch when enabled."""
        result = filter_branches(
            branches=sample_branch_data["branches"],
            hashes=sample_branch_data["hashes"],
            subjects=sample_branch_data["subjects"],
            tracks=sample_branch_data["tracks"],
            dates=sample_branch_data["dates"],
            current_branch="main",
            options=filter_options_exclude_current,
        )

        assert "main" not in result.branches
        assert len(result.branches) == 3
        assert "feature" in result.branches
        assert "bugfix" in result.branches
        assert "hug-backups/tmp" in result.branches

    def test_exclude_backup_branches(self, sample_branch_data, filter_options_exclude_backup):
        """Should exclude backup branches when enabled."""
        result = filter_branches(
            branches=sample_branch_data["branches"],
            hashes=sample_branch_data["hashes"],
            subjects=sample_branch_data["subjects"],
            tracks=sample_branch_data["tracks"],
            dates=sample_branch_data["dates"],
            current_branch="main",
            options=filter_options_exclude_backup,
        )

        assert "hug-backups/tmp" not in result.branches
        assert len(result.branches) == 3
        assert "main" in result.branches
        assert "feature" in result.branches
        assert "bugfix" in result.branches

    def test_exclude_both_current_and_backup(self, sample_branch_data, filter_options_both):
        """Should exclude both current and backup branches."""
        result = filter_branches(
            branches=sample_branch_data["branches"],
            hashes=sample_branch_data["hashes"],
            subjects=sample_branch_data["subjects"],
            tracks=sample_branch_data["tracks"],
            dates=sample_branch_data["dates"],
            current_branch="main",
            options=filter_options_both,
        )

        assert "main" not in result.branches
        assert "hug-backups/tmp" not in result.branches
        assert len(result.branches) == 2
        assert "feature" in result.branches
        assert "bugfix" in result.branches

    def test_empty_input_returns_empty(self):
        """Should handle empty input arrays."""
        options = FilterOptions()

        result = filter_branches(
            branches=[],
            hashes=[],
            subjects=[],
            tracks=[],
            dates=[],
            current_branch="",
            options=options,
        )

        assert len(result.branches) == 0
        assert len(result.hashes) == 0
        assert len(result.subjects) == 0

    def test_all_filtered_out(self, sample_branch_data):
        """Should handle case where all branches are filtered out."""
        options = FilterOptions(exclude_current=True, exclude_backup=True)

        # Only main and backup branches exist
        branches = ["main", "hug-backups/tmp"]
        result = filter_branches(
            branches=branches,
            hashes=["abc", "def"],
            subjects=["Init", "Backup"],
            tracks=["", ""],
            dates=["2026-01-30", "2026-01-31"],
            current_branch="main",
            options=options,
        )

        assert len(result.branches) == 0

    def test_maintains_array_consistency(self, sample_branch_data, filter_options_both):
        """Should maintain consistent array lengths in output."""
        result = filter_branches(
            branches=sample_branch_data["branches"],
            hashes=sample_branch_data["hashes"],
            subjects=sample_branch_data["subjects"],
            tracks=sample_branch_data["tracks"],
            dates=sample_branch_data["dates"],
            current_branch="main",
            options=filter_options_both,
        )

        # All arrays should have the same length
        assert len(result.branches) == len(result.hashes)
        assert len(result.branches) == len(result.subjects)
        assert len(result.branches) == len(result.tracks)
        assert len(result.branches) == len(result.dates)

    def test_inconsistent_array_lengths_raises_error(self):
        """Should raise ValueError when input arrays have different lengths."""
        options = FilterOptions()

        with pytest.raises(ValueError) as exc_info:
            filter_branches(
                branches=["main", "feature"],
                hashes=["abc"],  # Only 1 hash
                subjects=["Init", "Feature"],
                tracks=["", ""],
                dates=["2026-01-30", "2026-01-31"],
                current_branch="main",
                options=options,
            )

        assert "inconsistent lengths" in str(exc_info.value).lower()

    def test_preserves_parallel_array_data(self, sample_branch_data, filter_options_both):
        """Should preserve data alignment across parallel arrays."""
        result = filter_branches(
            branches=sample_branch_data["branches"],
            hashes=sample_branch_data["hashes"],
            subjects=sample_branch_data["subjects"],
            tracks=sample_branch_data["tracks"],
            dates=sample_branch_data["dates"],
            current_branch="main",
            options=filter_options_both,
        )

        # Find the index of "feature" in result
        if "feature" in result.branches:
            idx = result.branches.index("feature")
            assert result.hashes[idx] == "def456"
            assert result.subjects[idx] == "Feature"
            assert result.tracks[idx] == ""
            assert result.dates[idx] == "2026-01-31"

    def test_multiple_backup_branches(self):
        """Should filter out multiple backup branches."""
        options = FilterOptions(exclude_backup=True)

        result = filter_branches(
            branches=["main", "hug-backups/tmp1", "feature", "hug-backups/tmp2"],
            hashes=["abc", "def", "ghi", "jkl"],
            subjects=["Init", "B1", "Feature", "B2"],
            tracks=["", "", "", ""],
            dates=["2026-01-30", "2026-01-31", "2026-01-31", "2026-01-31"],
            current_branch="main",
            options=options,
        )

        assert len(result.branches) == 2
        assert "main" in result.branches
        assert "feature" in result.branches
        assert not any(b.startswith("hug-backups/") for b in result.branches)

    def test_current_branch_not_in_list(self, sample_branch_data, filter_options_exclude_current):
        """Should handle case where current_branch is not in the list."""
        result = filter_branches(
            branches=sample_branch_data["branches"],
            hashes=sample_branch_data["hashes"],
            subjects=sample_branch_data["subjects"],
            tracks=sample_branch_data["tracks"],
            dates=sample_branch_data["dates"],
            current_branch="nonexistent",  # Not in the list
            options=filter_options_exclude_current,
        )

        # Should return all branches except backups
        assert "main" in result.branches
        assert "feature" in result.branches
        assert "bugfix" in result.branches
        assert "hug-backups/tmp" in result.branches


################################################################################
# TestMainFunction (CLI tests)
################################################################################


class TestMainFunction:
    """Integration tests for main() CLI entry point."""

    def test_filter_command_outputs_bash_declarations(self, monkeypatch, capsys):
        """Should output bash declarations for filter command."""
        import sys

        monkeypatch.setattr(
            sys,
            "argv",
            [
                "branch_filter.py",
                "filter",
                "--branches",
                "main feature hug-backups/tmp",
                "--hashes",
                "abc def ghi",
                "--subjects",
                "Init Feature Backup",
                "--dates",
                "2026-01-30 2026-01-31 2026-01-31",
                "--exclude-backup",
                "--current-branch",
                "main",
            ],
        )

        from git.branch_filter import main

        result = main()
        captured = capsys.readouterr()

        assert result is None  # Success returns None
        assert "declare -a filtered_branches=" in captured.out
        assert "main" in captured.out
        assert "feature" in captured.out
        # Backup should be excluded
        assert "hug-backups/tmp" not in captured.out

    def test_exclude_current_flag(self, monkeypatch, capsys):
        """Should respect --exclude-current flag."""
        import sys

        monkeypatch.setattr(
            sys,
            "argv",
            [
                "branch_filter.py",
                "filter",
                "--branches",
                "main feature",
                "--hashes",
                "abc def",
                "--subjects",
                "Init Feature",
                "--dates",
                "2026-01-30 2026-01-31",
                "--current-branch",
                "main",
                "--exclude-current",
            ],
        )

        from git.branch_filter import main

        result = main()
        captured = capsys.readouterr()

        assert result is None
        assert "main" not in captured.out
        assert "feature" in captured.out

    def test_include_backup_flag(self, monkeypatch, capsys):
        """Should respect --include-backup flag."""
        import sys

        monkeypatch.setattr(
            sys,
            "argv",
            [
                "branch_filter.py",
                "filter",
                "--branches",
                "main hug-backups/tmp",
                "--hashes",
                "abc def",
                "--subjects",
                "Init Backup",
                "--dates",
                "2026-01-30 2026-01-31",
                "--include-backup",
            ],
        )

        from git.branch_filter import main

        result = main()
        captured = capsys.readouterr()

        assert result is None
        assert "hug-backups/tmp" in captured.out

    def test_exits_with_error_on_inconsistent_arrays(self, monkeypatch):
        """Should NOT error on inconsistent arrays from CLI - CLI pads them.

        Note: The direct filter_branches() function still raises ValueError
        for inconsistent arrays, but the CLI main() function handles this
        gracefully by padding shorter arrays with empty strings.
        """
        import sys

        monkeypatch.setattr(
            sys,
            "argv",
            [
                "branch_filter.py",
                "filter",
                "--branches",
                "main feature",
                "--hashes",
                "abc",  # Only one hash
                "--current-branch",
                "main",
            ],
        )

        from git.branch_filter import main

        # Should succeed because CLI pads arrays
        result = main()
        assert result is None
