- In shell scripts, NEVER use the `local` keyword outside a function body!
- Scripts should always follow the D.R.Y. principle, have high maintainability and elegance.
- Try to keep most of the work in library functions (../lib/) while the scripts themselves basically work as a thin layer that call the library to promote maximum code reuse

## Per-command keywords (optional)

Scripts may declare `_hug_keywords='[...]'` alongside `_hug_category` so
`hug help /<query>` and `hug help !<query>` can match curated terms not
present in the command's description. Each keyword is a separate match
unit (scored independently). Keep keywords specific to *this* command —
do not add words that would also fit a destructive sibling. Empty/absent
keywords gracefully fall back to description-only scoring.

Example: `git-w-wip` declares `_hug_keywords='["save","shelve","stash"]'`;
`git-w-wipdel` (destructive) does NOT include `save` or `stash`.

Non-script commands (git-aliases, passthroughs) have no script to annotate —
their keywords/summaries live in `../lib/python/commands.toml` (registry),
loaded by `command_meta.py`. Keep the two surfaces consistent: a keyword that
would fit a destructive sibling stays out of BOTH.

The discovery layer also invokes scripts directly from NON-REPO cwds — both
`--search-meta` and `-h/--help` must work there (an installed layout may have
no `.git` at all). Dispatch `eval "$(parse_common_flags "$@")"` BEFORE
`check_git_repo`, or the guard locks users out of the very help that explains
recovery (see git-mff, git-shc).

