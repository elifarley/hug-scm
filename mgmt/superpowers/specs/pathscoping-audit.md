# Path Scoping Audit — Lay of the Land

**Date**: 2026-08-15
**Scope**: All hug commands that accept, could accept, or interact with file-path / pathspec arguments.
**Goal**: Map current behavior, identify bugs, document gaps, and propose how path scoping SHOULD work for the best developer experience.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Command-by-Command Audit](#2-command-by-command-audit)
3. [Bugs](#3-bugs)
4. [Inconsistencies](#4-inconsistencies)
5. [Documentation Gaps](#5-documentation-gaps)
6. [How It SHOULD Work](#6-how-it-should-work)
7. [Open Questions](#7-open-questions)

---

## 1. Architecture Overview

### How hug dispatches

`bin/hug` is a thin dispatcher: detects git/hg, runs `exec git "$@"`. Git aliases (defined in `git-config/.gitconfig`) map short names to scripts in `git-config/bin/`. For example, `sla` → `statusbase --long`.

### Two pathspec-handling patterns

**Pattern A — Ad-hoc `*` catch-all**
Used by: `statusbase`, `sls`, `slu`, `slk`, `sli`, `slc` *(amended 2026-08-16: `shv` removed — it has its own hand-rolled `--` split and passes pathspecs through to `dd_commit_diff … -- "${pathspecs[@]}"`; ad-hoc but `--`-proper, not a silent catch-all)*

```bash
pathspecs=()
for arg in "$@"; do
  case "$arg" in
    --json) ... ;;
    -c|--count) ... ;;
    *) pathspecs+=("$arg") ;;   # bare "--" collected as a pathspec!
  esac
done
```

Pathspecs are forwarded through `list_files_with_status` → `list_*_files` → `git <cmd> -- "${pathspecs[@]}"`. Works, but doesn't properly consume `--` as a separator.

**Pattern B — `parse_pathspecs` + `parse_common_flags`**
Used by: `shc`, `shcp`, `shp`, `cmod`, `cmoda`

```bash
eval "$(parse_pathspecs "$@")"           # splits at first --
eval "$(parse_common_flags "${_pathspec_pre_args[@]}")"
# later: git <cmd> "$@" -- "${_pathspec_pathspecs[@]+"${_pathspec_pathspecs[@]}"}"
```

Properly separates flags from pathspecs. The library function `parse_pathspecs` in `hug-cli-flags` handles `--` correctly.

**Pattern C — Direct positional arg**
Used by: `fa`, `fb`, `fblame`, `fborn`, `fcon`, `stats-file`, `h-steps`, `llf/llfp/llfs`

Single file as positional arg, passed with explicit `-- "$file"` to git.

**Pattern D — Pass-through**
Used by: `l`, `ll`, `c`, `ca`

All remaining args forwarded verbatim to `git log` / `git commit`. Git handles `--` and pathspecs natively.

### Critical ordering rule

`parse_pathspecs` **MUST** run before `parse_common_flags`. The latter intercepts a trailing bare `--` as an interactive-file-selection trigger. If run first, it consumes the separator before `parse_pathspecs` can see it.

### The `--` duality

| Context | `--` meaning |
|---------|-------------|
| `parse_pathspecs` | Pathspec separator (first `--` splits args) |
| `parse_common_flags` (trailing bare `--`) | Interactive file selection trigger |
| `parse_common_flags` (mid-stream via getopt) | Standard option terminator |
| Pattern A scripts | Literal pathspec (accidentally) |

---

## 2. Command-by-Command Audit

### Legend

- **Pathspec**: YES/NO/SINGLE — whether the command accepts path arguments
- **Pattern**: A (ad-hoc), B (parse_pathspecs), C (direct positional), D (pass-through), N/A
- **`--` handling**: PROPER / MISSING / N/A
- **Help docs paths**: YES / NO — whether help text mentions path support
- **Quoting guidance**: YES / NO — whether help text warns about glob quoting

### Status Commands

| Command | Pathspec | Pattern | `--` handling | Help docs | Quoting | Notes |
|---------|:--------:|:-------:|:------------:|:---------:|:-------:|-------|
| `hug s` | NO | N/A | PROPER (getopt) | N/A | N/A | Summary-only; rejects positional args |
| `hug sl` | YES | A (via statusbase) | **MISSING** | NO | NO | Alias → `statusbase -uno` |
| `hug sla` | YES | A (via statusbase) | **MISSING** | NO | NO | Alias → `statusbase --long` |
| `hug sls` | YES | A | **MISSING** | **NO HELP** | NO | No `show_help()` at all; `--help` swallowed as pathspec |
| `hug slu` | YES | A | **MISSING** | **NO HELP** | NO | Same as sls |
| `hug slk` | YES | A | **MISSING** | **NO HELP** | NO | Same as sls |
| `hug sli` | YES | A | **MISSING** | **NO HELP** | NO | Same as sls |
| `hug slc` | YES | A | **MISSING** | YES | NO | Only sl* script with help text |
| `hug sw` | YES | B | PROPER | YES | YES | Reference implementation |
| `hug ss` | YES | B | PROPER | YES | YES | Reference implementation |
| `hug su` | YES | B | PROPER | YES | YES | Reference implementation |
| `hug sx` | NO | N/A | N/A | N/A | N/A | Quick snapshot; no path concept |
| `statusbase` | YES | A | **MISSING** | **NO HELP** | NO | Base for sl/sla; no `show_help()` |

### Show Commands

| Command | Pathspec | Pattern | `--` handling | Help docs | Quoting | Notes |
|---------|:--------:|:-------:|:------------:|:---------:|:-------:|-------|
| `hug sh` | NO | N/A | N/A | N/A | N/A | Commit-only; **feature gap** — sibling shc/shcp/shp all support paths |
| `hug shc` | YES | B | PROPER | YES | YES | Reference implementation |
| `hug shcp` | YES | B | PROPER | YES | YES | Reference implementation |
| `hug shp` | SINGLE | B | PROPER | YES | YES | Single-file only; warns on multiple |
| `hug shv` | YES | A (ad-hoc) | PROPER | YES | NO | Hand-rolled `--` split; skips `parse_common_flags` entirely |
| `hug dd` | YES | A (ad-hoc) | PROPER | YES | NO | Via `dd_dispatch` in hug-git-difftool lib |

### Log/History Commands

| Command | Pathspec | Pattern | `--` handling | Help docs | Quoting | Notes |
|---------|:--------:|:-------:|:------------:|:---------:|:-------:|-------|
| `hug l` | YES | D (pass-through) | PROPER | YES | NO | Verbatim to `git log` |
| `hug ll` | YES | D (pass-through) | PROPER | YES | NO | Verbatim to `git log` |
| `hug llu` | NO | N/A | N/A | N/A | N/A | Hardcoded `@{u}..HEAD` range |
| `hug llf` | SINGLE | C | PROPER | YES | NO | Single file via `--follow --` |
| `hug llfp` | SINGLE | C | PROPER | YES | NO | Delegates to llf |
| `hug llfs` | SINGLE | C | PROPER | YES | NO | Delegates to llf |
| `hug lc` | SINGLE | via parse_common_flags | **BUG** | YES | NO | `--` consumed by `parse_common_flags` |
| `hug lcr` | SINGLE | via parse_common_flags | **BUG** | YES | NO | Same `--` consumption bug |
| `hug lf` | SINGLE | via parse_common_flags | **BUG** | YES | NO | Same `--` consumption bug |
| `hug log-outgoing` | NO | N/A | N/A | N/A | N/A | Branch comparison only |
| `hug stats` | NO | N/A | N/A | N/A | N/A | Gateway to subcommands |
| `hug stats-file` | SINGLE | C | PROPER | YES | NO | Direct `-- "$file"` |
| `hug stats-author` | NO | N/A | N/A | N/A | N/A | Positional = author name |
| `hug stats-branch` | NO | N/A | N/A | N/A | N/A | Positional = branch name |

### Commit Commands

| Command | Pathspec | Pattern | `--` handling | Help docs | Quoting | Notes |
|---------|:--------:|:-------:|:------------:|:---------:|:-------:|-------|
| `hug c` | NO (pass-through) | D | N/A | NO | NO | Forwards `$@` to `git commit` |
| `hug ca` | NO (pass-through) | D | N/A | NO | NO | Forwards `$@` to `git commit -a` |
| `hug caa` | NO | N/A | N/A | N/A | N/A | Stages all then commits |
| `hug ccp` | NO | N/A | N/A | N/A | N/A | Commit refs only |
| `hug cmod` | YES | B | PROPER | **NO** | **NO** | **Undocumented pathspec support** |
| `hug cmoda` | YES | B | PROPER | **NO** | **NO** | **Undocumented pathspec support** |
| `hug cmv` | NO | N/A | N/A | N/A | N/A | Operates on commits/branches |

### Staging Commands

| Command | Pathspec | Pattern | `--` handling | Help docs | Quoting | Notes |
|---------|:--------:|:-------:|:------------:|:---------:|:-------:|-------|
| `hug a` | YES | A (positional) | **CONFLICT** | YES | NO | `--` = interactive selection, NOT pathspec separator |
| `hug aa` | NO | N/A | N/A | YES | N/A | Explicitly rejects args |
| `hug us` | YES | two-stage, loud unknown-flag reject | **errors loudly** on `--` today | YES | NO | Demands ≥1 path; zero args → interactive selector over staged files (git-us:144-158). *(Amended 2026-08-16 — originally mismarked "A / N/A"; `--` hits the `-*` error case at git-us:92-94, it is not a silent catch-all. See the pathspec-contract design spec §5.5.)* |

### File Commands

| Command | Pathspec | Pattern | `--` handling | Help docs | Quoting | Notes |
|---------|:--------:|:-------:|:------------:|:---------:|:-------:|-------|
| `hug fa` | SINGLE | C | PROPER | YES | NO | `--follow` limits to single file |
| `hug fb` | SINGLE | C | PROPER | YES | NO | Direct `-- "$@"` |
| `hug fblame` | SINGLE | C | PROPER | YES | NO | Via `remaining_args` |
| `hug fborn` | SINGLE | C | PROPER | YES | NO | Direct `-- "$@"` |
| `hug fcat` | TARGET+PATH | C | N/A (`:` syntax) | YES | N/A | `git show "$commit:$path"` *(amended 2026-08-17: the CLI surface is positional `hug fcat <commit> <path>`; the `:` form is the internal git-show syntax this row describes — probe: `hug fcat HEAD:src/a.py` errors "Missing arguments")* |
| `hug fcon` | SINGLE | C | PROPER | YES | NO | Direct `-- "$@"` |

### Working-Directory Commands

| Command | Pathspec | Pattern | `--` handling | Help docs | Quoting | Notes |
|---------|:--------:|:-------:|:------------:|:---------:|:-------:|-------|
| `hug w discard` | YES | A | PROPER¹ | YES | NO | Break-early flag parsing |
| `hug w discard-all` | NO | N/A | N/A | N/A | N/A | Rejects args |
| `hug w get` | YES | A | **BUG** | YES | NO | `-u` + files broken; missing `--` in git restore |
| `hug w purge` | YES | A | PROPER¹ | YES | NO | Collect-all flag parsing |
| `hug w purge-all` | NO | N/A | N/A | N/A | N/A | Rejects args |
| `hug w wipe` | YES | C | PROPER | YES | NO | Delegates to `w discard` |
| `hug w wipe-all` | NO | N/A | N/A | N/A | N/A | Delegates to `w discard-all` |
| `hug w zap` | YES | A | PROPER¹ | YES | NO | Break-early flag parsing |
| `hug w zap-all` | NO | N/A | N/A | N/A | N/A | Rejects args |
| `hug w wip` | NO | N/A | N/A | N/A | N/A | Message string only |
| `hug w unwip` | NO | N/A | N/A | N/A | N/A | Branch name only |
| `hug w wipdel` | NO | N/A | N/A | N/A | N/A | Branch name only |

### HEAD Commands

| Command | Pathspec | Pattern | `--` handling | Help docs | Quoting | Notes |
|---------|:--------:|:-------:|:------------:|:---------:|:-------:|-------|
| `hug h back` | NO | N/A | N/A | N/A | N/A | |
| `hug h files` | NO | N/A | N/A | N/A | N/A | |
| `hug h restore` | NO | N/A | N/A | N/A | N/A | |
| `hug h rewind` | NO | N/A | N/A | N/A | N/A | |
| `hug h rollback` | NO | N/A | N/A | N/A | N/A | |
| `hug h squash` | NO | N/A | N/A | N/A | N/A | |
| `hug h steps` | SINGLE | C | PROPER | YES | NO | Single file; interactive fallback |
| `hug h undo` | NO | N/A | N/A | N/A | N/A | |

---

## 3. Bugs

### BUG-1: `--` misinterpreted as pathspec in Pattern A commands (all `sl*` + `statusbase`)

**Severity**: Medium (works by accident; breaks if file named `--` exists)

**Affected**: `sl`, `sla`, `sls`, `slu`, `slk`, `sli`, `slc`, `statusbase`

**Root cause**: No `--` case in the argument-parsing `case` statement. Bare `--` falls into `*) pathspecs+=("$arg")`, becoming a literal pathspec.

**Reproduction**:
```bash
hug sls -- src/     # "--" becomes pathspec; accidentally works because
                    # git sees: git diff --cached -- -- src/
                    # first -- is git's separator, second "--" matches no file
```

**Impact**: Correct by coincidence. Would break if a file literally named `--` existed in the repo.

**Fix**: Add `--) shift; break ;;` to each `case` statement, or migrate to `parse_pathspecs`.

---

### BUG-2: `--` consumed by `parse_common_flags` in `lc`, `lcr`, `lf`

**Severity**: Medium (works in common case; breaks when path collides with branch/tag name)

**Affected**: `lc`, `lcr`, `lf`

**Root cause**: These scripts call `parse_common_flags` directly on `$@` (without pre-splitting via `parse_pathspecs`). `parse_common_flags` encounters `--` mid-argument-list, consumes it (shifts past it), and passes only the post-`--` args into `$@`. The separator itself is discarded.

**Reproduction**:
```bash
hug lc "import" -- src/main.js
# parse_common_flags eats "--", passes "src/main.js" as remaining arg
# Resulting git command: git log -S "import" src/main.js  (missing --)
# Fails if a branch/tag named "src/main.js" exists
```

**Fix**: Use `parse_pathspecs` before `parse_common_flags` (the documented ordering rule), then re-inject `-- "${_pathspec_pathspecs[@]}"` when delegating to `hug ll`.

---

### BUG-3: `git-w-get` — `-u` flag breaks with file arguments

**Severity**: Medium (valid use case rejected)

**Affected**: `w get`

**Root cause**: When `-u` (upstream) is set, the first remaining positional arg is still captured as `target_identifier` instead of being treated as a file path.

**Reproduction**:
```bash
hug w get -u file.txt
# file.txt becomes target_identifier, not a file
# Error: "Cannot specify --upstream with a specific commit or integer N."
```

**Fix**: When `use_upstream=true`, skip the target_identifier extraction step and treat all remaining `$@` as files.

---

### BUG-4: `git-w-get` — Missing `--` separator in `git restore` call

**Severity**: Low (files starting with `-` would be misinterpreted as flags)

**Affected**: `w get`

**Location**: `git-w-get`, line ~324

**Current code**:
```bash
git restore --source="$commit" --worktree "${files_to_reset[@]}"
```

**Expected**:
```bash
git restore --source="$commit" --worktree -- "${files_to_reset[@]}"
```

---

### BUG-5: `sl*` commands swallow `--help` as a pathspec

**Severity**: Low (misleading UX; no data corruption)

**Affected**: `sls`, `slu`, `slk`, `sli` (and `statusbase`)

**Root cause**: No `show_help()` function and no `-h`/`--help` case in the arg loop. `--help` falls into `*) pathspecs+=("$arg")`, causing a search for files matching the pathspec `--help`.

**Reproduction**:
```bash
hug sls --help    # No help shown; searches for file named "--help"
```

---

### BUG-6: `git-sh` silently overwrites commit ref with path argument

**Severity**: Low (confusing UX when paths are accidentally passed)

**Affected**: `sh`

**Root cause**: `sh` accepts only a commit ref as a positional arg. If a user runs `hug sh HEAD -- src/`, the `*` catch-all assigns `src/` to `commit_ref`, overwriting `HEAD`.

**Expected**: Should either support pathspecs (like `shc`/`shcp`/`shp`) or reject extra args with a clear error.

---

## 4. Inconsistencies

### INCONSISTENCY-1: Two parsing patterns coexist

Pattern A (ad-hoc) and Pattern B (`parse_pathspecs`) serve the same purpose but have different `--` semantics. Commands in the same category (e.g., `slc` vs `sw` in @status) use different patterns.

**Recommendation**: Standardize on Pattern B (`parse_pathspecs`) for all commands that accept `-- <pathspec>...`.

### INCONSISTENCY-2: `--` semantics are position-disambiguated but undocumented

The two intentional `--` meanings are cleanly disambiguated by position:

| Usage | Meaning | Mechanism |
|-------|---------|-----------|
| `hug sw --` | Interactive file selection (trailing bare `--`) | `parse_common_flags` detects last-arg `--` |
| `hug sw -- src/` | Pathspec separator (mid-stream) | getopt treats as option terminator; `src/` becomes positional |

This is a sound design — no actual conflict. The problem is that it's undocumented: no help text or article explains this positional rule. Users familiar with git's `--` (always a pathspec separator) may be surprised that `hug a --` opens a picker instead of doing nothing.

Note: Pattern A scripts (`sl*`, `statusbase`) don't participate in this design at all — they have no `parse_common_flags` call and just accidentally collect `--` as a literal pathspec (BUG-1).

### INCONSISTENCY-3: Break-early vs collect-all flag parsing in `w-*` commands

| Pattern | Scripts | Behavior |
|---------|---------|----------|
| Break-early (`break` on `*`) | `w-discard`, `w-get` | Custom flags must come before common flags |
| Collect-all (gather into temp_args) | `w-purge` | Custom flags accepted in any position |

`hug w discard --force -u file.txt` fails silently because the break-early parser stops at `--force`, never seeing `-u`. `hug w purge --force -u file.txt` works because collect-all processes all args.

### INCONSISTENCY-4: Pathspec cardinality varies without clear rationale

| Cardinality | Commands |
|-------------|----------|
| Multiple pathspecs | `sl*`, `sw`, `ss`, `su`, `shc`, `shcp`, `l`, `ll`, `a`, `us`, `w-discard`, `w-purge`, `w-zap` |
| Single file only | `shp`, `fa`, `fb`, `fblame`, `fborn`, `fcon`, `llf`, `lc`, `lcr`, `lf`, `stats-file`, `h-steps` |
| No paths | `s`, `sx`, `llu`, `sh`, `c`, `ca`, `caa`, `h-back`, `h-rewind`, etc. |

Single-file commands silently accept multiple args but pass them all to git, where `--follow` breaks with >1 file (e.g., `fa`, `fb`). No validation or error.

### INCONSISTENCY-5: Quoting guidance only in reference commands

Only `sw`, `ss`, `su`, `shc`, `shcp` have a `PATH FILTERING:` section in their help text stating "Globs must be quoted to prevent shell expansion." All other path-accepting commands omit this.

---

## 5. Documentation Gaps

### GAP-1: No pathspec help article

There is no `hug help :pathspec` or `hug help :paths` article. The article system has only 3 articles (`hug-101`, `agents`, `worktree`). A pathspec article would be the single highest-leverage documentation fix.

**Proposed content**:
- What pathspecs are and how git handles them
- Quoting rules (`'*.md'` vs `*.md`)
- `--` separator usage and the interactive-selection duality
- Git magic pathspecs (`:(glob)`, `:(icase)`) — passed through verbatim
- Directory scoping vs file globbing
- Per-command reference table

### GAP-2: `parse_pathspecs` undocumented in developer docs

The ordering invariant ("`parse_pathspecs` MUST run before `parse_common_flags`") is the key correctness rule for pathspec support. It's documented only in code comments (`hug-cli-flags:21-23`) and a design spec (`mgmt/plans/2026-05-05-shc-shcp-path-filtering-design.md`), never in:
- `git-config/lib/README.md`
- `CLAUDE.md`
- Any help article

### GAP-3: `cmod`/`cmoda` pathspec support completely undocumented

Both commands support `-- <path>...` via `parse_pathspecs` (verified in source), but help text says only `hug cmod [OPTIONS]` — no path mention at all.

### GAP-4: `sls`, `slu`, `slk`, `sli` have no help text at all

These commands have no `show_help()` function. Users cannot discover their pathspec support, `--json` flag, `-c/--count` mode, or `-q/--quiet` option.

### GAP-5: Git magic pathspecs undocumented but functional

`:(glob)`, `:(icase)`, `:(exclude)` are passed through to git verbatim (the plumbing does `-- "${pathspecs[@]}"`), so they work. But:
- Zero mentions in any help text, article, or docs page
- The design spec explicitly defers them as "undefined"
- Users have no way to discover they're available

### GAP-6: No quoting guidance in 25+ commands

Only 6 commands (`sw`, `ss`, `su`, `shc`, `shcp`, `shv`) warn about glob quoting. The remaining 25+ path-accepting commands provide no quoting guidance.

### GAP-7: `hug help @` category descriptions don't mention path filtering

The `@status`, `@show`, `@history` category descriptions don't mention that their commands support path filtering. Users browsing help categories can't discover this capability.

---

## 6. How It SHOULD Work

### Principle 1: Every command that touches files SHOULD accept pathspecs

Commands that operate on files should be filterable by path. Currently missing pathspec support where it would be valuable:

| Command | Proposed pathspec behavior |
|---------|---------------------------|
| `hug sh` | `hug sh HEAD -- src/` — show commit with file stats, filtered to `src/` |
| `hug llu` | `hug llu -- src/` — show outgoing commits touching `src/` |
| `hug h back` | Debatable — `hug h back 3 -- src/` could limit which files are kept staged |
| `hug h files` | `hug h files 5 -- src/` — preview files for HEAD movement, filtered |

### Principle 2: Standardize on Pattern B (`parse_pathspecs`)

All commands accepting `-- <pathspec>...` should use `parse_pathspecs` from `hug-cli-flags`. This:
- Properly handles `--` as a separator
- Aligns with the documented ordering rule
- Eliminates the accidental "works by coincidence" behavior in Pattern A commands
- Makes the `--` / interactive-selection duality explicit

**Migration priority** (Pattern A → Pattern B):
1. `statusbase` / `sls` / `slu` / `slk` / `sli` / `slc` (highest impact — most-used commands)
2. `shv` (currently hand-rolled)
3. `dd` (via `dd_dispatch`)

### Principle 3: Consistent help text structure

Every path-accepting command should have this section:

```
PATH FILTERING:
    Append -- <path>... to restrict output to matching paths.
    Globs must be quoted to prevent shell expansion.

    hug <cmd> -- src/ tests/          # Filter to two directories
    hug <cmd> --stat -- '*.java'      # Stats for Java files only
```

Reference: `git-sw` (lines 42-47) is the gold standard.

### Principle 4: Validate single-file commands

Commands that accept only a single file (`fa`, `fb`, `fblame`, etc.) should validate and reject multiple file args with a clear error, rather than silently passing them to git where `--follow` breaks.

### Principle 5: Central pathspec documentation

Create `hug help :pathspec` covering:
- Basic pathspec syntax (wildcards, directories, negation)
- Quoting rules and why they matter
- `--` separator usage and the interactive-selection duality
- Git magic pass-through (`:(glob)`, `:(icase)`) — documented as "passed through to git"
- Per-command support matrix

### Principle 6: Document the `--` positional rule

The current `--` semantics are well-designed and position-disambiguated:
- **Trailing bare `--`** → interactive file selection
- **Mid-stream `--` followed by args** → pathspec separator (git semantics)

No behavioral change needed — just document this rule consistently in the pathspec article and in each command's help text. Pattern A scripts should migrate to Pattern B so they participate in this design rather than bypassing it.

---

## 7. Open Questions

1. **Should `hug sh` gain pathspec support?** Its siblings (`shc`, `shcp`, `shp`) all support paths. The design spec (`2026-05-05-shc-shcp-path-filtering-design.md`) may have intentionally excluded it.

2. **Should `hug llu` gain pathspec support?** Filtering outgoing commits by path would be useful (`hug llu -- src/` = "what commits touching src/ haven't been pushed?"). The range is hardcoded to `@{u}..HEAD`, but `git log @{u}..HEAD -- src/` works.

3. **Should negative pathspecs (`:(exclude)`) be officially supported?** Currently passed through to git but explicitly deferred. The plumbing handles it; the question is whether to document and test it.

4. **Should `hug a -- file` stage `file` or open interactive selection?** Current behavior: opens interactive selection (if `file` is the only arg). This conflicts with git's `git add -- file` semantics. But changing it would break the muscle memory of `hug a --` for interactive selection.

5. **Pattern A migration scope**: Should all sl* commands migrate to Pattern B in one batch, or incrementally?

6. **Should `parse_pathspecs` be documented in `git-config/lib/README.md`?** This seems uncontroversial — the function exists, is used by 5 scripts, and its ordering rule is critical.

---

## Appendix: Shared Library Pathspec Functions

### `parse_pathspecs` (hug-cli-flags)

Splits `$@` at the first `--` into `_pathspec_pre_args` and `_pathspec_pathspecs`. Must be called before `parse_common_flags`.

```bash
eval "$(parse_pathspecs "$@")"
# _pathspec_pre_args=(HEAD --stat)
# _pathspec_pathspecs=('*.java' 'src/')
```

### `list_files_with_status` (hug-select-files)

Accepts `--staged`, `--unstaged`, `--untracked`, `--ignored`, `--conflicts`, `--cwd`, and remaining args as pathspecs. Routes to `list_*_files` functions.

### `list_*_files` (hug-git-files)

Each function (`list_staged_files`, `list_unstaged_files`, `list_untracked_files`, `list_ignored_files`, `list_conflicted_files`) accepts `--status`, `--cwd`, and remaining args as pathspecs. All pass pathspecs to git with `-- "${pathspecs[@]}"`.

### `count_files_with_status` (hug-select-files)

Accepts a state enum and pathspecs. Passes pathspecs to git with `-- "${pathspecs[@]}"`. Used by `sl* -c` mode.

---

## Appendix B: Suggested Enhancements

Three approaches, ordered by ambition.

---

### 1. Conservative — "Fix what's broken, document what works"

**What it is**: Fix the 6 bugs, migrate Pattern A → Pattern B, add help text and a `hug help :pathspec` article.

Concrete steps:
1. Migrate `statusbase`/`sls`/`slu`/`slk`/`sli`/`slc` to `parse_pathspecs` (eliminates BUG-1, BUG-5)
2. Fix `lc`/`lcr`/`lf` to use `parse_pathspecs` before `parse_common_flags` (eliminates BUG-2)
3. Fix `w get -u` file handling and add `--` to `git restore` call (BUG-3, BUG-4)
4. Add `show_help()` to `sls`/`slu`/`slk`/`sli` with PATH FILTERING section
5. Add PATH FILTERING section to `cmod`/`cmoda` help
6. Write `hug help :pathspec` article
7. Document `parse_pathspecs` ordering rule in `git-config/lib/README.md`

**What it unlocks**: Every path-accepting command behaves consistently and is documented. Users can rely on `-- <path>` working the same everywhere. The `sl*` commands stop swallowing `--help`.

**What it risks**: Low risk. Pattern A → Pattern B migration could subtly change `--` handling in edge cases (e.g., `hug sls --` currently runs a listing; after migration it would trigger interactive selection if `parse_common_flags` is also added). Need to decide: do `sl*` commands get interactive selection via `--`, or do they keep `--` as purely a pathspec separator?

**What would make it fail**: If the `sl*` migration introduces regressions in count mode (`-c`) or JSON mode (`--json`) because `parse_pathspecs` changes arg ordering. The existing `sl*` tests would catch this — but only if they cover `--` usage.

**First testable version**: Migrate `git-statusbase` to `parse_pathspecs`. Run `hug sla`, `hug sla 'TODO*'`, `hug sla -- 'TODO*'`, `hug sla -c 'TODO*'`, `hug sla --json`. All should produce identical output to the current behavior, except `hug sla --` would now trigger interactive selection instead of listing everything.

---

### 2. Ambitious — "Pathspec middleware: one library, all commands, auto-generated docs"

**What it is**: Replace the current fragmented approach (each script parses its own args) with a shared pathspec middleware layer. Every command that wants path support declares it in metadata; the middleware handles parsing, validation, help text generation, and shell completion.

Concrete steps:
1. Extend `hug-cli-flags` with a `declare_pathspec_mode` function:
   ```bash
   # Called early in each script:
   declare_pathspec_mode \
     --cardinality=multi|single|none \
     --interactive              # bare -- opens picker
     --count                    # supports -c/--count
   ```
2. The function sets up parsing, validates cardinality (rejects >1 file for `single` mode), and populates `_pathspec_pathspecs` consistently.
3. Auto-generate the PATH FILTERING help section from the declaration — every command gets identical formatting.
4. Add pathspec-aware shell completion: `hug sla <TAB>` completes paths, `hug sla -- <TAB>` completes paths, `hug sla -<TAB>` completes flags.
5. Add a `hug pathspec` test harness that validates pathspec handling across all commands.

**What it unlocks**:
- **Zero-inconsistency path handling**: every command uses the same library, same `--` semantics, same cardinality validation.
- **Auto-documentation**: PATH FILTERING sections generated from declarations, never stale.
- **Shell completion**: tab-complete pathspecs after `--` in every command.
- **Single-file validation**: commands like `fa`, `fb`, `fblame` auto-reject multiple files with a clear error.
- **Easy extensibility**: adding pathspec support to a new command is a one-line declaration.

**What it risks**: Medium risk. Refactoring ~15 scripts to use a new middleware layer is a significant change. Each script has its own flag parsing quirks (`--json`, `--count`, `-q`, custom flags). The middleware must be flexible enough to coexist with per-command custom flags without becoming a monolith.

**What would make it fail**: If the middleware tries to handle too much (custom flags, interactive mode, JSON output) it becomes the "one ring" that every script depends on but nobody fully understands. The key is to keep it scoped to *pathspec parsing and validation only*, leaving everything else to each script.

**First testable version**: Implement `declare_pathspec_mode` for `single` cardinality. Migrate `git-fa` (simplest single-file command) to use it. Verify: `hug fa README.md` works, `hug fa README.md CHANGELOG.md` errors with "fa accepts only one file." Then migrate `git-shc` (multi-cardinality with `parse_pathspecs`) and verify no regression.

---

### 3. Strange but powerful — "Named focus groups: `hug focus`"

**What it is**: Named, composable pathspec groups that persist across commands and sessions. Not a single env var — a proper focus management system with multiple named lenses.

#### CLI surface

```bash
# Create named focus groups (each can contain multiple paths/globs)
hug focus add "ipv4" src/ipv4/
hug focus add "ipv6" src/ipv6/ docs/ipv6/
hug focus add "python" 'hug-scm-mcp-server/**/*.py'
hug focus add "tests" 'tests/**/*.sh' 'tests/**/*.py'

# Use a focus group with any command
hug sla --focus ipv4              # untracked files in src/ipv4/
hug sw --focus ipv6               # diff scoped to ipv6 paths
hug ll -5 --focus python          # last 5 commits touching Python files
hug shc HEAD --focus tests        # files changed in HEAD, filtered to tests

# Set a default focus (used when no --focus given)
hug focus set ipv4
hug sl                            # now auto-scoped to ipv4
hug focus clear                   # remove default; back to full repo

# Management
hug focus list                    # show all named focus groups + active default
hug focus show ipv4               # show paths in the "ipv4" focus
hug focus rm ipv4                 # delete a named focus group
hug focus clear-all               # delete all focus groups

# Modify an existing focus group
hug focus add ipv4 src/ipv4-new/  # adds path to existing "ipv4" group
hug focus set ipv4 src/ipv4/      # replaces "ipv4" contents (also sets as default)
hug focus set ipv4                # sets "ipv4" as the active default (no path change)
```

#### Storage

Focus groups are stored in `.git/hug-focus` (gitignored by default — personal workflow config). Format:

```ini
# .git/hug-focus
[ipv4]
src/ipv4/

[ipv6]
src/ipv6/
docs/ipv6/

[python]
hug-scm-mcp-server/**/*.py

[tests]
tests/**/*.sh
tests/**/*.py

# Active default (optional)
[active]
default = ipv4
```

Could also support a committed `.hug-focus` in the repo root for team-shared focus groups (like `.editorconfig` for pathscoping). The precedence: `.git/hug-focus` (personal) overrides `.hug-focus` (shared).

#### Priority / override rules

1. **Explicit `-- <path>` on a command** → highest priority, overrides everything
2. **`--focus <name>` on a command** → uses that named focus group
3. **Active default** (set via `hug focus set`) → used when neither of the above
4. **No focus** → full repo (current behavior)

This means:
```bash
hug focus set ipv4
hug sla                    # scoped to ipv4 (default)
hug sla --focus tests      # scoped to tests (--focus overrides default)
hug sla -- '*.md'          # scoped to *.md (explicit pathspec overrides everything)
```

#### Integration with existing commands

The focus resolution happens in the shared libraries, not in each command script. The existing `parse_pathspecs` / pathspec-collecting code gets one additional step:

```bash
# In the shared pathspec resolution layer (e.g., new function resolve_pathspecs):
resolve_pathspecs() {
  # 1. If explicit pathspecs given via -- or positional args, use them
  if [[ ${#_pathspec_pathspecs[@]} -gt 0 ]]; then
    return
  fi
  # 2. If --focus <name> given, resolve from .git/hug-focus
  if [[ -n "${_focus_name:-}" ]]; then
    _pathspec_pathspecs=($(load_focus_group "$_focus_name"))
    return
  fi
  # 3. If active default focus set, resolve it
  local default_focus
  default_focus=$(get_active_focus)
  if [[ -n "$default_focus" ]]; then
    _pathspec_pathspecs=($(load_focus_group "$default_focus"))
  fi
}
```

Each command only needs to add `--focus` to its recognized flags and call `resolve_pathspecs` after `parse_pathspecs`. The `hug s` summary line could show the active focus:

```
🟣 HEAD: 25edb6d 🌿main...origin/main │ K:3 I:0 │ 🎯 ipv4
```

#### What it unlocks

- **Workflow scoping**: Working on the networking subsystem? `hug focus set ipv4`. Every command is automatically scoped. Switch to tests: `hug focus set tests`. No repetitive `-- <path>`.
- **Multiple parallel contexts**: Unlike a single env var, you can define `ipv4`, `ipv6`, `tests`, `python` and switch between them instantly.
- **Agent ergonomics**: An AI agent can `hug focus add "task-scope" src/module/` at the start of a task and use `--focus task-scope` on every subsequent command. Reduces token cost and error rate vs. repeating `-- src/module/` each time.
- **Team-shared scopes**: Committed `.hug-focus` gives the whole team the same focus groups (like "backend", "frontend", "infra").
- **Composable with explicit paths**: `hug sw -- tests/` still works; explicit overrides focus.
- **Zero breaking changes**: No `--focus`, no active default → current behavior.

#### What it risks

- **Forgotten focus**: User sets a default, walks away, comes back confused by filtered output. Mitigated by the `🎯 focus-name` indicator in `hug s` output.
- **Storage format complexity**: INI parsing in bash is doable but fiddly. Could use a simpler format (one path per line, blank-line-separated groups).
- **Scope creep**: The temptation to add focus-aware commit (`hug c --focus ipv4` = only commit ipv4 files) creates a maintenance burden. Better to keep focus as a *viewing* concept initially.
- **Gitignored file**: `.git/hug-focus` is per-worktree, not per-user. Multiple worktrees of the same repo could have different focuses (which might be a feature, not a bug).

#### What would make it fail

If focus resolution is implemented per-command instead of in the shared library. Every command adding its own `--focus` parsing and `.git/hug-focus` reading would replicate the current inconsistency problem. The entire value is in centralizing the resolution.

#### First testable version

1. Implement `load_focus_group` and `get_active_focus` in a new `hug-focus` library (parse `.git/hug-focus`).
2. Add `resolve_pathspecs` call to `list_files_with_status` only.
3. Create a `.git/hug-focus` file manually with one group.
4. Test: `hug sla` (no focus → full listing), set active default, `hug sla` (filtered), `hug sla -- '*.py'` (explicit overrides).
5. This validates the core mechanic with zero changes to any command script.
