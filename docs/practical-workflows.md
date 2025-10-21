# Practical Workflows with Hug SCM

You've learned the basics of version control with the [Beginner's Guide](hug-for-beginners.md) and understand concepts like commits and branches. Now, it's time to level up. This guide shows you how to combine Hug's commands into fluid, powerful workflows that you'll use every day in a professional development environment.

We'll structure this guide around the typical lifecycle of building a feature, from a fresh branch to a clean merge.

[[toc]]

::: info Mnemonic Legend
- **Bold letters** in command names highlight the initials that make each alias (for example, `hug sl` → **S**tatus + **L**ist).
- For deep dives on specific commands, refer to the command reference pages (e.g., `[Working Directory (w*)](commands/working-dir.md)`).
:::

## The Core Development Cycle

This workflow is the backbone of most feature development.

### 1. Starting a New Task

**Scenario:** You're about to start work on a new feature, "user-authentication". First, you need a clean, up-to-date branch.

**Workflow:**
1.  **Switch to the main branch**: `hug b main`
2.  **Get the latest updates**: `hug bpullr` (**B**ranch **Pull** with **R**ebase)
3.  **Create your feature branch**: `hug bc feature/user-authentication` (**B**ranch **C**reate`)
 
**Why it works:** This sequence ensures you start from the most recent version of the main branch, which helps prevent merge conflicts later. Using `bpullr` maintains a clean, linear project history.

### 2. The "Inner Loop": Code, Commit, Repeat

This is where you'll spend most of your time: writing code and saving progress. The goal is to make small, logical "atomic" commits.

**Scenario:** You've implemented the login form and want to commit it.

**Workflow:**
1.  **Check your status**: `hug sla` (**S**tatus **L**ist **A**ll) to see tracked and untracked files.
2.  **Review your changes**: `hug sw` (**S**tatus **W**orking diff) shows a combined diff of everything.
3.  **Stage your changes**:
    *   For everything: `hug aa` (**A**dd **A**ll)
    *   For just one part of a file: `hug ap` (**A**dd **P**atch) for an interactive staging session.
4.  **Commit**: `hug c "feat: Add user login form"`
 
#### Handling Interruptions: The WIP Workflow
**Scenario:** You're in the middle of a complex change when an urgent bug report comes in. You can't commit your broken code, but you can't lose it either. This is what the WIP (Work-In-Progress) workflow is for.
 
**Workflow:**
1.  **Park your current work**: `hug wip "Refactoring user model"`
    *   This command takes all your changes (staged, unstaged, and untracked), commits them to a new, dated WIP branch, and cleans your working directory. You remain on your original feature branch.
2.  **Switch to a hotfix branch**: `hug b main && hug bc hotfix/urgent-bug`
3.  **Fix the bug, merge it, and return**: `# ... do the work ...`
4.  **Resume your work**: `hug b feature/user-authentication` and then `hug w unwip`. Select the WIP branch you created.
    *   This squash-merges the work from the WIP branch back into your feature branch, restoring your changes so you can continue where you left off.
 
The WIP workflow is a safer, more robust alternative to `git stash`. See the [WIP Workflow Guide](commands/working-dir.md#wip-workflow) for more details.
 
#### Fixing Your Last Commit
**Scenario:** You just committed, but you forgot to include a file, or you made a typo in the commit message.
 
**Workflow:**
1.  **Stage the missing file**: `hug a forgotten-file.js`
2.  **Amend the previous commit**: `hug cm` (**C**ommit **M**odify)
    *   This opens your editor with the last commit message, allowing you to edit it. When you save and close, the staged changes will be added to that commit instead of creating a new one. This keeps your history clean.
 
### 3. Preparing for Review
**Scenario:** Your feature is complete! Before you create a pull request, you want to clean up your commit history. You might have several "WIP" or "fixup" commits that should be combined into one or two logical commits.
 
**Workflow:**
1.  **Sync with the main branch**: `hug bpullr` to pull the latest changes from `main` and rebase your work on top. This is the best time to resolve any conflicts.
2.  **Start an interactive rebase**: `hug rbi main` (**R**ebase **I**nteractive)
    *   This opens an editor with a list of all the commits you've made on your feature branch.
    *   You can reorder them, `reword` their messages, `squash` them into the commit above them, or `fixup` (squash without keeping the message).
3.  **Push your clean branch**: `hug bpushf` (**B**ranch **Push** **F**orce)
    *   Because you've rewritten history with rebase, a normal push will be rejected. A force push is required. **Only do this on your own feature branch that no one else is using.**
 
### 4. Merging and Cleaning Up
**Scenario:** Your pull request has been approved and merged!
 
**Workflow:**
1.  **Switch to main and update**: `hug b main && hug bpull`
2.  **Delete your local feature branch**: `hug bdel feature/user-authentication` (**B**ranch **DEL**ete)
3.  **Delete the remote feature branch**: `hug bdelr feature/user-authentication` (**B**ranch **DEL**ete **R**emote)
 
## Specialized Workflows
 
### Investigating History
**Scenario:** A bug was introduced recently, and you need to find out when and why.
 
**Workflow:**
*   **Find the last change to a file**: `hug llf <file> -1` shows the most recent commit that touched a file, even if it was renamed.
*   **Search commit messages**: `hug lf "keyword"` searches all commit messages for a term.
*   **Search code changes (the "pickaxe" search)**: `hug lc "functionName"` finds commits where `functionName` was added or removed.
*   **See who changed what**: `hug fblame <file>` shows the author of every line in a file.
 
### Undoing Mistakes Safely
There are two main ways to undo work, depending on whether the mistake is public (pushed) or private (local).
 
*   **Local Mistake: "I just made a bad commit on my machine."**
    *   **Solution**: `hug h back` (**H**EAD **B**ack). This moves the branch pointer back one commit but **keeps your changes staged**. You can edit them and re-commit correctly. It's the safest way to undo a local commit.
    *   Use `hug h undo` to do the same, but leave the changes in your working directory (unstaged).
 
*   **Public Mistake: "I pushed a commit that broke the build."**
    *   **Solution**: `hug revert <commit-hash>`. This creates a *new* commit that is the exact opposite of the bad commit.
    *   This is the safe way to undo public changes because it doesn't rewrite history. Anyone who has already pulled the bad commit can simply pull the new revert commit to fix their local repository. After reverting, just `hug bpush`.
