#!/usr/bin/env python3
"""
Tests for json_transform.py module

Tests JSON transformation utilities including commit search,
git log transformation, and status transformation.
"""

import json
import os
import sys
from unittest.mock import patch

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from json_transform import (
    _status_to_type,
    commit_search,
    transform_git_log_to_json,
    transform_git_status_to_json,
    validate_json_schema,
)


class TestStatusToType:
    """Test status code to type conversion"""

    def test_modified(self):
        assert _status_to_type("M") == "modified"

    def test_added(self):
        assert _status_to_type("A") == "added"

    def test_deleted(self):
        assert _status_to_type("D") == "deleted"

    def test_renamed(self):
        assert _status_to_type("R") == "renamed"

    def test_unknown(self):
        assert _status_to_type("X") == "unknown"


class TestTransformGitLogToJson:
    """Test git log transformation"""

    def test_empty_log(self):
        result = transform_git_log_to_json("")
        data = json.loads(result)
        assert data == []

    def test_single_commit(self):
        log_output = (  # noqa: E501
            "abc123---HUG-FIELD-SEPARATOR---abc---HUG-FIELD-SEPARATOR---John Doe---HUG-FIELD-SEPARATOR---john@example.com---HUG-FIELD-SEPARATOR---2025-01-01 12:00:00 +0000---HUG-FIELD-SEPARATOR---Test commit"  # noqa: E501
        )
        result = transform_git_log_to_json(log_output)
        data = json.loads(result)

        assert len(data) == 1
        assert data[0]["sha"] == "abc123"
        assert data[0]["sha_short"] == "abc"
        assert data[0]["author"]["name"] == "John Doe"
        assert data[0]["author"]["email"] == "john@example.com"
        assert data[0]["date"] == "2025-01-01 12:00:00 +0000"
        assert data[0]["message"] == "Test commit"

    def test_multiple_commits(self):
        log_output = (  # noqa: E501
            "abc123---HUG-FIELD-SEPARATOR---abc---HUG-FIELD-SEPARATOR---John Doe---HUG-FIELD-SEPARATOR---john@example.com---HUG-FIELD-SEPARATOR---2025-01-01 12:00:00 +0000---HUG-FIELD-SEPARATOR---First commit\x00"  # noqa: E501
            "def456---HUG-FIELD-SEPARATOR---def---HUG-FIELD-SEPARATOR---Jane Smith---HUG-FIELD-SEPARATOR---jane@example.com---HUG-FIELD-SEPARATOR---2025-01-02 12:00:00 +0000---HUG-FIELD-SEPARATOR---Second commit"  # noqa: E501
        )
        result = transform_git_log_to_json(log_output)
        data = json.loads(result)

        assert len(data) == 2
        assert data[0]["sha"] == "abc123"
        assert data[1]["sha"] == "def456"

    def test_commit_with_special_characters(self):
        log_output = 'abc123---HUG-FIELD-SEPARATOR---abc---HUG-FIELD-SEPARATOR---John "Doe"---HUG-FIELD-SEPARATOR---john@example.com---HUG-FIELD-SEPARATOR---2025-01-01 12:00:00 +0000---HUG-FIELD-SEPARATOR---Test "quoted" commit'  # noqa: E501
        result = transform_git_log_to_json(log_output)
        data = json.loads(result)

        assert len(data) == 1
        assert data[0]["author"]["name"] == 'John "Doe"'
        assert data[0]["message"] == 'Test "quoted" commit'


class TestTransformGitStatusToJson:
    """Test git status transformation"""

    def test_empty_status(self):
        result = transform_git_status_to_json("")
        assert result["staged"] == []
        assert result["unstaged"] == []
        assert result["untracked"] == []
        assert result["summary"]["clean"] is True

    def test_unstaged_modified_file(self):
        # Git status format: XY filename where X=staged, Y=unstaged
        # ' M' means not staged, modified in working tree
        status_output = " M file.txt"
        result = transform_git_status_to_json(status_output)

        # With ' M', first char is space (not staged), second is M (unstaged modified)
        assert len(result["staged"]) == 0
        assert len(result["unstaged"]) == 1
        assert result["unstaged"][0]["path"] == "file.txt"
        assert result["unstaged"][0]["status"] == "modified"
        assert result["summary"]["clean"] is False

    def test_staged_file(self):
        status_output = "M  file.txt"
        result = transform_git_status_to_json(status_output)

        assert len(result["staged"]) == 1
        assert result["staged"][0]["path"] == "file.txt"
        assert result["staged"][0]["status"] == "modified"

    def test_untracked_file(self):
        status_output = "?? new_file.txt"
        result = transform_git_status_to_json(status_output)

        assert len(result["untracked"]) == 1
        assert result["untracked"][0]["path"] == "new_file.txt"
        assert result["untracked"][0]["status"] == "untracked"

    def test_multiple_files(self):
        status_output = "M  staged.txt\n M unstaged.txt\n?? untracked.txt"
        result = transform_git_status_to_json(status_output)

        assert len(result["staged"]) == 1
        assert len(result["unstaged"]) == 1
        assert len(result["untracked"]) == 1


class TestValidateJsonSchema:
    """Test JSON schema validation"""

    def test_valid_status_schema(self):
        json_data = '{"repository": "/path", "status": {}}'
        assert validate_json_schema(json_data, "status") is True

    def test_valid_commit_search_schema(self):
        json_data = '{"repository": "/path", "search": {}, "results": []}'
        assert validate_json_schema(json_data, "commit_search") is True

    def test_valid_branch_list_schema(self):
        json_data = '{"repository": "/path", "branches": []}'
        assert validate_json_schema(json_data, "branch_list") is True

    def test_invalid_json(self):
        json_data = "{invalid json}"
        assert validate_json_schema(json_data, "status") is False

    def test_missing_required_field(self):
        json_data = '{"repository": "/path"}'
        assert validate_json_schema(json_data, "status") is False


class TestCommitSearch:
    """Test commit search functionality using Command Mock Framework"""

    def test_message_search_success(self, command_mock):
        """Test message search with successful results."""
        mock_fn = command_mock.get_subprocess_mock("log/search.toml", "message_match")
        with patch("json_transform.subprocess.run", side_effect=mock_fn):
            result = commit_search("message", "fix", False, False, [])

            assert "results" in result
            assert len(result["results"]) == 3
            assert result["search"]["type"] == "message"
            assert result["search"]["term"] == "fix"

    def test_code_search_success(self, command_mock):
        """Test code search with successful results."""
        mock_fn = command_mock.get_subprocess_mock("log/search.toml", "code_match")
        with patch("json_transform.subprocess.run", side_effect=mock_fn):
            result = commit_search("code", "function_name", False, [])

            assert result["search"]["type"] == "code"
            assert result["search"]["term"] == "function_name"

    def test_with_files(self, command_mock):
        """Test search with files included."""
        mock_fn = command_mock.get_subprocess_mock("log/search.toml", "with_files")
        with patch("json_transform.subprocess.run", side_effect=mock_fn):
            result = commit_search("message", "feature", True, False, [])

            assert len(result["results"]) == 2
            assert "files" in result["results"][0]
            assert len(result["results"][0]["files"]) == 3

    def test_no_match(self, command_mock):
        """Test search with no matching results."""
        mock_fn = command_mock.get_subprocess_mock("log/search.toml", "no_match")
        with patch("json_transform.subprocess.run", side_effect=mock_fn):
            result = commit_search("message", "nonexistent", False, False, [])

            assert "results" in result
            assert len(result["results"]) == 0

    def test_git_error(self, command_mock):
        """Test handling of git command errors."""
        mock_fn = command_mock.get_subprocess_mock("log/search.toml", "git_error")
        with patch("json_transform.subprocess.run", side_effect=mock_fn):
            result = commit_search("message", "test", False, False, [])

            assert "error" in result
            assert result["error"]["type"] == "git_error"

    def test_invalid_search_type(self):
        """Test handling of invalid search type."""
        result = commit_search("invalid", "test", False, [])

        assert "error" in result
        assert result["error"]["type"] == "invalid_search_type"


class TestIntegration:
    """Integration tests that test the full workflow"""

    def test_json_output_is_valid(self):
        """Test that all output is valid JSON"""
        log_output = "abc123\x00abc\x00John Doe\x00john@example.com\x002025-01-01 12:00:00 +0000\x00Test commit\x00"  # noqa: E501
        result = transform_git_log_to_json(log_output)

        # Should not raise
        data = json.loads(result)
        assert isinstance(data, list)

    def test_unicode_handling(self):
        """Test that Unicode characters are handled correctly"""
        log_output = "abc123---HUG-FIELD-SEPARATOR---abc---HUG-FIELD-SEPARATOR---Café---HUG-FIELD-SEPARATOR---test@example.com---HUG-FIELD-SEPARATOR---2025-01-01 12:00:00 +0000---HUG-FIELD-SEPARATOR---Test café résumé"  # noqa: E501
        result = transform_git_log_to_json(log_output)
        data = json.loads(result)

        assert "Café" in data[0]["author"]["name"]
        assert "café" in data[0]["message"]
        assert "résumé" in data[0]["message"]
