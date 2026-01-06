# Hug Skills

This directory contains Claude Code skills that enhance your experience working with Hug.

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

**Installation:**
Copy `hug-workflow.skill` to your `~/.claude/skills/` directory. Claude Code will automatically discover and load it.

## Usage

Once installed, skills auto-load when relevant. No manual activation needed - Claude Code detects when a skill is needed based on your conversation context.

## Contributing

Have a skill that improves the Hug workflow? Submit a PR to add it here!
