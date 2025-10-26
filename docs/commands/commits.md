# Commits (c*)

The `c*` commands handle creating and modifying commits, making it easier to record changes in your repository.

## Quick Reference

| Command   | Memory Hook                           | Summary                                            |
|-----------|---------------------------------------|----------------------------------------------------|
| `hug c`   | **C**ommit staged                     | Commit staged changes                              |
| `hug ca`  | **C**ommit **A**ll tracked            | Commit ALL tracked changes                         |
| `hug caa` | **C**ommit **A**dd **A**ll            | Stage and commit ALL changes (tracked + untracked) |
| `hug cm`  | **C**ommit **M**odify                 | Modify last commit with staged changes only        |
| `hug cma` | **C**ommit **M**odify **A**ll tracked | Modify last commit with all tracked changes        |
| `hug cc`  | **C**ommit **C**opy (or cherry-pick)  | Copy a commit from another branch onto HEAD        |

## hug c (Commit staged)

Commit staged changes.

**Usage:** `hug c [options]`

**Examples:**
```shell
hug c # A text editor will be shown so that you can add a message
hug c -m "Fix typo in README"
```

This is a safe way to commit, ensuring only staged files are included.

To preview what would be committed, run `hug sl` for a list of changed files or `hug ss` for a diff of staged changes.

## hug ca (Commit All tracked)

Commit all tracked changes.

**Usage:** `hug ca`

**Examples:**
```shell
hug ca # A text editor will be shown so that you can add a message
hug ca -m "Fix typo in README"
```

This is a quick way to commit without having to add files to the staging area first.
Useful if you know that ALL tracked files must be committed.

## hug caa (Commit Add All)

Stage all untracked changes and commit (tracked and untracked).

**Usage:** `hug caa`

**Examples:**
```shell
hug caa -m "Add new feature with all related files"
```

Stages all current changes (staged and unstaged) and creates a new commit.
It is a convenient shortcut for `hug aa && hug c`.

## hug cm (Commit Modify)

Modify the last commit with staged changes.

This command allows you to add staged changes to the previous commit without creating a new one. It's ideal for fixing small mistakes or adding forgotten files.

When you run `hug cm` (**C**ommit **M**odify) without flags, your editor will open with the previous commit message already populated. This is very convenient if you just need to fix a typo or slightly reword the message.

If you want to replace the old message entirely, you can provide a new one directly with the `-m` flag, which avoids opening the editor.

**Usage:** `hug cm`

**Examples:**
```shell
# Realize you forgot to add a file to the last commit
hug a docs/forgotten-file.md
# Open the editor to see the last message and confirm or tweak it
hug cm

# Or... Replace the last commit message entirely without opening the editor
hug cm -m "A completely new and corrected commit message"
```

## hug cma

Modify the last commit with all tracked changes.

Similar to `hug cm` (**C**ommit **M**odify), this command modifies the last commit.
However, it automatically includes all changes to **ALL tracked files**, so you don't need to stage them first.

Running `hug cma` opens your editor with the existing commit message, making it perfect for small edits. To replace the message entirely without opening the editor, use the `-m` flag.

Usage: `hug cma`

**Examples:**
```shell
# After committing, you make a quick change to a file you just committed
# Open the editor to adjust the commit message
hug cma

# Modify and provide a new message in one step
hug cma -m "Add new feature (with all files)"
```

## hug cc (Commit Copy)

Copy a commit from another branch onto the current branch (cherry-pick).

**Usage:** `hug cc <commit>`

**Examples:**
```shell
hug cc a1b2c3d4  # Apply the changes from commit a1b2c3d4 to the tip (HEAD) of the current branch
```

Applies the changes from a specific commit on top of the current HEAD, creating a new commit on the current branch. `hug` also adds the original commit hash to the new commit message for reference. This is useful for bringing a specific bug fix or feature from one branch to another without merging the entire source branch.

## Tips
- Use `hug s` (**S**tatus) or `hug sl` (**S**tatus + **L**ist) to check what you are about to commit, especially before using `hug c` (**C**ommit).
- `hug ca` (**C**ommit **A**ll tracked) and `hug caa` (**C**ommit **A**dd **A**ll) are great for speed, but be sure you want to commit *all* changes. For more selective commits, stage files individually with `hug a` (**A**dd) or `hug aa` (**A**dd **A**ll) and then use `hug c` (**C**ommit).
- Use `hug cm` (**C**ommit **M**odify) or `hug cma` (**C**ommit **M**odify **A**ll tracked) to fix mistakes in your last commit (e.g., forgotten changes or typos in the message) without creating extra "fixup" commits. This keeps your history cleaner.

> [!WARNING]
> Avoid using `hug cm` (**C**ommit **M**odify) or `hug cma` (**C**ommit **M**odify **A**ll tracked) on commits that have already been pushed to a remote repository (like GitHub).
> Modifying a commit rewrites history, which can create significant problems for anyone who has already pulled your changes.
