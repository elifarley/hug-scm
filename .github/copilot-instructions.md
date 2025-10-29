# Copilot Instructions for Hug SCM

## Project Overview

Hug is a CLI tool that provides a humane, intuitive interface for Git and other version control systems. It transforms complex Git commands into a simple, predictable language that feels natural to use.

**Key Facts:**
- Written in Bash scripts (/git-config/bin/*) and git aliases (/git-config/.git-config)
- Acts as a wrapper/interface layer over Git
- Currently only supports Git and Mercurial (future: Sapling)
- Documentation site built with VitePress

## Prerequisites

Before working on this project, ensure you have:

**Required:**
- Bash 4.0 or higher
- Git 2.0 or higher
- Make (for running build commands)

**For Testing:**
- BATS (Bash Automated Testing System) - automatically installed via `make test-deps-install`
- Helper libraries (bats-support, bats-assert, bats-file) - automatically installed

**For Documentation:**
- Node.js 16+ and npm (for VitePress documentation)
- VHS (for creating images used in /docs/*)

**Setup:**
1. Install Hug: `make install`
2. Install test dependencies: `make test-deps-install`
3. Install documentation dependencies: `make vhs-deps-install`
4. Activate in current shell: `source bin/activate`

## Repository Structure

```
hug-scm/
├── git-config/              # Git-specific implementation
│   ├── bin/                 # Executable Bash scripts (git-* and hug)
│   ├── lib/                 # Shared library code
│   │   ├── hug-common       # Common utilities
│   │   └── hug-git-kit      # Git-specific helpers
│   ├── completions/         # Shell completion scripts
│   └── install.sh           # Installation script
├── docs/                    # VitePress documentation
│   ├── .vitepress/          # VitePress config
│   ├── commands/            # Command documentation
│   ├── architecture/        # ADRs and design docs
│   └── *.md                 # Documentation pages
├── tests/                   # BATS test suite
│   ├── test_helper.bash     # Shared test utilities
│   ├── unit/                # Unit tests for individual commands
│   └── integration/         # Workflow/integration tests
└── *.md                     # Root documentation
```

## Coding Standards

### Bash Scripts

1. **Shebang**: Use `#!/usr/bin/env bash` for portability
2. **Safety**: Enable strict mode where appropriate (set -euo pipefail)
3. **Naming Conventions**:
   - Scripts in `git-config/bin/` follow pattern: `git-<command>` or `git-<prefix>-<command>`
   - Use lowercase with hyphens (e.g., `git-w-discard-all`)
   - Main entry point is `hug` script
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

### Git Integration

- All scripts ultimately call Git commands
- The `hug` main script delegates to `git` with appropriate subcommands
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

Before running tests, you must install Hug via `make install; make test-deps-install`.

**Test Structure:**
- `tests/test_helper.bash` - Common setup, utilities, and helpers
- `tests/unit/` - Unit tests for individual commands
- `tests/integration/` - End-to-end workflow tests
- `tests/deps/` - Local test dependencies (auto-installed, listed in .gitignore)

**Helper Libraries:**
- bats-support - Enhanced BATS support functions
- bats-assert - Assertion helpers (assert_success, assert_output, etc.)
- bats-file - File system assertions

**Dependency Management:**
The project uses a self-contained test dependency system:
- Run `make test-deps-install` to install/update BATS and helpers locally
- Test runner automatically bootstraps dependencies if missing
- Dependencies are stored in `tests/deps/` and ignored by git
- Can be overridden via `DEPS_DIR` env var for custom paths (e.g., in CI or restricted environments)

**Running Tests:**
```bash
make test-deps-install         # Install BATS and helpers first
make test                      # Run all tests (recommended)
make test-unit                 # Run unit tests only
make test-integration          # Run integration tests only
make test-check                # Check prerequisites
```

**Writing Tests:**
1. Use descriptive test names: `@test "hug a - stages tracked changes only"`
2. Use `setup()` and `teardown()` functions from test_helper.bash
3. Create isolated test repos with `setup_test_repo()`
4. Use BATS assertions: `assert_success`, `assert_output`, `assert_line`
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
npm run docs:dev      # Development server
npm run docs:build    # Production build
npm run docs:preview  # Preview production build
```

## Development Workflow

### Adding a New Command

1. **Create the script** in `git-config/bin/`:
   ```bash
   # Example: git-config/bin/git-w-newcmd
   #!/usr/bin/env bash
   # Brief description of what this command does
   
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
3. Make minimal, focused changes
4. Update or add tests for new behavior
5. Update documentation if behavior changes
6. Run full test suite to prevent regressions

### Common Tasks

**Add a bash script:**
- Place in appropriate location (git-config/bin/ or git-config/lib/)
- Follow naming conventions
- Make executable (chmod +x)
- Source library files if needed: `. "$(git --exec-path)/hug-common"`

**Add or modify tests:**
- Use existing tests as templates
- Follow BATS syntax and conventions
- Use test helpers from test_helper.bash
- Test both happy path and error cases

**Update documentation:**
- Edit markdown files in docs/
- Use VitePress markdown extensions where helpful
- Keep examples practical and realistic
- Test docs locally: `npm run docs:dev`

## Important Notes

### When Working with Bash Scripts

1. **Quote variables**: Always quote variables to prevent word splitting: `"$var"`
2. **Check existence**: Use `[[ -f "$file" ]]` for files, `[[ -d "$dir" ]]` for directories
3. **Exit codes**: 0 = success, non-zero = error
4. **Command substitution**: Use `$()` instead of backticks: `result=$(command)`
5. **Arrays**: Use proper array syntax: `arr=("item1" "item2")`, access with `"${arr[@]}"`

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

1. **Not activating Hug**: Run `source bin/activate` after installation
2. **Skipping `make install`**: Required before running tests
3. **Forgetting git --no-pager**: Use in scripts to avoid pager issues
4. **Unquoted variables**: Always quote bash variables: `"$var"` not `$var`

## Getting Help

- Read existing scripts in `git-config/bin/` for examples
- Check `tests/` for testing patterns
- Review documentation in `docs/`
- Consult TESTING.md for detailed testing guide
- See README.md for command philosophy and structure

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
