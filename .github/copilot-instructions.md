# Copilot Instructions for Hug SCM

## Working Persona

**When contributing to this codebase, act as a world-renowned Google principal engineer:**

- **Engineering Excellence:** Write production-grade code with zero shortcuts
- **Systems Thinking:** Consider scalability, maintainability, and long-term impact
- **User Empathy:** Every feature must solve a real user problem
- **Quality First:** Zero dependencies where possible, comprehensive error handling
- **Documentation as Code:** Git history tells the story, commit messages are artifacts
- **Pragmatic Decisions:** Ship high-value features with minimal complexity
- **Performance Mindset:** Optimize for common cases, stream data, avoid unnecessary work

## Project Overview

**Hug SCM** is a humane CLI interface layer for Git and Mercurial that transforms complex version control commands into an intuitive, predictable language. It's written in Bash with comprehensive test coverage via BATS.

**Key Points:**
- Bash-based CLI with 70+ commands organized by semantic prefixes
- Dual VCS support: Git (primary) and Mercurial (parallel implementation)
- Python helpers for computational analysis (co-changes, ownership, activity)
- BATS-based test suite (unit, integration, library tests)
- VitePress documentation with ADRs for architectural decisions
- Safety-first philosophy: shorter commands = safer, longer commands = more powerful

## Development Commands

### Testing

**IMPORTANT: Always use `make` targets for testing, NOT direct `./tests/run-tests.sh` invocation.**

The Makefile provides comprehensive test capabilities with better ergonomics:

```bash
# SHOW_FAILING=1 is recommended for all BATS tests:
# - Shows only failures during test run (less noise)
# - Still shows test count (e.g., "1..248") and summary ("✓ All tests passed!")
# - Makes failures immediately visible when they occur
# - No downside: same confidence signal, cleaner output

# All tests (recommended for final validation)
make test SHOW_FAILING=1                    # Runs ALL tests (BATS + pytest)
                                            # = test-bash + test-lib-py

# BATS-only or pytest-only
make test-bash SHOW_FAILING=1               # All BATS tests (unit + integration + lib)
make test-lib-py                            # Python library tests (pytest)
make test-lib-py-coverage                   # Python tests with coverage report

# BATS test categories (subsets of test-bash)
make test-unit SHOW_FAILING=1               # BATS unit tests (tests/unit/)
make test-integration SHOW_FAILING=1        # BATS integration tests (tests/integration/)
make test-lib SHOW_FAILING=1                # BATS library tests (tests/lib/)

# Run specific BATS test files (supports basename or full path)
make test-unit TEST_FILE=test_head.bats SHOW_FAILING=1
make test-unit TEST_FILE=test_analyze_deps.bats SHOW_FAILING=1
make test-lib TEST_FILE=test_hug_common.bats SHOW_FAILING=1
make test-integration TEST_FILE=test_workflows.bats SHOW_FAILING=1
make test-bash TEST_FILE=test_head.bats SHOW_FAILING=1

# Filter tests by name pattern (works with BATS and pytest)
make test-unit TEST_FILTER="hug w discard" SHOW_FAILING=1
make test-lib TEST_FILTER="confirm_action" SHOW_FAILING=1
make test-bash TEST_FILTER="hug s" SHOW_FAILING=1
make test-lib-py TEST_FILTER="test_analyze" # pytest -k pattern

# Combine BATS options: file + filter + show-failing
make test-unit TEST_FILE=test_analyze_deps.bats TEST_FILTER="dependency" SHOW_FAILING=1
make test-bash TEST_FILTER="hug w" SHOW_FAILING=1

# Check prerequisites without running tests
make test-check                             # BATS dependencies check
```

**Test Hierarchy Summary:**
```
make test (ALL)
├── make test-bash (ALL BATS)
│   ├── make test-unit (tests/unit/*.bats)
│   ├── make test-integration (tests/integration/*.bats)
│   └── make test-lib (tests/lib/*.bats)
└── make test-lib-py (git-config/lib/python/tests/)
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

## Prerequisites

Your environment was already pre-configured with all required tools, so you don't need to install them again.

Some dependencies, like Gum and VHS, are installed in `$HOME/.hug-deps`.

IMPORTANT! Before starting, you need to run `bin/activate` so that everything will be available to you in your `$PATH`, including Hug (no need to provide full command path).

However, you don't really need to call some of the tools directly (vhs, bats, etc) since we have excellent, high-level Makefile targets you should prefer to use instead (check them out).

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

## Coding Standards

### Bash Scripts

1. **Shebang**: Use `#!/usr/bin/env bash` for portability
2. **Safety**: Enable strict mode where appropriate (set -euo pipefail)
3. **Naming Conventions**:
   - Scripts in `git-config/bin/` follow pattern: `git-<command>` or `git-<prefix>-<command>`
   - Use lowercase with hyphens (e.g., `git-w-discard-all`)
   - Main entry point is `hug` script, which calls the needed scripts in `git-config/bin/` or aliases from `git-config/.gitconfig`
4. **Command Prefix Convention**:
   - `h*` = HEAD operations (e.g., h back, h undo, h rewind)
   - `w*` = Working directory (e.g., w discard, w wipe, w zap)
   - `s*` = Status & staging (e.g., s, sl, ss, sw)
   - `b*` = Branching (e.g., b, bc, bl, bpush)
   - `t*` = Tagging (e.g., t, tc, ta, tdel)
   - `l*` = Logging (e.g., l, ll, lf)
   - `f*` = File inspection (e.g., fblame, fcon)
   - `c*` = Commits (e.g., c, ca, caa)
5. **Comments**: Add comments for complex logic, but prefer self-documenting code
6. **Error Handling**: Check command results and provide helpful error messages
7. Leverage charmbracelet Gum when possible for a nicer text UI
8. **Gum Availability**: In scripts and tests, always use the `gum_available` helper function to check if `gum` is installed, instead of calling `command -v gum`.

### Git Integration

- All scripts ultimately call Git or Mercurial commands
- The `hug` main script delegates to `git` or `hg` with appropriate subcommands
- Custom git commands are sourced through Git's extension mechanism
- Use `git --no-pager` to prevent pager issues in scripts

### Safety Philosophy & Security Considerations

Hug follows a "progressive destructiveness" approach:
- Shorter commands = safer (e.g., `hug a` stages tracked files)
- Longer commands = more powerful/destructive (e.g., `hug aa` stages everything)
- Destructive operations require confirmation (unless `-f` flag)
- Provide `--dry-run` for preview where applicable

**Security Guidelines:**
1. **Input Validation**: Always validate user input, especially file paths
2. **Confirmation Prompts**: Destructive operations must prompt for confirmation
3. **No Force by Default**: Never make `-f` or `--force` the default behavior
4. **Safe Defaults**: Commands should fail safe rather than destructively
5. **Clear Warnings**: Use clear, specific warning messages for dangerous operations
6. **Dry Run First**: Implement `--dry-run` for state-modifying commands

## Testing

### Framework: BATS (Bash Automated Testing System)

**Test Structure:**
- `tests/test_helper.bash` - Common setup, utilities, and helpers
- `tests/unit/` - Unit tests for individual commands
- `tests/integration/` - End-to-end workflow tests
- `tests/lib/` - Unit tests for library files (those in `git-config/lib/*`)
**Helper Libraries:**
- bats-support - Enhanced BATS support functions
- bats-assert - Assertion helpers (assert_success, assert_output, etc.)
- bats-file - File system assertions

**Dependency Management:**
The project uses a self-contained test dependency system:
- Users can run `make test-deps-install` to install/update BATS and helpers.
- By default, dependencies are installed in `$HOME/.hug-deps`.
- The installation directory for test dependencies can be overridden by setting the `DEPS_DIR` environment variable.
- The installation directory for the `vhs` dependency can be overridden by setting the `VHS_DEPS_DIR` environment variable.

**Running 1 or more Specific Tests:**
Useful when testing specific functionality, as this is much faster.
Works for all categories (unit, integration, lib) and general `test`.
Filters search the specified file or entire category.
```shell
# Specific file: 
make test-unit TEST_FILE=test_head.bats # (auto-prepends `tests/unit/`)

# Filter (matches @test names across files):
make test-unit TEST_FILTER="hug h back"

# Combine:
make test-unit TEST_FILE=test_head.bats TEST_FILTER="edge case"

# Full paths also work:
make test-unit TEST_FILE=tests/unit/test_head.bats

# Show only failing tests (hides passing test output):
make test-unit SHOW_FAILING=1
make test-unit TEST_FILE=test_head.bats SHOW_FAILING=1
```

**Running ALL Tests or a category:**
Useful for the final test run, after having tested specific functionality (see section above).
```shell
make test                      # Run all tests (recommended)
make test-lib                  # Run unit tests for library files only
make test-unit                 # Run unit tests for Hug commands only
make test-integration          # Run integration tests only

# Show only failing tests for faster identification of failures:
make test SHOW_FAILING=1
make test-unit SHOW_FAILING=1
```

**Writing Tests:**
1. Use descriptive test names: `@test "hug a - stages tracked changes only"`
2. Use `setup()` and `teardown()` functions from test_helper.bash
3. Create isolated test repos with `setup_test_repo()`
4. Use BATS assertions instead of braces: `assert_success`, `assert_output`, `assert_line`
5. Test both success and error cases
6. Include tests for safety features (confirmations, dry-run)

**Test Coverage Requirements:**
- All new commands must include unit tests
- Complex workflows should have integration tests
- Test edge cases and error conditions
- Verify safety mechanisms work correctly

## Documentation

### Location
- Main docs: `/docs/` directory (VitePress)
- Command reference: Primarily in README.md and docs/commands/
- Architecture decisions: `docs/architecture/ADR-*.md`

### Documentation Standards
1. Keep README.md command examples up to date
2. Document new commands in appropriate docs/ pages
3. Use consistent formatting (see existing docs)
4. Include examples for all commands
5. Document flags and options clearly
6. Create ADRs for significant architectural decisions

### Building Docs
```bash
make docs-dev      # Development server
make docs-build    # Production build
make docs-preview  # Preview production build
```

## Development Workflow

### Adding a New Command

1. **Create the script** in `git-config/bin/`:
   ```bash
   # Example: git-config/bin/git-w-newcmd
   #!/usr/bin/env bash
   # Brief description of what this command does

   # Import only needed library files
   . "$HUG_HOME/git-config/lib/hug-terminal"
   . "$HUG_HOME/git-config/lib/hug-output"
   . "$HUG_HOME/git-config/lib/hug-gum"
   . "$HUG_HOME/git-config/lib/hug-git-repo"
   # Implementation
   ```

2. **Make it executable**:
   ```bash
   chmod +x git-config/bin/git-w-newcmd
   ```

3. **Add tests** in appropriate test file:
   ```bash
   # In tests/unit/test_working_dir.bats
   @test "hug w newcmd - does something useful" {
       setup_test_repo
       # Test implementation
       run hug w newcmd
       assert_success
       assert_output --partial "expected output"
   }
   ```

4. **Update documentation**:
   - Add to README.md command reference
   - Add to relevant docs/ pages
   - Include examples

5. **Test thoroughly**:
   ```bash
   make test
   ```

### Modifying Existing Commands

1. Understand the current behavior first
2. Run existing tests to establish baseline
3. Make sure it only imports the library files it needs
4. Make minimal, focused changes
5. Update or add tests for new behavior
6. Run specific tests relevant to your changes (leveraging `TEST_FILTER` and `TEST_FILE`)
7. Once specific tests pass, run full test suite to prevent regressions
6. Update relevant documentation when appropriate

### Common Tasks

**Add a bash script or library file:**
- Place in appropriate location (git-config/bin/ or git-config/lib/)
- Follow naming conventions
- Make executable (chmod +x) if it's not a library file

**Add or modify tests:**
- Use existing tests as templates
- Follow BATS syntax and conventions
- Use test helpers from test_helper.bash
- Test both happy path and error cases

**Update documentation:**
- Edit markdown files in docs/
- Use VitePress markdown extensions where helpful
- Keep examples practical and realistic
- Test if docs still build successfully: `make docs-build`

## Important Notes

### When Working with Bash Scripts

1. **Quote variables**: Always quote variables to prevent word splitting: `"$var"`
2. **Check existence**: Use `[[ -f "$file" ]]` for files, `[[ -d "$dir" ]]` for directories
3. **Exit codes**: 0 = success, non-zero = error
4. **Command substitution**: Use `$()` instead of backticks: `result=$(command)`
5. **Arrays**: Use proper array syntax: `arr=("item1" "item2")`, access with `"${arr[@]}"`
6. **Gum Check**: Use the `gum_available` function instead of `command -v gum` to check for its availability.

### Git Integration Patterns

Hug commands ultimately call Git. Common patterns:
```bash
# Direct git call
git status --short

# Through hug wrapper (delegates to git)
hug sl  # calls git statusbase internally

# Custom git extension
git w-discard  # custom script in git-config/bin/
```

### Testing in Sandboxed Environment

Tests create isolated Git repositories in temp directories:
- Each test gets a fresh repo
- Changes don't affect the real repository
- Cleanup happens automatically via teardown

## CI/CD

- GitHub Actions workflows in `.github/workflows/`
- `test.yml` - Runs test suite on push/PR
- `deploy-docs.yml` - Builds and deploys documentation
- Tests must pass before merging

## Best Practices

1. **Make minimal changes** - Change only what's necessary
2. **Test early and often** - Run tests after each change
3. **Follow existing patterns** - Look at similar commands for guidance
4. **Document as you go** - Update docs with code changes
5. **Safety first** - Maintain Hug's safety philosophy
6. **Be consistent** - Follow naming conventions and command structure
7. **Think about edge cases** - Test error conditions and boundary cases

## Common Pitfalls

### When Adding New Commands

1. **Forgetting to make scripts executable**: Always run `chmod +x git-config/bin/git-<command>` on new scripts
2. **Not testing in isolation**: Always test new commands in a fresh test repository
3. **Breaking existing commands**: Run full test suite before committing changes
4. **Inconsistent naming**: Follow the prefix convention (h*, w*, s*, b*, etc.)

### When Writing Tests

1. **Not using setup_test_repo()**: Tests must create isolated repos via test helper
2. **Depending on external state**: Tests should be self-contained and order-independent
3. **Ignoring test failures**: All tests must pass before merging
4. **Not testing error cases**: Test both success and failure scenarios

### When Modifying Documentation

1. **Forgetting to update README.md**: Keep command reference up to date
2. **Breaking VitePress syntax**: Test docs locally from project root with `npm run docs:dev`
3. **Inconsistent examples**: Use realistic, practical examples

### General Development

3. **Forgetting git --no-pager**: Use in scripts to avoid pager issues
4. **Unquoted variables**: Always quote bash variables: `"$var"` not `$var`

## Commit Message Philosophy

**Git history is documentation.** Each commit message is an artifact that explains WHY a change was made, not just WHAT changed.

### The WHY/WHAT/HOW/IMPACT Structure

Every commit message should follow this pattern:

```
<type>: <concise summary in imperative mood>

WHY: <The problem being solved and its importance>
<Detailed explanation of the user pain point, business need, or technical debt>

WHAT: <The specific changes made>
<High-level overview of the solution>
<Key components modified or added>

HOW: <Implementation approach and technical details>
<Architecture patterns used>
<Algorithms or data structures chosen>

IMPACT: <Real-world benefits for users and developers>
<How this improves user experience>
<Performance implications>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Commit Types

Use conventional commit prefixes:
- **feat:** New feature for users
- **fix:** Bug fix
- **docs:** Documentation changes
- **refactor:** Code restructuring without behavior change
- **perf:** Performance improvements
- **test:** Adding or updating tests
- **chore:** Maintenance tasks (deps, tooling)

## Documentation Organization

**IMPORTANT: Before creating or modifying documentation, consult `docs/DOCS_ORGANIZATION.md` for file placement guidelines.**

### Quick Reference: Where to Put Documentation

| Type | Location | Examples |
|------|----------|----------|
| **User Guides** | `docs/*.md` | getting-started.md, workflows.md |
| **Command Reference** | `docs/commands/*.md` | head.md, branching.md, status-staging.md |
| **Architecture Decisions** | `docs/architecture/ADR-*.md` | ADR-001-automated-testing-strategy.md |
| **Planning Docs** | `docs/planning/*.md` | json-output-roadmap.md |
| **VHS Screencasts** | `docs/screencasts/*.tape` | hug-sl-states.tape, template.tape |
| **Library Docs** | `git-config/lib/README.md` | Library function documentation |
| **Python Helpers** | `git-config/lib/python/README.md` | Python analysis module docs |
| **Testing Guide** | `TESTING.md` (root) | Testing strategy and examples |
| **Contributing** | `CONTRIBUTING.md` (root) | Contribution guidelines |

## Getting Help

- Read existing scripts in `git-config/bin/` for examples
- Check `tests/` for testing patterns
- Review documentation in `docs/`
- Consult TESTING.md for detailed testing guide
- See README.md for command philosophy and structure
- Check CLAUDE.md for comprehensive development guidance

## Quick Reference

**Command Pattern**: `hug <command> [args]`
- Shorter commands = more common/safer
- Longer commands  = more specific/powerful/dangerous

**Command Pattern**: `hug <prefix> [subcommand] [args]`
- Single letter prefix = command category
- Subcommand = specific operation
- Shorter = more common/safer
- Longer = more specific/powerful

**Example**: `hug w discard file.js`
- `w` = working directory category
- `discard` = operation
- `file.js` = target

**Safety Levels** (increasing destructiveness):
- `discard` - Remove unstaged changes
- `wipe` - Remove staged + unstaged
- `purge` - Remove untracked files
- `zap` - Complete cleanup (discard + purge)
- `rewind` - Reset HEAD and discard changes
