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
