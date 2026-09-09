# Design: Fetch-discovery registry for the hug help system

- **Date:** 2026-09-08
- **Branch:** `fetch-discovery-registry-for-help-search`
- **Status:** Approved (brainstorming session, Approach A); roast rounds 1–4
  applied. Round 4: BrokenPipeError contract made deliverable (devnull
  redirect / `os._exit(0)` for the shutdown-flush case — a bare suppress
  exits 120 outside any catch), flag-like help names guarded out of the card
  chain (`-*` bash guard + `card -- "$prefix"` + BATS pin), the actively-
  wrong `docs/meta/hug-completion-reference.md` added to the change-set
  (teaches `bpull` = rebase today) with three more true-hit docs folded into
  the deferred list, and drift test 1 strengthened from alias existence to
  alias semantics (`git_equivalent` token-subset). All findings verified
  against live code before adoption.

## Problem

Agents (and humans) search hug's help system for `fetch` and find nothing — yet
`hug fetch` works. Every discovery path dead-ends:

| Path | Today |
|---|---|
| `hug fetch origin --tags` | ✅ Works — `bin/hug:221` passes unknown commands to `git` |
| `hug help /fetch` | ❌ `(none)` |
| `hug help /pull` | ❌ `(none)` |
| `hug help /bs` | ❌ `(none)` — same defect, non-sync member (README-documented command) |
| `hug help '@push-pull'` | ⚠️ Description promises "fetch updates, pull and rebase"; lists only 4 push/outgoing commands |
| `hug help bpullr` | ⚠️ Alias-expands to raw `git pull` usage, then "(none)" |
| `hug help fetch` | ⚠️ `command -v git-fetch` resolves git's exec-path builtin (`/usr/lib/git-core/git-fetch`, git 2.34.1 here) → prints the full GIT-FETCH(1) man page (36 KB of generic git prose, zero hug context) |
| `hug help :agents` translation table | ❌ Has `push → bpush`; no fetch row at all |

**Root cause:** the help index is built exclusively from the 107 `git-config/bin/`
scripts via their `--search-meta` protocol (`help_search.collect_metadata`). Commands
that are not scripts are invisible to all four discovery sigils (`/keyword`,
`'!intent'`, `@category`, and exact-name help):

- `fetch` — pure dispatcher passthrough
- `bpull` = `pull --ff-only` (`.gitconfig:514`)
- `bpullr` = `pull --rebase` (`.gitconfig:518`)
- `pullall` = `pull --all` (`.gitconfig:522`)
- `tpull` = `fetch --tags` (`.gitconfig:306`) — fetch semantics, "pull" name
- `tpullf` = `fetch --tags --prune --prune-tags --force` (`.gitconfig:310`)
- `bs` = `switch -` (`.gitconfig:368`) — switch back to the previous branch;
  documented in README (incl. a wip/pause/resume workflow) yet `/bs` → `(none)`

The most common sync primitive an agent needs (`fetch` before
`hug wtc --base origin/main`, per the `:worktree` article's "base off an UP-TO-DATE
integration branch") is precisely the one the help system cannot surface.

## Goals

1. All four discovery sigils answer "fetch" (and "pull", "tags fetch", …).
2. `hug help <name>` renders a hug-flavored card for registry entries instead of
   falling through to raw git alias expansion.
3. `@push-pull` lists the existing sync surface so the category's promise matches
   its contents.
4. `:agents` article teaches `git fetch → hug fetch`.
5. Regression-pin the whole behavior in the help-search quality corpus.

## Non-goals

- **No first-class `git-fetch` script.** `hug fetch` stays a passthrough.
- **No shell-completion changes.** A third consumer can ride the same registry later.
- **No Mercurial-mode help changes.** The registry lives in `git-config/`; hg help
  remains the dispatcher's static text.
- **No behavior change to any existing command** — this is metadata + help display only.
- Not indexed: `push` (the right answer is `bpush`, already searchable — indexing raw
  push would be a footgun); `brr` (branch helper `b -R`, `.gitconfig:364`, not a sync
  primitive — may appear in a Related block); naked `pull` (can merge unexpectedly;
  the `bpull*` cards teach the safe forms).
- Known limitation, accepted: prefix listings (`hug help f`) stay registry-blind —
  Goal 1 scopes coverage to the four sigils. The six sync aliases already surface
  in prefix listings via the existing alias loop (git-hughelp:57-63); `fetch` is
  the one entry absent there (it is not an alias).

## Architecture (Approach A: static registry + loader)

Two new pieces, three thin integration points.

### New: `git-config/lib/python/commands.toml`

One table per non-script command. Schema:

```toml
[fetch]
kind = "passthrough"          # "alias" | "passthrough"
description = """
Download new commits and refs from remotes without merging.
Multi-line prose used by /keyword + !intent search and the help card.
Speaks the user's vocabulary (download, sync, update, remote).
"""
keywords = ["fetch", "download", "sync", "update", "remote"]
categories = ["push-pull"]     # every value must exist in categories/
git_equivalent = "git fetch"
usage = "hug fetch [--tags] [--prune] [<remote> [<refspec>...]]"
related = ["bpull", "bpullr", "tpull", "llu"]
```

Field rules:
- **No `summary` field.** The listing/search one-liner is DERIVED from
  `description`'s first sentence via `category_meta.derive_summary`
  (same `SUMMARY_MAX = 70` budget) — the exact pattern `categories/*.toml`
  already uses. One prose source, one derivation, no second summary format to
  keep in sync and no length rule left unenforced. Write descriptions so the
  first sentence stands alone as the listing line.
- `description` feeds fuzzy scoring (WRatio/token-set) and the card body.
- `keywords` is the registry analog of the per-script `_hug_keywords` protocol
  (see `git-config/bin/CLAUDE.md`); each keyword is an independent match unit.
- `categories` values are validated against `categories/*.toml` at load.
- Table names (the command names) are validated against hug's command grammar:
  `^[a-z][a-z0-9]*(-[a-z0-9]+)*$` — a name with spaces, capitals, or a
  gateway-style form like `h fetch` fails at load instead of flowing unchecked
  into card headers, drift tests, and command strings.
- `related` entries are validated at load: each must resolve to a registry
  sibling, a `git-config/bin/git-*` script, or a `.gitconfig` alias (one
  `git config --file … --get-regexp '^alias\.'` call per load, not per name).
  A dead `hug <name>` hint on a card is the same discovery dead-end this
  feature fixes.
- **Merge format (pinned):** registry rows enter the index as
  `CommandInfo(command="hug <table-name>", …)` — the same hug-prefixed string
  `derive_command_name` produces for scripts (help_search.py:331). The sort
  key (help_search.py:418), every rendered line (`format_results` prints
  `cmd.command` verbatim), the corpus rows, and the BATS assertions all
  consume the prefixed form; a bare table name would fail the corpus, break
  the BATS rows, and reorder the merged index in one stroke.

### New: `git-config/lib/python/command_meta.py`

Loader mirroring `category_meta.py`: frozen dataclass, schema validation
(table-name grammar, required fields, `kind` enum, unknown-category rejection,
`related` resolvability), derives the listing summary from `description` via
`category_meta.derive_summary`, and raises loudly on a missing or corrupt
`commands.toml` (same failure posture as `categories/` — the file ships with the
repo; silent-empty would silently break the corpus). Paths the loader needs
beyond its own directory — the `.gitconfig` for `related` validation, hug's bin
dir — resolve `__file__`-relative (the existing `_DEFAULT_BIN_DIR` pattern,
help_search.py:109), which works identically in-repo and installed.

### Integration 1 — `help_search.py` index merge

The registry reaches `collect_metadata()` as an explicit `cmd_meta` parameter,
default `None` = no merge — mirroring the `cat_meta: dict | None = None`
precedent (help_search.py:360-367). Auto-loading inside the function would
couple every existing mock-dir unit test in `test_help_search.py` to the real
repo's TOML validity; the explicit param keeps them hermetic. `main()` passes
the loaded registry; the corpus fixture passes the real one.

`collect_metadata()` merges registry entries as `CommandInfo` rows after the
script-cache load and **before** the `sorted(...)` at help_search.py:418
(`hydrate_category_fields` runs immediately after the sort) — so the returned
list is one uniformly sorted index.
Appending after the sort would leave script rows sorted and registry rows
appended; `@push-pull`'s page renders in input order, so it would list four
push scripts, then the six sync entries, instead of one alphabetical list.
Registry rows never enter `search-meta.cache` — the cache is keyed by script
filename and written only inside the script loop, so no invalidation logic is
needed.

`CommandInfo` gains one optional field: `kind: str | None = None`
(`None` = script; fully backward-compatible with all existing constructions).

Because the merge happens upstream of `search_keyword`, `search_intent`,
`search_category`, and `list_categories`, **all four sigils surface registry
entries with zero search-engine changes**.

### Integration 2 — `git-hughelp` exact-help precedence

Current resolution (lines 46–53): script `--help`, else raw alias expansion.
New strict chain:

1. **Hug's own script exists** → run `"$dir/git-$prefix" --help` — the
   `$dir/`-prefixed invocation is load-bearing: inside a git-dispatched script
   PATH position 1 is git's exec-path (probed: `/usr/lib/git-core`), so a bare
   `git-$prefix` would re-resolve through PATH and, on the future day hug
   ships a script named like a git builtin, execute GIT's builtin instead of
   hug's. The existence test MUST be `[[ -x "$dir/git-$prefix" ]]` (the
   directory git-hughelp itself lives in) — **not** the current
   `command -v "git-$prefix"`.
   WHY: when git dispatches an external subcommand it prepends its exec-path to
   PATH, and Debian/Ubuntu-family git ships dashed builtins there
   (`/usr/lib/git-core/git-fetch` on git 2.34.1 — verified live: `hug help fetch`
   prints the GIT-FETCH(1) man page today). A PATH lookup makes branch ① win for
   `fetch` and the card unreachable — the exact regression this design exists to
   prevent. Behavior change vs today, accepted: for git-core-named names, the
   hug card + "Full flags: git help fetch" line replaces git's man page dump.
2. **Registry has `$prefix`** → `uv run --directory "$dir/../lib/python"
   --extra search help_search.py card -- "$prefix"` — **no `exec`** (an `exec`
   replaces the shell, making the exit-4 fall-through below impossible and
   killing every non-registry alias's help, e.g. `hug help brr` which today
   prints alias help + listing, exit 0). Exit-code contract — THIS TABLE IS THE
   SINGLE OWNER of card-mode exit semantics; every other section defers to it:
   - `0` → card printed; exit 0 (the card's Related block replaces the
     prefix listing).
   - `1` → **uv launcher failure** — `uv run` itself can exit 1 BEFORE
     help_search.py runs (environment creation/update: offline first run,
     dependency/build failure). Bash maps this to a LOUD exit: "hug: help
     card environment failure for '$prefix' (uv rc=1)" and `exit 1` — never
     fall-through, an environment failure must not masquerade as a miss.
   - `4` → name not owned by the registry; fall through to ③/④. **Exit 4 is
     reserved EXCLUSIVELY for a registry miss.** Why not 1: uv's own
     environment failures exit 1 (see the row above), so 1 must mean loud,
     never miss. Python also exits 1 on any unhandled exception by default,
     so card mode wraps its whole body (registry load + render) in a
     catch-all mapping ANY unexpected `Exception` to ≥2 with the traceback
     on stderr — without it, every card bug would masquerade as a miss and
     silently degrade to legacy help, exit 0.
     The catch-all must NOT swallow benign signals: `KeyboardInterrupt` and
     `SystemExit` re-raise unwrapped (Ctrl-C exits 130, no traceback).
     `BrokenPipeError` is quiet success — with the canonical mitigation, not
     a bare suppress: for card-sized output the pipe error typically fires at
     interpreter-SHUTDOWN flush, after and outside the guarded body (probed:
     exit 120 + "Exception ignored in: <_io.TextIOWrapper ...> BrokenPipeError"
     — and 120 would land in this loud branch, the exact "reads as a bug"
     outcome forbidden here). On BrokenPipeError (caught in-body or as
     shutdown flush), point stdout at devnull before exiting:
     `os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())` then
     `sys.exit(0)` (equivalently flush + `os._exit(0)`) — help is the most
     piped output a CLI has; `hug help fetch | head` must not read as a bug.
   - **Flag-like `$prefix` never reaches ① or ②.** A `-`-prefixed prefix is
     not a command name; bash guards the chain (`[[ "$prefix" == -* ]] &&
     skip to ③/④`), preserving today's behavior for `hug help -h` (prefix
     listing, exit 0). Defense-in-depth: the card invocation passes the name
     after `--` (`help_search.py card -- "$prefix"`), so argparse can never
     intercept `-h`/`--help` as HelpAction (which would print generic usage
     to stdout, exit 0 — misread by bash as "card printed") or swallow
     `--all`/`--explain` into an accidental empty-query miss.
   - `≥2` → loud failure, never fall-through: registry missing/corrupt
     (message + exit 2 — `main()`'s `sys.exit(1)` categories posture is
     deliberately NOT copied into card mode, for the reason above), the
     catch-all, and — per the user-directed promotion of uv to a REQUIRED
     dependency — bash's exit 127 for a missing `uv` binary, which prints an
     actionable "uv is required for hug help; install.sh provisions it"
     message. There is deliberately NO fall-through on 127: on a properly
     provisioned install the path cannot trigger, and on a broken one, loud
     beats silent. (Bounded misclassification: argparse's unknown-mode exit 2
     also lands here, with its own invalid-choice message.)
3. Alias exists → `git $prefix -h` (unchanged fallback).
4. Prefix listing (unchanged).

Property (the invariants that actually hold): ① no registry name collides with a
hug bin script (drift test 2a), so branch ② only claims names no hug script
owns; ② branch ① is PATH-free — it tests `-x` on hug's own bin dir, so git-core
dashed executables CANNOT shadow the card no matter what PATH holds. The flip
side, accepted by design: a git-core executable MAY share a registry name
(`fetch` does — `/usr/lib/git-core/git-fetch`), and the card deliberately
outranks it. If hug ever ships a real `git-fetch` script, it lands in branch ①'s
bin dir and the card is shadowed in turn — the desired direction (scripts beat
cards). Bash stays a thin dispatcher (per `git-config/bin/CLAUDE.md`).

Dependency change, owned honestly (user-directed 2026-09-08): exact-name help
is pure bash today (git-hughelp:46–63; `install.sh` installs no uv, README
never mentions uv). This design **promotes uv to a required hug dependency**
— `install.sh` provisions/validates it and README documents it — rather than
degrading help when it is absent. Consequence: every non-script exact-help
lookup (registry miss → ③) pays one `uv run` venv resolution before falling
through (latency on a human-interactive path; the sigil modes already require
it), and on an improperly provisioned install the 127 branch above fails
LOUDLY with an install hint instead of silently returning weaker help.

### Integration 3 — card mode in `help_search.py`

`help_search.py card <name>`: renders and exits 0 when the registry owns the name;
exits 1 otherwise (bash falls through to ③/④); exits ≥2 with a loud message on
environment failure. The card is a **pure function over the loaded registry
dict** — it must NOT run `collect_metadata()`. Related lines resolve their
one-line summaries from (in order): the registry itself, a **read-only** peek
at `search-meta.cache` via `_load_cache` (card mode must NEVER call
`_save_cache` — peek, never populate). The cache is keyed by script FILENAME
(help_search.py:383-395: `name = script_path.name`), so the peek derives the
key `git-<name>` (registry names are grammar-validated single tokens — no
gateway forms to map); if neither source has the name, render the
bare `hug <name>` hint.
Rationale: `collect_metadata` scans/execs every script on a cold cache, so an
exact-name card would pay a 107-script sweep per call — a discovery win with a
performance footgun.

Card layout:

```
hug fetch — (git passthrough)
Download new commits and refs from remotes without merging

<description body>

Usage: hug fetch [--tags] [--prune] [<remote> [<refspec>...]]
Git equivalent: git fetch
Full flags: git help fetch

Related:
  hug bpull    — fast-forward-only pull (safe default)
  hug bpullr   — pull with rebase (linear history)
  hug tpull    — fetch tags
  hug llu      — verify what came in (behind count)
```

Related lines pull each entry's/script's one-line summary where available; kind
shown as `(git alias)` or `(git passthrough)`.

**Full-flags derivation (pinned):** `git help <name>` for `kind = "passthrough"`,
`git help <target-command-of-alias>` for `kind = "alias"` — derived from
`git_equivalent`'s leading command, NOT from the registry name. Rationale:
probed live, `git help bpullr` exits 0 but prints an alias notice
(`'bpullr' is aliased to 'pull --rebase'`), not flags — a name-derived hint is
a dead-end of exactly the class this feature removes. So `bpull`/`bpullr`/
`pullall` → `git help pull`; `tpull`/`tpullf` → `git help fetch`; `bs` →
`git help switch`; `fetch` → `git help fetch`.

### Display markers

In `@category` pages and `/keyword` / `!intent` results, registry rows render a
trailing marker derived from `kind`: `hug bpullr — Pull with rebase (git alias)`.
Summaries in the TOML stay pure prose; the marker is added by the format layer
(`format_results`, `format_category_page`) when `cmd.kind` is set — so a reader
sees immediately why `hug bpullr -h` isn't hug-flavored.

## Registry contents (initial)

Seven entries: six sync commands in `@push-pull` (`tpull`/`tpullf` additionally
in `@tags`) plus `bs` in `@branching` — the first non-sync member, included
deliberately (user-directed 2026-09-08): it is documented in README, used in a
README workflow, and equally invisible to search. It also proves the registry
generalizes beyond one category. Systematic coverage of the remaining non-script
commands (index or consciously exclude, per command) is tracked in
[elifarley/hug-scm#338](https://github.com/elifarley/hug-scm/issues/338).

| name | kind | description's first sentence (= derived listing summary) | extra keywords | related | usage · git_equivalent (→ full-flags) |
|---|---|---|---|---|---|
| `fetch` | passthrough | download commits/refs from remotes, no merge | download, sync, update, remote, refs | bpull, bpullr, tpull, llu | `hug fetch [--tags] [--prune] [<remote> [<refspec>...]]` · `git fetch` → `git help fetch` |
| `bpull` | alias | fast-forward-only pull; fails if merge/rebase needed | update, integrate | fetch, bpullr, mff | `hug bpull` · `git pull --ff-only` → `git help pull` |
| `bpullr` | alias | pull with rebase (linear history) | rebase, update, integrate | fetch, bpull, rb | `hug bpullr` · `git pull --rebase` → `git help pull` |
| `pullall` | alias | fetch from all remotes, then update the current branch's upstream | all, every, remote | fetch, bpull | `hug pullall` · `git pull --all` → `git help pull` |
| `tpull` | alias | fetch tags from the remote | tag, download | fetch, tpullf, t | `hug tpull` · `git fetch --tags` → `git help fetch` |
| `tpullf` | alias | force fetch + prune stale tags | tag, prune, force | tpull, fetch | `hug tpullf` · `git fetch --tags --prune --prune-tags --force` → `git help fetch` |
| `bs` | alias | switch back to the previous branch | previous, back, toggle, last | b, bc | `hug bs` · `git switch -` → `git help switch` |

Note on `pullall`: `git pull --all` fetches all remotes but integrates only the
current branch's upstream (per `git help pull`) — the description must not teach
"pulls every branch", which the `.gitconfig` comment's own phrasing invites.

## Testing

### Quality corpus (the regression net for the reported complaint)

`git-config/lib/python/tests/test_quality_corpus.py` gains rows in the existing
top-N-membership style:

Expected entries are the hug-prefixed `command` strings (the existing corpus
convention, e.g. `("push", ["hug bpush"])` at test_quality_corpus.py:56):

- `/fetch` top-5 ⊇ {"hug fetch", "hug tpull", "hug tpullf"}
- `/pull` top-5 ⊇ {"hug bpull", "hug bpullr", "hug pullall"}
- `/bs` top-5 ⊇ {"hug bs"}
- intent `update my repo from the remote` top-5 ⊇ {"hug fetch", "hug bpull",
  "hug bpullr"}
- intent `go back to the previous branch` top-5 ⊇ {"hug bs"}
- Destructive-sibling guard style: `/fetch` must NOT surface `h-rewind`/
  `w-zap`-class commands (inherits the corpus's F3 guarantee pattern).

### pytest unit tests (`git-config/lib/python/tests/`)

- Loader: valid file → entries; missing required field → error; bad `kind` → error;
  unknown category → error; table name failing the command grammar → error;
  `related` entry resolving to nothing → error; missing file → error.
- Derived summary: first sentence of `description` becomes the summary; a
  description whose first sentence exceeds 70 chars is truncated by the same
  rule as `category_meta.derive_summary` (one pinned test, not a silent guess).
- Merge: `collect_metadata` output contains registry rows with correct `kind`;
  script rows keep `kind=None`; the merged list is fully sorted (registry names
  interleaved alphabetically, not appended); cache still bypasses registry
  (second call with warm cache still includes registry rows).
- Card: found name → card text contains kind, git-equivalent, related, usage,
  and the correctly derived Full-flags hint (alias → target command, not the
  registry name); unknown name → exit 4, no partial card; related summary
  resolution order (registry → read-only `git-<name>` cache key → bare hint).
- Card anti-masquerade — the exit contract's own test matrix, one row per
  bucket: corrupted `commands.toml` in card mode → exit ≥2, stderr carries the
  registry error, output does NOT contain "Commands starting with"; forced
  render failure (test-only entry whose render raises) → exit ≥2, never 1;
  `BrokenPipeError` (piped reader closes) → quiet exit 0 via the devnull
  redirect — assert BOTH the in-body raise (large output) and a shutdown-flush
  shape; `KeyboardInterrupt` → exit 130, no traceback; flag-like name behind
  the guard → unit-level `card -- -h` is an ordinary miss (exit 4, no usage
  on stdout) and `card -- --bogus` likewise resolves to the miss code 4
  (argparse treats what follows `--` as positionals).

### Drift tests (the two consistency guarantees)

1. **Alias resolution AND semantics:** every `kind = "alias"` entry resolves
   via `git config --file git-config/.gitconfig --get alias.<name>`
   (non-empty), AND each entry's `git_equivalent` tokens appear in the
   resolved alias body (token-subset assertion — also matches the
   `!f() { … }` shell-function forms of `tpull`/`tpullf`). Existence alone
   would let a `.gitconfig` body edit keep every artifact green while cards
   teach stale semantics.
2. **No hug-bin shadowing + PATH-free branch ①:**
   (a) for each registry name N, no hug bin script `git-config/bin/git-N`
   exists;
   (b) branch ① never consults PATH — assert at the source level BOTH halves:
   script existence resolved with `-x` on git-hughelp's own directory AND the
   invocation in the `$dir/git-$prefix`-prefixed form (a bare `git-$prefix`
   invocation would re-resolve through PATH, where git's exec-path sits at
   position 1, and silently reintroduce the man-page dump the day hug ships a
   git-builtin-colliding script name); plus behaviorally that `hug help fetch`
   renders the card even with git's exec-path prepended to PATH (the BATS card
   case already pins this end to end).
   Deliberately NOT probed: `$(git --exec-path)/git-N` / `command -v git-N`
   collisions. Registry names MAY collide with git-core dashed executables
   (`fetch` does, by design) — a PATH/exec-path non-collision assertion would
   be red on day one on every Debian/Ubuntu box and asserts the one invariant
   this design rejects.

### BATS integration (`tests/integration/test_help_articles.bats` + additions)

- `hug help /fetch` → output contains `hug fetch` and `hug tpull`.
- `hug help fetch` → card (contains "git passthrough"); does NOT contain
  "Commands starting with"; does NOT contain the GIT-FETCH man-page banner.
- `hug help bpullr` → card; does NOT contain git's raw `usage: git pull` banner.
- `hug help -h` (flag-like prefix) → bash guard skips ①②; prefix listing,
  exit 0, no card, no argparse usage on stdout (pin for the flag-like-name
  row of the exit contract).
- `hug help brr` (non-registry alias) → alias help + prefix listing still work,
  exit 0 (regression pin for the no-`exec` fall-through contract; `brr` is
  deliberately excluded from the registry per non-goals, `.gitconfig:364`).
- `hug help bs` (registry entry) → card contains "(git alias)" and "switch
  back", exit 0, no "Commands starting with" (positive pin for the
  user-directed 7th entry).
- `hug help zzz` (unknown name) → prefix listing "(none)", exit 0.
- `hug help s` → unchanged script help (precedence regression: branch ① wins).
- `hug help '@push-pull'` → lists `bpull`, `bpullr`, `fetch` with kind markers,
  in one alphabetical run (no script-block-then-registry-block split).
- `hug help bpush` (a script name, unaffected by registry) → unchanged.

## Error handling

- **Registry failure is loud everywhere — with one mode-scoped exit code.**
  Search modes (`/keyword`, `!intent`, `@category`): a bad or missing
  `commands.toml` exits 1 with a clear message on stderr, mirroring
  `help_search.main()`'s `sys.exit(1)` categories posture (help_search.py
  936/939/953/971). Card mode: the SAME failure exits **≥2** per Integration 2's
  contract table — exit 4 is reserved for a registry miss, so copying the
  search-mode code would make a corrupt registry masquerade as a miss (fall
  through to legacy help with exit 0). No catch-and-continue in any mode:
  silent degradation would
  quietly shrink the index and the corpus, the exact outcome the loader exists
  to prevent.
- Cache integrity (the narrow sense of "script search survives"): registry rows
  never enter `search-meta.cache` and are merged only after the cache is read,
  so a corrupt registry cannot alter or invalidate cached script metadata — but
  the process still exits 1 before printing anything.
- Card mode for a name owned by BOTH registry and a hug script cannot happen
  (drift test 2a: no registry name matches `git-config/bin/git-N`); if it
  somehow did, bash branch ① still wins — scripts beat cards.

## Docs change-set (per DOCS_ORGANIZATION.md)

1. `git-config/lib/python/articles/agents.md`:
   - Translation table gains: `git fetch` → `hug fetch` (passthrough note).
   - New short "Fetching & pulling" block beside Pushing: `hug fetch` (safe, no
     merge), `hug bpull` (safe default), `hug bpullr` (linear history), `tpull`
     for tags; reminder to fetch before `hug wtc --base origin/main`.
2. `docs/git-to-hug.md` — the PUBLIC translation guide: add `git fetch → hug
   fetch` rows to both the quick table and the detailed section (it already
   documents `git pull → hug bpull` / `--rebase → hug bpullr` with no fetch
   row — the same dead-end this feature fixes, in the artifact agents
   actually read).
3. `docs/command-map.md`: add `fetch` to the push/pull tree beside
   `bpull`/`bpullr` (passthrough note).
4. `docs/meta/hug-completion-reference.md` — **actively wrong today** and
   agent-facing: its Pull section teaches "`bpull`: Pull with rebase"
   (reality: `bpull = pull --ff-only`, `.gitconfig:514` — rebase is
   `bpullr`, which has zero rows there) and phrases `pullall` as the exact
   "pulls every branch" misconception the registry corrects. Fix the `bpull`
   row, add `bpullr`, align `pullall`'s phrasing with the registry
   description.
5. `README.md` command reference: add `hug fetch` row beside the existing
   `bpull`/`bpullr` rows.
6. **uv promoted to a required hug dependency** (user-directed 2026-09-08):
   `install.sh` provisions/validates uv (it currently installs none —
   verified: zero uv mentions in install.sh and README), and `README.md`
   documents it under requirements. This is what licenses the never-fall-
   through ≥2 posture of the card exit contract.
7. Authoring homes for the registry (so the second contributor knows where
   metadata lives):
   - `git-config/bin/CLAUDE.md`: extend the `_hug_keywords` note — bin scripts
     declare keywords in `_hug_keywords`; non-script commands declare them in
     `commands.toml`.
   - `git-config/lib/python/README.md` (Module Organization): add
     `command_meta.py` / `commands.toml`.

Consciously deferred (consistency debt — none of these become false; they name
bpull/tpull without claiming fetch coverage): `docs/cheat-sheet.md`,
`docs/workflows.md`, `docs/practical-workflows.md`, `docs/cookbook.md`,
`docs/commands/branching.md`, `docs/commands/tagging.md`,
`docs/commands/worktree.md`, `docs/commands/rebase.md`,
`docs/skills/hug-workflow/SKILL.md`, and
`docs/skills/hug-repo-analysis/guides/branch-analysis.md`. Fold their fetch
rows into the systematic coverage pass in
[elifarley/hug-scm#338](https://github.com/elifarley/hug-scm/issues/338).

No new docs pages; no VitePress sidebar changes.

## Success criteria

- `hug help /fetch`, `hug help /pull` return the family (no more `(none)`).
- `hug help bpullr` renders the card; raw `git pull` usage no longer appears.
- `hug help '@push-pull'` lists the six sync entries (bs renders under
  `@branching`); category promise matches contents.
- `:agents` article shows the fetch translation.
- Corpus rows + drift tests + BATS cases green; full `make test` green.

## References

- `bin/hug:217-221` — git-repo dispatch (`exec git "$@"` passthrough)
- `git-config/bin/git-hughelp:38-53` — sigil dispatch + exact-help resolution
- `git-config/lib/python/help_search.py` — `CommandInfo`, `collect_metadata`,
  `search_*`, `format_*`, cache
- `git-config/lib/python/category_meta.py` — loader pattern to mirror
- `git-config/.gitconfig:306,310,368,514,518,522` — the seven aliases
- Shadowing receipt: `/usr/lib/git-core/git-fetch -> git` (git 2.34.1,
  exec-path `/usr/lib/git-core` first on PATH inside git-dispatched scripts;
  live: `hug help fetch` prints the GIT-FETCH(1) man page today)
- Prior art: `categories/*.toml` + `category_meta.py` (chosen over category-level
  keyword pollution — see `category_meta.py` docstring, /autoplan F3)
