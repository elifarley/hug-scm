# Hug CLI Reference for Shell Completions

This document provides a complete reference of the Hug tool's command structure, subcommands, options, and arguments. Hug is a Git enhancement tool that wraps `git` commands via aliases in `.gitconfig` and additional executable scripts in `bin/` (named `git-*`). 

When `hug` is invoked, it acts as a thin wrapper around `git` (via `exec git "$@"`), redirecting `hug help` to `git hughelp`. Thus:
- Standard Git commands (e.g., `hug status`, `hug log`) use Git's native completions.
- Aliases from `.gitconfig` (e.g., `hug l` for `log --oneline --graph --decorate --color`) are completable as top-level commands.
- Custom scripts (e.g., `hug w discard`) provide additional top-level commands like `w`, `h`, `c`, etc., with their own substructures.

For shell completions (Bash, Fish, Zsh, etc.):
- Complete top-level commands from the lists below.
- For alias-based commands, complete as Git subcommands (use Git's completion logic, but suggest based on alias names).
- For custom scripts, complete subcommands, then options, then arguments (e.g., files, commits, branches).
- Arguments like files, commits, branches/tags/remotes can use Git's standard completion (e.g., `git ls-files`, `git rev-parse --symbolic`, `git branch`, `git tag`, `git remote`).
- Options are typically short (`-f`) or long (`--force`), case-sensitive.
- Positional arguments are required unless noted as optional (`[...]`).
- No commands take `--help` as a subcommand; use `-h` or `--help` flags where supported.
- All commands assume a Git repository context (fail outside one).
- Dynamic completions: For file paths, suggest from `git ls-files` or `git status --porcelain`; for commits, use `git rev-parse --short`; etc.

## 1. Alias-Based Commands (from .gitconfig)
These are top-level commands defined as Git aliases. Complete them as static words. Some are shell functions (`!f() { ... }`) that accept arguments (e.g., search terms, files, commits). Pass-through options are Git-native.

### Discoverability
- `alias [pattern]`: Show Git aliases (optionally filtered). Args: `[pattern]` (optional string).

### Logging (l*)
- `l [git-log-opts]`: `log --oneline --graph --decorate --color`. Args: Git log options.
- `ll [git-log-opts]`: `log --graph --pretty=log1 --date=short`. Args: Git log options.
- `la [git-log-opts]`: Log all branches. Args: Git log options.
- `lo`: Log outgoing changes (quiet mode, alias for `log-outgoing --quiet`). No args.
- `lol`: Log outgoing changes (verbose mode, alias for `log-outgoing`). No args.
- `llf <file> [-p] [git-log-opts]`: Log commits to a file (with optional patches). Args: `<file>` (required), `[-p]` (show patches), Git log options.
- `llfp <file> [git-log-opts]`: Log file with patches. Args: `<file>` (required), Git log options.
- `llfs <file> [git-log-opts]`: Log file stats. Args: `<file>` (required), Git log options.
- `lf <search-term> [-i] [-p] [--all] [git-log-opts]`: Search commits by message. Args: `<search-term>` (required), `[-i]` (ignore case), `[-p]` (patches), `[--all]`, Git log options.
- `lc <search-term> [-i] [-p] [--all] [-- <file>] [git-log-opts]`: Search by code changes. Args: `<search-term>` (required), options as above, `[-- <file>]` (optional file restriction).
- `lcr <regex> [-i] [-p] [--all] [-- <file>] [git-log-opts]`: Search by regex in diff. Args: `<regex>` (required), options as above.
- `lau <author> [git-log-opts]`: Commits by author. Args: `<author>` (required), Git log options.
- `ld <since> [<until>]`: Commits in date range. Args: `<since>` (required date), `[<until>]` (optional, defaults to now).
- `lp [git-log-opts]`: File history with patches. Args: Git log options.

### File Inspection (f*)
- `fblame <file>`: Blame with whitespace/copy detection. Args: `<file>` (required).
- `fb <file>`: Short blame. Args: `<file>` (required).
- `fcon <file>`: Contributors to file. Args: `<file>` (required).
- `fa <file>`: Author commit counts for file. Args: `<file>` (required).
- `fborn <file>`: When file was added. Args: `<file>` (required).

### Staging (a*)
- `a [<files>...]`: Stage tracked files or specifics. Args: `[<files>...]` (optional; if none, stage updates).
- `aa`: Stage everything (tracked + untracked + deletions). No args.
- `ai`: Interactive add menu. No args.
- `ap`: Interactive patch add. No args.

### Unstaging (us*)
- `us <files...>`: Unstage specific files. Args: `<files...>` (required, at least one).
- `usa`: Unstage all. No args.
- `untrack <files...>`: Stop tracking files (keep locally). Args: `<files...>` (required).

### HEAD Operations (h*)
These map to custom scripts (see Section 2).
- `back [<n|commit>]`: Soft reset back. Args: `[<n|commit>]` (optional, defaults to HEAD~1).
- `undo [<n|commit>]`: Mixed reset back. Args: as above.
- `rollback [<n|commit>]`: Keep reset back. Args: as above.
- `rewind [<n|commit>]`: Hard reset back. Args: as above.
- `squash [<n|commit>]`: Squash commits into one. Args: `[<n|commit>]` (optional, default 2).
- `files [<n|commit>]`: Preview files in commits. Args: `[<n|commit>]` (optional, default 1).

### Working Directory (w*)
These map to custom scripts (see Section 2).
- `wip "<message>"`: Park changes on new WIP branch. Args: `"<message>"` (required). Options: `--stay` to remain on WIP branch.
- `wips "<message>"`: Alias for `wip --stay`. Args: `"<message>"` (required).
- `unwip [<wip-branch>]`: Unpark WIP branch. Args: `[<wip-branch>]` (optional, interactive picker if omitted). Options: `--no-squash`, `-f|--force`.
- `wipdel [<wip-branch>]`: Delete WIP branch (no integration). Args: `[<wip-branch>]` (optional). Options: `-f|--force`.
- `get <commit> [files...]`: Get files from commit. Args: `<commit>` (required), `[files...]` (optional).

### Commits (c*)
- `ca`: Commit all tracked. No args.
- `cm`: Amend last commit (staged only). No args.
- `cma`: Amend last (all tracked). No args.
- `cii`: Interactive stage + commit. No args.
- `cim`: Interactive add + status + commit. No args.
- `o`: Outgoing changes (alias for `log-outgoing --quiet`). No args.
- `cc [<commit-range>] [git-cherry-pick-opts]`: Cherry-pick with attribution. Args: `<commit-range>` (required, hash/range), Git cherry-pick options.
- `caa`: Commit all (tracked + untracked). No args.

### Status (s*)
- `sl [git-status-opts]`: Status (no untracked). Args: Git status options.
- `sla [git-status-opts]`: Status (long, with untracked). Args: as above.
- `sli [git-status-opts]`: Ignored + untracked files + status. Args: as above.
- `s`: Quick summary (custom). No args.
- `ss [<file>]`: Status with staged patch. Args: `[<file>]` (optional).
- `su [<file>]`: Status with unstaged patch. Args: as above.
- `sw [<file>]`: Status with working dir patch. Args: as above.
- `sx`: Working tree summary (custom). No args.

### Show (sh*)
- `sh [<commit>]`: Show commit with files. Args: `[<commit>]` (optional, default HEAD).
- `shp [<commit>]`: Show commit patch. Args: as above.
- `shc <commit>`: Files changed in commit. Args: `<commit>` (required).
- `shf <file> [git-show-opts]`: File diff in commit. Args: `<file>` (required), Git show options.

### Tags (t*)
- `t [<pattern>]`: List tags. Args: `[<pattern>]` (optional, default *).
- `tc <tag> [<commit>]`: Create lightweight tag. Args: `<tag>` (required), `[<commit>]` (optional).
- `ta <tag> [<message>]`: Create annotated tag. Args: `<tag>` (required), `[<message>]` (optional).
- `ts <tag>`: Show tag details. Args: `<tag>` (required).
- `tr <old-tag> <new-tag>`: Rename tag. Args: `<old-tag> <new-tag>` (required).
- `tm <tag> [<new-commit>]`: Move tag. Args: `<tag>` (required), `[<new-commit>]` (optional, default HEAD).
- `tma <tag> <message> [<new-commit>]`: Move + re-annotate. Args: `<tag> <message>` (required), `[<new-commit>]` (optional).
- `tpush [<tags>]`: Push tags. Args: `[<tags>]` (optional; if none, all).
- `tpull`: Fetch tags. No args.
- `tpullf`: Fetch + prune tags. No args.
- `tdel <tag>`: Delete local tag. Args: `<tag>` (required).
- `tdelr <tag>`: Delete remote tag. Args: `<tag>` (required).
- `tco <tag>`: Checkout tag. Args: `<tag>` (required).
- `twc [<commit>]`: Tags containing commit. Args: `[<commit>]` (optional, default HEAD).
- `twp [<object>]`: Tags pointing at object. Args: `[<object>]` (optional, default HEAD).

### Branches (b*)
- `b <branch>`: Switch branch. Args: `<branch>` (required).
- `bs`: Switch to previous. No args.
- `bl`: List local branches. No args.
- `bll`: List local branches (enhanced). No args.
- `bla`: List all branches. No args.
- `blr`: List remote branches. No args.
- `bc <branch>`: Create + switch branch. Args: `<branch>` (required).
- `br <new-name>`: Rename current branch. Args: `<new-name>` (required).
- `bdel <branch>`: Delete merged local branch. Args: `<branch>` (required).
- `bdelf <branch>`: Force delete local branch. Args: `<branch>` (required).
- `bdelr <branch>`: Delete remote branch. Args: `<branch>` (required).
- `bwc [<commit>]`: Branches containing commit. Args: `[<commit>]` (optional, default HEAD).
- `bwp [<object>]`: Branches pointing at object. Args: `[<object>]` (optional, default HEAD).
- `bwnc [<commit>]`: Branches not containing commit. Args: as above.
- `bwm [<commit>]`: Merged branches. Args: `[<commit>]` (optional, default HEAD).
- `bwnm [<commit>]`: Not merged branches. Args: as above.
- `bpush [options] [<remote>] [<url>]`: Push branch + upstream (custom script, see Section 2).

### Rebase (rb*)
- `rb <branch>`: Rebase onto branch. Args: `<branch>` (required).
- `rbi [<commit>]`: Interactive rebase. Args: `[<commit>]` (optional; if none, --root).
- `rbc`: Continue rebase. No args.
- `rba`: Abort rebase. No args.
- `rbs`: Skip commit. No args.

### Merge (m*)
- `m <branch>`: Squash merge. Args: `<branch>` (required).
- `mff <branch>`: FF-only merge. Args: as above.
- `mkeep <branch>`: No-FF merge. Args: as above.
- `ma`: Abort merge. No args.

### Pull
- `bpull`: Pull with rebase. No args.
- `pullall`: Pull all remotes. No args.

### Utilities
- `type <object>`: Object type. Args: `<object>` (required).
- `dump <object>`: Object contents. Args: `<object>` (required).
- `remote2ssh [<remote>]`: Switch remote to SSH. Args: `[<remote>]` (optional, default origin).

## 2. Custom Script-Based Commands
These are top-level commands backed by executable scripts (`git-*` in `bin/`). Complete subcommands statically, then options, then args.

### h (HEAD operations, via git-h)
Subcommands:
- `back [<n|commit>]`: Soft reset (keep staged). Args: `[<n|commit>]` (optional). Options: `-u|--upstream`, `-h|--help`, `--force`, `--quiet`.
- `undo [<n|commit>]`: Mixed reset (keep unstaged). Args: as above. Options: as above.
- `rollback [<n|commit>]`: Keep reset (lose commit changes, preserve local). Args: as above. Options: as above.
- `rewind [<n|commit>]`: Hard reset (destructive). Args: as above. Options: as above.
- `squash [<n|commit>]`: Squash commits into one. Args: `[<n|commit>]` (optional, default 2). Options: `-u|--upstream`, `-h|--help`, `--force`, `--quiet`.
- `files [<n|commit>]`: Preview files in commits. Args: `[<n|commit>]` (optional, default 1). Options: `-u|--upstream`, `--quiet`, `--stat`.
- `steps <file>`: Count steps back to file change. Args: `<file>` (required). Options: `--raw`, `--quiet`.

### w (Working Directory, via git-w)
Subcommands (gateway to specific scripts):
- `discard [options] <paths...>` (via git-w-discard): Discard tracked changes. Args: `<paths...>` (required, at least one). Options: `-u|--unstaged` (default if no flags), `-s|--staged`, `--dry-run`, `-f|--force`, `-h|--help`.
- `discard-all [options]`: Repo-wide discard. No positional args. Options: `-u|--unstaged` (default), `-s|--staged`, `--dry-run`, `-f|--force`, `-h|--help`.
- `purge [options] <paths...>` (via git-w-purge): Remove untracked/ignored. Args: `<paths...>` (required). Options: `-u|--untracked` (default), `-i|--ignored`, `--dry-run`, `-h|--help`.
- `purge-all [options]`: Repo-wide purge. No positional args. Options: `-u|--untracked` (default), `-i|--ignored`, `--dry-run`, `-f|--force`, `-h|--help`.
- `wipe [options] <paths...>` (via git-w-wipe): Wipe staged + unstaged. Args: `<paths...>` (required). Options: `-u -s` (both), `--dry-run`, `-f`.
- `wipe-all [options]`: Repo-wide wipe. No positional args. Options: as wipe.
- `zap [options] <paths...>` (via git-w-zap): Full reset (wipe + purge). Args: `<paths...>` (required). Options: `--dry-run`, `-h|--help`.
- `zap-all [options]`: Repo-wide zap. No positional args. Options: `--dry-run`, `-f|--force`, `-h|--help`.
- `wip [options] "<message>"`: Park changes on new WIP branch. Args: `"<message>"` (required). Options: `--stay`, `-h|--help`.
- `wips "<message>"`: Alias for `wip --stay` (parks and stays on WIP branch). Args: `"<message>"` (required).
- `unwip [options] [<wip-branch>]`: Unpark WIP branch. Args: `[<wip-branch>]` (optional, interactive if omitted). Options: `-f|--force`, `--no-squash`, `-h|--help`.
- `wipdel [options] [<wip-branch>]`: Delete WIP branch (no integration). Args: `[<wip-branch>]` (optional, interactive if omitted). Options: `-f|--force`, `-h|--help`.
- `get <commit> [files...]`: Get files from commit. Args: `<commit>` (required), `[files...]` (optional; if none, all files). No options (use `-h` for help).

### c (Commit, via git-c)
- `c [git-commit-opts]`: Commit staged. No positional args. Options: Pass-through to `git commit` (e.g., `-m <msg>`, `-v`), plus `-h|--help`.

### bpush (Branch Push, via git-bpush)
- `bpush [options] [<remote>] [<url>]`: Push + upstream. Args: `[<remote>]` (optional), `[<url>]` (optional). Options: `-u|--update`, `-f|--force` (safe), `--unsafe` (force), `-t|--track`, `-h|--help`.

### cc (Cherry-pick, via git-cc)
- `cc [git-cherry-pick-opts] <commit-range>...`: Cherry-pick. Args: `<commit-range>...` (required, at least one). Options: Pass-through to `git cherry-pick` (e.g., `--no-commit`), plus `-h|--help`.

### caa (Commit All, via git-caa)
- `caa [git-commit-opts]`: Commit all. No positional args. Options: Pass-through to `git commit`.

### s (Status Summary, via git-s)
- `s`: Quick colored summary. No args/options (use `-h` for help).

### ss (Staged Status, via git-ss)
- `ss [<file>]`: Status + staged patch. Args: `[<file>]` (optional). Use `-h` for help.

### su (Unstaged Status, via git-su)
- `su [<file>]`: Status + unstaged patch. Args: as above.

### sw (Working Status, via git-sw)
- `sw [<file>]`: Status + working patch. Args: as above.

### sx (Working Changes, via git-sx)
- `sx [--no-color]`: Summary of changes. Options: `--no-color`, `-h|--help`.

### statusbase (Enhanced Status, via git-statusbase)
- `statusbase [git-status-opts]`: Status + latest commit. Args: Git status options.

### remote2ssh (Remote Switch, via git-remote2ssh)
- `remote2ssh [<remote>]`: Switch to SSH URL. Args: `[<remote>]` (optional, default origin). No options.

### bll (Branch List Enhanced, via git-bll)
- `bll`: List local branches with enhanced formatting. No args/options.

### log-outgoing (Outgoing Changes, via git-log-outgoing)
- `log-outgoing [options]`: Show commits not yet pushed to upstream. Options: `--quiet`, `--fetch`, `-h|--help`.

### hughelp (Help, via git-hughelp)
- `hughelp [<prefix>]`: Smart help for prefix. Args: `[<prefix>]` (optional). No options.

## 3. General Completion Rules
- **Files/Paths**: Complete using prefix match for unmodified tracked + substring match for modified and untracked (focus on active changes)
- **Commits/Refs**: Complete from `git rev-parse --symbolic-full-name --branches --tags --remotes` or hashes via `git rev-list --all --abbrev-ref=short`.
- **Branches**: `git branch --list`.
- **Tags**: `git tag --list`.
- **Remotes**: `git remote`.
- **Stashes**: `git stash list --format=%gd`.
- **Options**: Complete long options with `--`, short without. Suggest based on command (e.g., `-f` for force).
- **Dynamic**: For commands with `[git-opts]`, defer to Git completions.
- **Errors**: Commands fail outside Git repo; completions should check `git rev-parse --git-dir`.
- **No Global Options**: Hug has no global flags; per-command only.

This spec covers all provided files. Use it to generate completions that suggest words, then options, then args dynamically.
