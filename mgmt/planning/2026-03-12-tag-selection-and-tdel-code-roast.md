# Tag Selection and `tdel` Engineering Roast

**Date:** 2026-03-12  
**Agent:** code-roast (invoked by Augment Agent)  
**Scope:** interactive tag selection and tag deletion refactor

---

## Executive Summary

The refactor is directionally strong: it removes stale `gum --multi` usage, routes tag selection through the shared gum abstraction, and adds the missing regression tests for the previously broken path.

The biggest remaining risk is no longer the original bug. It is the **behavioral contract** around selection helpers for read-only versus destructive commands. `hug t` and `hug tdel` now share more plumbing, so the project should be explicit about cancellation, empty results, no-tags cases, and fallback behavior.

---

## Scope Reviewed

- `git-config/lib/hug-git-tag`
- `git-config/bin/git-tdel`
- `git-config/bin/git-t`
- `tests/lib/test_hug-git-tag.bats`
- `tests/unit/test_tag_commands.bats`
- `tests/bin/gum-mock`
- `tests/test_helper.bash`
- `docs/commands/tagging.md`

---

## Major Findings

### 1. `select_tags()` now carries a cross-command UX contract

**Affected areas:** `git-config/lib/hug-git-tag`, `git-config/bin/git-t`, `git-config/bin/git-tdel`

**Problem:** The shared helper now controls behavior used by both browsing and destructive deletion flows.

**Why it matters:** These commands do not have identical semantics for cancel, empty selection, no-data states, and multi-select invariants. In Bash, implicit contracts drift easily.

**Recommended remediation:** Treat `select_tags()` as a real API. Either split it into `select_one_tag` and `select_many_tags`, or document and preserve explicit return semantics for selected, cancelled, no-data, and error cases.

### 2. Destructive-path edge cases still need stronger coverage

**Affected areas:** `tests/unit/test_tag_commands.bats`, `tests/lib/test_hug-git-tag.bats`

**Problem:** The newly added tests cover the broken interactive selection path, but the highest-risk destructive no-op boundaries remain lightly tested.

**Why it matters:** CLI deletion bugs usually appear around cancellation, no matches, no tags, or non-interactive fallbacks rather than in the happy path.

**Recommended remediation:** Add tests for selection cancel, confirmation cancel, no tags, gum unavailable, and repo-state assertions proving zero side effects.

### 3. Public behavior should be intentionally distinct

**Affected areas:** `git-config/bin/git-t`, `git-config/bin/git-tdel`, `docs/commands/tagging.md`

**Problem:** User-visible outcomes for cancelled selection, no matches, and no tags can still blur together if the command layer does not clearly own the messaging.

**Why it matters:** A CLI that says little or uses the same message for different states feels flaky even when technically correct.

**Recommended remediation:** Keep selection mechanics shared, but make command-level messages and exit behavior deliberately distinct for browse versus delete flows.

---

## Medium Concerns

### 4. Destructive argv handling deserves continued paranoia

**Affected areas:** `git-config/bin/git-tdel`

**Problem:** Shared selection refactors are a common place for arrays to collapse into strings or for tag names to be passed without defensive argv boundaries.

**Recommended remediation:** Keep auditing that selections remain arrays end-to-end and that destructive downstream invocations stay fully quoted and defensive.

### 5. Tests should stay black-box at the command layer

**Affected areas:** `tests/bin/gum-mock`, command-level test files

**Problem:** It is easy for command tests to become too coupled to gum internals once selectors route through a shared helper.

**Recommended remediation:** Keep gum-plumbing assertions mainly in library tests. Keep command tests focused on output, exit status, and repository state.

---

## What This Review Does *Not* Say

This review does **not** indicate a blocker in the implemented fix. The current change set appears materially better than the pre-refactor state and closes the original production bug.

The remaining issues are about hardening the helper contract and preventing future semantic drift.

---

## Recommended Follow-up Priorities

1. Add destructive cancel/no-op tests for `hug tdel`.
2. Define or split the tag-selection helper contract more explicitly.
3. Clarify user-facing messages for cancel, empty result, and no-tags states.
4. Keep command tests black-box and repo-state oriented.

---

## Intended Use of This Document

This document is a focused post-refactor engineering review. It should be used as guidance for the next hardening pass on interactive tag selection and tag deletion behavior.

