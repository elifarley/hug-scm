+++
title   = "Hug for AI agents: discovery, status, and pushing safely"
summary = "Cheatsheet for AI coding agents driving hug end-to-end."
order   = 20
+++

# Hug for AI agents

This article is the portable version of the hug guidance any AI coding agent
needs regardless of external config. Covers every operation that differs from
raw git — commands you must use, commands you must never use, and exactly why.

## Two non-negotiables

**Always `hug`, never `git`.** The table below covers the highest-traffic
substitutions:

| git command             | hug equivalent   |
|-------------------------|------------------|
| `git push`              | `hug bpush`      |
| `git add`               | `hug a`          |
| `git status`            | `hug s`          |
| `git log`               | `hug ll`         |
| `git merge --no-ff`     | `hug mkeep`      |

**Always `hug bpush` with no branch argument.** `bpush` handles everything:
auto `-u` on first push, force-with-lease for safe force-push (`-f`), and
upstream switching (`-t`). Arguments to `bpush` are `<remote>` or `<url>`,
NOT a branch name. Never use `hug push` or `git push`.

## Discovery (use these first)

    hug help @                      # best entry point — lists all categories
    hug help <command>              # full help for a top-level command (never truncate)
    hug help <subcmd> -h            # sub-command help (ALWAYS -h, never --help)

`hug help <command>` includes a "see also" footer listing related commands.
Always read it when a command is unfamiliar — it often surfaces a better fit.

Four sigils cover all discovery modes:

- `:article` — narrative articles (like this one)
- `/keyword` — fuzzy keyword search across command summaries
- `'!intent'` — natural-language intent search (e.g. `'!save my work in progress'`)
- `@category` — browse a whole command family

## Reading state

    hug s                           # one-line summary (ball color + counts)
    hug ll [remote/<branch>] -N     # last N commits, one per line
    hug sh <committish>             # commit details + file stats
    hug shp <committish>            # commit details + full patch
    hug sh HEAD                     # details on the last commit

## CWD diff (staged + unstaged)

    hug sw                          # staged + unstaged changes (both)
    hug ss                          # staged only
    hug su                          # unstaged only

Pass `--stat` to show file stats only (no patch body). Pass a single path to
scope the diff to one file or directory.

## File listing — pick the right state

State alphabet for tracked files:

- `S:*` — staged; substates: `Mod`, `Del`, `Ren`, `Add` (Add = previously
  untracked file that has been staged)
- `U:*` — unstaged; substates: `Mod`, `Del`, `Ren`
- `untrcK` — untracked (not yet staged)
- `Ignore` — ignored by `.gitignore`
- `Cnflt` — conflicted (usually shown automatically)

Listing commands:

    hug sl                          # S:* + U:*
    hug sls                         # S:* only  (e.g. S:Del  tmp.log)
    hug slu                         # U:* only
    hug sla                         # S:* + U:* + untrcK
    hug slk                         # untracked only  (e.g. untrcK new-dir/)
    hug sli                         # ignored only    (e.g. Ignore __pycache__/)

## Staging, committing, amending

    hug a <files>                   # stage specific files (precise; prefer this)
    hug a                           # stage all tracked changes (modifications only, not deletions)
    hug aa                          # stage everything: new files, updates, deletions (broad)

    hug c -m "message"              # commit with message
    hug cmod                        # amend last commit (run `hug help cmod` for full set)

`hug aa` is the wide net. Reach for it deliberately, not by default.

## Merging

    hug mkeep <branch> [-m msg]     # merge --no-ff: always creates a merge commit
    hug mff                         # fast-forward only

Use `hug mkeep` instead of `git merge --no-ff`. The `-m` flag sets the merge
commit message.

## Worktrees — never `git worktree`

You MUST NEVER use `git worktree` for any operation. If you need a worktree
operation not covered below, report exactly what you need and stop — do not
attempt a raw git command.

    hug wtc <branch> --new -y       # create new branch from HEAD + its worktree
    hug wtc <branch> -y             # create worktree for an existing branch
    hug wtl                         # list all worktrees
    hug wtl <search>                # filter by path/branch substring (OR logic)
    hug wtl -b <branch>             # filter by exact branch name
    hug wtdel <branch> --force      # delete worktree (add --with-branch to drop branch too)

Worktrees land at a canonical path chosen by hug. Never pass `.worktrees/`
or any explicit path to these commands.

## Decoding the summary line

Commands like `hug s`, `hug sl`, and `hug sls` end with a summary line:

    🟣 HEAD: f0bd63f 🌿main...origin/main [ahead 3] │ K:19 I:16592

- `K:` — count of untracked files
- `I:` — count of ignored files

Ball color encodes working-tree state (precedence: top → bottom):

| Color    | Meaning                              |
|----------|--------------------------------------|
| 🟡 Yellow | both staged AND unstaged changes     |
| 🔴 Red    | unstaged changes only                |
| 🟢 Green  | staged changes only                  |
| 🟣 Magenta| untracked files only                 |
| ⚫ Black  | ignored files only                   |
| ⚪ White  | clean repo                           |

Yellow/Red/Green/Magenta override the entries below them. Untracked and
ignored files are still counted in `K:`/`I:` regardless of which color shows.

## Where to go next

- `hug help :hug-101` — beginner walkthrough of the daily loop
- `hug help <command>` — full help for any specific command
- `hug help @<category>` — browse a whole command family (e.g. `@branching`)
- `hug help /<keyword>` — fuzzy keyword search (e.g. `/undo`)
- `hug help '!<intent>'` — natural-language lookup (e.g. `'!save my work'`)
