# Commits (c*)

The `c*` commands handle creating and amending commits, making it easier to record changes in your repository.

## Quick Reference

| Command | Memory Hook | Summary |
| --- | --- | --- |
| `hug c` | **C**ommit | Commit staged changes with a message |
| `hug caa` | **C**ommit **A**ll **A**mend | Amend previous commit including all changes |
| `hug cc` | **C**ommit **C**lose | Commit and close a referenced issue |

## hug c

Commit staged changes with a message.

**Usage:** `hug c <message>`

**Examples:**
```bash
hug c "Fix typo in README"
hug c -m "Update dependencies" -a  # Commit all changes
```

This is a safe way to commit, ensuring only staged files are included unless `-a` is used.

## hug caa

Commit all changes and amend the last commit.

**Usage:** `hug caa <message>`

**Examples:**
```bash
hug caa "Add missing feature"
```

Amends the previous commit by adding all current changes (staged and unstaged) and updating the message.

## hug cc

Commit and close an issue (integrates with GitHub/GitLab).

**Usage:** `hug cc <message> #<issue-number>`

**Examples:**
```bash
hug cc "Resolve authentication bug #123"
```

Automatically closes the specified issue when the commit is pushed to the default branch.

### Tips
- Always stage changes with `hug s` or `hug a` before `hug c`.
- Use `hug caa` for quick fixes to the last commit without creating a new one.
- For interactive commits, consider using `git commit` directly for advanced options.
