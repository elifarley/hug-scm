+++
title   = "Hug for AI agents: discovery, status, and pushing safely"
summary = "Cheatsheet for AI coding agents driving hug end-to-end."
order   = 20
+++

Hug is a direct replacement for git. It supports any git command AND ADDITIONAL commands.

## Common git-to-hug translations

| git command             | hug equivalent   |
|-------------------------|------------------|
| `git push`              | `hug bpush`      |
| `git add`               | `hug a`          |
| `git status`            | `hug s`          |
| `git log`               | `hug ll`         |
| `git merge --no-ff`     | `hug mkeep`      |


## CWD discipline: use `hug -C <dir>`

Keep hug commands self-documenting and CWD-independent. Pass the repo or
worktree directory with `-C` (works as in `git -C`) instead of `cd`-ing just to run a command.
The pattern to avoid is `cd <dir> && hug …`.
GOOD:
- `hug -C /my/repo ll`
- `hug -C /my/repo.WT.feat-1 s`
- `cd /my/repo-root.WT.feat-1` — then build / test / edit / hug there (working in a worktree)
- `cd /my/build-dir && make && ./run-tests` — several non-hug commands
BAD (never write these):
- `hug ll` (relies on CWD — could be an unexpected dir!)
- `cd /my/repo && hug ll` (cd-ing only to run a hug command — use `hug -C /my/repo ll` instead)

## Common flags

These conventions recur across hug commands; a command's own `-h` is authoritative.

- `-y` — auto-confirm routine (safe, recoverable) confirmations, for
  non-interactive agent use. Insufficient for dangerous operations; NOT a
  substitute for `-f`.
- `-f` / `--force` — authorize a **dangerous** operation (where `-y` is not
  enough). Exact scope is command-specific: selects force-with-lease on
  `hug bpush`, also overrides a dirty worktree on `hug wtdel`, skips the
  confirmation on a `hug h *` HEAD move. Check the command's `-h`.
- `--dry-run` — preview without acting. Supported by the destructive
  working-tree commands (`hug w discard-all`, `w-purge`, `w-wipe`, `w-zap`),
  worktree deletion (`hug wtdel`, `wtprune`), and `hug rb` (rebase with backup).
  NOT on `hug h *` HEAD moves or `hug bpush`: preview a HEAD move via its
  reset-equivalent (table below) plus `hug ss`/`hug su`, and a push via
  `hug llu`/`hug lol`.
- `-q` / `--quiet` — suppress the human-facing summary/chatter (stderr) for
  quieter automation.

## Discovery (use these first)

- `hug help @`: Best entry point — lists all categories
- `hug help <command>`: Full help for a top-level command (never truncate its output).
   - Includes a "see also" footer listing related commands. Always read it when a command is unfamiliar — it often surfaces a better fit.
   - Before running a related command for the first time, run `hug help` on it.
- To get help on *sub-commands* (NEVER use `--help`, ALWAYS `-h`):
   - `hug w get -h` - The top-level command is `w`. This gets help for its `get` sub-command.
   - `hug h back -h` ...

`hug help` has 4 discovery sigils that cover all discovery modes:

- `:article` — narrative articles (like this one)
- `/keyword` — fuzzy keyword search across command summaries
- `'!intent'` — natural-language intent search (e.g. `'!save my work in progress'`)
- `@category` — browse a whole command family

## Reading state

- `hug s`: one-line summary (ball color + counts)
- `hug ll [remote/<branch>] -N`: last N commits, one per line
- `hug llu [-N]`: outgoing commits (what would be pushed)
- `hug lol [-N]`: outgoing commits + file stats
- `hug sh HEAD`: details on the last commit
- `hug sh <committish>`: commit details + file stats
- `hug shp <committish>`: commit details + file stats + full patch

### Scriptable status queries

`hug s` prints human chatter to stderr and keeps stdout clean.
Query flags capture single fields to stdout for scripts:
- `branch=$(hug s -b)` (empty if detached)
- `upstream=$(hug s -u)` (empty if none)
- `remote_url=$(hug s -r)` (empty if none)
- `hash=$(hug s -H)`

| flag          | output                           |
|---------------|----------------------------------|
| -b, --branch  | current branch name              |
| -u, --upstream| Upstream tracking branch name    |
| -r, --remote  | URL of the tracking remote       |
| -H, --hash    | full HEAD hash                   |
| --ball        | Ball emoji w/ working-tree state |

Also:
- Count of Staged, Unstaged, untracKed and Ignored files: --staged, --unstaged, --untracked, --ignored
- Count of commits ahead and behind upstream: --ahead, --behind

Combine 2 or more: `hug s -b -H` prints branch then hash, tab-separated.

### CWD diff (staged + unstaged)

- `hug ss`: staged only
- `hug su`: unstaged only
- `hug sw`: staged + unstaged changes (both)

Pass `--stat` to show file stats only (no patch body).
Pass a single path to scope the diff to one file or directory.

### File listing — pick the right state

State alphabet for files:

- `S:*` — staged; substates: `Mod`, `Del`, `Ren`, `Add` (Add = previously untracked file that has been staged)
- `U:*` — unstaged; substates: `Mod`, `Del`, `Ren`
- `untrcK` — untracKed (not yet staged)
- `Ignore` — Ignored by `.gitignore`
- `Cnflt` — conflict

Listing commands:

- `hug sl`: S:* + U:*
- `hug sls`: S:* only  (e.g. `S:Del  tmp.log`)
- `hug slu`: U:* only
- `hug sla`: S:* + U:* + untrcK
- `hug slk`: untracked only  (e.g. `untrcK new-dir/`)
- `hug sli`: ignored only    (e.g. `Ignore __pycache__/`)

## Decoding the summary line

Commands like `hug s`, `hug sl`, and `hug sls` end with a summary line. Ex.:
    🟣 HEAD: f0bd63f 🌿main...origin/main [ahead 3] │ K:19 I:16592

- `K:` — count of untracKed files
- `I:` — count of Ignored files

Ball color encodes working-tree state (precedence: top → bottom):

| Color    | Meaning                              |
|----------|--------------------------------------|
| 🟡 Yellow | both staged AND unstaged changes     |
| 🔴 Red    | unstaged changes only                |
| 🟢 Green  | staged changes only                  |
| 🟣 Magenta| untracked files only                 |
| ⚫ Black  | ignored files only                   |
| ⚪ White  | clean repo                           |

- Yellow/Red/Green aren't affected by untracked and ignored files;
- Magenta isn't affected by ignored files;
- Untracked and ignored files are still counted in `K:`/`I:` regardless of which color shows.

## Staging, committing

- `hug a <file1> [<file2> ...]`: stage files
- `hug us <file1> [<file2> ...]`: unstage files

- `hug c -m "message"`: commit staged changes

## Amending

- `hug cmod -m "message"`: amend last commit with STAGED changes only (rewrites HEAD)
   - **Caution:** `cmod` only amends with staged changes, but in a dirty tree it's easy to have staged files you are not even aware of. That's why it's important to run `hug ss` before to list what's currently staged and run `hug us <file1> [<file2> ...]` to unstage files you don't want included.
   - If unrelated changes end up in the amended commit, recover with `hug h back 1 --force`, unstage unwanted files, and run `hug cmod --no-edit` again.
- `hug cmod --no-edit` — amend HEAD with staged changes only, doesn't change the commit message.
- **`cmod` is NEVER a read and has no safe preview form: it is a commit command.**
  Bare `hug cmod` (no -m/--no-edit/-C) is not a reliable no-op either — its
  behavior depends on the editor environment: with EDITOR set it opens an editor
  (closing it amends HEAD); with no EDITOR (dumb terminal, CI, many agent
  contexts) git errors "Terminal is dumb, but EDITOR unset" and leaves HEAD
  unchanged — but that's an error path, not a guarantee, and a
  backgrounded/detached editor can still let the amend proceed silently. So do
  not treat bare cmod as a read. For a DETERMINISTIC non-interactive amend, pass
  `--no-edit` (keep message) or `-m` (replace message). To INSPECT HEAD (which
  commit would be amended, its hash/message), use `hug s`, `hug s --short-hash`,
  or `hug sh HEAD` — never `cmod`.

Before running `cmod` (Commit MODify), ALWAYS run `hug s --short-hash` to check which commit is going to be amended (as HEAD may have moved).

## Commit vs amend (and how to recover)

Default to `hug c` when you mean "create a new commit from what is staged."
Only reach for `hug cmod` when you intend to **rewrite HEAD** (e.g. fixing a commit you just made before pushing).

**Anti-pattern:** running `hug cmod` when you meant `hug c`. The new work gets
folded into HEAD and rewrites history. Recover with `hug h back 1 --force`
(HEAD back one, keep changes staged — soft-reset semantics), then run `hug c -m "msg"`.

**Anti-pattern:** running `hug cmod` (especially bare, as a misguided "check
HEAD" / "touch HEAD" step) when you only wanted to READ state. On a *published*
branch this can silently diverge local `main` from `origin/main` (ahead 1,
behind N) and must never be pushed. If the amended commit's content already
exists on `origin/main`, recover by realigning local main to the remote:
`hug h rewind origin/main --force`. `hug h back 1 --force` is the WRONG recovery
here — it keeps the misfire's parent, not origin's tip. ⚠️ `rewind` runs
`git reset --hard` and destroys staged AND unstaged changes — so FIRST stash or
commit any unrelated dirty-tree work (`hug w stash` / `hug c`), THEN rewind, or
those changes are permanently lost. After rewinding, verify with `hug s`
showing ⚫ (no ahead/behind).

## HEAD vs working-directory operations — don't confuse them

- `hug h *` commands **move HEAD** to another commit (rewind/undo/rollback commits). They do not discard arbitrary uncommitted working-tree churn. `hug help @head` for the matrix.
- `hug w *` commands **change files** without touching HEAD (discard, restore, stash-as-wip). `hug w -h` for the matrix.

Equivalences:

| hug command      | git equivalent     | effect                               |
|------------------|--------------------|--------------------------------------|
| `hug h back`     | `git reset --soft` | HEAD moves, changes kept **staged**  |
| `hug h undo`     | `git reset --mixed`| HEAD moves, changes kept **unstaged**|
| `hug h rewind`   | `git reset --hard` | HEAD moves, **discard all**          |
| `hug h rollback` | `git reset --keep` | HEAD moves, discard commits' content, PRESERVE other uncommitted changes |

If a merge or fast-forward is blocked by dirty files, stash or use `hug w discard-all` — do not touch HEAD.

## Merging

- `hug mkeep <branch> [-m msg]`: like `git merge --no-ff`: always creates a merge commit
- `hug mff`: fast-forward only

## Pushing

**Always `hug bpush` with no branch argument.** `bpush` also works on first push without manual remote/branch spelling.
Arguments to `bpush` are `<remote-name>` or `<url>` (or both), NEVER a branch name. Never use `hug push` nor `git push`.

Use flag `--track` to set or switch upstream tracking to the target remote (default: preserve existing unless auto-setup applies).

Force-push variants exist, but default to the safe one:

- `hug bpush -f` — force-with-lease (safe; aborts if upstream moved)
- `hug bpush-unsafe` — unconditional force push; avoid unless you mean it


## Worktrees — never `git worktree`

**Always start branch-worthy work (spec/plan files, feature, bugfix, refactor, multi-step) in a new worktree — never a bare branch in the main checkout; it is the first step, before any other action.** WHY: isolation keeps the main checkout clean, enables parallel agent work, and stops half-finished edits from polluting the tree — critical for an autonomous agent.

- `hug wtc <branch> --new -y`: create new branch from HEAD + its worktree
- `hug wtc <branch> --base [remote/]<point> -y`: new branch from a start-point (branch/tag/ref); implies --new
- `hug wtc <branch> -y`: create worktree for an existing branch
- `hug wtl`: list all worktrees
- `hug wtl <search>`: filter by path/branch substring (OR logic)
- `hug wtl -b <branch>`: filter by exact branch name
- `hug wtdel <branch> --force`: delete worktree (add --with-branch to drop branch too)

Two hard rules: never `git worktree` (hard-blocked — use the `hug wt*` commands above); never pass an explicit path or `.worktrees/` (hug owns the canonical `<repo>.WT.<branch>` path). Base off an UP-TO-DATE integration branch (usually `origin/main`), not a stale local HEAD.

**Full ritual — skip conditions, provisioning, work-inside discipline, cleanup, subagents:** `hug help :worktree`.

## Where to go next

- `hug help :hug-101` — beginner walkthrough of the daily loop
- `hug help :worktree` — the full branch-worthy-work worktree ritual
- `hug help <command>` — full help for any specific command (mind its "see also" footer)
- Reach for the discovery sigils above (`@` `/` `'!'` `:`) to find anything this cheatsheet omits.
