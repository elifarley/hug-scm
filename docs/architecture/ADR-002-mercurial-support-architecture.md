# ADR-002: Mercurial Support Architecture

**Status**: Accepted  
**Date**: 2025-10-23  
**Decision Makers**: Engineering Team  
**Context**: Hug SCM currently only supports Git. The project aims to provide a unified interface for multiple version control systems, with Mercurial (hg) being the next target.

## Problem Statement

Hug SCM needs to add Mercurial support while:
- Maintaining the same intuitive command interface for users
- Preserving the existing Git implementation without disruption
- Creating an extensible architecture for future SCM additions
- Ensuring code reusability and maintainability
- Supporting both Git and Mercurial repositories seamlessly

## Constraints

1. **Backward Compatibility**: Existing Git functionality must remain unchanged
2. **Unified Interface**: Users should use the same `hug` commands regardless of SCM
3. **Code Organization**: Clear separation between SCM-specific and common code
4. **Minimal Duplication**: Share common functionality where possible
5. **Testing**: Comprehensive test coverage for both Git and Mercurial
6. **Installation**: Support systems with only Git, only Mercurial, or both

## Options Considered

### Option 1: Parallel Directory Structure (Selected)

**Description**: Create a parallel `hg-config` directory mirroring the `git-config` structure, with SCM-specific implementations and shared common libraries.

```
hug-scm/
├── git-config/
│   ├── bin/           # Git-specific commands (git-a, git-b, etc.)
│   ├── lib/
│   │   ├── hug-common      # Common utilities (shared)
│   │   └── hug-git-kit     # Git-specific operations
│   └── .gitconfig          # Git aliases
├── hg-config/
│   ├── bin/           # Mercurial-specific commands (hg-a, hg-b, etc.)
│   ├── lib/
│   │   ├── hug-common      # Symlink to git-config/lib/hug-common
│   │   └── hug-hg-kit      # Mercurial-specific operations
│   └── .hgrc              # Mercurial config
└── bin/
    └── hug            # Main dispatcher (detects SCM and delegates)
```

**Pros**:
- ✅ **Clear Separation**: Git and Mercurial code are cleanly separated
- ✅ **Minimal Git Impact**: No changes to existing Git implementation
- ✅ **Shared Common Code**: Both SCMs use the same `hug-common` library
- ✅ **Easy Testing**: Can test Git and Mercurial independently
- ✅ **Future Extensibility**: Easy to add more SCMs (svn-config, etc.)
- ✅ **Selective Installation**: Users can choose which SCMs to install
- ✅ **Familiar Pattern**: Mirrors the existing structure developers know

**Cons**:
- ⚠️ Some code duplication for SCM-specific implementations
- ⚠️ Need to maintain two sets of command scripts

**Implementation Details**:
- Main `hug` script detects repository type (`.git` vs `.hg`)
- Delegates to `git <subcommand>` or `hg <subcommand>` accordingly
- Common library shared via symlink
- SCM-specific libraries (hug-git-kit, hug-hg-kit) handle differences

---

### Option 2: Single Directory with Conditional Logic

**Description**: Keep all commands in one directory with conditional logic to handle Git vs Mercurial.

```
hug-scm/
├── bin/
│   ├── git-a    # Contains both git and hg logic
│   ├── git-b    # if is_git; then ... else hg ...; fi
│   └── ...
└── lib/
    ├── hug-common
    ├── hug-git-kit
    └── hug-hg-kit
```

**Pros**:
- ✅ Single set of command files
- ✅ All logic in one place

**Cons**:
- ❌ **Complex Scripts**: Each command contains branching logic
- ❌ **Hard to Maintain**: Changes affect both SCMs
- ❌ **Difficult Testing**: Hard to test Git/Mercurial independently
- ❌ **Git Disruption**: Requires modifying all existing Git commands
- ❌ **Poor Separation**: Violates single responsibility principle
- ❌ **Harder Debugging**: More complex to trace execution paths

---

### Option 3: Plugin Architecture

**Description**: Create a plugin system where each SCM is a dynamically loaded plugin.

```
hug-scm/
├── core/          # Core hug functionality
├── plugins/
│   ├── git/       # Git plugin
│   └── mercurial/ # Mercurial plugin
└── bin/hug        # Plugin loader
```

**Pros**:
- ✅ Very extensible
- ✅ True plugin architecture

**Cons**:
- ❌ **Over-Engineering**: Too complex for current needs
- ❌ **Performance**: Plugin loading overhead
- ❌ **Bash Limitations**: Difficult to implement cleanly in Bash
- ❌ **Major Refactoring**: Requires rewriting existing Git support
- ❌ **Complexity**: Harder for contributors to understand

---

### Option 4: Wrapper with Backend Switching

**Description**: Single `hug` command that wraps and translates to Git or Mercurial commands.

```
hug-scm/
├── bin/
│   └── hug        # Translates hug commands to git or hg
└── lib/
    ├── translations.conf  # Command mappings
    └── ...
```

**Pros**:
- ✅ Single command entry point
- ✅ Simple translation table

**Cons**:
- ❌ **Loses Rich Functionality**: Hard to implement complex operations
- ❌ **Limited Flexibility**: Can't handle SCM-specific features
- ❌ **Poor Error Handling**: Generic translations miss nuances
- ❌ **Not Extensible**: Doesn't scale to more complex operations

---

## Decision

**We will adopt Option 1: Parallel Directory Structure**

This approach provides the best balance of:
- Clear separation of concerns
- Minimal impact on existing Git implementation
- Maintainability and testability
- Future extensibility for additional SCMs
- Code reusability through shared libraries

## Architecture Design

### Directory Structure

```
hug-scm/
├── git-config/
│   ├── bin/
│   │   ├── git-a, git-aa, git-b, git-bc, ...
│   │   ├── git-h, git-h-back, git-h-undo, ...
│   │   ├── git-w, git-w-discard, git-w-purge, ...
│   │   └── hug (dispatcher)
│   ├── lib/
│   │   ├── hug-common           # Common utilities
│   │   └── hug-git-kit          # Git-specific operations
│   ├── .gitconfig
├── hg-config/
│   ├── bin/
│   │   ├── hg-a, hg-aa, hg-b, hg-bc, ...
│   │   ├── hg-h, hg-h-back, hg-h-undo, ...
│   │   ├── hg-w, hg-w-discard, hg-w-purge, ...
│   │   └── hug (symlink to git-config/bin/hug)
│   ├── lib/
│   │   ├── hug-common           # Symlink to git-config/lib/hug-common
│   │   └── hug-hg-kit           # Mercurial-specific operations
│   ├── .hgrc
├── tests/
│   ├── unit/
│   │   ├── test_git_*.bats      # Git-specific tests
│   │   └── test_hg_*.bats       # Mercurial-specific tests
│   └── integration/
│       ├── test_git_workflows.bats
│       └── test_hg_workflows.bats
└── docs/
    └── architecture/
        └── ADR-002-mercurial-support-architecture.md
```

### Command Mapping

| Hug Command | Git Command | Mercurial Command |
|-------------|-------------|-------------------|
| `hug s` | `git status` | `hg status` |
| `hug a` | `git add -u` | `hg addremove` |
| `hug aa` | `git add -A` | `hg addremove` |
| `hug c` | `git commit` | `hg commit` |
| `hug b <branch>` | `git switch <branch>` | `hg update <branch>` |
| `hug bc <branch>` | `git switch -c <branch>` | `hg branch <branch>` |
| `hug l` | `git log --oneline --graph` | `hg log -G` |
| `hug w discard` | `git restore` | `hg revert` |
| `hug w purge` | `git clean` | `hg purge --all` |
| `hug h back` | `git reset --soft HEAD~1` | `hg rollback` / `hg uncommit` |
| `hug h undo` | `git reset HEAD~1` | `hg uncommit --keep` |

### Core Components

#### 1. Main Dispatcher (bin/hug)

The main `hug` command detects the repository type and dispatches to the appropriate backend:

```bash
#!/usr/bin/env bash
# Detect repository type and dispatch

if git rev-parse --git-dir >/dev/null 2>&1; then
    # Git repository
    exec git "$@"
elif hg root >/dev/null 2>&1; then
    # Mercurial repository
    exec hg "$@"
else
    echo "Error: Not in a Git or Mercurial repository"
    exit 1
fi
```

#### 2. Common Library (hug-common)

Shared by both Git and Mercurial, contains:
- Color definitions
- Output functions (error, warning, info, success)
- User interaction (prompts, confirmations)
- String/array manipulation
- File system utilities

**No changes needed** - works for both SCMs.

#### 3. SCM-Specific Libraries

**hug-git-kit**: Git-specific operations (existing, unchanged)

**hug-hg-kit**: New Mercurial-specific operations
- Repository validation
- Commit operations
- Branch management
- Working directory state
- Change operations (revert, purge)

### Mercurial Command Implementation Strategy

#### Phase 1: Core Commands (Essential)
- Status and staging: `s`, `sl`, `sla`, `a`, `aa`, `us`
- Commits: `c`, `ca`, `caa`
- Branching: `b`, `bc`, `bl`, `bs`
- Logging: `l`, `ll`, `la`

#### Phase 2: Working Directory (Important)
- Discard: `w discard`, `w discard-all`
- Purge: `w purge`, `w purge-all`
- Wipe/Zap: `w wipe`, `w wipe-all`, `w zap`, `w zap-all`

#### Phase 3: HEAD Operations (Advanced)
- `h back`: Soft undo (uncommit, keep changes)
- `h undo`: Reset (uncommit, unstage)
- `h rollback`: Remove commits and changes
- `h rewind`: Hard reset to commit

#### Phase 4: Additional Features
- WIP operations: `wip`, `wips`, `unwip`
- Tagging: `t*` commands
- File inspection: `f*` commands
- Advanced operations: rebase, merge equivalents

### Key Mercurial Differences to Handle

1. **Branching Model**:
   - Git: Branches are references (cheap)
   - Mercurial: Branches are permanent (recorded in commits)
   - Bookmarks in Mercurial are closer to Git branches

2. **Staging Area**:
   - Git: Has explicit staging area (index)
   - Mercurial: No staging area (commits directly from working directory)
   - Hug abstraction: Stage operations in Mercurial will prepare for commit

3. **Command Equivalents**:
   - `git reset`: `hg rollback` or `hg uncommit` (requires extension)
   - `git restore`: `hg revert`
   - `git clean`: `hg purge` (requires extension)
   - `git switch`: `hg update` or `hg bookmark`

4. **Extensions Required**:
   - `evolve`: For modern change operations (amend, uncommit)
   - `purge`: For cleaning untracked files
   - `rebase`: For rebase operations

### Testing Strategy

Following ADR-001 (BATS testing):

#### Unit Tests
- `tests/unit/test_hg_status_staging.bats`
- `tests/unit/test_hg_working_dir.bats`
- `tests/unit/test_hg_head.bats`
- `tests/unit/test_hg_branching.bats`

#### Integration Tests
- `tests/integration/test_hg_workflows.bats`
- Cross-SCM tests (if applicable)

#### Test Helpers
- `create_test_hg_repo()`: Create Mercurial test repository
- `require_hg()`: Skip test if Mercurial not installed
- `require_hg_extension()`: Skip test if extension unavailable

### Installation

#### Git Only
```bash
./install.sh --git-only
```

#### Mercurial Only
```bash
./install.sh --hg-only
```

#### Both (Default)
```bash
./install.sh
```

The installer will:
1. Detect which SCMs are available
2. Install support for available SCMs
3. Configure PATH and aliases
4. Set up completions

### Documentation Updates

1. **README.md**: Add Mercurial examples
2. **Installation Guide**: Add Mercurial prerequisites
3. **Command Reference**: Add Mercurial equivalents
4. **Core Concepts**: Explain SCM abstraction layer

## Implementation Plan

### Phase 1: Foundation (Sprint 1)
1. ✅ Create ADR-002 document
2. Create `hg-config/` directory structure
3. Create `hug-hg-kit` library with core functions
4. Update main `hug` dispatcher for SCM detection
5. Set up test infrastructure for Mercurial

### Phase 2: Core Commands (Sprint 2)
1. Implement status commands (`s`, `sl`, `sla`)
2. Implement staging commands (`a`, `aa`, `us`)
3. Implement commit commands (`c`, `ca`, `caa`)
4. Implement basic branching (`b`, `bc`, `bl`)
5. Add unit tests for each command group

### Phase 3: Working Directory (Sprint 3)
1. Implement discard operations
2. Implement purge operations
3. Implement wipe/zap operations
4. Add comprehensive tests

### Phase 4: Advanced Features (Sprint 4)
1. Implement HEAD operations
2. Implement WIP workflow
3. Implement logging commands
4. Add integration tests

### Phase 5: Polish & Documentation (Sprint 5)
1. Add tagging support
2. Add file inspection commands
3. Complete documentation
4. Update installation scripts
5. Add completion scripts for Mercurial

## Metrics for Success

- All core Git commands have Mercurial equivalents
- Test coverage >80% for Mercurial commands
- Zero regression in Git functionality
- Documentation covers both SCMs
- Installation works on Ubuntu and macOS
- Commands feel natural for both Git and Mercurial users

## Future Considerations

### Additional SCMs
This architecture allows easy addition of:
- **Sapling**: Meta's VCS (similar to Mercurial)
- **Fossil**: Distributed VCS with built-in wiki/tickets
- **SVN**: Centralized VCS (via svn-config/)

### Unified Command Completion
Improve tab completion to work across SCMs:
```bash
hug b <TAB>  # Lists branches from current SCM
```

### Cross-SCM Operations
Potential for repository conversion helpers:
```bash
hug convert --from git --to hg
```

### Performance Optimization
- Cache SCM detection results
- Lazy load SCM-specific libraries
- Optimize common operations

## References

- [Mercurial Documentation](https://www.mercurial-scm.org/doc/)
- [Mercurial Book](http://hgbook.red-bean.com/)
- [Git to Mercurial Equivalents](https://www.mercurial-scm.org/wiki/GitConcepts)
- [ADR-001: Automated Testing Strategy](./ADR-001-automated-testing-strategy.md)

## Revision History

- 2025-10-23: Initial decision document created
