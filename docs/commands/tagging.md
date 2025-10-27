# Tagging (t*)

Tagging commands in Hug are for creating, listing, and managing release markers or important milestones in your project's history. They are prefixed with `t` for "tag."

These commands provide intuitive ways to create lightweight and annotated tags, manage tag lifecycle (move, rename, delete), sync with remotes, and query which tags relate to specific commits.

> **Note:** Tag commands are implemented as Git aliases in `.gitconfig`, providing a consistent interface over Git's native tag functionality.

## Quick Reference

| Command | Memory Hook | Summary |
| --- | --- | --- |
| `hug t` | **T**ags list | List all tags (optionally matching a pattern) |
| `hug tc` | **T**ag **C**reate | Create a lightweight tag |
| `hug ta` | **T**ag **A**nnotated | Create an annotated (detailed) tag |
| `hug ts` | **T**ag **S**how | Show tag details |
| `hug tr` | **T**ag **R**ename | Rename a tag |
| `hug tm` | **T**ag **M**ove | Move tag to a new commit |
| `hug tma` | **T**ag **M**ove **A**nnotated | Move and re-annotate tag |
| `hug tpush` | **T**ag **Push** | Push specific tag(s) to remote (or all if no args) |
| `hug tpull` | **T**ag **Pull** | Fetch tags from remote |
| `hug tpullf` | **T**ag **Pull** **F**orce | Force fetch and prune tags from remote |
| `hug tdel` | **T**ag **DEL**ete | Delete local tag |
| `hug tdelr` | **T**ag **DEL**ete **R**emote | Delete remote tag |
| `hug tco` | **T**ag **C**heck**O**ut | Checkout a specific tag |
| `hug twc` | **T**ags **W**hich **C**ontain | Tags which contain a commit |
| `hug twp` | **T**ags **W**hich **P**oint | Tags which point to an object |

## Listing Tags

### `hug t [pattern]`
- **Description**: Lists all existing tags. If a pattern is provided, only tags matching that pattern are shown (e.g., `v1.*` for all v1.x tags).
- **Example**: 
  ```shell
  hug t              # List all tags
  hug t "v1.*"       # List tags matching v1.*
  hug t "v2.0*"      # List tags starting with v2.0
  ```
- **Safety**: Read-only; no repo changes.

## Creating Tags

### `hug tc <tag-name> [commit]`
- **Description**: Creates a lightweight tag at the specified commit (defaults to HEAD). This is a simple pointer to a specific commit and contains no extra information. Good for quick, temporary markers.
- **Example**: 
  ```shell
  hug tc v1.0.1              # Tag current commit
  hug tc v1.0.1 a1b2c3       # Tag specific commit
  ```
- **Safety**: Non-destructive; creates new tag reference.

### `hug ta <tag-name> "<message>"`
- **Description**: Creates an annotated tag. This is recommended for official releases, as it is a full object in the Git database that includes the tagger's name, email, date, and a message. Annotated tags are the Git-recommended way to mark releases.
- **Example**: 
  ```shell
  hug ta v1.0.0 "Initial stable release"
  hug ta v2.0.0 "Major rewrite with breaking changes"
  ```
- **Safety**: Non-destructive; creates new tag object.

## Viewing Tag Details

### `hug ts <tag-name>`
- **Description**: Show detailed information about a tag, including the commit it points to, the tag message (for annotated tags), and the tagger information.
- **Example**: 
  ```shell
  hug ts v1.0.0       # Show details for v1.0.0 tag
  ```
- **Safety**: Read-only; displays tag information.

## Modifying Tags

### `hug tr <old-tag> <new-tag>`
- **Description**: Rename a tag by creating a new tag pointing to the same commit and deleting the old tag. The commit reference stays the same, only the tag name changes.
- **Example**: 
  ```shell
  hug tr v1.0 v1.0.1       # Rename tag v1.0 to v1.0.1
  ```
- **Safety**: Deletes old tag locally; must manually update remote if already pushed.

### `hug tm <tag-name> [commit]`
- **Description**: Move an existing tag to point to a different commit (defaults to HEAD). Keeps the same tag name but changes what commit it references.
- **Example**: 
  ```shell
  hug tm v1.0           # Move v1.0 tag to current HEAD
  hug tm v1.0 a1b2c3    # Move v1.0 tag to specific commit
  ```
- **Safety**: Overwrites existing tag; use with caution on shared tags.

### `hug tma <tag-name> "<message>" [commit]`
- **Description**: Move an existing tag to a new commit (defaults to HEAD) and update its annotation message. Combines move and re-annotate operations.
- **Example**: 
  ```shell
  hug tma v1.0 "Updated release notes"           # Re-annotate at HEAD
  hug tma v1.0 "Hotfix included" a1b2c3         # Move and re-annotate
  ```
- **Safety**: Overwrites existing tag; coordinate with team if tag is shared.

## Synchronizing Tags with Remotes

### `hug tpush [tags...]`
- **Description**: Push tag(s) to the remote repository. If no tag names are provided, pushes all tags. By default, `git push` does not send tags, so this is necessary to share tags with others.
- **Example**: 
  ```shell
  hug tpush v1.0.0           # Push single tag
  hug tpush v1.0.0 v1.0.1    # Push multiple specific tags
  hug tpush                  # Push all local tags
  ```
- **Safety**: Publishes tags to remote; coordinate releases with team.

### `hug tpull`
- **Description**: Fetch all tags from the remote repository. This updates your local tag references to match what's on the remote.
- **Example**: 
  ```shell
  hug tpull       # Fetch all tags from remote
  ```
- **Safety**: Read-only operation; updates local tag references but doesn't modify working directory.

### `hug tpullf`
- **Description**: Force fetch tags from remote, pruning any local tags that no longer exist on the remote. This is the forceful version that synchronizes your local tags to exactly match the remote.
- **Example**: 
  ```shell
  hug tpullf      # Force sync tags with remote
  ```
- **Safety**: Removes local tags not on remote; use when you need to completely sync with remote state.

## Deleting Tags

### `hug tdel <tag-name>`
- **Description**: Delete a tag from your local repository. The tag still exists on the remote unless you also delete it there.
- **Example**: 
  ```shell
  hug tdel v1.0-beta       # Delete local tag
  ```
- **Safety**: Only affects local repository; remote tag remains.

### `hug tdelr <tag-name>`
- **Description**: Delete a tag from the remote repository (`origin`). This removes the tag for everyone, so use carefully on shared repositories.
- **Example**: 
  ```shell
  hug tdelr v1.0-beta      # Delete tag from remote
  ```
- **Safety**: Removes tag from remote repository; coordinate with team before deleting shared release tags.

## Checking Out Tags

### `hug tco <tag-name>`
- **Description**: Checkout a specific tag, putting your repository in "detached HEAD" state at that tag's commit. This is useful for inspecting or building from a specific release.
- **Example**: 
  ```shell
  hug tco v1.0.0       # Checkout tag v1.0.0
  ```
- **Safety**: Puts you in detached HEAD state; create a branch if you need to make changes.

## Tag Queries

### `hug twc [commit]`
- **Description**: Show tags which contain a specific commit in their history (defaults to HEAD). This answers "which releases include this commit?"
- **Example**: 
  ```shell
  hug twc              # Tags containing HEAD
  hug twc a1b2c3       # Tags containing specific commit
  ```
- **Safety**: Read-only query.

### `hug twp [object]`
- **Description**: Show tags which point directly at a specific object (defaults to HEAD). This answers "which tags point exactly to this commit?"
- **Example**: 
  ```shell
  hug twp              # Tags pointing at HEAD
  hug twp a1b2c3       # Tags pointing at specific commit
  ```
- **Safety**: Read-only query.

## Best Practices

- **Use annotated tags for releases**: Annotated tags (`hug ta`) are recommended for version releases because they include metadata about who tagged and when.
- **Use lightweight tags for temporary markers**: Lightweight tags (`hug tc`) are good for temporary bookmarks or personal references.
- **Never move or delete shared tags**: Once a tag is pushed and others have pulled it, avoid moving or deleting it. This causes confusion and breaks reproducibility.
- **Use semantic versioning**: Follow patterns like `v1.2.3` for consistent, sortable version tags.
- **Tag before pushing**: Create and verify your tag locally before pushing to remote.

## Tips

- List tags with patterns for specific versions: `hug t "v2.*"`
- Check what tags include a bugfix: `hug twc <bugfix-commit>`
- Before deleting a remote tag, notify your team
- Use `hug ts` to verify tag details before pushing
- Combine with `hug sh` to see what a tagged release contains: `hug sh v1.0.0`

See also: [Branching](branching) for branch management, [Commits](commits) for creating commits to tag, and [Logging](logging) for viewing tagged history.
