# Help Category Metadata + Search Quality Overhaul — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add per-category description + keywords metadata, redesign `@<category>`
display, and overhaul `/keyword` and `!intent` scoring with a `MatchSpec` model
so results are precise, diverse, and capped.

**Architecture:** Per-category TOML manifests at
`git-config/lib/python/categories/<name>.toml` are the single source of truth.
A new `category_meta.py` module loads + validates them. `help_search.py` is
refactored around a `MatchSpec` dataclass — `(field, scorer, weight,
min_threshold, label)` — so each searchable field gets its own scorer and
threshold. `!intent` becomes genuinely token-aware (`token_set_ratio`),
distinct from `/keyword`. Strict validation: a script declaring an unmanifested
category fails CI and exits 1 at runtime. The bash dispatcher (`git-hughelp`)
stays thin — only its no-arg tip line changes.

**Design principles:**
- **DRY**: Category metadata lives once, in one TOML per category.
- **TDD**: Every Python change starts with a failing test.
- **Bite-sized**: Each task is one logical commit; steps are 2-5 min each.
- **No regressions**: Existing `MIN_KEYWORD_SCORE` semantics preserved during
  the refactor — quality improvements come from added fields and new spec lists,
  not from breaking what works.
- **Stdout/stderr discipline**: Per `CLAUDE.md`, data → stdout, chatter → stderr.

**Tech Stack:** Python 3.10+ via `uv run` (already in use), `thefuzz` (already
optional dep), `tomllib` (stdlib in 3.11+) / `tomli` (already a dep for 3.10),
`pytest`, BATS.

**Reference:** `docs/plans/2026-05-06-help-category-meta-design.md` (commit
`52d44e7`).

---

## Task 0: Bootstrap the 19 category TOML manifests

**Files:**
- Create: `git-config/lib/python/categories/analysis.toml`
- Create: `git-config/lib/python/categories/branching.toml`
- Create: `git-config/lib/python/categories/committing.toml`
- Create: `git-config/lib/python/categories/files.toml`
- Create: `git-config/lib/python/categories/garbage.toml`
- Create: `git-config/lib/python/categories/head.toml`
- Create: `git-config/lib/python/categories/history.toml`
- Create: `git-config/lib/python/categories/merge.toml`
- Create: `git-config/lib/python/categories/parking.toml`
- Create: `git-config/lib/python/categories/push-pull.toml`
- Create: `git-config/lib/python/categories/rebase.toml`
- Create: `git-config/lib/python/categories/show.toml`
- Create: `git-config/lib/python/categories/staging.toml`
- Create: `git-config/lib/python/categories/statistics.toml`
- Create: `git-config/lib/python/categories/status.toml`
- Create: `git-config/lib/python/categories/tags.toml`
- Create: `git-config/lib/python/categories/utilities.toml`
- Create: `git-config/lib/python/categories/working-dir.toml`
- Create: `git-config/lib/python/categories/worktrees.toml`

**WHY first:** these are pure data, no code dependency. Land them before any
loader so subsequent tasks can rely on real fixtures, not mocks.

**Step 1: Create each TOML manifest**

Schema for every file:
```toml
label       = "<short title shown in boxed header>"
description = """
<2-4 sentence paragraph describing the category>
"""
keywords    = [
  "<curated keyword>", "<curated keyword>", "<curated keyword>", ...
]
```

Required: `label` (string), `description` (string), `keywords` (≥3 entries).

**Authoring guidance:**
- Description's **first sentence ≤ 70 chars** (it becomes the summary column
  in `hug help @`). Shorten or rephrase if needed.
- Keywords are **curated**, not exhaustive — pick terms users would actually
  type. Each keyword you list claims "this category IS about this word".
- Lowercase keywords; allow hyphens.

**Reference content** (use these as the bootstrap; tune as needed):

```toml
# analysis.toml
label       = "Repository analysis"
description = """
Analyse history, ownership, and dependencies across the codebase.
Surfaces hot spots, expert authors, and co-changing files.
"""
keywords    = ["analyse", "analyze", "blame", "ownership", "co-change",
               "hotspot", "expert", "deps"]
```

```toml
# branching.toml
label       = "Branch operations"
description = """
Create, list, switch, and delete branches.
Branches let you work on parallel lines of development without
conflicting with shared code.
"""
keywords    = ["branch", "switch", "checkout", "tracking", "upstream",
               "head", "ref", "rename"]
```

```toml
# committing.toml
label       = "Commits"
description = """
Create, modify, and rewrite commits.
Commits are atomic snapshots of work; amending and cherry-picking
let you reshape history before sharing.
"""
keywords    = ["commit", "amend", "cherry-pick", "message", "snapshot",
               "stage", "fixup"]
```

```toml
# files.toml
label       = "File inspection"
description = """
Inspect history, contents, and ownership of specific files.
Trace when a file appeared, what it touched, who wrote each line.
"""
keywords    = ["file", "blame", "born", "history", "show", "cat"]
```

```toml
# garbage.toml
label       = "Garbage collection"
description = """
Repository garbage collection and storage compaction.
"""
keywords    = ["gc", "garbage", "prune", "pack", "compact"]
```

```toml
# head.toml
label       = "HEAD operations"
description = """
Move HEAD around safely.
Undo, rollback, rewind, or squash commits while keeping local
work intact when possible.
"""
keywords    = ["head", "undo", "rollback", "rewind", "back", "squash",
               "reset", "revert"]
```

```toml
# history.toml
label       = "Commit history"
description = """
View commit logs and diffs across the repository.
Filter by file, author, range, or content; format compactly or
in detail.
"""
keywords    = ["log", "history", "show", "list", "diff", "commits"]
```

```toml
# merge.toml
label       = "Merging"
description = """
Merge branches together via fast-forward or merge commits.
"""
keywords    = ["merge", "fast-forward", "ff", "no-ff", "join", "combine"]
```

```toml
# parking.toml
label       = "Work-in-progress parking"
description = """
Park work-in-progress aside and unpark it later.
Like a stash, but tracked as commits on a parking branch.
"""
keywords    = ["wip", "park", "stash", "save", "shelve", "unpark"]
```

```toml
# push-pull.toml
label       = "Remote sync"
description = """
Sync the local repository with remotes.
Push branches, fetch updates, pull and rebase, set upstream tracking.
"""
keywords    = ["push", "pull", "fetch", "remote", "origin", "upstream",
               "sync", "tracking"]
```

```toml
# rebase.toml
label       = "Rebase"
description = """
Replay commits onto another base.
Continue, abort, or finish an in-progress rebase.
"""
keywords    = ["rebase", "replay", "interactive", "continue", "abort",
               "onto"]
```

```toml
# show.toml
label       = "Show details"
description = """
Show details for commits, patches, and objects.
"""
keywords    = ["show", "details", "patch", "diff", "commit", "object"]
```

```toml
# staging.toml
label       = "Staging area"
description = """
Stage and unstage changes for the next commit.
The staging area is the buffer between working tree and history.
"""
keywords    = ["stage", "add", "index", "unstage", "reset", "tracked",
               "untracked"]
```

```toml
# statistics.toml
label       = "Repository statistics"
description = """
Aggregate statistics about authorship, churn, and branch activity.
"""
keywords    = ["stats", "statistics", "churn", "authors", "count",
               "metrics"]
```

```toml
# status.toml
label       = "Working tree state"
description = """
View the working tree state.
Show staged, unstaged, untracked, and ignored files; full or
compact summary.
"""
keywords    = ["status", "state", "summary", "modified", "staged",
               "unstaged", "untracked", "ignored", "list"]
```

```toml
# tags.toml
label       = "Tags"
description = """
Create, list, move, and delete tags.
Tags are immutable named pointers; useful for releases.
"""
keywords    = ["tag", "release", "version", "annotate", "label"]
```

```toml
# utilities.toml
label       = "Utilities"
description = """
General-purpose utility commands.
"""
keywords    = ["utility", "tools", "misc", "helper"]
```

```toml
# working-dir.toml
label       = "Working directory"
description = """
Working-directory operations.
Discard, wipe, purge, restore, or pull files in the working tree
without touching commit history.
"""
keywords    = ["working", "tree", "discard", "wipe", "purge", "restore",
               "wip", "zap", "clean"]
```

```toml
# worktrees.toml
label       = "Worktrees"
description = """
Manage git worktrees.
Create, list, switch, prune, and remove additional working trees
sharing a single repository.
"""
keywords    = ["worktree", "wt", "checkout", "linked", "secondary",
               "isolated"]
```

**Step 2: Verify all files parse as valid TOML**

```bash
cd git-config/lib/python
uv run python -c '
import tomllib
from pathlib import Path
for p in sorted(Path("categories").glob("*.toml")):
    with p.open("rb") as f:
        d = tomllib.load(f)
    assert "label" in d, f"{p}: missing label"
    assert "description" in d, f"{p}: missing description"
    assert "keywords" in d and len(d["keywords"]) >= 3, f"{p}: bad keywords"
    print(f"OK  {p.name}")
'
```
Expected: 19 lines of `OK <name>.toml`.

**Step 3: Commit**
```
hug a git-config/lib/python/categories/
hug c -m "feat: bootstrap 19 category TOML manifests for help discovery"
```

---

## Task 1: TDD — `category_meta.py` loader and validator

**Files:**
- Create: `git-config/lib/python/category_meta.py`
- Create: `git-config/lib/python/tests/test_category_meta.py`

**Step 1: Write the failing test file**

Create `git-config/lib/python/tests/test_category_meta.py`:

```python
"""Tests for category_meta.py — per-category metadata loader/validator."""

from pathlib import Path

import pytest

from category_meta import (
    CategoryMeta,
    load_categories,
    validate_against_scripts,
    derive_summary,
)


class TestDeriveSummary:
    def test_first_sentence_short(self):
        assert derive_summary("A short sentence. Another one.") == "A short sentence."

    def test_first_sentence_truncated(self):
        long = "A " + "very " * 30 + "long sentence."
        s = derive_summary(long)
        assert len(s) <= 70
        # Truncation should be on a word boundary, ending with an ellipsis.
        assert s.endswith("…")
        assert " " in s

    def test_strips_leading_newlines(self):
        assert derive_summary("\n\n  A sentence.\n  More.") == "A sentence."

    def test_empty_input(self):
        assert derive_summary("") == ""

    def test_no_sentence_terminator(self):
        # Treat the whole text as the first "sentence".
        assert derive_summary("just words no terminator") == "just words no terminator"


class TestLoadCategories:
    @pytest.fixture
    def cat_dir(self, tmp_path):
        d = tmp_path / "categories"
        d.mkdir()
        (d / "branching.toml").write_text(
            'label = "Branch operations"\n'
            'description = """\nCreate, list, switch, and delete branches.\nDetails follow.\n"""\n'
            'keywords = ["branch", "switch", "checkout"]\n'
        )
        (d / "staging.toml").write_text(
            'label = "Staging area"\n'
            'description = "Stage and unstage changes."\n'
            'keywords = ["stage", "add", "index"]\n'
        )
        return d

    def test_loads_all_files(self, cat_dir):
        cats = load_categories(cat_dir)
        assert set(cats.keys()) == {"branching", "staging"}

    def test_meta_fields_populated(self, cat_dir):
        cats = load_categories(cat_dir)
        b = cats["branching"]
        assert isinstance(b, CategoryMeta)
        assert b.name == "branching"
        assert b.label == "Branch operations"
        assert "Create, list, switch" in b.description
        assert b.keywords == ("branch", "switch", "checkout")

    def test_summary_derived(self, cat_dir):
        cats = load_categories(cat_dir)
        assert cats["branching"].summary == "Create, list, switch, and delete branches."

    def test_missing_label_raises(self, tmp_path):
        d = tmp_path / "categories"
        d.mkdir()
        (d / "x.toml").write_text(
            'description = "x"\nkeywords = ["a","b","c"]\n'
        )
        with pytest.raises(ValueError, match="missing 'label'"):
            load_categories(d)

    def test_missing_description_raises(self, tmp_path):
        d = tmp_path / "categories"
        d.mkdir()
        (d / "x.toml").write_text(
            'label = "X"\nkeywords = ["a","b","c"]\n'
        )
        with pytest.raises(ValueError, match="missing 'description'"):
            load_categories(d)

    def test_too_few_keywords_raises(self, tmp_path):
        d = tmp_path / "categories"
        d.mkdir()
        (d / "x.toml").write_text(
            'label = "X"\ndescription = "x"\nkeywords = ["a","b"]\n'
        )
        with pytest.raises(ValueError, match="needs >= 3 keywords"):
            load_categories(d)


class TestValidateAgainstScripts:
    def _meta(self, name):
        return CategoryMeta(name=name, label=name, description="x", summary="x", keywords=("a","b","c"))

    def test_no_errors_when_complete(self):
        cats = {"branching": self._meta("branching"), "staging": self._meta("staging")}
        used = {"branching", "staging"}
        assert validate_against_scripts(cats, used) == []

    def test_error_for_missing_manifest(self):
        cats = {"branching": self._meta("branching")}
        used = {"branching", "flubber"}
        errors = validate_against_scripts(cats, used)
        assert len(errors) == 1
        assert "flubber" in errors[0]

    def test_orphan_manifest_is_warning_not_error(self):
        # Orphans returned as warnings via separate field if needed; for now,
        # only missing manifests are errors. Orphan detection is a future hook.
        cats = {"branching": self._meta("branching"), "ghost": self._meta("ghost")}
        used = {"branching"}
        errors = validate_against_scripts(cats, used)
        assert errors == []
```

**Step 2: Run tests — verify they fail with ModuleNotFoundError**

Run: `make test-lib-py TEST_FILTER=test_category_meta`
Expected: FAIL with `ModuleNotFoundError: No module named 'category_meta'`.

**Step 3: Implement `category_meta.py`**

Create `git-config/lib/python/category_meta.py`:

```python
"""Per-category metadata loader.

Each category has one TOML file under ./categories/<name>.toml with:
  label       — short title for headers
  description — multi-line paragraph, first sentence becomes the summary
  keywords    — curated terms; matched strictly when scoring search

WHY a separate module: keeps loader/validator/IO out of help_search.py,
which stays focused on search. Easier to test in isolation; clean module
boundary if other tooling wants to consume the loader.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

# tomllib is stdlib in 3.11+; tomli is the backport for older Pythons.
if sys.version_info >= (3, 11):
    import tomllib  # type: ignore[import-not-found]
else:
    import tomli as tomllib  # type: ignore[no-redef]

# Summary cap matches the @ listing column width budget.
SUMMARY_MAX = 70

_SENTENCE_END = re.compile(r"(?<=[.!?])\s+")


@dataclass(frozen=True)
class CategoryMeta:
    name: str               # filename stem
    label: str
    description: str        # full paragraph as written
    summary: str            # first sentence; ≤ SUMMARY_MAX when feasible
    keywords: tuple[str, ...]


def derive_summary(description: str, max_len: int = SUMMARY_MAX) -> str:
    """Return the first sentence of `description`, truncated to <= max_len.

    Truncation falls back on word boundaries with an ellipsis.
    Empty input returns empty string.
    """
    text = description.strip()
    if not text:
        return ""
    # First sentence: split on .!? followed by whitespace; first part wins.
    first = _SENTENCE_END.split(text, maxsplit=1)[0].strip()
    if len(first) <= max_len:
        return first
    # Truncate on a word boundary, append U+2026 horizontal ellipsis.
    cut = first[: max_len - 1].rsplit(" ", 1)[0]
    return f"{cut}…"


def load_categories(directory: str | Path) -> dict[str, CategoryMeta]:
    """Load every <name>.toml under `directory` into a dict keyed by name.

    Raises ValueError on schema violations (missing fields, too-few keywords),
    with the manifest path embedded in the message.
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
        kws = data.get("keywords", [])
        if not isinstance(kws, list) or len(kws) < 3:
            raise ValueError(f"{path}: 'keywords' needs >= 3 entries")

        name = path.stem
        out[name] = CategoryMeta(
            name=name,
            label=str(data["label"]),
            description=str(data["description"]).strip(),
            summary=derive_summary(str(data["description"])),
            keywords=tuple(str(k) for k in kws),
        )
    return out


def validate_against_scripts(
    categories: dict[str, CategoryMeta],
    used_categories: set[str],
) -> list[str]:
    """Return a list of error strings; empty == OK.

    Currently: each category referenced by some script MUST have a manifest.
    Orphan manifests (no script references them) are silently allowed —
    they may be placeholders for upcoming commands.
    """
    missing = sorted(used_categories - categories.keys())
    return [
        f"category '{name}' is referenced by a script "
        f"but has no manifest at categories/{name}.toml"
        for name in missing
    ]
```

**Step 4: Run tests — verify they pass**

Run: `make test-lib-py TEST_FILTER=test_category_meta`
Expected: PASS — all 11 tests green.

**Step 5: Smoke load against the real bootstrap from Task 0**

```bash
cd git-config/lib/python
uv run python -c '
from pathlib import Path
from category_meta import load_categories
cats = load_categories(Path("categories"))
print(f"loaded {len(cats)} categories")
print("sample:", cats["branching"].summary)
'
```
Expected: `loaded 19 categories` and the summary string for branching.

**Step 6: Commit**
```
hug a git-config/lib/python/category_meta.py git-config/lib/python/tests/test_category_meta.py
hug c -m "feat: add category_meta.py loader + validator with TDD coverage"
```

---

## Task 2: TDD — `MatchSpec` dataclass + `run_search` refactor (preserve behavior)

**Files:**
- Modify: `git-config/lib/python/help_search.py`
- Modify: `git-config/lib/python/tests/test_help_search.py`

**WHY this task:** the current `search_keyword` / `search_category` functions
are ad-hoc loops with hard-coded scorers. We refactor them into a generic
`run_search(query, items, specs)` driven by `MatchSpec` records. Behavior MUST
remain identical; quality changes come in subsequent tasks.

**Step 1: Add new test class to `test_help_search.py`**

Append:

```python
from help_search import MatchSpec, run_search


class TestMatchSpec:
    def _info(self, **kw):
        return CommandInfo(**kw)

    def test_run_search_uses_field_value(self):
        cmds = [self._info(command="hug bpush", description="push to origin", categories=["push-pull"])]
        specs = [MatchSpec(field="description", scorer=lambda q, t: 100 if q in t else 0,
                           weight=1.0, min_threshold=50, label="desc")]
        results = run_search("push", cmds, specs)
        assert len(results) == 1
        score, cmd, spec = results[0]
        assert cmd.command == "hug bpush"
        assert score == 100
        assert spec.label == "desc"

    def test_run_search_applies_weight(self):
        cmds = [self._info(command="x", description="desc", categories=[])]
        specs = [MatchSpec(field="description", scorer=lambda q, t: 100,
                           weight=0.5, min_threshold=0, label="desc")]
        results = run_search("anything", cmds, specs)
        assert results[0][0] == 50

    def test_run_search_filters_below_threshold(self):
        cmds = [self._info(command="x", description="d", categories=[])]
        specs = [MatchSpec(field="description", scorer=lambda q, t: 60,
                           weight=1.0, min_threshold=80, label="desc")]
        assert run_search("q", cmds, specs) == []

    def test_run_search_keeps_best_spec_per_command(self):
        cmds = [self._info(command="hug a", description="d", categories=[])]
        specs = [
            MatchSpec(field="description", scorer=lambda q, t: 50,
                      weight=1.0, min_threshold=0, label="desc"),
            MatchSpec(field="description", scorer=lambda q, t: 80,
                      weight=1.0, min_threshold=0, label="better"),
        ]
        score, _, spec = run_search("q", cmds, specs)[0]
        assert score == 80
        assert spec.label == "better"

    def test_existing_search_keyword_uses_run_search(self):
        # Regression: search_keyword still works after refactor.
        cmds = [
            CommandInfo(command="hug h undo", description="Move HEAD back, unstage changes.",
                        categories=["head"]),
        ]
        results = search_keyword(cmds, "undo")
        assert any(r.command == "hug h undo" for r in results)
```

**Step 2: Run tests — verify failures (`MatchSpec` not yet defined)**

Run: `make test-lib-py TEST_FILTER=test_help_search`
Expected: FAIL with `ImportError` for `MatchSpec` and `run_search`.

**Step 3: Add `MatchSpec` and `run_search` to `help_search.py`**

In `help_search.py`, near the existing `CommandInfo` definition:

```python
from collections.abc import Callable

@dataclass(frozen=True)
class MatchSpec:
    """One scoring rule: which field of an item to read, how to score against
    the query, what weight to apply, and what minimum threshold to require.
    """
    field: str
    scorer: Callable[[str, str], int]
    weight: float
    min_threshold: int
    label: str


def _read_field(item, field: str) -> list[str]:
    """Return zero or more strings for `field` on `item`.

    For composite fields like 'categories' (list-valued), returns each entry
    so each gets independently scored.
    """
    val = getattr(item, field, "")
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
    the highest scaled_score that meets its threshold. Sort descending by score.
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
```

**Step 4: Refactor `search_keyword` to use `run_search` (behavior-preserving)**

Replace the body of `search_keyword`:

```python
# Behavior-preserving refactor: same scorer, same threshold, same fields.
KEYWORD_SPECS_LEGACY = [
    MatchSpec(field="description", scorer=_fuzzy_score,
              weight=1.0, min_threshold=MIN_KEYWORD_SCORE, label="desc"),
    MatchSpec(field="command",     scorer=_fuzzy_score,
              weight=1.0, min_threshold=MIN_KEYWORD_SCORE, label="name"),
]


def search_keyword(commands: list[CommandInfo], query: str) -> list[CommandInfo]:
    return [item for _, item, _ in run_search(query, commands, KEYWORD_SPECS_LEGACY)]
```

(`command` field includes the `"hug "` prefix; current code strips it. To keep
parity, either strip in a helper or accept the prefix in scoring — `partial_ratio`
is unaffected. Keep the prefix; existing tests still pass because all fixtures
use `"hug <cmd>"` consistently.)

**Step 5: Run tests — verify all green**

Run: `make test-lib-py TEST_FILTER=test_help_search`
Expected: PASS — all original tests + 5 new MatchSpec tests.

**Step 6: Commit**
```
hug a git-config/lib/python/help_search.py git-config/lib/python/tests/test_help_search.py
hug c -m "refactor: introduce MatchSpec/run_search to drive scoring"
```

---

## Task 3: Wire category metadata into search; new `KEYWORD_SPECS`

**Files:**
- Modify: `git-config/lib/python/help_search.py`
- Modify: `git-config/lib/python/tests/test_help_search.py`

**WHY:** with `MatchSpec` in place, adding category fields is a one-line spec
addition. This is where curated keywords first start influencing relevance.

**Step 1: Extend `CommandInfo` with hydrated category metadata**

In `help_search.py`, replace `CommandInfo`:

```python
@dataclass
class CommandInfo:
    command: str = ""
    description: str = ""
    categories: list[str] = field(default_factory=list)
    # Derived at search time from CategoryMeta — joined with " " for scoring.
    category_desc: str = ""
    category_kw: str = ""
```

Add a helper:

```python
def hydrate_category_fields(
    commands: list[CommandInfo],
    cat_meta: dict[str, "CategoryMeta"],
) -> None:
    """Mutate each command in-place, populating category_desc and category_kw.

    Concatenates each of the command's categories' description + keywords.
    Joining is intentional: it lets a single MatchSpec score across all of a
    command's categories without nested loops.
    """
    for cmd in commands:
        descs, kws = [], []
        for cat_name in cmd.categories:
            meta = cat_meta.get(cat_name)
            if not meta:
                continue
            descs.append(meta.description)
            kws.extend(meta.keywords)
        cmd.category_desc = " ".join(descs)
        cmd.category_kw = " ".join(kws)
```

**Step 2: Add the new precision spec list**

```python
# Per-spec thresholds replace the global MIN_KEYWORD_SCORE for /keyword mode.
# WHY per-spec: partial_ratio>=70 on a free-text description is noisier than
# ratio>=88 on a curated keyword. Each scorer carries its own floor.
try:
    from thefuzz import fuzz as _fuzz
    _ratio = lambda q, t: _fuzz.ratio(q.lower(), t.lower())          # exact-ish
    _partial = lambda q, t: _fuzz.partial_ratio(q.lower(), t.lower()) # substring
    _wratio  = lambda q, t: _fuzz.WRatio(q.lower(), t.lower())        # hybrid
    _token_set = lambda q, t: _fuzz.token_set_ratio(q.lower(), t.lower())
except ImportError:
    # Fallback: substring-only (binary score).
    _ratio = _partial = _wratio = _token_set = lambda q, t: 100 if q.lower() in t.lower() else 0


KEYWORD_SPECS = [
    MatchSpec(field="command",       scorer=_ratio,    weight=1.00, min_threshold=90, label="name="),
    MatchSpec(field="command",       scorer=_partial,  weight=0.85, min_threshold=80, label="name~"),
    MatchSpec(field="description",   scorer=_wratio,   weight=0.90, min_threshold=80, label="desc"),
    MatchSpec(field="category_desc", scorer=_wratio,   weight=0.80, min_threshold=80, label="@cat-desc"),
    MatchSpec(field="category_kw",   scorer=_ratio,    weight=0.95, min_threshold=88, label="@cat-kw"),
]
```

Note: `category_kw` is the joined keyword string; `_ratio` against the WHOLE
joined string only fires when query equals one of the keywords (`"branch" ==
ratio("branch", "branch switch checkout ...")` ≈ low). To get exact-keyword
behavior, switch the field to a list and rely on `_read_field`'s list path —
`hydrate_category_fields` should store keywords as a list, not a joined string.

**Refinement of Step 1:** change `category_kw` to `list[str]`:

```python
@dataclass
class CommandInfo:
    command: str = ""
    description: str = ""
    categories: list[str] = field(default_factory=list)
    category_desc: str = ""
    category_kw: list[str] = field(default_factory=list)
```

```python
# In hydrate_category_fields:
cmd.category_kw = list(kws)   # not " ".join
```

Now `_read_field(cmd, "category_kw")` returns each keyword as a separate
string, and `_ratio(query, "branch") == 100` works as intended.

**Step 3: Replace the legacy spec list and rewrite `search_keyword`**

```python
def search_keyword(
    commands: list[CommandInfo],
    query: str,
    specs: list[MatchSpec] | None = None,
) -> list[CommandInfo]:
    return [item for _, item, _ in run_search(query, commands, specs or KEYWORD_SPECS)]
```

Delete `KEYWORD_SPECS_LEGACY` and the global `MIN_KEYWORD_SCORE` constant
(replaced by per-spec thresholds; keep a doc comment explaining).

**Step 4: Add tests for category-driven discovery**

```python
class TestKeywordSpecs:
    @pytest.fixture
    def commands(self):
        cmds = [
            CommandInfo(command="hug w wip", description="Park work-in-progress aside.",
                        categories=["working-dir", "parking"]),
            CommandInfo(command="hug b", description="Switch to a branch.",
                        categories=["branching"]),
        ]
        # Hydrate with fake category meta — keyword "save" claims parking.
        cat_meta = {
            "parking": CategoryMeta(
                name="parking", label="Parking",
                description="Park work-in-progress aside.",
                summary="Park work-in-progress aside.",
                keywords=("park", "save", "shelve", "wip")),
            "working-dir": CategoryMeta(
                name="working-dir", label="Working dir",
                description="Working tree operations.",
                summary="Working tree operations.",
                keywords=("working", "tree", "discard")),
            "branching": CategoryMeta(
                name="branching", label="Branching",
                description="Branch operations.", summary="Branch operations.",
                keywords=("branch", "switch")),
        }
        hydrate_category_fields(cmds, cat_meta)
        return cmds

    def test_finds_via_category_keyword(self, commands):
        # "save" only lives in the parking category's keywords.
        results = search_keyword(commands, "save")
        assert any(r.command == "hug w wip" for r in results)

    def test_direct_match_outranks_category_only(self, commands):
        # "branch" is a direct match for hug b's description AND a category keyword.
        # hug w wip should NOT outrank hug b just because parking has "wip".
        results = search_keyword(commands, "branch")
        assert results[0].command == "hug b"
```

**Step 5: Update `collect_metadata` to call `hydrate_category_fields`**

```python
def collect_metadata(
    bin_dir: str | Path,
    cache_dir: str | Path = _DEFAULT_CACHE_DIR,
    use_cache: bool = True,
    cat_meta: dict[str, "CategoryMeta"] | None = None,
) -> list[CommandInfo]:
    # ... existing body ...
    commands = sorted(commands, key=lambda c: c.command)
    if cat_meta:
        hydrate_category_fields(commands, cat_meta)
    return commands
```

The `main()` function will pass `load_categories(...)` in Task 10. Tests can
construct `cat_meta` directly.

**Step 6: Run tests — verify all green**

Run: `make test-lib-py TEST_FILTER=test_help_search`
Expected: PASS — old tests + new `TestKeywordSpecs` tests.

**Step 7: Commit**
```
hug a git-config/lib/python/help_search.py git-config/lib/python/tests/test_help_search.py
hug c -m "feat: extend keyword search to score against category description and keywords"
```

---

## Task 4: TDD — token-aware `!intent` mode

**Files:**
- Modify: `git-config/lib/python/help_search.py`
- Modify: `git-config/lib/python/tests/test_help_search.py`

**WHY:** today `!` aliases `/`. The design promotes it to a distinct mode
using `token_set_ratio` so multi-word phrases work without word-order or
stopword sensitivity.

**Step 1: Add failing tests**

```python
class TestIntentMode:
    @pytest.fixture
    def commands(self):
        cmds = [
            CommandInfo(command="hug w wip", description="Park work-in-progress aside.",
                        categories=["parking"]),
            CommandInfo(command="hug bpush", description="Push current branch to origin.",
                        categories=["push-pull"]),
        ]
        cat_meta = {
            "parking": CategoryMeta(name="parking", label="Parking",
                                    description="Park work-in-progress aside.",
                                    summary="Park work-in-progress aside.",
                                    keywords=("park", "save", "shelve", "wip")),
            "push-pull": CategoryMeta(name="push-pull", label="Remote sync",
                                      description="Sync with remotes.",
                                      summary="Sync with remotes.",
                                      keywords=("push", "pull", "remote")),
        }
        hydrate_category_fields(cmds, cat_meta)
        return cmds

    def test_intent_token_aware(self, commands):
        # "save my work" should find hug w wip via category keyword "save".
        results = search_intent(commands, "save my work")
        assert any(r.command == "hug w wip" for r in results)

    def test_intent_word_order_independent(self, commands):
        a = [r.command for r in search_intent(commands, "remote push")]
        b = [r.command for r in search_intent(commands, "push remote")]
        assert a == b
```

**Step 2: Add `INTENT_SPECS` and `search_intent`**

```python
INTENT_SPECS = [
    MatchSpec(field="description",   scorer=_token_set, weight=0.95, min_threshold=75, label="desc"),
    MatchSpec(field="category_desc", scorer=_token_set, weight=0.90, min_threshold=75, label="@cat-desc"),
    MatchSpec(field="category_kw",   scorer=_token_set, weight=0.80, min_threshold=75, label="@cat-kw"),
]


def search_intent(
    commands: list[CommandInfo],
    query: str,
    specs: list[MatchSpec] | None = None,
) -> list[CommandInfo]:
    return [item for _, item, _ in run_search(query, commands, specs or INTENT_SPECS)]
```

**Step 3: Update `main()` `!` branch**

```python
elif args.mode == "!":
    if not args.query:
        print("Usage: hug help !<intent>")
        print("Find commands by what you want to accomplish.")
        print("Example: hug help !push to remote")
        return
    results = search_intent(commands, args.query)
    print(f"Commands for '{args.query}':")
    print(format_results(results))
```

**Step 4: Run tests — verify green**

Run: `make test-lib-py TEST_FILTER=test_help_search`
Expected: PASS.

**Step 5: Commit**
```
hug c -m "feat: make !intent a token-aware mode distinct from /keyword"
```

---

## Task 5: Result cap + soft diversification + `--all` flag

**Files:**
- Modify: `git-config/lib/python/help_search.py`
- Modify: `git-config/lib/python/tests/test_help_search.py`

**Step 1: Add failing tests**

```python
class TestDiversify:
    def _scored(self, *items):
        # items: (score, command, primary_category)
        return [(s, CommandInfo(command=c, description="", categories=[cat]), None)
                for s, c, cat in items]

    def test_caps_results(self):
        from help_search import diversify
        scored = self._scored(
            (90, "hug a", "x"), (89, "hug b", "x"), (88, "hug c", "x"),
            (87, "hug d", "x"), (86, "hug e", "x"), (85, "hug f", "x"),
            (84, "hug g", "x"), (83, "hug h", "x"), (82, "hug i", "x"),
            (81, "hug j", "x"), (80, "hug k", "x"),
        )
        out = diversify(scored, cap=10)
        assert len(out) == 10

    def test_soft_diversify_penalises_same_category_excess(self):
        from help_search import diversify
        scored = self._scored(
            (90, "hug a", "branching"),
            (89, "hug b", "branching"),
            (88, "hug c", "branching"),
            (87, "hug d", "branching"),    # 4th from branching → penalised
            (86, "hug e", "staging"),      # should now outrank hug d
        )
        out = diversify(scored, cap=10, soft_cap_per_category=3, penalty=5)
        cmds = [c.command for _, c, _ in out]
        # First 3 branching keep order; 4th from branching falls below staging.
        assert cmds.index("hug e") < cmds.index("hug d")

    def test_all_flag_disables_cap(self):
        from help_search import diversify
        scored = self._scored(*[(80 - i, f"hug{i}", "x") for i in range(15)])
        out = diversify(scored, cap=None, soft_cap_per_category=None)
        assert len(out) == 15
```

**Step 2: Implement `diversify`**

```python
def diversify(
    scored: list[tuple[int, CommandInfo, MatchSpec | None]],
    cap: int | None = 10,
    soft_cap_per_category: int | None = 3,
    penalty: int = 5,
) -> list[tuple[int, CommandInfo, MatchSpec | None]]:
    """Cap to `cap` results; gently penalise per-category overflow.

    After `soft_cap_per_category` results from the same primary category, each
    additional same-category hit gets `penalty * extra_count` subtracted. Strong
    direct matches still beat weak cross-category hits — the penalty is small.

    Pass `cap=None` and/or `soft_cap_per_category=None` to disable.
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
```

**Step 3: Wire `diversify` into `search_keyword`/`search_intent` and add `--all`**

```python
def search_keyword(commands, query, specs=None, *, all_results=False):
    raw = run_search(query, commands, specs or KEYWORD_SPECS)
    out = diversify(raw, cap=None if all_results else 10,
                    soft_cap_per_category=None if all_results else 3)
    return [item for _, item, _ in out]


def search_intent(commands, query, specs=None, *, all_results=False):
    raw = run_search(query, commands, specs or INTENT_SPECS)
    out = diversify(raw, cap=None if all_results else 10,
                    soft_cap_per_category=None if all_results else 3)
    return [item for _, item, _ in out]
```

In `main()`:
```python
parser.add_argument("--all", action="store_true",
                    help="Disable result cap and per-category diversification.")
# ...
results = search_keyword(commands, args.query, all_results=args.all)
```

**Step 4: Update `format_results` to show overflow note**

```python
def format_results(commands: list[CommandInfo],
                   total: int | None = None) -> str:
    if not commands:
        return "  (none)"
    lines = []
    for cmd in commands:
        desc = cmd.description or "(no description)"
        lines.append(f"  {cmd.command:24s} - {desc}")
    if total is not None and total > len(commands):
        lines.append("")
        lines.append(f"  Showing top {len(commands)} of {total}. "
                     f"Pass --all to see all matches.")
    return "\n".join(lines)
```

In `main()`, compute `total` from the un-capped run for that note.

**Step 5: Run tests + smoke**

```bash
make test-lib-py TEST_FILTER=test_help_search
hug help /branch          # Should cap at 10
hug help /branch --all    # No cap, no diversification
```

**Step 6: Commit**
```
hug c -m "feat: cap search results to top 10 with soft per-category diversification"
```

---

## Task 6: TDD — `--explain` flag annotates each result

**Files:**
- Modify: `git-config/lib/python/help_search.py`
- Modify: `git-config/lib/python/tests/test_help_search.py`

**Step 1: Add failing tests**

```python
class TestExplain:
    def test_format_results_explain_shows_label_and_score(self):
        from help_search import format_results, MatchSpec
        cmd = CommandInfo(command="hug bc", description="Create a new branch", categories=["branching"])
        spec = MatchSpec(field="description", scorer=lambda q, t: 95, weight=1.0,
                         min_threshold=80, label="desc")
        out = format_results([cmd], details=[(95, cmd, spec)], explain=True)
        assert "[desc, 95]" in out

    def test_format_results_no_explain_omits_annotations(self):
        from help_search import format_results
        cmd = CommandInfo(command="hug bc", description="Create a new branch", categories=["branching"])
        out = format_results([cmd])
        assert "[desc" not in out
```

**Step 2: Extend `format_results`**

```python
def format_results(commands,
                   total: int | None = None,
                   details: list | None = None,
                   explain: bool = False) -> str:
    if not commands:
        return "  (none)"
    lines = []
    detail_map = {id(item): (score, spec) for score, item, spec in (details or [])}
    for cmd in commands:
        desc = cmd.description or "(no description)"
        line = f"  {cmd.command:24s} - {desc}"
        if explain and id(cmd) in detail_map:
            score, spec = detail_map[id(cmd)]
            line += f"   [{spec.label}, {score}]"
        lines.append(line)
    if total is not None and total > len(commands):
        lines.append("")
        lines.append(f"  Showing top {len(commands)} of {total}. "
                     f"Pass --all to see all matches.")
    return "\n".join(lines)
```

**Step 3: Wire `--explain` through `main()`**

```python
parser.add_argument("--explain", action="store_true",
                    help="Annotate each result with the matching field and score.")
explain = args.explain or os.environ.get("HUG_HELP_EXPLAIN") == "1"
# ... results, details = ... ; format_results(results, details=details, explain=explain)
```

For this to thread through, refactor `search_keyword`/`search_intent` to also
return the `(score, item, spec)` tuples optionally — or expose a parallel
`run_keyword(...)` returning the tuple list. Cleaner: add an internal helper

```python
def _run_with_specs(commands, query, specs, all_results):
    raw = run_search(query, commands, specs)
    capped = diversify(raw,
                       cap=None if all_results else 10,
                       soft_cap_per_category=None if all_results else 3)
    return capped, len(raw)  # (kept_tuples, total_before_cap)
```

Then `search_keyword`/`search_intent` call `_run_with_specs` and discard the
metadata; `main()` calls it directly to get the tuples for `--explain`.

**Step 4: Run tests + smoke**

```bash
make test-lib-py TEST_FILTER=test_help_search
hug help /branch --explain
```

**Step 5: Commit**
```
hug c -m "feat: add --explain flag annotating which spec matched each result"
```

---

## Task 7: Update `format_category_list` — summary column

**Files:**
- Modify: `git-config/lib/python/help_search.py`
- Modify: `git-config/lib/python/tests/test_help_search.py`

**Step 1: Add failing test**

```python
class TestFormatCategoryListWithMeta:
    def test_summary_column_present(self):
        from help_search import format_category_list
        cmds = [
            CommandInfo(command="hug bc", description="", categories=["branching"]),
            CommandInfo(command="hug b",  description="", categories=["branching"]),
            CommandInfo(command="hug a",  description="", categories=["staging"]),
        ]
        cat_meta = {
            "branching": CategoryMeta(name="branching", label="Branch ops",
                description="Create, list, switch, and delete branches.",
                summary="Create, list, switch, and delete branches.",
                keywords=("branch", "switch", "checkout")),
            "staging": CategoryMeta(name="staging", label="Staging area",
                description="Stage and unstage changes.",
                summary="Stage and unstage changes.",
                keywords=("stage", "add", "index")),
        }
        out = format_category_list(cmds, cat_meta=cat_meta)
        assert "@branching" in out
        assert "Create, list, switch, and delete branches" in out
        assert "(2)" in out  # two branching commands
        assert "to learn about a category and list its commands" in out
```

**Step 2: Update `format_category_list`**

```python
def format_category_list(
    commands: list[CommandInfo],
    cat_meta: dict[str, "CategoryMeta"] | None = None,
) -> str:
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
        lines.append(
            f"  @{cat:<{name_w}}  ({counts[cat]:>{count_w}}){sep}{summary}".rstrip()
        )
    lines += [
        "",
        "Use `hug help @<category>` to learn about a category and list its commands.",
        "Use `hug help /<keyword>` for keyword search, or `hug help !<intent>` "
        "for natural-language search.",
    ]
    return "\n".join(lines)
```

In `main()` `@` branch (no query): pass `cat_meta` through.

**Step 3: Run tests + smoke**

```bash
make test-lib-py TEST_FILTER=test_help_search
hug help @
```

**Step 4: Commit**
```
hug c -m "feat: add summary column to `hug help @` listing"
```

---

## Task 8: Boxed `@<category>` page

**Files:**
- Modify: `git-config/lib/python/help_search.py`
- Modify: `git-config/lib/python/tests/test_help_search.py`

**Step 1: Add failing tests**

```python
class TestFormatCategoryPage:
    def test_includes_label_and_paragraph(self):
        from help_search import format_category_page
        meta = CategoryMeta(name="branching", label="Branch operations",
            description="Create, list, switch, and delete branches.\nDetails follow.",
            summary="Create, list, switch, and delete branches.",
            keywords=("branch", "switch", "checkout"))
        cmds = [CommandInfo(command="hug bc", description="Create a new branch.",
                            categories=["branching"])]
        out = format_category_page(meta, cmds, width=72)
        assert "@branching" in out
        assert "Branch operations" in out
        assert "Create, list, switch, and delete branches." in out
        assert "branch, switch, checkout" in out
        assert "hug bc" in out
        assert "Create a new branch." in out

    def test_decorations_routed_to_stderr_layer(self):
        # The function returns a tuple (stderr_text, stdout_text) so the caller
        # can route correctly per stdout/stderr discipline.
        from help_search import format_category_page
        meta = CategoryMeta(name="x", label="X", description="A.", summary="A.",
                            keywords=("a", "b", "c"))
        stderr_text, stdout_text = format_category_page(meta, [], width=72,
                                                        split_streams=True)
        assert "──" in stderr_text  # box rules
        assert "──" not in stdout_text
        assert stdout_text == ""  # no commands → empty data section
```

**Step 2: Implement `format_category_page`**

```python
import textwrap


def _rule(title: str, width: int) -> str:
    """`── <title> ─────...` rule, total length = width."""
    head = f"── {title} "
    return head + "─" * max(0, width - len(head))


def format_category_page(
    meta: CategoryMeta,
    commands: list[CommandInfo],
    width: int = 72,
    split_streams: bool = False,
) -> str | tuple[str, str]:
    """Render the boxed category page.

    If split_streams is True, returns (stderr_text, stdout_text):
      - stderr: rules, headings, paragraph, keywords, tip
      - stdout: command list (data)
    Otherwise returns a single combined string for tests / non-TTY use.
    """
    width = max(40, min(width, 100))

    # Header
    chatter = [_rule(f"@{meta.name} — {meta.label}", width), ""]
    chatter += textwrap.wrap(meta.description.replace("\n", " ").strip(),
                             width=width) or [""]
    chatter += ["", _rule("Keywords", width), ""]
    chatter += textwrap.wrap(", ".join(meta.keywords), width=width)
    chatter += ["", _rule(f"Commands ({len(commands)})", width), ""]

    # Data
    data_lines: list[str] = []
    for cmd in commands:
        desc = cmd.description or "(no description)"
        data_lines.append(f"  {cmd.command:24s} - {desc}")

    tip = ["", "Tip: `hug help <command>` for full help on any command."]

    if split_streams:
        stderr_text = "\n".join(chatter + tip)
        stdout_text = "\n".join(data_lines)
        return stderr_text, stdout_text

    return "\n".join(chatter + data_lines + tip)
```

**Step 3: Wire into `main()` `@<query>` branch**

```python
elif args.mode == "@":
    if not args.query:
        print(format_category_list(commands, cat_meta=cat_meta))
        return
    # Direct hit by exact name first; fall back to fuzzy.
    meta = (cat_meta or {}).get(args.query)
    if meta is None:
        # fuzzy category match (existing behavior) → if exactly one, use it; else legacy listing
        matched = [m for m in (cat_meta or {}).values()
                   if _fuzzy_score_strict(args.query, m.name) >= MIN_CATEGORY_SCORE]
        if len(matched) == 1:
            meta = matched[0]
    if meta is not None:
        cmds_in = [c for c in commands if meta.name in c.categories]
        width = _terminal_width()
        stderr_text, stdout_text = format_category_page(meta, cmds_in,
                                                        width=width,
                                                        split_streams=True)
        print(stderr_text, file=sys.stderr)
        if stdout_text:
            print(stdout_text)
        return
    # Fallback to legacy listing for ambiguous fuzzy matches
    results = search_category(commands, args.query)
    print(f"Commands in category '{args.query}':", file=sys.stderr)
    print(format_results(results))
```

Add `_terminal_width()`:

```python
def _terminal_width(default: int = 72) -> int:
    try:
        return os.get_terminal_size().columns
    except OSError:
        return default
```

**Step 4: Run tests + smoke**

```bash
make test-lib-py TEST_FILTER=test_help_search
hug help @branching                # Boxed page on stderr; commands on stdout
hug help @branching | grep bpush   # Should still find bpush — data is on stdout
```

**Step 5: Commit**
```
hug c -m "feat: render @<category> as boxed page with stdout/stderr discipline"
```

---

## Task 9: Update `git-hughelp` no-arg tip lines

**Files:**
- Modify: `git-config/bin/git-hughelp`

**Step 1: Replace the `Topic search:` block**

Lines 22-25 of `git-hughelp` currently read:
```
  echo 'Topic search:'
  echo '  hug help /keyword   - Search commands by keyword (fuzzy)'
  echo '  hug help @category  - Browse commands by category'
  echo '  hug help !intent    - Find commands by what you want to do'
```

Replace with:
```bash
  echo 'Topic search:'
  echo '  hug help /<keyword>  - Search commands by keyword (fuzzy)'
  echo '  hug help @           - List all categories'
  echo '  hug help @<category> - Learn about a category and list its commands'
  echo '  hug help !<intent>   - Find commands by what you want to do'
```

**Step 2: Smoke test**

```bash
hug help                  # Topic search section shows the new lines
hug help @                # Lists categories with summaries
hug help @branching       # Boxed page
```

**Step 3: Commit**
```
hug a git-config/bin/git-hughelp
hug c -m "docs: clarify @ tip line — distinguish @ listing from @<category>"
```

---

## Task 10: Wire validation + cache extension

**Files:**
- Modify: `git-config/lib/python/help_search.py`
- Modify: `git-config/lib/python/tests/test_help_search.py`
- Modify: `git-config/lib/python/tests/test_category_meta.py`

**Step 1: Tests — runtime validation in `main()`**

In `test_help_search.py`:

```python
class TestRuntimeValidation:
    def test_main_exits_1_when_script_category_missing_manifest(self, tmp_path, monkeypatch, capsys):
        # Build a bin dir with one script declaring 'flubber' (no manifest).
        bin_dir = tmp_path / "bin"
        bin_dir.mkdir()
        s = bin_dir / "git-frob"
        s.write_text("#!/usr/bin/env bash\n"
                     "test \"${1:-}\" = '--search-meta' && "
                     "{ printf 'category = [\"flubber\"]\\n'; exit 0; }\n"
                     "test \"${1:-}\" = '--help' && "
                     "{ printf 'hug frob: Frob the wibble.\\n'; exit 0; }\n")
        s.chmod(0o755)
        cat_dir = tmp_path / "categories"
        cat_dir.mkdir()  # empty: no manifest for 'flubber'

        from help_search import main as help_main
        monkeypatch.setattr("sys.argv", ["help_search.py", "@",
                                          "--bin-dir", str(bin_dir),
                                          "--cache-dir", str(tmp_path / "cache"),
                                          "--categories-dir", str(cat_dir)])
        with pytest.raises(SystemExit) as exc_info:
            help_main()
        assert exc_info.value.code == 1
        err = capsys.readouterr().err
        assert "flubber" in err
```

**Step 2: Add `--categories-dir` arg and validation in `main()`**

```python
_DEFAULT_CATEGORIES_DIR = os.path.join(os.path.dirname(__file__), "categories")


def main():
    parser = argparse.ArgumentParser(description="Hug help topic search")
    parser.add_argument("mode", choices=["/", "@", "!"], help="Search mode")
    parser.add_argument("query", nargs="?", default="")
    parser.add_argument("--bin-dir", default=_DEFAULT_BIN_DIR)
    parser.add_argument("--cache-dir", default=_DEFAULT_CACHE_DIR)
    parser.add_argument("--categories-dir", default=_DEFAULT_CATEGORIES_DIR)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--explain", action="store_true")
    args = parser.parse_args()

    from category_meta import load_categories, validate_against_scripts
    cat_meta = load_categories(args.categories_dir)
    commands = collect_metadata(args.bin_dir, cache_dir=args.cache_dir,
                                cat_meta=cat_meta)
    used = {c for cmd in commands for c in cmd.categories}
    errors = validate_against_scripts(cat_meta, used)
    if errors:
        for e in errors:
            print(f"error: {e}", file=sys.stderr)
        sys.exit(1)
    # ... existing dispatch ...
```

**Step 3: Cache extension — track `categories_mtime_max`**

In `_load_cache`/`_save_cache` or `collect_metadata`, after computing `cache`,
also store the latest mtime across `categories/*.toml`:

```python
def _categories_mtime_max(categories_dir: str | Path) -> float:
    return max((p.stat().st_mtime for p in Path(categories_dir).glob("*.toml")),
               default=0.0)
```

In `collect_metadata`, accept `categories_dir` and:

```python
mtime_max = _categories_mtime_max(categories_dir) if categories_dir else 0.0
cache_meta = cache.get("_meta", {})
if cache_meta.get("categories_mtime_max", 0.0) < mtime_max:
    # Categories changed — invalidate by clearing per-script entries that have
    # category-derived fields (i.e. all of them).
    cache = {"_meta": {"categories_mtime_max": mtime_max}}
    updated = True
```

Add a test in `test_help_search.py::TestCache` covering this.

**Step 4: Pytest hook for static validation**

In `test_category_meta.py`, add:

```python
class TestRepoIntegrity:
    """Real repo: every category referenced by a real script must have a manifest."""

    def test_all_used_categories_have_manifests(self):
        import re
        repo_root = Path(__file__).resolve().parents[3]
        bin_dir = repo_root / "git-config" / "bin"
        cat_dir = repo_root / "git-config" / "lib" / "python" / "categories"
        used: set[str] = set()
        for script in bin_dir.glob("git-*"):
            text = script.read_text(errors="ignore")
            m = re.search(r"_hug_category=\'(\[.*?\])\'", text)
            if not m:
                continue
            for raw in re.findall(r'"([^"]+)"', m.group(1)):
                used.add(raw)
        cats = load_categories(cat_dir)
        errors = validate_against_scripts(cats, used)
        assert errors == [], "\n".join(errors)
```

**Step 5: Run all Python tests + smoke**

```bash
make test-lib-py
hug help @                # Validates at startup; should pass since Task 0 covered all 19
```

**Step 6: Commit**
```
hug c -m "feat: enforce category manifest completeness at runtime and in tests"
```

---

## Task 11: Quality regression corpus

**Files:**
- Create: `git-config/lib/python/tests/test_quality_corpus.py`

**WHY:** with multiple knobs (per-spec thresholds, weights, diversification),
threshold tuning is a moving target. A small set of golden queries → expected
top-3 results acts as a regression net.

**Step 1: Create the corpus**

```python
"""Quality regression corpus for help_search.

Pinned golden queries with expected top-3 results. Adjust if the scoring
model genuinely improves; the file is the contract.
"""
from pathlib import Path

import pytest

from category_meta import load_categories
from help_search import collect_metadata, search_keyword, search_intent


REPO = Path(__file__).resolve().parents[3]


@pytest.fixture(scope="module")
def commands():
    cats = load_categories(REPO / "git-config" / "lib" / "python" / "categories")
    return collect_metadata(REPO / "git-config" / "bin", use_cache=False, cat_meta=cats)


@pytest.mark.parametrize("query,expected_in_top3", [
    ("undo",     ["hug h undo", "hug h rollback"]),
    ("push",     ["hug bpush"]),
    ("branch",   ["hug b", "hug bc"]),
    ("worktree", ["hug wtl", "hug wtc"]),
])
def test_keyword_corpus(commands, query, expected_in_top3):
    results = [c.command for c in search_keyword(commands, query)][:3]
    for cmd in expected_in_top3:
        assert cmd in results, f"{query!r}: {cmd} not in top-3 ({results})"


@pytest.mark.parametrize("query,expected_in_top3", [
    ("save my work in progress", ["hug w wip"]),
    ("show me what changed",     ["hug sw", "hug ss"]),
    ("push to remote",           ["hug bpush"]),
])
def test_intent_corpus(commands, query, expected_in_top3):
    results = [c.command for c in search_intent(commands, query)][:3]
    for cmd in expected_in_top3:
        assert cmd in results, f"{query!r}: {cmd} not in top-3 ({results})"
```

**Step 2: Run corpus**

```bash
make test-lib-py TEST_FILTER=test_quality_corpus
```

If a query fails, **first** verify the expectation is reasonable; then tune
weights/thresholds in `KEYWORD_SPECS`/`INTENT_SPECS`. Commit any tuning
adjustments separately, with the corpus test as justification.

**Step 3: Commit**
```
hug a git-config/lib/python/tests/test_quality_corpus.py
hug c -m "test: add quality regression corpus for /keyword and !intent"
```

---

## Task 12: Extend integration BATS tests

**Files:**
- Modify: `tests/integration/test_help_topic_search.bats`

**Step 1: Add new cases at the end of the file**

```bash
# --- New: rich @<category> page ---

@test "hug help @branching - shows boxed header on stderr" {
    cd "$TEST_TEMP_DIR"
    run bash -c 'hug help @branching 2>&1 1>/dev/null'
    assert_success
    assert_output --partial "@branching"
    assert_output --partial "Branch operations"
    assert_output --partial "Keywords"
}

@test "hug help @branching - command list reaches stdout" {
    cd "$TEST_TEMP_DIR"
    run bash -c 'hug help @branching 2>/dev/null'
    assert_success
    assert_output --partial "hug bc"
}

@test "hug help @branching | grep - data is pipe-safe" {
    cd "$TEST_TEMP_DIR"
    run bash -c 'hug help @branching 2>/dev/null | grep "hug bc"'
    assert_success
}

@test "hug help @ - lists categories with summary column" {
    cd "$TEST_TEMP_DIR"
    run hug help @
    assert_success
    assert_output --partial "@branching"
    assert_output --partial "—"   # em-dash separator before summary
}

@test "hug help @ - tip line mentions 'learn about a category'" {
    cd "$TEST_TEMP_DIR"
    run hug help @
    assert_success
    assert_output --partial "learn about a category and list its commands"
}

# --- New: !intent token-aware ---

@test "hug help !save my work - finds the wip command via category keyword" {
    cd "$TEST_TEMP_DIR"
    run bash -c "hug help '!save my work'"
    assert_success
    assert_output --partial "hug w wip"
}

# --- New: --explain flag ---

@test "hug help /branch --explain - annotates with match source" {
    cd "$TEST_TEMP_DIR"
    run hug help /branch --explain
    assert_success
    assert_output --partial "[desc"
}

# --- New: --all disables cap ---

@test "hug help /branch --all - returns more than 10 results when applicable" {
    cd "$TEST_TEMP_DIR"
    run hug help /branch --all
    assert_success
    # We don't lock in a specific N here; just assert no overflow note appears.
    refute_output --partial "Pass --all to see all matches"
}

# --- New: validation failure exits 1 ---

# (Smoke; the comprehensive test is in pytest. We only check the wiring.)
@test "hug help @ - exits 0 in healthy repo" {
    cd "$TEST_TEMP_DIR"
    run hug help @
    assert_success
}
```

**Step 2: Run integration tests**

```bash
make test-integration TEST_FILE=test_help_topic_search
```
Expected: PASS — all 13 existing + 9 new.

**Step 3: Commit**
```
hug a tests/integration/test_help_topic_search.bats
hug c -m "test: extend topic search BATS coverage for @<cat> page, !intent, --explain"
```

---

## Task 13: Final validation

**Step 1: Run the full test suite**
```bash
make test
```
Expected: all green (BATS + pytest).

**Step 2: Run sanitize**
```bash
make sanitize
```
Expected: no lint/format/type issues.

**Step 3: Manual smoke walkthrough**

```bash
hug help                            # No-arg: groups + 4 topic-search lines
hug help s                          # Prefix search: unchanged
hug help h                          # Prefix search: unchanged with extras
hug help @                          # Catalog with summary column
hug help @branching                 # Boxed page on stderr; commands on stdout
hug help @branching | head -5       # Pipe-safe data section
hug help @branching --explain       # Should have no effect on @ — graceful
hug help /branch                    # Top-10, no overflow note if <10
hug help /branch --all              # Full list
hug help /branch --explain          # Annotated
hug help '!save my work'            # Token-aware: finds w wip via category keyword
hug help '!push to remote'          # Should find bpush regardless of word order
HUG_HELP_EXPLAIN=1 hug help /undo   # Env-var path also works
```

**Step 4: Update top-level `README.md` if topic search section needs changes**
(usually no — the section is generic. Skip if irrelevant.)

**Step 5: Commit any fixes from validation**
```
hug c -m "fix: address issues found during final validation"
```
(Skip if nothing to fix.)

---

## Task Summary

| # | Description | Depends on |
|---|---|---|
| 0 | Bootstrap 19 category TOML manifests | — |
| 1 | TDD `category_meta.py` loader + validator | 0 |
| 2 | TDD `MatchSpec` + `run_search` refactor (behavior-preserving) | 1 |
| 3 | Wire category fields into `KEYWORD_SPECS`; new precision spec list | 2 |
| 4 | Token-aware `INTENT_SPECS` and `search_intent` | 3 |
| 5 | Result cap + soft diversification + `--all` | 4 |
| 6 | `--explain` flag with match-source annotation | 5 |
| 7 | Summary column in `format_category_list` | 6 |
| 8 | Boxed `@<category>` page with stderr/stdout split | 7 |
| 9 | Update `git-hughelp` no-arg tip lines | 8 |
| 10 | Wire validation + cache extension into `main()` | 9 |
| 11 | Quality regression corpus | 10 |
| 12 | Extend integration BATS tests | 11 |
| 13 | Final validation | 12 |
