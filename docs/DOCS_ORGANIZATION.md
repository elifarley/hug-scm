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
│
├── command-map.md              # High-level overview (quick reference)
├── cheat-sheet.md              # Command syntax reference
├── core-concepts.md            # Conceptual foundation
├── hug-for-beginners.md        # Tutorial for new users
├── practical-workflows.md      # Real-world usage patterns
├── cookbook.md                 # Solutions to common problems
├── installation.md             # Setup instructions
├── architecture/               # ADRs and design decisions
└── index.md                    # Landing page
```

### Navigation Hierarchy

In `.vitepress/config.mjs`:

```
Sidebar Structure:
├── Guides
│   ├── Installation
│   ├── Core Concepts
│   ├── Hug for Beginners
│   ├── Practical Workflows
│   └── Cookbook
└── Command Reference
    ├── Command Map
    ├── Cheat Sheet
    └── Core Commands (collapsible)
        ├── Utilities
        ├── HEAD Operations (h*)
        ├── Working Directory (w*)
        ├── Status & Staging (s*, a*)
        ├── Branching (b*)
        ├── Commits (c*)
        ├── Logging (l*)
        ├── File Inspection (f*)
        ├── Tagging (t*)
        ├── Rebase (r*)
        └── Merge (m*)
```

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

## Related Files

### command-map.md

High-level overview showing all command families.

**Update when**:
- Adding a new command family (prefix)
- Changing the mental model/organization

**Content**:
- Table overview of all families
- Tree view of all commands
- One-sentence summaries per command

### cheat-sheet.md

Syntax reference without detailed explanations.

**Update when**:
- Adding a new command
- Changing command syntax or options

**Content**:
- All commands organized by prefix
- Syntax only
- No explanations (users know what they're looking for)

### README.md

Main project readme with quick start and command reference.

**Update when**:
- Adding a new command
- Changing core command behavior
- Adding new examples

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

## Review Checklist

Before committing command documentation:

- [ ] File name is semantic and lowercase with hyphens
- [ ] Quick Reference table is at the top
- [ ] Every command has: description, examples, safety info
- [ ] Examples are realistic and practical
- [ ] Memory hooks are clear (bold key letters)
- [ ] Safety indicators (✅/⚠️/🔄) are accurate
- [ ] Cross-references link to related commands
- [ ] Scenarios show real-world usage
- [ ] Screenshots are added if UI-relevant
- [ ] Documentation builds without errors: `make docs-build`
- [ ] Links work: `make docs-dev` and test navigation
- [ ] Related files updated (command-map, cheat-sheet, README if needed)
- [ ] Mercurial notes added if behavior differs

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

## Summary

**Best practices in brief**:

1. **One file per semantic prefix** (h*, w*, s*, b*, etc.)
2. **Quick reference table** at the top
3. **Detailed command sections** with examples and safety info
4. **Memory hooks** to help users remember commands
5. **Cross-links** to related commands and concepts
6. **Real-world scenarios** showing how commands work together
7. **Visual examples** where UI or complex behavior is involved
8. **Clear safety indicators** showing consequences of each command
9. **Keep in sync** with command implementation and README.md
10. **Test builds** before committing: `make docs-build`

This structure makes Hug's extensive command set feel organized and discoverable rather than overwhelming.
