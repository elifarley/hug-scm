#!/usr/bin/env python3
"""
Hug Git Search Library - Python implementation

Provides type-safe search functionality for filtering items by field values
with configurable OR/AND logic. Replaces the Bash search_items_by_fields()
function from hug-arrays.

Supports:
- Case-insensitive substring matching across multiple fields
- OR logic (any term matches any field = match)
- AND logic (all terms must match at least one field each)
- Bash variable declaration output for eval
"""

import argparse
import sys
from dataclasses import dataclass
from typing import Literal


@dataclass
class SearchResult:
    """Result of a search operation.

    Attributes:
        matched: True if search terms matched, False otherwise
        logic: The search logic used ("OR" or "AND")
        terms: The search terms that were evaluated
    """

    matched: bool
    logic: Literal["OR", "AND"]
    terms: list[str]

    def to_bash_declare(self) -> str:
        """Format as bash variable declarations.

        Outputs bash 'declare' statements that can be eval'd to set variables:
        - search_matched (integer: 0 for match, 1 for no match)
        - search_logic (string: "OR" or "AND")
        - search_terms (array: list of search terms)

        Note: Uses '_search_' prefix to avoid nameref conflicts in Bash callers.

        Returns:
            Bash declare statements as a string
        """
        lines = []

        # Matched is output as integer exit code style (0=match, 1=no match)
        matched_code = 0 if self.matched else 1
        lines.append(f"declare -i _search_matched={matched_code}")

        # Logic as string
        lines.append(f"declare _search_logic={_bash_escape(self.logic)}")

        # Terms as array
        terms_arr = " ".join(_bash_escape(t) for t in self.terms)
        lines.append(f"declare -a _search_terms=({terms_arr})")

        return "\n".join(lines)


def _bash_escape(s: str) -> str:
    """Escape string for safe bash declare usage.

    Uses single quotes with inner quote escaping for maximum compatibility.
    Handles: backslashes, single quotes, and most special characters.

    Args:
        s: String to escape

    Returns:
        Escaped string wrapped in single quotes
    """
    s = s.replace("\\", "\\\\")  # Backslashes first (order matters)
    s = s.replace("'", "'\\''")  # Single quotes
    return f"'{s}'"


def search_items_by_fields(
    search_terms: str,
    logic: Literal["OR", "AND"],
    *fields: str,
) -> bool:
    """Search for terms across multiple fields with configurable logic.

    This function replaces the Bash search_items_by_fields() function,
    providing type-safe parameter handling and eliminating the potential
    for "unbound variable" bugs.

    The search performs case-insensitive substring matching:
    - A term matches if it appears as a substring within any field value
    - Matching is case-insensitive (both strings are lowercased for comparison)

    Args:
        search_terms: Space-separated search terms to look for
        logic: Search logic - "OR" (any term matches) or "AND" (all terms must match)
        *fields: Variable number of field values to search within

    Returns:
        True if search matched the criteria, False otherwise.
        Empty search_terms returns True (matches everything).

    Logic Behavior:
        OR logic: Return True if ANY term matches ANY field
        AND logic: Return True if ALL terms match at least ONE field each

    Examples:
        >>> # OR logic - matches if "feat" or "bug" is in any field
        >>> search_items_by_fields("feat bug", "OR", "feature-branch", "Fix bug")
        True

        >>> # AND logic - both "feat" and "123" must be found
        >>> search_items_by_fields("feat 123", "AND", "feature-branch", "abc123")
        True

        >>> # Empty search terms matches everything
        >>> search_items_by_fields("", "OR", "any-value")
        True

        >>> # OR logic - no match
        >>> search_items_by_fields("xyz", "OR", "main", "develop")
        False

        >>> # AND logic - only one term matches
        >>> search_items_by_fields("feat xyz", "AND", "feature-branch", "main")
        False
    """
    # Early return: empty search terms means match everything (like Bash version)
    if not search_terms or not search_terms.strip():
        return True

    # Split search terms into list (handles multiple spaces)
    terms = [t for t in search_terms.strip().split() if t]

    if not terms:
        return True

    # OR logic: return True if any term matches any field
    if logic == "OR":
        for term in terms:
            term_lower = term.lower()
            for field in fields:
                if term_lower in field.lower():
                    return True  # Found a match
        return False  # No term matched any field

    # AND logic: all terms must match at least one field each
    for term in terms:
        term_lower = term.lower()
        term_matched = False
        for field in fields:
            if term_lower in field.lower():
                term_matched = True
                break  # This term matched, move to next term

        if not term_matched:
            return False  # This term didn't match any field

    return True  # All terms matched at least one field


def main():
    """CLI entry point for bash wrapper calls.

    Usage:
        python3 search.py search [options]

    Options:
        --terms STR       Space-separated search terms
        --logic STR       Search logic: "OR" or "AND" (default: "OR")
        --fields LIST     Space-separated field values to search

    Outputs bash variable declarations via to_bash_declare().
    Returns exit code 1 on error.

    The output uses '_search_' prefix for all variables to avoid nameref
    conflicts in Bash callers. Callers should use 'local -a' before eval.

    Example:
        $ python3 search.py search --terms "feat bug" --logic OR --fields "feature-branch main"
        declare -i _search_matched=0
        declare _search_logic='OR'
        declare -a _search_terms=('feat' 'bug')

    Bash integration example:
        local -a _search_terms=()
        eval "$(python3 search.py search --terms "$search_terms" --logic "$logic" --fields "${fields[@]}")"
        result=$_search_matched  # 0=match, 1=no match
    """
    parser = argparse.ArgumentParser(description="Search fields for Hug SCM")
    parser.add_argument(
        "command", choices=["search"], help="Command to run (currently only 'search' supported)"
    )
    parser.add_argument("--terms", required=True, help="Space-separated search terms")
    parser.add_argument(
        "--logic",
        default="OR",
        choices=["OR", "AND"],
        help="Search logic: 'OR' (any match) or 'AND' (all must match)",
    )
    parser.add_argument("--fields", required=True, help="Space-separated field values to search")

    args = parser.parse_args()

    try:
        # Parse space-separated values
        terms = args.terms
        fields = args.fields.split() if args.fields else []

        # Run search - pass positional args first, then keyword args
        matched = search_items_by_fields(terms, args.logic, *fields)

        # Build SearchResult for bash output
        result = SearchResult(
            matched=matched,
            logic=args.logic,
            terms=terms.split(),
        )

        # Output bash declarations
        print(result.to_bash_declare())

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
