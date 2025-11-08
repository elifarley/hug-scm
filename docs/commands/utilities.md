# Utilities

Miscellaneous utility commands for working with repositories.

[[toc]]

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

### WIP Management

See [Working Directory Commands](./working-dir.md#wip-work-in-progress) for WIP (Work In Progress) branch management commands.
