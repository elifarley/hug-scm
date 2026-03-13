# Tag Selection Python Migration — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Migrate tag discovery, modeling, filtering, formatting, and selection logic from Bash (`hug-git-tag`) to a Python module (`tag_select.py`), eliminating parallel-array bugs at the source.

**Architecture:** Two-mode Python CLI (`prepare` for gum path, `select` for numbered-list path) called via `eval "$(python3 ...)"`. Python calls git directly. Bash adapter is ~30 lines. Callers (`git-t`, `git-tdel`) unchanged.

**Tech Stack:** Python 3 (dataclasses, subprocess, argparse), Bash, BATS, pytest

**Design doc:** `docs/plans/2026-03-13-tag-selection-python-migration-design.md`

---

### Task 0: Baseline — verify all tests pass

**Files:**
- None modified

**Step 1: Run existing BATS tests**

Run: `make test-bash TEST_FILTER="tag"`
Expected: All tag-related tests pass

**Step 2: Run existing pytest tests**

Run: `make test-lib-py`
Expected: All Python tests pass

---

### Task 1: Data model and bash escape — `TagInfo`, `TagFilterOptions`, `TagSelectionResult`

**Files:**
- Create: `git-config/lib/python/git/tag_select.py`
- Create: `git-config/lib/python/tests/test_tag_select.py`

**Step 1: Write failing tests for data model**

```python
"""Unit tests for tag_select.py - Tag selection with type safety.

Following Google Python testing best practices:
- Arrange-Act-Assert pattern
- Descriptive test names
- Test edge cases and error conditions
- Mock subprocess calls to avoid external dependencies
"""

import pytest

from git.tag_select import (
    TagFilterOptions,
    TagInfo,
    TagSelectionResult,
    _bash_escape,
)

################################################################################
# Test Fixtures
################################################################################


@pytest.fixture
def sample_tags():
    """A small set of TagInfo records for pure-logic tests."""
    return [
        TagInfo(
            name="v2.0.0",
            hash="abc1234",
            tag_type="annotated",
            subject="Release 2.0",
            date="2026-03-10 12:00:00 +0000",
            signature="",
            is_current=True,
        ),
        TagInfo(
            name="v1.1.0",
            hash="def5678",
            tag_type="lightweight",
            subject="Quick patch",
            date="",
            signature="",
            is_current=False,
        ),
        TagInfo(
            name="v1.0.0",
            hash="789abcd",
            tag_type="signed",
            subject="First stable release",
            date="2026-01-01 10:00:00 +0000",
            signature="verified",
            is_current=False,
        ),
    ]


################################################################################
# TagInfo construction
################################################################################


class TestTagInfo:
    def test_basic_construction(self):
        tag = TagInfo(
            name="v1.0.0",
            hash="abc1234",
            tag_type="lightweight",
            subject="Initial",
            date="",
            signature="",
            is_current=False,
        )
        assert tag.name == "v1.0.0"
        assert tag.hash == "abc1234"
        assert tag.tag_type == "lightweight"
        assert tag.is_current is False

    def test_annotated_tag_with_date(self):
        tag = TagInfo(
            name="v2.0.0",
            hash="def5678",
            tag_type="annotated",
            subject="Release",
            date="2026-03-10 12:00:00 +0000",
            signature="",
            is_current=True,
        )
        assert tag.date == "2026-03-10 12:00:00 +0000"
        assert tag.is_current is True

    def test_signed_tag_with_signature(self):
        tag = TagInfo(
            name="v3.0.0",
            hash="ghi9012",
            tag_type="signed",
            subject="Signed release",
            date="2026-03-11 09:00:00 +0000",
            signature="verified",
            is_current=False,
        )
        assert tag.signature == "verified"
        assert tag.tag_type == "signed"


################################################################################
# TagSelectionResult
################################################################################


class TestTagSelectionResult:
    def test_selected_status(self):
        result = TagSelectionResult(
            status="selected", tags=["v1.0.0", "v2.0.0"], indices=[0, 1]
        )
        assert result.status == "selected"
        assert len(result.tags) == 2

    def test_cancelled_status(self):
        result = TagSelectionResult(status="cancelled", tags=[], indices=[])
        assert result.status == "cancelled"
        assert result.tags == []

    def test_no_tags_status(self):
        result = TagSelectionResult(status="no_tags", tags=[], indices=[])
        assert result.status == "no_tags"

    def test_no_matches_status(self):
        result = TagSelectionResult(status="no_matches", tags=[], indices=[])
        assert result.status == "no_matches"


################################################################################
# _bash_escape
################################################################################


class TestBashEscape:
    def test_simple_string(self):
        assert _bash_escape("hello") == "'hello'"

    def test_string_with_single_quote(self):
        assert _bash_escape("it's") == "'it'\\''s'"

    def test_string_with_backslash(self):
        assert _bash_escape("path\\to") == "'path\\\\to'"

    def test_empty_string(self):
        assert _bash_escape("") == "''"

    def test_string_with_spaces(self):
        assert _bash_escape("hello world") == "'hello world'"
```

**Step 2: Write minimal module to make tests pass**

```python
#!/usr/bin/env python3
"""
Hug Git Tag Select Library - Python implementation

Provides type-safe tag discovery, filtering, formatting, and selection to
replace the parallel-array approach in the Bash hug-git-tag library.

Python calls git directly (like worktree.py), eliminating the 8-nameref
compute_tag_details() bottleneck at its source.

Supports:
- Tag discovery via git subprocess calls
- Structured tag records (TagInfo dataclass)
- Type and pattern filtering
- Formatted display rows for gum and numbered-list selection
- Bash declare output for eval consumption
- Two CLI modes: prepare (gum path) and select (numbered-list path)
"""

import re
import sys
from dataclasses import dataclass


@dataclass
class TagInfo:
    """Single tag record — replaces 8 parallel Bash arrays.

    Attributes:
        name: Tag name (e.g., "v1.0.0")
        hash: Short (7-char) commit hash the tag points to
        tag_type: One of "lightweight", "annotated", "signed"
        subject: Commit or tag message subject line
        date: Tagger date for annotated/signed tags, empty string for lightweight
        signature: "verified" for verified signed tags, empty string otherwise
        is_current: True if HEAD is on this exact tag
    """

    name: str
    hash: str
    tag_type: str
    subject: str
    date: str
    signature: str
    is_current: bool


@dataclass
class TagFilterOptions:
    """Filtering criteria for tag selection.

    Attributes:
        type_filter: Filter by tag type ("lightweight", "annotated", "signed"), or None
        pattern: Regex pattern to match against tag names, or None
    """

    type_filter: str | None = None
    pattern: str | None = None


@dataclass
class TagSelectionResult:
    """Explicit outcome of a tag selection operation.

    Unlike the Bash implementation which overloaded exit codes and array emptiness,
    this provides unambiguous status for every outcome.

    Attributes:
        status: One of "selected", "cancelled", "no_tags", "no_matches", "error"
        tags: Selected tag names (non-empty only when status == "selected")
        indices: 0-based indices into the filtered tag list
    """

    status: str
    tags: list[str]
    indices: list[int]


def _bash_escape(s: str) -> str:
    """Escape string for safe bash declare usage.

    Uses single quotes with inner quote escaping for maximum compatibility.
    Handles: backslashes, single quotes, and most special characters.

    Strategy: '...' with '\\'' for embedded single quotes.

    Args:
        s: String to escape

    Returns:
        Escaped string wrapped in single quotes
    """
    s = s.replace("\\", "\\\\")  # Backslashes first (order matters)
    s = s.replace("'", "'\\''")  # Single quotes
    return f"'{s}'"
```

**Step 3: Run tests to verify they pass**

Run: `make test-lib-py TEST_FILTER="test_tag_select"`
Expected: All tests PASS

**Step 4: Commit**

```
feat(tag-select): add data model and bash escape for tag selection Python module

WHY: First building block of the tag selection migration. The dataclasses
(TagInfo, TagFilterOptions, TagSelectionResult) replace 8 parallel Bash
arrays with typed records, making contracts explicit and testable.
```

---

### Task 2: `filter_tags()` — pure filtering logic

**Files:**
- Modify: `git-config/lib/python/git/tag_select.py`
- Modify: `git-config/lib/python/tests/test_tag_select.py`

**Step 1: Write failing tests for filter_tags**

```python
from git.tag_select import filter_tags

class TestFilterTags:
    def test_no_filters_returns_all(self, sample_tags):
        options = TagFilterOptions()
        result = filter_tags(sample_tags, options)
        assert len(result) == 3

    def test_type_filter_annotated(self, sample_tags):
        options = TagFilterOptions(type_filter="annotated")
        result = filter_tags(sample_tags, options)
        assert len(result) == 1
        assert result[0].name == "v2.0.0"

    def test_type_filter_lightweight(self, sample_tags):
        options = TagFilterOptions(type_filter="lightweight")
        result = filter_tags(sample_tags, options)
        assert len(result) == 1
        assert result[0].name == "v1.1.0"

    def test_type_filter_signed(self, sample_tags):
        options = TagFilterOptions(type_filter="signed")
        result = filter_tags(sample_tags, options)
        assert len(result) == 1
        assert result[0].name == "v1.0.0"

    def test_pattern_filter(self, sample_tags):
        options = TagFilterOptions(pattern=r"v1\.")
        result = filter_tags(sample_tags, options)
        assert len(result) == 2
        assert {t.name for t in result} == {"v1.1.0", "v1.0.0"}

    def test_combined_filters(self, sample_tags):
        options = TagFilterOptions(type_filter="lightweight", pattern=r"v1\.")
        result = filter_tags(sample_tags, options)
        assert len(result) == 1
        assert result[0].name == "v1.1.0"

    def test_no_matches(self, sample_tags):
        options = TagFilterOptions(pattern=r"v99\.")
        result = filter_tags(sample_tags, options)
        assert len(result) == 0

    def test_empty_input(self):
        options = TagFilterOptions()
        result = filter_tags([], options)
        assert result == []

    def test_invalid_regex_treated_as_literal(self, sample_tags):
        # A pattern with invalid regex should be treated as literal
        options = TagFilterOptions(pattern="[invalid")
        result = filter_tags(sample_tags, options)
        assert len(result) == 0
```

**Step 2: Run tests to verify they fail**

Run: `make test-lib-py TEST_FILTER="TestFilterTags"`
Expected: FAIL (function not defined)

**Step 3: Implement filter_tags**

```python
def filter_tags(tags: list[TagInfo], options: TagFilterOptions) -> list[TagInfo]:
    """Apply type and pattern filters to a list of tags.

    Pure function — no side effects, no git calls. Easy to test.

    Args:
        tags: List of TagInfo records to filter
        options: Filtering criteria (type and/or name pattern)

    Returns:
        Filtered list of TagInfo records (may be empty)
    """
    result = tags

    if options.type_filter:
        result = [t for t in result if t.tag_type == options.type_filter]

    if options.pattern:
        try:
            compiled = re.compile(options.pattern)
            result = [t for t in result if compiled.search(t.name)]
        except re.error:
            # Invalid regex: treat as literal substring match
            result = [t for t in result if options.pattern in t.name]

    return result
```

**Step 4: Run tests to verify they pass**

Run: `make test-lib-py TEST_FILTER="TestFilterTags"`
Expected: All PASS

**Step 5: Commit**

```
feat(tag-select): add filter_tags() pure filtering logic
```

---

### Task 3: `format_display_rows()` — display row construction

**Files:**
- Modify: `git-config/lib/python/git/tag_select.py`
- Modify: `git-config/lib/python/tests/test_tag_select.py`

**Step 1: Write failing tests**

```python
from git.tag_select import format_display_rows

class TestFormatDisplayRows:
    def test_basic_formatting(self, sample_tags):
        rows = format_display_rows(sample_tags)
        assert len(rows) == 3

    def test_current_tag_has_star_prefix(self, sample_tags):
        rows = format_display_rows(sample_tags)
        # v2.0.0 is_current=True
        assert rows[0].startswith("* v2.0.0")

    def test_non_current_tag_no_star(self, sample_tags):
        rows = format_display_rows(sample_tags)
        # v1.1.0 is_current=False
        assert not rows[1].startswith("*")
        assert "v1.1.0" in rows[1]

    def test_type_indicator_lightweight(self, sample_tags):
        rows = format_display_rows(sample_tags)
        assert "[L]" in rows[1]  # v1.1.0 is lightweight

    def test_type_indicator_annotated(self, sample_tags):
        rows = format_display_rows(sample_tags)
        assert "[A]" in rows[0]  # v2.0.0 is annotated

    def test_type_indicator_signed(self, sample_tags):
        rows = format_display_rows(sample_tags)
        assert "[S]" in rows[2]  # v1.0.0 is signed

    def test_hash_included(self, sample_tags):
        rows = format_display_rows(sample_tags)
        assert "abc1234" in rows[0]

    def test_subject_included(self, sample_tags):
        rows = format_display_rows(sample_tags)
        assert "Release 2.0" in rows[0]

    def test_empty_list(self):
        rows = format_display_rows([])
        assert rows == []
```

**Step 2: Run tests to verify they fail**

Run: `make test-lib-py TEST_FILTER="TestFormatDisplayRows"`
Expected: FAIL

**Step 3: Implement format_display_rows**

```python
# Type indicator mapping — matches the Bash _build_tag_select_options() output
_TYPE_INDICATORS = {
    "lightweight": "[L]",
    "annotated": "[A]",
    "signed": "[S]",
}


def format_display_rows(tags: list[TagInfo]) -> list[str]:
    """Build formatted selection rows for interactive display.

    Produces the same format as the Bash _build_tag_select_options() so that
    gum filter and numbered-list display look identical before and after migration.

    Format: "[* ]tagname [L|A|S] hash subject"

    Args:
        tags: List of TagInfo records to format

    Returns:
        List of formatted display strings (one per tag)
    """
    rows = []
    for tag in tags:
        parts = []

        # Current tag marker
        if tag.is_current:
            parts.append(f"* {tag.name}")
        else:
            parts.append(tag.name)

        # Type indicator
        indicator = _TYPE_INDICATORS.get(tag.tag_type, "")
        if indicator:
            parts.append(indicator)

        # Hash and subject
        parts.append(tag.hash)
        parts.append(tag.subject)

        rows.append(" ".join(parts))

    return rows
```

**Step 4: Run tests to verify they pass**

Run: `make test-lib-py TEST_FILTER="TestFormatDisplayRows"`
Expected: All PASS

**Step 5: Commit**

```
feat(tag-select): add format_display_rows() for selection display
```

---

### Task 4: `parse_numbered_input()` — user input parsing

**Files:**
- Modify: `git-config/lib/python/git/tag_select.py`
- Modify: `git-config/lib/python/tests/test_tag_select.py`

**Step 1: Write failing tests**

```python
from git.tag_select import parse_numbered_input

class TestParseNumberedInput:
    def test_single_number(self):
        assert parse_numbered_input("3", 10) == [2]  # 1-based to 0-based

    def test_comma_separated(self):
        assert parse_numbered_input("1,3,5", 10) == [0, 2, 4]

    def test_range(self):
        assert parse_numbered_input("2-4", 10) == [1, 2, 3]

    def test_mixed(self):
        assert parse_numbered_input("1,3-5,7", 10) == [0, 2, 3, 4, 6]

    def test_all_keyword(self):
        assert parse_numbered_input("all", 3) == [0, 1, 2]

    def test_a_keyword(self):
        assert parse_numbered_input("a", 3) == [0, 1, 2]

    def test_ALL_uppercase(self):
        assert parse_numbered_input("ALL", 3) == [0, 1, 2]

    def test_empty_string(self):
        assert parse_numbered_input("", 10) == []

    def test_whitespace_only(self):
        assert parse_numbered_input("  ", 10) == []

    def test_out_of_bounds_ignored(self):
        assert parse_numbered_input("0,1,99", 5) == [0]  # 0 is invalid (1-based), 99 too high

    def test_invalid_text_ignored(self):
        assert parse_numbered_input("abc,2", 10) == [1]

    def test_duplicates_removed(self):
        assert parse_numbered_input("1,1,1", 10) == [0]

    def test_sorted_output(self):
        assert parse_numbered_input("5,1,3", 10) == [0, 2, 4]

    def test_spaces_around_numbers(self):
        assert parse_numbered_input(" 1 , 3 ", 10) == [0, 2]
```

**Step 2: Run tests to verify they fail**

Run: `make test-lib-py TEST_FILTER="TestParseNumberedInput"`
Expected: FAIL

**Step 3: Implement parse_numbered_input**

```python
def parse_numbered_input(user_input: str, num_items: int) -> list[int]:
    """Parse user selection input into 0-based indices.

    Supports the same input formats as branch_select.py:
    - 'a' or 'all' (case-insensitive) -> select all items
    - Comma-separated 1-based numbers: "1,2,3"
    - Inclusive ranges: "2-4"
    - Mixed: "1,3-5,7"
    - Empty string -> no selection

    Args:
        user_input: Raw input string from the user
        num_items: Total number of items available for selection

    Returns:
        Sorted list of unique 0-based indices within bounds
    """
    user_input = user_input.strip()

    if not user_input:
        return []

    if user_input.lower() in ("a", "all"):
        return list(range(num_items))

    indices: set[int] = set()

    for part in user_input.split(","):
        part = part.strip()

        if "-" in part:
            try:
                start_str, end_str = part.split("-", 1)
                start = int(start_str.strip())
                end = int(end_str.strip())
                # Convert 1-based to 0-based, clamp to bounds
                start_idx = max(0, start - 1)
                end_idx = min(num_items - 1, end - 1)
                for i in range(start_idx, end_idx + 1):
                    indices.add(i)
            except ValueError:
                continue
        else:
            try:
                num = int(part)
                idx = num - 1  # 1-based to 0-based
                if 0 <= idx < num_items:
                    indices.add(idx)
            except ValueError:
                continue

    return sorted(indices)
```

**Step 4: Run tests to verify they pass**

Run: `make test-lib-py TEST_FILTER="TestParseNumberedInput"`
Expected: All PASS

**Step 5: Commit**

```
feat(tag-select): add parse_numbered_input() for user selection parsing
```

---

### Task 5: Bash declare output — `to_bash_declare()` and `tags_to_bash_declare()`

**Files:**
- Modify: `git-config/lib/python/git/tag_select.py`
- Modify: `git-config/lib/python/tests/test_tag_select.py`

**Step 1: Write failing tests**

```python
from git.tag_select import to_bash_declare, tags_to_bash_declare

class TestToBashDeclare:
    def test_selected_result(self):
        result = TagSelectionResult(
            status="selected", tags=["v1.0.0", "v2.0.0"], indices=[0, 1]
        )
        output = to_bash_declare(result)
        assert "declare -a selected_tags=(" in output
        assert "'v1.0.0'" in output
        assert "'v2.0.0'" in output
        assert "selection_status='selected'" in output

    def test_cancelled_result(self):
        result = TagSelectionResult(status="cancelled", tags=[], indices=[])
        output = to_bash_declare(result)
        assert "declare -a selected_tags=()" in output
        assert "selection_status='cancelled'" in output

    def test_custom_array_name(self):
        result = TagSelectionResult(
            status="selected", tags=["v1.0.0"], indices=[0]
        )
        output = to_bash_declare(result, array_name="my_tags")
        assert "declare -a my_tags=(" in output

    def test_tag_with_special_characters(self):
        result = TagSelectionResult(
            status="selected", tags=["release/v1.0's"], indices=[0]
        )
        output = to_bash_declare(result)
        # Should be properly escaped for bash eval
        assert "release/v1.0" in output

    def test_no_tags_result(self):
        result = TagSelectionResult(status="no_tags", tags=[], indices=[])
        output = to_bash_declare(result)
        assert "selection_status='no_tags'" in output


class TestTagsToBashDeclare:
    def test_prepare_output(self, sample_tags):
        formatted = ["* v2.0.0 [A] abc1234 Release 2.0",
                      "v1.1.0 [L] def5678 Quick patch",
                      "v1.0.0 [S] 789abcd First stable release"]
        output = tags_to_bash_declare(sample_tags, formatted)
        assert "declare -a filtered_tags=(" in output
        assert "declare -a formatted_options=(" in output
        assert "selection_status='ready'" in output
        assert "tag_count=3" in output

    def test_empty_tags(self):
        output = tags_to_bash_declare([], [])
        assert "selection_status='no_tags'" in output
        assert "tag_count=0" in output
```

**Step 2: Run tests to verify they fail**

Run: `make test-lib-py TEST_FILTER="TestToBashDeclare or TestTagsToBashDeclare"`
Expected: FAIL

**Step 3: Implement**

```python
def to_bash_declare(
    result: TagSelectionResult, array_name: str = "selected_tags"
) -> str:
    """Format a TagSelectionResult as bash declare statements for eval.

    Outputs:
    - declare -a <array_name>=('tag1' 'tag2' ...)
    - selection_status='selected'

    Args:
        result: The selection result to serialize
        array_name: Name for the bash array variable (default: "selected_tags")

    Returns:
        Bash declare statements as a string, one per line
    """
    lines = []
    tags_arr = " ".join(_bash_escape(t) for t in result.tags)
    lines.append(f"declare -a {array_name}=({tags_arr})")
    lines.append(f"selection_status={_bash_escape(result.status)}")
    return "\n".join(lines)


def tags_to_bash_declare(tags: list[TagInfo], formatted: list[str]) -> str:
    """Format tag data for the prepare CLI command (gum path).

    Outputs bash declare statements that the Bash adapter evals to get
    filtered_tags[] and formatted_options[] for gum_filter_by_index.

    Args:
        tags: Filtered TagInfo records
        formatted: Formatted display rows (parallel to tags)

    Returns:
        Bash declare statements as a string
    """
    if not tags:
        return (
            "declare -a filtered_tags=()\n"
            "declare -a formatted_options=()\n"
            "selection_status='no_tags'\n"
            "tag_count=0"
        )

    lines = []
    tags_arr = " ".join(_bash_escape(t.name) for t in tags)
    lines.append(f"declare -a filtered_tags=({tags_arr})")

    opts_arr = " ".join(_bash_escape(f) for f in formatted)
    lines.append(f"declare -a formatted_options=({opts_arr})")

    lines.append("selection_status='ready'")
    lines.append(f"tag_count={len(tags)}")

    return "\n".join(lines)
```

**Step 4: Run tests to verify they pass**

Run: `make test-lib-py TEST_FILTER="TestToBashDeclare or TestTagsToBashDeclare"`
Expected: All PASS

**Step 5: Commit**

```
feat(tag-select): add bash declare output for Bash adapter consumption
```

---

### Task 6: `load_tags()` — git subprocess integration

**Files:**
- Modify: `git-config/lib/python/git/tag_select.py`
- Modify: `git-config/lib/python/tests/test_tag_select.py`

**Step 1: Write failing tests (mocked subprocess)**

```python
from unittest.mock import MagicMock, patch
from git.tag_select import load_tags

class TestLoadTags:
    @patch("git.tag_select._run_git")
    def test_empty_repo_no_tags(self, mock_run):
        mock_run.return_value = ""
        result = load_tags()
        assert result == []

    @patch("git.tag_select._run_git")
    def test_lightweight_tag(self, mock_run):
        def side_effect(args):
            cmd = args[0] if args else ""
            if args == ["tag", "--sort=-version:refname"]:
                return "v1.0.0"
            elif args[:2] == ["cat-file", "-t"]:
                return "commit"  # lightweight tag points to commit
            elif args[:2] == ["rev-parse", "--short"]:
                return "abc1234"
            elif args[:3] == ["log", "-n", "1"]:
                return "Initial commit"
            elif args[:2] == ["describe", "--tags"]:
                return ""
            return ""

        mock_run.side_effect = side_effect
        result = load_tags()
        assert len(result) == 1
        assert result[0].tag_type == "lightweight"
        assert result[0].name == "v1.0.0"
        assert result[0].hash == "abc1234"

    @patch("git.tag_select._run_git")
    def test_annotated_tag(self, mock_run):
        def side_effect(args):
            if args == ["tag", "--sort=-version:refname"]:
                return "v2.0.0"
            elif args[:2] == ["cat-file", "-t"]:
                return "tag"  # annotated
            elif args[:2] == ["tag", "-l"] and "--format=%(taggerdate:iso8601)" in " ".join(args):
                return "2026-03-10 12:00:00 +0000"
            elif args[:2] == ["tag", "-l"] and "--format=%(subject)" in " ".join(args):
                return "Release 2.0"
            elif args[:2] == ["rev-list", "-n"]:
                return "abc1234def5678901234567890123456789012345"
            elif args[:2] == ["verify-tag", "--quiet"]:
                raise RuntimeError("not signed")  # Not signed
            elif args[:2] == ["describe", "--tags"]:
                return ""
            return ""

        mock_run.side_effect = side_effect
        result = load_tags()
        assert len(result) == 1
        assert result[0].tag_type == "annotated"

    @patch("git.tag_select._run_git")
    def test_current_tag_detected(self, mock_run):
        def side_effect(args):
            if args == ["tag", "--sort=-version:refname"]:
                return "v1.0.0"
            elif args[:2] == ["describe", "--tags"]:
                return "v1.0.0"  # HEAD is on this tag
            elif args[:2] == ["cat-file", "-t"]:
                return "commit"
            elif args[:2] == ["rev-parse", "--short"]:
                return "abc1234"
            elif args[:3] == ["log", "-n", "1"]:
                return "Initial"
            return ""

        mock_run.side_effect = side_effect
        result = load_tags()
        assert result[0].is_current is True

    @patch("git.tag_select._run_git")
    def test_multiple_tags_preserve_sort_order(self, mock_run):
        def side_effect(args):
            if args == ["tag", "--sort=-version:refname"]:
                return "v2.0.0\nv1.1.0\nv1.0.0"
            elif args[:2] == ["cat-file", "-t"]:
                return "commit"
            elif args[:2] == ["rev-parse", "--short"]:
                return "abc1234"
            elif args[:3] == ["log", "-n", "1"]:
                return "Commit msg"
            elif args[:2] == ["describe", "--tags"]:
                return ""
            return ""

        mock_run.side_effect = side_effect
        result = load_tags()
        assert len(result) == 3
        assert [t.name for t in result] == ["v2.0.0", "v1.1.0", "v1.0.0"]
```

**Step 2: Run tests to verify they fail**

Run: `make test-lib-py TEST_FILTER="TestLoadTags"`
Expected: FAIL

**Step 3: Implement load_tags and _run_git helper**

```python
import subprocess


def _run_git(args: list[str], check: bool = False) -> str:
    """Run a git command and return stdout as stripped string.

    Args:
        args: Git arguments (without leading 'git')
        check: If True, raise on non-zero exit

    Returns:
        Stripped stdout string, or empty string on failure

    Raises:
        RuntimeError: If check=True and git returns non-zero exit
    """
    try:
        result = subprocess.run(
            ["git", "--no-pager"] + args,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if check and result.returncode != 0:
            raise RuntimeError(
                f"git {' '.join(args)} failed: {result.stderr.strip()}"
            )
        return result.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        if check:
            raise RuntimeError(f"git command failed: {e}") from e
        return ""


def load_tags() -> list[TagInfo]:
    """Discover all tags in the current git repository.

    Calls git directly to build TagInfo records. Replaces
    compute_tag_details() for the selection path.

    Tags are returned in version-descending order (newest first),
    matching the Bash implementation's git tag --sort=-version:refname.

    Returns:
        List of TagInfo records, empty if no tags exist
    """
    # Get current tag (if HEAD is on one)
    current_tag = _run_git(["describe", "--tags", "--exact-match"])

    # Get all tags sorted by version (newest first)
    tag_output = _run_git(["tag", "--sort=-version:refname"])
    if not tag_output:
        return []

    tag_names = [line.strip() for line in tag_output.splitlines() if line.strip()]
    tags: list[TagInfo] = []

    for name in tag_names:
        # Determine object type (commit = lightweight, tag = annotated/signed)
        object_type = _run_git(["cat-file", "-t", name]) or "commit"

        tag_type = "lightweight"
        date = ""
        subject = ""
        signature = ""
        hash_str = ""

        if object_type == "tag":
            # Annotated or signed tag
            tag_type = "annotated"

            # Get tagger date and subject
            date = _run_git(
                ["tag", "-l", f"--format=%(taggerdate:iso8601)", name]
            )
            subject = _run_git(
                ["tag", "-l", f"--format=%(subject)", name]
            )

            # Get the commit hash the tag points to
            full_hash = _run_git(["rev-list", "-n", "1", name])
            hash_str = full_hash[:7] if full_hash else ""

            # Check if signed
            try:
                _run_git(["verify-tag", "--quiet", name], check=True)
                tag_type = "signed"
                signature = "verified"
            except RuntimeError:
                pass  # Not signed or verification failed
        else:
            # Lightweight tag — get hash directly
            hash_str = _run_git(["rev-parse", "--short", name])

        # Get commit subject if not from annotated tag
        if not subject:
            subject = _run_git(
                ["log", "-n", "1", "--pretty=format:%s", hash_str or name]
            ) or "(no commit message)"

        # Sanitize newlines (defensive, matching Bash tr -d '\n\r')
        name = name.replace("\n", "").replace("\r", "")
        hash_str = hash_str.replace("\n", "").replace("\r", "")
        subject = subject.replace("\n", "").replace("\r", "")

        tags.append(
            TagInfo(
                name=name,
                hash=hash_str,
                tag_type=tag_type,
                subject=subject,
                date=date,
                signature=signature,
                is_current=(name == current_tag),
            )
        )

    return tags
```

**Step 4: Run tests to verify they pass**

Run: `make test-lib-py TEST_FILTER="TestLoadTags"`
Expected: All PASS

**Step 5: Commit**

```
feat(tag-select): add load_tags() with direct git subprocess calls

WHY: Python calling git directly eliminates the 8-nameref
compute_tag_details() bottleneck. Tag records are built as TagInfo
dataclasses, making the data contract explicit and type-safe.
```

---

### Task 7: CLI entry point — `prepare` and `select` commands

**Files:**
- Modify: `git-config/lib/python/git/tag_select.py`
- Modify: `git-config/lib/python/tests/test_tag_select.py`

**Step 1: Write failing tests for CLI**

```python
import subprocess as sp
import os

class TestCLIPrepare:
    @patch("git.tag_select.load_tags")
    def test_prepare_outputs_bash_declares(self, mock_load, sample_tags):
        mock_load.return_value = sample_tags
        # Test the internal prepare function
        from git.tag_select import _cmd_prepare
        output = _cmd_prepare(type_filter=None, pattern=None)
        assert "declare -a filtered_tags=" in output
        assert "declare -a formatted_options=" in output
        assert "selection_status='ready'" in output

    @patch("git.tag_select.load_tags")
    def test_prepare_with_type_filter(self, mock_load, sample_tags):
        mock_load.return_value = sample_tags
        from git.tag_select import _cmd_prepare
        output = _cmd_prepare(type_filter="annotated", pattern=None)
        assert "'v2.0.0'" in output
        assert "'v1.1.0'" not in output

    @patch("git.tag_select.load_tags")
    def test_prepare_no_tags(self, mock_load):
        mock_load.return_value = []
        from git.tag_select import _cmd_prepare
        output = _cmd_prepare(type_filter=None, pattern=None)
        assert "selection_status='no_tags'" in output

    @patch("git.tag_select.load_tags")
    def test_prepare_no_matches(self, mock_load, sample_tags):
        mock_load.return_value = sample_tags
        from git.tag_select import _cmd_prepare
        output = _cmd_prepare(type_filter=None, pattern="v99")
        assert "selection_status='no_matches'" in output


class TestCLISelect:
    @patch("git.tag_select.load_tags")
    @patch("builtins.input", return_value="1")
    def test_select_single(self, mock_input, mock_load, sample_tags):
        mock_load.return_value = sample_tags
        from git.tag_select import _cmd_select
        output = _cmd_select(
            type_filter=None, pattern=None, multi=False, prompt="Pick"
        )
        assert "selection_status='selected'" in output
        assert "'v2.0.0'" in output

    @patch("git.tag_select.load_tags")
    @patch("builtins.input", return_value="1,3")
    def test_select_multi(self, mock_input, mock_load, sample_tags):
        mock_load.return_value = sample_tags
        from git.tag_select import _cmd_select
        output = _cmd_select(
            type_filter=None, pattern=None, multi=True, prompt="Pick"
        )
        assert "selection_status='selected'" in output
        assert "'v2.0.0'" in output
        assert "'v1.0.0'" in output

    @patch("git.tag_select.load_tags")
    @patch("builtins.input", return_value="")
    def test_select_empty_input_cancels(self, mock_input, mock_load, sample_tags):
        mock_load.return_value = sample_tags
        from git.tag_select import _cmd_select
        output = _cmd_select(
            type_filter=None, pattern=None, multi=True, prompt="Pick"
        )
        assert "selection_status='cancelled'" in output

    @patch("git.tag_select.load_tags")
    def test_select_no_tags(self, mock_load):
        mock_load.return_value = []
        from git.tag_select import _cmd_select
        output = _cmd_select(
            type_filter=None, pattern=None, multi=False, prompt="Pick"
        )
        assert "selection_status='no_tags'" in output
```

**Step 2: Run tests to verify they fail**

Run: `make test-lib-py TEST_FILTER="TestCLI"`
Expected: FAIL

**Step 3: Implement CLI functions and argparse main**

```python
import argparse


def _cmd_prepare(type_filter: str | None, pattern: str | None) -> str:
    """Execute the 'prepare' CLI command (gum path).

    Loads tags, filters, formats display rows, returns bash declares.

    Args:
        type_filter: Optional tag type filter
        pattern: Optional name pattern filter

    Returns:
        Bash declare statements as string
    """
    tags = load_tags()
    if not tags:
        return tags_to_bash_declare([], [])

    filtered = filter_tags(tags, TagFilterOptions(type_filter=type_filter, pattern=pattern))
    if not filtered:
        return (
            "declare -a filtered_tags=()\n"
            "declare -a formatted_options=()\n"
            "selection_status='no_matches'\n"
            "tag_count=0"
        )

    formatted = format_display_rows(filtered)
    return tags_to_bash_declare(filtered, formatted)


def _cmd_select(
    type_filter: str | None,
    pattern: str | None,
    multi: bool,
    prompt: str,
) -> str:
    """Execute the 'select' CLI command (numbered-list path).

    Loads tags, filters, displays numbered list, reads user input,
    returns bash declares with selection result.

    Args:
        type_filter: Optional tag type filter
        pattern: Optional name pattern filter
        multi: If True, allow multiple selections
        prompt: Prompt text to display

    Returns:
        Bash declare statements as string
    """
    tags = load_tags()
    if not tags:
        return to_bash_declare(
            TagSelectionResult(status="no_tags", tags=[], indices=[])
        )

    filtered = filter_tags(tags, TagFilterOptions(type_filter=type_filter, pattern=pattern))
    if not filtered:
        return to_bash_declare(
            TagSelectionResult(status="no_matches", tags=[], indices=[])
        )

    formatted = format_display_rows(filtered)

    # Display numbered list
    print(f"{prompt}:\n", file=sys.stderr)
    for i, row in enumerate(formatted):
        print(f"  {i + 1:2d}) {row}", file=sys.stderr)
    print(file=sys.stderr)

    # Read user input
    try:
        if multi:
            user_input = input(
                "Enter numbers to select (comma-separated, or 'a' for all): "
            )
        else:
            user_input = input("Enter number: ")
    except EOFError:
        user_input = ""

    if not user_input.strip():
        return to_bash_declare(
            TagSelectionResult(status="cancelled", tags=[], indices=[])
        )

    indices = parse_numbered_input(user_input, len(filtered))
    if not indices:
        return to_bash_declare(
            TagSelectionResult(status="cancelled", tags=[], indices=[])
        )

    if not multi:
        # Single select: take only first
        indices = indices[:1]

    selected = [filtered[i].name for i in indices]
    return to_bash_declare(
        TagSelectionResult(status="selected", tags=selected, indices=indices)
    )


def main():
    """CLI entry point for bash wrapper calls.

    Usage:
        python3 tag_select.py prepare [--type TYPE] [--pattern PATTERN]
        python3 tag_select.py select [--type TYPE] [--pattern PATTERN] [--multi] [--prompt TEXT]
    """
    parser = argparse.ArgumentParser(description="Tag selection for Hug SCM")
    parser.add_argument(
        "command",
        choices=["prepare", "select"],
        help="Command to run: prepare (gum path) or select (numbered list)",
    )
    parser.add_argument("--type", dest="type_filter", default=None, help="Filter by tag type")
    parser.add_argument("--pattern", default=None, help="Filter by name regex pattern")
    parser.add_argument("--multi", action="store_true", help="Allow multiple selections")
    parser.add_argument("--prompt", default="Select a tag", help="Prompt text")

    args = parser.parse_args()

    try:
        if args.command == "prepare":
            output = _cmd_prepare(
                type_filter=args.type_filter, pattern=args.pattern
            )
        else:
            output = _cmd_select(
                type_filter=args.type_filter,
                pattern=args.pattern,
                multi=args.multi,
                prompt=args.prompt,
            )
        print(output)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
```

**Step 4: Run tests to verify they pass**

Run: `make test-lib-py TEST_FILTER="TestCLI"`
Expected: All PASS

**Step 5: Run full pytest suite**

Run: `make test-lib-py`
Expected: All tests PASS (existing + new)

**Step 6: Commit**

```
feat(tag-select): add CLI entry point with prepare and select commands

WHY: The CLI is the contract surface between Python and Bash. Two modes:
- prepare: returns filtered_tags + formatted_options for gum path
- select: handles full numbered-list interaction for non-gum path
Both output bash declare statements consumed via eval.
```

---

### Task 8: Bash adapter — refactor `select_tags()` in hug-git-tag

**Files:**
- Modify: `git-config/lib/hug-git-tag` (lines 554-799)

**Step 1: Run existing BATS tests to confirm green baseline**

Run: `make test-bash TEST_FILTER="tag"`
Expected: All tag-related tests pass

**Step 2: Replace select_tags() with Python-backed adapter**

Replace lines 554-799 of `git-config/lib/hug-git-tag` (from `# Selection Functions` through `select_tags() { ... }`) with the thin adapter. Keep `_map_selected_tag_indices()` (gum path needs it). Remove `_build_tag_select_options()` (Python replaces it).

New `select_tags()`:

```bash
################################################################################
# Selection Functions
################################################################################

# Maps 0-based selection indices back to tag names with bounds checking.
# Usage: _map_selected_tag_indices selected_tags selected_indices tags
# Returns:
#   0 if at least one valid tag was selected
#   1 if no indices were provided
#   2 if all indices were invalid
# WHY: Still needed for the gum path where Bash handles gum_filter_by_index
# and must map the returned indices to tag names.
_map_selected_tag_indices() {
    local -n selected_ref="$1"
    local -n indices_ref="$2"
    local -n tags_ref="$3"

    selected_ref=()

    if [[ ${#indices_ref[@]} -eq 0 ]]; then
        return 1
    fi

    local idx
    for idx in "${indices_ref[@]}"; do
        if [[ ! "$idx" =~ ^[0-9]+$ ]] || [[ "$idx" -lt 0 ]] || [[ "$idx" -ge ${#tags_ref[@]} ]]; then
            warn "Skipped invalid tag selection index: $idx"
            continue
        fi

        selected_ref+=("${tags_ref[idx]}")
    done

    if [[ ${#selected_ref[@]} -eq 0 ]]; then
        return 2
    fi

    return 0
}

# Universal tag selection function — Python-backed adapter
# Usage: select_tags selected_tags [options]
# Parameters:
#   $1 - Nameref to array to receive selected tags
# Options:
#   --multi-select    Allow multiple selections
#   --type TYPE       Filter by type (lightweight/annotated/signed)
#   --pattern PATTERN Filter by name pattern
#   --prompt TEXT     Custom prompt text
# Returns:
#   0 if one or more tags were selected
#   1 if the selection was cancelled or left empty
#   2 if no tags exist, no tags match the filters, or an internal selection error occurred
#
# WHY: This function delegates data-heavy work (tag discovery, filtering,
# formatting, numbered-list interaction) to Python's tag_select.py, keeping
# only gum integration and result mapping in Bash. This replaces ~130 lines
# of parallel-array management with a thin adapter.
select_tags() {
    local selected_array_name="$1"
    local -n selected_ref="$1"
    shift

    local multi_select=false
    local prompt="Select a tag"
    local -a python_args=()

    # Parse options — build python_args for passthrough
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --multi-select)
                multi_select=true
                python_args+=(--multi)
                shift
                ;;
            --type)
                python_args+=(--type "$2")
                shift 2
                ;;
            --pattern)
                python_args+=(--pattern "$2")
                shift 2
                ;;
            --prompt)
                prompt="$2"
                python_args+=(--prompt "$2")
                shift 2
                ;;
            *)
                error "Unknown option for select_tags: $1"
                return 2
                ;;
        esac
    done

    local tag_select_py="$HUG_HOME/git-config/lib/python/git/tag_select.py"

    # Gum path: Python prepares data, Bash handles gum interaction
    if gum_available; then
        # shellcheck disable=SC2034  # variables set by eval
        local -a filtered_tags=() formatted_options=()
        local selection_status="" tag_count=0

        if ! eval "$(python3 "$tag_select_py" prepare "${python_args[@]}")"; then
            return 2
        fi

        # Check for no-data states
        if [[ "$selection_status" == "no_tags" || "$selection_status" == "no_matches" ]]; then
            selected_ref=()
            [[ "$selection_status" == "no_tags" ]] && warn "No tags found in this repository."
            [[ "$selection_status" == "no_matches" ]] && warn "No tags match the specified filters."
            return 2
        fi

        # Feed formatted options to gum
        local selection_output=""
        local -a gum_flags=()
        $multi_select && gum_flags+=(--no-limit)

        if ! selection_output=$(gum_filter_by_index formatted_options "$prompt" "${gum_flags[@]}"); then
            selected_ref=()
            return 1
        fi

        # Map gum's returned indices to tag names
        local -a selected_indices=()
        mapfile -t selected_indices <<< "$selection_output"
        _map_selected_tag_indices "$selected_array_name" selected_indices filtered_tags
        return $?
    fi

    # Non-gum path: Python handles everything (numbered list + user input)
    # shellcheck disable=SC2034  # variables set by eval
    local -a selected_tags=()
    local selection_status=""

    if ! eval "$(python3 "$tag_select_py" select "${python_args[@]}")"; then
        return 2
    fi

    case "$selection_status" in
        selected)
            selected_ref=("${selected_tags[@]}")
            return 0
            ;;
        cancelled)
            selected_ref=()
            return 1
            ;;
        no_tags)
            warn "No tags found in this repository."
            selected_ref=()
            return 2
            ;;
        no_matches)
            warn "No tags match the specified filters."
            selected_ref=()
            return 2
            ;;
        *)
            selected_ref=()
            return 2
            ;;
    esac
}
```

**Step 3: Run BATS tests to verify no regressions**

Run: `make test-bash TEST_FILTER="tag"`
Expected: All tag-related tests pass

**Step 4: Run full test suite**

Run: `make test`
Expected: All tests pass (BATS + pytest)

**Step 5: Commit**

```
refactor(tag-select): replace select_tags() with Python-backed adapter

WHY: The Bash select_tags() managed tag data through 8 parallel arrays,
inline filtering, and two duplicated selection code paths. The new adapter
delegates all data work to Python's tag_select.py and keeps only gum
integration and index mapping in Bash.

WHAT: select_tags() shrinks from ~160 lines to ~55 lines. Removed
_build_tag_select_options() (fully replaced by Python format_display_rows).
Kept _map_selected_tag_indices() for the gum path.

HOW: Two-mode delegation:
- Gum path: eval "$(python3 tag_select.py prepare ...)" then gum_filter_by_index
- Non-gum: eval "$(python3 tag_select.py select ...)"
Return contract (0/1/2) preserved exactly.

IMPACT: Callers (git-t, git-tdel) require zero changes. Eliminates the
parallel-array synchronization risk that caused the original gum breakage.
```

---

### Task 9: BATS regression validation and cleanup

**Files:**
- Possibly modify: `tests/lib/test_hug-git-tag.bats` (only if regressions found)
- Possibly modify: `tests/unit/test_tag_commands.bats` (only if regressions found)

**Step 1: Run the full BATS tag test suite with verbose output**

Run: `make test-bash TEST_FILTER="tag" TEST_SHOW_ALL_RESULTS=1`
Expected: All tests pass. If failures, investigate and fix.

**Step 2: Run the command-level tests**

Run: `make test-unit TEST_FILE=test_tag_commands.bats TEST_SHOW_ALL_RESULTS=1`
Expected: All tests pass

**Step 3: Run the library tests**

Run: `make test-lib TEST_FILE=test_hug-git-tag.bats TEST_SHOW_ALL_RESULTS=1`
Expected: All tests pass

**Step 4: Run the complete test suite**

Run: `make test`
Expected: All BATS + pytest tests pass

**Step 5: Commit (only if test fixes were needed)**

```
fix(tag-select): adjust BATS tests for Python-backed selection
```

---

### Task 10: Final cleanup and documentation

**Files:**
- Modify: `git-config/lib/python/README.md` (add tag_select.py to module list)

**Step 1: Update Python README**

Add to the "Bash-to-Python Migration Modules" section in `git-config/lib/python/README.md`:

```markdown
- ✅ `git/tag_select.py` - Tag selection with direct git integration (NNN lines, NN tests ✓)
```

Update the test count in the "Current Status" line.

**Step 2: Run final validation**

Run: `make test`
Expected: All tests pass

**Step 3: Commit**

```
docs: add tag_select.py to Python helper documentation
```
