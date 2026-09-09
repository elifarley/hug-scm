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
import textwrap
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from category_meta import CategoryMeta

# Fuzzy matching: optional dependency with substring-only fallback.
# WHY four scorers: each searchable field has its own noise profile.
#   _ratio        — strict full-string comparison; right for short curated keywords
#   _partial      — substring partial match; right for short queries vs long names
#   _wratio       — hybrid (length-normalised + token-aware); right for free-text descriptions
#   _token_set    — token-set comparison; ignores word order; right for !intent phrases
#
# Fallback functions are defined at module level (always present) so tests can
# pin their behavior even when thefuzz is installed. The try/except picks
# which set of names is bound for production use.


def _fb_equal(query: str, target: str) -> int:
    """Fallback for ratio/WRatio: 100 iff strings equal (case-insensitive)."""
    return 100 if query.lower() == target.lower() else 0


def _fb_substring(query: str, target: str) -> int:
    """Fallback for partial_ratio: 100 iff query is a substring of target."""
    return 100 if query.lower() in target.lower() else 0


def _fb_token_subset(query: str, target: str) -> int:
    """Fallback for token_set_ratio: 100 iff every query word appears in target.

    Loses the partial-token tolerance the real scorer has, but pins a
    predictable binary signal for the no-thefuzz path.
    """
    q_words = set(query.lower().split())
    t_words = set(target.lower().split())
    return 100 if q_words and q_words.issubset(t_words) else 0


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
    # Bind production names to the fallback functions defined above.
    # Per-spec thresholds in KEYWORD_SPECS / INTENT_SPECS still filter via
    # the binary 0/100 signal — "match" or "no match" with no in-between.
    _fuzzy_score = _fb_substring
    _fuzzy_score_strict = _fb_equal
    _ratio = _fb_equal
    _partial = _fb_substring
    _wratio = _fb_substring
    _token_set = _fb_token_subset


# Gateway prefixes: scripts matching git-{X}-* are dispatched through git-{X}
GATEWAY_PREFIXES = {"h", "w"}

# Minimum relevance score for the @category fuzzy-match path.
# /keyword and !intent now use per-spec thresholds in KEYWORD_SPECS / INTENT_SPECS.
# Categories are short known strings; ratio() keeps a single global floor here.
MIN_CATEGORY_SCORE = 60

# Default paths
_DEFAULT_BIN_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "bin")
_DEFAULT_CACHE_DIR = "/tmp/cache/hug"
_DEFAULT_CATEGORIES_DIR = os.path.join(os.path.dirname(__file__), "categories")
# The one metadata cache file, by its write path (collect_metadata) and its
# read-only peek path (render_card) — a literal in either would drift.
_CACHE_FILENAME = "search-meta.cache"


@dataclass
class CommandInfo:
    """Metadata for a single hug command.

    `keywords` is parsed directly from each script's `--search-meta` output
    (per-command, NOT inherited from the category — see /autoplan F3).
    `category_desc` is hydrated at search time from CategoryMeta.description
    so it can be matched as a search field without re-loading the TOML.
    `kind` is set only for registry rows merged from commands.toml (Task 2):
    "alias" | "passthrough". None (= script) is the default, so every
    pre-existing construction — all keyword-based — is untouched.
    """

    command: str = ""
    description: str = ""
    categories: list[str] = field(default_factory=list)
    keywords: list[str] = field(default_factory=list)
    category_desc: str = ""
    kind: str | None = None


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


# Intent mode (!) is a genuinely different scorer family from /keyword.
# token_set_ratio ignores word order and tolerates extra words, which fits
# natural-language queries like "!save my work in progress" where the user
# isn't typing precise terms. Lower min_threshold (75 vs /keyword's 80-90)
# because token_set_ratio scores higher on average for partial-token matches
# — same precision target, calibrated to the scorer's distribution.
INTENT_SPECS = [
    MatchSpec(field="description", scorer=_token_set, weight=0.95, min_threshold=75, label="desc"),
    MatchSpec(
        field="category_desc",
        scorer=_token_set,
        weight=0.90,
        min_threshold=75,
        label="@cat-desc",
    ),
    MatchSpec(field="keywords", scorer=_token_set, weight=0.80, min_threshold=75, label="keywords"),
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
    cmd_meta: dict | None = None,
) -> list[CommandInfo]:
    """Collect metadata from all git-* scripts, using cache when possible.

    When `cat_meta` is supplied, each command's `category_desc` field is
    hydrated from CategoryMeta.description for scoring against by the
    `@cat-desc` spec. Pass None to skip hydration (tests that don't need
    category descriptions, or environments where the manifests aren't loaded).

    When `cmd_meta` is supplied (a command_meta.load_commands() registry of
    non-script commands), each entry is merged as a CommandInfo row with
    `kind` set. The merge runs AFTER the cache build — registry rows never
    enter search-meta.cache, so a warm cache still yields them — and BEFORE
    the sort, so the returned list is one alphabetical run rather than a
    sorted script block followed by an appended registry block. Default None
    = no merge, mirroring `cat_meta` so mock-dir tests stay hermetic.
    """
    bin_path = Path(bin_dir)
    cache_file = Path(cache_dir) / _CACHE_FILENAME

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

    if cmd_meta:
        for name, meta in cmd_meta.items():
            # command="hug <name>" is the pinned merge format — the same
            # hug-prefixed string derive_command_name produces for scripts,
            # so the sort key and every rendered line agree (spec C-003).
            # Descriptions are TOML multi-line prose; flatten whitespace so
            # a row renders as ONE listing line (format layers never wrap)
            # while the full prose stays available to fuzzy scoring.
            commands.append(
                CommandInfo(
                    command=f"hug {name}",
                    description=" ".join(meta.description.split()),
                    keywords=list(meta.keywords),
                    categories=list(meta.categories),
                    kind=meta.kind,
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


# Result-shaping defaults. Cap keeps the result list scannable; the soft
# per-category cap nudges variety so a dominant category doesn't crowd out
# niche-but-relevant commands. The penalty is small — a strong direct match
# still beats a weak cross-category match.
DEFAULT_RESULT_CAP = 10
DEFAULT_SOFT_CAT_CAP = 3
DEFAULT_DIVERSIFY_PENALTY = 5


def diversify(
    scored: list[tuple[int, CommandInfo, MatchSpec | None]],
    cap: int | None = DEFAULT_RESULT_CAP,
    soft_cap_per_category: int | None = DEFAULT_SOFT_CAT_CAP,
    penalty: int = DEFAULT_DIVERSIFY_PENALTY,
) -> list[tuple[int, CommandInfo, MatchSpec | None]]:
    """Cap to `cap` results; gently penalise per-category overflow.

    After `soft_cap_per_category` results from the same primary category,
    each additional same-category hit gets `penalty * extra_count` subtracted
    from its score, then the list is re-sorted. Strong direct matches still
    beat weak cross-category hits — the penalty is small and proportional.

    `cap=None` and/or `soft_cap_per_category=None` disable each axis (used
    by `--all`). Primary category = first entry of cmd.categories.
    """
    if soft_cap_per_category is not None:
        seen: dict[str, int] = {}
        adjusted: list[tuple[int, CommandInfo, MatchSpec | None]] = []
        for score, cmd, spec in scored:
            primary = cmd.categories[0] if cmd.categories else ""
            n = seen.get(primary, 0)
            adj = score
            if n >= soft_cap_per_category:
                adj = max(0, score - penalty * (n - soft_cap_per_category + 1))
            adjusted.append((adj, cmd, spec))
            seen[primary] = n + 1
        adjusted.sort(key=lambda x: x[0], reverse=True)
        scored = adjusted
    return scored if cap is None else scored[:cap]


def _run_with_specs(
    commands: list[CommandInfo],
    query: str,
    specs: list[MatchSpec],
    all_results: bool,
) -> tuple[list[tuple[int, CommandInfo, MatchSpec]], int]:
    """Run + diversify; return (capped_tuples, total_before_cap).

    Internal helper used by both search_keyword/search_intent (which discard
    the metadata) and main() (which uses it for --explain annotations and
    the overflow note). Returning the full tuple list + raw count keeps
    every caller working from the same source of truth.
    """
    raw = run_search(query, commands, specs)
    capped = diversify(
        raw,
        cap=None if all_results else DEFAULT_RESULT_CAP,
        soft_cap_per_category=None if all_results else DEFAULT_SOFT_CAT_CAP,
    )
    return capped, len(raw)


def search_keyword(
    commands: list[CommandInfo],
    query: str,
    specs: list[MatchSpec] | None = None,
    *,
    all_results: bool = False,
) -> list[CommandInfo]:
    """Precision search via KEYWORD_SPECS (per-field scorers + thresholds).

    Each command is scored against five fields: command name (ratio + partial),
    description, category description, and per-command keywords. The best
    spec wins per command; results sort by score descending, then are
    diversified + capped to top 10 (override with `all_results=True`).
    """
    capped, _total = _run_with_specs(commands, query, specs or KEYWORD_SPECS, all_results)
    return [item for _, item, _ in capped]


def search_intent(
    commands: list[CommandInfo],
    query: str,
    specs: list[MatchSpec] | None = None,
    *,
    all_results: bool = False,
) -> list[CommandInfo]:
    """Phrase / intent search via INTENT_SPECS (token-aware scoring).

    Multi-word queries like `save my work in progress` are scored with
    token_set_ratio so word order doesn't matter and stopwords don't sink
    the match. Diversified + capped to top 10 by default; pass
    `all_results=True` to disable.
    """
    capped, _total = _run_with_specs(commands, query, specs or INTENT_SPECS, all_results)
    return [item for _, item, _ in capped]


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


def _display_description(cmd: CommandInfo) -> str:
    """Listing text for one command: description plus the registry kind marker.

    Shared by every render site (format_results, format_category_page — and
    Task 3's card related-lines) so a registry row self-explains why `-h`
    isn't hug-flavored identically everywhere. The marker is a render-time
    suffix; descriptions stay pure prose in the TOML.
    """
    desc = cmd.description or "(no description)"
    if cmd.kind:  # registry rows only; scripts keep kind=None
        desc = f"{desc} (git {cmd.kind})"
    return desc


def format_results(
    commands: list[CommandInfo],
    total: int | None = None,
    details: list[tuple[int, CommandInfo, MatchSpec]] | None = None,
    explain: bool = False,
) -> str:
    """Format command results for terminal output.

    When `total` is supplied and exceeds `len(commands)`, an overflow note
    advertises the `--all` flag so users know results were capped.

    When `explain=True` and `details` is supplied, each result line is
    annotated with `[<label>, <score>]` showing which spec produced the
    match. Off by default — keeps the default output clean. Tag identifies
    results by `id()` (CommandInfo is mutable so it's not hashable).
    """
    if not commands:
        return "  (none)"
    detail_map: dict[int, tuple[int, MatchSpec]] = {}
    if details:
        for score, item, spec in details:
            detail_map[id(item)] = (score, spec)
    lines = []
    for cmd in commands:
        line = f"  {cmd.command:24s} - {_display_description(cmd)}"
        if explain and id(cmd) in detail_map:
            score, spec = detail_map[id(cmd)]
            line += f"   [{spec.label}, {score}]"
        lines.append(line)
    if total is not None and total > len(commands):
        lines.append("")
        lines.append(f"  Showing top {len(commands)} of {total}. Pass --all to see all matches.")
    return "\n".join(lines)


def _terminal_width(default: int = 72) -> int:
    """Best-effort terminal width detection.

    Returns os.get_terminal_size().columns when available; falls back to
    `default` when stdout is not a TTY (piped, captured by tests, etc.).
    """
    try:
        return os.get_terminal_size().columns
    except OSError:
        return default


def _rule(title: str, width: int) -> str:
    """Render a horizontal rule with a leading title segment.

    `── <title> ─────────...` total length = width.
    """
    head = f"── {title} "
    return head + "─" * max(0, width - len(head))


def format_category_page(
    meta: "CategoryMeta",
    commands: list[CommandInfo],
    width: int = 72,
    split_streams: bool = False,
) -> "str | tuple[str, str, str]":
    """Render the `hug help @<category>` deep-dive page.

    Layout (width-bounded):

      ── @<name> — <label> ────────────────────────...
      <description paragraph, word-wrapped>
      ── Commands (N) ─────────────────────────────...
        hug a    - description...
        hug bc   - description...
      Tip: `hug help <command>` for full help on any command.

    When `split_streams=True`, returns `(header, data, footer)` as three
    strings so the caller can interleave them across stderr (header,
    footer) and stdout (data) per the project's stdout/stderr discipline.
    Splitting header from footer matters because the caller needs to flush
    `data` to stdout BEFORE the footer hits stderr — otherwise the
    "Tip:" line visually lands before the command list in interactive TTYs.

    Otherwise returns a single combined string for tests / non-TTY use.

    No "Keywords" section: per-category keywords were dropped in B-tweaked
    (they would propagate to destructive sibling commands — see /autoplan
    F3). Per-command keywords surface via /keyword and !intent search,
    not on the category browse page.
    """
    width = max(40, min(width, 100))

    header: list[str] = [_rule(f"@{meta.name} — {meta.label}", width), ""]
    if meta.description:
        # textwrap collapses internal whitespace; flatten newlines so the
        # description renders as one re-wrapped paragraph regardless of how
        # the author hard-wrapped it in the TOML.
        header += textwrap.wrap(meta.description.replace("\n", " ").strip(), width=width)
    header += ["", _rule(f"Commands ({len(commands)})", width), ""]

    data_lines: list[str] = []
    for cmd in commands:
        data_lines.append(f"  {cmd.command:24s} - {_display_description(cmd)}")

    footer = ["", "Tip: `hug help <command>` for full help on any command."]

    if split_streams:
        return (
            "\n".join(header).rstrip("\n"),
            "\n".join(data_lines),
            "\n".join(footer).lstrip("\n"),
        )

    return "\n".join(header + data_lines + footer)


def format_category_list(
    commands: list[CommandInfo],
    cat_meta: dict | None = None,
) -> str:
    """Format the full category listing for '@' with no query.

    When `cat_meta` is supplied, each line is enriched with the category's
    one-line summary (CategoryMeta.summary). Without cat_meta, falls back
    to the bare `@<name>  (count)` shape — keeps the function usable in
    tests and contexts without manifests loaded.
    """
    cats = list_categories(commands)
    if not cats:
        return "Available categories: (none)"

    name_w = max(len(c) for c in cats)
    counts = {c: sum(1 for cmd in commands if c in cmd.categories) for c in cats}
    count_w = max(len(str(n)) for n in counts.values())

    lines = ["Available categories:", ""]
    for cat in cats:
        meta = (cat_meta or {}).get(cat)
        summary = meta.summary if meta else ""
        sep = "  — " if summary else ""
        lines.append(f"  @{cat:<{name_w}}  ({counts[cat]:>{count_w}}){sep}{summary}".rstrip())
    lines += [
        "",
        "Tips:",
        "`hug help @<category>` to learn about a category and list its commands.",
        "`hug help /<keyword>` for keyword search.",
        "`hug help '!<intent>'` for natural-language search.",
    ]
    return "\n".join(lines)


def _silence_stdout() -> None:
    """Point fd 1 at devnull so no later stdout write can fail.

    The shared mitigation behind every quiet stdout-failure path: buffered
    leftovers and the interpreter-shutdown flush become harmless. Exit
    semantics stay at the call sites (os._exit(0) in the flush guard and
    the __main__ guard; return 0 in render_card's BrokenPipeError handler).
    """
    os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())


def _flush_stdout_quietly() -> None:
    """Flush stdout; on write failure end the process quietly at exit 0.

    BrokenPipeError (dead pipe) AND other stdout write failures (/dev/full →
    ENOSPC) share this posture: silence stdout, then os._exit(0). SCOPE IS
    DELIBERATE: only the flush is guarded. Pipeline failures elsewhere in
    main() (unwritable cache dir, ...) are NOT caught here — the __main__
    guard stays BrokenPipeError-only so they propagate loudly (exit 1);
    this helper runs solely for an actual stdout flush failure.
    """
    try:
        sys.stdout.flush()
    except OSError:
        _silence_stdout()
        os._exit(0)


# Cache-sourced text is UNTRUSTED INPUT: strip ANSI escape sequences (CSI —
# cursor/color/etc.; OSC including OSC 52 clipboard writes, terminated by
# BEL or ST) and C0 control bytes + DEL before any of it reaches a terminal.
# First-party registry prose never passes through here.
# LESSON (alternation order): the escape-sequence alternatives MUST come
# before the bare control class — a leading [\x00-\x1f] matches the ESC
# byte alone, consuming it before the CSI/OSC arms can see the sequence and
# leaving "[2J"-style tails behind (caught by the sanitizer test).
_UNTRUSTED_TEXT_RE = re.compile(
    r"(\x1b\[[0-9;:]*[a-zA-Z])|(\x1b\][^\x07\x1b]*(\x07|\x1b\\))|[\x00-\x1f\x7f]"
)


def _strip_control_chars(text: str) -> str:
    """Strip control bytes and ANSI CSI/OSC escape sequences from text."""
    return _UNTRUSTED_TEXT_RE.sub("", text)


def render_card(
    name: str,
    registry: dict | None = None,
    commands_path: str | Path | None = None,
    cache_dir: str | Path | None = None,
) -> int:
    """Render the hug card for a registry-owned name.

    Exit contract: 0 card | 4 miss (EXCLUSIVELY) | >=2 loud. WHY 4, not 1:
    uv itself can exit 1 BEFORE this script runs (environment creation or
    update failure — offline first run, dependency/build error), so exit 1
    must mean LOUD for the bash caller and never be read as a miss. Python
    also exits 1 on any bare crash — the same code — so EVERY unexpected
    exception is caught and re-mapped to 3 with a stderr message: a card bug
    must never masquerade as a registry miss (that confusion is what would
    silently degrade `hug help <name>` to legacy help).

    Pure function over the loaded registry + a READ-ONLY cache peek. Card
    rendering never calls collect_metadata — no per-script metadata queries,
    no cache writes (_save_cache is forbidden here); the one registry load
    itself does a single alias scan — so `hug help <name>` stays fast and
    side-effect-free.
    """
    try:
        if registry is None:
            # Lazy import mirrors main()'s pattern: keeps help_search
            # importable even if command_meta has an issue.
            from command_meta import RegistryError, load_commands

            try:
                registry = load_commands(path=commands_path)
            except RegistryError as exc:
                # Corrupt/missing registry is loud, and >=2 so it can never
                # be misread as the exit-4 miss.
                print(f"error: {exc}", file=sys.stderr)
                return 2
        cmd = registry.get(name)
        if cmd is None:
            return 4  # miss — EXCLUSIVELY 4; 1 is loud (uv can exit 1 before we run)

        # Full flags point at git_equivalent's LEADING command, not the hug
        # name: `git help bpullr` prints an alias notice, `git help pull` is
        # what actually documents the flags.
        parts = cmd.git_equivalent.split()
        full_flags_target = parts[1] if parts[:1] == ["git"] else cmd.git_equivalent
        lines = [
            f"hug {name} — (git {cmd.kind})",
            "",
            cmd.summary,
            "",
            cmd.description,
            "",
            f"Usage: {cmd.usage}",
            f"Git equivalent: {cmd.git_equivalent}",
            f"Full flags: git help {full_flags_target}",
            "",
            "Related:",
        ]
        # Read-only peek for best-effort related summaries. Keyed by script
        # FILENAME `git-<name>` — the same key _save_cache writes; never
        # written here (a card must not mutate the cache it reads).
        peek = _load_cache(Path(cache_dir) / _CACHE_FILENAME) if cache_dir is not None else {}
        for rel in cmd.related:
            rel_meta = registry.get(rel)
            if rel_meta:  # registry-owned related: use the loaded summary
                lines.append(f"  hug {rel} — {rel_meta.summary}")
                continue
            # Script/alias related: cached description if one is present.
            # Cache values are untrusted JSON — only a non-empty STRING may
            # be rendered; anything else (number, null, "") degrades to the
            # bare hint instead of leaking junk into the card or turning a
            # render into a loud exit. The hint is also the ONLY card text
            # originating outside this repo, so control bytes and ANSI
            # escapes are stripped (registry summaries above are first-party
            # prose and skip the sanitizer).
            cached = peek.get(f"git-{rel}")
            hint = cached.get("description") if isinstance(cached, dict) else None
            if isinstance(hint, str) and hint:
                lines.append(f"  hug {rel} — {_strip_control_chars(hint)}")
            else:
                lines.append(f"  hug {rel}")
        print("\n".join(lines))
        return 0
    except BrokenPipeError:
        # In-body raises are handled here; the shutdown-flush case is handled
        # by the module-level guard below (both end at devnull + exit 0).
        _silence_stdout()
        return 0
    except KeyboardInterrupt:
        raise  # unwrapped: the shell sees 130 — never the exit-3 catch-all
    except Exception as exc:
        # Python exits 1 on a bare crash — that code is RESERVED for miss, so
        # map ANY unexpected exception to >=2 loudly.
        print(f"error: card render failed: {exc}", file=sys.stderr)
        return 3


def main():
    parser = argparse.ArgumentParser(description="Hug help topic search")
    parser.add_argument("mode", choices=["/", "@", "!", ":", "card"], help="Search mode")
    # Card mode carries the command name in this same positional — argparse's
    # greedy left-to-right match gives the FIRST optional positional every
    # value, so a separate trailing `name` positional could never receive one
    # (probed: `card -- fetch` yields query='fetch', name=None).
    parser.add_argument(
        "query", nargs="?", default="", help="Search query (card mode: exact command name)"
    )
    parser.add_argument("--bin-dir", default=_DEFAULT_BIN_DIR, help="Directory with git-* scripts")
    parser.add_argument("--cache-dir", default=_DEFAULT_CACHE_DIR, help="Cache directory")
    parser.add_argument(
        "--categories-dir",
        default=_DEFAULT_CATEGORIES_DIR,
        help="Directory containing per-category TOML manifests",
    )
    parser.add_argument(
        "--articles-dir",
        default=os.path.join(os.path.dirname(__file__), "articles"),
        help="Directory containing article markdown files",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Disable result cap and per-category diversification.",
    )
    parser.add_argument(
        "--explain",
        action="store_true",
        help="Annotate each result with the matching field and score.",
    )
    args = parser.parse_args()

    if args.mode == "card":
        # Card bypasses the search pipeline below entirely: no categories
        # load, no script scan, NO collect_metadata — it renders from the
        # registry + a read-only cache peek alone. It also owns a DIFFERENT
        # exit posture (miss=4, anything broken >=2 via render_card — 1 is
        # reserved for uv's own launcher failures), so the search modes'
        # loud-but-exit-1 handling must never see card failures. The name
        # rides in `query` (see the positional above).
        rc = render_card(args.query, commands_path=None, cache_dir=args.cache_dir)
        # Quiet-flush BEFORE sys.exit: SystemExit would skip the __main__
        # guard's flush line, and card-sized output usually fits the stdout
        # buffer — the failure would then surface only at interpreter
        # finalization (probed: exit 120) where no except can see it. The
        # helper owns the write-failure posture (devnull + exit 0) so a dead
        # pipe AND /dev/full both stay a quiet 0.
        _flush_stdout_quietly()
        sys.exit(rc)

    # HUG_HELP_EXPLAIN=1 enables --explain via env var (handy when wrapping
    # `hug help` in shell aliases or scripts that can't easily pass flags).
    explain = args.explain or os.environ.get("HUG_HELP_EXPLAIN") == "1"

    # Load category manifests. Loader errors (malformed TOML, missing
    # required fields) are surfaced as hard failures — these mean the
    # repository state is broken and we should refuse to operate rather
    # than silently dropping the affected category.
    from category_meta import load_categories, validate_against_scripts

    try:
        cat_meta = load_categories(args.categories_dir)
    except FileNotFoundError:
        print(
            f"error: categories directory not found: {args.categories_dir}",
            file=sys.stderr,
        )
        sys.exit(1)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)

    # Load the non-script command registry (commands.toml). WHY bare defaults:
    # the CLI exposes no registry flag, and command_meta's __file__-relative
    # defaults resolve identically in repo and installed layouts — the same
    # shipped file this module's _DEFAULT_* constants anchor to. A corrupt
    # registry is loud, same posture as categories: silent-empty would shrink
    # the index and every search answer with it. Article mode (":") renders
    # prose from articles_loader and never reads the registry, so it skips
    # this block entirely — no TOML parse, no alias-scan subprocess.
    cmd_registry = None
    if args.mode != ":":
        from command_meta import RegistryError, load_commands

        try:
            cmd_registry = load_commands()
        except RegistryError as exc:
            print(f"error: {exc}", file=sys.stderr)
            sys.exit(1)  # search-mode posture: mirrors the categories sys.exit(1)

    commands = collect_metadata(
        args.bin_dir, cache_dir=args.cache_dir, cat_meta=cat_meta, cmd_meta=cmd_registry
    )

    # Strict validation: every category referenced by a script MUST have a
    # manifest. Catches the most likely drift mode (a contributor adds a
    # category to a script without bootstrapping the corresponding TOML).
    # Script rows only (kind is None): registry categories were already
    # validated at load time against the canonical categories/ dir, and
    # dragging them in here would fail fixture invocations whose
    # --categories-dir legitimately holds a partial manifest set.
    used_categories = {c for cmd in commands if cmd.kind is None for c in cmd.categories}
    errors = validate_against_scripts(cat_meta, used_categories)
    if errors:
        for err in errors:
            print(f"error: {err}", file=sys.stderr)
        sys.exit(1)

    if args.mode == "/":
        if not args.query:
            print("Usage: hug help /<keyword>")
            print("Fuzzy search across command descriptions and names.")
            return
        capped, total = _run_with_specs(commands, args.query, KEYWORD_SPECS, args.all)
        results = [item for _, item, _ in capped]
        print(f"Keyword search for '{args.query}':")
        print(format_results(results, total=total, details=capped, explain=explain))

    elif args.mode == "@":
        if not args.query:
            print(format_category_list(commands, cat_meta=cat_meta))
            return
        # First try an exact name hit; CategoryMeta has the boxed-page data.
        meta = cat_meta.get(args.query) if cat_meta else None
        if meta is not None:
            cmds_in_cat = [c for c in commands if meta.name in c.categories]
            header, data, footer = format_category_page(
                meta, cmds_in_cat, width=_terminal_width(), split_streams=True
            )
            # Decorative chatter → stderr; command list → stdout. Header
            # first, then data, then footer — flushing in that order so the
            # tip ("Tip: hug help <command>...") visually follows the
            # commands rather than preceding them. Keeps `hug help
            # @branching | grep bpush` pipe-safe (only data hits stdout).
            print(header, file=sys.stderr, flush=True)
            if data:
                print(data, flush=True)
            print(footer, file=sys.stderr, flush=True)
            return
        # Fall back to fuzzy category-name match for typos / partial names.
        # No boxed page in this path — search_category returns potentially
        # multiple categories, so we render the legacy listing instead.
        results = search_category(commands, args.query)
        print(f"Commands in category '{args.query}':")
        print(format_results(results))

    elif args.mode == "!":
        # Intent mode is now token-aware via INTENT_SPECS — distinct from
        # /keyword's per-field precision scoring. T4 promoted ! from a
        # /keyword alias to its own search path.
        if not args.query:
            print("Usage: hug help !<intent>")
            print("Find commands by what you want to accomplish.")
            print("Example: hug help '!push to remote'")
            return
        capped, total = _run_with_specs(commands, args.query, INTENT_SPECS, args.all)
        results = [item for _, item, _ in capped]
        print(f"Commands for '{args.query}':")
        print(format_results(results, total=total, details=capped, explain=explain))

    elif args.mode == ":":
        # Article mode: load articles, dispatch by query presence.
        # WHY a separate branch (not folded into / @ !): articles are a
        # different content model (long-form prose, not commands), with
        # a different storage model (markdown files vs script metadata)
        # and different output (rendered body vs scored result lines).
        # Sharing the dispatcher keeps the user-facing UX coherent
        # (single `hug help <sigil>` surface), but the inner pipeline
        # belongs in articles_loader.
        #
        # WHY lazy import here (not at module top): mirrors the existing
        # lazy `from category_meta import ...` pattern in this function.
        # Keeps help_search.py importable even if articles_loader.py has
        # an issue (defense in depth), and avoids paying import cost for
        # every / @ ! invocation that doesn't need articles.
        from articles_loader import (
            find_article,
            format_article_list,
            load_articles,
            render_article,
        )

        # WHY only ValueError (not FileNotFoundError as load_categories does):
        # load_articles returns [] for a missing/non-existent directory rather
        # than raising — articles are an opt-in feature, absence is not an error.
        # Only schema violations (malformed frontmatter, oversize summary, etc.)
        # surface as ValueError. See Task 2's load_articles contract.
        try:
            articles = load_articles(args.articles_dir)
        except ValueError as exc:
            print(f"error: {exc}", file=sys.stderr)
            sys.exit(1)

        if not args.query:
            # Listing: route streams per stdout/stderr discipline.
            # Header/footer (chatter) → stderr; slug list (data) → stdout.
            header, body, footer = format_article_list(articles, width=_terminal_width())
            print(header, file=sys.stderr, flush=True)
            if body:
                print(body, flush=True)
            if footer:  # empty for "no articles" empty-list path; guard avoids spurious blank line
                print(footer, file=sys.stderr, flush=True)
            return

        result = find_article(articles, args.query)
        if result.found is not None:
            render_article(result.found)
            return

        # Unknown slug: print informative error with fuzzy suggestions.
        print(f"error: no article named ':{args.query}'", file=sys.stderr)
        if result.suggestions:
            print("", file=sys.stderr)
            print("Did you mean:", file=sys.stderr)
            for s in result.suggestions:
                print(f"  :{s.slug}  — {s.summary}", file=sys.stderr)
        # WHY exit 1 even when no suggestions: a slug that doesn't exist is an
        # unambiguous error (unlike @<category>'s fuzzy fallback, which may
        # legitimately return no matches as part of a "best-effort" listing).
        # Shell scripts checking `hug help :foo` should be able to detect failure.
        sys.exit(1)


if __name__ == "__main__":
    try:
        rc = main()
        _flush_stdout_quietly()  # LOAD-BEARING: for buffered (card-sized) output
        # the EPIPE fires only here (or at interpreter finalization, which no
        # except can see — probed exit 120). Flushing INSIDE the try via the
        # helper surfaces it to the quiet path; the subsequent shutdown flush
        # writes an empty buffer to devnull-safe stdout.
        sys.exit(rc)
    except BrokenPipeError:
        # BrokenPipeError ONLY — never OSError. A broad `except OSError` here
        # (review regression) converted search-mode pipeline failures (probed:
        # unwritable cache dir → rc 0, EMPTY output) into silent success; those
        # MUST propagate loudly (exit 1 + traceback, the pre-existing posture).
        # Only an in-body EPIPE — output bigger than the stdout buffer, raised
        # mid-main — lands here; smaller ones fail the helper's flush above.
        _silence_stdout()
        os._exit(0)
