# Worktree Command Family Enhancements Roadmap

## Overview

The `wt*` command family has been successfully implemented with the core commands (wt, wtl, wtll, wtc, wtdel). This roadmap outlines planned enhancements to extend the worktree management capabilities to match the full functionality of the `b*` (branch) command family and add worktree-specific utilities.

## Current State: Complete ✅

**Implemented Commands:**
- `hug wt` - Interactive worktree management (like hug b)
- `hug wtl` - List worktrees in short format (like hug bl)
- `hug wtll` - List worktrees in long format with details (like hug bll)
- `hug wtc <branch>` - Create worktree for existing branch (like hug bc)
- `hug wtdel [path]` - Remove worktree safely (like hug bdel)

## Phase 1: Core Missing Parallels (High Priority)

### 1.1 `hug wtmv` - Move/Rename Worktree

**Priority**: 🔴 High
**Pattern**: Parallel to `hug bmv` (branch move)
**Implementation**: Uses `git worktree move` (Git 2.30+)

**Use Cases:**
```bash
# Move/rename worktree using absolute paths
hug wtmv ~/old-workspace/feature-auth ~/new-workspace/feature-auth

# Force move (skip confirmation)
hug wtmv ~/project-feature ~/new-location -f
```

**Implementation Details:**
- Support both path moves and directory renames
- Auto-update any worktree-specific configuration
- Validate destination doesn't conflict with existing worktrees
- Integration with existing worktree validation logic

**Safety Features:**
- Check for uncommitted changes before move
- Verify destination directory is available
- Confirm operation unless `--force` used
- Preserve all worktree metadata and configuration

### 1.2 `hug wtprune` - Prune Stale Worktree Metadata

**Priority**: 🔴 High
**Pattern**: Worktree-specific maintenance command
**Implementation**: Uses `git worktree prune`

**Use Cases:**
```bash
# Clean up metadata for deleted worktree directories
hug wtprune

# Show what would be pruned without actually doing it
hug wtprune --dry-run

# Force prune all stale worktree references
hug wtprune --force

# Verbose output showing what's being cleaned
hug wtprune --verbose
```

**Implementation Details:**
- Identify worktree references pointing to deleted directories
- Clean up orphaned worktree metadata
- Interactive confirmation before pruning
- Detailed reporting of what was pruned
- Integration with existing worktree validation

**Safety Features:**
- Always show what will be pruned before execution
- Require confirmation unless `--force` used
- Never remove worktrees that exist on disk
- Preserve valid worktree metadata

## Phase 2: Enhanced Information & Discovery (Medium Priority)

### 2.1 `hug wtsh` - Detailed Worktree Information

We already have `hug sh [commitish]` to show detailed info on a commit. if no commit is provided, it shows info on HEAD:

```shell
hug sh
  427878c Sat Nov 22 07:10 (7 days ago) [musistudio] (HEAD -> main, origin/main  , origin/HEAD)
  release 1.0.71
   
   
   README.md                             |  1 +
   README_zh.md                          |  1 +
   package.json                          |  4 ++--
   pnpm-lock.yaml                        | 10 +++++-----
   ui/src/components/ui/color-picker.tsx | 28 +++++++++++++++-------------
   ui/src/locales/en.json                |  9 +++++++++
   ui/src/locales/zh.json                |  9 +++++++++
   7 files changed, 42 insertions(+), 20 deletions(-)
```

So `hug wtsh` could show details on a worktree.

**Priority**: 🟡 Medium
**Pattern**: Worktree-specific information command

**Use Cases:**
```bash
# Detailed info about current worktree
hug wtsh

# Info about specific worktree
hug wtsh ~/workspaces-project/feature-auth

# Include remote tracking information
hug wtsh --remotes

# Show configuration details
hug wtsh --config
```

**Output Format:**
```
Worktree: ~/workspaces-project/feature-auth
Branch: feature-auth
Commit: a3f2b1c (feat: implement OAuth authentication)
Status: Clean ✓
Locked: No
Remote: origin/feature-auth (ahead 2, behind 1)
Created: 2024-11-15 14:30:22
Last Modified: 2024-11-20 09:15:45
Configuration:
  core.sparsecheckout = true
  pull.rebase = true
```

### 2.2 `hug wtfind` - Find Worktree by Branch

Note: we already have `hug bwp`: Show 'Branches Which Point' directly at an object.
I've created an alias: wtwp = wtfind. good?

**Priority**: 🟡 Medium
**Pattern**: Worktree discovery command

**Use Cases:**
```bash
# Find worktree for specific branch
hug wtfind feature-auth

# Find worktree for branch selected via interactive branch selection menu
hug wtfind

# List all branch-to-worktree mappings
hug wtfind --all

# JSON output for automation
hug wtfind --json

# Find multiple branches
hug wtfind feature-auth hotfix-bug
```

**Implementation Details:**
- Fast lookup of worktree paths by branch name
- Support multiple branch search
- JSON output for integration with scripts
- Handle cases where branch has no worktree
- Show current worktree indicator

## Phase 3: Advanced Features (Low Priority)

### 3.1 `hug wtcp` - Copy Worktree

**Priority**: 🟢 Low
**Pattern**: Parallel to `hug bcp` (branch copy)

**Use Cases:**
```bash
# Copy worktree for experimental work
hug wtcp ~/feature-auth feature-auth-experiment

# Create backup copy of worktree
hug wtcp ~/feature-auth feature-auth-backup

# Copy to custom location
hug wtcp feature-auth ~/experiments/feature-refactor
```

**Implementation Considerations:**
- Git doesn't natively support copying worktrees
- Would involve creating new worktree + copying uncommitted changes
- Complex but potentially very useful for experimentation workflows

### 3.2 `hug wtcr` - Remote Branch Worktree

**Priority**: 🟢 Low
**Pattern**: Parallel to `hug brr` (remote branch)

**Use Cases:**
```bash
# Create worktree from remote branch selected via interactive remote branch browser menu
hug wtcr

# Create worktree from remote branch
hug wtcr origin/feature-auth

# Create worktree and immediately switch to it
hug wtcr origin/hotfix-bug --switch
```

## Implementation Strategy

### Technical Requirements

**Library Extensions (hug-git-worktree):**
- `move_worktree()` - Core move functionality
- `prune_worktrees()` - Metadata cleanup
- `get_worktree_info()` - Detailed information gathering
- `find_worktree_by_branch()` - Fast branch lookup

**Safety & Validation:**
- Consistent error handling across all commands
- Dry-run support for all destructive operations
- Integration with existing confirmation patterns
- Status indicator preservation

**Testing Strategy:**
- Unit tests for each new command
- Integration tests for complex workflows
- Edge case testing (dirty worktrees, locked worktrees, etc.)
- Cross-platform compatibility testing

### User Experience Considerations

**Consistency:**
- Follow established wt* naming patterns
- Maintain consistent help text and usage patterns
- Use same status indicators and formatting as other commands
- Integration with existing color scheme and output formatting

**Discoverability:**
- Add commands to appropriate help sections
- Update command map and documentation
- Include examples in cheat sheet and workflows
- Cross-reference related commands in help text

**Performance:**
- Efficient worktree discovery and lookup
- Minimal filesystem operations for non-destructive commands
- Optimized JSON output for automation
- Fast startup for interactive commands

## Timeline & Dependencies

**Phase 1 (Q1 2025): Core Missing Parallels**
- `hug wtmv` - 1-2 weeks implementation
- `hug wtprune` - 1 week implementation
- Documentation and testing - 1 week

**Phase 2 (Q2 2025): Enhanced Information**
- `hug wtsh` - 1-2 weeks implementation
- `hug wtfind` - 1 week implementation
- Integration testing and documentation

**Phase 3 (Q3 2025): Advanced Features**
- `hug wtcp` - 2-3 weeks (complex implementation)
- `hug wtcr` - 1-2 weeks implementation
- Advanced workflow documentation

### Dependencies

**Git Version Requirements:**
- `git worktree move` requires Git 2.30+ (for wtmv)
- Enhanced worktree features may require newer Git versions
- Fallback strategies for older Git versions

**Library Dependencies:**
- May need additional helper functions in hug-git-worktree
- Integration with existing error handling patterns
- Consistent use of existing JSON output utilities

## Success Metrics

**Usage Metrics:**
- Adoption of new commands in user workflows
- Reduction in manual worktree management tasks
- Integration with automation scripts and CI/CD pipelines

**Quality Metrics:**
- Test coverage >90% for all new commands
- Consistent error handling and user feedback
- Performance benchmarks against manual worktree operations

**User Experience:**
- Reduced context switching overhead for parallel development
- Improved discoverability of worktree-related operations
- Enhanced productivity for multi-branch development workflows

---

**Next Steps:**
1. Begin Phase 1 implementation with `hug wtmv`
2. Gather user feedback on current wt* command usage
3. Prioritize Phase 2 features based on user needs
4. Evaluate Git version requirements and compatibility strategy
