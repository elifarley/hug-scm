# Documentation Organization Guide

This guide describes how documentation is organized in the Hug SCM project and where to place different types of documentation.

## Philosophy

- **Single Source of Truth**: Each topic should have ONE authoritative document
- **Clear Hierarchy**: User docs, developer docs, planning docs, and ADRs are separated
- **Discoverability**: Logical organization makes docs easy to find
- **Maintainability**: Avoid duplication; consolidate related content

## Directory Structure

```
hug-scm/
├── README.md                           # Project overview, quick start
├── TESTING.md                          # Testing guide for contributors
├── CONTRIBUTING.md                     # Contribution guidelines
├── CLAUDE.md                           # AI assistant instructions
│
├── docs/                               # VitePress documentation site
│   ├── index.md                        # Documentation homepage
│   ├── getting-started.md              # User guide: installation, first steps
│   ├── workflows.md                    # User guide: common workflows
│   ├── cheat-sheet.md                  # Quick reference: scenario-based
│   ├── command-map.md                  # Quick reference: all 139 commands
│   │
│   ├── architecture/                   # Architecture Decision Records (ADRs)
│   │   ├── ADR-001-automated-testing-strategy.md
│   │   └── ADR-002-mercurial-support-architecture.md
│   │
│   ├── commands/                       # Command reference documentation
│   │   ├── head.md                     # HEAD operations (h*)
│   │   ├── working-dir.md              # Working directory (w*)
│   │   ├── status-staging.md           # Status/staging (s*, a*, us*)
│   │   ├── branching.md                # Branching (b*)
│   │   ├── commits.md                  # Commits (c*)
│   │   ├── logging.md                  # Logging (l*)
│   │   ├── file-inspection.md          # File inspection (f*)
│   │   ├── tagging.md                  # Tagging (t*)
│   │   ├── rebase-merge.md             # Rebase/merge (r*, m*)
│   │   └── img/                        # Screenshots (VHS-generated)
│   │       ├── *.png                   # Static screenshots
│   │       └── *.gif                   # Animated demos
│   │
│   ├── meta/                           # Meta/tooling documentation
│   │   └── hug-completion-reference.md # Shell completion internals
│   │
│   ├── planning/                       # Planning & roadmap documents
│   │   └── json-output-roadmap.md      # Future: JSON output support
│   │
│   ├── screencasts/                    # VHS tape files & guide
│   │   ├── README.md                   # VHS guide (SINGLE SOURCE OF TRUTH)
│   │   ├── template.tape               # Template for new tape files
│   │   ├── bin/                        # VHS build scripts
│   │   └── *.tape                      # VHS tape files
│   │
│   └── DOCS_ORGANIZATION.md            # This file
│
├── git-config/lib/                     # Git implementation libraries
│   ├── README.md                       # Library documentation
│   └── python/                         # Python analysis helpers
│       ├── README.md                   # Python library docs
│       └── tests/                      # Python tests
│
├── hg-config/lib/                      # Mercurial implementation libraries
│   └── README.md                       # Mercurial library docs
│
└── tests/                              # Test suite
    └── README.md                       # Test suite documentation
```

## Documentation Categories

### 1. User-Facing Documentation (`docs/*.md`)

**Purpose**: Help end users learn and use Hug SCM

**Location**: `docs/` (root level)

**Examples**:
- `index.md` - Documentation homepage
- `getting-started.md` - Installation, activation, first commands
- `workflows.md` - Common workflows and use cases
- `cheat-sheet.md` - Scenario-based quick reference
- `command-map.md` - Complete command reference

**When to use**: User guides, tutorials, how-tos, overview content

### 2. Command Reference (`docs/commands/*.md`)

**Purpose**: Detailed reference for each command category

**Location**: `docs/commands/`

**Naming**: Based on command prefix or category

**Examples**:
- `head.md` - HEAD operations (h*)
- `working-dir.md` - Working directory (w*)
- `status-staging.md` - Status/staging (s*, a*, us*)
- `branching.md` - Branch commands (b*)

**Structure**:
- Overview of the category
- List of commands with descriptions
- Usage examples with screenshots
- Tips and best practices

**When to use**: Documenting specific commands and their usage

### 3. Architecture Decision Records (`docs/architecture/ADR-*.md`)

**Purpose**: Record important architectural decisions and rationale

**Location**: `docs/architecture/`

**Naming**: `ADR-NNN-descriptive-title.md` (sequential numbering)

**Examples**:
- `ADR-001-automated-testing-strategy.md`
- `ADR-002-mercurial-support-architecture.md`

**Structure**: Follow the ADR template:
- **Status**: Proposed, Accepted, Deprecated, Superseded
- **Context**: The problem and constraints
- **Decision**: The chosen solution
- **Consequences**: Positive and negative outcomes
- **Alternatives Considered**: Other options and why they were rejected

**When to use**: Major architectural decisions (framework choices, structural changes, design patterns)

### 4. Planning & Roadmap (`docs/planning/*.md`)

**Purpose**: Future features, roadmaps, and planning documents

**Location**: `docs/planning/`

**Examples**:
- `json-output-roadmap.md` - JSON output support roadmap

**When to use**: Planning docs, roadmaps, feature proposals (not yet implemented)

### 5. Meta/Tooling Documentation (`docs/meta/*.md`)

**Purpose**: Documentation about tooling, internals, or meta-documentation

**Location**: `docs/meta/`

**Examples**:
- `hug-completion-reference.md` - Shell completion implementation details

**When to use**: Documentation about the project's internal tools or processes

### 6. VHS Screencasts (`docs/screencasts/`)

**Purpose**: Visual documentation via terminal recordings

**Location**: `docs/screencasts/`

**Key Files**:
- `README.md` - **SINGLE SOURCE OF TRUTH** for VHS documentation
- `template.tape` - Template for new tape files
- `*.tape` - VHS tape files

**Important**: All VHS documentation is consolidated in `docs/screencasts/README.md`:
- Creating tape files
- Building screenshots
- CI/CD integration
- Future enhancements
- Troubleshooting

**When to use**: Creating visual documentation for commands

### 7. Library Documentation (`git-config/lib/README.md`)

**Purpose**: Developer documentation for Bash libraries

**Location**: `git-config/lib/README.md`

**Content**:
- Library overview
- Function documentation
- Usage patterns
- Command structure patterns
- Best practices

**When to use**: Documenting library functions, development patterns, code organization

### 8. Python Library Documentation (`git-config/lib/python/README.md`)

**Purpose**: Developer documentation for Python analysis helpers

**Location**: `git-config/lib/python/README.md`

**Content**:
- Module overview
- Design principles
- When to use Python vs Bash
- Testing strategy

**When to use**: Documenting Python analysis modules

### 9. Testing Documentation

**Two files**:
- `TESTING.md` (root) - **Comprehensive testing guide** for contributors
- `tests/README.md` - Test suite technical documentation

**TESTING.md** (root):
- Philosophy and goals
- Quick start
- Writing tests
- Running tests
- Best practices
- Troubleshooting

**tests/README.md**:
- Test directory structure
- Helper functions
- Coverage tracking
- Technical details

### 10. Root-Level Documentation

**Files**:
- `README.md` - Project overview, installation, quick start
- `CONTRIBUTING.md` - How to contribute (code, tests, docs)
- `TESTING.md` - Testing guide
- `CLAUDE.md` - Instructions for AI assistants

## Decision Tree: Where to Put Documentation

**Ask yourself:**

1. **Is it an architectural decision?**
   → `docs/architecture/ADR-NNN-*.md`

2. **Is it a planning/roadmap document?**
   → `docs/planning/*.md`

3. **Is it command reference?**
   → `docs/commands/*.md`

4. **Is it a user guide or tutorial?**
   → `docs/*.md`

5. **Is it about VHS screenshots?**
   → `docs/screencasts/README.md` (single source of truth)

6. **Is it about testing?**
   → `TESTING.md` or `tests/README.md`

7. **Is it library implementation?**
   → `git-config/lib/README.md` or `git-config/lib/python/README.md`

8. **Is it meta/tooling documentation?**
   → `docs/meta/*.md`

9. **Is it project overview or contributing?**
   → `README.md` or `CONTRIBUTING.md`

## What NOT to Create

**Do NOT create:**
- ❌ Implementation notes in root (`IMPLEMENTATION_*.md`)
- ❌ Temporary procedural docs (`SCREENSHOT_GENERATION.md`)
- ❌ Multiple docs for same topic (consolidate to single source)
- ❌ Duplicate VHS documentation (use `docs/screencasts/README.md`)
- ❌ Summary files that duplicate content from the main docs

**Instead:**
- ✅ Write ADRs for architectural decisions
- ✅ Add to planning docs for roadmaps
- ✅ Update existing docs rather than creating new ones
- ✅ Consolidate related docs into single source of truth

## Naming Conventions

### Files
- **Lowercase with hyphens**: `getting-started.md`, `json-output-roadmap.md`
- **Descriptive**: Name reflects content (`workflows.md`, not `guide.md`)
- **ADRs**: `ADR-NNN-descriptive-title.md` (sequential numbering)

### Headings
- **Title Case for Main Titles**: "Getting Started with Hug SCM"
- **Sentence case for subsections**: "Installing dependencies"

### Code Examples
- **Use triple backticks** with language identifier
- **Include comments** for clarity
- **Show both command and output** when helpful

## Updating Documentation

### When Adding New Content

1. **Check if similar documentation exists**
   - Read `docs/DOCS_ORGANIZATION.md` (this file)
   - Search existing docs: `grep -r "topic" docs/`
   - Consolidate into existing doc if appropriate

2. **Choose the right location**
   - Use the decision tree above
   - Follow naming conventions

3. **Update relevant indexes**
   - Add to `docs/DOCS_ORGANIZATION.md` if new category
   - Update VitePress sidebar in `docs/.vitepress/config.mjs` if user-facing

4. **Follow the project style**
   - Use existing docs as templates
   - Match the tone and structure
   - Include examples and screenshots where helpful

### When Consolidating Documentation

1. **Identify the single source of truth**
   - Choose the most comprehensive document
   - Or create a new consolidated document

2. **Merge content**
   - Preserve all valuable information
   - Remove redundancy
   - Update cross-references

3. **Delete redundant files**
   - Don't leave stale docs around
   - Update any links to deleted files

4. **Update this guide**
   - Reflect the new organization
   - Update the decision tree if needed

## VitePress Integration

User-facing documentation in `docs/` is published via VitePress.

### Sidebar Configuration

Edit `docs/.vitepress/config.mjs` to add docs to the sidebar:

```javascript
sidebar: {
  '/': [
    {
      text: 'Guide',
      items: [
        { text: 'Getting Started', link: '/getting-started' },
        { text: 'Workflows', link: '/workflows' }
      ]
    },
    {
      text: 'Commands',
      items: [
        { text: 'HEAD Operations', link: '/commands/head' },
        { text: 'Working Directory', link: '/commands/working-dir' }
      ]
    }
  ]
}
```

### Building Documentation

```bash
make docs-dev     # Development server (hot reload)
make docs-build   # Production build
make docs-preview # Preview production build
```

## Examples of Good Documentation Organization

### Example 1: Adding a New Command Category

**Task**: Document the new `analyze` command prefix

**Steps**:
1. Create `docs/commands/analyze.md` (command reference)
2. Add entry to VitePress sidebar
3. Update `command-map.md` to include new commands
4. Create VHS tape files in `docs/screencasts/` for visual examples

**Don't**: Create `ANALYZE_IMPLEMENTATION.md` in root

### Example 2: Planning a New Feature

**Task**: Plan multi-repository support

**Steps**:
1. Create `docs/planning/multi-repo-roadmap.md`
2. Include: problem statement, proposed solution, open questions
3. When decided, create `docs/architecture/ADR-003-multi-repo-support.md`
4. After implementation, update user docs (`workflows.md`, etc.)

**Don't**: Create temporary notes in root

### Example 3: Documenting VHS Improvements

**Task**: Document new VHS features

**Steps**:
1. Update `docs/screencasts/README.md` (single source of truth)
2. Add to appropriate section (CI/CD, Best Practices, Future Enhancements)
3. Update examples if needed

**Don't**: Create separate `VHS_IMPROVEMENTS.md` or `VHS_CI_INTEGRATION.md`

## Maintenance

This document should be updated when:
- New documentation categories are added
- File structure changes
- Documentation consolidation occurs
- New conventions are established

Keep this guide current so it remains a helpful resource for contributors.

## Questions?

If you're unsure where to put documentation:
1. Consult this guide
2. Look at similar existing documentation
3. Ask in GitHub Discussions or Issues
4. When in doubt, favor consolidation over proliferation
