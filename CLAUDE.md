# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Hug SCM** is a humane CLI interface layer for Git and Mercurial that transforms complex version control commands into an intuitive, predictable language. It's written in Bash with comprehensive test coverage via BATS.

**Key Points:**
- Bash-based CLI with 60+ commands organized by semantic prefixes
- Dual VCS support: Git (primary) and Mercurial (parallel implementation)
- BATS-based test suite (unit, integration, library tests)
- VitePress documentation with ADRs for architectural decisions
- Safety-first philosophy: shorter commands = safer, longer commands = more powerful

## Development Commands

### Testing

```bash
# All tests (recommended for final validation)
make test

# Specific test categories
make test-unit                              # Unit tests only
make test-integration                       # Integration tests only
make test-lib                               # Library tests only

# Filter and show only failing tests (faster iteration)
make test-unit TEST_FILTER="hug w discard"
make test-unit SHOW_FAILING=1
make test TEST_FILE=test_head.bats          # Specific file

# Direct invocation for advanced options
./tests/run-tests.sh -j 4                   # Parallel execution
./tests/run-tests.sh -v                     # Verbose output
./tests/run-tests.sh -f "exact test name"   # Single test
```

### Installation & Activation

```bash
# Install Hug SCM
make install

# Activate Hug in current shell (required before manual testing)
source bin/activate

# Check test prerequisites
make test-check
```

### Documentation

```bash
make docs-dev                               # Local dev server (port 5173)
make docs-build                             # Production build
make docs-preview                           # Preview production build
```

### Setup

```bash
# Install test dependencies (BATS, helpers)
make test-deps-install

# Install optional dependencies (gum, vhs)
make optional-deps-install

# View all available commands
make help
```

## Project Architecture

### Directory Structure

```
hug-scm/
├── bin/                          # Main entry points
│   ├── hug                        # Dispatcher (auto-detects Git vs Mercurial)
│   ├── hug-clone, hug-init        # Clone/init operations
│   └── activate                   # Shell activation script
│
├── git-config/                    # Git implementation (primary)
│   ├── bin/                       # 60+ command scripts (git-*, named git-<prefix>-<cmd>)
│   ├── lib/                       # 21 modular library functions (~4500 LOC)
│   │   ├── hug-common             # Shared utilities (output, confirmation, colors)
│   │   ├── hug-cli-flags          # GNU getopt-based flag parsing
│   │   ├── hug-gum                # Interactive selection (charmbracelet/gum)
│   │   ├── hug-git-kit            # Git operations (repo, state, files, discard, branch, commit, etc.)
│   │   └── ... 16 more focused modules
│   ├── completions/               # Shell completion scripts
│   └── .gitconfig                 # Git aliases for all Hug commands
│
├── hg-config/                     # Mercurial implementation (parallel to git-config)
│   ├── bin/                       # Mercurial command scripts
│   ├── lib/                       # Shared hug-common + hug-hg-kit
│   └── .hgrc                      # Mercurial configuration
│
├── tests/                         # BATS test suite
│   ├── test_helper.bash           # Common setup/utilities
│   ├── unit/                      # 17 test files for commands
│   ├── lib/                       # 16 test files for library modules
│   ├── integration/               # 4 test files for workflows
│   ├── run-tests.sh               # Test runner with filtering support
│   └── README.md                  # Test documentation
│
├── docs/                          # VitePress documentation
│   ├── architecture/              # ADRs (testing strategy, Mercurial support)
│   ├── commands/                  # Command reference docs
│   ├── .vitepress/                # VitePress config
│   └── *.md                       # User documentation
│
├── .github/workflows/             # CI/CD automation
│   ├── test.yml                   # Run BATS tests on push/PR
│   ├── deploy-docs.yml            # Deploy VitePress docs
│   └── regenerate-vhs-images.yml  # Screencast updates
│
├── Makefile                       # Development commands
├── README.md                      # Main project readme
├── TESTING.md                     # Testing guide
├── CONTRIBUTING.md               # Contribution guidelines
└── install.sh                     # Installation script
```

### Command Organization

Commands are organized by semantic prefixes:

| Prefix | Category | Examples |
|--------|----------|----------|
| `h*` | HEAD operations | h, h-back, h-undo, h-squash, h-rewind, h-rollback |
| `w*` | Working directory | w, w-discard, w-wipe, w-purge, w-zap, w-unwip, w-get |
| `s*` | Status & staging | s, a, aa, us, usa, sl, sla, ss, su, sw |
| `b*` | Branching | b, bc, bl, bpush, bpull, bdel, bpullr |
| `c*` | Commits | c, ca, caa, cm, cma, ccp, cmv |
| `l*` | Logging | l, ll, la, lp, lf, lc, lau, ld |
| `f*` | File inspection | fblame, fb, fcon, fa, fborn |
| `t*` | Tagging | t, tc, ta, ts, tr, tm, tdel |
| `r*`, `m*` | Rebase & merge | rb, rbi, rbc, m, mff, mkeep |

### Library Architecture

All command scripts source shared libraries. Key modules:

- **hug-common**: Utilities for colors, output, confirmations, arrays
- **hug-cli-flags**: GNU getopt-based flag parsing (supports `-f`, `--dry-run`, combined flags)
- **hug-gum**: Interactive selection wrapper around charmbracelet/gum
- **hug-git-repo**: Repository & commit validation, path operations
- **hug-git-state**: Working tree state checks (staged, unstaged, clean)
- **hug-git-files**: File listing functions (staged, unstaged, tracked, untracked, ignored)
- **hug-git-discard**: Discard operations with dry-run and confirmation support
- **hug-git-branch**: Branch info, display, interactive selection
- **hug-git-commit**: Commit range analysis, preview helpers
- **hug-git-upstream**: Upstream operation handlers
- **hug-git-backup**: Backup branch management
- **hug-git-rebase**: Rebase conflict resolution helpers

See `git-config/lib/README.md` for comprehensive library documentation.

## Key Implementation Patterns

### Command Script Template

All command scripts follow this pattern:

```bash
#!/usr/bin/env bash
CMD_BASE="$(readlink -f "$0" 2>/dev/null || greadlink -f "$0")" || CMD_BASE="$0"
CMD_BASE="$(dirname "$CMD_BASE")"
for f in hug-common hug-git-kit; do . "$CMD_BASE/../lib/$f"; done
set -euo pipefail

# Command implementation
```

### Gateway Command Pattern (for command categories)

```bash
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  subcommand1) shift; git x-subcommand1 "$@" ;;
  subcommand2) shift; git x-subcommand2 "$@" ;;
  *) echo "Usage: hug x <subcommand>"; exit 1 ;;
esac
```

### Confirmation Pattern

Always use the library function, respects `HUG_FORCE`:

```bash
if [[ $force == true ]]; then
  export HUG_FORCE=true
fi
# Later...
confirm_action "delete"  # User types "delete" to confirm
```

### Dry-Run Support

Destructive operations should support `--dry-run`:

```bash
if $dry_run; then
  printf 'Would perform these actions:\n'
  print_list 'Files' "${files[@]}"
  return 0
fi
# Actual operation here
```

## Testing Strategy

### Framework: BATS (Bash Automated Testing System)

**Why BATS:** Native Bash, perfect for testing Bash scripts, TAP-compliant, used by Docker/Homebrew, excellent CI/CD integration.

**Test Structure:**
- **Unit tests** (tests/unit/): Individual command testing (~30KB, 17 files)
- **Library tests** (tests/lib/): Library module validation (~30KB, 16 files)
- **Integration tests** (tests/integration/): End-to-end workflows (~25KB, 4 files)

### Test Helpers (test_helper.bash)

Key utilities available to all tests:

```bash
# Repository setup
create_test_repo()               # Fresh git repo
create_test_repo_with_history()  # Repo with commits
create_test_repo_with_changes()  # Repo with uncommitted changes
cleanup_test_repo()              # Cleanup

# Assertions
assert_success / assert_failure
assert_output "text" / assert_output --partial "text"
assert_file_exists / assert_file_not_exists
assert_git_clean()

# Environment
require_hug()                    # Skip if hug not installed
require_git_version "2.23"       # Skip if git too old
```

### Writing Tests

Use the Arrange-Act-Assert pattern:

```bash
@test "hug command: does something" {
  # Arrange
  echo "content" > file.txt

  # Act
  run hug command args

  # Assert
  assert_success
  assert_output --partial "expected"
}
```

Test both success and error cases, edge cases, and safety features (confirmations, dry-run).

### Coverage Goals

**Target: >80% overall coverage**

Current status:
- ✅ Status/staging (s*, a*, us*)
- ✅ Working directory (w*)
- ✅ HEAD operations (h*)
- ✅ Library modules (hug-fs, hug-common)
- ⏳ Branch operations, commits, logging, tagging (in progress)

## Development Workflow

### Adding a New Command

1. Create script in `git-config/bin/` following the standard template
2. Make it executable: `chmod +x git-config/bin/git-<cmd>`
3. Add tests in appropriate `tests/unit/` file
4. Update README.md command reference and `docs/commands/` pages
5. Run tests: `make test`

### Modifying Existing Commands

1. Run existing tests to establish baseline
2. Make minimal, focused changes
3. Update or add tests for new behavior
4. Run specific tests: `make test-unit TEST_FILTER="command name"`
5. Run full suite: `make test`
6. Update documentation

### Before Committing

```bash
# Test locally
make test

# Verify specific functionality
make test-unit TEST_FILE=test_head.bats SHOW_FAILING=1

# Check documentation builds
make docs-build
```

## Important Notes

### Bash Best Practices

- **Quote variables**: `"$var"` not `$var`
- **Use `$()` for substitution**: Not backticks
- **Check existence**: `[[ -f "$file" ]]` for files, `[[ -d "$dir" ]]` for dirs
- **Use proper arrays**: `arr=("item1" "item2")`, access with `"${arr[@]}"`
- **Exit codes**: 0 = success, non-zero = error
- **Gum availability**: Use `gum_available` helper, not `command -v gum`

### Git Integration Patterns

- Use `git --no-pager` in scripts to prevent pager issues
- Commands ultimately call Git or Mercurial via Git's extension mechanism
- All state-modifying commands should support `--dry-run` and `-f/--force`

### Safety Philosophy

- Shorter commands = safer (e.g., `hug a` stages tracked files only)
- Longer commands = more powerful/destructive (e.g., `hug aa` stages everything)
- All destructive operations require confirmation (unless `-f` flag)
- Provide `--dry-run` for preview where applicable
- Always validate input, especially file paths

### Environment Variables

- `HUG_FORCE`: Skip confirmation prompts when `true`
- `HUG_QUIET`: Suppress output functions when set (any value)
- `GIT_PREFIX`: Git prefix path (usually auto-set)
- `HUG_HOME`: Set by installation to home directory of Hug installation

## Architecture Documentation

**ADRs (Architecture Decision Records)** in `docs/architecture/`:

- **ADR-001: Automated Testing Strategy** - Rationale for choosing BATS, test structure
- **ADR-002: Mercurial Support Architecture** - Parallel implementation approach for hg support

These provide important context for major architectural decisions.

## Common Pitfalls

### When Adding Commands

- Forgetting to make scripts executable (`chmod +x`)
- Not testing in isolation (use fresh test repos)
- Breaking existing commands (always run full test suite)
- Inconsistent naming (follow prefix convention)

### When Writing Tests

- Not using `setup_test_repo()` (creates isolated repos)
- Depending on external state (tests must be self-contained)
- Ignoring test failures (all tests must pass before merging)
- Not testing error cases (test both success and failure)

### When Modifying Documentation

- Forgetting to update README.md command reference
- Breaking VitePress syntax (test with `make docs-build`)
- Inconsistent examples (use realistic, practical examples)

## Documentation Structure

- **README.md**: Main project overview and command reference
- **TESTING.md**: Comprehensive testing guide with examples
- **CONTRIBUTING.md**: Contribution guidelines
- **git-config/lib/README.md**: Library function documentation and patterns
- **docs/**: VitePress site with command docs and architecture decisions
- **docs/architecture/ADR-*.md**: Architectural decision records

## Useful References

- Test examples: Look at existing tests in `tests/unit/`, `tests/lib/`, `tests/integration/`
- Command examples: See scripts in `git-config/bin/` for real-world patterns
- Library patterns: Check `git-config/lib/README.md` for common usage patterns
- BATS docs: https://bats-core.readthedocs.io/
- GitHub Issues: Existing discussions provide context for design decisions
