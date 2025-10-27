---
title: Welcome to Hug Documentation
editLink: true
lastUpdated: true
outline: [2, 3]
---

# Welcome to Hug Documentation

Hug is a CLI tool to streamline development. It provides a humane, intuitive interface for Git and Mercurial, transforming complex commands into a predictable, unified language that keeps you focused on coding.

Key features:
- **Intuitive Commands**: Shorter for common/safe ops, longer for powerful ones (e.g., `hug b` to switch branches).
- **Safety Built-In**: Previews, dry-runs, and confirmations for destructive actions.
- **Discoverability**: Grouped by prefix (e.g., `h*` for HEAD, `w*` for working directory).
- **Multi-VCS Support**: Full support for both Git and Mercurial with automatic repository detection.

Start with [Hug for Beginners](hug-for-beginners.md)

## Command Reference
Start with the [Command Map](/command-map) for a quick overview of all families, or the [Cheat Sheet](/cheat-sheet) for daily workflows.

Dive into detailed guides for command groups:

- [HEAD Operations (h*): Undo and rewind commits](commands/head)
- [Working Directory (w*): Clean up changes](commands/working-dir)
- [Status & Staging (s*, a*): View and stage files](commands/status-staging)
- [Branching (b*): Switch, list, and manage branches](commands/branching)
- [Commits (c*): Create and amend commits](commands/commits)
- [Logging (l*): Search and view history](commands/logging)
- [File Inspection (f*): Analyze file authorship and history](commands/file-inspection)
- [Tagging (t*): Manage tags for releases](commands/tagging)
- [Merge (m*): Integrate branches](commands/merge)
- [Rebase (r*): Edit history](commands/rebase)
- [WIP Workflow (w*): Park, resume, and unpark temp work](commands/working-dir)
 
### Tips for Common Queries
- **Most recent commit touching a file**: Use `hug llf <file> -1` to get the latest commit modifying a specific file (handles renames with `--follow`). For multiple files, run separately and compare timestamps, or use `hug llf file1 -1` and `hug llf file2 -1`.
- **Last N commits for a file**: `hug llf <file> -N` (e.g., `-2` for last 2). Use `hug llfp <file> -1` for patches or `hug llfs <file> -1` for changes.
- **Search history by file changes**: Combine with `lf` or `lc` for message/code searches restricted to file touches.
