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
| Mutating, explicit-path | `a` `us` `cmod` `cmoda` | which files are staged / unstaged / committed | `a`: opens the picker (scoped to any given pathspecs); `us`: opens the staged-file selector (same as no arguments); `cmod`/`cmoda`: inert |
| Diff & search pickers | `ss` `su` `sw` `lc` `lf` `lcr` | the diff / search output | Opens the interactive picker, scoped to any given pathspecs |

(`shp` `shcp` `shc` `dd` also accept pathspecs — they scope the shown diff;
they have no picker arm.)

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
| `cmod` / `cmoda` | ✅ | — | inert |
| `sh` | ❌ not yet | — | — |
| `llu` | ❌ not yet | — | — |
| `w`, `w-discard`, `w-get`, other `w-*` | ❌ not yet | — | — |

Single-file commands (`fa`, `fb`, `fblame`, `fborn`, `fcon`, `llf`,
`h steps`, `stats file`) take a file ARGUMENT, not pathspecs.

## Breaking changes / script migration

If you script hug, these PR-B flips change observable behavior:

1. **Unknown dash-tokens on the `sl*` family and `us` now fail loudly.**
   Before: `hug sls -x` exit 0 with `No staged files matching '-xX' found.`
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

Exit statuses: usage errors (unknown dash-token, valueless value-flags) are
exit 2 (`HUG_EX_USAGE`). Scoped vs unscoped `--json` never changes exit
status — only the envelope's contents.
