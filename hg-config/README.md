# Hug SCM - Mercurial Support

This directory contains Mercurial-specific support for Hug SCM.

## Structure

```
hg-config/
├── bin/              # Mercurial command implementations
│   ├── hg-a          # Add/stage files
│   ├── hg-b          # Switch bookmark/branch
│   ├── hg-c          # Commit changes
│   ├── hg-h          # HEAD operations
│   ├── hg-l          # Log history
│   ├── hg-s          # Status
│   ├── hg-w          # Working directory operations
│   └── ...           # Many more commands
├── lib/
│   ├── hug-common    # Symlink to common utilities (shared with git-config)
│   └── hug-hg-kit    # Mercurial-specific operations library
├── .hgrc             # Mercurial configuration with Hug aliases
├── activate          # Shell script to activate Hug for Mercurial
└── install.sh        # Installation script
```

## Prerequisites

- Mercurial (hg) version 4.0 or later
- Bash 4.0 or later

### Recommended Extensions

For full functionality, enable these Mercurial extensions in `~/.hgrc`:

```ini
[extensions]
purge =     # Required for 'hug w purge' commands
evolve =    # Required for 'hug h back/undo' commands
```

To install evolve:
```bash
# Ubuntu/Debian
sudo apt-get install mercurial-evolve

# macOS
brew install mercurial
pip install hg-evolve

# Or via pip
pip install --user hg-evolve
```

## Installation

### Standalone Mercurial Support

If you only want Mercurial support (without Git):

```bash
cd hg-config
./install.sh
```

### Combined Installation

To install both Git and Mercurial support, use the main installer:

```bash
cd ..  # Go to project root
./install.sh
```

## Quick Start

After installation, open a new terminal or run:

```bash
source ~/path/to/hug-scm/hg-config/activate
```

Navigate to a Mercurial repository and try:

```bash
hug s        # Show status
hug a file.txt   # Add a file
hug c -m "message"  # Commit
hug l        # View history
```

## Command Mapping

| Hug Command | Mercurial Equivalent | Description |
|-------------|---------------------|-------------|
| `hug s` | `hg status` | Show repository status |
| `hug a` | `hg add` | Add files |
| `hug aa` | `hg addremove` | Add all files (including removals) |
| `hug c` | `hg commit` | Commit changes |
| `hug ca` | `hg commit` | Commit all (same as `c`) |
| `hug caa` | `hg addremove && hg commit` | Add all and commit |
| `hug b <name>` | `hg update <name>` | Switch to bookmark/branch |
| `hug bc <name>` | `hg bookmark <name>` | Create new bookmark |
| `hug bl` | `hg bookmarks` | List bookmarks |
| `hug l` | `hg log -G` | View history graph |
| `hug ll` | `hg log -G` (detailed) | View detailed history |
| `hug w discard` | `hg revert` | Discard changes |
| `hug w purge` | `hg purge` | Remove untracked files |
| `hug w zap` | `hg revert && hg purge` | Complete cleanup |
| `hug h back` | `hg uncommit` | Uncommit, keep changes |
| `hug h undo` | `hg uncommit && hg revert` | Uncommit and discard |

## Key Differences from Git

### Bookmarks vs Branches

Mercurial has both branches and bookmarks:
- **Branches** are permanent (recorded in commits)
- **Bookmarks** are lightweight (like Git branches)

Hug uses bookmarks by default for Git-like behavior.

### No Staging Area

Unlike Git, Mercurial doesn't have a staging area:
- `hug a` in Mercurial just marks files as tracked
- `hug c` commits all changes to tracked files
- Use `hg status` to see what will be committed

### Evolve Extension

Some advanced operations (like uncommit) require the evolve extension:
```ini
[extensions]
evolve =
```

## Available Commands

### Status & Staging
- `hug s` - Status summary
- `hug sl` - Status without untracked files
- `hug sla` - Full status with untracked files
- `hug a <files>` - Add files
- `hug aa` - Add everything (including removals)

### Commits
- `hug c [-m msg]` - Commit changes
- `hug ca [-m msg]` - Commit all (same as `c`)
- `hug caa [-m msg]` - Add all and commit

### Bookmarks & Branches
- `hug b [name]` - Switch to bookmark/branch (or list if no args)
- `hug bc <name>` - Create new bookmark
- `hug bl` - List bookmarks

### History
- `hug l` - Log with graph
- `hug ll` - Detailed log
- `hug la` - Log all branches

### Working Directory
- `hug w discard <files>` - Discard changes in files
- `hug w discard-all` - Discard all changes
- `hug w purge [paths]` - Remove untracked files
- `hug w purge-all` - Remove all untracked files
- `hug w wipe` - Alias for discard
- `hug w zap` - Complete cleanup (discard + purge)
- `hug w zap-all` - Complete cleanup of entire repo

### HEAD Operations
- `hug h back [N]` - Uncommit last N changes (keep in working dir)
- `hug h undo [N]` - Uncommit and discard last N changes

## Testing

Tests for Mercurial support are in the `tests/unit/` directory:

```bash
# Run Mercurial tests
bats tests/unit/test_hg_basic.bats

# Run all tests
bats tests/
```

## Troubleshooting

### "hg: unknown command"

Make sure the hg-config/bin directory is in your PATH:
```bash
export PATH="$PATH:/path/to/hug-scm/hg-config/bin"
```

### "extension 'purge' is not enabled"

Add to your `~/.hgrc`:
```ini
[extensions]
purge =
```

### "extension 'evolve' is not enabled"

Required for `hug h back/undo` commands. Add to `~/.hgrc`:
```ini
[extensions]
evolve =
```

Then install evolve:
```bash
pip install --user hg-evolve
```

## Contributing

When adding new Mercurial commands:

1. Follow the existing command patterns
2. Use the standard header with library sourcing
3. Add help text with `show_help()` function
4. Include examples in the help text
5. Add tests in `tests/unit/test_hg_*.bats`

See existing commands in `bin/` for examples.

## See Also

- [Main Hug Documentation](../README.md)
- [Architecture Decision Record](../docs/architecture/ADR-002-mercurial-support-architecture.md)
- [Mercurial Documentation](https://www.mercurial-scm.org/doc/)
- [Mercurial Book](http://hgbook.red-bean.com/)
