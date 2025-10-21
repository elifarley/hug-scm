# Merge (m*)

Merge commands in Hug are used to integrate changes from one branch into another. Hug's merge commands often default to safer or cleaner strategies like squash merging. They are prefixed with `m` for "merge."

> [!TIP]
> Make sure to learn about the [WIP Workflow](working-dir.md#wip-workflow).
> It lets you park changes on a dedicated, dated branch that you can push, share, and resume safely.

## Quick Reference

| Command | Memory Hook | Summary                                                   |
| --- | --- |-----------------------------------------------------------|
| `hug m` | **M**erge (squash) | Squash-merge a branch into the current branch (no commit) |
| `hug mkeep` | **M**erge **Keep** commit | Perform a standard merge, creating a merge commit         |
| `hug mff` | **M**erge **F**ast-**F**orward | Fast-forward merge only (fails if not possible)           |
| `hug ma` | **M**erge **A**bort | Abort a merge in progress (after conflicts)               |

## Commands

### `hug m <branch-name>`
- **Description**: Performs a squash merge. It takes all the commits from `<branch-name>`, combines them into a single set of changes, and stages them in your current branch. You then need to run `hug c` to create a single, clean commit. This is great for keeping the main branch history tidy.
- **Example**:
  ```shell
  # On the 'main' branch
  hug m my-feature-branch
  hug c "Implement the new feature"
  ```
- **Safety**: Preserves a clean, linear history on the target branch. The original feature branch is not deleted automatically.

### `hug mkeep <branch-name>`
- **Description**: Performs a standard, non-fast-forward merge. This integrates the history of the feature branch into the target branch and always creates a new "merge commit". This is useful when you want to explicitly record the event of a merge.
- **Example**:
  ```shell
  # On the 'main' branch
  hug mkeep my-feature-branch
  ```

### `hug mff <branch-name>`
- **Description**: Performs a fast-forward merge. This is only possible if the target branch has not diverged from the feature branch. It simply moves the target branch pointer up to the tip of the feature branch without creating a merge commit.
- **Example**: `hug mff my-feature-branch`

### `hug ma`
- **Description**: Aborts a merge that has resulted in conflicts. This will return your working directory to the state it was in before you attempted the merge. It is the safe way to back out of a confusing merge.
- **Example**: `hug ma`
