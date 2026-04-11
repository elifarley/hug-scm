"""Shared selection infrastructure for Hug SCM interactive selection modules.

This module is the single source of truth for primitives shared across all
interactive selection modules (tag_select, worktree_select, branch_select,
branch_filter).  Before this module existed, each duplicated _bash_escape()
and inlined declare-statement generation — a classic DRY violation that caused
subtle divergence bugs.

Public API:
    bash_escape(s)        — escape a Python string for bash single-quote context
    BashDeclareBuilder    — fluent builder for bash declare statements
    parse_numbered_input  — parse user selection string → 0-based index list
    get_selection_input   — read user selection with env-var / test_selection override
    add_common_cli_args   — register shared argparse arguments on a parser

    ANSI color constants: YELLOW, BLUE, GREY, CYAN, GREEN, NC

Design decisions:
    - bash_escape is public (not _bash_escape) because it is shared
      infrastructure, not a module-private helper.
    - BashDeclareBuilder validates variable names eagerly (at add_* call time),
      following the fail-fast principle.  Deferring validation to build() would
      produce confusing late errors.
    - Fluent API (each add_* returns self) allows concise chaining without
      sacrificing readability.
    - parse_numbered_input is ported verbatim from branch_select.parse_user_input
      so all selection modules share identical parsing semantics going forward.
    - get_selection_input encodes a three-level precedence chain used in every
      selection module: test_selection arg > env var > stdin.  Centralising it
      prevents subtle drift (e.g. one module reading a different env var name).
    - add_common_cli_args accepts include_no_gum so that callers that never
      drive gum (e.g. tag_select in numbered mode) don't advertise the flag.
"""

import argparse
import os
import re
import sys
import termios
import tty

################################################################################
# Character-mode input support for ESC key detection.
################################################################################
# Use tty + termios (stdlib, POSIX-only) when available, so we can read a single
# keypress and detect ESC (\x1b) without waiting for Enter.  Falls back to None
# if these modules aren't available (Windows, some CI environments).
_HAS_TTY = True

# These values intentionally match branch_select.py so every module that
# imports from selection_core produces visually consistent terminal output.
# Using \x1b (ESC) is more explicit than \033 and avoids octal ambiguity.
YELLOW = "\x1b[33m"  # branch names, tag names, commit hashes
BLUE = "\x1b[34m"  # dates, timestamps
GREY = "\x1b[90m"  # secondary info (commit subjects, descriptions)
CYAN = "\x1b[36m"  # tracking / remote info
GREEN = "\x1b[32m"  # positive indicators (current item, success)
NC = "\x1b[0m"  # No Color — reset all attributes


################################################################################
# Variable name validation
################################################################################

# Bash variable name rule: [a-zA-Z_][a-zA-Z0-9_]*
# This matches POSIX portable character names exactly.
_VAR_NAME_RE = re.compile(r"^[a-zA-Z_][a-zA-Z0-9_]*$")


def _validate_var_name(name: str) -> None:
    """Raise ValueError if name is not a valid bash variable name.

    Called eagerly by each BashDeclareBuilder.add_* method so that invalid
    names produce an immediate, actionable error rather than silently emitting
    broken bash syntax.

    Args:
        name: Candidate bash variable name.

    Raises:
        ValueError: If name does not match [a-zA-Z_][a-zA-Z0-9_]*.
    """
    if not _VAR_NAME_RE.match(name):
        raise ValueError(f"Invalid bash variable name: {name!r}. Must match [a-zA-Z_][a-zA-Z0-9_]*")


################################################################################
# Bash escaping
################################################################################


def bash_escape(s: str) -> str:
    """Escape a Python string for safe use inside bash single-quote contexts.

    Strategy: wrap in single quotes, using the '\\'' idiom for any embedded
    single quote.  Backslashes are doubled FIRST so that bash doesn't interpret
    them as escape sequences — order matters here.

    This is the canonical implementation extracted from the four modules that
    previously each duplicated it as _bash_escape().

    Args:
        s: Arbitrary Python string to make safe for bash eval.

    Returns:
        Single-quoted, bash-safe string.

    Examples:
        >>> bash_escape("hello")
        "'hello'"
        >>> bash_escape("it's")
        "'it'\\\\''s'"
        >>> bash_escape("path\\\\to")
        "'path\\\\\\\\to'"
        >>> bash_escape("")
        "''"
    """
    # Order matters: escape backslashes before touching single quotes.
    # If we swapped the order we would double-escape the backslashes we introduce
    # for the single-quote idiom, producing garbled output.
    s = s.replace("\\", "\\\\")
    s = s.replace("'", "'\\''")
    return f"'{s}'"


################################################################################
# BashDeclareBuilder
################################################################################


class BashDeclareBuilder:
    """Fluent builder for bash `declare` statements.

    Collects variable declarations and renders them as newline-separated bash
    `declare` statements suitable for `eval` in a Bash adapter script.

    Supported declaration types:
        add_array(name, values)  → declare -a name=('v1' 'v2')
        add_scalar(name, value)  → declare name='val'
        add_int(name, value)     → declare -i name=42

    All string values are shell-escaped via bash_escape().  Integer values are
    not quoted — bash integers are always safe to emit bare.

    Variable name validation is eager: invalid names raise ValueError
    immediately at add_* call time, not at build() time.

    Example::

        output = (
            BashDeclareBuilder()
            .add_array("filtered_tags", ["v1.0", "v2.0"])
            .add_scalar("selection_status", "ready")
            .add_int("tag_count", 2)
            .build()
        )
        # declare -a filtered_tags=('v1.0' 'v2.0')
        # declare selection_status='ready'
        # declare -i tag_count=2
    """

    def __init__(self) -> None:
        # List of fully-rendered declare lines, in insertion order.
        self._lines: list[str] = []

    def add_array(self, name: str, values: list[str]) -> "BashDeclareBuilder":
        """Append a declare -a array statement.

        Args:
            name: Bash variable name (must match [a-zA-Z_][a-zA-Z0-9_]*).
            values: List of string values; each is bash_escape()d individually.

        Returns:
            self, for fluent chaining.

        Raises:
            ValueError: If name is not a valid bash variable name.
        """
        _validate_var_name(name)
        escaped = " ".join(bash_escape(v) for v in values)
        self._lines.append(f"declare -a {name}=({escaped})")
        return self

    def add_scalar(self, name: str, value: str) -> "BashDeclareBuilder":
        """Append a declare scalar (string) statement.

        Args:
            name: Bash variable name (must match [a-zA-Z_][a-zA-Z0-9_]*).
            value: String value; bash_escape()d before emission.

        Returns:
            self, for fluent chaining.

        Raises:
            ValueError: If name is not a valid bash variable name.
        """
        _validate_var_name(name)
        self._lines.append(f"declare {name}={bash_escape(value)}")
        return self

    def add_int(self, name: str, value: int) -> "BashDeclareBuilder":
        """Append a declare -i integer statement.

        Integers are emitted bare (no quoting) — they are always safe as literal
        digits in bash arithmetic context and quoting them would prevent bash
        from treating the variable as an integer type.

        Args:
            name: Bash variable name (must match [a-zA-Z_][a-zA-Z0-9_]*).
            value: Integer value.

        Returns:
            self, for fluent chaining.

        Raises:
            ValueError: If name is not a valid bash variable name.
        """
        _validate_var_name(name)
        self._lines.append(f"declare -i {name}={value}")
        return self

    def build(self) -> str:
        """Render all accumulated declarations as a newline-separated string.

        Returns:
            Multi-line string of bash declare statements, or empty string if no
            declarations were added.
        """
        return "\n".join(self._lines)


################################################################################
# User input parsing
################################################################################


def parse_numbered_input(user_input: str, num_items: int, allow_all: bool = True) -> list[int]:
    """Parse a user selection string into a sorted list of 0-based indices.

    This is the canonical implementation extracted from
    branch_select.parse_user_input() so that every selection module shares
    identical parsing semantics — previously each module duplicated this logic
    and subtle differences crept in.

    Supported formats:
        ''         → []                  (no selection)
        'a' / 'A'  → [0 .. num_items-1]  (select all, when allow_all=True)
        'all'/'ALL'→ same as 'a'
        '1'        → [0]                 (1-based display → 0-based index)
        '1,3,5'    → [0, 2, 4]          (comma-separated)
        '1-3'      → [0, 1, 2]          (inclusive range)
        '1,3-5,7'  → [0, 2, 3, 4, 6]   (mixed)

    Out-of-bounds numbers and malformed parts are silently skipped so the
    function never raises for bad user input — it degrades gracefully.
    Reverse ranges (e.g. '5-3') produce an empty range (Python range semantics).

    Args:
        user_input: Raw string typed by the user.
        num_items:  Total number of selectable items.
        allow_all:  When True (default), 'a'/'all' selects everything.
                    Set to False when the caller handles its own "all" logic.

    Returns:
        Sorted list of unique 0-based indices within [0, num_items).

    Examples:
        >>> parse_numbered_input("1,2,3", 5)
        [0, 1, 2]
        >>> parse_numbered_input("1-3", 5)
        [0, 1, 2]
        >>> parse_numbered_input("all", 3)
        [0, 1, 2]
        >>> parse_numbered_input("1,3-5,7", 10)
        [0, 2, 3, 4, 6]
    """
    user_input = user_input.strip()

    # Empty input → nothing selected
    if not user_input:
        return []

    # 'a' / 'all' shortcut — case-insensitive, gated by allow_all
    if allow_all and user_input.lower() in ("a", "all"):
        return list(range(num_items))

    indices: set[int] = set()

    for part in user_input.split(","):
        part = part.strip()

        if "-" in part:
            # Range token, e.g. "3-7"
            # split on the FIRST hyphen only so that negative numbers in the
            # start position still parse; the end position cannot be negative
            # in a valid range, so we leave error handling to the ValueError path.
            try:
                start_str, end_str = part.split("-", 1)
                start_idx = max(0, int(start_str.strip()) - 1)  # 0-based, clamped
                end_idx = min(num_items - 1, int(end_str.strip()) - 1)  # 0-based, clamped
                # When start_idx > end_idx (reverse range or out-of-bounds start)
                # range() produces an empty sequence — no results, no error.
                indices.update(range(start_idx, end_idx + 1))
            except ValueError:
                # Non-integer endpoints → skip this token silently
                continue
        else:
            # Single number token
            try:
                idx = int(part) - 1  # 1-based display → 0-based index
                if 0 <= idx < num_items:
                    indices.add(idx)
                # Out-of-bounds → silently ignored
            except ValueError:
                # Non-integer token → skip silently
                continue

    return sorted(indices)


################################################################################
# Selection input sourcing
################################################################################


def get_selection_input(
    test_selection: str | None = None,
    env_var: str = "HUG_TEST_NUMBERED_SELECTION",
) -> str:
    """Return user selection input from the highest-priority available source.

    This function encodes the three-level precedence chain used across every
    selection module.  Centralising it prevents subtle drift where modules read
    different environment variable names or handle EOFError differently.

    Precedence (first match wins):
        1. test_selection argument  — if not None, returned as-is.
           The sentinel for "not set" is None; an empty string "" is a valid
           and deliberate choice that DOES short-circuit the chain.
        2. env_var environment variable — if the named variable is set.
        3. input() from stdin — the normal interactive path.
        4. Empty string — returned silently when stdin raises EOFError
           (e.g. non-interactive CI environments piping /dev/null to stdin).

    Args:
        test_selection: Pre-determined value for automated testing.  Pass None
                        to fall through to the env var / stdin path.
        env_var:        Name of the environment variable to check at level 2.
                        Defaults to "HUG_TEST_NUMBERED_SELECTION".

    Returns:
        The user's selection string (may be empty).
    """
    # Level 1: explicit test_selection argument (None is the "not set" sentinel)
    if test_selection is not None:
        return test_selection

    # Level 2: environment variable override (useful for shell-script test suites)
    if env_var in os.environ:
        return os.environ[env_var]

    # Level 3 + 4: interactive stdin, with graceful EOFError fallback.
    #
    # CHARACTER-MODE KEY READ: Use tty + termios (POSIX) to read a single keypress
    # and detect the ESC key (\x1b) without waiting for Enter.  Python's built-in
    # input() is line-buffered and cannot detect ESC on its own.
    #
    # Flow:
    #   - Save terminal settings, set raw mode (tty.setraw).
    #   - Read one character with sys.stdin.read(1).
    #   - If it's '\x1b' (ESC), return None → parse_single_input returns None
    #     → caller maps to "cancelled".  Indistinguishable from pressing Enter
    #     on an empty prompt — the right UX.
    #   - For any other character, restore terminal and fall through to input().
    #     (Arrow-key navigation is not implemented here; only ESC matters.)
    #   - On any exception / failure, restore terminal and degrade to input().
    #   - Graceful degradation: if tty/termios are unavailable (non-POSIX,
    #     non-TTY, or any read error), fall through to line-mode input().
    try:
        fd = sys.stdin.fileno()
        old_settings = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            c = sys.stdin.read(1)
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
        if c == "\x1b":
            # ESC pressed — signal cancellation (None), not empty string.
            # parse_single_input(None, ...) returns None → "cancelled".
            return None
        # Non-ESC character typed — fall through to line-mode input() below.
    except Exception:
        # Fall through to line-mode input on any terminal/read error.
        # Covers: non-POSIX (ImportError), non-TTY (isatty false), any I/O error.
        pass

    try:
        return input()
    except EOFError:
        return ""


################################################################################
# Shared argparse configuration
################################################################################


def add_common_cli_args(
    parser: argparse.ArgumentParser,
    include_no_gum: bool = False,
) -> None:
    """Register shared CLI arguments on an ArgumentParser.

    Every selection-module CLI accepts --placeholder and --selection.
    The --no-gum flag is optional: only callers that drive gum should advertise
    it, because advertising an unknown flag confuses users who don't need it.

    Args:
        parser:         The ArgumentParser to augment.
        include_no_gum: When True, also register --no-gum (action="store_true").
                        Defaults to False.
    """
    parser.add_argument(
        "--placeholder",
        default="",
        help="Prompt text displayed above the selection list.",
    )
    parser.add_argument(
        "--selection",
        default=None,
        help=("Pre-selected input for automated testing (simulates the user typing a selection)."),
    )
    if include_no_gum:
        parser.add_argument(
            "--no-gum",
            action="store_true",
            help="Disable gum usage and fall back to the numbered-list mode.",
        )
