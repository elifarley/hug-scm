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
from log_json import parse_log_with_stats


class TestParseLogWithStats:
    """Test parse_log_with_stats function"""

    def test_single_commit_basic(self):
        """Test parsing a single commit without stats"""
        lines = [
            "abc123def456|~|abc123|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|2 hours ago|~|Fix bug|~|Fix bug\n|~||~|\n"
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        assert commit['hash'] == 'abc123def456'
        assert commit['hash_short'] == 'abc123'
        assert commit['author']['name'] == 'Alice'
        assert commit['author']['email'] == 'alice@example.com'
        assert commit['message']['subject'] == 'Fix bug'
        assert commit['message']['body'] is None

    def test_single_commit_with_body(self):
        """Test parsing commit with multi-line message body"""
        lines = [
            "abc123|~|abc|~|Bob|~|bob@example.com|~|Bob|~|bob@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|Add feature|~|Add feature\n\nThis is a longer description.\nWith multiple lines.|~||~|\n"
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        assert commit['message']['subject'] == 'Add feature'
        assert commit['message']['body'] == 'This is a longer description.\nWith multiple lines.'

    def test_single_commit_with_numstat(self):
        """Test parsing commit with file statistics"""
        lines = [
            "abc123|~|abc|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|Update files|~|Update files\n|~||~|\n",
            "\n",
            "10\t5\tREADME.md\n",
            "20\t3\tsrc/app.js\n"
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        assert commit['stats']['files_changed'] == 2
        assert commit['stats']['insertions'] == 30
        assert commit['stats']['deletions'] == 8

    def test_binary_file_in_numstat(self):
        """Test handling binary files (marked with -)"""
        lines = [
            "abc123|~|abc|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|Add image|~|Add image\n|~||~|\n",
            "\n",
            "-\t-\timage.png\n",
            "5\t2\tREADME.md\n"
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        # Binary file contributes to file count but not insertions/deletions
        assert commit['stats']['files_changed'] == 2
        assert commit['stats']['insertions'] == 5
        assert commit['stats']['deletions'] == 2

    def test_multiple_commits(self):
        """Test parsing multiple commits"""
        lines = [
            "abc123|~|abc|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|2 hours ago|~|First commit|~|First commit\n|~||~|\n",
            "\n",
            "10\t5\tfile1.txt\n",
            "def456|~|def|~|Bob|~|bob@example.com|~|Bob|~|bob@example.com|~|2025-11-18T11:00:00Z|~|1 hour ago|~|Second commit|~|Second commit\n|~||~|\n",
            "\n",
            "20\t10\tfile2.txt\n"
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 2
        assert commits[0]['hash'] == 'abc123'
        assert commits[0]['stats']['insertions'] == 10
        assert commits[1]['hash'] == 'def456'
        assert commits[1]['stats']['insertions'] == 20

    def test_commit_with_refs(self):
        """Test parsing commit with branch/tag refs"""
        lines = [
            "abc123|~|abc|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|Tagged commit|~|Tagged commit\n|~||~|HEAD -> main, origin/main, tag: v1.0\n"
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        assert 'HEAD' in commit['refs']
        assert 'main' in commit['refs']
        assert 'origin/main' in commit['refs']
        assert 'tag: v1.0' in commit['refs']

    def test_commit_with_multiple_parents(self):
        """Test merge commit with multiple parents"""
        lines = [
            "abc123|~|abc|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|Merge branch|~|Merge branch\n|~|parent1 parent2|~|\n"
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        assert len(commit['parents']) == 2
        assert 'parent1' in commit['parents']
        assert 'parent2' in commit['parents']

    def test_empty_input(self):
        """Test parsing empty input"""
        lines = []

        commits = parse_log_with_stats(lines)

        assert commits == []

    def test_commit_with_no_stats(self):
        """Test commit where no files changed (stats should be zero)"""
        lines = [
            "abc123|~|abc|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|Empty commit|~|Empty commit\n|~||~|\n",
            "\n"
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        assert commit['stats']['files_changed'] == 0
        assert commit['stats']['insertions'] == 0
        assert commit['stats']['deletions'] == 0

    def test_malformed_numstat_line(self):
        """Test that malformed numstat lines are skipped gracefully"""
        lines = [
            "abc123|~|abc|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|Update|~|Update\n|~||~|\n",
            "\n",
            "10\t5\tvalid_file.txt\n",
            "malformed line without tabs\n",
            "20\t10\tanother_valid_file.txt\n"
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        # Should only count the 2 valid numstat lines
        assert commit['stats']['files_changed'] == 2
        assert commit['stats']['insertions'] == 30
        assert commit['stats']['deletions'] == 15

    def test_commit_with_special_characters_in_message(self):
        """Test commit message with special characters"""
        lines = [
            'abc123|~|abc|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|Fix "bug" in <module>|~|Fix "bug" in <module>\n\nDetailed description with special chars: $, %, &|~||~|\n'
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        assert commit['message']['subject'] == 'Fix "bug" in <module>'
        assert 'special chars: $, %, &' in commit['message']['body']

    def test_commit_with_empty_refs(self):
        """Test commit with no refs"""
        lines = [
            "abc123|~|abc|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|No refs|~|No refs\n|~||~|\n"
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        assert commit['refs'] is None

    def test_real_world_commit_format(self):
        """Test with a more realistic commit structure"""
        lines = [
            "e1bb93c05d8699243d43c9148a00804ae79cffff|~|e1bb93c|~|Elifarley C|~|elifarley@gmail.com|~|Elifarley C|~|elifarley@gmail.com|~|2025-11-18T19:19:14-03:00|~|12 minutes ago|~|feat: add comprehensive JSON output support for analysis commands (Phase 4a)|~|feat: add comprehensive JSON output support for analysis commands (Phase 4a)\n\nWHY: JSON output enables automation.\n\nWHAT: Added JSON support to 4 commands.\n\nIMPACT: Users can now pipe output to jq.|~|258d41a972c0e71100a1c64ca75de03bfc6943d1|~|HEAD -> main\n",
            "\n",
            "11\t3\tREADME.md\n",
            "47\t23\tdocs/planning/json-output-roadmap.md\n",
            "213\t0\ttests/unit/test_json_output.bats\n"
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        assert commit['hash'] == 'e1bb93c05d8699243d43c9148a00804ae79cffff'
        assert commit['hash_short'] == 'e1bb93c'
        assert commit['author']['name'] == 'Elifarley C'
        assert 'JSON output enables automation' in commit['message']['body']
        assert len(commit['parents']) == 1
        assert 'HEAD' in commit['refs']
        assert 'main' in commit['refs']
        assert commit['stats']['files_changed'] == 3
        assert commit['stats']['insertions'] == 271  # 11 + 47 + 213
        assert commit['stats']['deletions'] == 26     # 3 + 23 + 0


class TestEdgeCases:
    """Test edge cases and error handling"""

    def test_incomplete_commit_line(self):
        """Test handling of incomplete commit lines"""
        lines = [
            "abc123|~|abc|~|Alice\n",  # Incomplete - missing fields
            "def456|~|def|~|Bob|~|bob@example.com|~|Bob|~|bob@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|Valid commit|~|Valid commit\n|~||~|\n"
        ]

        commits = parse_log_with_stats(lines)

        # Should skip incomplete line and only parse valid commit
        assert len(commits) == 1
        assert commits[0]['hash'] == 'def456'

    def test_blank_lines_between_commits(self):
        """Test that blank lines are handled correctly"""
        lines = [
            "abc123|~|abc|~|Alice|~|alice@example.com|~|Alice|~|alice@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|First|~|First\n|~||~|\n",
            "\n",
            "\n",
            "def456|~|def|~|Bob|~|bob@example.com|~|Bob|~|bob@example.com|~|2025-11-18T11:00:00Z|~|1 hour ago|~|Second|~|Second\n|~||~|\n"
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 2

    def test_unicode_in_commit_message(self):
        """Test handling of Unicode characters"""
        lines = [
            "abc123|~|abc|~|José García|~|jose@example.com|~|José García|~|jose@example.com|~|2025-11-18T10:00:00Z|~|1 hour ago|~|Add emoji support 🎉|~|Add emoji support 🎉\n\nSupports UTF-8: ñ, é, 中文|~||~|\n"
        ]

        commits = parse_log_with_stats(lines)

        assert len(commits) == 1
        commit = commits[0]
        assert commit['author']['name'] == 'José García'
        assert '🎉' in commit['message']['subject']
        assert '中文' in commit['message']['body']
