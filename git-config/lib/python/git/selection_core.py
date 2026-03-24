"""Shared selection infrastructure for Hug SCM interactive selection modules.

This module is the single source of truth for primitives shared across all
interactive selection modules (tag_select, worktree_select, branch_select,
branch_filter).  Before this module existed, each duplicated _bash_escape()
and inlined declare-statement generation — a classic DRY violation that caused
subtle divergence bugs.

Public API:
    bash_escape(s)        — escape a Python string for bash single-quote context
    BashDeclareBuilder    — fluent builder for bash declare statements

Design decisions:
    - bash_escape is public (not _bash_escape) because it is shared
      infrastructure, not a module-private helper.
    - BashDeclareBuilder validates variable names eagerly (at add_* call time),
      following the fail-fast principle.  Deferring validation to build() would
      produce confusing late errors.
    - Fluent API (each add_* returns self) allows concise chaining without
      sacrificing readability.
"""

import re

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
        raise ValueError(
            f"Invalid bash variable name: {name!r}. "
            "Must match [a-zA-Z_][a-zA-Z0-9_]*"
        )


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
