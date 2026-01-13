"""
Unit tests for log_json.py module.

Tests the parsing of git log output with --numstat into JSON format.
"""

import pytest
import json
from io import StringIO
import sys
import os

# Add parent directory to path to import log_json
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from log_json import parse_log_with_stats, parse_single_commit


class TestParseLogWithStats:
    """Test parse_log_with_stats function"""

    def test_single_commit_basic(self):
        """Test parsing a single commit without stats"""
        lines = [
            "abc123def456789012345678901234567890abcd|~|abc123d|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|2 hours ago|~|2025-11-18T10:00:00Z|~|2 hours ago|~|tree123abc456def789012345678901234567890|~|Fix bug|~|Fix bug\n|~||~|\n"
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        assert commit["sha"] == "abc123def456789012345678901234567890abcd"
        assert commit["sha_short"] == "abc123d"
        assert commit["author"]["name"] == "Alice"
        assert commit["author"]["email"] == "alice@example.com"
        assert commit["subject"] == "Fix bug"
        assert commit["body"] is None

    def test_single_commit_with_body(self):
        """Test parsing commit with multi-line message body"""
        lines = [
            "abc123def456789012345678901234567890abcd|~|abc123d|~|Bob|~|bob@example.com|~|Bob|~|bob@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|2025-11-18T10:00:00Z|~|1 hour ago|~|tree456def789012345678901234567890abcdef|~|Add feature|~|Add feature\n\nThis is a longer description.\nWith multiple lines.|~||~|\n"
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        assert commit["subject"] == "Add feature"
        assert commit["body"] == "This is a longer description.\nWith multiple lines."

    def test_single_commit_with_numstat(self):
        """Test parsing commit with file statistics"""
        lines = [
            "abc123def456789012345678901234567890abcd|~|abc123d|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|2025-11-18T10:00:00Z|~|1 hour ago|~|tree789abc456def012345678901234567890ab|~|Update files|~|Update files\n|~||~|\n",
            "\n",
            "10\t5\tREADME.md\n",
            "20\t3\tsrc/app.js\n",
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        assert commit["stats"]["files_changed"] == 2
        assert commit["stats"]["insertions"] == 30
        assert commit["stats"]["deletions"] == 8

    def test_binary_file_in_numstat(self):
        """Test handling binary files (marked with -)"""
        lines = [
            "abc123def456789012345678901234567890abcd|~|abc123d|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|2025-11-18T10:00:00Z|~|1 hour ago|~|tree012abc456def789012345678901234567890|~|Add image|~|Add image\n|~||~|\n",
            "\n",
            "-\t-\timage.png\n",
            "5\t2\tREADME.md\n",
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        # Binary file contributes to file count but not insertions/deletions
        assert commit["stats"]["files_changed"] == 2
        assert commit["stats"]["insertions"] == 5
        assert commit["stats"]["deletions"] == 2

    def test_multiple_commits(self):
        """Test parsing multiple commits"""
        lines = [
            "abc123def456789012345678901234567890abcd|~|abc123d|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|2 hours ago|~|2025-11-18T10:00:00Z|~|2 hours ago|~|tree345abc456def789012345678901234567890|~|First commit|~|First commit\n|~||~|\n",
            "\n",
            "10\t5\tfile1.txt\n",
            "\n",
            "def456abc789012345678901234567890abcdef0|~|def456a|~|Bob|~|bob@example.com|~|Bob|~|bob@example.com|~|2025-11-18T11:00:00Z|~|1 hour ago|~|2025-11-18T11:00:00Z|~|1 hour ago|~|tree678def012345678901234567890abcdef12|~|Second commit|~|Second commit\n|~||~|\n",
            "\n",
            "20\t10\tfile2.txt\n",
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 2
        assert commits[0]["sha"] == "abc123def456789012345678901234567890abcd"
        assert commits[0]["stats"]["insertions"] == 10
        assert commits[1]["sha"] == "def456abc789012345678901234567890abcdef0"
        assert commits[1]["stats"]["insertions"] == 20

    def test_commit_with_refs(self):
        """Test parsing commit with branch/tag refs"""
        lines = [
            "abc123def456789012345678901234567890abcd|~|abc123d|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|2025-11-18T10:00:00Z|~|1 hour ago|~|tree901abc456def789012345678901234567890|~|Tagged commit|~|Tagged commit\n|~||~|HEAD -> main, origin/main, tag: v1.0\n"
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        assert "HEAD" in commit["refs"]
        assert "main" in commit["refs"]
        assert "origin/main" in commit["refs"]
        assert "tag: v1.0" in commit["refs"]

    def test_commit_with_multiple_parents(self):
        """Test merge commit with multiple parents"""
        lines = [
            "abc123def456789012345678901234567890abcd|~|abc123d|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|2025-11-18T10:00:00Z|~|1 hour ago|~|tree234abc456def789012345678901234567890|~|Merge branch|~|Merge branch\n|~|parent1abc456def789012345678901234567890 parent2def789abc012345678901234567890ab|~|\n"
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        assert len(commit["parents"]) == 2
        assert commit["parents"][0]["sha"] == "parent1abc456def789012345678901234567890"
        assert commit["parents"][1]["sha"] == "parent2def789abc012345678901234567890ab"

    def test_empty_input(self):
        """Test parsing empty input"""
        lines = []

        commits = parse_log_with_stats(lines)

        assert commits == []

    def test_commit_with_no_stats(self):
        """Test commit where no files changed (stats should be zero)"""
        lines = [
            "abc123def456789012345678901234567890abcd|~|abc123d|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|2025-11-18T10:00:00Z|~|1 hour ago|~|tree567abc456def789012345678901234567890|~|Empty commit|~|Empty commit\n|~||~|\n",
            "\n",
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        assert commit["stats"]["files_changed"] == 0
        assert commit["stats"]["insertions"] == 0
        assert commit["stats"]["deletions"] == 0

    def test_malformed_numstat_line(self):
        """Test that malformed numstat lines are skipped gracefully"""
        lines = [
            "abc123def456789012345678901234567890abcd|~|abc123d|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|2025-11-18T10:00:00Z|~|1 hour ago|~|tree890abc456def789012345678901234567890|~|Update|~|Update\n|~||~|\n",
            "\n",
            "10\t5\tvalid_file.txt\n",
            "malformed line without tabs\n",
            "20\t10\tanother_valid_file.txt\n",
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        # Should only count the 2 valid numstat lines
        assert commit["stats"]["files_changed"] == 2
        assert commit["stats"]["insertions"] == 30
        assert commit["stats"]["deletions"] == 15

    def test_commit_with_special_characters_in_message(self):
        """Test commit message with special characters"""
        lines = [
            'abc123def456789012345678901234567890abcd|~|abc123d|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|2025-11-18T10:00:00Z|~|1 hour ago|~|tree123def456789012345678901234567890ab|~|Fix "bug" in <module>|~|Fix "bug" in <module>\n\nDetailed description with special chars: $, %, &|~||~|\n'
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        assert commit["subject"] == 'Fix "bug" in <module>'
        assert "special chars: $, %, &" in commit["body"]

    def test_commit_with_empty_refs(self):
        """Test commit with no refs"""
        lines = [
            "abc123def456789012345678901234567890abcd|~|abc123d|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|2025-11-18T10:00:00Z|~|1 hour ago|~|tree456def789012345678901234567890abcdef|~|No refs|~|No refs\n|~||~|\n"
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        assert commit["refs"] is None

    def test_real_world_commit_format(self):
        """Test with a more realistic commit structure"""
        lines = [
            "e1bb93c05d8699243d43c9148a00804ae79cffff|~|e1bb93c|~|Elifarley C|~|elifarley@gmail.com|~|Elifarley C|~|elifarley@gmail.com|~|2025-11-18T19:19:14-03:00|~|12 minutes ago|~|2025-11-18T19:19:14-03:00|~|12 minutes ago|~|tree258d41a972c0e71100a1c64ca75de03bfc694|~|feat: add comprehensive JSON output support for analysis commands (Phase 4a)|~|feat: add comprehensive JSON output support for analysis commands (Phase 4a)\n\nWHY: JSON output enables automation.\n\nWHAT: Added JSON support to 4 commands.\n\nIMPACT: Users can now pipe output to jq.|~|258d41a972c0e71100a1c64ca75de03bfc6943d1|~|HEAD -> main\n",
            "\n",
            "11\t3\tREADME.md\n",
            "47\t23\tdocs/planning/json-output-roadmap.md\n",
            "213\t0\ttests/unit/test_json_output.bats\n",
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        assert commit["sha"] == "e1bb93c05d8699243d43c9148a00804ae79cffff"
        assert commit["sha_short"] == "e1bb93c"
        assert commit["author"]["name"] == "Elifarley C"
        assert "JSON output enables automation" in commit["body"]
        assert len(commit["parents"]) == 1
        assert "HEAD" in commit["refs"]
        assert "main" in commit["refs"]
        assert commit["stats"]["files_changed"] == 3
        assert commit["stats"]["insertions"] == 271  # 11 + 47 + 213
        assert commit["stats"]["deletions"] == 26  # 3 + 23 + 0


class TestEdgeCases:
    """Test edge cases and error handling"""

    def test_incomplete_commit_line(self):
        """Test handling of incomplete commit lines"""
        lines = [
            "abc123|~|abc|~|Alice\n",  # Incomplete - missing fields
            "def456abc789012345678901234567890abcdef0|~|def456a|~|Bob|~|bob@example.com|~|Bob|~|bob@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|2025-11-18T10:00:00Z|~|1 hour ago|~|tree012abc456def789012345678901234567890|~|Valid commit|~|Valid commit\n|~||~|\n",
        ]

        commits = parse_log_with_stats(lines)

        # Should skip incomplete line and only parse valid commit
        assert len(commits) == 1
        assert commits[0]["sha"] == "def456abc789012345678901234567890abcdef0"

    def test_blank_lines_between_commits(self):
        """Test that blank lines are handled correctly"""
        lines = [
            "abc123def456789012345678901234567890abcd|~|abc123d|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|2025-11-18T10:00:00Z|~|1 hour ago|~|tree345abc456def789012345678901234567890|~|First|~|First\n|~||~|\n",
            "\n",
            "\n",
            "\n",
            "def456abc789012345678901234567890abcdef0|~|def456a|~|Bob|~|bob@example.com|~|Bob|~|bob@example.com|~|2025-11-18T11:00:00Z|~|1 hour ago|~|2025-11-18T11:00:00Z|~|1 hour ago|~|tree678def012345678901234567890abcdef12|~|Second|~|Second\n|~||~|\n",
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 2

    def test_unicode_in_commit_message(self):
        """Test handling of Unicode characters"""
        lines = [
            "abc123def456789012345678901234567890abcd|~|abc123d|~|José García|~|jose@example.com|~|José García|~|jose@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|2025-11-18T10:00:00Z|~|1 hour ago|~|tree901abc456def789012345678901234567890|~|Add emoji support 🎉|~|Add emoji support 🎉\n\nSupports UTF-8: ñ, é, 中文|~||~|\n"
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        assert commit["author"]["name"] == "José García"
        assert "🎉" in commit["subject"]
        assert "中文" in commit["body"]


class TestConditionalStats:
    """Test conditional stats field inclusion (new 15-field format)"""

    def test_stats_included_when_flag_true(self):
        """Test stats field is present when include_stats=True"""
        lines = [
            "abc123def456789012345678901234567890abcd|~|abc123d|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|2 hours ago|~|2025-11-18T10:00:00Z|~|2 hours ago|~|tree123abc|~|Fix bug|~|Fix bug\n|~||~|\n",
            "\n",
            "10\t5\tREADME.md\n",
        ]

        commits = parse_log_with_stats(lines, include_stats=True)

        assert len(commits) == 1
        commit = commits[0]
        assert "stats" in commit
        assert commit["stats"]["files_changed"] == 1
        assert commit["stats"]["insertions"] == 10
        assert commit["stats"]["deletions"] == 5

    def test_stats_excluded_when_flag_false(self):
        """Test stats field is absent when include_stats=False"""
        lines = [
            "abc123def456789012345678901234567890abcd|~|abc123d|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|2 hours ago|~|2025-11-18T10:00:00Z|~|2 hours ago|~|tree123abc|~|Fix bug|~|Fix bug\n|~||~|\n",
            "\n",
            "10\t5\tREADME.md\n",
        ]

        commits = parse_log_with_stats(lines, include_stats=False)

        assert len(commits) == 1
        commit = commits[0]
        assert "stats" not in commit
        # Verify other fields still present
        assert commit["sha"] == "abc123def456789012345678901234567890abcd"
        assert commit["subject"] == "Fix bug"

    def test_stats_included_by_default(self):
        """Test stats field defaults to included (backward compatibility)"""
        lines = [
            "abc123def456789012345678901234567890abcd|~|abc123d|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|2 hours ago|~|2025-11-18T10:00:00Z|~|2 hours ago|~|tree123abc|~|Fix bug|~|Fix bug\n|~||~|\n"
        ]

        commits = parse_log_with_stats(lines)  # No include_stats arg

        assert len(commits) == 1
        commit = commits[0]
        assert "stats" in commit
        assert commit["stats"]["files_changed"] == 0


class TestNoBodyFlag:
    """Test --no-body flag functionality (new 15-field format)"""

    def test_body_omitted_when_flag_true(self):
        """Test body is None and message=subject when omit_body=True"""
        lines = [
            "abc123def456789012345678901234567890abcd|~|abc123d|~|Bob|~|bob@example.com|~|Bob|~|bob@example.com|~|2025-11-18T11:00:00Z|~|1 hour ago|~|2025-11-18T11:00:00Z|~|1 hour ago|~|tree456def|~|Add feature|~|Add feature\n\nThis is a detailed description.\nWith multiple lines.|~||~|\n"
        ]

        commits = parse_log_with_stats(lines, omit_body=True)

        assert len(commits) == 1
        commit = commits[0]
        assert commit["subject"] == "Add feature"
        assert commit["body"] is None
        assert commit["message"] == "Add feature"  # Should equal subject only

    def test_body_included_when_flag_false(self):
        """Test body is present when omit_body=False"""
        lines = [
            "abc123def456789012345678901234567890abcd|~|abc123d|~|Bob|~|bob@example.com|~|Bob|~|bob@example.com|~|2025-11-18T11:00:00Z|~|1 hour ago|~|2025-11-18T11:00:00Z|~|1 hour ago|~|tree456def|~|Add feature|~|Add feature\n\nThis is a detailed description.\nWith multiple lines.|~||~|\n"
        ]

        commits = parse_log_with_stats(lines, omit_body=False)

        assert len(commits) == 1
        commit = commits[0]
        assert commit["subject"] == "Add feature"
        assert commit["body"] == "This is a detailed description.\nWith multiple lines."
        assert (
            commit["message"]
            == "Add feature\n\nThis is a detailed description.\nWith multiple lines."
        )

    def test_body_included_by_default(self):
        """Test body defaults to included (backward compatibility)"""
        lines = [
            "abc123def456789012345678901234567890abcd|~|abc123d|~|Bob|~|bob@example.com|~|Bob|~|bob@example.com|~|2025-11-18T11:00:00Z|~|1 hour ago|~|2025-11-18T11:00:00Z|~|1 hour ago|~|tree456def|~|Add feature|~|Add feature\n\nDetailed body text.|~||~|\n"
        ]

        commits = parse_log_with_stats(lines)  # No omit_body arg

        assert len(commits) == 1
        commit = commits[0]
        assert commit["body"] == "Detailed body text."
        assert "Detailed body text." in commit["message"]

    def test_no_body_with_subject_only_commit(self):
        """Test --no-body flag on commit that has no body anyway"""
        lines = [
            "abc123def456789012345678901234567890abcd|~|abc123d|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|2 hours ago|~|2025-11-18T10:00:00Z|~|2 hours ago|~|tree123abc|~|Quick fix|~|Quick fix\n|~||~|\n"
        ]

        commits = parse_log_with_stats(lines, omit_body=True)

        assert len(commits) == 1
        commit = commits[0]
        assert commit["subject"] == "Quick fix"
        assert commit["body"] is None
        assert commit["message"] == "Quick fix"


class TestCombinedFlags:
    """Test combining include_stats and omit_body flags (new 15-field format)"""

    def test_no_stats_no_body(self):
        """Test with both stats excluded and body omitted"""
        lines = [
            "abc123def456789012345678901234567890abcd|~|abc123d|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|2 hours ago|~|2025-11-18T10:00:00Z|~|2 hours ago|~|tree123abc|~|Update docs|~|Update docs\n\nAdded new examples.|~||~|\n",
            "\n",
            "5\t2\tREADME.md\n",
        ]

        commits = parse_log_with_stats(lines, include_stats=False, omit_body=True)

        assert len(commits) == 1
        commit = commits[0]
        assert "stats" not in commit
        assert commit["body"] is None
        assert commit["message"] == "Update docs"
        assert commit["subject"] == "Update docs"

    def test_with_stats_no_body(self):
        """Test with stats included but body omitted"""
        lines = [
            "abc123def456789012345678901234567890abcd|~|abc123d|~|Bob|~|bob@example.com|~|Bob|~|bob@example.com|~|2025-11-18T11:00:00Z|~|1 hour ago|~|2025-11-18T11:00:00Z|~|1 hour ago|~|tree456def|~|Refactor code|~|Refactor code\n\nImproved performance.|~||~|\n",
            "\n",
            "15\t8\tsrc/main.py\n",
        ]

        commits = parse_log_with_stats(lines, include_stats=True, omit_body=True)

        assert len(commits) == 1
        commit = commits[0]
        assert "stats" in commit
        assert commit["stats"]["insertions"] == 15
        assert commit["body"] is None
        assert commit["message"] == "Refactor code"
