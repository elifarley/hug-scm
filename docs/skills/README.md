# Hug Skills

This directory contains skills that enhance your agent's experience working with hug.
Each skill is a directory containing a `SKILL.md` (some add supporting files).

## Install

Skills live in per-skill directories. Copy the ones you want into your agent's skills
directory (Claude Code paths shown; adjust the destination for other hosts):

```bash
# From a clone of this repo:
cp -r docs/skills/hug-workflow      ~/.claude/skills/
cp -r docs/skills/hug-worktree      ~/.claude/skills/
cp -r docs/skills/hug-repo-analysis ~/.claude/skills/
```

Or fetch a single skill's `SKILL.md` directly (works while a skill is exactly one file
— see the note below):

```bash
mkdir -p ~/.claude/skills/hug-worktree
curl -sSL https://raw.githubusercontent.com/elifarley/hug-scm/main/docs/skills/hug-worktree/SKILL.md \
  -o ~/.claude/skills/hug-worktree/SKILL.md
```

That's it — Claude Code auto-discovers and loads a skill when its triggers match.

> **Note:** the single-file `curl` form holds only while a skill is exactly one
> `SKILL.md`. `hug-repo-analysis` ships supporting material under `guides/`, so use the
> `cp -r` (directory) form for it. A multi-file-safe installer is a possible follow-up.

## What are Skills?

Skills are modular packages that extend an agent's capabilities with specialized
knowledge and workflows. When you work in hug-related projects, a matching skill
auto-loads to provide better assistance.

## Available Skills

### hug-workflow

Git workflow management using hug (enhanced git replacement) — staging, committing,
amending, inspection, history. Auto-triggers on commit/stage/status/log/diff.

### hug-worktree

The worktree-first ritual for branch-worthy work: create a worktree before starting,
work inside it, clean up after merge. Delegates to `hug help :worktree`, so non-skill
agents get the same ritual straight from hug. Auto-triggers when starting a
feature/bugfix/refactor/spec.

### hug-repo-analysis

Repository analysis and reporting helpers (ships supporting material under `guides/`).

## Contributing

Have a skill that improves the hug workflow? Open a PR to add it here.
