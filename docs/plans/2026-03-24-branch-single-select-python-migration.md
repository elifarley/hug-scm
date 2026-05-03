<!-- /autoplan restore point: /home/ecc/.gstack/projects/elifarley-hug-scm/main-autoplan-restore-20260324-195643.md -->
# Unified Selection Framework + Branch Single-Select Migration — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Create a shared selection toolkit (`selection_core.py`) that eliminates ~240 lines of duplicated code across 4 Python modules, then use it to migrate `print_interactive_branch_menu()` to Python.

**Architecture:** `selection_core.py` provides `bash_escape`, `BashDeclareBuilder`, `parse_numbered_input`, `get_selection_input`, `add_common_cli_args`, and ANSI color constants. Existing modules (`tag_select.py`, `worktree_select.py`, `branch_select.py`, `branch_filter.py`) refactor to import from it. Branch single-select (`prepare`/`single-select` CLI commands) added to `branch_select.py`. Bash adapter shrinks `print_interactive_branch_menu` from ~60 to ~25 lines.

**Tech Stack:** Python 3 (dataclasses, argparse), Bash, BATS, pytest

**Design doc:** `~/.gstack/projects/elifarley-hug-scm/ecc-main-design-20260324-194422.md`
**In-repo design:** `docs/plans/2026-03-24-branch-single-select-python-migration-design.md`

---

### Task 0: Baseline — verify all tests pass

**Files:**
- None modified

**Step 1: Run existing BATS tests**

Run: `make test-bash TEST_FILTER="branch"`
Expected: All branch-related tests pass

**Step 2: Run existing pytest tests**

Run: `make test-lib-py`
Expected: All Python tests pass

---

### Task 1: Create selection_core.py — bash_escape and BashDeclareBuilder

**Files:**
- Create: `git-config/lib/python/git/selection_core.py`
- Create: `git-config/lib/python/tests/test_selection_core.py`

**Step 1: Write failing tests for bash_escape**

Test the canonical escaping function: simple strings, single quotes, backslashes,
empty strings, newlines, special characters. These tests should match the behavior
of the existing `_bash_escape()` in `tag_select.py`.

**Step 2: Write failing tests for BashDeclareBuilder**

Test: `add_array` produces `declare -a name=('v1' 'v2')`, `add_scalar` produces
`declare name='val'`, `add_int` produces `declare -i name=42`. Test variable name
validation raises `ValueError` on invalid names. Test `build()` produces newline-
separated output. Test escaping of values with special characters.

**Step 3: Implement bash_escape and BashDeclareBuilder**

Extract `bash_escape` from `tag_select.py` (canonical source). Implement
`BashDeclareBuilder` with variable name validation (`[a-zA-Z_][a-zA-Z0-9_]*`).

**Step 4: Run tests**

Run: `make test-lib-py TEST_FILTER="test_selection_core"`
Expected: All tests pass

---

### Task 2: Add parse_numbered_input and get_selection_input to selection_core.py

**Files:**
- Modify: `git-config/lib/python/git/selection_core.py`
- Modify: `git-config/lib/python/tests/test_selection_core.py`

**Step 1: Write failing tests for parse_numbered_input**

Test: single numbers, comma-separated, ranges, "all"/"a", empty input, invalid input,
out of bounds, duplicates. These should match `branch_select.py`'s `parse_user_input()`
behavior (the canonical source, with `allow_all` parameter).

**Step 2: Write failing tests for get_selection_input**

Test precedence: `test_selection` arg wins over env var, env var wins over stdin.
Test EOFError returns empty string.

**Step 3: Implement both functions**

`parse_numbered_input`: port from `branch_select.py`'s `parse_user_input` (add
`allow_all=True` parameter, matching existing behavior).

`get_selection_input`: extract from the three-way check pattern in `branch_select.py`.

**Step 4: Add add_common_cli_args and ANSI color constants**

`add_common_cli_args(parser)`: adds `--placeholder`, `--selection`, `--no-gum`.
Color constants: YELLOW, BLUE, GREY, CYAN, GREEN, NC (matching `hug-terminal`).

**Step 5: Run tests**

Run: `make test-lib-py TEST_FILTER="test_selection_core"`
Expected: All tests pass

---

### Task 3: Refactor tag_select.py to use selection_core

**Files:**
- Modify: `git-config/lib/python/git/tag_select.py`
- Modify: `git-config/lib/python/tests/test_tag_select.py`

**Step 1: Replace _bash_escape with import**

Replace `from git.tag_select import _bash_escape` usage (and the local definition)
with `from git.selection_core import bash_escape`.

**Step 2: Replace parse_numbered_input with import**

Replace the local `parse_numbered_input` with import from `selection_core`.

**Step 3: Replace inline declare output with BashDeclareBuilder**

Replace `to_bash_declare()` and `tags_to_bash_declare()` f-string patterns with
`BashDeclareBuilder`.

**Step 4: Add --selection CLI flag**

Add `--selection` flag (matching `branch_select.py`) so `get_selection_input()`
can serve the module. Replace inline `input()` / env var checks with
`get_selection_input()`.

**Step 5: Run tests**

Run: `make test-lib-py TEST_FILTER="test_tag_select"`
Expected: All existing tests pass (zero behavior change)

Run: `make test-bash TEST_FILTER="tag"`
Expected: All BATS tag tests pass

---

### Task 4: Refactor worktree_select.py to use selection_core

**Files:**
- Modify: `git-config/lib/python/git/worktree_select.py`
- Modify: `git-config/lib/python/tests/test_worktree_select.py`

**Step 1: Replace _bash_escape with import**

**Step 2: Replace inline declare output with BashDeclareBuilder**

Replace `worktrees_to_bash_declare()` and `selection_to_bash_declare()` with
`BashDeclareBuilder`.

**Step 3: Add --selection CLI flag and use get_selection_input**

**Step 4: Run tests**

Run: `make test-lib-py TEST_FILTER="test_worktree_select"`
Expected: All existing tests pass

Run: `make test-bash TEST_FILTER="worktree"`
Expected: All BATS worktree tests pass

---

### Task 5: Refactor branch_select.py and branch_filter.py to use selection_core

**Files:**
- Modify: `git-config/lib/python/git/branch_select.py`
- Modify: `git-config/lib/python/git/branch_filter.py`
- Modify: `git-config/lib/python/tests/test_branch_select.py`
- Modify: `git-config/lib/python/tests/test_branch_filter.py`

**Step 1: Replace _bash_escape in both modules with import**

**Step 2: Replace parse_user_input with parse_numbered_input from selection_core**

Rename all references from `parse_user_input` to `parse_numbered_input`. Update
test imports accordingly.

**Step 3: Replace inline declare output with BashDeclareBuilder**

Replace `SelectedBranches.to_bash_declare()` and `FilteredBranches.to_bash_declare()`
with `BashDeclareBuilder`.

**Step 4: Remove _should_use_gum**

Delete the dead code `_should_use_gum()` function and its imports. The gum path
is handled by Bash (per design doc Premise #2). The existing `select` command's
gum path is a dead code branch (falls through to `pass` with a TODO).

**Step 5: Use get_selection_input**

Replace the inline three-way input check in `multi_select_branches()` with
`get_selection_input()`.

**Step 6: Run tests**

Run: `make test-lib-py TEST_FILTER="test_branch"`
Expected: All existing tests pass

Run: `make test-bash TEST_FILTER="branch"`
Expected: All BATS branch tests pass

---

### Task 6: Add SingleSelectResult and format_single_select_options to branch_select.py

**Files:**
- Modify: `git-config/lib/python/git/branch_select.py`
- Modify: `git-config/lib/python/tests/test_branch_select.py`

**Step 1: Write failing tests for SingleSelectResult**

Test: dataclass construction (selected, cancelled, no_branches), `to_bash_declare()`
output (declare statements with correct variable names), escaping of special chars.

**Step 2: Write failing tests for format_single_select_options**

Test: current branch gets green marker, hash/date/subject/track formatting with ANSI,
empty optional fields, inconsistent array lengths raises ValueError.

**Step 3: Implement SingleSelectResult**

```python
@dataclass
class SingleSelectResult:
    status: str   # "selected" | "cancelled" | "no_branches"
    branch: str   # empty unless status == "selected"
    index: int    # -1 if not selected

    def to_bash_declare(self) -> str:
        b = BashDeclareBuilder()
        b.add_scalar("selected_branch", self.branch)
        b.add_scalar("selection_status", self.status)
        b.add_int("selected_index", self.index)
        return b.build()
```

**Step 4: Implement format_single_select_options**

Domain-owned formatting (not shared) — formats with current branch green marker,
ANSI colors for hash/date/track/subject. Uses color constants from selection_core.

**Step 5: Run tests**

Run: `make test-lib-py TEST_FILTER="test_branch_select"`
Expected: All tests pass

---

### Task 7: Add single_select_branches and CLI commands (prepare, single-select)

**Files:**
- Modify: `git-config/lib/python/git/branch_select.py`
- Modify: `git-config/lib/python/tests/test_branch_select.py`

**Step 1: Write failing tests for single_select_branches**

Test: returns selected branch, returns cancelled on empty input, returns no_branches
for empty list, respects HUG_TEST_NUMBERED_SELECTION env var, invalid input returns
cancelled, out of bounds returns cancelled, displays numbered list.

**Step 2: Write failing tests for CLI prepare command**

Test: outputs `declare -a formatted_options=(...) selection_status='ready' branch_count=N`.
Test: formats with current branch marker.

**Step 3: Write failing tests for CLI single-select command**

Test: outputs `declare selected_branch=... selection_status='selected'`.
Test: cancelled status.

**Step 4: Implement single_select_branches**

Uses `format_single_select_options()`, `get_selection_input()`, returns
`SingleSelectResult`.

**Step 5: Add prepare and single-select to CLI main()**

Extend argparse choices with `"prepare"` and `"single-select"`. Add
`--current-branch` flag. The existing `select` (multi) and `format-options`
commands remain unchanged.

**Step 6: Run tests**

Run: `make test-lib-py TEST_FILTER="test_branch_select"`
Expected: All tests pass

---

### Task 8: Bash adapter — refactor print_interactive_branch_menu()

**Files:**
- Modify: `git-config/lib/hug-git-branch`

**Step 1: Refactor print_interactive_branch_menu to use Python**

Replace the inline formatting loops (lines ~217-268) with Python CLI calls:
- Gum path: `python3 branch_select.py prepare ...` → eval → formatted_options
  → `get_gum_selection_index` → branch lookup
- Non-gum path: `python3 branch_select.py single-select ... --no-gum` → eval
  → `selected_branch`, `selection_status`

Bash adapter reads `selected_branch` from eval output and assigns to the nameref.

**Step 2: Verify callers unchanged**

`git-b`, `git-wtc`, `select_branches()`, and `single_select_branch()` all call
`print_interactive_branch_menu()` — function signature preserved.

**Step 3: Run BATS tests**

Run: `make test-bash TEST_FILTER="branch"`
Expected: All branch-related BATS tests pass

---

### Task 9: Full regression validation

**Files:**
- None modified (validation only)

**Step 1: Run full test suite**

Run: `make test`
Expected: All BATS and pytest tests pass

**Step 2: Verify selection_core.py is the single source**

Confirm: no remaining `_bash_escape` definitions in tag_select.py, worktree_select.py,
branch_select.py, or branch_filter.py. Only imports from selection_core.

---

### Task 10: Documentation update

**Files:**
- Modify: `git-config/lib/python/README.md`

**Step 1: Document selection_core.py**

Add section documenting the shared toolkit: `bash_escape`, `BashDeclareBuilder`,
`parse_numbered_input`, `get_selection_input`, `add_common_cli_args`.

**Step 2: Document branch_select.py new commands**

Add `prepare` and `single-select` CLI commands to the branch_select.py documentation.

**Step 3: Update the New Domain Checklist**

Document the convention for adding new selection domains (from design doc).

**Step 4: Run final tests**

Run: `make test`
Expected: All tests pass

---

<!-- AUTONOMOUS DECISION LOG -->
## Decision Audit Trail

| # | Phase | Decision | Principle | Rationale | Rejected |
|---|-------|----------|-----------|-----------|----------|
| 1 | CEO | Accept: Add error-guard to Bash adapter (Task 8) | P1+P5 | Silent variable corruption on Python failure is unacceptable for git-b | — |
| 2 | CEO | Accept: Elevate select_wip_branch no-gum fix | P2 | Same file, in blast radius, user-facing bug | git-brestore (different file) |
| 3 | CEO | **APPROVED**: Null-delimiter for new prepare/single-select commands | P1 | User chose completeness; both CEO+Eng flagged independently | Defer option |
| 4 | CEO | Defer: Protocol stub | P3 | Nice documentation, not critical for 5 domains | — |
| 5 | CEO | Defer: Split into 2 PRs | P3 | Implementer decides at execution time | — |
| 6 | CEO | Accept: BATS test for branch with spaces | P1 | Documents known limitation, cheap | — |
| 7 | Eng | Accept: Validate Python stdout before eval | P1+P5 | Injection risk if stray print() added; low-cost guard | — |
| 8 | Eng | Accept: Document selected_index=-1 sentinel contract | P5 | Callers MUST check selection_status, not index | — |
| 9 | Eng | Accept: Enforce monkeypatch for env var in tests | P1 | Prevent test pollution across BATS/pytest | — |
| 10 | Eng | Accept: Write parse_single_input for single-select | P5 | Multi-select parser silently discards invalid input; wrong UX | — |
| 11 | Eng | Accept: Fix Task 3 Step 1 description | P5 | Import direction was wrong in plan text | — |
| 12 | Eng | Accept: Document empty-subjects invariant + test | P1 | Behavior preserved by accident, needs explicit test | — |
| 13 | Eng | Accept: Add BATS eval round-trip tests | P1 | Critical gap — Python tests don't verify Bash eval | — |
| 14 | Eng | Accept: Note _should_use_gum bug in deletion commit | P3 | Trivial, preserves knowledge | — |
| 15 | Eng | Accept: Parameterize add_common_cli_args(include_no_gum) | P5 | Don't add dead flags to tag/worktree modules | — |

## NOT in Scope

- `select_files_with_status()` migration — most complex domain (~240 lines), deferred
- `git-us`, `git-untrack`, `git-bdel-backup` inline selections — separate task
- `git-brestore` 4-arg bug — different file, different blast radius
- Unifying `branch_select.py` + `branch_filter.py` — premature
- Python calling git directly for branches — existing data flow works

## What Already Exists

| Sub-problem | Existing code | Reuse approach |
|-------------|--------------|----------------|
| bash_escape | tag_select.py:_bash_escape (canonical, best documented) | Extract to selection_core |
| parse_numbered_input | branch_select.py:parse_user_input (has allow_all) | Extract to selection_core |
| Input reading (test/env/stdin) | branch_select.py:multi_select_branches lines 394-406 | Extract to get_selection_input |
| ANSI color formatting | branch_select.py:format_multi_select_options | Pattern for new format_single_select_options |
| Two-mode CLI (prepare/select) | tag_select.py + worktree_select.py | Precedent for new commands |
| Gum index lookup | hug-git-branch:get_gum_selection_index | Stays in Bash, not migrated |

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 1 | clean | 6 findings (1 high, 2 medium, 3 low) |
| Eng Review | `/plan-eng-review` | Architecture & tests | 1 | clean | 10 findings (2 critical, 2 high, 4 medium, 2 low) |
| CEO Voices | `/autoplan` | Independent subagent | 1 | subagent-only | Codex unavailable |
| Eng Voices | `/autoplan` | Independent subagent | 1 | subagent-only | Codex unavailable |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | skipped | No UI scope |

**VERDICT:** APPROVED — 15 auto-decisions + 1 user taste decision (null-delimiter: accepted). All critical findings resolved via accepted decisions. Cross-phase theme (space-split + eval safety) addressed.
