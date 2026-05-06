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
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path

# Fuzzy matching: optional dependency with substring-only fallback.
# WHY four scorers: each searchable field has its own noise profile.
#   _ratio        — strict full-string comparison; right for short curated keywords
#   _partial      — substring partial match; right for short queries vs long names
#   _wratio       — hybrid (length-normalised + token-aware); right for free-text descriptions
#   _token_set    — token-set comparison; ignores word order; right for !intent phrases
try:
    from thefuzz import fuzz as _fuzz

    def _fuzzy_score(query: str, target: str) -> int:
        return _fuzz.partial_ratio(query.lower(), target.lower())

    def _fuzzy_score_strict(query: str, target: str) -> int:
        # ratio() is stricter than partial_ratio — full-string comparison, not substring.
        # Categories are short known strings; partial_ratio over-matches.
        return _fuzz.ratio(query.lower(), target.lower())

    def _ratio(query: str, target: str) -> int:
        return _fuzz.ratio(query.lower(), target.lower())

    def _partial(query: str, target: str) -> int:
        return _fuzz.partial_ratio(query.lower(), target.lower())

    def _wratio(query: str, target: str) -> int:
        return _fuzz.WRatio(query.lower(), target.lower())

    def _token_set(query: str, target: str) -> int:
        return _fuzz.token_set_ratio(query.lower(), target.lower())

    HAS_THEFUZZ = True
except ImportError:
    HAS_THEFUZZ = False

    # Substring-only fallback: 100 if query is a substring of target, else 0.
    # Loses precision but keeps the binary search functional without thefuzz.
    # Per-spec thresholds in KEYWORD_SPECS / INTENT_SPECS still filter via
    # this binary signal — meaning "match" or "no match" with no in-between.
    def _fuzzy_score(query: str, target: str) -> int:
        q, t = query.lower(), target.lower()
        return 100 if q in t else 0

    def _fuzzy_score_strict(query: str, target: str) -> int:
        q, t = query.lower(), target.lower()
        return 100 if q == t else 0

    def _ratio(query: str, target: str) -> int:
        q, t = query.lower(), target.lower()
        return 100 if q == t else 0

    def _partial(query: str, target: str) -> int:
        q, t = query.lower(), target.lower()
        return 100 if q in t else 0

    def _wratio(query: str, target: str) -> int:
        q, t = query.lower(), target.lower()
        return 100 if q in t else 0

    def _token_set(query: str, target: str) -> int:
        # Best-effort token check: 100 if every query word appears in target.
        q_words = set(query.lower().split())
        t_words = set(target.lower().split())
        return 100 if q_words and q_words.issubset(t_words) else 0


# Gateway prefixes: scripts matching git-{X}-* are dispatched through git-{X}
GATEWAY_PREFIXES = {"h", "w"}

# Minimum relevance score for the @category fuzzy-match path.
# /keyword and !intent now use per-spec thresholds in KEYWORD_SPECS / INTENT_SPECS.
# Categories are short known strings; ratio() keeps a single global floor here.
MIN_CATEGORY_SCORE = 60

# Default paths
_DEFAULT_BIN_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "bin")
_DEFAULT_CACHE_DIR = "/tmp/cache/hug"


@dataclass
class CommandInfo:
    """Metadata for a single hug command.

    `keywords` is parsed directly from each script's `--search-meta` output
    (per-command, NOT inherited from the category — see /autoplan F3).
    `category_desc` is hydrated at search time from CategoryMeta.description
    so it can be matched as a search field without re-loading the TOML.
    """

    command: str = ""
    description: str = ""
    categories: list[str] = field(default_factory=list)
    keywords: list[str] = field(default_factory=list)
    category_desc: str = ""


@dataclass(frozen=True)
class MatchSpec:
    """One scoring rule: which field of an item to read, how to score against
    the query, what weight to apply, and what minimum threshold to require.

    The `field` is read via getattr; for list-valued fields (e.g. categories),
    each entry is scored independently — see `_read_field`. The `label` is
    used by --explain output to show why a result matched.
    """

    field: str
    scorer: Callable[[str, str], int]
    weight: float
    min_threshold: int
    label: str


def _read_field(item, field_name: str) -> list[str]:
    """Return zero or more strings for `field_name` on `item`.

    For composite fields (list-valued), returns each entry so each gets
    independently scored. Strings return a single-element list. Anything
    else returns []. Empty strings inside lists are skipped at scoring time.
    """
    val = getattr(item, field_name, "")
    if isinstance(val, str):
        return [val]
    if isinstance(val, (list, tuple)):
        return [str(v) for v in val]
    return []


def run_search(
    query: str,
    items: list,
    specs: list[MatchSpec],
) -> list[tuple[int, object, MatchSpec]]:
    """Run a list of MatchSpec against each item; return sorted best-match list.

    For each item: try every spec, keep the (scaled_score, item, spec) with
    the highest scaled_score that meets its threshold. Sort descending by
    score. Items with no spec meeting threshold are excluded.

    WHY best-spec-per-item: a single result line shows ONE annotation in
    --explain output ("matched on desc"/"matched on @cat-kw"/etc.). Picking
    the highest-scoring spec keeps the annotation honest.
    """
    if not query.strip():
        return []
    out: list[tuple[int, object, MatchSpec]] = []
    for item in items:
        best: tuple[int, object, MatchSpec] | None = None
        for spec in specs:
            for value in _read_field(item, spec.field):
                if not value:
                    continue
                raw = spec.scorer(query, value)
                scaled = int(round(raw * spec.weight))
                if scaled < spec.min_threshold:
                    continue
                if best is None or scaled > best[0]:
                    best = (scaled, item, spec)
        if best is not None:
            out.append(best)
    out.sort(key=lambda x: x[0], reverse=True)
    return out


# Per-spec thresholds: partial_ratio>=70 on a free-text description is a
# noisier signal than ratio>=88 on a curated keyword. Each scorer carries
# its own floor so we tighten precision on noisy fields without losing
# recall on curated ones. Tune as a unit with the T11 quality corpus.
#
# Field semantics:
#   command       — full hug command (e.g. "hug bpush"); ratio for exact-ish,
#                   partial_ratio for substring (caught at lower weight)
#   description   — free-text from --help; WRatio's hybrid scoring fits best
#   category_desc — joined CategoryMeta.description; WRatio for prose
#   keywords      — per-command curated terms; ratio for exact-ish only
#                   (each keyword is a separate match unit, see _read_field)
KEYWORD_SPECS = [
    MatchSpec(field="command", scorer=_ratio, weight=1.00, min_threshold=90, label="name="),
    # name~ weight tuned 0.85→0.95 during T3: at 0.85 a typo like "undoo"
    # against "hug h undo" (partial_ratio=89) scaled to 75 — below floor
    # 80 — losing recall on common typos. 0.95 keeps the down-weight intent
    # ("partial is fuzzier than ratio") while maintaining typo tolerance:
    # 89×0.95 ≈ 84.5 ≥ 80 passes; partial_ratio<84 still rejected.
    MatchSpec(field="command", scorer=_partial, weight=0.95, min_threshold=80, label="name~"),
    MatchSpec(field="description", scorer=_wratio, weight=0.90, min_threshold=80, label="desc"),
    MatchSpec(
        field="category_desc", scorer=_wratio, weight=0.80, min_threshold=80, label="@cat-desc"
    ),
    MatchSpec(field="keywords", scorer=_ratio, weight=0.95, min_threshold=88, label="keywords"),
]


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
    """Extract one-line description from help output.

    Matches both 'hug <cmd>: <desc>' and '<cmd>: <desc>' patterns.
    Some scripts output 'hug h undo: ...' while gateway subcommands
    output just 'h undo: ...' or 'bpush: ...'.
    """
    match = re.search(r"^(?:hug\s+)?([^:\n]+):\s*(.+)$", help_text, re.MULTILINE)
    return match.group(2).strip() if match else ""


def _query_script(script_path: Path) -> dict | None:
    """Query a single script for --search-meta and --help."""
    try:
        meta_result = subprocess.run(
            [str(script_path), "--search-meta"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if meta_result.returncode != 0:
            return None
        meta_text = meta_result.stdout.strip()
    except (subprocess.TimeoutExpired, OSError):
        return None

    # Parse category from TOML: category = ["...", "..."]
    categories = []
    cat_match = re.search(r"category\s*=\s*\[(.*?)\]", meta_text)
    if cat_match:
        categories = [
            c.strip().strip('"').strip("'") for c in cat_match.group(1).split(",") if c.strip()
        ]

    # Skip scripts with empty categories (not yet annotated)
    if not categories:
        return None

    # Parse per-command keywords (optional): keywords = ["...", "..."]
    # Absent line → empty list, which gracefully degrades to description-only
    # scoring for commands that haven't been bootstrapped (see T0.5).
    keywords = []
    kw_match = re.search(r"keywords\s*=\s*\[(.*?)\]", meta_text)
    if kw_match:
        keywords = [
            k.strip().strip('"').strip("'") for k in kw_match.group(1).split(",") if k.strip()
        ]

    # Extract description from --help
    description = ""
    try:
        help_result = subprocess.run(
            [str(script_path), "--help"],
            capture_output=True,
            text=True,
            timeout=5,
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
        "keywords": keywords,
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
    cat_meta: dict | None = None,
) -> list[CommandInfo]:
    """Collect metadata from all git-* scripts, using cache when possible.

    When `cat_meta` is supplied, each command's `category_desc` field is
    hydrated from CategoryMeta.description for scoring against by the
    `@cat-desc` spec. Pass None to skip hydration (tests that don't need
    category descriptions, or environments where the manifests aren't loaded).
    """
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
    for _name, data in cache.items():
        if not data.get("categories") or not data.get("description"):
            continue
        commands.append(
            CommandInfo(
                command=data["command"],
                description=data["description"],
                categories=data["categories"],
                keywords=data.get("keywords", []),
            )
        )

    commands = sorted(commands, key=lambda c: c.command)
    if cat_meta:
        hydrate_category_fields(commands, cat_meta)
    return commands


def hydrate_category_fields(commands: list[CommandInfo], cat_meta: dict) -> None:
    """Populate `category_desc` on each command from CategoryMeta.description.

    Multiple categories per command are joined with " " so a single MatchSpec
    against `category_desc` scores across all of them. CategoryMeta keywords
    are NOT joined into commands — keywords live per-command via the
    `--search-meta` protocol, see /autoplan F3.
    """
    for cmd in commands:
        descs = []
        for cat_name in cmd.categories:
            meta = cat_meta.get(cat_name)
            if meta is not None:
                descs.append(meta.description)
        cmd.category_desc = " ".join(descs)


def search_keyword(
    commands: list[CommandInfo],
    query: str,
    specs: list[MatchSpec] | None = None,
) -> list[CommandInfo]:
    """Precision search via KEYWORD_SPECS (per-field scorers + thresholds).

    Each command is scored against five fields: command name (ratio + partial),
    description, category description, and per-command keywords. The best
    spec wins per command; results sort by score descending.

    Pass `specs` to override the default KEYWORD_SPECS (used by tests).
    """
    return [item for _, item, _ in run_search(query, commands, specs or KEYWORD_SPECS)]


def search_category(commands: list[CommandInfo], query: str) -> list[CommandInfo]:
    """Find commands belonging to a specific category (fuzzy matched)."""
    if not query.strip():
        return []
    results = []
    for cmd in commands:
        for cat in cmd.categories:
            score = _fuzzy_score_strict(query, cat)
            if score >= MIN_CATEGORY_SCORE:
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
