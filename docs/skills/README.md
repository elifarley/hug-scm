# Hug Skills

This directory contains Claude Code skills that enhance your experience working with Hug.

## Quick Install

**One-line installation:**
```bash
curl -sSL https://raw.githubusercontent.com/elifarley/hug-scm/main/docs/skills/hug-workflow.skill -o ~/.claude/skills/hug-workflow.skill
```

**Or manual install:**
```bash
mkdir -p ~/.claude/skills
cp docs/skills/hug-workflow.skill ~/.claude/skills/
```

That's it! Claude Code will automatically discover and load the skill when you work with Git.

## What are Skills?

Skills are modular packages that extend Claude's capabilities with specialized knowledge and workflows. When you use Claude Code with Hug-related projects, these skills auto-load to provide better assistance.

## Available Skills

### hug-workflow.skill

Git workflow management using Hug (enhanced Git replacement).

**Features:**
- Safety rules for staging and committing
- Pre-commit workflows
- Amend and fix operations
- Common command reference

**Auto-triggers when:**
- You mention committing, staging, or Git operations
- Claude needs to inspect repository state
- Working with branches or history

## Usage

Once installed, skills auto-load when relevant. No manual activation needed - Claude Code detects when a skill is needed based on your conversation context.

## Contributing

Have a skill that improves the Hug workflow? Submit a PR to add it here!
