# Changelog

All notable changes to the Hug SCM project will be documented in this file.

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
