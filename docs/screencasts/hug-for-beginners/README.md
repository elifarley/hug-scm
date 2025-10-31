# Hug for Beginners - Screencasts

This directory contains VHS tape files for generating screenshots used in the beginner's tutorial (`docs/hug-for-beginners.md`).

## Structure

```
hug-for-beginners/
├── setup.tape           # Beginner-specific setup (uses /tmp/beginner-repo)
├── bin/
│   └── repo-setup.sh    # Creates minimal beginner repository
├── hug-aa.tape          # Individual command demonstrations
├── hug-c.tape
├── hug-bc.tape
└── ...
```

## Beginner Repository

The beginner tapes use a **separate, minimal repository** (`/tmp/beginner-repo`) that is:
- Created from scratch with `hug init`
- Contains only a README.md file initially
- Has no complex history, branches, or tags
- Provides a clean learning environment

This is different from the main demo repository (`/tmp/demo-repo`) used for command reference documentation, which has a complex structure with multiple branches, tags, and history.

## Creating the Beginner Repository

```bash
bash docs/screencasts/hug-for-beginners/bin/repo-setup.sh
```

This creates `/tmp/beginner-repo` with minimal content suitable for tutorials.

## Building Screenshots

From this directory:

```bash
# Build single tape
../bin/vhs hug-aa.tape

# Build all tapes
for tape in hug-*.tape; do
    ../bin/vhs "$tape"
done
```

Screenshots are generated to: `../../img/hug-for-beginners/`

## Design Principles

1. **Co-location**: Tapes for `hug-for-beginners.md` live in `screencasts/hug-for-beginners/`
2. **Self-contained**: Has its own setup script and configuration
3. **Beginner-focused**: Uses simple, clean repository without complex scenarios
4. **Progressive**: Each tape demonstrates a specific learning step

## Image References

In the markdown, reference images as:
```markdown
![Description](img/hug-for-beginners/hug-aa.png)
```
