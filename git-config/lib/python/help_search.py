#!/usr/bin/env python3
"""
Hug Help Topic Search — fuzzy search across command metadata.

Provides three search modes:
  /keyword  — fuzzy search description + command name
  @category — browse commands by category tag
  !intent   — fuzzy search description (same as /keyword, kept for API symmetry)

Uses thefuzz for fuzzy matching with fallback to case-insensitive substring matching.
Metadata is collected by querying each script's --search-meta flag and extracting
descriptions from --help output. Results are cached with mtime-based invalidation.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

# Fuzzy matching: optional dependency with fallback
try:
    from thefuzz import fuzz as _fuzz

    def _fuzzy_score(query: str, target: str) -> int:
        return _fuzz.partial_ratio(query.lower(), target.lower())

    HAS_THEFUZZ = True
except ImportError:
    HAS_THEFUZZ = False

    def _fuzzy_score(query: str, target: str) -> int:
        q, t = query.lower(), target.lower()
        return 100 if q in t else 0


# Gateway prefixes: scripts matching git-{X}-* are dispatched through git-{X}
GATEWAY_PREFIXES = {"h", "w"}

# Minimum relevance score (0-100) to include in results
MIN_SCORE = 55

# Default paths
_DEFAULT_BIN_DIR = os.path.join(os.path.dirname(__file__), "..", "bin")
_DEFAULT_CACHE_DIR = "/tmp/cache/hug"


@dataclass
class CommandInfo:
    """Metadata for a single hug command."""

    command: str = ""
    description: str = ""
    categories: list[str] = field(default_factory=list)


def derive_command_name(filename: str) -> str:
    """Derive the canonical hug command from a script filename.

    Rules:
      - Strip 'git-' prefix
      - For gateway prefixes (h, w): git-h-undo → "hug h undo"
      - For everything else: git-bpush → "hug bpush"
    """
    raw = filename.removeprefix("git-")
    for gw in sorted(GATEWAY_PREFIXES, key=len, reverse=True):
        prefix = f"{gw}-"
        if raw.startswith(prefix):
            sub = raw.removeprefix(prefix)
            return f"hug {gw} {sub}"
    return f"hug {raw}"


def parse_description_from_help(help_text: str) -> str:
    """Extract one-line description from 'hug <cmd>: <description>' pattern."""
    match = re.search(r"^hug\s+[^:]+:\s*(.+)$", help_text, re.MULTILINE)
    return match.group(1).strip() if match else ""


def _query_script(script_path: Path) -> dict | None:
    """Query a single script for --search-meta and --help."""
    try:
        meta_result = subprocess.run(
            [str(script_path), "--search-meta"],
            capture_output=True, text=True, timeout=5,
        )
        if meta_result.returncode != 0:
            return None
        meta_text = meta_result.stdout.strip()
    except (subprocess.TimeoutExpired, OSError):
        return None

    # Parse category from TOML: category = ["...", "..."]
    categories = []
    cat_match = re.search(r'category\s*=\s*\[(.*?)\]', meta_text)
    if cat_match:
        categories = [
            c.strip().strip('"').strip("'")
            for c in cat_match.group(1).split(",")
            if c.strip()
        ]

    # Skip scripts with empty categories (not yet annotated)
    if not categories:
        return None

    # Extract description from --help
    description = ""
    try:
        help_result = subprocess.run(
            [str(script_path), "--help"],
            capture_output=True, text=True, timeout=5,
        )
        if help_result.returncode == 0:
            description = parse_description_from_help(help_result.stdout)
    except (subprocess.TimeoutExpired, OSError):
        pass

    # Also skip if no description (script has no useful help text)
    if not description:
        return None

    filename = script_path.name
    return {
        "command": derive_command_name(filename),
        "description": description,
        "categories": categories,
        "mtime": script_path.stat().st_mtime,
    }


def _load_cache(cache_file: Path) -> dict:
    """Load the metadata cache from disk."""
    if not cache_file.exists():
        return {}
    try:
        data = json.loads(cache_file.read_text())
        return data if isinstance(data, dict) else {}
    except (json.JSONDecodeError, OSError):
        return {}


def _save_cache(cache_file: Path, data: dict) -> None:
    """Save the metadata cache to disk."""
    cache_file.parent.mkdir(parents=True, exist_ok=True)
    cache_file.write_text(json.dumps(data, indent=2))


def collect_metadata(
    bin_dir: str | Path,
    cache_dir: str | Path = _DEFAULT_CACHE_DIR,
    use_cache: bool = True,
) -> list[CommandInfo]:
    """Collect metadata from all git-* scripts, using cache when possible."""
    bin_path = Path(bin_dir)
    cache_file = Path(cache_dir) / "search-meta.cache"

    # Load cache
    cache = _load_cache(cache_file) if use_cache else {}
    updated = False

    # Scan scripts
    for script_path in sorted(bin_path.glob("git-*")):
        if not script_path.is_file():
            continue
        if not os.access(script_path, os.X_OK):
            continue

        name = script_path.name
        mtime = script_path.stat().st_mtime

        # Check cache freshness
        if use_cache and name in cache:
            cached = cache[name]
            if cached.get("mtime") == mtime:
                continue  # Cache hit

        # Query the script
        result = _query_script(script_path)
        if result:
            cache[name] = result
        elif name in cache:
            del cache[name]  # Script no longer provides metadata
        updated = True

    # Save cache if changed
    if updated:
        _save_cache(cache_file, cache)

    # Build CommandInfo list from cache
    commands = []
    for name, data in cache.items():
        if not data.get("categories") or not data.get("description"):
            continue
        commands.append(CommandInfo(
            command=data["command"],
            description=data["description"],
            categories=data["categories"],
        ))

    return sorted(commands, key=lambda c: c.command)


def search_keyword(commands: list[CommandInfo], query: str) -> list[CommandInfo]:
    """Fuzzy search across description + command name."""
    if not query.strip():
        return []
    scored = []
    for cmd in commands:
        search_fields = [cmd.description, cmd.command.replace("hug ", "")]
        best_score = 0
        for field_text in search_fields:
            score = _fuzzy_score(query, field_text)
            best_score = max(best_score, score)
        if best_score >= MIN_SCORE:
            scored.append((best_score, cmd))
    scored.sort(key=lambda x: x[0], reverse=True)
    return [cmd for _, cmd in scored]


def search_category(commands: list[CommandInfo], query: str) -> list[CommandInfo]:
    """Find commands belonging to a specific category (fuzzy matched)."""
    if not query.strip():
        return []
    results = []
    for cmd in commands:
        for cat in cmd.categories:
            score = _fuzzy_score(query, cat)
            if score >= MIN_SCORE:
                results.append(cmd)
                break
    return results


def list_categories(commands: list[CommandInfo]) -> list[str]:
    """Return sorted list of all categories found across commands."""
    cats = set()
    for cmd in commands:
        cats.update(cmd.categories)
    return sorted(cats)


def format_results(commands: list[CommandInfo]) -> str:
    """Format command results for terminal output."""
    if not commands:
        return "  (none)"
    lines = []
    for cmd in commands:
        desc = cmd.description or "(no description)"
        lines.append(f"  {cmd.command:24s} - {desc}")
    return "\n".join(lines)


def format_category_list(commands: list[CommandInfo]) -> str:
    """Format the full category listing for '@' with no query."""
    cats = list_categories(commands)
    lines = ["Available categories:"]
    for cat in cats:
        count = sum(1 for c in commands if cat in c.categories)
        lines.append(f"  @{cat:16s} ({count} commands)")
    lines.append("")
    lines.append("Use 'hug help @<category>' to see commands in a category.")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Hug help topic search")
    parser.add_argument("mode", choices=["/", "@", "!"], help="Search mode")
    parser.add_argument("query", nargs="?", default="", help="Search query")
    parser.add_argument("--bin-dir", default=_DEFAULT_BIN_DIR, help="Directory with git-* scripts")
    parser.add_argument("--cache-dir", default=_DEFAULT_CACHE_DIR, help="Cache directory")
    args = parser.parse_args()

    commands = collect_metadata(args.bin_dir, cache_dir=args.cache_dir)

    if args.mode == "/":
        if not args.query:
            print("Usage: hug help /<keyword>")
            print("Fuzzy search across command descriptions and names.")
            return
        results = search_keyword(commands, args.query)
        print(f"Keyword search for '{args.query}':")
        print(format_results(results))

    elif args.mode == "@":
        if not args.query:
            print(format_category_list(commands))
            return
        results = search_category(commands, args.query)
        print(f"Commands in category '{args.query}':")
        print(format_results(results))

    elif args.mode == "!":
        # Intent mode uses same logic as keyword (searches description).
        # Kept as separate sigil for API symmetry and future semantic search.
        if not args.query:
            print("Usage: hug help !<intent>")
            print("Find commands by what you want to accomplish.")
            print("Example: hug help !push to remote")
            return
        results = search_keyword(commands, args.query)
        print(f"Commands for '{args.query}':")
        print(format_results(results))


if __name__ == "__main__":
    main()
