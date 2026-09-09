"""Loader for commands.toml — the registry of non-script hug commands.

Mirrors category_meta.py's structure: frozen dataclass, loud validation,
derive_summary reuse. Paths resolve __file__-relative (the
_DEFAULT_BIN_DIR pattern, help_search.py:109) so both repo and installed
layouts work. A missing or corrupt registry is a LOUD error — silent-empty
would shrink the index and the corpus (the exact failure the loader exists
to prevent).
"""

from __future__ import annotations

import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

if sys.version_info >= (3, 11):
    import tomllib  # type: ignore[import-not-found]
else:
    import tomli as tomllib  # type: ignore[no-redef]

from category_meta import derive_summary

DEFAULT_PATH = Path(__file__).resolve().parent / "commands.toml"
DEFAULT_CATEGORIES_DIR = Path(__file__).resolve().parent / "categories"
DEFAULT_BIN_DIR = Path(__file__).resolve().parents[2] / "bin"
DEFAULT_GITCONFIG = Path(__file__).resolve().parents[2] / ".gitconfig"

NAME_RE = re.compile(r"^[a-z][a-z0-9]*(-[a-z0-9]+)*$")
VALID_KINDS = {"alias", "passthrough"}
# 'kind' MUST be listed here: the VALID_KINDS check reads entry["kind"]
# directly, so an omitted kind would otherwise escape validation as a raw
# KeyError instead of a RegistryError with table+key context.
REQUIRED_FIELDS = (
    "kind",
    "description",
    "keywords",
    "categories",
    "git_equivalent",
    "usage",
    "related",
)


class RegistryError(Exception):
    """Loud registry failure: file+table+key context, never silent."""


@dataclass(frozen=True)
class CommandMeta:
    name: str
    kind: str
    description: str
    summary: str
    keywords: list[str]
    categories: list[str]
    git_equivalent: str
    usage: str
    related: list[str]


def _fail(path: Path, table: str, key: str, why: str) -> RegistryError:
    # Interpolate the REAL path: tmp_path probes and non-default installs
    # must point at the actual offending file, not a hardcoded literal.
    return RegistryError(f"{path} [{table}] {key}: {why}")


def _known_categories(categories_dir: Path) -> set[str]:
    return {p.stem for p in categories_dir.glob("*.toml")}


def _bin_scripts(bin_dir: Path) -> set[str]:
    return {p.stem.removeprefix("git-") for p in bin_dir.glob("git-*")}


def _aliases(gitconfig: Path) -> dict[str, str]:
    """One subprocess call total — never per-name (spec: related validation)."""
    out = subprocess.run(
        ["git", "config", "--file", str(gitconfig), "--get-regexp", r"^alias\."],
        capture_output=True,
        text=True,
        check=False,
    ).stdout
    aliases = {}
    for line in out.splitlines():
        key, _, value = line.partition(" ")
        if not key:  # multi-line alias values emit keyless continuation lines
            continue
        aliases[key.removeprefix("alias.")] = value
    return aliases


def load_commands(
    path: Path | None = None,
    categories_dir: Path | None = None,
    bin_dir: Path | None = None,
    gitconfig: Path | None = None,
) -> dict[str, CommandMeta]:
    """Load + validate the registry. Raises RegistryError loudly."""
    path = Path(path or DEFAULT_PATH)
    categories_dir = Path(categories_dir or DEFAULT_CATEGORIES_DIR)
    bin_dir = Path(bin_dir or DEFAULT_BIN_DIR)
    gitconfig = Path(gitconfig or DEFAULT_GITCONFIG)

    if not path.is_file():
        raise RegistryError(f"missing registry file: {path}")
    try:
        raw = tomllib.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # corrupt TOML must be loud, not empty
        raise RegistryError(f"unparsable registry {path}: {exc}") from exc

    known_cats = _known_categories(categories_dir)
    scripts = _bin_scripts(bin_dir)
    aliases: dict[str, str] | None = None  # lazy: one subprocess per load

    # Full name set hoisted BEFORE the loop: related resolution must not
    # depend on table order — an entry may reference a LATER table (a
    # passthrough has no alias/script, so processed-so-far would miss it).
    names = set(raw)

    registry: dict[str, CommandMeta] = {}
    for name, entry in raw.items():
        if not NAME_RE.match(name):
            raise _fail(path, name, "name", f"violates command grammar {NAME_RE.pattern}")
        if not isinstance(entry, dict):
            raise _fail(path, name, "table", "expected a TOML table")
        for field in REQUIRED_FIELDS:
            if field not in entry:
                raise _fail(path, name, field, "missing required field")
        for list_field in ("keywords", "categories", "related"):
            value = entry[list_field]
            if not isinstance(value, list):
                # 'categories = "branching"' would char-gram in the set diff;
                # 'keywords = "tag"' would silently become ['t','a','g'].
                raise _fail(
                    path,
                    name,
                    list_field,
                    f"must be a TOML array of strings, got {type(value).__name__}",
                )
        kind = entry["kind"]
        if kind not in VALID_KINDS:
            raise _fail(path, name, "kind", f"must be one of {sorted(VALID_KINDS)}")
        unknown = set(entry["categories"]) - known_cats
        if unknown:
            raise _fail(path, name, "categories", f"unknown categories {sorted(unknown)}")
        if aliases is None:
            aliases = _aliases(gitconfig)
        for rel in entry["related"]:
            if rel not in names and rel not in scripts and rel not in aliases:
                raise _fail(
                    path,
                    name,
                    "related",
                    f"'{rel}' resolves to no registry entry, bin script, or alias",
                )
        description = entry["description"]
        if not isinstance(description, str) or not description.strip():
            raise _fail(path, name, "description", "must be non-empty prose")
        registry[name] = CommandMeta(
            name=name,
            kind=kind,
            description=description.strip(),  # mirror category_meta: no edge whitespace
            summary=derive_summary(description),
            keywords=list(entry["keywords"]),
            categories=list(entry["categories"]),
            git_equivalent=entry["git_equivalent"],
            usage=entry["usage"],
            related=list(entry["related"]),
        )
    if not registry:
        raise RegistryError(f"{path}: registry is empty — silent-empty is forbidden")
    return registry


if __name__ == "__main__":  # manual probe: uv run command_meta.py
    for name, cmd in load_commands().items():
        print(f"{name}: {cmd.kind} — {cmd.summary}")
