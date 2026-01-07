# Hug SCM Agent Skills

This directory contains Agent Skills for AI assistants to effectively investigate and work with Git repositories using Hug SCM.

## What are Agent Skills?

Agent Skills are organized bundles of instructions, workflows, and domain expertise that equip AI assistants with specialized knowledge. Unlike simple tools that execute single actions, skills provide:

- **Procedural knowledge**: How to accomplish complex tasks
- **Domain expertise**: Best practices and patterns
- **Progressive disclosure**: Loading only relevant information when needed
- **Composable workflows**: Combining multiple tools effectively

Learn more: [Anthropic's Agent Skills Engineering Blog](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)

## Structure

```
skills/
├── SKILL.md                 # Core skill definition (ALWAYS READ THIS FIRST)
├── guides/                  # Detailed workflow guides (Level 2)
│   ├── bug-hunting.md       # Investigating when bugs were introduced
│   ├── pre-commit-review.md # Reviewing changes before committing
│   ├── branch-analysis.md   # Comparing and analyzing branches
│   └── history-cleanup.md   # Cleaning up commits for PR
└── README.md                # This file
```

## Using These Skills

### For AI Assistants

1. **Start with SKILL.md** - This provides core Hug SCM knowledge, command prefixes, and investigation patterns
2. **Reference guides as needed** - Each guide focuses on a specific workflow:
   - Bug investigation → `guides/bug-hunting.md`
   - Pre-commit review → `guides/pre-commit-review.md`
   - Branch comparison → `guides/branch-analysis.md`
   - History cleanup → `guides/history-cleanup.md`
3. **Apply the patterns** - Combine commands following the documented workflows

### For Developers

These skills are designed to work with:

- **Hug SCM CLI** - Direct command-line usage
- **Hug SCM MCP Server** - Tool-based access via Model Context Protocol
- **Code execution environments** - Advanced analysis with scripting

## Core Concepts

### Hug's Four-Tier Value Proposition

Hug delivers value at multiple levels beyond simple Git aliases:

1. **Humanization** - Intuitive names, better UX, semantic prefixes
2. **Workflow Automation** - Multi-step operations, interactive selection, safety nets
3. **Computational Analysis** - Statistical algorithms impossible with pure Git (co-changes, ownership, dependencies, activity patterns, churn analysis)
4. **Machine-Readable Export** - JSON output for automation and dashboards

### Hug's Safety-First Philosophy

All skills emphasize Hug's core principles:

1. **Brevity Hierarchy** - Shorter = safer (`hug a` vs `hug aa`)
2. **Progressive Destructiveness** - `discard < wipe < purge < zap`
3. **Semantic Prefixes** - Commands grouped by purpose (`h*`, `w*`, `s*`, `l*`, `analyze`)
4. **Built-in Safety** - Confirmations, dry-run, automatic backups
5. **Interactive Modes** - Gum-based selection for complex operations

### Command Prefix Quick Reference

| Prefix | Category | Examples |
|--------|----------|----------|
| `h*` | HEAD operations | `h back`, `h squash`, `h files` |
| `w*` | Working directory | `w discard`, `w purge`, `w zap` |
| `s*` | Status & staging | `s`, `ss`, `su`, `sw` |
| `b*` | Branching | `b`, `bc`, `bl`, `bdel` |
| `c*` | Commits | `c`, `ccp`, `cmv` |
| `l*` | Logging | `lf`, `lc`, `lcr`, `lol` |
| `f*` | File inspection | `fborn`, `fblame`, `fcon` |
| `t*` | Tagging | `t`, `tc`, `ta`, `tdel` |
| `analyze` | Computational analysis | `analyze co-changes`, `analyze deps`, `analyze ownership` |

## Skill Highlights

### Hidden Gems

These powerful but under-documented features are covered in the skills:

1. **`hug fborn`** - Binary search to find file's creation commit (fast!)
2. **`hug h steps`** - Calculate safe rewind steps
3. **Temporal operations** - Time-based queries with `-t "3 days ago"`
4. **Auto-backups** - Destructive HEAD operations create safety branches
5. **Interactive selection** - Most commands support `--` for Gum-based picking
6. **Upstream comparisons** - `-u` flag for unpushed commit analysis
7. **Computational analysis** - `analyze` commands use statistical algorithms (co-changes, ownership, dependencies)
8. **JSON export** - Many commands accept `--json` or `--format json` for automation

### Key Investigation Patterns

The skills teach these fundamental patterns:

**Pattern 1: Status → Search → Inspect → Act**
```bash
hug s                        # what's changed?
hug lf "keyword"             # find related commits
hug shp <commit>             # inspect details
# make informed decision
```

**Pattern 2: Temporal Analysis**
```bash
hug h files -t "3 days ago"  # recent changes
hug ld "monday" "friday"     # date range
hug lau "Author" --since="1 month ago"
```

**Pattern 3: File Investigation**
```bash
hug fborn <file>             # when created?
hug llf <file>               # full history
hug fblame <file>            # who wrote what?
```

**Pattern 4: Computational Analysis**
```bash
hug analyze co-changes <file>           # find architecturally coupled files
hug analyze ownership <file>            # who maintains this file?
hug analyze deps <commit>               # what commits are related?
hug analyze activity --format json      # export temporal patterns
```

## Integration Points

### With Hug SCM MCP Server

The MCP server exposes read-only tools that map to Hug commands:

- `hug_status` → `hug s`, `hug sla`
- `hug_log` → `hug l` with filters
- `hug_h_files` → `hug h files` (temporal, upstream)
- `hug_show_diff` → `hug ss`, `hug su`, `hug sw`
- `hug_branch_list` → `hug bl`, `hug bla`

Skills teach when and how to combine these tools effectively.

### With Code Execution

For complex analysis requiring data processing:

```typescript
// Example: Find files changed most often (basic approach)
const commits = await hug_log({ count: 100 });
const fileChanges = new Map();

for (const commit of commits) {
  const files = await hug_h_files({ count: 1, commit: commit.hash });
  files.forEach(f => fileChanges.set(f, (fileChanges.get(f) || 0) + 1));
}

// Show hot spots
const hotSpots = Array.from(fileChanges.entries())
  .sort((a, b) => b[1] - a[1])
  .slice(0, 10);
```

```typescript
// Example: Advanced analysis with JSON export
const coChanges = await execCommand('hug analyze co-changes src/main.ts --format json');
const ownership = await execCommand('hug analyze ownership src/main.ts --format json');
const deps = await execCommand('hug analyze deps HEAD --format json');

// Combine multiple data sources for rich insights
const analysis = {
  coupling: JSON.parse(coChanges),
  maintainers: JSON.parse(ownership),
  dependencies: JSON.parse(deps)
};
```

## Development Workflow

When adding new skills or guides:

1. **Keep SKILL.md concise** - It's loaded first, avoid bloat
2. **Detailed guides go in guides/** - Reference from SKILL.md
3. **Use real examples** - Show actual command sequences
4. **Explain the "why"** - Not just "what" but "why this approach"
5. **Cross-reference** - Link related guides and main docs

## Learning Path

Recommended order for learning these skills:

1. **SKILL.md (Core)** - Essential Hug knowledge and patterns
2. **pre-commit-review.md** - Daily workflow, safest operations
3. **bug-hunting.md** - Investigation techniques
4. **branch-analysis.md** - Understanding branch relationships
5. **history-cleanup.md** - Advanced (rewriting history)

## Additional Resources

- [Main Hug SCM Documentation](../../index.md)
- [Command Reference](../../command-map.md)
- [Workflows Guide](../../workflows.md)
- [Testing Guide](https://github.com/elifarley/hug-scm/blob/main/TESTING.md)

## Contributing

To improve these skills:

1. Test workflows with real repositories
2. Add examples from actual debugging sessions
3. Document common pitfalls and solutions
4. Cross-reference with main documentation
5. Keep safety considerations prominent

## Version

Current version: 1.0.0

Last updated: 2024

## License

These skills are part of the Hug SCM project and follow the same Apache 2.0 license.
