# Working Directory (w*)

Working Directory commands in Hug help you manage, clean up, and restore changes in your local files. Prefixed with `w` for "working directory," they range from safe discards to nuclear cleanups, always with previews.

These build on Git's `reset`, `stash`, and `clean` but add intuitive names and safety layers.

## Quick Reference

| Command | Memory Hook                             | Summary                                                  |
| --- |-----------------------------------------|----------------------------------------------------------|
| `hug w discard` | **W**orking directory **D**iscard       | Discard unstaged or staged changes for paths             |
| `hug w discard-all` | **W**orking directory **discard **ALL** | Discard unstaged or staged changes across the repository |
| `hug w wipe` | **W**orking directory **W**ipe          | Discard uncommitted changes for paths                    |
| `hug w wipe-all` | **W**orking directory **W**ipe **ALL**  | Drop uncommitted changes in entire repo                  |
| `hug w purge` | **W**orking directory **P**urge         | Remove untracked or ignored files for paths              |
| `hug w purge-all` | **W**orking directory **P**urge **ALL** | Repo-wide purge of untracked/ignored files               |
| `hug w zap` | **W**orking directory **Z**ap           | Combine wipe + purge for paths                           |
| `hug w zap-all` | **W**orking directory **Z**ap **ALL**   | Full repo cleanup of tracked and untracked files         |
| `hug w wip` | **W**ork **I**n **P**rogress            | Park changes on dated WIP branch (pushable)              |
| `hug wips` | **W**ork **I**n **P**rogress **S**tay  | Park changes on new  WIP branch and stay on it           |
| `hug w unwip` | **Un**park **W**ork **I**n **P**rogress | Squash-merge WIP to current + delete                     |
| `hug w wipdel` | **W**ork **I**n **P**rogress **DEL**ete | Delete WIP branch (no integration)                       |
| `hug w backup` | **W**orking directory **B**ackup        | Stash tracked and untracked changes safely               |
| `hug w get` | **W**orking directory **G**et           | Restore files from a specific commit                     |

## Commands

### Discard Changes
Discard unstaged or staged changes without affecting untracked files.

- `hug w discard [-u|-s] <files...>`
  - **Description**: Discard unstaged (`-u`, default) or staged (`-s`) changes for specific files/paths.
  - **Example**:
    ```shell
    hug w discard file.js     # Discard unstaged changes in file.js
    hug w discard -s .        # Discard all staged changes
    ```
  - **Safety**: `--dry-run` to preview; requires `-f` to force.

- `hug w discard-all [-u|-s]`
  - **Description**: Repo-wide discard of unstaged or staged changes.
  - **Example**: `hug w discard-all -u` (default unstaged).

### Wipe Changes
Drop uncommitted changes (both staged and unstaged).

- `hug w wipe <files...>`
  - **Description**: Wipe staged + unstaged for specific files (tracked only).
  - **Example**: `hug w wipe src/*.js`

- `hug w wipe-all`
  - **Description**: Wipe all tracked files to clean state.
  - **Safety**: Confirmation required; `--dry-run` available.

### Purge Untracked
Remove untracked or ignored files (e.g., build artifacts).

- `hug w purge [-u|-i] <paths...>`
  - **Description**: Purge untracked (`-u`, default) or ignored (`-i`) files/paths.
  - **Example**: `hug w purge -i node_modules/`

- `hug w purge-all [-u|-i]`
  - **Description**: Repo-wide purge.
  - **Safety**: `--dry-run`; `-f` to skip prompts.

### Zap (Nuclear Cleanup)
Combines wipe + purge for full reset.

- `hug w zap <paths...>`
  - **Description**: Full cleanup (discard + purge) for paths.
  - **Example**: `hug w zap my-file` (careful!)

- `hug w zap-all`
  - **Description**: Complete repo reset - tracked to clean, untracked/ignored removed.
  - **Safety**: Always previews and confirms; use with caution.

### Utilities
- `hug w wip "<msg>"`
    - **Description**: Park all changes (staged/unstaged/untracked) on a new branch like `WIP/YY-MM-DD/HHmm.slug` with `[WIP] <msg>` commit. Working directory will be on the same branch as before, but clean, ready for tackling a more important task that just came in. Preferred over stashing for pushable, persistent saves of temp work.
    - **Example**: `hug wip "Draft feature"` → Resume: `hug b WIP/24-10-05/1430.draftfeature`; finish: `hug unwip WIP/24-10-05/1430.draftfeature` (squash-merges WIP to current branch and deletes WIP).

- `hug w wips "<msg>"`
  - **Description**: Park all changes (staged/unstaged/untracked) on a new branch like `WIP/YY-MM-DD/HHmm.slug` with `[WIP] <msg>` commit. Working directory will be on the new WIP branch so that you can *stay* on it for focused work. Preferred over stashing for pushable, persistent saves of temp work.
  - **Example**: `hug wips "Draft feature"` → continue editing immediately → finish: `hug b my-main-branch; hug unwip WIP/24-10-05/1430.draftfeature` (squash-merges to `my-main-branch` and deletes WIP branch).

- `hug w unwip [WIP_BRANCH]`
  - **Description**: Unpark by squash-merging WIP changes into the current branch as one commit, then deleting the WIP branch. Interactive if no branch specified (requires fzf).
  - **Example**: `hug unwip` (prompts to select); `--no-squash` for regular merge.
  - **Safety**: Previews changes; aborts on conflicts (resolve manually).

- `hug w wipdel [WIP_BRANCH]`
  - **Description**: Delete a WIP branch without integrating (for worthless/abandoned work). Safe if merged; `-f` to force.
  - **Example**: `hug wipdel WIP/24-10-05/1430.draftfeature`
  - **Safety**: Prompts if unmerged.

- `hug w get <commit> [files...]`
  - **Description**: Restore files from a specific commit to working directory.
  - **Example**: `hug w get HEAD~2 README.md` (gets from 2 commits ago)

  ### WIP Workflow Choices
  ::: tip When to Use `wips` vs. `wip`
    - **Use `wips` (--stay)**: When you want to dive deeper into temp/experimental work without switching contexts (e.g., prototyping a feature mid-session). It   keeps you on the isolated WIP branch for commits like `hug c "Refine prototype"`, then finish with `hug w unwip <wip>` (squash-merge + delete).
    - **Use `wip` (switch back)**: For brief pauses (e.g., handling a hotfix on main). Parks safely, returns you to your primary task, and lets you resume later   via `hug b <wip>`. Better for multi-tasking or team syncs, as WIP branches are pushable for backups.
    - **Contrast with Stash**: Both WIP variants are branch-based (versioned, shareable), unlike local-only stashes. Avoid stash for anything >1 hour—use `wips`   for persistence without cluttering main.
      :::

  **Full Flow Example (Deep Work with `wips`)**:
    1. `hug wips "Explore auth flows"` → Parks current changes, stays on `WIP/24-10-05/1430.exploreauthflows`.
    2. Edit more: `hug a . && hug c "Add OAuth integration"`.
    3. Pause/resume: `hug bs` (back to main), later `hug b WIP/...` to continue.
    4. Finish: `hug b main && hug w unwip WIP/...` (integrates as one commit).

## Tips
- Chain with status: `hug w discard file.js && hug sl`
- Restore from stash: Use [Stash Commands](status-staging#s*) like `hug sapply`.
- For undoing HEAD moves that affect working dir, see [HEAD Operations](head).
- For WIP: Park with `hug wip` (changes moved out of your way into a new WIP branch) or `hug wips` (changes moved to new WIP branch, working dir stays on it), resume with `hug b <wip>`, finish with `hug w unwip` or discard with `hug w wipdel`.
