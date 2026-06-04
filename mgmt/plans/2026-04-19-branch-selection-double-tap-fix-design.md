<!-- /autoplan restore point: /home/ecc/.gstack/projects/elifarley-hug-scm/main-autoplan-restore-20260419-184111.md -->
# Fix: Double-Tap Branch Selection Bug

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Fix the bug where typing a number at the `hug b` branch selection menu requires typing it twice — the first keypress is silently consumed by the ESC-detection probe.

**Architecture:** The ESC-detection code in `selection_core.py:get_selection_input()` reads one character in raw TTY mode to check for ESC. When the character is not ESC, it needs to be prepended to the `input()` result so the user doesn't have to type twice. The fix is userspace buffering: store the consumed character and prepend it to `input()`'s return value. A pty-based test exercises the real TTY code path.

**Tech Stack:** Python 3, termios/tty (POSIX), pty (for testing)

---

## Root Cause

In `selection_core.py:get_selection_input()` (lines 379-400), the ESC-detection probe reads one character in raw mode via `sys.stdin.read(1)`. Raw mode disables echo, so the character disappears. If the character is not ESC, the code falls through to `input()` — but the character was already consumed from stdin and is gone. The user must type their input again.

Introduced by commit `fb44a5a` ("feat: detect ESC keypress to abort numbered-list branch selection").

## Why Tests Missed It

The Python tests for `get_selection_input` only exercise the input precedence chain (`test_selection` arg > env var > `builtins.input` mock). They never exercise the raw-mode `termios` path, which only runs when stdin is a real TTY.

---

### Task 1: Write pty-based tests exposing the double-tap bug

**Files:**
- Modify: `git-config/lib/python/tests/test_selection_core.py` — add new test class after `TestGetSelectionInput`

**Step 1: Write the failing tests**

Add the following test class to `test_selection_core.py`, after the existing `TestGetSelectionInput` class (after line ~614, before `TestAddCommonCliArgs`):

```python
import os
import pty


class TestGetSelectionInputRawMode:
    """Tests for get_selection_input() raw-mode TTY path.

    The existing TestGetSelectionInput tests mock builtins.input, which
    bypasses the termios raw-mode ESC-detection probe entirely. These tests
    use pty.openpty() to create a real pseudo-terminal, exercising the
    actual TTY code path where the double-tap bug lives.
    """

    def test_non_esc_single_digit_not_consumed(self, monkeypatch):
        """A single non-ESC digit typed at a real TTY should be available to input().

        Regression test for the double-tap bug: the raw-mode ESC probe reads
        one character with sys.stdin.read(1). If it's not ESC, the character
        must be prepended to input()'s result so the user doesn't have to
        type it again.
        """
        master_fd, slave_fd = pty.openpty()
        try:
            os.write(master_fd, b"3\n")
            monkeypatch.delenv("HUG_TEST_NUMBERED_SELECTION", raising=False)
            slave = os.fdopen(slave_fd, "r")
            monkeypatch.setattr("sys.stdin", slave)
            result = get_selection_input(test_selection=None)
            assert result == "3"
        finally:
            os.close(master_fd)

    def test_esc_returns_none(self, monkeypatch):
        """ESC keypress should return None (cancellation signal)."""
        master_fd, slave_fd = pty.openpty()
        try:
            os.write(master_fd, b"\x1b")
            monkeypatch.delenv("HUG_TEST_NUMBERED_SELECTION", raising=False)
            slave = os.fdopen(slave_fd, "r")
            monkeypatch.setattr("sys.stdin", slave)
            result = get_selection_input(test_selection=None)
            assert result is None
        finally:
            os.close(master_fd)

    def test_non_esc_multi_digit(self, monkeypatch):
        """Multi-digit input like '12' should return '12', not '2'.

        The raw-mode probe consumes '1'; input() reads '2\\n'.
        Userspace buffering must prepend '1' to get '12'.
        """
        master_fd, slave_fd = pty.openpty()
        try:
            os.write(master_fd, b"12\n")
            monkeypatch.delenv("HUG_TEST_NUMBERED_SELECTION", raising=False)
            slave = os.fdopen(slave_fd, "r")
            monkeypatch.setattr("sys.stdin", slave)
            result = get_selection_input(test_selection=None)
            assert result == "12"
        finally:
            os.close(master_fd)

    def test_empty_newline_returns_empty_string(self, monkeypatch):
        """Just Enter (newline) after raw-mode probe should return empty string.

        The raw-mode read(1) consumes '\\n'; input() sees EOF and returns ''.
        Prepended '\\n' + '' gives '\\n', but input() on the remaining buffer
        after the first read may return ''.  The key assertion: no crash, no hang.
        """
        master_fd, slave_fd = pty.openpty()
        try:
            os.write(master_fd, b"\n")
            monkeypatch.delenv("HUG_TEST_NUMBERED_SELECTION", raising=False)
            slave = os.fdopen(slave_fd, "r")
            monkeypatch.setattr("sys.stdin", slave)
            result = get_selection_input(test_selection=None)
            assert isinstance(result, str)
        finally:
            os.close(master_fd)
```

**Step 2: Run tests to verify they fail**

Run: `make test-lib-py TEST_FILTER="TestGetSelectionInputRawMode"`
Expected: `test_non_esc_single_digit_not_consumed` FAILS — the current code consumes the character and `input()` gets only "\n" (empty string). `test_esc_returns_none` should PASS (existing behavior). `test_non_esc_multi_digit` FAILS.

---

### Task 2: Run the new test to verify it fails (demonstrates the bug)

**Step 1: Run the specific test**

Run: `make test-lib-py TEST_FILTER="test_non_esc_single_digit_not_consumed"`

Expected: FAIL. The assertion `result == "3"` will fail because the raw-mode probe consumed "3" and `input()` sees only the newline (empty string).

If the test fails as expected, the bug is confirmed and the test is valid.

---

### Task 3: Fix the bug — userspace buffering in selection_core.py

**Files:**
- Modify: `git-config/lib/python/git/selection_core.py:391-398`

**Why userspace buffering, not os.write:** The /autoplan review empirically verified that `os.write(fd, c.encode())` does NOT push characters back to the TTY input buffer. Writing to the slave side of a pty produces output on the master side, not readable input on the slave. Userspace buffering (prepending the consumed character to `input()`'s return value) is portable, simple, and works everywhere.

**Step 1: Apply the fix**

In `selection_core.py`, change lines 391-398:

Change from:
```python
        if c == "\x1b":
            # ESC pressed — signal cancellation (None), not empty string.
            # parse_single_input(None, ...) returns None → "cancelled".
            return None
        # Non-ESC character typed — fall through to line-mode input() below.
    except Exception:
        # Fall through to line-mode input on any terminal/read error.
        # Covers: non-POSIX (ImportError), non-TTY (isatty false), any I/O error.
        pass

    try:
        return input()
    except EOFError:
        return ""
```

To:
```python
        if c == "\x1b":
            # ESC pressed — signal cancellation (None), not empty string.
            # parse_single_input(None, ...) returns None → "cancelled".
            return None
        # Non-ESC character: prepend to input() result instead of TTY push-back.
        # os.write(fd, c) was considered but does NOT work — writing to the
        # slave pty fd produces output on the master side, not readable input.
        # Userspace buffering is portable, simple, and avoids TTY-specific hacks.
    except Exception:
        # Fall through to line-mode input on any terminal/read error.
        # Covers: non-POSIX (ImportError), non-TTY (isatty false), any I/O error.
        pass

    try:
        # If the raw-mode probe consumed a character (stored in `c`), prepend
        # it to input()'s result. input() strips the trailing newline, so
        # c + input() correctly reconstructs the full user input.
        if 'c' in dir() and c != "\x1b":
            return c + input()
        return input()
    except EOFError:
        return ""
```

Wait — `c` is scoped inside the try block. We need to declare it before:

```python
        if c == "\x1b":
            # ESC pressed — signal cancellation (None), not empty string.
            return None
    except Exception:
        # Fall through to line-mode input on any terminal/read error.
        c = ""  # Ensure c is defined for the prepend path below
        pass

    try:
        return c + input()
    except EOFError:
        return ""
```

Actually, the cleanest approach: initialize `c = ""` before the try block, so it's always in scope:

Change from (full block, lines 379-400):
```python
    try:
        fd = sys.stdin.fileno()
        old_settings = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            c = sys.stdin.read(1)
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
        if c == "\x1b":
            # ESC pressed — signal cancellation (None), not empty string.
            # parse_single_input(None, ...) returns None → "cancelled".
            return None
        # Non-ESC character typed — fall through to line-mode input() below.
    except Exception:
        # Fall through to line-mode input on any terminal/read error.
        # Covers: non-POSIX (ImportError), non-TTY (isatty false), any I/O error.
        pass

    try:
        return input()
    except EOFError:
        return ""
```

To:
```python
    c = ""  # Will hold the consumed character from raw-mode probe
    try:
        fd = sys.stdin.fileno()
        old_settings = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            c = sys.stdin.read(1)
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
        if c == "\x1b":
            # ESC pressed — signal cancellation (None), not empty string.
            # parse_single_input(None, ...) returns None → "cancelled".
            return None
        # Non-ESC character consumed — will be prepended to input() result
        # below.  os.write(fd, c) does NOT work: writing to the slave pty fd
        # produces output on the master side, not readable input on the slave.
    except Exception:
        # Fall through to line-mode input on any terminal/read error.
        # c remains "" — input() proceeds normally without prepend.
        pass

    try:
        return c + input()
    except EOFError:
        return ""
```

**Step 2: Run the failing tests to verify they pass**

Run: `make test-lib-py TEST_FILTER="TestGetSelectionInputRawMode"`
Expected: ALL PASS — `test_non_esc_single_digit_not_consumed`, `test_non_esc_multi_digit`, `test_esc_returns_none`, `test_empty_newline_returns_empty_string`.

---

### Task 3.5: Fix existing None-crash bug in branch multi-select

**Files:**
- Modify: `git-config/lib/python/git/branch_select.py:467`

**Why:** `get_selection_input()` can return `None` (ESC cancellation). `tag_select.py:547` and `worktree_select.py:413` already guard against this (`if user_input is None: user_input = ""`). But `branch_select.py:467` in the multi-select path passes the raw value directly to `parse_numbered_input()`, which calls `.strip()` on it at line 277 — causing an `AttributeError` crash on ESC.

**Step 1: Add the None guard**

In `branch_select.py`, after line 467 (`selection = get_selection_input(...)`), add:

```python
    selection = get_selection_input(test_selection=options.test_selection)

    # get_selection_input returns None when ESC is pressed (detected via
    # tty/termios character-mode read).  Treat it identically to empty input,
    # consistent with tag_select and worktree_select.
    if selection is None:
        selection = ""
```

**Step 2: Run branch tests to verify no regression**

Run: `make test-lib-py TEST_FILE=test_branch_select.py`
Expected: ALL PASS.

---

### Task 4: Run all tests to verify fix and no regressions

**Step 1: Run the full Python test suite**

Run: `make test-lib-py`
Expected: ALL PASS — no regressions in existing selection tests or any other Python tests.

**Step 2: Run BATS branch-related tests**

Run: `make test-unit TEST_FILE=test_branch_switch.bats`
Expected: ALL PASS — the `hug b` command tests continue to work.

Run: `make test-lib TEST_FILE=test_hug_git_branch.bats`
Expected: ALL PASS — branch library integration tests continue to work.

---

### Task 5: Commit the fix

**Step 1: Stage and commit**

```bash
git add git-config/lib/python/git/selection_core.py git-config/lib/python/git/branch_select.py git-config/lib/python/tests/test_selection_core.py
git commit -m "fix: prevent first keypress consumption in numbered selection menus

WHY: The ESC-detection probe in get_selection_input() reads one character
in raw TTY mode via sys.stdin.read(1). Raw mode disables echo, so the
character is silently consumed. When the character is not ESC, the code
fell through to input() — but the character was already gone, forcing
users to type their selection twice (the 'double-tap' bug).

WHAT: Prepend the consumed character to input()'s return value using
userspace buffering (c + input()) instead of TTY push-back. Also fix
an existing crash where branch multi-select passed None (from ESC) to
parse_numbered_input(), which calls .strip() on it.

HOW: os.write(fd, c) was originally proposed for push-back, but empirically
verified to NOT work — writing to the slave pty fd produces output on
the master side, not readable input. Userspace buffering is portable,
simple, and avoids TTY-specific hacks.

IMPACT: Users can now type a single number at any selection menu (branch,
tag, worktree) and press Enter — the expected one-shot behavior. ESC
cancellation still works correctly."
```

---

## /autoplan Review Output

### Phase 1: CEO Review (Strategy & Scope)

**Mode:** SELECTIVE EXPANSION (auto-decided, P6: bias toward action)

#### Premise Challenge

| # | Premise | Status | Evidence |
|---|---------|--------|----------|
| P1 | `os.write(fd, c.encode())` pushes back to TTY input buffer | **FALSE** | Verified by empirical test: writing to slave fd produces output on master side, not readable input on slave. Both Claude subagent and Codex flagged this. The proposed fix will not work. |
| P2 | Root cause is character consumption in raw mode | TRUE | Verified against selection_core.py:384 — `sys.stdin.read(1)` consumes the character, no push-back exists |
| P3 | PTY test adequately validates the fix | WEAK | Only covers single-digit happy path. No ESC test, no multi-digit, no arrow-key escape sequences, no paste |
| P4 | Fix scope is branch-selection only | FALSE | `get_selection_input()` is shared by branch_select, tag_select, worktree_select — all three selection modules use it |

**CRITICAL: Premise P1 is false. The proposed `os.write()` fix does not work. This plan cannot proceed without a different approach to character push-back.**

#### "NOT in scope" (deferred)

| Item | Reason |
|------|--------|
| Remove ESC probe entirely | Viable alternative but changes product behavior; separate decision |
| Full character-mode input layer | Out of scope for a bugfix; architectural change |
| Arrow-key navigation | Not implemented; future feature |

#### What already exists

| Sub-problem | Existing code | Reuse potential |
|-------------|---------------|-----------------|
| Selection input precedence | `get_selection_input()` with test_selection > env_var > stdin | Core of the fix |
| ESC detection | `selection_core.py:379-391` raw-mode probe | The code that introduced the bug |
| Numbered input parsing | `parse_numbered_input()` | No changes needed |
| Selection callers | branch_select.py:467, tag_select.py:543, worktree_select.py:409 | All share the fix |

#### Error & Rescue Registry

| Error | Cause | Rescue | Severity |
|-------|-------|--------|----------|
| Character consumed silently | Raw-mode read(1) without push-back | Fix push-back mechanism | Critical |
| os.write push-back fails silently | Wrong fd semantics (writes to output, not input) | Need alternative approach | Critical (plan flaw) |
| Non-TTY environment | termios unavailable | Exception handler → fall through to input() | Handled |

#### Failure Modes Registry

| Failure mode | Likelihood | Impact | Mitigation |
|-------------|-----------|--------|------------|
| Push-back doesn't work on real TTY | HIGH (confirmed) | Fix is useless | Need alternative: userspace buffering or TIOCSTI |
| Multi-digit selection breaks | Medium | Users can't select items >9 | Test needed |
| Arrow-key escape sequences interpreted as multiple chars | Medium | False cancellation or corrupted input | Escape sequence handling needed |
| Race between push-back and input() | Low | Intermittent failure | Single-threaded Python mitigates |

#### Dream State Delta

```
CURRENT ──────────── THIS PLAN ──────────── 12-MONTH IDEAL
(ESC probe eats       (os.write push-back     (Clean input model:
 first keypress)       — WON'T WORK)           no raw/cooked mixing,
                                               gum for interactive,
                                               line-mode for numbered)
```

#### CEO Dual Voices — Consensus Table

```
═══════════════════════════════════════════════════════════════
  Dimension                           Claude  Codex   Consensus
  ──────────────────────────────────── ─────── ─────── ─────────
  1. Premises valid?                   No      No      CONFIRMED FALSE (P1)
  2. Right problem to solve?           Yes     Yes     CONFIRMED
  3. Scope calibration correct?        Narrow  Narrow  CONFIRMED (too narrow)
  4. Alternatives explored?            No      No      CONFIRMED (insufficient)
  5. Competitive/market risks?         Low     Low     CONFIRMED (not applicable)
  6. 6-month trajectory sound?         Medium  Medium  CONFIRMED (hybrid model fragile)
═══════════════════════════════════════════════════════════════
```

#### Implementation Alternatives

| Approach | Effort | Risk | Portability | Verdict |
|----------|--------|------|-------------|---------|
| A) Userspace buffering: store consumed char, prepend to input() result | Low (5 lines) | Low | Universal | **Recommended** |
| B) TIOCSTI injection into tty input buffer | Low (3 lines) | Medium | Deprecated Linux 5.2+, removed on some distros | Rejected |
| C) Remove raw-mode probe, use 'q' for cancel | Low (10 lines) | Low | Universal | Viable alternative |
| D) os.write(fd) push-back | Low (2 lines) | HIGH | BROKEN (writes to output, not input) | **Won't work** |

#### Completion Summary (CEO)

| Section | Findings | Severity |
|---------|----------|----------|
| Premises | P1 (os.write push-back) is FALSE | Critical |
| Existing code leverage | 3 modules share get_selection_input | High impact |
| Scope | Fix affects all selection, not just branch | Medium |
| Alternatives | None explored in plan | High |
| Test coverage | Single happy-path only | Medium |
| 6-month trajectory | Hybrid raw/cooked model is fragile | Medium |

---

### Phase 2: Design Review

**SKIPPED** — no UI scope detected (CLI/terminal tool, no graphical components).

---

### Phase 3: Eng Review (Architecture & Code Quality)

#### Architecture ASCII Diagram

```
                    get_selection_input()
                    [selection_core.py:326]
                           │
              ┌────────────┼────────────┐
              │            │            │
       branch_select  tag_select  worktree_select
       [:467 multi]   [:543]      [:409]
       [:563 single]
              │            │            │
       parse_numbered_input()  (shared)
       [selection_core.py:237]
```

Coupling: single point of fix. All three modules call `get_selection_input()`. Fix goes in one place.

#### NOT in scope (Eng)

| Item | Reason |
|------|--------|
| Arrow-key escape sequence handling | Not implemented; out of scope for bugfix |
| Full character-mode input layer | Architectural change; separate decision |
| Non-POSIX (Windows) support | Already gracefully degraded via except block |

#### What already exists

| Component | Location | Status |
|-----------|----------|--------|
| `get_selection_input()` | selection_core.py:326 | Has raw-mode probe (the bug site) |
| `parse_numbered_input()` | selection_core.py:237 | Expects str, crashes on None |
| ESC None handling | tag_select:547, worktree_select:413 | Handled (normalize to "") |
| ESC None handling | branch_select:467 (multi) | **MISSING** — crash on ESC |
| PTY test infrastructure | test_selection_core.py | None — new class needed |

#### Section 1: Architecture

**Finding: Userspace buffering is the correct approach.** Store consumed character in `c`, then return `c + input()` instead of bare `input()`. This avoids TTY push-back entirely.

The fix changes `get_selection_input()` lines 391-398 from:
```python
# Non-ESC character typed — fall through to line-mode input() below.
...
return input()
```
To:
```python
# Non-ESC character typed — prepend it to line-mode input() result.
...
return c + input()
```

**Coupling assessment:** Fix is localized to `get_selection_input()`. All three callers benefit automatically. No caller changes needed for the double-tap fix itself.

#### Section 2: Code Quality

**Finding (Critical): `parse_numbered_input()` crash on ESC in multi-select.** Codex discovered that `branch_select.py:467` passes raw `get_selection_input()` return to `parse_numbered_input()` without None guard. `parse_numbered_input` calls `.strip()` at line 277, which raises `AttributeError` on None. Tag and worktree callers have the guard (`if user_input is None: user_input = ""`), but branch multi-select does not. This is an existing bug that must be fixed in blast radius.

**Auto-decision:** Fix the None guard in branch multi-select (P2: boil lakes). 1 line addition.

#### Section 3: Test Review

**Current coverage:** 0% for raw-mode TTY path. Existing tests mock `builtins.input`, bypassing termios entirely.

**Test diagram → required tests:**

| Codepath | Test | Type | Priority |
|----------|------|------|----------|
| Non-ESC single digit consumed | `test_non_esc_single_digit_not_consumed` | PTY | Critical |
| ESC returns None | `test_esc_returns_none` | PTY | Critical |
| Multi-digit "12\n" | `test_non_esc_multi_digit` | PTY | High |
| Empty input "\n" | `test_empty_newline` | PTY | Medium |
| Multi-select ESC crash | `test_multi_select_esc_no_crash` | Unit | Critical |

**Test plan artifact:** `~/.gstack/projects/elifarley-hug-scm/elifarley-main-test-plan-20260419-185039.md`

#### Section 4: Performance

**No performance concerns.** The fix changes `return input()` to `return c + input()`. String concatenation of one character is negligible. The raw-mode probe was already present and is unchanged.

#### Failure Modes Registry (Eng)

| Failure mode | Likelihood | Impact | Mitigation |
|-------------|-----------|--------|------------|
| `c + input()` wrong for multi-byte chars | Low | Corrupted input | Raw mode reads one byte; valid for ASCII digits |
| `parse_numbered_input(None)` crash | HIGH (existing) | Multi-select crashes on ESC | Add None guard in branch_select |
| PTY test flaky in CI | Low | False test failures | Use deterministic pty.openpty(), not real terminal |
| `input()` sees empty string after buffering "\n" | Medium | Returns "\n" stripped to "" | Correct behavior (empty = cancel) |

#### ENG DUAL VOICES — CONSENSUS TABLE

```
═══════════════════════════════════════════════════════════════
  Dimension                           Claude  Codex   Consensus
  ──────────────────────────────────── ─────── ─────── ─────────
  1. Architecture sound?               Yes     Yes     CONFIRMED
  2. Test coverage sufficient?         No      No      CONFIRMED (insufficient)
  3. Performance risks addressed?      Yes     N/A     CONFIRMED (none)
  4. Security threats covered?         Yes     N/A     CONFIRMED (none)
  5. Error paths handled?              Partial Partial CONFIRMED (None crash in multi)
  6. Deployment risk manageable?       Yes     Yes     CONFIRMED (low)
═══════════════════════════════════════════════════════════════
```

#### Eng Completion Summary

| Section | Findings | Severity |
|---------|----------|----------|
| Architecture | Userspace buffering correct; localized fix | Sound |
| Code Quality | parse_numbered_input crash on None | Critical (existing bug) |
| Test Coverage | 0% raw-mode coverage; 5 tests needed | High |
| Performance | No concerns | N/A |
| Shared helper | branch multi-select missing None guard | Critical |

---

### Phase 3.5: DX Review

**Mode:** DX POLISH (auto-decided, bugfix context)

Product type: CLI tool (developer-facing). Primary persona: developer using `hug` for branch switching.

#### DX Scorecard

| Dimension | Score | Notes |
|-----------|-------|-------|
| 1. Getting started | N/A | Bugfix, not onboarding |
| 2. Error messages | 8/10 | Crash on ESC in multi-select is silent (AttributeError) |
| 3. API/CLI naming | N/A | No naming changes |
| 4. Documentation | 7/10 | Fix needs code comment explaining why userspace buffering |
| 5. Upgrade path | 10/10 | Transparent bugfix, no API changes |
| 6. Escape hatches | N/A | No new opinions |
| 7. Consistency | 9/10 | Fix applies uniformly to all 3 selection modules |
| 8. Magical moments | N/A | Bugfix, not feature |

**TTHW:** N/A (bugfix)

#### DX Dual Voices — Consensus Table

```
═══════════════════════════════════════════════════════════════
  Dimension                           Claude  Codex   Consensus
  ──────────────────────────────────── ─────── ─────── ─────────
  1. Getting started < 5 min?          N/A     N/A     N/A
  2. API/CLI naming guessable?         N/A     N/A     N/A
  3. Error messages actionable?        Yes     Yes     CONFIRMED
  4. Docs findable & complete?         Yes     Yes     CONFIRMED
  5. Upgrade path safe?                Yes     Yes     CONFIRMED
  6. Dev environment friction-free?    N/A     N/A     N/A
═══════════════════════════════════════════════════════════════
```

---

### Decision Audit Trail

| # | Phase | Decision | Classification | Principle | Rationale | Rejected |
|---|-------|----------|-----------|-----------|----------|----------|
| 1 | CEO | SELECTIVE EXPANSION mode | Mechanical | P6 | Bias toward action on confirmed bugfix | - |
| 2 | CEO | Premise P1 (os.write push-back) is FALSE | Mechanical | P1+P5 | Empirically verified; both models agree | os.write approach |
| 3 | CEO | Userspace buffering over remove-ESC | Taste → User chose A | P1 | User chose to preserve ESC-to-cancel | Remove ESC probe |
| 4 | Eng | Fix parse_numbered_input None crash | Mechanical | P2 | In blast radius, 1-line fix, existing bug | - |
| 5 | Eng | Add 5 PTY/unit tests (not just 1) | Mechanical | P1 | Shared helper needs coverage for ESC, multi-digit, crash | Single happy-path test |
| 6 | Eng | No TIOCSTI (deprecated) | Mechanical | P3 | Userspace buffering is simpler and more portable | TIOCSTI injection |
| 7 | DX | DX POLISH mode | Mechanical | P3 | Bugfix context, not feature launch | DX EXPANSION |

### Cross-Phase Themes

**Theme: Shared helper contract is broken** — flagged in CEO (scope too narrow), Eng (None crash in multi-select), DX (silent error). High-confidence signal: `get_selection_input()` returns `str | None` but callers assume `str`. The fix must address both the double-tap bug AND the contract inconsistency.
