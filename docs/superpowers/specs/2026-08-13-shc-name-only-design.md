# Design: `hug shc --name-only` — repo-relative changed-file paths

- **Issue:** [elifarley/hug-scm#266](https://github.com/elifarley/hug-scm/issues/266)
- **Companion issues (filed, out of scope here):**
  - [elifarley/hug-scm#268](https://github.com/elifarley/hug-scm/issues/268) — `hug shc <merge-commit>` shows no files (pre-existing bug, affects both modes)
  - [elifarley/hug-scm#269](https://github.com/elifarley/hug-scm/issues/269) — align path-only/name-only conventions across `wtl` vs `shc`
- **Date:** 2026-08-13
- **Branch:** `shc-name-only`

## Problem

`hug shc <range>` elides directory names in its file list (`.../` truncation), making the
output unusable for machine parsing — a script cannot recover the full repo-relative path from
the elided form. The workaround (`hug shcp -q` and parsing `diff --git a/<path> b/` headers)
ships the entire patch just to get file names, which is token-heavy.

## Solution

Add a `-n, --name-only` flag to `hug shc` that prints ONLY changed file paths, repo-relative,
one per line, no stats, no header on stdout, no elision. Exit **0 even on zero matches** (detect
emptiness via stdout). Mirrors `git diff --name-only`.

## Decisions (locked during brainstorming)

| Decision | Choice | Rationale |
|---|---|---|
| Long flag | `--name-only` | Matches `git diff --name-only` — the vocabulary the motivating use case was reaching for. |
| Short flag | `-n` | Mnemonic ("names"); **not** `-p`, which is already `--patch` in the `sh*` family (`hug sh -p`). |
| Path format | **repo-relative** | What a diff-file-list consumer needs. Deliberately diverges from `hug wtl --path-only` (absolute), because the domains differ — a worktree path is inherently absolute, a changed-file path is inherently repo-relative. Tracked in #269. |
| Exit code on zero matches | **0** | Aligns with `git diff --name-only` and the existing `shc` stat-mode "exit 0 for scriptability" philosophy. **Revises issue #266's written AC** (which said "exit 1, consistent with `wtl --path-only`") — the maintainer chose exit 0 during design. Diverges from `wtl --path-only` (exit 1); tracked in #269. |
| Implementation home | New lib function `show_changed_file_names()` in `hug-git-show` | `git-shc` already sources `hug-git-show`; satisfies the repo's "scripts stay thin, work in lib/" rule (D.R.Y./SOLID). |
| Flag plumbing | **Pre-strip** `-n/--name-only` from `"$@"` BEFORE `parse_pathspecs`/`parse_common_flags` | See "Bundled-flag hazard" below: post-eval peeling silently drops `-n` on bundled forms like `-nq`. Pre-stripping sidesteps both the extraction-loop last-wins swallow and any getopt bundling ambiguity. |
| D.R.Y. consolidation | Replace `git-shc`'s inline `*..*` range check with `is_range()` | Eliminates a raw range-string check; uses the existing library function at `hug-git-repo:297`. Included per "maximize correctness / include it". |

## Architecture

Two changes, both small and localized.

### 1. New library function — `show_changed_file_names()` in `git-config/lib/hug-git-show`

The correctness-critical insight (verified by probe — see "Correctness evidence" below): `--name-only`
is a **one-flag swap** on the existing dispatch, not a new dispatch. `git diff --name-only` /
`git diff-tree --no-commit-id --name-only -r --root` are exact behavioral drop-ins for the `--stat`
variants across every input form `shc` accepts.

Contract:

```bash
# Prints the repo-relative paths of files changed in a commit or range,
# one per line — the --name-only equivalent of git-shc's --stat output.
#
# Usage: show_changed_file_names "commit_or_range" [pathspec...]
# Parameters:
#   $1   - Commit ref, range, or N/-N form (resolved internally via resolve_commit_ref,
#          so the function is independently testable without the script wrapper).
#   $2.. - Optional pathspecs (already-exploded args, passed as-is).
# Output:
#   Repo-relative file paths to stdout, one per line. Empty on no matches.
# Exit codes:
#   0 always (zero matches → empty stdout, exit 0 — caller detects emptiness via stdout).
# Environment:
#   None read; does NOT honor HUG_QUIET (output is pure data — no header by design).
# Notes:
#   - Mirrors git-shc's dispatch EXACTLY: is_range → git diff --name-only,
#     else git diff-tree --no-commit-id --name-only -r --root.
#   - Merge-commit single-commit shows nothing (same as --stat) — known parity,
#     see #268 for the pre-existing bug this preserves.
#   - Independently callable and unit-testable (no dependency on the git-shc script).
show_changed_file_names() {
    local target="${1:-HEAD}"
    shift || true
    local -a pathspec_args=()
    [[ $# -gt 0 ]] && pathspec_args=(-- "$@")

    local resolved
    resolved=$(resolve_commit_ref "$target" "HEAD")

    if is_range "$resolved"; then
        git diff --name-only "$resolved" "${pathspec_args[@]+"${pathspec_args[@]}"}"
    else
        git diff-tree --no-commit-id --name-only -r --root "$resolved" "${pathspec_args[@]+"${pathspec_args[@]}"}"
    fi
}
```

Design points:
- **Resolves its own ref** → independently testable from BATS without the script wrapper (satisfies `lib/CLAUDE.md`'s "elegant tests" requirement).
- **No `HUG_QUIET` read** → pure data output, no header. Single Responsibility: the *script* owns the human-facing header decision; the *function* is a data producer.
- **`shift || true`** → safe under `set -euo pipefail` when called with zero pathspecs.
- **Pathspec idiom** `"${arr[@]+"${arr[@]}"}"`** is the codebase standard (matches `git-shc:153,161`).

### 2. `git-shc` script changes

**(a) Flag parsing — pre-strip BEFORE the shared parsers.** Add a small shim at the very top
of `git-shc`, BEFORE the existing `eval parse_pathspecs` / `eval parse_common_flags` calls
(currently `git-shc:111-112`):

```bash
# Pre-strip -n/--name-only before the shared parsers. This MUST happen before
# parse_pathspecs/parse_common_flags — see "Bundled-flag hazard" below.
name_only=false
declare -a shc_args=()
for arg in "$@"; do
  case "$arg" in
  -n|--name-only) name_only=true ;;
  *) shc_args+=("$arg") ;;
  esac
done
# Then the existing flow runs on shc_args instead of "$@":
eval "$(parse_pathspecs "${shc_args[@]}")"
eval "$(parse_common_flags "${_pathspec_pre_args[@]}")"
```

The existing `commit_ref` extraction loop (`git-shc:116-123`) is **unchanged** — it never sees
`-n`/`--name-only`, so no new case is needed there.

**Why pre-strip and not post-eval-peel:** a post-eval approach (matching `-n` in the extraction
loop) silently fails on bundled forms. See "Bundled-flag hazard" for the verified failure.

**(b) Output branch** — after `commit_ref` is resolved (existing line ~133), before the existing
`--stat` path:

```bash
if $name_only; then
  show_changed_file_names "$commit_ref" "${_pathspec_pathspecs[@]+"${_pathspec_pathspecs[@]}"}"
  exit 0
fi
```

**(c) D.R.Y. consolidation** — replace the inline range check:

```diff
-if [[ "$commit_ref" == *..* ]]; then
+if is_range "$commit_ref"; then
```

(`is_range` is `[[ "$1" == *..* ]]` — identical behavior, library-sourced.)

**(d) Help text** — add `-n, --name-only` to OPTIONS, a CAPTURING OUTPUT note, and a GIT EQUIVALENT
line (see "Help text" below).

## Correctness evidence (probe-verified, git 2.x)

Behavioral parity between `--stat` and `--name-only` across every input form:

| Input | `--stat` (current) | `--name-only` (new) | Parity |
|---|---|---|---|
| Single commit `HEAD` | diff-tree --stat | diff-tree --name-only | ✅ same files |
| Range `main..HEAD` | diff --stat | diff --name-only | ✅ same files |
| `-N` / `N` forms | resolve_commit_ref | same resolve | ✅ |
| Root commit | `--root` lists files | `--root` lists files | ✅ |
| Pathspec `-- '*.py'` | filtered | filtered | ✅ |
| Empty match (pathspec hits nothing) | exit 0, empty | exit 0, empty | ✅ |
| Rename | new path | new path | ✅ |
| **Merge commit (single)** | **empty** (plain diff-tree) | **empty** (plain diff-tree) | ✅ preserved — pre-existing bug, tracked in #268 |

The merge-commit row is preserved on purpose: changing it would make `--name-only` *diverge* from
`--stat`, breaking parity. The fix belongs to #268, which will move both modes together.

### Bundled-flag hazard (why pre-strip is mandatory)

An earlier draft of this spec peeled `-n` in the post-eval extraction loop, reasoning that
`parse_common_flags` "passes unknown flags through to `$@`." That is **wrong**, and a code roast
caught it. Reproduced on the real binary (`hug -C <repo> shc -nq HEAD` → stats output, exit 0):

- `parse_pathspecs` splits args on `--` only; it does NOT expand bundles. So `-nq HEAD` becomes
  `_pathspec_pre_args=(-nq HEAD)`.
- The extraction loop's `*)` branch assigns `commit_ref` on every non-flag token, **last-wins**.
  `-nq` matches `*)` (it isn't `-n`), sets `commit_ref=-nq`, then `HEAD` overwrites it. `name_only`
  stays `false`. Net effect: `-nq` is silently swallowed and the command runs in `--stat` mode.
- Separated forms (`-n HEAD`, `-n -q HEAD`, `--name-only HEAD`) would work under post-eval peeling,
  but the silent failure on bundles is a CRITICAL correctness hole — common CLI muscle memory
  (`-nq` to suppress the header) produces wrong output with no error.

**Pre-stripping** removes `-n`/`--name-only` from `"$@"` before *any* of the shared parsers see it,
so neither `parse_pathspecs`'s pass-through nor the extraction loop's last-wins swallow can drop it.
After pre-strip, `-nq HEAD` is *not* recognized as `-n` (it is an unknown bundle) and flows through
to `reject_flag_ref "-nq"` → loud error, exit 2. That is the correct, fail-loud behavior for an
ambiguous bundle — matching the existing `--stat`-rejection philosophy.

The existing `--stat` rejection path (`--stat` → `commit_ref` → `reject_flag_ref`) is untouched by
the pre-strip design.

### No-match hint: `--name-only` intentionally omits it (by design)

The existing `--stat` path emits a stderr hint when a pathspec matches nothing
(`git-shc:168-170`: `printf 'No files matching %s in %s\n' ...`). The proposed
`--name-only` output branch returns `exit 0` *before* that block, so `--name-only`
mode emits **no hint** on a no-match pathspec.

This divergence is **intentional and documented**, not an oversight:
- `--name-only` mode is pure machine data (no header, no legend, no `HUG_QUIET`
  coupling — see the function contract). A stderr hint would violate that contract.
- A caller detects "no matches" via empty stdout, which is unambiguous for a
  one-path-per-line format. The hint exists in `--stat` mode because that mode
  is human-facing (header on stderr, stats table on stdout) and benefits from the
  reassurance; `--name-only` is for scripts.
- Same input, two modes, two stderr behaviors is acceptable *because* the modes
  have different audiences. This mirrors the stdout/stderr discipline rule in
  `CLAUDE.md`: data commands keep stdout clean; the hint is chatter that belongs
  only in the human mode.



## Help text additions (in `git-shc` show_help)

OPTIONS block:
```
    -n, --name-only Print ONLY changed file paths (repo-relative), one per line.
                    No stats, no header on stdout, no elision. Exit 0 even on
                    zero matches (detect via empty stdout). Machine-parseable.
```

CAPTURING OUTPUT additions:
```
    hug shc -n main..HEAD            # Paths only (repo-relative, pipe-safe)
    files=$(hug shc -n -3)           # Capture changed-file list to a variable
    hug shc -n main..HEAD -- '*.py'  # Paths only, filtered to Python files
```

GIT EQUIVALENTS additions:
```
    git diff --name-only main..HEAD  →  hug shc -n main..HEAD
    git diff-tree --name-only HEAD   →  hug shc -n HEAD
```

## Tests

Per `lib/CLAUDE.md` ("changing functionality in library functions must be covered by elegant
tests"), both the library function and the script flag are tested.

**Library tests** (`tests/lib/test_hug_git_show.bats`, the show-lib home):
1. `show_changed_file_names` single commit → correct repo-relative paths
2. `show_changed_file_names` range → cumulative paths
3. `show_changed_file_names` root commit → lists root files
4. `show_changed_file_names` with pathspec → filtered
5. `show_changed_file_names` no-match pathspec → empty stdout, **exit 0**

**Script tests** (`tests/unit/test_sh.bats`, alongside existing `shc` tests):
6. `hug shc -n HEAD` / `hug shc --name-only HEAD` → paths only, no header on stdout, no `.../` elision. Also asserts stdout/stderr discipline: `2>/dev/null` leaves data intact; `2>&1 1>/dev/null` leaks nothing human-facing to stdout (the `--name-only` path emits no header by design, so this is a guard against regressions).
7. `hug shc -n main..HEAD | wc -l` equals the file count (the issue's AC pipe test)
8. `hug shc -n -3` and `hug shc -n HEAD~2` → N/-N forms work
9. `hug shc -n main..HEAD -- '*.py'` → pathspec filtering in name-only mode
10. `hug shc -n` no-match pathspec → exit 0, empty stdout (corrected AC — exit 0, not 1). **No "No files matching" hint on stderr** (see "No-match hint" below).
11. **Regression guard:** `hug shc --stat` → still rejected with help + exit 2 (existing test stays green)
12. **Bundled-flag rejection (CRITICAL regression guard):** `hug shc -nq HEAD` and `hug shc -qn HEAD` → **rejected** with help + exit 2 (NOT silently run in stats mode). This is the test that would have caught the original bundled-flag silent-drop; it must stay green.

## Deliverables

1. `show_changed_file_names()` in `git-config/lib/hug-git-show`
2. `git-shc`: `-n/--name-only` flag (pre-strip shim) + output branch + `is_range()` consolidation + help text
3. Library tests (1–5) + script tests (6–12)
4. **Sibling documentation** (every file that documents the `shc` command surface must mention `-n`):
   - `README.md:546` — extend the command signature to show `[OPTIONS]` and note `-n`.
   - `docs/commands/head.md:215` — add a `-n` example near the existing `hug shc HEAD~3..HEAD` line.
   - `docs/cookbook.md:191` — add a `hug shc -n` example alongside the existing `hug shc abc1234`.
   - `docs/skills/hug-repo-analysis/guides/bug-hunting.md:104` — note `-n` for scriptable file extraction.
5. Reference #268 and #269 from the PR body (already filed)

## Non-goals

- Changing the default `--stat` mode.
- Changing `wtl` (#269).
- Touching `shcp`/`sh`/`shp`.
- Standardizing flag names family-wide (#269).
- Altering merge-commit behavior (#268) — `--name-only` preserves `--stat`'s current (empty) merge behavior for parity.
