# Core Concepts

Hug SCM isn't just a wrapper around Git; it's a philosophy for interacting with your repositories more safely and intuitively. Understanding these core concepts will help you get the most out of *Hug* and build a stronger mental model for version control.

> [!TIP]
> If you're a complete beginner, check [Hug for Beginners](hug-for-beginners.md)

[[toc]]

## Hug's Philosophy

Hug is built on three main principles:

1.  **Safety First**: Destructive operations should be difficult to perform accidentally. Hug uses confirmations (`-f` to force), previews (`--dry-run`), and safer defaults (like `h back` for a soft reset) to prevent data loss. The most destructive commands, like `h rewind`, have the longest names and strictest confirmations.
2.  **Intuitive Mnemonics**: Commands are grouped by prefixes that map to a specific area of Git (`h*` for HEAD, `w*` for Working Directory, etc.). Suffixes add specificity, making commands easy to remember (e.g., `hug bl` -> **B**ranch **L**ist).
3.  **Progressive Disclosure**: Simple commands (`hug s`) provide a high-level summary. More detailed commands (`hug sl`, `hug sla`...) reveal more information. This keeps your workflow clean and focused, allowing you to "zoom in" on details only when you need them.

## Key Git Concepts, Simplified by Hug

To make Git's abstract concepts more concrete, let's think of your repository as a **high-tech lab facility**. Hug provides a humane layer over Git's core components, which map directly to parts of your lab.

### The Three Areas of Your Lab

Git manages your code across three main areas. Hug's commands are designed to give you clear visibility and control over each one.

1.  **Working Directory**: These are the actual files on your filesystem.
    - **Lab Analogy**: This is your **main lab table**. It's your live, hands-on workspace where you edit files, add new ones, and delete old ones. Changes here are "live," but they haven't been officially recorded yet.
    - **Hug's View**: `hug su` (**S**tatus + **U**nstaged) shows you the "mess" on your lab table. `hug w discard` cleans it up.

2.  **The Index (Staging Area)**: A "holding area" where you prepare your next official record, known as a commit.
    - **Lab Analogy**: This is your lab's **preparation counter**. After completing an experiment on your lab table, you move the results (your changed files) here to be documented and stored.
    - **Hug's View**: `hug a` (**A**dd) and `hug aa` (**A**dd **A**ll) move files from the lab table to the preparation counter. `hug ss` (**S**tatus + **S**taged) shows you exactly what's on the counter. `hug us` moves things back to the lab table.

3.  **The Repository (Commits & HEAD)**: The permanent history of your project, made up of commits.
    - **Lab Analogy**: A **commit** is like a **labeled moment in your lab's security camera recording**. It's a permanent snapshot of your staged files at a specific point in time. **HEAD** is simply a pointer to the most recent recording you've made on your current timeline.
    - **Hug's View**: `hug c` (**C**ommit) takes everything on the preparation counter and creates that permanent snapshot. `hug l` lets you review the timeline of all your recordings. `hug h back` and `hug h undo` move the HEAD pointer back to an earlier recording.

### Branches: Your Lab Rooms

As your project grows, you might want to work on a new feature without disturbing the stable, working version of your code.

-   **Lab Analogy**: A **branch** is like having a **separate lab room** within your main facility. You can experiment with new ideas in this room without affecting the main project. If your experiment is successful, you can merge your findings back into the main room. If not, you can simply close off the room.

-   **Hug's View**:
    -   `hug bc new-feature`: Creates a new lab room called `new-feature` and immediately moves you into it.
    -   `hug b main`: Moves you out of your current room and back into the `main` lab room.
    - The files on your "lab table" (working directory) instantly swap to match the state of the new room you've entered.

### The WIP Workflow: A Better Way to Park Work

Other version control systems have a more convoluted "stash" feature that is a single, temporary holding area local to your machine. It can be lost if something happens to your computer.

Hug promotes the **[WIP (Work-In-Progress) workflow](commands/working-dir.md#wip-workflow)** as a safer, more robust alternative.

-   **What is it?** Instead of a stash, `hug wip` (**W**ork **I**n **P**rogress) creates a real, timestamped branch (`WIP/YY-MM-DD/HHmm.slug`). It commits all your current changes (staged, unstaged, and untracked) to this branch.

-   **Why is it better?**
    -   **Persistent & Safe**: A WIP branch is part of your repository's history. It won't get lost if you rebase or switch machines.
    -   **Shareable**: You can push a WIP branch (`hug bpush`) to a remote repository to back it up or get feedback from a teammate.
    -   **Versioned**: You can continue to work on a WIP branch, adding more commits to document your experiment or spike.
    -   **Clear**: `hug bl` (**B**ranch **L**ist) gives you a clear, descriptive list of all your parked tasks, unlike the cryptic lists from other tools.

The `wip` / `wips` / `unwip` / `wipdel` commands provide a complete, safe lifecycle for [managing temporary work](commands/working-dir.md#wip-workflow), making it one of Hug's cornerstone features.
