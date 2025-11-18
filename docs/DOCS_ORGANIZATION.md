# Command Documentation Organization Guide

This guide explains how to best organize and structure command documentation in `docs/*` for Hug SCM, with recommendations based on the current architecture.

## Current Organization

### Directory Structure

```
docs/
├── commands/                    # Command reference (organized by prefix/category)
│   ├── utilities.md            # clone, init
│   ├── head.md                 # h* (HEAD operations)
│   ├── working-dir.md          # w* (working directory & WIP)
│   ├── status-staging.md       # s*, a* (status & staging)
│   ├── branching.md            # b* (branching)
│   ├── commits.md              # c* (commits)
│   ├── logging.md              # l* (logging)
│   ├── file-inspection.md      # f* (file inspection)
│   ├── tagging.md              # t* (tagging)
│   ├── rebase.md               # r* (rebase)
│   ├── merge.md                # m* (merge)
│   └── img/                    # Screenshots and images (VHS-generated)
│       ├── README.md           # Image generation notes
│       ├── PLACEHOLDER_NOTE.md # Placeholder documentation
│       └── *.png, *.gif        # Generated screenshots
│
├── screencasts/                # VHS tape files for screenshot generation
│   ├── bin/                    # VHS build and maintenance scripts
│   │   ├── vhs-build.sh        # Main build orchestrator
│   │   ├── vhs-clean.sh        # Cleanup generated files
│   │   ├── vhs-strip-metadata.sh # Post-processing
│   │   ├── repo-setup.sh       # Demo repo creation
│   │   └── vhs-commit-push.sh  # Automated commit workflow
│   ├── hug-for-beginners/      # Beginner guide tapes
│   │   └── README.md           # Category documentation
│   ├── practical-workflows/    # Workflow demo tapes
│   │   └── README.md           # Category documentation
│   ├── *.tape                  # Individual command tape files
│   ├── template.tape           # Template for new tapes
│   ├── README.md               # VHS system documentation
│   └── VHS_TROUBLESHOOTING.md  # Common issues and solutions
│
├── mcp-server/                 # MCP server documentation
│   ├── index.md                # Overview and features
│   ├── quickstart.md           # Installation and setup
│   ├── usage.md                # Using MCP tools
│   ├── architecture.md         # Design and implementation
│   └── examples.md             # Example use cases
│
├── meta/                       # Developer tooling documentation
│   └── hug-completion-reference.md  # Shell completion details
│
├── architecture/               # ADRs and design decisions
│   ├── ADR-001-automated-testing-strategy.md
│   └── ADR-002-mercurial-support-architecture.md
│
├── getting-started.md          # Consolidated beginner guide (NEW)
├── workflows.md                # Consolidated workflows guide (NEW)
├── hug-for-beginners.md        # 📚 Legacy: Original beginner tutorial
├── core-concepts.md            # 📚 Legacy: Core concepts explained
├── practical-workflows.md      # 📚 Legacy: Workflow patterns
├── cookbook.md                 # 📚 Legacy: Solutions to common problems
│
├── command-map.md              # High-level overview (authoritative)
├── cheat-sheet.md              # Command syntax reference
├── installation.md             # Setup instructions
├── index.md                    # Landing page
│
├── json-output-support.md      # JSON output implementation roadmap
├── VHS_IMPROVEMENTS.md         # VHS enhancement suggestions
├── VHS_CI_INTEGRATION.md       # CI/CD integration for VHS
└── DOCS_ORGANIZATION.md        # This file
```

### Navigation Hierarchy

In `.vitepress/config.mjs`:

```
Sidebar Structure:
├── Guides (collapsed: false)
│   ├── Installation
│   ├── Getting Started (NEW - consolidated)
│   ├── Workflows (NEW - consolidated)
│   ├── 📚 Legacy: Beginner's Guide (hug-for-beginners)
│   ├── 📚 Legacy: Core Concepts
│   ├── 📚 Legacy: Practical Workflows
│   └── 📚 Legacy: Cookbook
│
├── Command Reference (collapsed: false)
│   ├── Command Map (authoritative source)
│   ├── Cheat Sheet
│   └── Core Commands (collapsible, collapsed: true)
│       ├── Utilities (clone, etc.)
│       ├── HEAD Operations (h*)
│       ├── Working Directory & WIP (w*)
│       ├── Status & Staging (s*, a*)
│       ├── Branching (b*)
│       ├── Commits (c*)
│       ├── Logging (l*)
│       ├── File Inspection (f*)
│       ├── Tagging (t*)
│       ├── Rebase (r*)
│       └── Merge (m*)
│
└── MCP Server (collapsible, collapsed: true)
    ├── Overview
    ├── Quick Start
    ├── Usage
    ├── Architecture
    └── Examples
```

**Navigation Flow**:
- New users: Installation → Getting Started → Workflows → Command Map
- Experienced users: Cheat Sheet → Core Commands (as needed)
- AI Integration: MCP Server section
- Legacy content: Preserved but marked, maintains link compatibility

## Best Practices for Command Documentation

### 1. File Naming

**Rule**: Use semantic, lowercase filenames with hyphens.

```
✅ Good:
- head.md (matches h* prefix)
- working-dir.md (clear what w* covers)
- status-staging.md (combines s* and a* as a unit)

❌ Avoid:
- h-operations.md (redundant with content)
- commands-reference.md (too generic)
```

**Why**: Clear filenames make it easy to find docs, especially with fuzzy search.

### 2. File Organization (One File Per Category)

**Rule**: Group commands by semantic prefix, not by feature or complexity level.

```
✅ Good organization:
- docs/commands/head.md contains ALL h* commands (back, undo, rewind, squash, etc.)
- docs/commands/branching.md contains ALL b* commands (b, bc, bl, bpull, etc.)

❌ Poor organization:
- docs/commands/safe-operations.md (mixes h* and w*)
- docs/commands/destructive.md (mixes w* and h*)
- docs/commands/head-basic.md + docs/commands/head-advanced.md (splits one prefix)
```

**Why**:
- Users learn commands by prefix (memory hook system)
- Each file is a complete reference for one semantic category
- Easier to maintain: all related commands in one place

### 3. Document Structure Within Each File

Every command documentation file should follow this structure:

```markdown
# Category Name (prefix description)

## Introduction
Brief explanation of what this category does and why users might use it.
Cross-reference to related categories with links.

::: info Mnemonic Legend
- **Bold letters** highlight key initials for command mnemonics
- Safety icons: ✅ safe · ⚠️ caution · 🔄 confirmation required
:::

## On This Page
- [Quick Reference](#quick-reference)
- [Commands](#commands)
- [Scenarios](#scenarios)
- [Tips](#tips)

> [!TIP] Cross-references
> Link to related command families

## Quick Reference

| Command | Memory Hook | Summary |
|---------|-------------|---------|
| Command syntax | **M**emonic breakdown | One-line description |

## Commands

### Command Name

- **Description**: What it does and when to use it
- **Example**:
  ```shell
  hug command example1
  hug command example2
  ```
- **Safety**: ✅ safe / ⚠️ destructive / 🔄 confirmation required
- Optional: Visual screenshot or detailed explanation

## Scenarios

Real-world use cases that combine multiple commands from this category.

## Tips

Helpful tricks and best practices specific to this command family.
```

### 4. Content Quality Standards

#### Quick Reference Table

Always include at the top:

```markdown
| Command | Memory Hook | Summary |
|---------|-------------|---------|
| `hug h back [N] [-u]` | **H**EAD **Back** | Move HEAD back, keep changes staged |
```

**Columns**:
- **Command**: Exact syntax (monospace)
- **Memory Hook**: How to remember the command (bold the key letters)
- **Summary**: One-line description of what it does

#### Command Details

For each command include:

```markdown
### `hug h back [N|commit] [-u] [--force]`
- **Description**: Clear explanation, including when to use it
- **Example**:
  ```shell
  hug h back          # One-line description
  hug h back 3        # With arguments
  hug h back -u       # With flags
  ```
- **Safety**: ✅/⚠️/🔄 with explanation of any confirmations or destructiveness
```

**Requirements**:
- Include real, practical examples (not hypothetical)
- Show command with args and flags
- Be specific about what the command does
- Explain any safety mechanisms or confirmations
- Link to related commands

#### Memory Hooks (Mnemonics)

Use bold letters to break down command names:

```
✅ Good:
- `hug h back` → **H**EAD **Back** (easy to remember)
- `hug sl` → **S**tatus + **L**ist
- `hug bcp` → **B**ranch **CP** (copy)

❌ Poor:
- hug sb → doesn't break down clearly
- hug x → too cryptic
```

#### Safety Indicators

Use consistent icons at the start of descriptions:

- ✅ **Safe/Read-only** - No data modification possible
- ⚠️ **Destructive** - Modifies files or history
- 🔄 **Confirmation required** - Prompts before destructive action
- 🟡 **Conditional** - May be safe or destructive depending on state

```markdown
- **Safety**: ✅ Read-only; previews changes without modifying repo
- **Safety**: 🔄 Confirmation required; shows preview before discarding changes
- **Safety**: ⚠️ Destructive; use `--dry-run` first to preview
```

### 5. Cross-Linking

Link to related commands and concepts:

```markdown
> [!TIP] Related Commands
> See [HEAD Operations](head) for other ways to move HEAD
> See [Working Directory cleanup](working-dir) for discarding changes

::: warning See Also
- [Status overview](status-staging) for checking what you're discarding
- [Branching guide](branching) for branch-specific operations
:::
```

### 6. Visual Examples

Use screenshots from VHS screencasts:

```markdown
### Visual Example

![hug h back in action](img/hug-h-back.png)

The screenshot shows:
1. Initial state with 3 commits
2. Running `hug h back`
3. Final state with HEAD moved back
```

**Image location**: `docs/commands/img/`
**Generated by**: VHS tool (see `docs/screencasts/`)
**When to use**:
- For complex commands with multiple steps
- To show interactive selection
- To demonstrate terminal UI elements

### 7. Scenarios Section

Include real-world use cases:

```markdown
## Scenarios

### Undo Last Commit for Editing
You committed but need to adjust the changes:
```shell
hug h back           # Move HEAD back, changes stay staged
hug su file.js       # View what changed
# Edit file.js
hug c -m "Fixed message"  # Commit again
```

### Move Multiple Commits to Another Branch
You're on main but your last 3 commits should be on a feature branch:
```shell
hug h back 3         # Move HEAD back on main
hug bc feature       # Create and switch to feature
hug h forward 3      # Move forward 3 (restore commits)
```
```

**Format**:
- Title describing the scenario
- Context (why someone would do this)
- Commands to solve it
- Explanation of what happens

### 8. Mercurial Notes

When a command has different behavior in Mercurial, note it:

```markdown
::: info Mercurial Compatibility
Mercurial bookmarks work like Git branches; use `hug b` the same way.
Note: Mercurial has no staging area, so `hug a` commits directly.
:::
```

Add to separate section if major differences exist.

## Documentation Maintenance

### Updating Command Docs

When adding or modifying a command:

1. **Update the relevant file** in `docs/commands/`
2. **Update Quick Reference** table at top of file
3. **Add/modify command section** with all details
4. **Add scenario** showing real-world usage
5. **Add screenshot** if UI-relevant (generate with VHS)
6. **Add cross-references** to related commands
7. **Update command-map.md** if it's a new command
8. **Update cheat-sheet.md** if command syntax changed

### Keeping Command Docs in Sync

**Rule**: Command docs should reflect README.md command reference.

```
README.md (quick commands reference)
     ↓
docs/command-map.md (high-level overview)
     ↓
docs/commands/*.md (detailed reference)
```

**When README changes**: Update all three locations.

### Documentation Build

```bash
# Development server
make docs-dev         # http://localhost:5173/hug-scm/

# Production build
make docs-build

# Preview production
make docs-preview
```

## File Template

Here's a template for a new command category file:

```markdown
# Category Name (prefix*)

Brief introduction about what this command category does and its purpose.
Explain the mental model behind the prefix (e.g., "h* for HEAD operations").

These commands [main purpose], providing [what value].

::: info Mnemonic Legend
- **Bold letters** in command names show the initials that build the command name
- Safety icons: ✅ safe/preview-only · ⚠️ requires caution · 🔄 confirms before running
:::

## On This Page
- [Quick Reference](#quick-reference)
- [Commands](#commands)
- [Scenarios](#scenarios)
- [Tips](#tips)

> [!TIP] Related Commands
> See [Other Category](other-category) for [description].

## Quick Reference

| Command | Memory Hook | Summary |
|---------|-------------|---------|
| `hug prefix cmd` | **P**refix **Cmd** | What it does |

## Commands

### `hug prefix cmd [args] [options]`

- **Description**: Clear description of what this command does and when you'd use it
- **Example**:
  ```shell
  hug prefix cmd              # Basic usage
  hug prefix cmd arg1         # With argument
  hug prefix cmd --flag       # With flag
  ```
- **Safety**: ✅ Safe explanation or ⚠️/🔄 explanation
- **Options**: Description of key flags if not obvious

Additional details, warnings, or notes as needed.

## Scenarios

### Real-world Use Case Title

Context and explanation...

```shell
# Commands to solve the problem
hug prefix cmd
hug other cmd
```

Explanation of what happened and why.

## Tips

- **Tip 1**: Useful trick
- **Tip 2**: Common pattern
```

## Documentation Types and Their Purposes

### 1. User-Facing Command Documentation

#### command-map.md

**Purpose**: Authoritative source of truth for all commands
**Update when**:
- Adding a new command family (prefix)
- Changing the mental model/organization
- Adding or removing commands

**Content**:
- Table overview of all families
- Tree view of all commands
- One-sentence summaries per command

#### cheat-sheet.md

**Purpose**: Quick syntax reference for experienced users
**Update when**:
- Adding a new command
- Changing command syntax or options

**Content**:
- All commands organized by prefix
- Syntax only (no explanations)
- Scenario-based quick lookups

#### README.md

**Purpose**: Main project entry point
**Update when**:
- Adding a new command category
- Changing core command behavior
- Adding new examples or value propositions

**Content**:
- Quick start guide
- Four-tier value proposition
- Command reference summary
- Installation instructions

### 2. VHS Screenshot Documentation

#### docs/screencasts/README.md

**Purpose**: Guide for creating and maintaining VHS tape files
**Update when**:
- Adding new tape file patterns
- Changing build process
- Adding new VHS features

**Content**:
- Tape file creation guide
- Build process documentation
- Best practices for screencasts
- Troubleshooting common issues

#### VHS_CI_INTEGRATION.md

**Purpose**: CI/CD integration strategies
**Update when**:
- Changing CI workflow
- Adding new automation
- Updating VHS version

**Content**:
- Three integration approaches (full CI, pre-commit, hybrid)
- GitHub Actions workflows
- Troubleshooting CI issues

#### VHS_IMPROVEMENTS.md

**Purpose**: Enhancement tracking and suggestions
**Update when**:
- Implementing suggested improvements
- Adding new enhancement ideas
- Marking features as complete

**Content**:
- Implemented features (✅)
- Suggested improvements (🚀)
- Priority recommendations

### 3. MCP Server Documentation

#### docs/mcp-server/index.md

**Purpose**: Overview and introduction
**Update when**:
- Adding new MCP tools
- Changing server features
- Major architectural changes

**Content**:
- Feature overview
- Available tools list
- Use cases

#### docs/mcp-server/quickstart.md

**Purpose**: Installation and setup guide
**Update when**:
- Installation process changes
- New configuration options
- Claude Desktop integration updates

**Content**:
- Installation steps
- Configuration examples
- First-time setup

#### docs/mcp-server/architecture.md

**Purpose**: Technical design documentation
**Update when**:
- Architectural changes
- New design patterns
- Tool implementation changes

**Content**:
- System architecture
- Module structure
- Design decisions

### 4. Planning and Roadmap Documentation

#### json-output-support.md

**Purpose**: Implementation planning and tracking
**Type**: Living document (updated as implemented)

**Update when**:
- Implementing JSON support in commands
- Changing JSON output format
- Adding new use cases

**Content**:
- Current state (commands with JSON)
- Prioritized recommendations
- Implementation patterns
- Roadmap phases

**Note**: This is a planning document that will evolve. As features are implemented, mark them complete and update the status sections.

### 5. Meta Documentation

#### docs/meta/hug-completion-reference.md

**Purpose**: Shell completion technical documentation
**Update when**:
- Adding new completion patterns
- Changing completion behavior
- Supporting new shells

**Content**:
- Completion mechanism details
- Implementation patterns
- Shell-specific notes

#### DOCS_ORGANIZATION.md (this file)

**Purpose**: Documentation organization guide
**Update when**:
- Adding new documentation types
- Changing organization patterns
- New best practices emerge

**Content**:
- Structure guidelines
- Best practices
- Maintenance procedures

## VitePress Configuration

The sidebar is configured in `docs/.vitepress/config.mjs`:

```javascript
{
  text: 'Core Commands',
  collapsible: true,
  collapsed: true,
  items: [
    { text: 'Command Category', link: '/commands/filename' },
    // ...
  ]
}
```

**To add a new command category**:

1. Create `docs/commands/new-category.md`
2. Add entry to `config.mjs` in the Core Commands section
3. Follow the file template above
4. Build and test: `make docs-dev`

## Style & Tone

### Voice

- **Direct and practical**: "Stage your changes" not "You might want to consider staging"
- **Action-oriented**: Start with verbs when possible
- **Clear about consequences**: "This discards your changes permanently"
- **Helpful warnings**: "First, check your status with `hug s`"

### Formatting

```markdown
✅ Use:
- Backticks for command syntax: `hug command`
- **Bold** for emphasis on key concepts
- > Blockquotes for tips and warnings
- Code blocks with language syntax highlighting
- Markdown callouts for special notes

❌ Avoid:
- ALL CAPS except for variable names
- Excessive punctuation!!!
- Deep nesting (max 3 levels)
- Walls of text (break into paragraphs)
```

### Callout Types

VitePress supports special callout syntax:

```markdown
> [!NOTE] Title (default blue)
> Information note

> [!TIP] Title (green)
> Helpful tip

> [!WARNING] Title (orange)
> Warning/caution

> [!IMPORTANT] Title (red)
> Important information

> [!DANGER] Title (red, emphasized)
> Dangerous operation
```

## VHS Screenshot Best Practices

### Creating Tape Files

**Location**: `docs/screencasts/*.tape`

**Naming Convention**: `hug-<command>.tape` or `hug-<category>-demo.tape`

**Template Structure**:
```tape
# VHS tape file for hug <command>
# Brief description of what this demonstrates

Output ../commands/img/hug-<command>.gif  # or .png

Require echo
Require hug

Set Shell "fish"          # Or bash, zsh
Set FontSize 13
Set Width 1020
Set Height 600           # Adjust as needed
Set Margin 0
Set Padding 10
Set Theme "Afterglow"

# Setup (hidden from output)
Hide
Type "cd /tmp/demo-repo" Enter
Sleep 500ms
Type "clear" Enter
Sleep 200ms
Show

# Demonstrate command
Set TypingSpeed 40ms
Type "hug command  # Brief inline explanation" Enter
Sleep 2s

# Cleanup (hidden)
Hide
Type "hug w zap-all -f" Enter
Sleep 300ms
```

**Best Practices**:
- Use `/tmp/demo-repo` for consistency
- Hide setup and cleanup commands
- Add inline comments to explain what's being shown
- Use realistic examples (not "foo.txt" or "test.md")
- Keep screenshots focused (one concept per tape)
- Set appropriate height to avoid empty space
- Use Sleep to give readers time to read output

### Regenerating Screenshots

**When to regenerate**:
- Command output format changes
- Adding new visual examples
- Fixing incorrect demonstrations
- Before major releases

**How to regenerate**:
```bash
# Setup demo repository
make demo-repo

# Regenerate all screenshots
make vhs

# Regenerate specific screenshot
make vhs-build-one TAPE=hug-sl-states.tape

# Check output
ls -la docs/commands/img/
```

**Committing screenshots**:
- Always commit generated images (not gitignored)
- Screenshots are committed to ensure CI builds work without VHS
- Monthly scheduled regeneration keeps them fresh
- Manual regeneration before releases

### Screenshot Organization

**File naming**: Match tape file name
- `hug-sl-states.tape` → `hug-sl-*.png` (4 states: clean, staged, unstaged, mixed)
- `hug-branch-demo.tape` → `hug-branch-demo.gif`

**Documentation references**:
```markdown
![Hug status list showing clean state](img/hug-sl-clean.png)
*Figure: Output of `hug sl` with a clean working directory*
```

## Documentation Consolidation Best Practices

### When to Consolidate

**Consolidate when**:
- Multiple files cover overlapping topics
- Content is duplicated across files
- Users are confused about which file to read
- Maintenance burden is high (updating same info in 3+ places)

**Example**: Recent consolidation (commit 0e9c998):
- `hug-for-beginners.md` + `core-concepts.md` → `getting-started.md`
- `practical-workflows.md` + `cookbook.md` + skills content → `workflows.md`

### How to Consolidate

**Process**:
1. **Identify overlap**: Map out which topics appear in multiple files
2. **Choose primary file**: Pick the most logical destination
3. **Merge best content**: Take the best explanation from each source
4. **Add navigation**: Include table of contents for long guides
5. **Preserve legacy**: Keep old files, mark as "📚 Legacy" in sidebar
6. **Update links**: Ensure VitePress config reflects new structure
7. **Test builds**: Verify `make docs-build` succeeds

**Preservation strategy**:
```javascript
// In .vitepress/config.mjs
{
  text: '📚 Legacy: Beginner\'s Guide',
  link: '/hug-for-beginners'
}
```

**Why preserve legacy files**:
- Maintains backward compatibility for external links
- Gives users time to discover new structure
- Prevents 404s from search engines or bookmarks

### Marking Legacy Content

**In sidebar**: Use 📚 emoji prefix
**In file**: Add note at top:
```markdown
::: warning Consolidated Documentation
This content has been merged into [Getting Started](getting-started.md).
This page is preserved for backward compatibility.
:::
```

## Planning Document Best Practices

### Purpose of Planning Documents

Planning documents (like `json-output-support.md`) serve as:
- **Living roadmaps**: Track implementation progress
- **Decision records**: Document why approaches were chosen
- **Reference guides**: Show examples and patterns for future work
- **Status tracking**: Mark what's completed vs planned

### Structure for Planning Documents

```markdown
# Feature Planning Document

**Status**: Planning / In Progress / Partially Implemented
**Date**: YYYY-MM-DD
**Purpose**: Brief purpose statement

## Table of Contents
[Standard TOC]

## Executive Summary
- Current state
- Opportunity
- Key findings

## Current State
What exists today (with version/date info)

## Prioritized Recommendations
Tier 1 (HIGH), Tier 2 (MEDIUM), etc.
Each with:
- Priority rating (⭐⭐⭐⭐⭐)
- Implementation complexity (🟢 LOW, 🟡 MEDIUM, 🔴 HIGH)
- Use cases
- Impact analysis

## Implementation Patterns
Code examples, best practices, templates

## Roadmap
Phased approach with milestones

## Status Tracking
- ✅ Completed
- 🔄 In Progress
- ⏭️ Planned
```

### Maintaining Planning Documents

**Update when**:
- Features are implemented (mark ✅)
- Priorities change (re-tier items)
- New use cases emerge (add examples)
- Implementation patterns are validated (update or add)

**Example update**:
```markdown
### Phase 1: Core Workflow Commands
**Status**: ✅ COMPLETED (2025-11-20)

1. **`hug sl` / `hug sla`** ✅
   - Implemented: 2025-11-18
   - Commit: abc123f
   - [Documentation](commands/status-staging.md#json-output)
```

## Review Checklist

### Command Documentation

Before committing command documentation:

- [ ] File name is semantic and lowercase with hyphens
- [ ] Quick Reference table is at the top
- [ ] Every command has: description, examples, safety info
- [ ] Examples are realistic and practical
- [ ] Memory hooks are clear (bold key letters)
- [ ] Safety indicators (✅/⚠️/🔄) are accurate
- [ ] Cross-references link to related commands
- [ ] Scenarios show real-world usage
- [ ] Screenshots are added if UI-relevant (via VHS tape files)
- [ ] Documentation builds without errors: `make docs-build`
- [ ] Links work: `make docs-dev` and test navigation
- [ ] Related files updated (command-map, cheat-sheet, README if needed)
- [ ] Mercurial notes added if behavior differs

### VHS Screenshot Documentation

Before committing VHS changes:

- [ ] Tape file follows naming convention (`hug-<command>.tape`)
- [ ] Demo repository is used (`/tmp/demo-repo`)
- [ ] Setup and cleanup are hidden (Hide/Show commands)
- [ ] Output path is correct (`../commands/img/`)
- [ ] Screenshot demonstrates realistic use case
- [ ] Inline comments explain what's shown
- [ ] Generated images are committed
- [ ] Command documentation references new screenshots
- [ ] `make vhs-build` succeeds without errors

### Consolidated Documentation

When consolidating documentation:

- [ ] Mapped overlapping content across files
- [ ] Chose logical destination for merged content
- [ ] Took best explanations from each source
- [ ] Added table of contents to long guides
- [ ] Preserved legacy files (not deleted)
- [ ] Marked legacy files with 📚 in sidebar
- [ ] Updated VitePress config navigation
- [ ] Added migration notice to legacy files
- [ ] Tested all internal links still work
- [ ] Verified `make docs-build` succeeds
- [ ] Checked navigation flow makes sense

### Planning Document Updates

When updating planning documents:

- [ ] Updated status (Planning/In Progress/Completed)
- [ ] Marked completed items with ✅
- [ ] Added commit references for implemented features
- [ ] Updated priorities if changed
- [ ] Added new use cases discovered
- [ ] Validated implementation patterns
- [ ] Updated roadmap phases
- [ ] Checked examples are still accurate

## Examples from Current Docs

### Well-Structured (Use as Reference)

- **status-staging.md**: Excellent quick reference table, clear scenarios, good visual examples
- **head.md**: Detailed command descriptions, good cross-references, safety levels clearly marked
- **branching.md**: Clear explanation of how auto-detection works, practical examples with expected outcomes

### Opportunities for Improvement

When expanding existing files:
- Add more scenario examples (real-world use cases)
- Include screenshots for interactive commands
- Expand Mercurial compatibility notes where applicable
- Add "Tips" sections with command combinations

## Documentation Evolution and Recent Changes

### Major Consolidation (November 2025)

**Commit**: 0e9c998 - "docs: consolidate and enhance documentation structure"

**Problem**: Documentation was fragmented across 9 overlapping files, creating maintenance burden and user confusion.

**Solution**: Consolidated into focused guides:

1. **getting-started.md** (NEW)
   - Merged: `hug-for-beginners.md` + `core-concepts.md`
   - Purpose: Single beginner-to-comfortable progression
   - Length: ~450 lines
   - Audience: New users learning Hug

2. **workflows.md** (NEW)
   - Merged: `practical-workflows.md` + `cookbook.md` + skills insights
   - Purpose: Comfortable-to-expert patterns
   - Length: ~650 lines
   - Audience: Users who know basics, want mastery

**Legacy files preserved**: All original files kept with "📚 Legacy" markers in sidebar to maintain link compatibility.

**Impact**:
- Reduced primary user-facing files: 9 → 7
- Clear learning progression: getting-started → workflows → command-map
- Better discoverability of advanced features
- Less maintenance (single source for concepts)

### VHS Screenshot System (October-November 2025)

**Added infrastructure**:
- `docs/screencasts/` directory with tape files
- `docs/screencasts/bin/` build scripts
- VHS_IMPROVEMENTS.md and VHS_CI_INTEGRATION.md guides
- Automated screenshot generation via `make vhs`

**Impact**:
- Visual examples for all major commands
- Consistent screenshot style and quality
- Reproducible documentation builds
- CI/CD integration (hybrid approach)

### MCP Server Documentation (November 2025)

**Added section**: `docs/mcp-server/`
- Dedicated documentation for AI assistant integration
- Installation, architecture, usage, examples
- Separate from main user docs (different audience)

**Impact**:
- Claude Desktop users can integrate Hug tools
- Clear separation of concerns (user docs vs integration docs)
- Enables AI-assisted repository exploration

### JSON Output Planning (November 2025)

**Added**: `json-output-support.md`
- Comprehensive planning document (1757 lines)
- Tracks implementation status
- Documents patterns and use cases
- Living roadmap for JSON output rollout

**Type**: Planning document (not user-facing guide)
**Status**: In progress (7 commands with JSON, 15+ planned)

## Maintenance Guidelines

### When Documentation Structure Changes

**After major changes**:
1. Update DOCS_ORGANIZATION.md (this file)
2. Update VitePress config sidebar
3. Test builds: `make docs-build`
4. Test navigation: `make docs-dev` and click through links
5. Verify search still works (pagefind)

### Regular Maintenance Tasks

**Weekly**:
- Review open issues for documentation bugs
- Check for broken links (VitePress build warnings)

**Monthly**:
- Regenerate VHS screenshots: `make vhs`
- Review planning documents (update completed items)
- Check for outdated examples

**Before releases**:
- Update README.md with new features
- Regenerate all screenshots
- Verify command-map.md is current
- Update installation.md if setup changed
- Review and update planning documents

### Adding New Documentation Types

When adding a new type of documentation:

1. **Choose appropriate location**:
   - User guides → `docs/*.md`
   - Command reference → `docs/commands/*.md`
   - Architecture → `docs/architecture/ADR-*.md`
   - Planning/roadmap → `docs/*-support.md` or `docs/*-roadmap.md`
   - Integration docs → `docs/<integration>/`
   - Meta/tooling → `docs/meta/`

2. **Update this guide**:
   - Add to directory structure
   - Add to "Documentation Types" section
   - Add to appropriate checklist
   - Add maintenance notes

3. **Update VitePress**:
   - Add to sidebar in config.mjs
   - Test navigation

4. **Document the pattern**:
   - Add examples to "Well-Structured" section
   - Update templates if needed

## Summary

**Best practices in brief**:

### Command Documentation
1. **One file per semantic prefix** (h*, w*, s*, b*, etc.)
2. **Quick reference table** at the top
3. **Detailed command sections** with examples and safety info
4. **Memory hooks** to help users remember commands
5. **Cross-links** to related commands and concepts
6. **Real-world scenarios** showing how commands work together
7. **Visual examples** (VHS screenshots) where UI or complex behavior is involved
8. **Clear safety indicators** showing consequences of each command
9. **Keep in sync** with command implementation and README.md
10. **Test builds** before committing: `make docs-build`

### VHS Screenshot Documentation
1. Use `/tmp/demo-repo` for consistency
2. Hide setup and cleanup commands
3. Realistic examples (not "foo.txt")
4. Commit generated images
5. Reference via `![description](img/filename.png)`

### Consolidation and Evolution
1. Consolidate when duplication is high
2. Preserve legacy files (backward compatibility)
3. Mark legacy content clearly (📚 emoji)
4. Update VitePress sidebar
5. Test all navigation flows

### Planning Documents
1. Living documents (update as implemented)
2. Track status explicitly (✅/🔄/⏭️)
3. Include implementation patterns
4. Reference commits when features land
5. Keep executive summary current

This structure makes Hug's extensive command set and growing feature ecosystem feel organized and discoverable rather than overwhelming.
