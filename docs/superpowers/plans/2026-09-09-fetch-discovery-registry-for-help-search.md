# Fetch-Discovery Registry for the Hug Help System — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every non-script hug command (`fetch` passthrough, `bpull`, `bpullr`, `pullall`, `tpull`, `tpullf`, `bs`) discoverable through all four help sigils and render a hug-flavored card for exact-name help.

**Architecture:** A static TOML registry (`commands.toml`) loaded by `command_meta.py` (mirroring `categories/*.toml` + `category_meta.py`) merges into `help_search`'s `CommandInfo` index before the sort; `git-hughelp` gains a strict script → card → alias precedence chain with a single-owned exit contract (0 card / 1 miss / ≥2 loud, BrokenPipe → devnull+0). Spec: `docs/superpowers/specs/2026-09-08-fetch-discovery-registry-for-help-search-design.md` (4 roast rounds, HEAD c883607d) — the spec is the contract; this plan transcribes it into tasks.

**Tech Stack:** Bash (git-hughelp), Python 3.10+ stdlib + `tomli`/`tomllib` + optional `thefuzz` (existing), pytest (lib/python/tests), BATS (tests/integration). All commands run from the worktree root with `HUG_HOME` pinned (test_helper does this for BATS; pytest uses `REPO = Path(__file__).resolve().parents[4]`).

**Worktree:** `/home/ecc/src/hug-scm.WT.fetch-discovery-registry-for-help-search` (branch `fetch-discovery-registry-for-help-search`). Do ALL work there; prefix commands with `cd` inside each compound Bash call.

---

### Task 1: Registry data + `command_meta.py` loader (with drift tests)

**Goal:** Create the 7-entry `commands.toml` and its validating loader, plus the two drift-test guarantees (alias resolution+semantics; no hug-bin shadowing + PATH-free branch ①).

**Files:**
- Create: `git-config/lib/python/commands.toml`
- Create: `git-config/lib/python/command_meta.py`
- Create: `git-config/lib/python/tests/test_command_meta.py`

**Acceptance Criteria:**
- [ ] `load_commands()` returns 7 entries; each has a derived `summary` = first sentence of `description` via `category_meta.derive_summary`
- [ ] Loader raises `RegistryError` (with file+table+key context) on: name failing `^[a-z][a-z0-9]*(-[a-z0-9]+)*$`, bad `kind`, unknown category, missing required field, `related` entry resolving to neither registry sibling, bin script, nor `.gitconfig` alias, missing file
- [ ] Drift 1: every alias-kind entry resolves in `.gitconfig` AND its `git_equivalent` tokens appear in the resolved alias body
- [ ] Drift 2: no registry name is a `git-config/bin/git-*` script; `git-hughelp` source contains both `-x "$dir/git-$prefix"` and the `$dir/git-$prefix`-prefixed invocation (no exec-path/PATH probes — deliberately, per spec)
- [ ] `pytest git-config/lib/python/tests/test_command_meta.py -v` green

**Verify:** `cd git-config/lib/python && uv run --extra search pytest tests/test_command_meta.py -v` → all pass

**Steps:**

- [ ] **Step 1: Write `git-config/lib/python/commands.toml`** (complete content — first sentences ≤70 chars so derived summaries don't truncate):

```toml
# Registry of non-script hug commands (git-aliases + dispatcher passthroughs).
# Loaded by command_meta.py; merged into help_search's CommandInfo index.
# Contract: docs/superpowers/specs/2026-09-08-fetch-discovery-registry-for-help-search-design.md
# Rules: name matches ^[a-z][a-z0-9]*(-[a-z0-9]+)*$; kind is "alias"|"passthrough";
# categories must exist under categories/; related must resolve (registry|script|alias);
# summary is DERIVED from description's first sentence — no summary field.

[fetch]
kind = "passthrough"
description = """Download new commits and refs from remotes without merging.
Does not touch your working tree or local branches — follow with hug bpull,
hug bpullr, or hug mff to integrate. Fetches before basing new work on
origin/main (see hug help :worktree)."""
keywords = ["fetch", "download", "sync", "update", "remote", "refs"]
categories = ["push-pull"]
git_equivalent = "git fetch"
usage = "hug fetch [--tags] [--prune] [<remote> [<refspec>...]]"
related = ["bpull", "bpullr", "tpull", "llu"]

[bpull]
kind = "alias"
description = """Fast-forward-only pull; fails if a merge or rebase would be needed.
The safe default for integrating upstream when your branch has no local commits
diverged from upstream."""
keywords = ["pull", "update", "integrate"]
categories = ["push-pull"]
git_equivalent = "git pull --ff-only"
usage = "hug bpull"
related = ["fetch", "bpullr", "mff"]

[bpullr]
kind = "alias"
description = """Pull with rebase: replay local commits on upstream for linear history."""
keywords = ["pull", "rebase", "update", "integrate"]
categories = ["push-pull"]
git_equivalent = "git pull --rebase"
usage = "hug bpullr"
related = ["fetch", "bpull", "rb"]

[pullall]
kind = "alias"
description = """Fetch from all remotes, then update the current branch's upstream.
Does NOT pull every branch — only the current branch integrates."""
keywords = ["all", "every", "remote"]
categories = ["push-pull"]
git_equivalent = "git pull --all"
usage = "hug pullall"
related = ["fetch", "bpull"]

[tpull]
kind = "alias"
description = """Fetch tags from the remote."""
keywords = ["tag", "download"]
categories = ["push-pull", "tags"]
git_equivalent = "git fetch --tags"
usage = "hug tpull"
related = ["fetch", "tpullf", "t"]

[tpullf]
kind = "alias"
description = """Force fetch tags and prune stale ones."""
keywords = ["tag", "prune", "force"]
categories = ["push-pull", "tags"]
git_equivalent = "git fetch --tags --prune --prune-tags --force"
usage = "hug tpullf"
related = ["tpull", "fetch"]

[bs]
kind = "alias"
description = """Switch back to the previous branch."""
keywords = ["previous", "back", "toggle", "last"]
categories = ["branching"]
git_equivalent = "git switch -"
usage = "hug bs"
related = ["b", "bc"]
```

- [ ] **Step 2: Write the failing loader tests** — `git-config/lib/python/tests/test_command_meta.py`:

```python
"""Tests for command_meta: registry loading, validation, drift guarantees.

Drift 2b note: we assert git-hughelp's SOURCE form (the -x existence test and
the $dir/-prefixed invocation), NOT exec-path/PATH probes — registry names MAY
collide with git-core dashed builtins (fetch does) by design.
"""
import re
import shutil
from pathlib import Path

import pytest

from command_meta import RegistryError, load_commands

REPO = Path(__file__).resolve().parents[4]
PY_DIR = REPO / "git-config" / "lib" / "python"
CATS = PY_DIR / "categories"
GITCONFIG = REPO / "git-config" / ".gitconfig"
HUGHELP = REPO / "git-config" / "bin" / "git-hughelp"
BIN = REPO / "git-config" / "bin"

REQUIRED = {"kind", "description", "keywords", "categories",
            "git_equivalent", "usage", "related"}


@pytest.fixture(scope="module")
def registry():
    return load_commands(categories_dir=CATS, bin_dir=BIN, gitconfig=GITCONFIG)


def test_loads_seven_entries(registry):
    assert set(registry) == {"fetch", "bpull", "bpullr", "pullall",
                             "tpull", "tpullf", "bs"}


def test_every_entry_has_required_fields(registry):
    for name, cmd in registry.items():
        for field in REQUIRED:
            assert getattr(cmd, field) is not None, (name, field)


def test_summary_derived_from_first_sentence(registry):
    assert registry["fetch"].summary.startswith(
        "Download new commits and refs from remotes without merging")
    assert len(registry["bs"].summary) <= 70


def test_name_grammar_rejects_bad_names(tmp_path):
    src = (PY_DIR / "commands.toml").read_text()
    bad = tmp_path / "commands.toml"
    bad.write_text(src + '\n[Bad Name]\nkind = "alias"\n')
    with pytest.raises(RegistryError, match="name"):
        load_commands(path=bad, categories_dir=CATS, bin_dir=BIN,
                      gitconfig=GITCONFIG)


def test_missing_file_is_loud(tmp_path):
    with pytest.raises(RegistryError):
        load_commands(path=tmp_path / "nope.toml", categories_dir=CATS,
                      bin_dir=BIN, gitconfig=GITCONFIG)


def test_unknown_category_rejected(tmp_path):
    src = (PY_DIR / "commands.toml").read_text()
    bad = tmp_path / "commands.toml"
    bad.write_text(src.replace('categories = ["push-pull"]',
                               'categories = ["nope"]', 1))
    with pytest.raises(RegistryError, match="categor"):
        load_commands(path=bad, categories_dir=CATS, bin_dir=BIN,
                      gitconfig=GITCONFIG)


# ── Drift guarantees ─────────────────────────────────────────────────────

def test_drift1_alias_resolution_and_semantics(registry):
    body_by_alias = dict(
        re.findall(r"^  ([a-z0-9-]+) = (.+)$", GITCONFIG.read_text(), re.M))
    for name, cmd in registry.items():
        if cmd.kind != "alias":
            continue
        body = body_by_alias.get(name)
        assert body, f"alias {name} missing from .gitconfig"
        toks = [t for t in cmd.git_equivalent.split() if t != "git"]
        missing = [t for t in toks if t not in body]
        assert not missing, f"{name}: git_equivalent tokens {missing} not in alias body {body!r}"


def test_drift2a_no_hug_bin_shadowing(registry):
    # strip the git- prefix: stem alone yields 'git-bpush', never matching
    # registry keys ('bpush') — the intersection would be vacuously empty.
    scripts = {p.stem.removeprefix("git-") for p in BIN.glob("git-*")}
    assert not (set(registry) & scripts)


def test_drift2b_branch1_is_pathfree_source():
    src = HUGHELP.read_text()
    assert '-x "$dir/git-$prefix"' in src          # existence test on hug's bin dir
    assert '"$dir/git-$prefix" --help' in src      # $dir/-prefixed invocation
```

- [ ] **Step 3: Run tests → FAIL** (`ModuleNotFoundError: command_meta` and/or drift-2b asserting against the unmodified git-hughelp).

Run: `cd git-config/lib/python && uv run --extra search pytest tests/test_command_meta.py -v`

- [ ] **Step 4: Write `git-config/lib/python/command_meta.py`**:

```python
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
    import tomllib
else:
    import tomli as tomllib

from category_meta import derive_summary

DEFAULT_PATH = Path(__file__).resolve().parent / "commands.toml"
DEFAULT_CATEGORIES_DIR = Path(__file__).resolve().parent / "categories"
DEFAULT_BIN_DIR = Path(__file__).resolve().parents[2] / "bin"
DEFAULT_GITCONFIG = Path(__file__).resolve().parents[2] / ".gitconfig"

NAME_RE = re.compile(r"^[a-z][a-z0-9]*(-[a-z0-9]+)*$")
VALID_KINDS = {"alias", "passthrough"}
REQUIRED_FIELDS = ("description", "keywords", "categories",
                   "git_equivalent", "usage", "related")


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


def _fail(table: str, key: str, why: str) -> "RegistryError":
    return RegistryError(f"commands.toml [{table}] {key}: {why}")


def _known_categories(categories_dir: Path) -> set[str]:
    return {p.stem for p in categories_dir.glob("*.toml")}


def _bin_scripts(bin_dir: Path) -> set[str]:
    return {p.stem.removeprefix("git-") for p in bin_dir.glob("git-*")}


def _aliases(gitconfig: Path) -> dict[str, str]:
    """One subprocess call total — never per-name (spec: related validation)."""
    out = subprocess.run(
        ["git", "config", "--file", str(gitconfig), "--get-regexp", r"^alias\."],
        capture_output=True, text=True, check=False,
    ).stdout
    aliases = {}
    for line in out.splitlines():
        key, _, value = line.partition(" ")
        aliases[key.removeprefix("alias.")] = value
    return aliases


def load_commands(path: Path | None = None,
                  categories_dir: Path | None = None,
                  bin_dir: Path | None = None,
                  gitconfig: Path | None = None) -> dict[str, CommandMeta]:
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

    registry: dict[str, CommandMeta] = {}
    for name, entry in raw.items():
        if not NAME_RE.match(name):
            raise _fail(name, "name", f"violates command grammar {NAME_RE.pattern}")
        if not isinstance(entry, dict):
            raise _fail(name, "table", "expected a TOML table")
        for field in REQUIRED_FIELDS:
            if field not in entry:
                raise _fail(name, field, "missing required field")
        kind = entry["kind"]
        if kind not in VALID_KINDS:
            raise _fail(name, "kind", f"must be one of {sorted(VALID_KINDS)}")
        unknown = set(entry["categories"]) - known_cats
        if unknown:
            raise _fail(name, "categories", f"unknown categories {sorted(unknown)}")
        if aliases is None:
            aliases = _aliases(gitconfig)
        for rel in entry["related"]:
            if rel not in registry and rel not in scripts and rel not in aliases:
                raise _fail(name, "related",
                            f"'{rel}' resolves to no registry entry, bin script, or alias")
        description = entry["description"]
        if not isinstance(description, str) or not description.strip():
            raise _fail(name, "description", "must be non-empty prose")
        registry[name] = CommandMeta(
            name=name,
            kind=kind,
            description=description,
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
```

- [ ] **Step 5: Run tests → PASS** (same command as Step 3). Note: drift 2b still fails until Task 4 edits git-hughelp — if the implementer reaches Task 1 before Task 4, mark `test_drift2b_branch1_is_pathfree_source` with `@pytest.mark.xfail(reason="Task 4 wires the chain", strict=True)` and REMOVE the mark in Task 4.

- [ ] **Step 6: Commit**

```bash
cd /home/ecc/src/hug-scm.WT.fetch-discovery-registry-for-help-search && hug a git-config/lib/python/commands.toml git-config/lib/python/command_meta.py git-config/lib/python/tests/test_command_meta.py && hug c
```

---

### Task 2: Index merge in `help_search.py` (kind field, `cmd_meta` param, before-sort merge, markers)

**Goal:** Registry rows flow through all four sigils as ordinary `CommandInfo` rows with `kind` set and `(alias)/(passthrough)` markers in listings — zero search-engine changes.

**Files:**
- Modify: `git-config/lib/python/help_search.py` (`CommandInfo` ~line 114-128, `collect_metadata` signature ~360-367, merge point before `sorted` at line 418, `format_results` ~587, `format_category_page` ~660-663)
- Modify: `git-config/lib/python/tests/test_help_search.py`

**Acceptance Criteria:**
- [ ] `collect_metadata(..., cmd_meta=None)` with `cmd_meta=None` behaves byte-identically to today (mock-dir tests stay hermetic — the explicit-param precedent of `cat_meta`)
- [ ] With `cmd_meta` passed, merged list is FULLY sorted on `command` (registry rows interleaved, not appended); script rows keep `kind=None`
- [ ] Warm cache: second `collect_metadata` call still includes registry rows
- [ ] `format_results`/`format_category_page` render `hug bpullr — Pull with rebase (git alias)` style markers when `kind` is set
- [ ] All existing `test_help_search.py` tests still pass unchanged

**Verify:** `cd git-config/lib/python && uv run --extra search pytest tests/test_help_search.py tests/test_command_meta.py -v` → green

**Steps:**

- [ ] **Step 1: Failing tests** — append to `tests/test_help_search.py`:

```python
def _cmd_meta():
    from command_meta import load_commands
    return load_commands(bin_dir=BIN, gitconfig=REPO / "git-config" / ".gitconfig")


def test_merge_interleaves_and_sorts():
    cmds = collect_metadata(BIN, use_cache=False, cat_meta=load_categories(CATS),
                            cmd_meta=_cmd_meta())
    names = [c.command for c in cmds]
    assert names == sorted(names)                      # ONE alphabetical run
    by_name = {c.command: c for c in cmds}
    assert by_name["hug bpullr"].kind == "alias"
    assert by_name["hug fetch"].kind == "passthrough"
    assert by_name["hug bpush"].kind is None           # scripts keep kind=None


def test_merge_survives_warm_cache():
    one = collect_metadata(BIN, use_cache=True, cat_meta=load_categories(CATS),
                           cmd_meta=_cmd_meta())
    two = collect_metadata(BIN, use_cache=True, cat_meta=load_categories(CATS),
                           cmd_meta=_cmd_meta())
    assert {c.command for c in one if c.kind} <= {c.command for c in two if c.kind}


def test_no_cmd_meta_is_hermetic():
    cmds = collect_metadata(BIN, use_cache=False, cat_meta=load_categories(CATS))
    assert all(c.kind is None for c in cmds)
    assert not any(c.command == "hug fetch" for c in cmds)


def test_format_marker_renders_kind():
    from help_search import CommandInfo, format_results
    row = CommandInfo(command="hug bpullr", description="Pull with rebase",
                      categories=["push-pull"], kind="alias")
    out = format_results([row], "pull")
    assert "(git alias)" in out
```

(`BIN`, `CATS`, `REPO` already exist in that file's imports/fixture scope — reuse them.)

- [ ] **Step 2: Run → FAIL** (`TypeError: unexpected keyword 'cmd_meta'`).

- [ ] **Step 3: Implement** — in `help_search.py`:

1. `CommandInfo` (line ~114-128): add field `kind: str | None = None` (keyword-defaulted; every existing construction is keyword-based — verified repo-wide, no positional breakage).
2. `collect_metadata` signature (~360-367): add `cmd_meta: dict | None = None` after `cat_meta`, mirroring the `cat_meta` precedent (default None = no merge; auto-loading would couple every mock-dir test to the real TOML).
3. Immediately BEFORE the `commands = sorted(commands, key=lambda c: c.command)` at line 418 (`hydrate_category_fields` runs after the sort — leave that order):

```python
    if cmd_meta:
        for name, meta in cmd_meta.items():
            commands.append(CommandInfo(
                command=f"hug {name}",          # pinned merge format (spec C-003, r2)
                description=meta.description,
                keywords=list(meta.keywords),
                categories=list(meta.categories),
                kind=meta.kind,
            ))
```

4. Render markers — in both `format_results` (line ~587, where `cmd.command` prints) and `format_category_page` (~660-663): append to the summary column when `getattr(cmd, "kind", None)`:

```python
    kind = getattr(cmd, "kind", None)
    suffix = f" ({kind.replace('passthrough', 'passthrough').replace('alias', 'alias') and 'git ' + kind})" if kind else ""
```

Simpler and exact — use this instead:

```python
    kind = getattr(cmd, "kind", None)
    summary_text = f"{cmd.summary} (git {kind})" if kind else cmd.summary
```

(with `cmd.summary` being whatever summary variable that render site already computes; add `kind="…"` to the two new `CommandInfo` constructions' fields. Registry rows carry their summary via the existing derive-from-description flow in `main()`'s hydrate — `hydrate_category_fields` fills category summaries; the FIRST-SENTENCE summary for search scoring comes from `description` via the scorer's description path, matching how the corpus simulation passed with plain `CommandInfo(description=…)` rows.)

5. **Wire the live search path** (review elifarley/hug-scm#339 thread: without
   this, Task 2's param exists but `main()` never passes it — the live
   `/fetch`, `/pull`, `@push-pull` paths stay registry-blind while every test
   passes). In `main()`, load the registry once and thread it through:

```python
    from command_meta import RegistryError, load_commands
    try:
        cmd_registry = load_commands()
    except RegistryError as exc:
        print(f"hug help: registry failure: {exc}", file=sys.stderr)
        sys.exit(1)  # search-mode posture: mirrors the categories sys.exit(1)
    cmds = collect_metadata(bin_dir, use_cache=args.use_cache,
                            cat_meta=cat_meta, cmd_meta=cmd_registry)
```

   (Card mode keeps its own lazy load inside `render_card` — Task 3. The
   exit-1-on-registry-failure posture for search modes is the spec's
   Error-handling contract; card mode maps the same failure to ≥2.)

- [ ] **Step 4: Run → PASS** (same command as Step 1, plus the full lib suite: `uv run --extra search pytest tests/ -q` → 957+ green).

- [ ] **Step 5: Commit** (`hug a git-config/lib/python/help_search.py git-config/lib/python/tests/test_help_search.py && hug c`)

---

### Task 3: Card mode in `help_search.py` (rendering + single-owned exit contract)

**Goal:** `help_search.py card -- <name>` renders the hug card; exit 0 card / 1 miss / ≥2 loud; BrokenPipe → devnull+0; KeyboardInterrupt → 130; catch-all scoped to `Exception`.

**Files:**
- Modify: `git-config/lib/python/help_search.py` (new `render_card()` function + `card` mode in `main()`'s argparse choices + dispatch)
- Modify: `git-config/lib/python/tests/test_help_search.py`

**Acceptance Criteria:**
- [ ] `card -- fetch` exits 0; card text contains "git passthrough", the description, `Usage:`, `Git equivalent: git fetch`, `Full flags: git help fetch`, and the Related block
- [ ] Full-flags derives from `git_equivalent`'s leading command, NOT the name (`bpullr` → `git help pull`; `bs` → `git help switch`)
- [ ] `card -- bpullr` exits 1 (miss for non-registry name `zzz` too), no partial card
- [ ] Corrupt registry in card mode → exit ≥2, message on stderr, nothing on stdout
- [ ] `card -- -h` / `card -- --bogus` → miss (1) / ≥2 — argparse never intercepts behind `--`
- [ ] BrokenPipeError → exit 0 via devnull redirect (both in-body and shutdown-flush shapes); KeyboardInterrupt → 130 no traceback
- [ ] Card never calls `collect_metadata`; related summaries peek `search-meta.cache` with key `git-<name>` via `_load_cache`, never `_save_cache`

**Verify:** `cd git-config/lib/python && uv run --extra search help_search.py card -- fetch; echo rc=$?` → card + `rc=0`; `… card -- zzz; echo rc=$?` → `rc=1`; `pytest tests/test_help_search.py -q` green

**Steps:**

- [ ] **Step 1: Failing tests** (append to `tests/test_help_search.py`; run card rendering via `capsys` + `monkeypatch` on `sys.argv`):

```python
import pytest

from help_search import render_card


def test_card_found_render(capsys):
    rc = render_card("fetch", registry=_cmd_meta(), cache_dir=None)
    out = capsys.readouterr().out
    assert rc == 0
    assert "git passthrough" in out and "Usage:" in out
    assert "Git equivalent: git fetch" in out
    assert "Full flags: git help fetch" in out
    assert "hug bpull" in out  # related


def test_card_fullflags_uses_alias_target(capsys):
    render_card("bpullr", registry=_cmd_meta(), cache_dir=None)
    out = capsys.readouterr().out
    assert "Full flags: git help pull" in out      # NOT git help bpullr


def test_card_miss_exit1(capsys):
    assert render_card("zzz", registry=_cmd_meta(), cache_dir=None) == 1


def test_card_corrupt_registry_loud(tmp_path, capsys):
    (tmp_path / "commands.toml").write_text("[fetch]\nkind = 'bogus'\n")
    rc = render_card("fetch", registry=None, commands_path=tmp_path / "commands.toml",
                     cache_dir=None)
    cap = capsys.readouterr()  # ONE capture: a second call resets to empty
    assert rc >= 2 and cap.err and not cap.out


def test_card_cache_peek_uses_git_name_key(capsys):
    # related summary for script `llu` resolves from a cache keyed by FILENAME
    import json
    cachedir = tmp_path_with_cache({"git-llu": {"description": "outgoing commits"}})
    render_card("fetch", registry=_cmd_meta(), cache_dir=cachedir)
    assert "outgoing commits" in capsys.readouterr().out
```

(`tmp_path_with_cache` = tiny helper writing `search-meta.cache` JSON into a tmp dir and returning the dir.)

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Implement `render_card()` + mode wiring** in `help_search.py`:

```python
def render_card(name, registry=None, commands_path=None, cache_dir=None) -> int:
    """Render the hug card for a registry-owned name. Exit contract:
    0 card | 1 miss (EXCLUSIVELY) | >=2 loud. Never fall through on >=2.
    Pure function over the registry + read-only cache peek — NEVER collect_metadata."""
    import os
    try:
        if registry is None:
            from command_meta import RegistryError, load_commands
            try:
                registry = load_commands(path=commands_path)
            except RegistryError as exc:
                print(f"hug help: registry failure: {exc}", file=sys.stderr)
                return 2
        cmd = registry.get(name)
        if cmd is None:
            return 1

        full_flags_target = (cmd.git_equivalent.split()[1]
                             if cmd.git_equivalent.split()[:1] == ["git"]
                             else cmd.git_equivalent)
        kind_label = f"(git {cmd.kind})"
        lines = [
            f"hug {name} — {kind_label}",
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
        peek = {}
        if cache_dir is not None:
            peek = _load_cache(Path(cache_dir) / "search-meta.cache")  # read-only; NEVER _save_cache
        for rel in cmd.related:
            rel_meta = registry.get(rel)
            if rel_meta:
                lines.append(f"  hug {rel} — {rel_meta.summary}")
            elif f"git-{rel}" in peek:
                lines.append(f"  hug {rel} — {peek[f'git-{rel}'].get('description', '')}")
            else:
                lines.append(f"  hug {rel}")
        print("\n".join(lines))
        return 0
    except BrokenPipeError:
        # Shutdown-flush fires OUTSIDE this handler for buffered card-sized
        # output — the devnull redirect below is the load-bearing half.
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        return 0
    except KeyboardInterrupt:
        raise  # unwrapped: exit 130, no traceback
    except Exception as exc:  # Python exits 1 on bare crash — that code is
        # RESERVED for miss, so map ANY unexpected exception to >=2 loudly.
        print(f"hug help: card failed: {exc}", file=sys.stderr)
        return 3
```

Then in `main()`: add `"card"` to the mode choices with a positional `name`, and dispatch `sys.exit(render_card(args.name, commands_path=…, cache_dir=cache_dir))`. Add the shutdown-flush guard at the script's top level so the post-`sys.exit(0)` final flush cannot reintroduce exit 120:

```python
if __name__ == "__main__":
    rc = main()
    sys.exit(rc)
```

with `main()` returning the int, and wrap `sys.exit(rc)` in the same `BrokenPipeError` → devnull+`os._exit(0)` pattern:

```python
if __name__ == "__main__":
    try:
        rc = main()
        sys.stdout.flush()  # LOAD-BEARING: for buffered (card-sized) output the
        # EPIPE fires only here (or at interpreter finalization, which no
        # except can see — probed exit 120). Flushing INSIDE the try surfaces
        # it to the handler; the subsequent shutdown flush then writes an
        # empty buffer to devnull-safe stdout.
        sys.exit(rc)
    except BrokenPipeError:
        import os
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        os._exit(0)
```

(`KeyboardInterrupt` is intentionally NOT caught here — default exit 130 without traceback.)

- [ ] **Step 4: Run → PASS**; smoke the three live exit buckets: `uv run --extra search help_search.py card -- fetch; echo $?` → `0`; `… card -- zzz; echo $?` → `1`; `… card -- bpullr; echo $?` → `0` with `git help pull`.

- [ ] **Step 5: Commit** (`hug a git-config/lib/python/help_search.py git-config/lib/python/tests/test_help_search.py && hug c`)

---

### Task 4: `git-hughelp` chain (flag guard, `-x` + `$dir` invocation, exit mapping)

**Goal:** Wire the strict script → card → alias chain with the pinned exit contract; remove the PATH-based `command -v`.

**Files:**
- Modify: `git-config/bin/git-hughelp:45-53` (exact-help resolution block)
- Modify: `tests/integration/test_help_articles.bats`

**Acceptance Criteria:**
- [ ] `hug help s` → script help (branch ①, `$dir/`-invoked)
- [ ] `hug help fetch` / `hug help bs` → card, exit 0, no "Commands starting with", no GIT-FETCH banner
- [ ] `hug help brr` → alias help + listing, exit 0 (non-registry alias fall-through)
- [ ] `hug help -h` → listing, exit 0, no card, no argparse usage
- [ ] `hug help zzz` → listing "(none)", exit 0
- [ ] `hug help /fetch` → search results (sigils unchanged)
- [ ] BATS: all new rows green; full `make test-bash` green

**Verify:** `make test-integration TEST_FILE=test_help_articles.bats` → green; manual: `hug help fetch; echo $?` → `0`

**Steps:**

- [ ] **Step 1: Failing BATS rows** — append to `tests/integration/test_help_articles.bats`:

```bash
@test "hug help fetch renders the registry card, not git's man page" {
  run hug help fetch
  assert_success
  assert_output --partial "git passthrough"
  assert_output --partial "Full flags: git help fetch"
  refute_output --partial "Commands starting with"
  refute_output --partial "GIT-FETCH"
}

@test "hug help bs renders the card (7th registry entry)" {
  run hug help bs
  assert_success
  assert_output --partial "(git alias)"
  assert_output --partial "switch back"
  refute_output --partial "Commands starting with"
}

@test "hug help brr keeps alias fall-through + listing" {
  run hug help brr
  assert_success
  assert_output --partial "aliased to"
  assert_output --partial "Commands starting with"
}

@test "hug help -h never renders a card or argparse usage" {
  run hug help -h
  assert_success
  refute_output --partial "git passthrough"
  refute_output --partial "usage: help_search.py"
}

@test "hug help zzz keeps the prefix listing" {
  run hug help zzz
  assert_success
  assert_output --partial "(none)"
}

@test "hug help s still hits the script help (precedence)" {
  run hug help s
  assert_success
  refute_output --partial "git passthrough"
}
```

- [ ] **Step 2: Run → FAIL** (`hug help fetch` prints GIT-FETCH(1) today).

Run: `make test-integration TEST_FILE=test_help_articles.bats`

- [ ] **Step 3: Implement** — replace `git-config/bin/git-hughelp` lines 45–53 (the exact-help block) with:

```bash
# Exact help: hug's own script → registry card → alias. Precedence is
# CONTRACT: scripts beat cards (spec Integration 2). Flag-like prefixes are
# not command names — they skip ①② entirely.
if [[ "$prefix" != -* ]]; then
  if [[ -x "$dir/git-$prefix" ]]; then
    echo
    "$dir/git-$prefix" --help
    echo
  else
    # Card mode. Exit contract (single owner — spec lines "Exit-code contract"):
    #   0 → card printed; stop.  1 → miss; fall through to alias/listing.
    #   127 → uv missing (REQUIRED dependency): loud hint.  >=2 → loud failure.
    uv run --directory "$dir/../lib/python" --extra search help_search.py card -- "$prefix"
    card_rc=$?
    case $card_rc in
      0) exit 0 ;;
      1) : ;;  # registry miss — fall through
      127) echo "hug: uv is required for 'hug help $prefix' (install.sh provisions it)." >&2; exit 127 ;;
      *) echo "hug: help card failed (rc=$card_rc): $prefix" >&2; exit "$card_rc" ;;
    esac
  fi
elif [[ -x "$dir/git-$prefix" ]]; then
  echo
  "$dir/git-$prefix" --help
  echo
fi
```

Also REMOVE the Task 1 xfail from `test_drift2b_branch1_is_pathfree_source`.

- [ ] **Step 4: Run → PASS** (BATS file + `make test-bash TEST_SHOW_ALL_RESULTS=0`).

- [ ] **Step 5: Commit** (`hug a git-config/bin/git-hughelp tests/integration/test_help_articles.bats git-config/lib/python/tests/test_command_meta.py && hug c`)

---

### Task 5: Corpus rows (regression net for the reported complaint)

**Goal:** Pin `/fetch`, `/pull`, `/bs` and both intent queries in `test_quality_corpus.py`.

**Files:**
- Modify: `git-config/lib/python/tests/test_quality_corpus.py` (keyword corpus list ~lines 55-64, intent corpus list ~96-141)

**Acceptance Criteria:**
- [ ] The five rows from the spec pass against the real index: `/fetch` ⊇ {"hug fetch","hug tpull","hug tpullf"}; `/pull` ⊇ {"hug bpull","hug bpullr","hug pullall"}; `/bs` ⊇ {"hug bs"}; intent `update my repo from the remote` ⊇ {"hug fetch","hug bpull","hug bpullr"}; intent `go back to the previous branch` ⊇ {"hug bs"}
- [ ] The corpus fixture passes `cmd_meta` (Task 2's param) so rows exercise the real merge

**Verify:** `cd git-config/lib/python && uv run --extra search pytest tests/test_quality_corpus.py -q` → all pass

**Steps:**

- [ ] **Step 1:** Update the module fixture to pass the registry: `cmds = collect_metadata(BIN, use_cache=False, cat_meta=cats, cmd_meta=load_commands(...))` (import `load_commands` from `command_meta`).
- [ ] **Step 2:** Add keyword rows after `("branch", ["hug b", "hug bc"])`:

```python
        ("fetch", ["hug fetch", "hug tpull", "hug tpullf"]),
        ("pull", ["hug bpull", "hug bpullr", "hug pullall"]),
        ("bs", ["hug bs"]),
```

- [ ] **Step 3:** Add intent rows:

```python
        ("update my repo from the remote", ["hug fetch", "hug bpull", "hug bpullr"]),
        ("go back to the previous branch", ["hug bs"]),
```

- [ ] **Step 4:** Run → PASS (round-4 roast already simulated all five rows green against the real scorers — a failure here means a merge/scorer regression, fix the code, never the expected values).
- [ ] **Step 5: Commit** (`hug a git-config/lib/python/tests/test_quality_corpus.py && hug c`)

---

### Task 6: uv promoted to required dependency (`install.sh` + README)

**Goal:** `install.sh` validates uv (user-directed: required, loud, no silent degradation); README documents it.

**Files:**
- Modify: `install.sh` (after `set -euo pipefail`, line 4)
- Modify: `README.md` (requirements/install section)

**Acceptance Criteria:**
- [ ] `install.sh` exits 1 with an actionable install hint when `uv` is absent; proceeds when present; `HUG_SKIP_UV_CHECK=1` escapes for hg-only/offline installs (documented inline)
- [ ] README's install section lists uv as a requirement with the install one-liner
- [ ] `bash -n install.sh` clean

**Verify:** `bash -n install.sh && PATH=/usr/bin:/bin bash -c 'unset -f uv; (command -v uv || true)' ; HUG_SKIP_UV_CHECK= PATH=/usr/bin:/bin bash install.sh` → uv-missing path prints hint and exits 1 (run the negative probe in a scratch HOME, never `$HOME`)

**Steps:**

- [ ] **Step 1:** Insert after line 4 of `install.sh`:

```bash
# uv is a REQUIRED dependency (help discovery sigils + exact-name cards run
# through `uv run`). Validate loudly; do not silently install toolchains.
if [[ "${HUG_SKIP_UV_CHECK:-}" != "1" ]] && ! command -v uv > /dev/null 2>&1; then
  echo "ERROR: uv is required by Hug SCM but was not found on PATH." >&2
  echo "Install it with: curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
  echo "Then re-run this installer. (HUG_SKIP_UV_CHECK=1 bypasses for hg-only installs.)" >&2
  exit 1
fi
```

- [ ] **Step 2:** In `README.md`, in the installation/requirements section, add: "`uv` (required — powers `hug help` discovery and help cards): `curl -LsSf https://astral.sh/uv/install.sh | sh`".
- [ ] **Step 3:** `bash -n install.sh` → clean; negative probe in `HOME=$(mktemp -d)`.
- [ ] **Step 4: Commit** (`hug a install.sh README.md && hug c`)

---

### Task 7: Docs change-set (articles, translation docs, completion reference, authoring homes)

**Goal:** Land the seven-doc change-set; agents' artifacts teach fetch truthfully everywhere they name the sync surface.

**Files:**
- Modify: `git-config/lib/python/articles/agents.md` (translation table + new "Fetching & pulling" block)
- Modify: `docs/git-to-hug.md` (:135-136 detailed rows, :440 quick table)
- Modify: `docs/command-map.md` (:106-107 tree)
- Modify: `docs/meta/hug-completion-reference.md` (:159-160 Pull section — actively wrong today)
- Modify: `git-config/bin/CLAUDE.md` (keywords authoring note)
- Modify: `git-config/lib/python/README.md` (Module Organization)

**Acceptance Criteria:**
- [ ] agents.md: `git fetch → hug fetch` translation row + Fetching & pulling block (fetch/bpull/bpullr/tpull + fetch-before-`wtc --base` reminder)
- [ ] git-to-hug.md: fetch row in BOTH tables beside the `git pull → hug bpull` rows
- [ ] command-map.md: `fetch` tree entry beside `bpull`/`bpullr`
- [ ] completion-reference: `bpull` row corrected to "Fast-forward-only pull", `bpullr` row added ("Pull with rebase"), `pullall` re-phrased to "Fetch all remotes, update current branch's upstream" (never "Pull all remotes")
- [ ] bin/CLAUDE.md: registry note (scripts → `_hug_keywords`; non-script commands → `commands.toml`)
- [ ] lib/python README Module Organization: `command_meta.py` / `commands.toml` row
- [ ] `make docs-build` green (VitePress compiles the touched docs)

**Verify:** `make docs-build` → success; `grep -n "hug fetch" docs/git-to-hug.md docs/command-map.md git-config/lib/python/articles/agents.md` → hits in all three

**Steps:**

- [ ] **Step 1:** agents.md — after the `git push → hug bpush` table row add `| \`git fetch\` | \`hug fetch\` (passthrough — downloads refs, no merge) |`; after the "## Pushing" section add:

```markdown
## Fetching & pulling

- `hug fetch`: download new commits/refs from remotes — never merges. Safe to run anytime; run it before `hug wtc <branch> --base origin/main` so the base is up to date.
- `hug bpull`: fast-forward-only pull (safe default; fails if a merge/rebase would be needed).
- `hug bpullr`: pull with rebase (linear history).
- `hug tpull` / `hug tpullf`: fetch tags / force-fetch + prune stale tags.
```

- [ ] **Step 2:** git-to-hug.md — insert `| git fetch | hug fetch |` adjacent to the existing `git pull → hug bpull` rows in both tables (:135-136 area and :440 area), matching each table's column style.
- [ ] **Step 3:** command-map.md — insert `│   ├── fetch         # Fetch from remote(s) — passthrough (no merge)` between the `bpullr` and `bpush` tree lines.
- [ ] **Step 4:** completion-reference.md — replace lines 159-160 with:

```markdown
- `bpull`: Fast-forward-only pull. No args.
- `bpullr`: Pull with rebase. No args.
- `pullall`: Fetch all remotes, update current branch's upstream. No args.
```

- [ ] **Step 5:** bin/CLAUDE.md — append after the `_hug_keywords` example paragraph:

```markdown
Non-script commands (git-aliases, passthroughs) have no script to annotate —
their keywords/summaries live in `../lib/python/commands.toml` (registry),
loaded by `command_meta.py`. Keep the two surfaces consistent: a keyword that
would fit a destructive sibling stays out of BOTH.
```

- [ ] **Step 6:** lib/python `README.md` Module Organization — add rows: `command_meta.py — loads commands.toml (non-script command registry); validates schema, derives summaries`; `commands.toml — the registry itself (fetch, bpull, bpullr, pullall, tpull, tpullf, bs)`.
- [ ] **Step 7:** `make docs-build` → green; commit all (`hug a <six files> && hug c`)

---

## Execution notes (all tasks)

- Run `make test` (or the task's Verify command) before each commit; the session's stop-hook does NOT fire for subagent commits — the coordinator runs `make sanitize` after the final task and folds fixes into that commit.
- NEVER pipe `hug help …` output through `head`/`grep` in interactive shell commands — the block-commands hook forbids it (BATS `run` capture is fine).
- Blocked-literal hygiene in commit messages: hyphenate `git-pull`-style phrases; the block-commands hook string-matches forbidden literals inside heredocs.
- Spec cross-reference for every pinned contract: `docs/superpowers/specs/2026-09-08-fetch-discovery-registry-for-help-search-design.md` — when this plan and the spec disagree, the spec wins; stop and reconcile.
