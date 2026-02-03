# Utilities

Miscellaneous utility commands for working with repositories.

[[toc]]

## Init (`hug init`)

Initialize a new Git or Mercurial repository. Defaults to Git.

### Basic Usage

```shell
# Initialize Git repo in current directory
hug init

# Initialize Git repo in new directory
hug init my-project

# Initialize with specific VCS
hug init --git
hug init --hg

# Skip post-init status display
hug init --no-status

# Pass options to underlying VCS
hug init --initial-branch=main
hug init my-project --bare
```

### Features

#### Defaults to Git

By default, `hug init` creates a Git repository. This makes it quick and easy to get started without specifying flags:

```shell
hug init my-new-project
```

#### Force Specific VCS

Use `--git` or `--hg` to explicitly choose the version control system:

```shell
# Git (explicit)
hug init --git my-git-repo

# Mercurial
hug init --hg my-hg-repo
```

#### Post-Init Status

By default, Hug provides helpful information after initialization. For empty repositories, it shows a friendly message:

```shell
$ hug init my-repo
ℹ️ Info: Initializing Git repository...
✅ Success: ✓ Initialized Git repository in 'my-repo'.
ℹ️ Info: Empty repository. Create your first commit to see status.
```

Use `--no-status` to skip this behavior, useful for scripts:

```shell
hug init --no-status my-repo
```

#### Safety Features

**Prevents Re-initialization:**
Hug checks if a repository already exists and prevents accidental re-initialization:

```shell
$ hug init
❌ Error: Already a Git repository.
```

**Directory Creation:**
If the specified directory doesn't exist, Hug creates it for you:

```shell
hug init path/to/my-project
```

### Examples

**Basic Git initialization:**
```shell
hug init
```

**Initialize in new directory:**
```shell
hug init my-awesome-project
cd my-awesome-project
```

**Initialize with custom branch name:**
```shell
hug init --initial-branch=main my-project
```

**Initialize bare repository:**
```shell
hug init --bare my-bare-repo.git
```

**Initialize Mercurial repository:**
```shell
hug init --hg my-hg-project
```

**Script-friendly (no status output):**
```shell
hug init --no-status project1
hug init --no-status project2
```

## Clone (`hug clone`)

Clone a Git or Mercurial repository with automatic VCS detection.

### Basic Usage

```shell
# Auto-detect VCS from URL
hug clone https://github.com/user/repo.git

# Clone to specific directory
hug clone https://gitlab.com/user/repo.git my-project

# Force specific VCS
hug clone --git https://example.com/repo
hug clone --hg https://hg.example.com/repo

# Skip post-clone status display
hug clone --no-status https://github.com/user/repo.git

# Pass options to underlying VCS
hug clone https://github.com/user/repo.git --depth 1
hug clone https://github.com/user/repo.git --branch develop
```

### Features

#### Automatic VCS Detection

Hug automatically detects whether a repository is Git or Mercurial based on URL patterns:

**Git Detection:**
- URLs ending with `.git`
- GitHub URLs (github.com)
- GitLab URLs (gitlab.com)
- Bitbucket Git URLs
- Gitea instances
- Codeberg URLs

**Mercurial Detection:**
- URLs ending with `.hg`
- URLs containing `hg.` in the domain

If the VCS cannot be determined automatically, Hug will prompt you to choose.

#### Safety Features

**Directory Existence Check:**
If the target directory already exists, Hug will prompt for confirmation before overwriting:

```shell
$ hug clone https://github.com/user/repo.git existing-dir
Directory 'existing-dir' exists. Overwrite? (y/N)
```

**Cleanup on Failure:**
If a clone operation fails (e.g., network error, invalid repository), Hug automatically cleans up any partially cloned directory.

#### Post-Clone Status

By default, Hug runs `hug s` after a successful clone to show you the repository status. This gives you immediate feedback about the cloned repository's state.

Use `--no-status` to skip this behavior, useful for scripts or when cloning multiple repositories:

```shell
hug clone --no-status https://github.com/user/repo1.git
hug clone --no-status https://github.com/user/repo2.git
```

### Examples

**Clone from GitHub:**
```shell
hug clone https://github.com/torvalds/linux.git
```

**Clone to specific directory:**
```shell
hug clone https://github.com/rust-lang/rust.git rust-compiler
```

**Shallow clone (faster for large repos):**
```shell
hug clone https://github.com/kubernetes/kubernetes.git --depth 1
```

**Clone specific branch:**
```shell
hug clone https://github.com/user/repo.git --branch develop
```

**Clone with SSH:**
```shell
hug clone git@github.com:user/private-repo.git
```

**Force Mercurial:**
```shell
hug clone --hg https://hg.mozilla.org/mozilla-central
```

### Command Reference

```
Usage: hug clone [--git|--hg] [--no-status] <url> [dir] [options]

Options:
  --git         Force Git as the VCS
  --hg          Force Mercurial as the VCS
  --no-status   Skip post-clone status display

Arguments:
  <url>         Repository URL to clone
  [dir]         Target directory (optional, defaults to repository name)
  [options]     Additional options passed to underlying VCS
```

### Tips

::: tip Working with Large Repositories
For large repositories, consider using `--depth 1` to create a shallow clone:
```shell
hug clone https://github.com/large/repo.git --depth 1
```
This downloads only the latest commit, significantly reducing clone time and disk space.
:::

::: tip Script-Friendly Cloning
When writing scripts, use `--no-status` to avoid interactive output:
```shell
#!/bin/bash
for repo in repo1 repo2 repo3; do
  hug clone --no-status "https://github.com/org/$repo.git"
done
```
:::

::: tip Authentication
Hug passes through authentication prompts from the underlying VCS. For automated workflows, configure SSH keys or credential helpers:
```shell
# Configure SSH key
ssh-keygen -t ed25519 -C "your_email@example.com"
# Add to GitHub/GitLab

# Or use credential helper
git config --global credential.helper store
```
:::

## Other Utilities

### Garbage Collection (`hug g`)

Perform safe, controlled Git garbage collection with three modes of increasing space savings.

#### Basic Usage

```shell
# Basic garbage collection (safe, preserves reflog)
hug g

# Expire reflog + gc (removes undo history)
hug g --expire

# Expire reflog + aggressive gc (maximum cleanup)
hug g --aggressive

# Preview what would be done
hug g --dry-run
hug g --expire --dry-run
hug g --aggressive --dry-run

# Skip confirmation prompts
hug g -f
hug g --expire --force
hug g --aggressive -f

# Suppress output
hug g -q
hug g --expire --quiet
```

#### Modes

Hug provides three garbage collection modes with increasing space savings and destructiveness:

| Mode | Git Operations | Space Savings | Danger Level | Confirmation |
|------|---------------|---------------|--------------|--------------|
| Basic | `git gc` | Mild | Low | Y/n (safe default) |
| Expire | `git reflog expire --expire=now --all` + `git gc` | Medium | Medium | y/N (warning default) |
| Aggressive | `git reflog expire --expire=now --all` + `git gc --prune=now --aggressive` | Maximum | Extreme | Type "aggressive" |

#### Features

**Basic Mode (Safe)**
- Runs `git gc` only
- Preserves reflog for undo operations
- Safe to use anytime
- Confirmation defaults to Yes

**Expire Mode (Medium Risk)**
- Expires reflog entries with `git reflog expire --expire=now --all`
- Then runs `git gc`
- Removes undo history - `hug h back` won't work after this
- Confirmation defaults to No

**Aggressive Mode (Maximum Cleanup)**
- Expires reflog entries
- Runs `git gc --prune=now --aggressive`
- Maximum space savings
- Cannot be undone - reflog history is permanently removed
- May take significantly longer than other modes
- Requires typing "aggressive" to confirm (without --force)

**Safety Features**
- `--dry-run`: Preview what would be done without applying changes
- Progressive confirmation: safer modes have easier confirmation
- `-f/--force`: Skip confirmation prompts when you're certain
- `-q/--quiet`: Suppress informational output

#### Examples

**Basic cleanup (safe, daily use):**
```shell
hug g
# Output:
# ℹ️ Info: run garbage collection [Y/n]: y
# ✅ Success: Garbage collection complete
```

**Medium cleanup (after major work):**
```shell
hug g --expire
# Output:
# ⚠️ Warning: ⚠ About to expire reflog and run garbage collection...
# Proceed? [y/N]: y
# ℹ️ Info: Expiring reflog entries...
# ✅ Success: Garbage collection complete (reflog expired)
```

**Maximum cleanup (before archiving):**
```shell
hug g --aggressive
# Output:
# ⚠️ This will PERMANENTLY remove reflog history and cannot be undone!
# ⚠️ Warning: ⚠ About to run aggressive garbage collection...
# → Type "aggressive" to confirm: aggressive
# ℹ️ Info: Running aggressive garbage collection (this may take a while)...
# ✅ Success: Aggressive garbage collection complete
```

**Preview before cleanup:**
```shell
hug g --dry-run
# Output:
# ℹ️ Info: Would run: git gc
```

**Skip confirmation for automated scripts:**
```shell
hug g --force
hug g --aggressive -f  # Skip typing "aggressive"
```

::: tip When to Use Each Mode
- **Basic**: Regular maintenance, safe for daily use
- **Expire**: After completing large features, when you won't need undo history
- **Aggressive**: Before archiving old projects, when you need maximum space savings
:::

::: warning Aggressive Mode Risks
The aggressive mode permanently removes reflog history, which means:
- You cannot use `hug h back` to undo changes
- You cannot recover deleted branches via reflog
- The operation cannot be reversed

Only use aggressive mode when you're certain you won't need undo history.
:::

#### Command Reference

```
Usage: hug g [OPTIONS]

Options:
      --expire           Expire reflog before gc (medium cleanup)
      --aggressive       Expire reflog and run aggressive gc (maximum cleanup)
      --dry-run          Show what would be done without applying changes
  -f, --force            Skip confirmation prompts
  -q, --quiet            Suppress output
  -h, --help             Show this help
```

### Untrack (`hug untrack`)

Stop tracking files but keep them locally. Useful for files that should be ignored but were already committed.

```shell
hug untrack config/secrets.yml
```

### Type and Dump

Inspect Git objects directly:

```shell
# Show object type
hug type HEAD
hug type a1b2c3d

# Show object contents
hug dump HEAD
hug dump a1b2c3d
```

### Remote2SSH (`hug remote2ssh`)

Convert a remote URL from HTTPS to SSH format for GitHub repositories.

#### Basic Usage

```shell
# Convert origin remote to SSH
hug remote2ssh

# Convert specific remote
hug remote2ssh upstream
```

#### Features

**Automatic URL Conversion**

Converts GitHub HTTPS URLs to SSH format automatically:
- `https://github.com/user/repo.git` → `git@github.com:user/repo.git`
- Updates the remote URL in-place
- Shows confirmation with `git remote -v`

**Safety**

- Read-only operation on remote configuration
- Only modifies URL, not repository content
- Works on any remote (defaults to `origin`)

#### Examples

**Convert default remote (origin):**
```shell
$ hug remote2ssh
Updated origin remote to use SSH:
origin  git@github.com:user/repo.git (fetch)
origin  git@github.com:user/repo.git (push)
```

**Convert specific remote:**
```shell
$ hug remote2ssh upstream
Updated upstream remote to use SSH:
upstream  git@github.com:org/repo.git (fetch)
upstream  git@github.com:org/repo.git (push)
```

::: tip When to Use SSH
SSH authentication is preferred over HTTPS for:
- **Passwordless pushing** - No need to enter credentials
- **Scripted automation** - SSH keys work seamlessly in CI/CD
- **Multiple repositories** - One SSH key for all GitHub repos

Set up SSH keys first:
```shell
ssh-keygen -t ed25519 -C "your_email@example.com"
# Add public key to GitHub Settings → SSH Keys
```
:::

### WIP Management

See [Working Directory Commands](./working-dir.md#wip-work-in-progress) for WIP (Work In Progress) branch management commands.
