# Changelog

All notable changes to the Hug SCM project will be documented in this file.

## [Unreleased]

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
- **`dev-test-deps-install`** - Install test dependencies (was `test-deps-install`, now deprecated)
- **`dev-optional-install`** - Install optional dependencies (was `optional-deps-install`, now deprecated)
- **`dev-optional-check`** - Check optional dependencies (was `optional-deps-check`, now deprecated)

**Documentation:**
- **`docs-deps-install`** - Install documentation dependencies (was `deps-docs`, now deprecated)

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

**CI/CD updates:**
- If you relied on `make check` including library tests, update to `make check-full`
- If you relied on `make test` running all tests, update to `make test-full`
- If you used `make test-deps-install`, update to `make dev-test-deps-install`
- If you used `make optional-deps-install`, update to `make dev-optional-install`
- If you used `make deps-docs`, update to `make docs-deps-install`

**New Recommended Workflow:**
```bash
# Initial setup
make doctor
make dev-env-init
make dev-deps-sync

# Development iteration
make sanitize-check   # Read-only static checks (no formatting)
make sanitize         # Format + lint + typecheck
make test             # Unit + integration tests (PRD-compliant)
make check            # Fast merge gate (PRD-compliant)

# Full validation (includes library tests)
make test-full
make check-full
make validate-full
```

**Deprecated Targets (still available, show warnings):**
- `test-deps-install` → use `dev-test-deps-install`
- `optional-deps-install` → use `dev-optional-install`
- `optional-deps-check` → use `dev-optional-check`
- `deps-docs` → use `docs-deps-install`

## [Unreleased] - 2025-01-13

### Changed - Makefile Canonical Targets

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
