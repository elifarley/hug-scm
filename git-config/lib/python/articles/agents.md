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

Force-push variants exist, but default to the safe one:

- `hug bpush -f` — force-with-lease (safe; aborts if upstream moved)
- `hug bpushf` — alias for the above
- `hug bpush-unsafe` — unconditional force push; avoid unless you mean it

## CWD discipline: use `hug -C <dir>`

Keep hug commands self-documenting and CWD-independent. Pass the repo or
worktree directory with `-C` instead of `cd`-ing just to run a command.

    hug -C /my/repo ll
    hug -C /my/repo.WT.feat-1 s

Plain `cd` is fine when entering a worktree to do real work there, but avoid
`cd /my/repo && hug ll` — it is fragile and unnecessary.

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
    hug llu [-N]                    # outgoing commits (what would be pushed)
    hug lol [-N]                    # outgoing commits + file stats
    hug sh <committish>             # commit details + file stats
    hug shp <committish>            # commit details + full patch
    hug sh HEAD                     # details on the last commit

### Scriptable status queries

`hug s` prints human chatter to stderr and keeps stdout clean. Query flags
capture single fields to stdout for scripts:

    branch=$(hug s -b)
    upstream=$(hug s -u)
    hash=$(hug s -H)

Available flags:

| flag            | output                                   |
|-----------------|------------------------------------------|
| `-b`, `--branch`| current branch name (empty if detached)  |
| `-u`, `--upstream`| remote tracking branch (empty if none) |
| `-H`, `--hash`  | full HEAD hash                           |
| `--short-hash`  | short HEAD hash                          |
| `--ahead`       | commits ahead of upstream                |
| `--behind`      | commits behind upstream                  |
| `--counts`      | ahead/behind as `+A -B`                 |
| `--ball`        | ball color (🟡🔴🟢🟣⚫⚪)               |
| `--staged`      | `true` if staged changes exist           |
| `--unstaged`    | `true` if unstaged changes exist         |
| `--untracked`   | `true` if untracked files exist          |
| `--ignored`     | `true` if ignored files exist            |

Combine: `hug s -b -H` prints branch then hash, tab-separated.
Use `-z` for NUL-separated machine-safe output.

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
    hug a                           # stage tracked files: modifications + deletions (NOT new/untracked)
    hug aa                          # stage everything, incl. new/untracked files (broad)

    hug c -m "message"              # commit staged changes
    hug cmod                        # amend last commit with STAGED changes only
    hug cmoda                       # amend last commit with ALL tracked changes

`hug aa` is the wide net. Reach for it deliberately, not by default.

### Commit vs amend

Default to `hug c` when you mean "create a new commit from what is staged."
Only reach for `hug cmod` when you intend to **rewrite HEAD** (e.g. fixing a
commit you just made before pushing).

- `hug cmod --no-edit` — amend HEAD with staged changes only, keep message.
  Preferred when unrelated files are also modified: stage just the intended
  files with `hug a`, then run this.
- `hug cmod -m "msg"` — amend HEAD with staged changes only, replace message.
- `hug cmoda --no-edit` — amend HEAD with all modified tracked files.
  ⚠️ Scope-expanding: it folds every tracked modification into the amended
  commit, including unrelated work. Only use when the tree is clean except for
  one logical change.

**Anti-pattern:** running `hug cmod` when you meant `hug c`. The new work gets
folded into HEAD and rewrites history. Recover with `hug h back 1 --force`
(HEAD back one, keep changes staged — soft-reset semantics), then run
`hug c -m "msg"`.

**Anti-pattern:** running `hug cmoda` in a tree with N unrelated changes. It
silently captures them all. Recover the same way: `hug h back 1 --force`, then
stage the files you actually want and use `hug cmod`.

## HEAD vs working-directory operations — don't confuse them

- `hug h *` commands **move HEAD** (rewind/undo/rollback commits). They do not
  discard arbitrary uncommitted working-tree churn.
- `hug w *` commands **change files** without touching HEAD (discard, restore,
  stash-as-wip).

**Common pitfall:** wanting to "discard dirty files before a fast-forward" and
reaching for `hug h back --force` — that moves HEAD back a commit and is not
what you wanted. For "discard uncommitted file changes, keep HEAD", use
`hug w discard-all` (or `hug w wip` to park changes on a side branch).

Equivalences:

| hug command                 | git equivalent        | effect on working tree                |
|-----------------------------|-----------------------|---------------------------------------|
| `hug h back [N] --force`    | `git reset --soft`    | HEAD back N, changes kept **staged**  |
| `hug h undo [N] --force`    | `git reset --mixed`   | HEAD back N, changes kept **unstaged**|
| `hug h rewind [N] --force`  | `git reset --hard`    | HEAD back N, **discard all**          |
| `hug h rollback [N]`        | —                     | HEAD back N, discard commits' content, preserve other uncommitted changes |

If a merge or fast-forward is blocked by dirty files, stash or use
`hug w discard-all` — do not touch HEAD.

## Merging

    hug mkeep <branch> [-m msg]     # merge --no-ff: always creates a merge commit
    hug mff                         # fast-forward only

Use `hug mkeep` instead of `git merge --no-ff`. The `-m` flag sets the merge
commit message.

## Worktrees — never `git worktree`

**Always start branch-worthy work (feature/bugfix/refactor/multi-step) in a new
worktree — never a bare branch in the main checkout.** Creating the worktree is
the first step, before any other action on the task. WHY: isolation keeps your
main checkout clean, enables parallel work, and stops half-finished edits from
polluting the tree — critical for an autonomous agent. Load the `/hug-worktree`
skill for the full ritual (guards, base-branch selection, cleanup).

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
or any explicit path to these commands. `-y` answers yes to routine
(safe, recoverable) confirmations — for non-interactive agent use, not a
substitute for `-f`.

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
- `hug help <command>` — full help for any specific command (mind its "see also" footer)
- Reach for the discovery sigils above (`@` `/` `'!'` `:`) to find anything this cheatsheet omits.
