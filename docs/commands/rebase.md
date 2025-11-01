# Rebase (r*)

Rebase commands in Hug help you **rewrite commit history**. The main goal is to maintain a clean, linear project timeline by re-applying your commits on top of another branch.

This is a powerful tool and should be used with care, especially on branches shared with others.

## Quick Reference

| Command | Memory Hook | Summary |
| --- | --- | --- |
| `hug rb` | **R**e**b**ase | Rebase the current branch onto another |
| `hug rbi` | **R**ebase **I**nteractive | Interactively edit commits in the current branch |
| `hug rba` | **R**ebase **A**bort | Abort a rebase in progress (safe escape) |
| `hug rbs` | **R**ebase **S**kip | Skip the current commit and continue |
| `hug rbc` | **R**ebase **C**ontinue | Continue rebase after **manual** conflict fix |
| `hug rbc-current` | **R**ebase **C**ontinue (with) **Current** | Resolve conflict with **current** version & continue |
| `hug rbc-other` | **R**ebase **C**ontinue (with) **Other** | Resolve conflict with **other** version & continue |

## Commands

### `hug rb <branch-name>`
-   **Description**: Updates your current branch by re-applying its commits on top of the latest commit from `<branch-name>`. This is the standard way to update a feature branch with the latest changes from `main`.
- **Example**:
  ```shell
  # While on 'my-feature', update it with the latest from 'main'
  hug rb main
  ```

-  **Safety**: **Never rebase a public branch** that others have pulled and are working on. This command can also cause merge conflicts if both branches modified the same files.

### `hug rbi <commit-ish>`
-   **Description**: Starts an **interactive rebase**, opening an editor with a list of commits from your branch. It allows you to clean up your history *before* merging by letting you `pick`, `reword`, `edit`, `squash`, `fixup`, or `drop` commits.
-   **Example**:
    ```shell
    # Interactively edit the last 3 commits
    hug rbi HEAD~3

    # Interactively edit all commits since branching from 'main'
    hug rbi main
    ```
-   **Safety**: This rewrites history. Use it only on local branches that you have not yet shared.

## Rebase Conflict Workflow

The following commands are used when a rebase is **paused** due to a merge conflict.

### `hug rba`
-   **Description**: This is your "undo" button. It completely **aborts** the entire rebase operation and returns your branch to the state it was in before you started.

### `hug rbc`
-   **Description**: After you have **manually** resolved a merge conflict (opened the files, edited them, and staged them with `hug a`), run this command to continue to the next commit.

### `hug rbs`
-   **Description**: Skips the current commit and continues with the rebase. This is rarely needed but can be useful if a commit's changes are no longer relevant.

---

> ### 💡 Key Concept: "Current" vs. "Other"
>
> When a rebase stops for a conflict, you must understand which version is which:
>
> * **Current**: The changes from the branch you are on and rebasing (e.g., `my-feature`). This is **your** code.
> * **Other**: The changes from the branch you are rebasing *onto* (e.g., `main`). This is the **incoming** code.
>
> Our `rbc-current` and `rbc-other` commands use this logic to resolve conflicts for you.

### `hug rbc-current [--all]`
-   **Description**: Resolves the *current* conflict by automatically choosing the version from your **current** (feature) branch.
-   **Behavior**:
    * **Without `--all`**: Resolves the *current* conflict with your changes, stages them, and **continues** to the next commit (which may also have conflicts).
    * **With `--all`**: Resolves the current conflict and applies the **same strategy** to all *future* conflicts in this rebase, allowing it to run to completion automatically.

### `hug rbc-other [--all]`
-   **Description**: Resolves the *current* conflict by automatically choosing the version from the **other** (target) branch (e.g., `main`).
-   **Behavior**:
    * **Without `--all`**: Resolves the *current* conflict with the incoming changes, stages them, and **continues** to the next commit.
    * **With `--all`**: Resolves the current conflict and applies the **same strategy** to all *future* conflicts, allowing it to run to completion automatically.
