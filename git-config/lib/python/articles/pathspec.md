+++
title   = "Pathspecs: filtering any hug command by path"
summary = "One -- <path>... contract across every path-accepting command."
order   = 20
+++

# Pathspecs: `-- <path>...` means the same thing everywhere

The canonical example — memorize this one line:

```
hug sla -- '*.md'        # list only Markdown files
hug sla '*.md'           # same thing — the separator is optional
```

**Quote your globs.** An unquoted `*.md` is expanded by YOUR shell before hug
ever sees it (to the files in the current directory — silently the wrong
scope). Quoted, the glob travels verbatim to git, which matches it against
the whole tree. This is why every example here quotes its pathspecs.

## The three command classes (what a trailing `--` does)

| Class | Commands | Pathspecs scope… | Trailing bare `--` |
|---|---|---|---|
| Listings | `sl` `sla` `sls` `slu` `slk` `sli` `slc` | the listing, `-c` count, AND the `--json` envelope | Inert — identical to no arguments |
| Mutating, explicit-path | `a` `us` `cmod` | which files are staged / unstaged / committed | `a`: opens the picker (scoped to any given pathspecs); `us`: opens the staged-file selector (same as no arguments); `cmod`: same as no pathspecs (the amend runs unscoped). `cmoda` is NOT in this class — see below |
| Diff & search pickers | `ss` `su` `sw` `lc` `lf` `lcr` | the diff / search output | Opens the interactive picker, scoped to any given pathspecs |
| Scoped destructives | `w-discard` `w-purge` `w-zap` `w-wipe` `w-get` | the SCOPE of destruction / restore — narrowing only, never widening | Opens the command's interactive file-selection arm (same as no arguments) |
| Log viewers | `llu` `sh` | the outgoing-log / commit-details output (`--json` too, on `llu`) | Inert — identical to no arguments |

(`shp` `shcp` `shc` `dd` also accept pathspecs — they scope the shown diff;
they have no picker arm. `shp` filters a SINGLE file: given several
pathspecs it uses the first and prints
`Warning: shp only supports single-file filtering. Using first path: …`.)

## Syntax

Everything after the FIRST `--` is pathspec data, handed to git verbatim:

```
hug sls -- src/ tests/          # union: anything under either directory
hug sw --stat -- '*.java'       # flags before, paths after
hug sl -- ':(exclude)src/'      # git magic: everything EXCEPT src/
hug lc term -- '*.py'           # search term first, then paths
```

Positionals also work without the separator — `hug sls src/` filters exactly
like `hug sls -- src/`. The separator is REQUIRED only when a path begins
with `-` (it would otherwise parse as an option):

```
hug sls -- -weird-file          # a file literally named '-weird-file'
```

## The `--` duality

- **Trailing bare `--`** (last argument): a UI trigger, never a pathspec —
  see the class table above for what each class does with it.
- **Mid-stream `--`**: the data/option boundary. Everything after it is
  pathspec data.

A **second, mid-stream `--`** after the first is a harmless *phantom
pathspec* under git's OR semantics — `hug sl -- a -- b` filters to `a` ∪ `b`
∪ (a pathspec matching nothing named `--`). No error, no surprise; git
unions the terms.

## Quoting rules — and WHY

| You type | Your shell sends | Result |
|---|---|---|
| `hug sla *.md` | the .md files in the CURRENT dir | wrong scope, silently |
| `hug sla '*.md'` | the literal `*.md` | git matches the whole tree |
| `hug sla src/*.ts` | current-dir matches only | wrong scope |
| `hug sla 'src/*.ts'` | literal | correct |

Single quotes are the safest default: they also protect `:(exclude)` magic,
`$`, backticks, and spaces in filenames. Double quotes still allow `$`
expansion inside.

## Magic pathspecs (passed through verbatim)

Git's pathspec magic works unchanged: `:(exclude)`, `:(glob)`, `:(icase)`,
`:(top)`. Hug does not interpret pathspecs — it forwards them, so git's own
semantics (including `:(exclude)` needing something to exclude FROM) apply:

```
hug sla -- ':(glob)docs/**/*.md' ':(exclude)docs/drafts/'
```

A MALFORMED magic pathspec (`:(bogus)src/`) fails loudly: git's own
`fatal: Invalid pathspec magic ...` reaches stderr, hug adds
`Invalid pathspec: ':(bogus)src/'. See 'hug help :pathspec'.` and the command
exits 2 (usage error) — the same class as an unknown option. A typo never
looks like an empty answer: listings print nothing on stdout, `--json`
commands emit NO envelope. This holds across the `sl*` family and `us`
(both the plain and the `--from-commit`/`--from-file` scopes).

## Edge cases

- **A file named `--` or `--help`** is unreachable as a pathspec BEFORE the
  separator (`--` is the separator itself; `--help` parses as an option).
  After the separator it is data, verbatim: `hug sls -- --help` filters to a
  file literally named `--help`. (Git norm; the only cost of an unambiguous
  separator.)
- **The picker covers the separator spelling only**: `hug su src/ --` is NOT
  a picker scope — a positional before the trailing `--` is pathspec data on
  a diff command, and the trailing `--` opens the picker carrying that scope
  only in commands whose picker is pathspec-aware. To scope a picker, put
  the paths after a mid-stream separator: `hug su -- src/ --`.
- **Mid-stream second `--`**: harmless phantom (see duality above).
- **Trailing `--` is never a phantom** — it is consumed by the parser on
  every contract command.

## Two escape hatches

- Want the full-repo JSON envelope back? **Omit pathspecs** — an unscoped
  `--json` run always describes the full state.
- A scoped listing omits the trailing one-line `hug s` summary (it would
  describe the whole repo, not your scope). **`hug s`** restores it on
  demand.

## Scoped destruction: the `w-*` family

On the destructive `w-*` commands, pathspecs are the **scope of
destruction** — and the scope is **narrowing-only**: a scope never widens
what the unscoped command would touch. The preview (`--dry-run`), the
confirmation list, and the destructive git call all flow through the ONE
validated pathspec set — what was previewed is what is destroyed.

```
hug w discard -- src/            # discard tracked changes under src/ only
hug w discard -s --dry-run -- src/   # PREVIEW: staged changes under src/ only
hug w purge -i -- build/         # remove ignored files under build/ only
hug w zap --dry-run -- ':(exclude)docs/'   # everything except docs/, previewed
hug w wipe -- file.js            # both staged+unstaged changes on file.js
hug w get HEAD~2 -- src/         # restore src/ to its HEAD~2 state
```

Category flags (`-s`, `-i`, `-u`) INTERSECT the scope — `-s -- src/` means
"staged changes under src/", not "all staged changes". Bare positionals
keep their pre-contract meaning (`hug w wipe file.js` ≡ `hug w wipe --
file.js`).

A scope that matches nothing touches nothing, loudly enough to trust:
`Nothing to discard; repository already clean for the specified paths.`,
exit 0. A scoped destructive omits the trailing `hug s` summary (same rule
as the listings — a scoped answer is the answer).

Want the whole tree back? That is what the `-all` variants are FOR:
`w-discard-all`, `w-purge-all`, `w-zap-all`, `w-wipe-all` are the
documented whole-tree escape hatch (like `aa` vs `a`) — they take NO
pathspecs, and a pathspec after `--` fails with exit 2 and a pointer to
the scoped form.

The wip workflow is intentionally OUT of the pathspec contract:
`w-wip`, `w-unwip`, `w-wipdel` keep `--` as a DATA separator (message /
WIP-branch name — `hug w wip -- "-fix"` makes `-fix` the message). Only
their exit discipline joined the family: unknown dash-tokens now exit 2.

## Log viewers: `llu` and `sh`

```
hug llu -- src/                  # outgoing commits touching src/
hug llu --json -- src/           # scoped JSON envelope (zero-count shape on no match)
hug sh HEAD -- src/a.py          # commit details, stats filtered to the path
hug sh HEAD src/a.py             # same — positionals are pathspecs (git parity)
hug sh -3 -- src/                # range spellings are DATA, not flags
```

`llu`'s outgoing-range computation is unchanged — the pathspecs only
filter which commits are shown. `sh` keeps its first positional as the
commit reference; everything after it (with or without the separator) is
pathspecs. A scoped `llu` omits the trailing `hug s` summary; a scoped
`sh` shows only the matching files in its stats block.

## Per-command support matrix

| Command | Pathspecs | `--json` scoped | Trailing bare `--` |
|---|---|---|---|
| `sl` / `sla` | ✅ | ✅ | inert |
| `sls` / `slu` / `slk` / `sli` / `slc` | ✅ | ✅ | inert |
| `ss` / `su` / `sw` | ✅ | — | picker (scoped) |
| `shc` / `shcp` / `shp` / `dd` | ✅ | — | inert |
| `lc` / `lf` / `lcr` | ✅ | ✅ | picker (scoped) |
| `a` | ✅ (post-`--` = exact files) | — | picker (scoped) |
| `us` | ✅ | — | staged-file selector |
| `cmod` | ✅ (scoped amend: out-of-scope changes stay in the working tree) | — | same as no pathspecs (unscoped amend) |
| `cmoda` | ❌ — `-a` amends ALL tracked changes; git itself rejects paths with `-a` (`paths ... with -a does not make sense`, loud fatal, HEAD untouched). Use `hug cmod -- <path>...` for a scoped amend | — | same as no pathspecs (unscoped amend) |
| `sh` | ✅ (the ref stays a ref; everything after it — separator or not — is pathspecs; range spellings like `-3` are DATA, not flags) | — | inert |
| `llu` | ✅ (outgoing commits touching the scope) | ✅ | inert |
| `w` (gateway) | pass-through — the subcommand owns the contract surface | — | — |
| `w-discard` / `w-purge` / `w-zap` / `w-wipe` | ✅ (the scope of destruction, narrowing only; category flags like `-s`, `-i` intersect it) | — | interactive selection arm |
| `w-get` | ✅ (the scope of the restore; `--target`/ref before `--`) | — | interactive selection arm |
| `w-discard-all` / `w-purge-all` / `w-zap-all` / `w-wipe-all` | ❌ by design — whole-tree escape hatch (like `aa` vs `a`); a pathspec after `--` fails with a pointer to the scoped form (`hug w zap-all is whole-tree; use the scoped form to filter: hug w zap -- src/.`), a bare trailing `--` is inert | — | inert |
| `w-wip` / `w-unwip` / `w-wipdel` | ❌ by design — `--` keeps its DATA meaning (message / WIP-branch name). Exit discipline only: unknown dash-tokens now exit 2 with the family template (`Messages beginning with '-' require '--'` / `Branch names beginning with '-'…`) | — | data (message / branch) |
| `fcat` | ✅ (the `<N\|commit>` target; takes exactly ONE path — from either side of the separator; two paths exit 2) | — | picker (scoped) |
| `shv` | ✅ (single commit/range token + scoped paths; `-N` is DATA at any digit length; flag-shaped tokens exit 2 with the family template) | — | inert |

Single-file commands (`fa`, `fb`, `fblame`, `fborn`, `fcon`, `llf`,
`h steps`, `stats file`) take a file ARGUMENT, not pathspecs — and they
reject extra files with exit 2 (`<cmd> accepts only one file`); a bare
trailing `--` routes to the picker where the command has one.

## Breaking changes / script migration

If you script hug, these PR-B and PR-C flips change observable behavior:

1. **Unknown dash-tokens on the `sl*` family and `us` now fail loudly.**
   Before: `hug sls -xX` exit 0 with `No staged files matching '-xX' found.`
   — a typo'd flag looked like an empty answer. After: exit 2 with
   `Unknown option: -xX. Pathspecs beginning with '-' require '--': hug sls -- -xX. See 'hug help :pathspec'.`
   Safe rewrite: if a file named `-xX` was genuinely meant, `hug sls -- -xX`.
2. **`--json` is now pathspec-scoped across the `sl*` family.** Before:
   `hug slc --json -- src/` emitted the whole-repo envelope (pathspecs
   silently ignored by contract). After: the envelope — including
   `summary.*` counts — describes only the scope:
   `hug slc --json -- src/ | jq .summary.conflicted` now counts conflicts
   under `src/` only. Scripts aggregating whole-repo counts from a scoped
   invocation must drop the pathspecs (escape hatch #1).
3. **`hug a -- <file>` stages exactly the named files.** Before it silently
   ran the equivalent of `git add -u`, staging every tracked-modified file
   you never named (fixed in v1.11.1.0, elifarley/hug-scm#300). The PR-B
   addition: `hug a -- src/ --` opens the picker SCOPED to `src/` (the scope
   is no longer silently discarded).
4. **`us` flips.** A mid-stream `--` was an error (`Unknown option: --`,
   exit 1) — now it is the separator: `hug us -- src/` unstages only files
   under `src/`. A trailing bare `--` was the same error — now it dispatches
   exactly like no arguments (the staged-file selector). The
   `--from-commit` file list is INTERSECTED with your pathspecs: they are a
   scope.
5. **Listings' trailing bare `--` is inert.** Before, `hug sl --` treated
   the `--` as a pathspec matching nothing (`No staged or unstaged files
   matching '--' found.`); now `hug sls --` is byte-identical to `hug sls`,
   summary included.
6. **Scoped listings omit the trailing summary line** (it describes the
   whole repo). Parse just the listing, or run `hug s` separately.
7. **Unknown dash-tokens on `w-discard`/`w-wipe`/`w-purge`/`w-zap` now
   fail loudly (exit 2)** — was a silent path: `hug w discard -xX` used to
   answer `Nothing to discard … from the specified paths`, exit 0, hiding
   the typo. Now: exit 2, the family template
   (`Unknown option: -xX. Pathspecs beginning with '-' require '--': hug w discard -- -xX. See 'hug help :pathspec'.`).
8. **A known flag spelled after `--` on the `w-*` family exits 2** — was
   swallowed as a path/commitish/message (worst receipt: `hug w zap --
   src/ --dry-run` silently SKIPPED the dry-run preview). Now:
   `Flags must precede '--': hug w zap --dry-run -- <path>.... See 'hug help :pathspec'.`
   A file literally named `--dry-run` remains reachable: `hug w zap -- ./--dry-run`.
   (Deviation from the spec, which claimed this for "any PR-C command":
   `sh` and `llu` treat a post-`--` flag spelling as inert pathspec DATA —
   never honored, never rejected.)
9. **Malformed magic on any PR-C command exits 2** (`Invalid pathspec:
   ':(bogus)src/'. See 'hug help :pathspec'.`) — was a silent no-match or
   unvalidated flow-through. Nothing is touched.
10. **A scope that matches nothing on a destructive is an info, exit 0**
    (`Nothing to discard; repository already clean for the specified paths.`)
    — nothing is touched. (This row corrects the spec's planned wording
    `No files matching … to <verb>.` to the shipped per-verb text.)
11. **`w-wip`/`w-unwip`/`w-wipdel` unknown dash-tokens exit 2** — was exit
    1. Their `--` keeps its DATA meaning (message / branch name), so the
    template's remedy names the real payload: `Messages beginning with '-'
    require '--': hug w wip -- "<message>".` (wip) / `Branch names beginning
    with '-' require '--': hug w unwip -- <branch>.` (unwip/wipdel).
12. **A `-all` command given a pathspec after `--` exits 2 with a
    whole-tree pointer** — was `unknown option: --`, exit 1:
    `hug w zap-all is whole-tree; use the scoped form to filter: hug w zap -- src/. See 'hug help :pathspec'.`
    A bare trailing `--` on an `-all` command is inert (identical to no
    arguments).
13. **`hug llu -- <path>` works** (scoped outgoing list, exit 0) — was
    `Unknown option: --`, exit 1. Scoped runs omit the trailing summary;
    `--json` scopes the envelope.
14. **`hug sh <ref> [path]` treats the trailing token(s) as pathspecs**
    (ref + scoped details, exit 0) — was `accepts one commit reference;
    unexpected …`, exit 1. `shp` still filters a single file: given several
    pathspecs it uses the first and warns.
15. **`hug w wips -- <msg>` composes as `wip --stay -- <msg>`** — the
    gateway used to append `--stay` AFTER your args, polluting the branch
    name (`WIP/….draftSTAY`) and never applying stay.
16. **`hug w <unknown-subcommand>` exits 2** — was usage printed, exit 0.
17. **`hug fcat` joins the contract** — `hug fcat <N|commit> --` opens the
    interactive file picker (pick-file-first; `fcat <N> <path> --` scopes it);
    two paths exit 2 (`accepts only one file`) — was silent first-wins; unknown
    dash-tokens exit 2 with the flag-naming template — was a ref-resolution
    error; flags-after-positional on `shv` converge to the same exit-2 family
    — was exit 1 `Unexpected`.

Exit statuses: usage errors (unknown dash-token, valueless value-flags) are
exit 2 (`HUG_EX_USAGE`). Scoped vs unscoped `--json` never changes exit
status — only the envelope's contents.
