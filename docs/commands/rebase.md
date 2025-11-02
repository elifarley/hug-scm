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

## Initiating a Rebase

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

> [!TIP] 💡 Key Concept: "Current" Branch vs. "Other" Branch
> When a rebase stops for a conflict, you must understand which version is which:
>
> - **Current** Branch: The changes from the branch you are on and rebasing (e.g., `my-feature`). This is **your** code.
> - **Other** Branch: The changes from the branch you are rebasing *onto* (e.g., `main`). This is the **incoming** code.
>
> Our `rbc-current` and `rbc-other` commands use this logic to resolve conflicts for you.

The following commands are used when a rebase is **paused** due to a conflicting commit.

### `hug rba`
-   **Description**: This is your "undo" button. It completely **aborts** the entire rebase operation and returns your branch to the state it was in before you started.

### `hug rbc`
-   **Description**: After you have **manually** resolved a merge conflict (opened the files, edited them, and staged them with `hug a`), run this command to continue to the next commit.

### `hug rbs`
-   **Description**: Skips the current commit and continues with the rebase. This is rarely needed but can be useful if a commit's changes are no longer relevant.

### `hug rbc-current [--all]`
-   **Description**: Resolves a conflicting commit by automatically choosing the version from your **current** branch.
-   **Behavior**:
    - **Without `--all`**: Resolves all conflicts in *one* commit with **your** changes, stages them, and **continues** to the next commit (which may also have conflicts).
    - **With `--all`**: Resolves all conflicts in **ALL** conflicting commits of this rebase operation, applying the **same strategy** to them all, allowing it to run to completion automatically.

### `hug rbc-other [--all]`
-   **Description**: Resolves a conflicting commit by automatically choosing the version from the **other** (target) branch (e.g., `main`).
-   **Behavior**:
    - **Without `--all`**: Resolves all conflicts in *one* commit with the **incoming** changes, stages them, and **continues** to the next commit (which may also have conflicts).
    - **With `--all`**: Resolves all conflicts in **ALL** conflicting commits of this rebase operation, applying the **same strategy** to them all, allowing it to run to completion automatically.

## Resolving Conflicts with `rbc-current` and `rbc-other`

Here's a practical guide to using these powerful aliases. Our demo repo has a special branch, `feature/rebase-conflict-demo`, created specifically for this tutorial.

### Step 1: Set Up the Scenario

First, let's get into the right state. We'll start a rebase that we know will cause a conflict.

```shell
# Switch to the feature branch
hug b feature/rebase-conflict-demo

# Attempt to rebase it on top of main
hug rb main
```

This will fail, and you'll see a message like this, indicating a conflict in `conflict.txt`:

```
CONFLICT (content): Merge conflict in conflict.txt
error: could not apply fa4f2bf... feat: Modify conflict file on feature branch
hint: Resolve all conflicts manually, mark them as resolved with
hint: "hug a <conflicted_files>", then run "hug rbc".
hint: See "git help rebase" for details.
```

### Step 2: Choose a Resolution Strategy

Now, you have a choice. Do you want to keep the version of the file from your feature branch (`current`) or the version from `main` (`other`)?

#### Option A: Keep Your Changes with `rbc-current`

If you want to resolve the conflict by keeping the changes from your current branch (`feature/rebase-conflict-demo`), use `rbc-current`.

```shell
hug rbc-current
```

The rebase will complete successfully. If you check the contents of the file, you'll see it contains the text from your feature branch:

```shell
$ cat conflict.txt
This is a line from the feature branch.
```

#### Option B: Take Incoming Changes with `rbc-other`

If you made a mistake, you can always undo the rebase and try again.

```shell
# Undo the last operation (the rebase)
hug undo

# Now, let's try again, but this time we'll keep the 'other' version
hug rb main
# ... conflict message appears again ...

hug rbc-other
```

Now the rebase is complete. If you inspect the file, it will have the version from the `main` branch:

```shell
$ cat conflict.txt
This is a line from the main branch.
```

By using these commands, you can resolve rebase conflicts in a single step without manually opening files.
