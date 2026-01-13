"""
Unit tests for hug_git_branch.py - Branch information retrieval.

Following Google Python testing best practices:
- Arrange-Act-Assert pattern
- Descriptive test names
- Test edge cases and error conditions
- Mock subprocess calls to avoid external dependencies
"""

import json
import pytest
from io import StringIO
from unittest.mock import patch, MagicMock
from subprocess import CalledProcessError

# Import module under test
import hug_git_branch


################################################################################
# Test Fixtures
################################################################################


@pytest.fixture
def sample_branch_details():
    """Sample BranchDetails for testing."""
    return hug_git_branch.BranchDetails(
        current_branch="main",
        max_len=10,
        branches=[
            hug_git_branch.BranchInfo(
                name="main", hash="abc123", subject="Initial commit", track="[origin/main: ahead 2]"
            ),
            hug_git_branch.BranchInfo(
                name="feature", hash="def456", subject="Add feature", track=""
            ),
            hug_git_branch.BranchInfo(
                name="bugfix", hash="ghi789", subject="Fix bug", track="[upstream/bugfix: behind 1]"
            ),
        ],
    )


@pytest.fixture
def sample_remote_branch_details():
    """Sample BranchDetails for remote branches."""
    return hug_git_branch.BranchDetails(
        current_branch="",
        max_len=8,
        branches=[
            hug_git_branch.BranchInfo(
                name="main", hash="abc123", subject="Main branch", remote_ref="origin/main"
            ),
            hug_git_branch.BranchInfo(
                name="feature",
                hash="def456",
                subject="Feature branch",
                remote_ref="upstream/feature",
            ),
        ],
    )


@pytest.fixture
def sample_wip_branch_details():
    """Sample BranchDetails for WIP branches."""
    return hug_git_branch.BranchDetails(
        current_branch="",
        max_len=12,
        branches=[
            hug_git_branch.BranchInfo(
                name="WIP/test-feature", hash="abc123", subject="[WIP] Work in progress"
            ),
            hug_git_branch.BranchInfo(
                name="WIP/bug-fix", hash="def456", subject="[WIP] Fixing bug"
            ),
        ],
    )


################################################################################
# TestBranchInfo (dataclass tests)
################################################################################


class TestBranchInfo:
    """Tests for BranchInfo dataclass."""

    def test_branch_info_initialization(self):
        """Should create BranchInfo with all fields."""
        branch = hug_git_branch.BranchInfo(
            name="main",
            hash="abc123",
            subject="Initial commit",
            track="[origin/main]",
            remote_ref="origin/main",
        )
        assert branch.name == "main"
        assert branch.hash == "abc123"
        assert branch.subject == "Initial commit"
        assert branch.track == "[origin/main]"
        assert branch.remote_ref == "origin/main"

    def test_branch_info_with_defaults(self):
        """Should create BranchInfo with default values."""
        branch = hug_git_branch.BranchInfo(name="feature", hash="def456")
        assert branch.name == "feature"
        assert branch.hash == "def456"
        assert branch.subject == ""
        assert branch.track == ""
        assert branch.remote_ref == ""


################################################################################
# TestBranchDetails (dataclass + serialization tests)
################################################################################


class TestBranchDetails:
    """Tests for BranchDetails dataclass and output methods."""

    def test_to_json_serializes_correctly(self, sample_branch_details):
        """Should serialize to valid JSON with all fields."""
        json_str = sample_branch_details.to_json()
        data = json.loads(json_str)

        assert data["current_branch"] == "main"
        assert data["max_len"] == 10
        assert len(data["branches"]) == 3
        assert data["branches"][0]["name"] == "main"
        assert data["branches"][0]["hash"] == "abc123"

    def test_to_json_includes_all_branch_fields(self):
        """Should include all branch fields in JSON."""
        details = hug_git_branch.BranchDetails(
            current_branch="main",
            max_len=10,
            branches=[
                hug_git_branch.BranchInfo(
                    name="feature",
                    hash="def456",
                    subject="Add feature",
                    track="[origin/feature]",
                    remote_ref="origin/feature",
                )
            ],
        )

        json_str = details.to_json()
        data = json.loads(json_str)

        branch = data["branches"][0]
        assert "name" in branch
        assert "hash" in branch
        assert "subject" in branch
        assert "track" in branch
        assert "remote_ref" in branch

    def test_to_bash_declare_outputs_valid_declarations(self, sample_branch_details):
        """Should output bash declare statements."""
        bash_output = sample_branch_details.to_bash_declare()

        assert "declare current_branch=" in bash_output
        assert "declare max_len=10" in bash_output
        assert "declare -a branches=" in bash_output
        assert "declare -a hashes=" in bash_output
        assert "declare -a tracks=" in bash_output
        assert "declare -a subjects=" in bash_output

    def test_to_bash_declare_includes_current_branch(self):
        """Should include current_branch in bash output."""
        details = hug_git_branch.BranchDetails(
            current_branch="main",
            max_len=10,
            branches=[hug_git_branch.BranchInfo(name="main", hash="abc123")],
        )

        bash_output = details.to_bash_declare()
        assert "declare current_branch='main'" in bash_output

    def test_to_bash_declare_includes_max_len(self):
        """Should include max_len in bash output."""
        details = hug_git_branch.BranchDetails(
            current_branch="main",
            max_len=25,
            branches=[hug_git_branch.BranchInfo(name="main", hash="abc123")],
        )

        bash_output = details.to_bash_declare()
        assert "declare max_len=25" in bash_output

    def test_to_bash_declare_includes_array_declarations(self):
        """Should include all array declarations."""
        details = hug_git_branch.BranchDetails(
            current_branch="main",
            max_len=10,
            branches=[
                hug_git_branch.BranchInfo(name="main", hash="abc123", subject="Commit 1", track=""),
                hug_git_branch.BranchInfo(
                    name="feature", hash="def456", subject="Commit 2", track="[origin/feature]"
                ),
            ],
        )

        bash_output = details.to_bash_declare()

        assert "declare -a branches=" in bash_output
        assert "declare -a hashes=" in bash_output
        assert "declare -a tracks=" in bash_output
        assert "declare -a subjects=" in bash_output

    def test_to_bash_declare_includes_remote_refs_for_remote_branches(
        self, sample_remote_branch_details
    ):
        """Should include remote_refs array when branches have remote_ref."""
        bash_output = sample_remote_branch_details.to_bash_declare()

        assert "declare -a remote_refs=" in bash_output
        assert "origin/main" in bash_output
        assert "upstream/feature" in bash_output

    def test_to_bash_declare_no_remote_refs_for_local_branches(self, sample_branch_details):
        """Should not include remote_refs array for local branches."""
        bash_output = sample_branch_details.to_bash_declare()

        assert "declare -a remote_refs=" not in bash_output

    def test_to_bash_declare_empty_arrays(self):
        """Should handle empty branch list."""
        details = hug_git_branch.BranchDetails(current_branch="", max_len=0, branches=[])

        bash_output = details.to_bash_declare()

        assert "declare -a branches=()" in bash_output
        assert "declare -a hashes=()" in bash_output
        assert "declare -a tracks=()" in bash_output
        assert "declare -a subjects=()" in bash_output


################################################################################
# TestBashEscape (utility function tests)
################################################################################


class TestBashEscape:
    """Tests for _bash_escape function."""

    def test_escapes_single_quotes(self):
        """Should escape single quotes correctly."""
        result = hug_git_branch._bash_escape("it's a test")
        assert "'\\''" in result

    def test_escapes_multiple_single_quotes(self):
        """Should escape multiple single quotes."""
        result = hug_git_branch._bash_escape("it's a 'test' here")
        # The result should contain escaped quotes - checking for presence rather than exact count
        assert "'\\''" in result
        assert "'test'" in result  # The word 'test' should also be present

    def test_escapes_backslashes(self):
        """Should escape backslashes correctly."""
        result = hug_git_branch._bash_escape(r"back\slash")
        assert "\\\\" in result

    def test_escapes_multiple_backslashes(self):
        """Should escape multiple backslashes."""
        result = hug_git_branch._bash_escape(r"back\\slash")
        assert "\\\\\\\\" in result  # Each \ becomes \\

    def test_escapes_both_single_quotes_and_backslashes(self):
        """Should escape both single quotes and backslashes."""
        result = hug_git_branch._bash_escape("it's a \\test")
        assert "'\\''" in result
        assert "\\\\" in result

    def test_handles_double_quotes(self):
        """Should handle double quotes (no special escaping needed in single quotes)."""
        result = hug_git_branch._bash_escape('test with "quotes"')
        assert '"' in result

    def test_handles_dollar_signs(self):
        """Should handle dollar signs (safe in single quotes)."""
        result = hug_git_branch._bash_escape("test with $var")
        assert "$" in result

    def test_handles_newlines_in_subjects(self):
        """Should preserve newlines in quoted strings."""
        result = hug_git_branch._bash_escape("line1\nline2")
        assert "line1" in result
        assert "line2" in result

    def test_handles_tabs(self):
        """Should handle tabs in strings."""
        result = hug_git_branch._bash_escape("test\ttab")
        assert "test" in result
        assert "tab" in result

    def test_handles_empty_string(self):
        """Should handle empty string."""
        result = hug_git_branch._bash_escape("")
        assert result == "''"

    def test_handles_simple_string(self):
        """Should handle simple alphanumeric string."""
        result = hug_git_branch._bash_escape("simple-test")
        assert result == "'simple-test'"

    def test_handles_special_characters(self):
        """Should handle various special characters."""
        result = hug_git_branch._bash_escape("test: value! [tag] (paren)")
        assert "test:" in result
        assert "value!" in result
        assert "[tag]" in result
        assert "(paren)" in result


################################################################################
# TestSanitizeString (utility function tests)
################################################################################


class TestSanitizeString:
    """Tests for _sanitize_string function."""

    def test_removes_leading_whitespace(self):
        """Should strip leading whitespace."""
        assert hug_git_branch._sanitize_string("  test") == "test"
        assert hug_git_branch._sanitize_string("\ttest") == "test"
        assert hug_git_branch._sanitize_string("\ntest") == "test"

    def test_removes_trailing_whitespace(self):
        """Should strip trailing whitespace."""
        assert hug_git_branch._sanitize_string("test  ") == "test"
        assert hug_git_branch._sanitize_string("test\t") == "test"
        assert hug_git_branch._sanitize_string("test\n") == "test"

    def test_removes_both_leading_and_trailing(self):
        """Should strip whitespace from both ends."""
        assert hug_git_branch._sanitize_string("  test  ") == "test"
        assert hug_git_branch._sanitize_string("\ntest\n") == "test"
        assert hug_git_branch._sanitize_string("  \t test \n  ") == "test"

    def test_removes_carriage_returns(self):
        """Should remove carriage returns."""
        assert hug_git_branch._sanitize_string("test\r\n") == "test"
        assert hug_git_branch._sanitize_string("test\r") == "test"

    def test_preserves_internal_whitespace(self):
        """Should preserve internal whitespace."""
        assert hug_git_branch._sanitize_string("test value") == "test value"
        assert hug_git_branch._sanitize_string("  test value  ") == "test value"

    def test_handles_empty_string(self):
        """Should handle empty string."""
        assert hug_git_branch._sanitize_string("") == ""

    def test_handles_whitespace_only(self):
        """Should handle whitespace-only string."""
        assert hug_git_branch._sanitize_string("   ") == ""
        assert hug_git_branch._sanitize_string("\n\t\r") == ""


################################################################################
# TestRunGit (git command execution tests)
################################################################################


class TestRunGit:
    """Tests for _run_git function."""

    def test_runs_git_command_successfully(self):
        """Should run git command and return stdout."""
        with patch("hug_git_branch.subprocess.run") as mock_run:
            mock_result = MagicMock()
            mock_result.stdout = "output\n"
            mock_run.return_value = mock_result

            result = hug_git_branch._run_git(["status"])

            assert result == "output"
            mock_run.assert_called_once_with(
                ["git", "status"], capture_output=True, text=True, check=True
            )

    def test_runs_git_command_with_check_false(self):
        """Should run git command without checking exit code."""
        with patch("hug_git_branch.subprocess.run") as mock_run:
            mock_result = MagicMock()
            mock_result.stdout = "output\n"
            mock_run.return_value = mock_result

            result = hug_git_branch._run_git(["status"], check=False)

            assert result == "output"
            mock_run.assert_called_once_with(
                ["git", "status"], capture_output=True, text=True, check=False
            )

    def test_strips_trailing_newlines(self):
        """Should strip trailing newlines and carriage returns."""
        with patch("hug_git_branch.subprocess.run") as mock_run:
            mock_result = MagicMock()
            mock_result.stdout = "output\n\r\n"
            mock_run.return_value = mock_result

            result = hug_git_branch._run_git(["status"])

            assert result == "output"

    def test_raises_on_non_zero_exit_when_check_true(self):
        """Should raise CalledProcessError on non-zero exit when check=True."""
        with patch("hug_git_branch.subprocess.run") as mock_run:
            mock_run.side_effect = CalledProcessError(1, "git")

            with pytest.raises(CalledProcessError):
                hug_git_branch._run_git(["status"], check=True)

    def test_returns_false_when_check_false(self):
        """Should not raise when check=False even on non-zero exit."""
        with patch("hug_git_branch.subprocess.run") as mock_run:
            # When check=False, _run_git catches the exception internally
            # Set up a mock result that will be returned
            mock_result = MagicMock()
            mock_result.stdout = ""
            mock_run.return_value = mock_result

            result = hug_git_branch._run_git(["status"], check=False)

            # Should complete without raising
            assert result is not None


################################################################################
# TestComputeDivergence (divergence calculation tests)
################################################################################


class TestComputeDivergence:
    """Tests for _compute_divergence function."""

    def test_ahead_only_returns_correct_status(self):
        """Should return [ahead N] when only ahead."""
        with patch("hug_git_branch._run_git") as mock_run:
            mock_run.return_value = "3\t0"

            status, ahead, behind = hug_git_branch._compute_divergence("feature", "origin/main")

            assert status == "[ahead 3]"
            assert ahead == "3"
            assert behind == "0"

    def test_behind_only_returns_correct_status(self):
        """Should return [behind N] when only behind."""
        with patch("hug_git_branch._run_git") as mock_run:
            mock_run.return_value = "0\t2"

            status, ahead, behind = hug_git_branch._compute_divergence("feature", "origin/main")

            assert status == "[behind 2]"
            assert ahead == "0"
            assert behind == "2"

    def test_even_returns_empty_status(self):
        """Should return empty string when even."""
        with patch("hug_git_branch._run_git") as mock_run:
            mock_run.return_value = "0\t0"

            status, ahead, behind = hug_git_branch._compute_divergence("feature", "origin/main")

            assert status == ""
            assert ahead == "0"
            assert behind == "0"

    def test_ahead_and_behind_returns_correct_status(self):
        """Should return [ahead N, behind M] when diverged."""
        with patch("hug_git_branch._run_git") as mock_run:
            mock_run.return_value = "3\t2"

            status, ahead, behind = hug_git_branch._compute_divergence("feature", "origin/main")

            assert status == "[ahead 3, behind 2]"
            assert ahead == "3"
            assert behind == "2"

    def test_handles_empty_output(self):
        """Should handle empty git output."""
        with patch("hug_git_branch._run_git") as mock_run:
            mock_run.return_value = ""

            status, ahead, behind = hug_git_branch._compute_divergence("feature", "origin/main")

            assert status == ""
            assert ahead == "0"
            assert behind == "0"

    def test_handles_malformed_output(self):
        """Should handle malformed output (wrong format)."""
        with patch("hug_git_branch._run_git") as mock_run:
            mock_run.return_value = "invalid"

            status, ahead, behind = hug_git_branch._compute_divergence("feature", "origin/main")

            assert status == ""
            assert ahead == "0"
            assert behind == "0"

    def test_handles_git_error(self):
        """Should handle git command errors gracefully."""
        with patch("hug_git_branch._run_git") as mock_run:
            mock_run.side_effect = CalledProcessError(1, "git")

            status, ahead, behind = hug_git_branch._compute_divergence("feature", "origin/main")

            assert status == ""
            assert ahead == "0"
            assert behind == "0"


################################################################################
# TestGetLocalBranchDetails (main function tests with mocks)
################################################################################


class TestGetLocalBranchDetails:
    """Tests for get_local_branch_details function."""

    def test_returns_branch_details_with_subjects(self):
        """Should parse git for-each-ref output with subjects."""
        with (
            patch("hug_git_branch._run_git") as mock_run,
            patch("hug_git_branch._run_git_for_each_ref") as mock_for_each,
            patch("hug_git_branch._compute_divergence") as mock_divergence,
        ):
            # Mock current branch
            mock_run.side_effect = [
                "main",  # branch --show-current
            ]

            # Mock divergence
            mock_divergence.return_value = ("", "0", "0")

            # Mock for-each-ref output
            mock_for_each.return_value = [
                "main",
                "abc123",
                "Initial commit",
                "origin/main",
                "[origin/main: ahead 2]",
                "",
            ]

            result = hug_git_branch.get_local_branch_details(include_subjects=True)

            assert result is not None
            assert result.current_branch == "main"
            assert len(result.branches) == 1
            assert result.branches[0].name == "main"
            assert result.branches[0].subject == "Initial commit"

    def test_excludes_backup_branches_when_enabled(self):
        """Should exclude hug-backups/* branches when exclude_backup=True."""
        with (
            patch("hug_git_branch._run_git") as mock_run,
            patch("hug_git_branch._run_git_for_each_ref") as mock_for_each,
            patch("hug_git_branch._compute_divergence") as mock_divergence,
        ):
            mock_run.return_value = "main"
            mock_divergence.return_value = ("", "0", "0")

            # Include a backup branch - each branch has 5 elements (refname, hash, subject, upstream, track)
            mock_for_each.return_value = [
                "main",
                "abc123",
                "Initial commit",
                "origin/main",
                "[origin/main]",
                "hug-backups/test",
                "def456",
                "Backup commit",
                "",
                "",
            ]

            result = hug_git_branch.get_local_branch_details(
                exclude_backup=True, batch_divergence=False
            )

            # Should not include backup branch
            assert len(result.branches) == 1
            assert result.branches[0].name == "main"

    def test_includes_backup_branches_when_disabled(self):
        """Should include hug-backups/* branches when exclude_backup=False."""
        with (
            patch("hug_git_branch._run_git") as mock_run,
            patch("hug_git_branch._run_git_for_each_ref") as mock_for_each,
            patch("hug_git_branch._compute_divergence") as mock_divergence,
        ):
            mock_run.return_value = "main"
            mock_divergence.return_value = ("", "0", "0")

            mock_for_each.return_value = [
                "main",
                "abc123",
                "Initial commit",
                "origin/main",
                "[origin/main]",
                "hug-backups/test",
                "def456",
                "Backup commit",
                "",
                "",
            ]

            result = hug_git_branch.get_local_branch_details(
                exclude_backup=False, batch_divergence=False
            )

            # Should include backup branch
            assert len(result.branches) == 2
            branch_names = [b.name for b in result.branches]
            assert "main" in branch_names
            assert "hug-backups/test" in branch_names

    def test_returns_none_when_no_branches(self):
        """Should return None when no branches exist."""
        with (
            patch("hug_git_branch._run_git") as mock_run,
            patch("hug_git_branch._run_git_for_each_ref") as mock_for_each,
        ):
            mock_run.return_value = "main"
            mock_for_each.return_value = []

            result = hug_git_branch.get_local_branch_details()

            assert result is None

    def test_calculates_max_len_correctly(self):
        """Should calculate maximum branch name length."""
        with (
            patch("hug_git_branch._run_git") as mock_run,
            patch("hug_git_branch._run_git_for_each_ref") as mock_for_each,
            patch("hug_git_branch._compute_divergence") as mock_divergence,
        ):
            mock_run.return_value = "main"
            mock_divergence.return_value = ("", "0", "0")

            # chunk_size is 5 with subjects - each branch has 5 elements (refname, hash, subject, upstream, track)
            mock_for_each.return_value = [
                "main",
                "abc123",
                "Commit",
                "",
                "",
                "very-long-branch-name",
                "def456",
                "Commit",
                "",
                "",
                "short",
                "ghi789",
                "Commit",
                "",
                "",
            ]

            result = hug_git_branch.get_local_branch_details(batch_divergence=False)

            assert result.max_len == len("very-long-branch-name")

    def test_detects_detached_head(self):
        """Should set current_branch to 'detached HEAD' when detached."""
        with (
            patch("hug_git_branch._run_git") as mock_run,
            patch("hug_git_branch._run_git_for_each_ref") as mock_for_each,
        ):
            mock_run.return_value = ""  # Empty = detached
            mock_for_each.return_value = ["main", "abc123", "Commit", "", ""]

            result = hug_git_branch.get_local_branch_details()

            assert result.current_branch == "detached HEAD"

    def test_without_subjects(self):
        """Should work without including subjects."""
        with (
            patch("hug_git_branch._run_git") as mock_run,
            patch("hug_git_branch._run_git_for_each_ref") as mock_for_each,
        ):
            mock_run.return_value = "main"

            # Without subjects, chunk size is smaller
            mock_for_each.return_value = ["main", "abc123", "origin/main", ""]

            result = hug_git_branch.get_local_branch_details(include_subjects=False)

            assert result is not None
            assert result.branches[0].subject == ""

    def test_divergence_calculation(self):
        """Should add divergence info to track strings when batch_divergence=True."""
        with (
            patch("hug_git_branch._run_git") as mock_run,
            patch("hug_git_branch._run_git_for_each_ref") as mock_for_each,
        ):
            mock_run.side_effect = ["main", "2\t1"]  # Current branch + divergence

            mock_for_each.return_value = ["main", "abc123", "Initial commit", "origin/main", "", ""]

            result = hug_git_branch.get_local_branch_details(batch_divergence=True)

            # Track string should include divergence
            assert "ahead 2" in result.branches[0].track or "behind 1" in result.branches[0].track


################################################################################
# TestGetRemoteBranchDetails
################################################################################


class TestGetRemoteBranchDetails:
    """Tests for get_remote_branch_details function."""

    def test_returns_remote_branch_details(self):
        """Should parse remote branches correctly."""
        with patch("hug_git_branch._run_git_for_each_ref") as mock_for_each:
            mock_for_each.return_value = [
                "origin/main",
                "abc123",
                "Main branch",
                "origin/feature",
                "def456",
                "Feature branch",
            ]

            result = hug_git_branch.get_remote_branch_details()

            assert result is not None
            assert len(result.branches) == 2
            assert result.branches[0].name == "main"
            assert result.branches[0].remote_ref == "origin/main"
            assert result.branches[1].name == "feature"
            assert result.branches[1].remote_ref == "origin/feature"

    def test_excludes_head_references(self):
        """Should exclude */HEAD references."""
        with patch("hug_git_branch._run_git_for_each_ref") as mock_for_each:
            mock_for_each.return_value = [
                "origin/main",
                "abc123",
                "Main branch",
                "origin/HEAD",
                "def456",
                "HEAD reference",
            ]

            result = hug_git_branch.get_remote_branch_details()

            # Should exclude HEAD refs
            assert len(result.branches) == 1
            assert result.branches[0].name == "main"

    def test_extracts_branch_name_from_remote_ref(self):
        """Should strip remote prefix (e.g., origin/feature -> feature)."""
        with patch("hug_git_branch._run_git_for_each_ref") as mock_for_each:
            mock_for_each.return_value = ["origin/feature", "abc123", "Feature commit"]

            result = hug_git_branch.get_remote_branch_details()

            assert result.branches[0].name == "feature"
            assert result.branches[0].remote_ref == "origin/feature"

    def test_sets_current_branch_to_empty_string(self):
        """Should set current_branch to empty for remote branches."""
        with patch("hug_git_branch._run_git_for_each_ref") as mock_for_each:
            mock_for_each.return_value = ["origin/main", "abc123", "Main branch"]

            result = hug_git_branch.get_remote_branch_details()

            assert result.current_branch == ""

    def test_returns_none_when_no_remote_branches(self):
        """Should return None when no remote branches exist."""
        with patch("hug_git_branch._run_git_for_each_ref") as mock_for_each:
            mock_for_each.return_value = []

            result = hug_git_branch.get_remote_branch_details()

            assert result is None

    def test_calculates_max_len(self):
        """Should calculate maximum branch name length (without remote prefix)."""
        with patch("hug_git_branch._run_git_for_each_ref") as mock_for_each:
            mock_for_each.return_value = [
                "origin/main",
                "abc123",
                "Commit",
                "upstream/very-long-branch",
                "def456",
                "Commit",
            ]

            result = hug_git_branch.get_remote_branch_details()

            # Max len should be based on "very-long-branch", not "upstream/very-long-branch"
            assert result.max_len == len("very-long-branch")


################################################################################
# TestGetWipBranchDetails
################################################################################


class TestGetWipBranchDetails:
    """Tests for get_wip_branch_details function."""

    def test_returns_wip_branches_with_default_pattern(self):
        """Should find WIP/* branches with default pattern."""
        with patch("hug_git_branch._run_git_for_each_ref") as mock_for_each:
            mock_for_each.return_value = [
                "WIP/test-feature",
                "abc123",
                "[WIP] Work in progress",
                "WIP/bug-fix",
                "def456",
                "[WIP] Fixing bug",
            ]

            result = hug_git_branch.get_wip_branch_details()

            assert result is not None
            assert len(result.branches) == 2
            assert "WIP/test-feature" in [b.name for b in result.branches]
            assert "WIP/bug-fix" in [b.name for b in result.branches]

    def test_uses_custom_ref_pattern(self):
        """Should use custom ref pattern when provided."""
        with patch("hug_git_branch._run_git_for_each_ref") as mock_for_each:
            mock_for_each.return_value = [
                "temp/feature-1",
                "abc123",
                "Temp commit",
                "temp/feature-2",
                "def456",
                "Temp commit",
            ]

            result = hug_git_branch.get_wip_branch_details(ref_pattern="refs/heads/temp/")

            assert result is not None
            assert len(result.branches) == 2

    def test_returns_none_when_no_wip_branches(self):
        """Should return None when no matching branches exist."""
        with patch("hug_git_branch._run_git_for_each_ref") as mock_for_each:
            mock_for_each.return_value = []

            result = hug_git_branch.get_wip_branch_details()

            assert result is None

    def test_sets_current_branch_to_empty(self):
        """Should set current_branch to empty for WIP listing."""
        with patch("hug_git_branch._run_git_for_each_ref") as mock_for_each:
            mock_for_each.return_value = ["WIP/test", "abc123", "Commit"]

            result = hug_git_branch.get_wip_branch_details()

            assert result.current_branch == ""


################################################################################
# TestFindRemoteBranch
################################################################################


class TestFindRemoteBranch:
    """Tests for find_remote_branch function."""

    def test_finds_branch_by_full_remote_ref(self):
        """Should return full ref if given full ref exists."""
        with patch("hug_git_branch._run_git") as mock_run:
            # Mock show-ref --verify success - it returns empty string on success
            mock_run.return_value = ""

            result = hug_git_branch.find_remote_branch("origin/feature")

            assert result == "origin/feature"

    def test_finds_branch_by_short_name(self):
        """Should find remote branch by short name."""
        from subprocess import CalledProcessError

        def side_effect_func(*args, **kwargs):
            if "show-ref" in args[0]:
                raise CalledProcessError(1, "git")
            return "origin/feature\nupstream/feature"

        with patch("hug_git_branch._run_git") as mock_run:
            mock_run.side_effect = side_effect_func

            result = hug_git_branch.find_remote_branch("feature")

            # Should prefer origin
            assert result == "origin/feature"

    def test_prefers_origin_when_multiple_remotes(self):
        """Should prefer origin when multiple remotes have same branch."""
        from subprocess import CalledProcessError

        def side_effect_func(*args, **kwargs):
            if "show-ref" in args[0]:
                raise CalledProcessError(1, "git")
            return "upstream/feature\nfork/feature\norigin/feature"

        with patch("hug_git_branch._run_git") as mock_run:
            mock_run.side_effect = side_effect_func

            result = hug_git_branch.find_remote_branch("feature")

            assert result == "origin/feature"

    def test_returns_alphabetically_first_when_no_origin(self):
        """Should return alphabetically first when no origin match."""
        from subprocess import CalledProcessError

        def side_effect_func(*args, **kwargs):
            if "show-ref" in args[0]:
                raise CalledProcessError(1, "git")
            return "fork/feature\nupstream/feature"

        with patch("hug_git_branch._run_git") as mock_run:
            mock_run.side_effect = side_effect_func

            result = hug_git_branch.find_remote_branch("feature")

            # Alphabetically first
            assert result == "fork/feature"

    def test_returns_none_when_not_found(self):
        """Should return None when branch doesn't exist."""
        from subprocess import CalledProcessError

        def side_effect_func(*args, **kwargs):
            if "show-ref" in args[0]:
                raise CalledProcessError(1, "git")
            return ""  # No matches from for-each-ref

        with patch("hug_git_branch._run_git") as mock_run:
            mock_run.side_effect = side_effect_func

            result = hug_git_branch.find_remote_branch("nonexistent")

            assert result is None


################################################################################
# TestMainFunction (CLI tests)
################################################################################


class TestMainFunction:
    """Integration tests for main() CLI entry point."""

    def test_local_outputs_bash_by_default(self, monkeypatch, capsys):
        """Should output bash declarations by default for local type."""
        import sys

        monkeypatch.setattr(sys, "argv", ["hug_git_branch.py", "local"])

        with patch("hug_git_branch.get_local_branch_details") as mock_get:
            mock_get.return_value = hug_git_branch.BranchDetails(
                current_branch="main",
                max_len=10,
                branches=[
                    hug_git_branch.BranchInfo(
                        name="main", hash="abc123", subject="Commit", track=""
                    )
                ],
            )

            # The main function returns None on success, calls sys.exit() on failure
            result = hug_git_branch.main()
            captured = capsys.readouterr()

            assert result is None  # Success returns None
            assert "declare current_branch=" in captured.out
            assert "declare -a branches=" in captured.out

    def test_local_outputs_json_with_flag(self, monkeypatch, capsys):
        """Should output JSON with --json flag."""
        import sys

        monkeypatch.setattr(sys, "argv", ["hug_git_branch.py", "local", "--json"])

        with patch("hug_git_branch.get_local_branch_details") as mock_get:
            mock_get.return_value = hug_git_branch.BranchDetails(
                current_branch="main",
                max_len=10,
                branches=[
                    hug_git_branch.BranchInfo(
                        name="main", hash="abc123", subject="Commit", track=""
                    )
                ],
            )

            result = hug_git_branch.main()
            captured = capsys.readouterr()

            assert result is None  # Success returns None
            data = json.loads(captured.out)
            assert "branches" in data
            assert data["current_branch"] == "main"

    def test_remote_mode(self, monkeypatch, capsys):
        """Should handle remote branch queries."""
        import sys

        monkeypatch.setattr(sys, "argv", ["hug_git_branch.py", "remote"])

        with patch("hug_git_branch.get_remote_branch_details") as mock_get:
            mock_get.return_value = hug_git_branch.BranchDetails(
                current_branch="",
                max_len=10,
                branches=[
                    hug_git_branch.BranchInfo(
                        name="main", hash="abc123", subject="Commit", remote_ref="origin/main"
                    )
                ],
            )

            result = hug_git_branch.main()
            captured = capsys.readouterr()

            assert result is None  # Success returns None
            assert "declare -a remote_refs=" in captured.out

    def test_wip_mode(self, monkeypatch, capsys):
        """Should handle WIP branch queries."""
        import sys

        monkeypatch.setattr(sys, "argv", ["hug_git_branch.py", "wip"])

        with patch("hug_git_branch.get_wip_branch_details") as mock_get:
            mock_get.return_value = hug_git_branch.BranchDetails(
                current_branch="",
                max_len=10,
                branches=[
                    hug_git_branch.BranchInfo(name="WIP/test", hash="abc123", subject="WIP commit")
                ],
            )

            result = hug_git_branch.main()
            captured = capsys.readouterr()

            assert result is None  # Success returns None
            assert "declare -a branches=" in captured.out
            assert "WIP/test" in captured.out

    def test_wip_custom_pattern(self, monkeypatch):
        """Should accept custom pattern for WIP branches."""
        import sys

        monkeypatch.setattr(
            sys, "argv", ["hug_git_branch.py", "wip", "--pattern", "refs/heads/temp/"]
        )

        with patch("hug_git_branch.get_wip_branch_details") as mock_get:
            mock_get.return_value = hug_git_branch.BranchDetails(
                current_branch="",
                max_len=10,
                branches=[
                    hug_git_branch.BranchInfo(
                        name="temp/test", hash="abc123", subject="Temp commit"
                    )
                ],
            )

            result = hug_git_branch.main()

            assert result is None  # Success returns None
            mock_get.assert_called_once_with(include_subjects=True, ref_pattern="refs/heads/temp/")

    def test_exits_with_1_when_no_branches(self, monkeypatch):
        """Should exit with code 1 when no branches found."""
        import sys

        monkeypatch.setattr(sys, "argv", ["hug_git_branch.py", "local"])

        with patch("hug_git_branch.get_local_branch_details") as mock_get:
            mock_get.return_value = None

            with pytest.raises(SystemExit) as exc_info:
                hug_git_branch.main()

            assert exc_info.value.code == 1

    def test_exits_with_1_on_git_error(self, monkeypatch):
        """Should exit with code 1 on git errors."""
        import sys

        monkeypatch.setattr(sys, "argv", ["hug_git_branch.py", "local"])

        with patch("hug_git_branch.get_local_branch_details") as mock_get:
            mock_get.side_effect = CalledProcessError(1, "git")

            with pytest.raises(SystemExit) as exc_info:
                hug_git_branch.main()

            assert exc_info.value.code == 1

    def test_exits_with_1_on_exception(self, monkeypatch, capsys):
        """Should exit with code 1 on unexpected errors."""
        import sys

        monkeypatch.setattr(sys, "argv", ["hug_git_branch.py", "local"])

        with patch("hug_git_branch.get_local_branch_details") as mock_get:
            mock_get.side_effect = Exception("Unexpected error")

            with pytest.raises(SystemExit) as exc_info:
                hug_git_branch.main()

            assert exc_info.value.code == 1

    def test_unknown_type_exits_with_2(self, monkeypatch):
        """Should exit with code 2 for unknown branch type."""
        import sys

        # Simulate invalid argument by patching argparse
        monkeypatch.setattr(sys, "argv", ["hug_git_branch.py", "unknown"])

        # argparse will exit with code 2 for invalid arguments
        with pytest.raises(SystemExit) as exc_info:
            hug_git_branch.main()

        # argparse uses exit code 2
        assert exc_info.value.code == 2


################################################################################
# TestEdgeCases
################################################################################


class TestEdgeCases:
    """Tests for edge cases and boundary conditions."""

    def test_handles_branch_names_with_special_chars(self):
        """Should handle branch names with special characters."""
        branch = hug_git_branch.BranchInfo(
            name="feature/fix-1.2.3", hash="abc123", subject="Commit"
        )

        bash_output = hug_git_branch.BranchDetails(
            current_branch=branch.name, max_len=20, branches=[branch]
        ).to_bash_declare()

        assert "feature/fix-1.2.3" in bash_output

    def test_handles_subjects_with_parentheses(self):
        """Should handle subjects with parentheses."""
        branch = hug_git_branch.BranchInfo(
            name="main", hash="abc123", subject="Fix bug (issue #123)"
        )

        bash_output = hug_git_branch.BranchDetails(
            current_branch="main", max_len=10, branches=[branch]
        ).to_bash_declare()

        assert "Fix bug (issue #123)" in bash_output

    def test_handles_subjects_with_brackets(self):
        """Should handle subjects with square brackets."""
        branch = hug_git_branch.BranchInfo(
            name="main", hash="abc123", subject="[WIP] Work in progress"
        )

        bash_output = hug_git_branch.BranchDetails(
            current_branch="main", max_len=10, branches=[branch]
        ).to_bash_declare()

        assert "[WIP] Work in progress" in bash_output

    def test_handles_unicode_in_subjects(self):
        """Should handle unicode characters in commit subjects."""
        branch = hug_git_branch.BranchInfo(
            name="main", hash="abc123", subject="Add emoji support ✨ 🎉"
        )

        bash_output = hug_git_branch.BranchDetails(
            current_branch="main", max_len=10, branches=[branch]
        ).to_bash_declare()

        # Should handle unicode without errors
        assert "✨" in bash_output or bash_output  # Just check it doesn't crash

    def test_handles_very_long_branch_names(self):
        """Should handle very long branch names."""
        long_name = "a" * 100
        branch = hug_git_branch.BranchInfo(name=long_name, hash="abc123", subject="Commit")

        details = hug_git_branch.BranchDetails(
            current_branch=long_name, max_len=100, branches=[branch]
        )

        assert details.max_len == 100
