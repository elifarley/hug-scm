# Tagging (t*)

Tagging commands in Hug are for creating, listing, and managing release markers or important milestones in your project's history. They are prefixed with `t` for "tag."

## Quick Reference

| Command | Memory Hook | Summary |
| --- | --- | --- |
| `hug t` | **T**ags list | List all tags |
| `hug tc` | **T**ag **C**reate | Create a lightweight tag |
| `hug ta` | **T**ag **A**nnotated | Create an annotated (detailed) tag |
| `hug tpush` | **T**ag **Push** | Push a specific tag to the remote |
| `hug tpusha`| **T**ag **Push** **A**ll | Push all tags to the remote |

## Commands

### `hug t`
- **Description**: Lists all existing tags, sorted by version number by default.
- **Example**: `hug t`

### `hug tc <tag-name>`
- **Description**: Creates a lightweight tag. This is a simple pointer to a specific commit and contains no extra information.
- **Example**: `hug tc v1.0.1`

### `hug ta <tag-name> "<message>"`
- **Description**: Creates an annotated tag. This is recommended for official releases, as it is a full object in the Git database that includes the tagger's name, email, date, and a message.
- **Example**: `hug ta v1.0.0 "Initial stable release"`

### `hug tpush <tag-name>`
- **Description**: Pushes a single, specific tag to the `origin` remote. By default, `git push` does not send tags.
- **Example**: `hug tpush v1.0.0`

### `hug tpusha`
- **Description**: Pushes all of your local tags to the `origin` remote.
- **Example**: `hug tpusha`
