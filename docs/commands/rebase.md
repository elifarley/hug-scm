# Rebase (r*)

Rebase commands in Hug help you rewrite commit history to maintain a clean, linear project timeline. They are prefixed with `r` for "rebase" and are powerful tools that should be used with care, especially on shared branches.

## Quick Reference

| Command | Memory Hook | Summary |
| --- | --- | --- |
| `hug rb` | **R**e**b**ase | Rebase the current branch onto another |
| `hug rbi` | **R**ebase **I**nteractive | Interactively edit commits in the current branch |
| `hug rbc` | **R**ebase **C**ontinue | Continue a rebase after resolving conflicts |
| `hug rba` | **R**ebase **A**bort | Abort a rebase in progress |
| `hug rbs` | **R**ebase **S**kip | Skip a commit during a rebase |

## Commands

### `hug rb <branch-name>`
- **Description**: Re-applies the commits from your current branch onto the tip of `<branch-name>`. This is commonly used to update a feature branch with the latest changes from `main`.
- **Example**:
  ```shell
  # While on 'my-feature', update it with the latest from 'main'
  hug rb main
  ```
- **Safety**: Can cause conflicts if both branches have modified the same files. Never rebase a public branch that others have pulled.

### `hug rbi <commit-ish>`
- **Description**: Starts an interactive rebase. This opens an editor with a list of commits, allowing you to `pick`, `reword`, `edit`, `squash`, `fixup`, or `drop` them. It's a powerful tool for cleaning up local commit history before creating a pull request.
- **Example**:
  ```shell
  # Interactively rebase the last 3 commits
  hug rbi HEAD~3

  # Interactively rebase all commits since branching from 'main'
  hug rbi main
  ```
- **Safety**: Rewrites history. Use only on local branches that you have not yet shared.

### Rebase Workflow Commands

These commands are used when a rebase is paused, usually due to a merge conflict.

-   `hug rbc` (**R**ebase **C**ontinue)
    -   **Description**: After resolving a merge conflict during a rebase, stage the changes (`hug a`) and run this command to continue to the next commit.
-   `hug rba` (**R**ebase **A**bort)
    -   **Description**: Aborts the entire rebase operation and returns your branch to the state it was in before the rebase began. This is a safe escape hatch if you get stuck.
-   `hug rbs` (**R**ebase **S**kip)
    -   **Description**: Skips the current commit and continues with the rebase. This is rarely needed but can be useful if a commit is no longer relevant.
