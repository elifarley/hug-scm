# Co-Changes File Mode Redesign Plan

**Status**: Proposed  
**Date**: 2026-03-06  
**Purpose**: Redesign `hug analyze co-changes` around a file-first interface with a cleaner CLI grammar and a simpler implementation model.

---

## Executive Summary

This plan makes co-change analysis answer the primary user question directly: **given a file, what other files most often change with it?**

### Final decisions

- Make **file mode** the primary interface: `hug analyze co-changes <file>`
- Make **repo-wide analysis** explicit: `hug analyze co-changes --all`
- Remove positional commit count syntax like `hug analyze co-changes 200`
- Use `--commits <n>` as the only count-based history selector
- Keep Bash as a thin CLI/orchestration layer and Python as the single analysis engine
- Prefer deletion of ambiguous behavior over compatibility shims

---

## Problem Statement

`hug analyze co-changes` is conceptually file-oriented, but its current implementation is repo-wide only. This creates three problems:

1. The command does not directly answer the common question: "what files are related to this file?"
2. The current positional count syntax blocks a clean `<file>` argument design.
3. Documentation already implies file mode in some places, so docs and implementation have drifted apart.

Because this repository has no user or migration constraints, the correct move is not to preserve the old shape. The correct move is to replace it with a cleaner command contract.

---

## Design Goals

- Answer the file-focused question directly and elegantly
- Eliminate CLI ambiguity permanently
- Keep the shell script thin and maintainable
- Centralize analysis logic in `git-config/lib/python/co_changes.py`
- Use one coherent correlation model across file mode and repo-wide mode
- Make help text, docs, JSON output, and tests describe the same truth

## Non-Goals

- Preserving positional count compatibility
- Adding a second command such as `hug analyze related-files`
- Implementing file mode by shell-filtering repo-wide JSON output
- Expanding scope into static dependency analysis or semantic code analysis

---

## Final CLI Contract

### Primary forms

- `hug analyze co-changes <file> [options]`
- `hug analyze co-changes --all [options]`

### Options

- `--commits <n>`: Analyze the last `n` commits when `--since` is not provided
- `--since <date>`: Analyze commits since a Git-recognized date expression
- `--threshold <pct>`: Minimum correlation threshold
- `--top <n>`: Maximum results to display
- `--json`: Emit structured JSON
- `--browse-root`: Only relevant when interactive file selection is used

### No-argument behavior

- If running in a TTY and `gum` is available, open interactive file selection
- Otherwise, fail with a clear error requiring either `<file>` or `--all`

### Explicit removal

These forms are removed as part of the redesign:

- `hug analyze co-changes 200`
- any parser behavior that guesses whether the first positional argument is a file or a count

---

## Alternatives Rejected

### 1. Keep both positional forms

Rejected because `hug analyze co-changes 200` and `hug analyze co-changes <file>` make the first positional argument permanently ambiguous.

### 2. Create a new command like `hug analyze related-files <file>`

Rejected because it splits one concept across two commands and weakens the command family.

### 3. Implement file mode by filtering repo-wide output

Rejected because it places logic in the wrong layer, wastes work, and makes the public command a wrapper around an internal workaround.

### 4. Preserve backward compatibility temporarily

Rejected because transition code would add complexity without delivering durable value.

---

## Architecture Boundaries

### Bash responsibilities

- Parse mode and flags
- Enforce `<file>` versus `--all` exclusivity
- Handle interactive file selection when appropriate
- Validate the file path in file mode
- Build the git log pipeline
- Invoke the Python helper

### Python responsibilities

- Parse commit/file history input
- Run file-mode analysis
- Run repo-wide analysis
- Apply thresholding, sorting, and result limiting
- Format text and JSON output

**Rule**: Bash orchestrates. Python analyzes.

---

## Internal Design Decisions

### 1. Two explicit analysis modes

The helper should expose two clear paths:

- `file` mode: analyze one target file against all peers
- `all` mode: analyze co-change pairs across the repository slice

### 2. Direct file-mode algorithm

File mode should not be implemented by computing the full pair matrix and filtering it afterward.

Instead, for the selected commit window:

- count how many commits touch the target file
- count how many commits touch each other file
- count how many commits touch both the target file and each peer file
- compute `correlation = co_changes / min(target_changes, peer_changes)`

This preserves the current correlation meaning while making file mode cheaper and simpler.

### 3. Shared result model

Use one correlation record shape across both modes so sorting, filtering, formatting, and JSON tests remain simple. File mode may add top-level metadata such as `mode` and `target_file`, but it should reuse the same per-result fields as repo-wide mode.

### 4. One explicit history selector

`--commits <n>` replaces positional count syntax. `--since` remains the time-based selector. The command should never infer whether a bare value is a file or a numeric scope selector.

---

## Implementation Slices

### Slice 1: Lock the contract

- Update help text and planning docs to the final grammar
- Identify all docs/examples using positional count syntax
- Treat the new contract as authoritative before code refactoring begins

### Slice 2: Refactor Python helper

- Introduce explicit file mode and all mode paths in `co_changes.py`
- Extract shared helpers for sorting, thresholding, and formatting
- Keep functions small, single-purpose, and easy to test

### Slice 3: Simplify the Bash wrapper

- Remove positional count parsing from `git-config/bin/git-analyze-co-changes`
- Add `<file>` and `--all` mode handling
- Add interactive file selection behavior consistent with other file-oriented commands

### Slice 4: Add comprehensive tests

Python tests:

- file mode happy path
- file mode empty/no-match path
- threshold and sorting behavior in file mode
- JSON metadata for mode-aware output

BATS tests:

- `hug analyze co-changes README.md --json`
- `hug analyze co-changes --all --json`
- `--commits` behavior
- invalid file handling
- no-arg interactive/error behavior

### Slice 5: Converge docs

- Update `README.md`
- Update `docs/workflows.md`
- Update `docs/cheat-sheet.md`
- Remove any example that contradicts the final CLI contract

---

## Acceptance Criteria

- `hug analyze co-changes <file>` is the primary documented workflow
- `hug analyze co-changes --all` provides explicit repo-wide analysis
- positional numeric count syntax is removed
- `--commits` is the only count-based history selector
- Bash remains a thin wrapper over Python analysis logic
- JSON output is mode-aware and structurally coherent
- docs, help text, and implementation no longer disagree
- relevant pytest and BATS tests pass

---

## Guiding Principle

This redesign should spend complexity on the **final shape** of the command, not on transition mechanics. With no migration constraints, the elegant path is to remove ambiguity rather than manage it.