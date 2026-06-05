# Changelog

All notable changes to the Hug SCM project will be documented in this file.

## [Unreleased]

## [1.2.0] - 2026-06-05

### Added

- **`hug shv` — visual show.** Renders a commit's patch (like `hug shp`) or a range's cumulative diff (like `hug shcp`) in your configured difftool instead of as text. `hug shv` defaults to HEAD; `hug shv <committish>`, `hug shv N`, `hug shv -N`, and `hug shv A..B` all work. It is a thin entry point over the same engine as `hug dd`'s commit mode, so `hug shv X` is identical to `hug dd X` for any commit/range/N. `shv s|u|w` is rejected with a redirect to `hug dd s|u|w` (it is commit-history only). Pathspec scoping mirrors `shcp` (multiple paths).
- **`hug dd` accepts the `N`/`-N` convention** (the same shorthand as `hug sh`/`shp`): `hug dd 3` is the commit three back, `hug dd -3` is the cumulative diff of the last three commits.
- **`is_root_commit <committish>` in `hug-git-repo`.** A per-ref companion to `is_at_root_commit` (which only answers for HEAD), so root-commit detection is correct for an arbitrary ref (e.g. `hug dd <root-sha>` reviewed from a non-root checkout).

### Changed

- **`hug dd <committish>` now shows that commit's *introduced* diff (commit vs its first parent), not worktree-vs-ref.** So **`hug dd HEAD` now matches `hug shp HEAD`** (visual), instead of silently behaving like bare `hug dd`. This makes `dd` a coherent visual-diff gateway: `s`/`u`/`w` (and bare `dd`) are working-tree views; a committish/range/N is a commit-history view. Bare `hug dd` is unchanged (still all uncommitted, worktree-vs-HEAD). A merge is diffed against its first parent (so `dd <merge>` can differ from `shp <merge>`'s combined diff); a root commit shows every file as added; a range is the cumulative endpoint diff. For working-tree-vs-a-ref, use a range (e.g. `hug dd main..HEAD`). This also fixes a latent bug: the old ref path lacked the no-changes guard, so `dd HEAD` launched an empty difftool on a clean tree; the engine now guards all paths and surfaces an error (rather than a misleading "no changes") on an invalid ref.
- **Ref-arithmetic helpers hoisted to `hug-git-repo`.** `resolve_commit_ref`, `reject_flag_ref`, and `is_range` moved from `hug-git-show` to `hug-git-repo` (pure ref arithmetic, already in every caller's load chain) so the visual-diff engine reuses them without a difftool-to-show dependency. No behavior change for `sh`/`shp`/`shc`/`shcp`/`l`/`ll`.

### Removed

- **Stray test-debugging artifacts from the repo root** (`errors.txt`, `errors-grouped.txt`, `semantic-count-test.txt`, `file1.txt`, `file3.txt`, `TAG_TEST_FIXES_SUMMARY.md`, `skipped-tests-analysis.yaml`) committed by mistake in earlier sessions. Legitimate fixtures (screencast demos, Python test fixtures) are untouched.

## [1.1.0] - 2026-06-04

### Fixed

- **`hug-common` self-resolves `HUG_HOME` from `BASH_SOURCE[1]`.** On CI where `HUG_HOME` is unset, `hug-common` now derives it from the sourcing script's path instead of calling the undefined `error` function and `exit 1` (which killed the parent). Fixes `test_quality_corpus.py` failures on GitHub Actions — 12 of 17 keyword/intent search tests were failing because `--help` subprocess invocations returned empty metadata.
- **CI workflow persists `HUG_HOME` to `GITHUB_ENV`.** After `make install`, `HUG_HOME=$GITHUB_WORKSPACE` is written to `$GITHUB_ENV` so all subsequent steps in each matrix job inherit it. Defense-in-depth layer alongside the self-resolution fix.
- **Python test conftest sets `HUG_HOME` for subprocesses.** An autouse session fixture walks up from `conftest.py` to find the repo root via `.git` marker detection, ensuring `HUG_HOME` is available even when tests run without prior activation.

### Added

- **BATS tests for `hug-common` HUG_HOME self-resolution.** Four new tests verify: derivation from `BASH_SOURCE`, preservation of existing values, graceful failure (`return 1` not `exit 1`), and caller survival on failure.

- **Staged gitlinks (submodule pointers) now visible in `hug sls` and `hug sl`.** When `submodule.*.ignore` or `diff.ignoreSubmodules` is set, `git diff --cached` silently suppresses gitlink entries. `list_staged_files()` now passes `--ignore-submodules=none` so staged submodule pointer changes are never dropped, regardless of ignore settings.

- **`hug dd` — visual side-by-side diff command family.** Opens a configured difftool (e.g. kitty diff) instead of a text patch: `hug dd s` (staged), `hug dd u` (unstaged), `hug dd w` / bare `hug dd` (all uncommitted — *net* worktree-vs-HEAD), and `hug dd <ref|range>`. The visual counterpart to `ss`/`su`/`sw`. `dd w` is a net view, so it intentionally differs from `sw`'s two-section split (a staged-then-reverted hunk cancels out) — see `docs/commands/status-staging.md` → "Visual diff". Productizes the former `dd` gitconfig alias into a real `git-dd` command with difftool preflight (friendly error when unconfigured), no-changes and non-TTY guards, `--no-prompt`, and an interactive `--` file picker. `--help` works without a TTY or a configured difftool.
- **`hug version` / `hug --version` now reports a version number.** Added a `VERSION` file at the repo root and wired the dispatcher to print it. Previously `hug version` printed only a description with no number. Scripts can read it via `hug version` or the `VERSION` file directly.
- **`hug s -r, --remote` query flag:** Outputs the fetch URL of the tracking remote (empty when no upstream is configured). Part of the `hug s` query flag system for scripting. Use `hug s -r` alone or combine: `hug s -b -r -u`.
- **Unified Selection Framework (`selection_core.py`).** Shared toolkit for all Python selection modules: `bash_escape`, `BashDeclareBuilder`, `parse_numbered_input`, `get_selection_input`, `add_common_cli_args`, and ANSI color constants. Adding a new selection domain now requires ~50 lines instead of ~200.
- **Branch single-select Python migration.** `print_interactive_branch_menu()` now delegates formatting and numbered-list interaction to Python via `branch_select.py prepare` and `single-select` commands. Eval output validated before execution.
- **Per-item CLI args for subjects and tracks.** `--subject`/`--track` repeated flags replace space-joined `--subjects`/`--tracks` to prevent multi-word commit subjects from being split incorrectly.
- **`parse_single_input()` for strict single-select.** Rejects anything that isn't exactly one valid integer, unlike the multi-select parser which silently skips invalid tokens.

### Changed

- **4 Python modules refactored onto `selection_core`.** `tag_select.py`, `worktree_select.py`, `branch_select.py`, and `branch_filter.py` now import shared utilities instead of maintaining local copies.
- **`multi_select_branches()` menu display moved to stderr.** Prevents menu text from being captured by Bash `$()` and eval'd as shell commands.
- **`branch_filter.py` `custom_filter` raises `NotImplementedError`.** Previously silently no-oped.
- **Worktree indicators changed format.** Worktree listing commands (`hug wtl`, `hug wt`, `hug wtll`, `hug wtsh`) now display single-character indicators (`* + # @`) instead of bracketed words (`[CURRENT]`, `[DIRTY]`, `[LOCKED]`, `[DETACHED]`). The new format is more compact and easier to scan. See `hug wtl --help` for the indicator legend.
- **Stdout/stderr discipline enforced across 21 commands and 5 libraries.** Listing and query commands now route headers, legends, and tips to stderr, keeping stdout clean for piping. The `CAPTURING OUTPUT` help text section documents this for `wtl`, `wtll`, `wtsh`, `shc`, and `h-files`. Script authors relying on stdout capturing these headers should test with `2>/dev/null` to verify behavior.
- **Migration note for script authors.** If you parse `hug wtl` output in scripts, update your grep patterns from `[CURRENT]`/`[DIRTY]` to `*`/`+`. For stable machine-readable output, prefer `hug wtl --json` which uses boolean fields and is not affected by display format changes.

### Removed

- **`_should_use_gum()` from `branch_select.py`.** Dead code with a latent bug. Gum detection stays in Bash.

### Breaking Changes - Makefile Target Naming Normalization

The Makefile targets have been renamed to align with the makefile-dev PRD canonical target taxonomy.

**Static Quality Targets:**
- **NEW**: `sanitize-check` - Read-only static checks (lint + typecheck)
- **NEW**: `sanitize-check-verbose` - Read-only static checks with detailed output
- **REMOVED**: `static` - replaced by `sanitize-check`
- **UPDATED**: `sanitize` now uses `sanitize-check` internally (DRY)

**Gate Targets (Naming Swapped):**
- **`check`** now means PRD-compliant fast gate (sanitize + unit tests only)
- **`check-full`** is the enhanced gate (includes library tests)
- **`check-verbose`** is now PRD-compliant with detailed output
- **`check-full-verbose`** is enhanced with detailed output
- **`validate-full`** added for full release validation including library tests
- **REMOVED**: `check-prd` - `check` is now PRD-compliant

**Test Targets (Naming Swapped):**
- **`test`** now means PRD-compliant behavioral tests (unit + integration)
- **`test-full`** includes all tests (prerequisites + library + unit + integration)
- **`test-verbose`** is now PRD-compliant with detailed output
- **`test-full-verbose`** includes all tests with detailed output
- **REMOVED**: `test-prd` - `test` is now PRD-compliant

**Development Dependencies (dev- prefix added):**
- **`dev-test-deps-install`** - Install test dependencies (replaces removed `test-deps-install`)
- **`dev-optional-install`** - Install optional dependencies (replaces removed `optional-deps-install`)
- **`dev-optional-check`** - Check optional dependencies (replaces removed `optional-deps-check`)

**Documentation:**
- **`docs-deps-install`** - Install documentation dependencies (replaces removed `deps-docs`)

**Migration Guide:**

**For users who used `make check` (old behavior included library tests):**
```bash
# Old: make check (included library tests)
# New: make check-full
```

**For users who used `make test` (old behavior included all tests):**
```bash
# Old: make test (included all tests)
# New: make test-full
```

**For users who used `make static`:**
```bash
# Old: make static
# New: make sanitize-check
```

**Removed Targets (breaking changes - no aliases available):**
- `test-deps-install` → use `dev-test-deps-install`
- `optional-deps-install` → use `dev-optional-install`
- `optional-deps-check` → use `dev-optional-check`
- `deps-docs` → use `docs-deps-install`
- `static` → use `sanitize-check`
- `check-prd` → use `check`
- `test-prd` → use `test`

### Changed - Makefile Canonical Targets (2025-01-13)

The Makefile has been updated to comply with the canonical target taxonomy.
**Breaking change:** Several make targets have been renamed.

**Renamed Targets:**
| Old Target | New Target | Purpose |
|------------|------------|---------|
| `python-check` | `doctor` | Environment & tool readiness check |
| `python-venv-create` | `dev-env-init` | Create virtual environment (one-time) |
| `test-deps-py-install` | `dev-deps-sync` | Sync dependencies from lockfiles |
| `test-check` | `check` | Fast merge gate (sanitize + unit tests) |

**New Targets Added:**
| Target | Purpose |
|--------|---------|
| `format` | Format code (LLM-friendly: summary only) |
| `format-verbose` | Format code (show changes) |
| `lint` | Run linting checks (LLM-friendly) |
| `lint-verbose` | Run linting (detailed) |
| `typecheck` | Type check Python (LLM-friendly) |
| `typecheck-verbose` | Type check Python (detailed) |
| `sanitize` | Run all static checks (format + lint + typecheck) |
| `test-unit-verbose` | Run unit tests (detailed output) |
| `test-integration-verbose` | Run integration tests (detailed output) |
| `test-verbose` | Run all tests (detailed output) |
| `check-verbose` | Merge gate with detailed output |

**Migration Guide:**
- Replace `make python-check` with `make doctor`
- Replace `make python-venv-create` with `make dev-env-init`
- Replace `make test-deps-py-install` with `make dev-deps-sync`
- Replace `make test-check` with `make doctor` (for prerequisites) or `make check` (for full gate)

**New Recommended Workflow:**
```bash
# Initial setup
make doctor
make dev-env-init
make dev-deps-sync

# Development iteration
make sanitize        # Format + lint + typecheck
make test            # Run all tests
make check           # Full merge gate
```
