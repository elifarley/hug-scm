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

## Recipe 5: Finding When a File Was Created (Using `fborn`)

**Goal:** Quickly discover when a file was originally added to the repository, even if it's been renamed multiple times.

**Scenario:** You're investigating an old file and want to know its origin story—when it was created and in what commit.

1.  **Use the Fast File Birth Command**

    `hug fborn` uses an efficient binary search to find the file's creation commit.
    ```shell
    hug fborn src/utils/validation.js
    ```

    This shows:
    - The commit hash where the file was first added
    - The commit date and author
    - The original filename (if renamed)

2.  **Review the Creation Context**

    Once you have the birth commit, see what else was added with it:
    ```shell
    # See the full commit details
    hug sh abc1234

    # See all files added in that commit
    hug shc abc1234
    ```

3.  **Trace the File's Evolution**

    After finding when it was born, follow its complete history:
    ```shell
    # Full file history (follows renames automatically)
    hug llf src/utils/validation.js

    # See all contributors to this file
    hug fcon src/utils/validation.js
    ```

**Why this is powerful:** Traditional `git log` can be slow for large repositories and requires careful `--follow` usage. `hug fborn` is optimized for this exact use case and works even across complex rename histories.

## Recipe 6: Investigating Changes from the Last Week (Temporal Queries)

**Goal:** Understand what changed in your repository over a specific time period without counting commits.

**Scenario:** It's Monday morning, and you want to see what your team accomplished last week.

1.  **See Files Changed in a Time Period**

    Use temporal flags instead of commit counts:
    ```shell
    # Files changed in last week
    hug h files -t "1 week ago"

    # Files changed since Friday
    hug h files -t "last friday"

    # Files changed in last 3 days
    hug h files -t "3 days ago"
    ```

2.  **View Commits in Date Range**

    Get detailed commit information for a specific period:
    ```shell
    # All commits from last week
    hug l --since="1 week ago"

    # Commits in specific date range
    hug ld "2024-01-15" "2024-01-22"

    # Or using relative dates
    hug ld "last monday" "last friday"
    ```

3.  **Search Within Time Period**

    Combine temporal queries with search:
    ```shell
    # Bug fixes from last month
    hug lf "fix" --since="1 month ago"

    # Code changes to authentication in last 2 weeks
    hug lc "authenticate" -t "2 weeks ago"
    ```

4.  **Author Activity in Time Period**

    See what specific developers worked on:
    ```shell
    # All commits by Alice last week
    hug lau "Alice" --since="1 week ago"

    # Bob's work this month
    hug lau "Bob" --since="1 month ago" --until="now"
    ```

**Pro tip:** Temporal queries are more intuitive than counting commits and work great for sprint reviews, weekly updates, or debugging "when did this break?"

## Recipe 7: Safely Experimenting with Automatic Backups

**Goal:** Try destructive operations confidently, knowing you have automatic safety nets.

**Scenario:** You want to squash commits or rewind HEAD but you're nervous about losing work.

1.  **Know That Backups Are Automatic**

    Hug automatically creates backup branches for destructive HEAD operations:
    ```shell
    # Before squashing, note your current commit
    hug l -1

    # Squash last 5 commits (auto-creates backup!)
    hug h squash 5
    ```

2.  **Check Your Backups**

    List all automatic backup branches:
    ```shell
    # Find backup branches
    hug bl | grep backup

    # Or more specifically
    hug bl | grep "hug-backup"
    ```

3.  **Recover If Something Goes Wrong**

    If you're not happy with the result:
    ```shell
    # Switch to the backup branch
    hug b hug-backup-20240122-153045

    # Verify it's what you want
    hug l -5

    # Restore your original branch to the backup
    hug b my-feature-branch
    git reset --hard hug-backup-20240122-153045
    ```

4.  **Try Dry-Run First**

    Most destructive commands support preview mode:
    ```shell
    # Preview what would be deleted
    hug w zap-all --dry-run

    # Preview what would be squashed
    hug h squash 3 --dry-run

    # Preview rollback impact
    hug h rollback --dry-run
    ```

5.  **Clean Up Old Backups**

    After you're confident everything is good:
    ```shell
    # Delete old backup branches
    hug bdel hug-backup-20240115-123456

    # Or force delete if needed
    hug bdelf hug-backup-20240115-123456
    ```

**Why this matters:** Automatic backups remove the fear from history rewriting. You can experiment freely, knowing you can always get back to your previous state.

## Recipe 8: Finding What You're About to Push (Unpushed Changes)

**Goal:** Review exactly what commits and files you're about to share with your team before pushing.

**Scenario:** You've been working locally and want to see what will be pushed to the remote.

1.  **Quick Overview**

    See unpushed commits in compact form:
    ```shell
    # Short log of outgoing commits
    hug lo

    # Or detailed version
    hug lol  # **L**og **O**utgoing **L**ong
    ```

2.  **See Changed Files**

    Review which files are in your unpushed commits:
    ```shell
    # Files in commits not yet pushed
    hug h files -u

    # The -u flag means "upstream" comparison
    ```

3.  **Detailed Review**

    Get full details of what you're about to push:
    ```shell
    # All unpushed commits with details
    hug ll @{u}..HEAD

    # With patches
    hug lp @{u}..HEAD
    ```

4.  **Count Your Commits**

    How many commits ahead are you?
    ```shell
    # Check branch status
    hug b  # Shows "ahead by N commits"

    # Or count manually
    hug l @{u}..HEAD --oneline | wc -l
    ```

5.  **Verify Before Pushing**

    Final checks before sharing:
    ```shell
    # Review commit messages
    hug ll @{u}..HEAD

    # Check for debug code or secrets
    hug h files -u  # Review file list
    git diff @{u}..HEAD | grep -i "console.log\|debugger\|TODO"

    # When satisfied, push
    hug bpush
    ```

**Pro tip:** Make reviewing unpushed changes part of your routine before every push. It catches embarrassing commits before they're public!

## Recipe 9: Interactive File Selection for Precision Work

**Goal:** Use Gum's visual interface to select exactly which files to operate on, avoiding command-line typos.

**Scenario:** You have many modified files but only want to stage, discard, or search specific ones.

1.  **Interactive File Staging**

    Select files visually instead of typing paths:
    ```shell
    # Interactive file selection for staging
    hug a --

    # Gum shows a list of modified files
    # Use arrow keys to select, space to mark, enter to confirm
    ```

2.  **Interactive File Discarding**

    Choose which changes to discard safely:
    ```shell
    # Select files to discard
    hug w discard --

    # Gum shows modified files
    # Mark the ones you want to discard
    # Confirmation prompt before executing
    ```

3.  **Interactive Search**

    Search code changes in specific files:
    ```shell
    # Search with file selection
    hug lc "functionName" --

    # Gum shows file list (current directory by default)
    # Select which file to search in

    # Or search across entire repository
    hug lc "functionName" --browse-root
    ```

4.  **Scope Control**

    By default, interactive selection is scoped to current directory:
    ```shell
    # Current directory scope (default)
    cd src/components/
    hug lc "import" --  # Only shows files in src/components/

    # Full repository scope
    hug lc "import" --browse-root  # Shows all files in repo
    ```

5.  **Other Interactive Operations**

    Many commands support interactive mode:
    ```shell
    # Select branch to delete
    hug bdel --

    # Select branch to switch to
    hug b --

    # Select files for blame
    hug fblame --
    ```

**Note:** Interactive selection requires [Gum](https://github.com/charmbracelet/gum) to be installed. Hug gracefully falls back to manual file specification if Gum isn't available.

## Recipe 10: Precise History Navigation with `h steps`

**Goal:** Safely rewind to exactly when a file last changed, without counting commits manually.

**Scenario:** You want to undo changes to a specific file but don't know how far back to go.

1.  **Find How Many Steps Back**

    Let Hug calculate the steps for you:
    ```shell
    # How many commits since this file changed?
    hug h steps src/auth/login.js
    ```

    Output might show: "File last changed 3 steps back from HEAD"

2.  **Rewind Precisely**

    Use that number to rewind exactly to that point:
    ```shell
    # Go back exactly 3 commits
    hug h back 3

    # Or undo those 3 commits
    hug h undo 3

    # Or rollback if you want to discard changes
    hug h rollback 3 --dry-run  # preview first
    hug h rollback 3            # then execute
    ```

3.  **Combine with Other Files**

    Check multiple files to find the right rewind point:
    ```shell
    # Check several related files
    hug h steps src/auth/login.js    # 3 steps back
    hug h steps src/auth/session.js  # 5 steps back
    hug h steps src/auth/token.js    # 2 steps back

    # Need to go back to when all were last modified
    hug h back 5  # Go back to oldest change
    ```

4.  **Verify Before Acting**

    Always check what you're about to undo:
    ```shell
    # See what's in those commits
    hug l -5

    # See files changed in that range
    hug h files 5

    # If it looks right, proceed
    hug h back 5
    ```

**Why this is useful:** Instead of manually counting commits with `hug l` and matching timestamps to file changes, `hug h steps` does the calculation instantly. Perfect for precise history navigation.
