# Cookbook: Practical Recipes

This page provides step-by-step solutions for common, real-world version control scenarios using Hug SCM. Use these recipes to handle complex tasks with confidence.

[[toc]]

## Recipe 1: Preparing a Feature for Pull Request

**Goal:** Clean up your local commit history before sharing it with your team.

**Scenario:** You've finished a feature on the `new-feature` branch. You have several "work-in-progress" commits that you want to combine into a single, clean commit.

1.  **Check Your Status**

    First, ensure your working directory is clean.
    ```shell
    hug s    # **S**tatus
    ```

2.  **Review Your Local Commits**

    Find out how many commits you are ahead of the `main` branch.
    ```shell
    # Shows commits in new-feature that are not in main
    hug l main..HEAD    # **L**og
    ```

3.  **Squash the Commits**

    Use `hug h squash` (**H**EAD **S**quash) to combine your local commits. Let's say you have 3 local commits.
    ```shell
    # This will move HEAD back 3 commits and recommit the changes
    # using the message from your most recent commit.
    hug h squash 3
    ```
    *Tip: For more complex history editing, use interactive rebase: `hug rbi main` (**R**ebase **I**nteractive)*

4.  **Push Your Cleaned Branch**

    Since you've rewritten history, you'll need to push with force. Use `bpushf` for a safe force-push.
    ```shell
    hug bpushf    # **B**ranch **Push** **F**orce
    ```
    Now your branch is ready to be reviewed in a Pull Request.

## Recipe 2: Finding and Reverting a Bug

**Goal:** Identify a commit that introduced a bug and safely undo it from the project's history.

**Scenario:** Users are reporting a bug in the login form that appeared sometime yesterday.

1.  **Search the History for Relevant Code**

    Use `hug lc` (**L**og **C**ode search) to find commits that modified the login logic.
    ```shell
    # Search for commits where the string "login" was added or removed
    hug lc "login" -- src/components/LoginForm.js
    ```

2.  **Inspect the Suspect Commit**

    Once you find a likely candidate (e.g., commit `a1b2c3d`), view its changes in detail.
    ```shell
    hug lp a1b2c3d -1 # **L**og with **P**atch for just that one commit
    ```

3.  **Revert the Commit**

    If you've confirmed this commit introduced the bug, revert it. This creates a *new* commit that undoes the changes from the bad one.
    ```shell
    hug revert a1b2c3d
    ```

4.  **Push the Fix**

    Push the new revert commit to your remote.
    ```shell
    hug bpush    # **B**ranch **Push**
    ```

## Recipe 3: Moving a Commit to Another Branch

**Goal:** You made a small commit on the wrong branch (`main`) and need to move it to a feature branch.

1.  **Get the Commit Hash**

    On the `main` branch, find the hash of the commit you made by mistake.
    ```shell
    hug l -1  # e.g., returns abc1234
    ```

2.  **Reset `main` Back to Its Previous State**

    Use `hug h back` (**H**EAD **Back**) to undo the commit but keep the changes staged.
    ```shell
    hug h back
    ```

3.  **Park the Changes**

    Use `hug w wip` (**W**ork **I**n **P**rogress) to save the staged changes on a temporary branch.
    ```shell
    hug w wip "Move this to the feature branch"
    # Note the WIP branch name, e.g., WIP/24-10-26/1530.movethis
    ```
    Your `main` branch is now clean.

4.  **Switch to the Correct Branch**

    ```shell
    hug b my-feature-branch    # **B**ranch
    ```

5.  **Unpark the Changes**

    Apply the changes from the WIP branch to your feature branch.
    ```shell
    hug w unwip WIP/24-10-26/1530.movethis    # **Un**park **W**ork **I**n **P**rogress
    ```
    The changes are now committed on the correct branch.

## Recipe 4: Updating Your Branch with the Latest from `main`

**Goal:** Keep your feature branch up-to-date with the `main` branch to avoid large merge conflicts later.

1.  **Commit Your Local Work**

    Make sure all your current work on the feature branch is committed.
    ```shell
    hug s    # **S**tatus
    hug caa -m "Save progress"    # **C**ommit **A**dd **A**ll
    ```

2.  **Fetch the Latest Changes**

    Get the latest updates from the remote, but don't merge them yet.
    ```shell
    hug fetch
    ```

3.  **Rebase Your Branch**

    Replay your local commits on top of the latest `main`. This maintains a clean, linear history.
    ```shell
    hug b main
    hug bpullr # **B**ranch **Pull** with **R**ebase
    ```
    *Or, if you already have `main` locally updated:*
    ```shell
    hug b main    # **B**ranch
    hug bpull    # **B**ranch **Pull**
    hug b my-feature-branch    # **B**ranch
    hug rb main    # **R**ebase
    ```

4.  **Resolve Conflicts (If Any)**

    If the rebase stops due to a conflict, open the conflicted files, edit them to resolve the issues, and then:
    ```shell
    hug a <conflicted-file>    # **A**dd
    hug rbc # **R**ebase **C**ontinue
    ```
    Repeat until the rebase is complete. If you get stuck, you can always abort with `hug rba` (**R**ebase **A**bort).
