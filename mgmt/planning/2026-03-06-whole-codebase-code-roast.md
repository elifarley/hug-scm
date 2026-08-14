# Whole-Codebase Engineering Roast

**Date:** 2026-03-06  
**Agent:** code-roast (invoked by Augment Agent)  
**Scope:** Entire `hug-scm` repository

---

## Executive Summary

This review looked at the repository as a system rather than at a single commit. The biggest risks are not isolated bugs; they are structural patterns that increase regression radius, semantic drift, and safety risk across a very broad CLI surface.

**Highest-impact conclusions:**
- Large ambient Bash libraries create hidden coupling and poor local reasoning.
- Parallel Git and Mercurial implementations will drift without stronger contracts.
- Safety-critical destructive behavior is enforced mostly by convention.
- The CLI surface has too many manual sources of truth.
- Test coverage exists, but the highest-risk cross-cutting contracts need stronger coverage.

---

## Scope Reviewed

- `bin/`
- `git-config/`
- `hg-config/`
- `tests/`
- `Makefile`
- `README.md`
- `docs/`

---

## Critical Findings

### 1. Hidden coupling through ambient sourced libraries

**Affected areas:** `git-config/lib/hug-common`, `git-config/lib/hug-git-kit`, many `git-config/bin/*`, likely mirrored in `hg-config/*`

**Problem:** Command scripts are thin wrappers over large sourced libraries. A command may appear small while depending on a wide, implicit runtime surface of functions and globals.

**Why it matters:** This increases regression radius, makes debugging indirect, and weakens unit-level testing because behavior is spread across ambient state.

**Recommended remediation:** Split broad libraries into smaller capability-focused modules with explicit contracts and fewer ambient globals.

### 2. Git/Hg parallel implementation invites semantic drift

**Affected areas:** `git-config/*`, `hg-config/*`

**Problem:** The project maintains parallel backends for Git and Mercurial.

**Why it matters:** Flags, prompt behavior, output shape, error handling, and edge-case behavior can diverge unless the UX contract is deliberately enforced.

**Recommended remediation:** Define shared command/backend contracts and add acceptance tests that exercise both backends against the same expected semantics.

### 3. Destructive-operation safety is convention-based

**Affected areas:** `git-config/lib/hug-common`, destructive command families in `git-config/bin/git-w-*`, `git-config/bin/git-h-*`, Hg equivalents

**Problem:** Confirmation, `--force`, and `--dry-run` behavior appears to be implemented by recurring patterns rather than one mandatory framework path.

**Why it matters:** One inconsistent flow in a destructive command can create a data-loss bug.

**Recommended remediation:** Centralize destructive execution behind one reusable safety layer that enforces prompt, dry-run rendering, and force bypass consistently.

---

## Major Concerns

### 4. Too many sources of truth for the CLI surface

**Affected areas:** command scripts, alias/config files, `README.md`, `docs/commands/*`, tests

**Problem:** Adding or changing a command requires synchronized manual edits across implementation, docs, config, and tests.

**Recommended remediation:** Create a declarative command registry and generate or validate the secondary artifacts from it.

### 5. Portability is too dependent on GNU-ish tooling

**Affected areas:** `git-config/lib/hug-cli-flags`, standard command templates, activation/install paths

**Problem:** The implementation depends on GNU `getopt`, `readlink -f`, or related platform-sensitive behavior.

**Recommended remediation:** Either fail fast with explicit prerequisites or replace fragile bits with portable helpers and platform-matrix validation.

### 6. Tests are not yet fully aligned to the highest-risk contracts

**Affected areas:** `tests/unit/`, `tests/lib/`, `tests/integration/`, `git-config/lib/python/tests/`

**Problem:** Many tests exist, but the most important repo-wide contracts need stronger direct coverage.

**Recommended remediation:** Add contract tests for confirmation semantics, `--force`, `--dry-run`, exit codes, path handling, and Git/Hg parity.

### 7. Bash↔Python boundaries are a likely fragility seam

**Affected areas:** `git-config/lib/python/*` plus Bash callers

**Problem:** Small output or interface changes in Python helpers can silently break Bash consumers.

**Recommended remediation:** Standardize machine-readable contracts and add boundary tests from Bash caller to Python helper to CLI rendering.

---

## Edge Cases Most Likely to Break

- Filenames with spaces, tabs, leading dashes, globs, or newlines
- Non-interactive execution without a TTY
- Large repositories with many ignored/untracked files
- Git/Hg semantic mismatches behind the same command language
- Nested repos, worktrees, and submodules
- Missing optional dependencies such as `gum` or missing Python
- Inconsistent `--dry-run` behavior that does not match real execution

---

## Recommended Top 3 Priorities

1. Decompose the ambient shell library model into explicit, testable contracts.
2. Create a single command/backend manifest to reduce drift.
3. Centralize destructive-operation safety so it is enforced by structure, not discipline.

---

## Intended Use of This Document

This report is a strategic engineering review. It is best used as input to roadmap planning, architectural cleanup, and targeted hardening work rather than as a line-by-line bug list.

