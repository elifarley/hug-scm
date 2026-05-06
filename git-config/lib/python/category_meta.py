"""Per-category metadata loader for `hug help`.

Each category has one TOML file under ./categories/<name>.toml with:
  label       — short title for headers (e.g. "Branch operations")
  description — multi-line paragraph; first sentence ≤ 70 chars
                becomes the summary column in `hug help @`

Keywords are NOT stored here — they live per-command via the existing
`--search-meta` protocol on each script. Splitting the layers prevents
category-level keyword pollution: a `save` keyword on `parking` would
otherwise propagate to every parking command, including destructive
siblings like `wipdel`. See the /autoplan dual-voice review (F3) and
the design doc revision note for the full rationale.

WHY a separate module: keeps loader/validator/IO out of help_search.py,
which stays focused on search. Easier to test in isolation; clean module
boundary if other tooling (a future `hug help-meta lint` command, a
shell-completion generator, etc.) wants to consume the loader.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

# tomllib is stdlib in 3.11+; tomli is the backport for older Pythons.
# The project's pyproject.toml already pins `tomli>=2.0.0` for python<3.11.
if sys.version_info >= (3, 11):
    import tomllib  # type: ignore[import-not-found]
else:
    import tomli as tomllib  # type: ignore[no-redef]

# Summary cap matches the @ listing column width budget. Tune in concert
# with the column padding logic in help_search.format_category_list.
SUMMARY_MAX = 70

# Sentence terminator: `.`, `!`, or `?` followed by whitespace.
# Used to split off the first sentence for the summary column.
_SENTENCE_END = re.compile(r"(?<=[.!?])\s+")


@dataclass(frozen=True)
class CategoryMeta:
    """Loaded metadata for one category.

    `name` is the filename stem (also the canonical category identifier
    used by `_hug_category` in scripts). `summary` is derived from
    `description` at load time so consumers don't recompute it.
    """

    name: str
    label: str
    description: str
    summary: str


def derive_summary(description: str, max_len: int = SUMMARY_MAX) -> str:
    """Return the first sentence of `description`, truncated to <= max_len.

    Truncation falls back on a word boundary with a U+2026 ellipsis so
    the summary column never breaks mid-word. Empty input returns "".

    WHY first-sentence: the @ listing summary column has limited width;
    the first sentence is almost always the most distilling. Authors who
    care about the exact summary string can write a description whose
    first sentence reads well in isolation.
    """
    text = description.strip()
    if not text:
        return ""
    first = _SENTENCE_END.split(text, maxsplit=1)[0].strip()
    if len(first) <= max_len:
        return first
    # Truncate on a word boundary, append U+2026 horizontal ellipsis.
    cut = first[: max_len - 1].rsplit(" ", 1)[0]
    return f"{cut}…"


def load_categories(directory: str | Path) -> dict[str, CategoryMeta]:
    """Load every <name>.toml under `directory` into a dict keyed by name.

    Raises ValueError on schema violations (missing fields), with the
    manifest path embedded in the message so the user can fix it.

    The dict ordering mirrors `Path.glob` sorted output, which keeps
    test assertions stable across runs.
    """
    base = Path(directory)
    out: dict[str, CategoryMeta] = {}
    for path in sorted(base.glob("*.toml")):
        with path.open("rb") as fh:
            data = tomllib.load(fh)

        if "label" not in data:
            raise ValueError(f"{path}: missing 'label'")
        if "description" not in data:
            raise ValueError(f"{path}: missing 'description'")

        name = path.stem
        out[name] = CategoryMeta(
            name=name,
            label=str(data["label"]),
            description=str(data["description"]).strip(),
            summary=derive_summary(str(data["description"])),
        )
    return out


def validate_against_scripts(
    categories: dict[str, CategoryMeta],
    used_categories: set[str],
) -> list[str]:
    """Return a list of error strings; empty list == OK.

    Strict policy: each category referenced by some script MUST have a
    manifest. Orphan manifests (no script references them) are silently
    allowed — they may be placeholders for upcoming commands. Flip
    orphans to errors later if drift becomes a problem.
    """
    missing = sorted(used_categories - categories.keys())
    return [
        f"category '{name}' is referenced by a script "
        f"but has no manifest at categories/{name}.toml"
        for name in missing
    ]
