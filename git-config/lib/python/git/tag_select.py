#!/usr/bin/env python3
"""
Hug Git Tag Select Library — Python implementation

Migrates tag discovery, filtering, formatting, and selection from the Bash
hug-git-tag library to a type-safe Python module.

Design rationale (from docs/plans/2026-03-13-tag-selection-python-migration-design.md):
- The Bash implementation passed tag data through 8 parallel arrays via namerefs.
  Array synchronisation bugs caused real regressions (see commit 52c646c).
- Python calling git directly (same approach as worktree.py) eliminates that
  problem at the source — data lives in TagInfo objects, not parallel lists.
- Explicit TagSelectionResult.status replaces the implicit convention of
  overloading exit codes + array-emptiness checks.

Two CLI modes for the Bash adapter:
    python3 tag_select.py prepare [--type TYPE] [--pattern PATTERN]
        Gum path: loads + filters + formats, outputs bash declare statements
        with filtered_tags[] and formatted_options[] for gum_filter_by_index.

    python3 tag_select.py select [--type TYPE] [--pattern PATTERN] [--multi] [--prompt TEXT]
        Numbered-list path: runs the full interactive selection loop, outputs
        bash declare statements with selected_tags[] and selection_status.

Exit codes: 0 always (status communicated through bash variables).
Non-zero only for genuine Python failures (import error, git not found).
"""

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass

################################################################################
# Data model
################################################################################


@dataclass
class TagInfo:
    """Single tag record — replaces 8 parallel Bash arrays.

    Attributes:
        name: Tag name (e.g., "v1.0.0")
        hash: Short (7-char) commit hash the tag points to
        tag_type: One of "lightweight", "annotated", "signed"
        subject: Commit or tag message subject line
        date: Tagger date for annotated/signed tags (ISO 8601); empty for lightweight
        signature: "verified" for GPG-verified signed tags, empty otherwise
        is_current: True if HEAD is exactly on this tag
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

    Both filters are optional; when both are provided they are combined with AND
    semantics (a tag must pass both to be included in the result).

    Attributes:
        type_filter: Exact match against tag_type ("lightweight", "annotated",
            "signed"), or None to skip type filtering.
        pattern: Regex pattern searched against tag names, or None to skip
            pattern filtering.  Invalid regex patterns fall back to literal
            substring matching (defensive, never raises).
    """

    type_filter: str | None = None
    pattern: str | None = None


@dataclass
class TagSelectionResult:
    """Explicit outcome of a tag selection operation.

    Unlike the Bash implementation which overloaded exit codes and array
    emptiness, this provides unambiguous status for every outcome so callers
    never have to infer state.

    Attributes:
        status: One of:
            "selected"   — user picked ≥1 tag; tags/indices are populated
            "cancelled"  — user pressed Enter / gave empty input
            "no_tags"    — repository has no tags at all
            "no_matches" — tags exist but all were filtered out
            "error"      — unexpected failure (rare, prefer exception propagation)
        tags: Selected tag names; non-empty only when status == "selected"
        indices: 0-based indices into the filtered tag list that were selected
    """

    status: str
    tags: list[str]
    indices: list[int]


################################################################################
# Bash escaping
################################################################################


def _bash_escape(s: str) -> str:
    """Escape a string for safe use inside bash declare array literals.

    Strategy: wrap in single quotes, using the '\\'' idiom for any embedded
    single quote.  Backslashes are doubled first so that bash doesn't interpret
    them as escape sequences.

    This is the canonical escaping helper used by all to_bash_declare functions
    in this codebase (worktree.py, branch_select.py use identical logic).

    Args:
        s: Arbitrary Python string to make safe for bash eval.

    Returns:
        Single-quoted, bash-safe string.

    Examples:
        >>> _bash_escape("hello")
        "'hello'"
        >>> _bash_escape("it's")
        "'it'\\\\''s'"
        >>> _bash_escape("path\\\\to")
        "'path\\\\\\\\to'"
    """
    # Order matters: escape backslashes before touching single quotes,
    # otherwise we would double-escape the backslashes we introduce.
    s = s.replace("\\", "\\\\")
    s = s.replace("'", "'\\''")
    return f"'{s}'"


################################################################################
# Pure filtering
################################################################################


def filter_tags(tags: list[TagInfo], options: TagFilterOptions) -> list[TagInfo]:
    """Apply type and pattern filters to a list of tags.

    Pure function — no side effects, no git calls, trivially testable.

    Filter semantics:
    - type_filter: exact string match on tag_type
    - pattern: regex search on tag name; falls back to literal substring if the
      pattern is not a valid regex (never raises re.error to callers)
    - Both filters combined with AND logic

    Args:
        tags: Input tag records; not mutated.
        options: Filtering criteria; either or both fields may be None.

    Returns:
        New list containing only the tags that satisfy all active filters,
        preserving the original ordering.
    """
    result: list[TagInfo] = list(tags)

    if options.type_filter:
        result = [t for t in result if t.tag_type == options.type_filter]

    if options.pattern:
        try:
            compiled = re.compile(options.pattern)
            result = [t for t in result if compiled.search(t.name)]
        except re.error:
            # Invalid regex: fall back to literal substring matching.
            # This is a defensive choice — the user may have typed a raw
            # version prefix like "[invalid" that happens to be what they want.
            result = [t for t in result if options.pattern in t.name]

    return result


################################################################################
# Display formatting
################################################################################

# Type indicator mapping — these one-letter codes match the display convention
# established by the Bash _build_tag_select_options() function.
_TYPE_INDICATORS: dict[str, str] = {
    "lightweight": "[L]",
    "annotated": "[A]",
    "signed": "[S]",
}


def format_display_rows(tags: list[TagInfo]) -> list[str]:
    """Build formatted selection rows for interactive display.

    Produces the same visual output as the Bash _build_tag_select_options()
    helper so that gum filter and numbered-list display look identical before
    and after the migration.

    Row format:  "[* ]tagname [L|A|S] hash subject"
      - Current tag gets the "* " prefix; non-current tags have no prefix.
      - Type indicator is omitted for unknown tag_type values (future-proof).

    Args:
        tags: Tag records to format; not mutated.

    Returns:
        List of formatted strings, one per tag, in the same order.
    """
    rows: list[str] = []
    for tag in tags:
        parts: list[str] = []

        # Current-tag marker: "* tagname" vs plain "tagname"
        if tag.is_current:
            parts.append(f"* {tag.name}")
        else:
            parts.append(tag.name)

        # Type indicator — skip gracefully for any unrecognised type
        indicator = _TYPE_INDICATORS.get(tag.tag_type, "")
        if indicator:
            parts.append(indicator)

        # Hash and subject always present (may be empty string in degenerate cases)
        parts.append(tag.hash)
        parts.append(tag.subject)

        rows.append(" ".join(parts))

    return rows


################################################################################
# User input parsing
################################################################################


def parse_numbered_input(user_input: str, num_items: int) -> list[int]:
    """Parse user selection input into 0-based indices.

    Supports the same input formats as branch_select.parse_user_input() so
    both selection surfaces behave identically:
      - 'a' / 'all' / 'ALL' (case-insensitive) → select all items
      - Comma-separated 1-based numbers: "1,2,3"
      - Inclusive ranges: "2-4" → items 2, 3, 4
      - Mixed: "1,3-5,7"
      - Empty / whitespace → no selection

    Out-of-range numbers are silently ignored; duplicates are deduplicated;
    output is always sorted ascending.

    Args:
        user_input: Raw input string from stdin.
        num_items: Total number of selectable items (upper bound for validation).

    Returns:
        Sorted list of unique 0-based indices in [0, num_items).
    """
    user_input = user_input.strip()

    if not user_input:
        return []

    # "all" / "a" shortcuts — case-insensitive
    if user_input.lower() in ("a", "all"):
        return list(range(num_items))

    indices: set[int] = set()

    for part in user_input.split(","):
        part = part.strip()

        if "-" in part:
            # Range: "start-end" (both 1-based, inclusive)
            try:
                start_str, end_str = part.split("-", 1)
                start = int(start_str.strip())
                end = int(end_str.strip())
                # Convert to 0-based, clamp to valid range
                start_idx = max(0, start - 1)
                end_idx = min(num_items - 1, end - 1)
                for i in range(start_idx, end_idx + 1):
                    indices.add(i)
            except ValueError:
                continue  # malformed range token, skip silently
        else:
            # Single 1-based number
            try:
                num = int(part)
                idx = num - 1  # convert to 0-based
                if 0 <= idx < num_items:
                    indices.add(idx)
            except ValueError:
                continue  # non-numeric token, skip silently

    return sorted(indices)


################################################################################
# Bash declare output
################################################################################


def to_bash_declare(result: TagSelectionResult, array_name: str = "selected_tags") -> str:
    """Serialize a TagSelectionResult to bash declare statements for eval.

    Outputs two lines:
        declare -a <array_name>=('tag1' 'tag2' ...)
        selection_status='status'

    All tag names are individually shell-escaped so that tags with special
    characters (spaces, single quotes, backslashes) survive the eval round-trip.

    Args:
        result: Selection outcome to serialize.
        array_name: Name for the bash array variable (default: "selected_tags").

    Returns:
        Multi-line string of bash variable declarations.
    """
    lines: list[str] = []
    tags_arr = " ".join(_bash_escape(t) for t in result.tags)
    lines.append(f"declare -a {array_name}=({tags_arr})")
    lines.append(f"selection_status={_bash_escape(result.status)}")
    return "\n".join(lines)


def tags_to_bash_declare(tags: list[TagInfo], formatted: list[str], status: str = "no_tags") -> str:
    """Serialize filtered tags and display rows to bash declare statements.

    Used by the 'prepare' CLI command (gum path).  The Bash adapter evals the
    output to obtain filtered_tags[] (tag names) and formatted_options[]
    (display rows) for feeding into gum_filter_by_index.

    Empty tags produce a no_tags signal so the caller can short-circuit without
    invoking gum at all.

    Args:
        tags: Filtered TagInfo records.
        formatted: Formatted display rows, parallel to tags (same length).
        status: Override the empty-case status (default: "no_tags").  Pass
            "no_matches" when tags exist but filters eliminated all of them,
            so the Bash adapter can distinguish the two empty cases.

    Returns:
        Multi-line string of bash variable declarations.
    """
    if not tags:
        # Short-circuit: nothing to show — emit empty arrays + sentinel status
        return (
            "declare -a filtered_tags=()\n"
            "declare -a formatted_options=()\n"
            f"selection_status='{status}'\n"
            "tag_count=0"
        )

    lines: list[str] = []

    tags_arr = " ".join(_bash_escape(t.name) for t in tags)
    lines.append(f"declare -a filtered_tags=({tags_arr})")

    opts_arr = " ".join(_bash_escape(f) for f in formatted)
    lines.append(f"declare -a formatted_options=({opts_arr})")

    lines.append("selection_status='ready'")
    lines.append(f"tag_count={len(tags)}")

    return "\n".join(lines)


################################################################################
# Git subprocess integration
################################################################################


def _run_git(args: list[str], check: bool = False) -> str:
    """Run a git command and return its stdout as a stripped string.

    Always uses 'git --no-pager' to prevent interactive pager prompts in
    non-TTY contexts (scripts, CI).

    Args:
        args: Git subcommand and arguments (without the leading 'git').
        check: If True, raise RuntimeError on non-zero exit code.

    Returns:
        Stripped stdout; empty string on failure (unless check=True).

    Note:
        When check=False (default), a command that exits non-zero with empty
        stdout is indistinguishable from one that exits 0 with empty stdout.
        Callers in load_tags() use ``or "fallback"`` to handle this safely.

    Raises:
        RuntimeError: If check=True and the command fails or times out.
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
                f"git {' '.join(args)} failed (exit {result.returncode}): {result.stderr.strip()}"
            )
        return result.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError) as exc:
        if check:
            raise RuntimeError(f"git command failed: {exc}") from exc
        return ""


def load_tags() -> list[TagInfo]:
    """Discover all tags in the current git repository as TagInfo records.

    Calls git directly to build structured records.  This replaces the Bash
    compute_tag_details() function for the selection path, eliminating the
    8-nameref parallel-array pattern.

    Tags are returned in version-descending order (newest first) as produced
    by 'git tag --sort=-version:refname', matching the Bash convention.

    Git calls made per tag:
      - cat-file -t <name>          → distinguish lightweight vs annotated/signed
      - tag -l --format=%(...)      → tagger date + subject (annotated only)
      - rev-list -n 1 <name>        → commit hash (annotated only)
      - verify-tag --quiet <name>   → GPG signature check (annotated only)
      - rev-parse --short <name>    → commit hash (lightweight)
      - log -n 1 --pretty=format:%s → commit subject (lightweight)
      - describe --tags --exact-match → detect if HEAD is on this tag (once)

    Performance: 5-7 subprocess calls per tag.  Acceptable for the typical
    <50 tag case; if needed in bulk, a batch approach using ``git for-each-ref``
    would be more efficient.

    Returns:
        List of TagInfo objects; empty list if the repository has no tags.
    """
    # Determine whether HEAD is currently sitting on an exact tag.
    # 'describe --exact-match' exits non-zero when HEAD is not on a tag,
    # which is fine — we just get an empty string and all is_current stay False.
    current_tag = _run_git(["describe", "--tags", "--exact-match"])

    # List all tags, newest version first.
    tag_output = _run_git(["tag", "--sort=-version:refname"])
    if not tag_output:
        return []

    tag_names = [line.strip() for line in tag_output.splitlines() if line.strip()]
    tags: list[TagInfo] = []

    for name in tag_names:
        # cat-file -t returns the object type:
        #   "commit" → lightweight tag (points directly to a commit)
        #   "tag"    → annotated or signed tag (points to a tag object)
        object_type = _run_git(["cat-file", "-t", name]) or "commit"

        tag_type = "lightweight"
        date = ""
        subject = ""
        signature = ""
        hash_str = ""

        if object_type == "tag":
            # Annotated (or possibly signed) tag
            tag_type = "annotated"

            # Tagger date and message subject from the tag object itself
            date = _run_git(["tag", "-l", "--format=%(taggerdate:iso8601)", name])
            subject = _run_git(["tag", "-l", "--format=%(subject)", name])

            # Dereference the tag to the commit it ultimately points to
            full_hash = _run_git(["rev-list", "-n", "1", name])
            hash_str = full_hash[:7] if full_hash else ""

            # GPG signature check: success → signed, any failure → plain annotated.
            # verify-tag exits non-zero for unsigned tags, which is the normal case.
            try:
                _run_git(["verify-tag", "--quiet", name], check=True)
                tag_type = "signed"
                signature = "verified"
            except RuntimeError:
                pass  # Expected: not signed, or GPG not configured

        else:
            # Lightweight tag — resolve directly to the commit hash
            hash_str = _run_git(["rev-parse", "--short", name])

        # For lightweight tags (or annotated tags where the message is empty),
        # fall back to reading the commit subject from the log.
        if not subject:
            subject = (
                _run_git(["log", "-n", "1", "--pretty=format:%s", hash_str or name])
                or "(no commit message)"
            )

        # Sanitise any stray newlines that might survive the .strip() call
        # (defensive, matching the Bash 'tr -d "\n\r"' convention).
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


################################################################################
# CLI command implementations
################################################################################


def _cmd_prepare(type_filter: str | None, pattern: str | None) -> str:
    """Execute the 'prepare' CLI command (gum path).

    Loads all tags, applies filters, formats display rows, and returns bash
    declare statements for the Bash adapter to eval before invoking
    gum_filter_by_index.

    Args:
        type_filter: Optional tag type to filter by.
        pattern: Optional regex pattern to filter tag names.

    Returns:
        Bash declare statements as a string.
    """
    tags = load_tags()
    if not tags:
        return tags_to_bash_declare([], [])

    filtered = filter_tags(tags, TagFilterOptions(type_filter=type_filter, pattern=pattern))
    if not filtered:
        # Tags exist but filters produced no results — distinct from no_tags
        return tags_to_bash_declare([], [], status="no_matches")

    formatted = format_display_rows(filtered)
    return tags_to_bash_declare(filtered, formatted)


def _cmd_select(
    type_filter: str | None,
    pattern: str | None,
    multi: bool,
    prompt: str,
) -> str:
    """Execute the 'select' CLI command (numbered-list path).

    Loads tags, applies filters, presents a numbered list on stderr (so that
    stdout contains only the bash declare output), reads user input, and
    returns bash declare statements with the selection result.

    Printing to stderr ensures that 'eval "$(python3 tag_select.py select ...)"'
    works correctly — eval only processes stdout.

    Args:
        type_filter: Optional tag type to filter by.
        pattern: Optional regex pattern to filter tag names.
        multi: If True, allow comma/range multi-selection; otherwise take
            only the first selected item.
        prompt: Header text to display above the numbered list.

    Returns:
        Bash declare statements as a string.
    """
    tags = load_tags()
    if not tags:
        return to_bash_declare(TagSelectionResult(status="no_tags", tags=[], indices=[]))

    filtered = filter_tags(tags, TagFilterOptions(type_filter=type_filter, pattern=pattern))
    if not filtered:
        return to_bash_declare(TagSelectionResult(status="no_matches", tags=[], indices=[]))

    formatted = format_display_rows(filtered)

    # Display to stderr so stdout stays clean for bash eval
    print(f"{prompt}:\n", file=sys.stderr)
    for i, row in enumerate(formatted):
        print(f"  {i + 1:2d}) {row}", file=sys.stderr)
    print(file=sys.stderr)

    # Read user selection
    try:
        if multi:
            user_input = input("Enter numbers to select (comma-separated, or 'a' for all): ")
        else:
            user_input = input("Enter number: ")
    except EOFError:
        # Non-interactive context (piped input exhausted)
        user_input = ""

    if not user_input.strip():
        return to_bash_declare(TagSelectionResult(status="cancelled", tags=[], indices=[]))

    indices = parse_numbered_input(user_input, len(filtered))
    if not indices:
        # User typed something but it produced no valid selections
        return to_bash_declare(TagSelectionResult(status="cancelled", tags=[], indices=[]))

    if not multi:
        # Single-select mode: discard all but the first chosen item
        indices = indices[:1]

    selected = [filtered[i].name for i in indices]
    return to_bash_declare(TagSelectionResult(status="selected", tags=selected, indices=indices))


################################################################################
# CLI entry point
################################################################################


def main() -> None:
    """CLI entry point for bash wrapper calls.

    Commands:
        prepare   Load + filter + format; output bash declares for gum path.
        select    Load + filter + numbered-list interaction; output bash declares.

    Both commands exit 0 and communicate outcomes via bash variables so that
    callers can use 'eval "$(python3 tag_select.py ...)"' safely.  Non-zero
    exits are reserved for genuine Python-level failures.

    Usage examples:
        python3 tag_select.py prepare --type annotated
        python3 tag_select.py select --multi --prompt "Delete tags"
        python3 tag_select.py prepare --pattern "^v1\\."
    """
    parser = argparse.ArgumentParser(
        description="Tag selection for Hug SCM — migrated from Bash to Python"
    )
    parser.add_argument(
        "command",
        choices=["prepare", "select"],
        help="'prepare' for gum path; 'select' for numbered-list path",
    )
    parser.add_argument(
        "--type",
        dest="type_filter",
        default=None,
        help="Filter by tag type: lightweight, annotated, or signed",
    )
    parser.add_argument(
        "--pattern",
        default=None,
        help="Filter tag names by regex pattern (falls back to literal on invalid regex)",
    )
    parser.add_argument(
        "--multi",
        action="store_true",
        help="Allow multiple tag selections (select command only)",
    )
    parser.add_argument(
        "--prompt",
        default="Select a tag",
        help="Prompt header text (select command only)",
    )

    args = parser.parse_args()

    try:
        if args.command == "prepare":
            output = _cmd_prepare(
                type_filter=args.type_filter,
                pattern=args.pattern,
            )
        else:  # "select"
            output = _cmd_select(
                type_filter=args.type_filter,
                pattern=args.pattern,
                multi=args.multi,
                prompt=args.prompt,
            )
        print(output)

    except Exception as exc:  # pylint: disable=broad-except
        # Unexpected failures should not leave the bash caller in an unknown
        # state — print to stderr and exit non-zero so the caller can detect it.
        print(f"tag_select: unexpected error: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
