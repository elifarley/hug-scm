# Design: `shc` deferred follow-ups — `-z` NUL mode, unborn-HEAD error, positional strictness, diff-tree consolidation

Closes [elifarley/hug-scm#274](https://github.com/elifarley/hug-scm/issues/274) — the four
items deliberately deferred when `shc --name-only` landed
([spec](2026-08-13-shc-name-only-design.md), feature
[elifarley/hug-scm#266](https://github.com/elifarley/hug-scm/issues/266), PR
[elifarley/hug-scm#270](https://github.com/elifarley/hug-scm/pull/270)).

## Problem

The adversarial review of `shc --name-only` surfaced four weaknesses, judged and deferred
so the flag itself would land deterministic and tested:

1. **`shc -n` cannot round-trip every filename.** Git C-quotes structural characters
   (newline, backslash, quote, tab) in line mode regardless of config — probe-verified on
   git 2.34.1: a newline path arrives as ONE C-quoted line (`"we\nird"`), safe for
   line-based consumers but not the path itself, so `-n` violates its own raw-path
   contract on such names. No released hug ever split a newline filename into bogus
   lines — git's line mode never emits raw newlines, and the quotePath pin shipped
   together with `-n` in v1.9.0 (elifarley/hug-scm#270) — so this corrects the earlier
   path-injection framing, which described behavior that never existed. The real defect:
   line mode cannot round-trip structural-char paths raw. A NUL-separated mode (`-z`) is
   git's raw, unambiguous machine contract and the real fix.
2. **Unborn HEAD leaks a raw git fatal.** In a freshly `init`ed repo, `hug shc -n` (and the
   stats mode) emit `fatal: ambiguous argument 'HEAD'` with exit 128 — not house style for
   a command advertised as scriptable.
3. **Positional last-wins.** `hug shc -n main..HEAD typo` silently runs with `typo` as the
   ref: a raw git fatal, or worse a valid-ref wrong answer. The `-nq` reject-loop fixed
   this class for flag tokens; positionals still go last-wins (pre-existing in stats mode
   too).
4. **The diff-tree flag set is triplicated.** The same invocation lives in three places —
   `git-shc`'s stats path, `show_changed_file_names()` (hug-git-show), and
   `extract_files_from_commit()` (hug-file-input) — but the determinism pins
   (quotePath/relative/renames/submodules) protect only ONE of the three, so a future flag
   change silently diverges the others.

## Solution

All four in one pass, because item 4's shared helper is the natural home for item 1's `-z`
plumbing (touching the same lines twice otherwise):

1. One new plumbing function `pinned_diff()` in `hug-git-diff` owning the canonical flag
   set, the determinism pins, and the range/single dispatch — plus a `--null` mode.
2. `git shc -n -z` / `--null`: NUL-separated paths via git's native `-z`.
3. Unborn HEAD → hug-branded error (exit 1) before any git diff runs.
4. A second positional → `error_usage` (exit 2), both modes.

## Decisions (locked during brainstorming)

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | Scope: all four items | Item 4's helper is item 1's natural home; items 2–3 are small |
| D2 | Flag: `-z, --null`; **requires** `-n` (`shc -z` alone → usage error, exit 2) | Family convention (`git-s` ships `-z, --null`); mirrors the `-nq` reject-loop philosophy; git's own `-z` implies no format |
| D3 | Second positional → `error_usage` (exit 2) naming both tokens | Issue's recommendation; a second ref is always a mistake (pathspecs go after `--`) |
| D4 | Pins everywhere: stats path and `extract_files_from_commit` gain the determinism pins, with tested behavior deltas | One flag set is the point of item 4; parameterized pins would preserve the divergence the issue complains about |
| D5 | Branded error for **unborn HEAD only**; invalid refs keep today's raw git fatal (exit 128) | Preserves `show_changed_file_names`'s documented exit-128 contract; matches the issue's scope |
| D6 | Approach A: one pinned runner function in `hug-git-diff` (vs. delegating to hug-git-show, vs. a shared flag array) | Kills the fourth near-duplication too (pins repeated across `show_changed_file_names`'s own branches); reachable from every call site via `hug-git-kit` |

## Architecture

### 1. New plumbing function — `pinned_diff()` in `git-config/lib/hug-git-diff`

The ONE canonical changed-files invocation for a commit or range. Pure data out; headers,
emoji, and error policy stay at call sites (exactly as the issue sketches).

```bash
# Runs the canonical pinned changed-files invocation for a commit or range.
# Usage: pinned_diff [--null] <format> <target> [pathspec...]
# Parameters:
#   --null   - Optional, FIRST arg: NUL-separated output (--name-only only).
#   $1       - Format: --name-only | --stat. Anything else is a caller bug.
#   $2       - resolved_ref: an ALREADY-RESOLVED commit ref or range (anything
#              is_range() recognizes). N/-N shorthand resolution is the CALLER's
#              job (resolve_commit_ref) — this function does not call it, keeping
#              pinned_diff a thin, independently testable plumbing layer. Named
#              resolved_ref, not "target", so it cannot be confused with the raw
#              user input that show_changed_file_names accepts.
#   $3..     - Optional pathspecs (already-exploded args, passed as-is).
# Output:
#   Git's own --name-only / --stat stream on stdout. With --null, paths are
#   NUL-terminated and never C-quoted (git's -z semantics — output must NEVER
#   be captured into a shell variable; bash strips NUL bytes).
# Exit codes:
#   The underlying git command's. Nothing is swallowed here; callers own
#   error policy (2>/dev/null, || true, branding).
# Environment:
#   None read; does NOT honor HUG_QUIET (pure data by design).
# Pins (every invocation, immune to user/server config — the determinism
# contract from the shc --name-only adversarial review, now protecting ALL
# call sites instead of one of three):
#   -c core.quotePath=false        non-ASCII bytes (> 0x7f) print raw. Git STILL
#                                  C-quotes structural chars (newline, backslash, quote,
#                                  tab) in line mode regardless of this config — -z is
#                                  the only fully-raw stream (probe-verified, git 2.34.1)
#   -c diff.relative=false         paths stay repo-relative
#   --find-renames                 a rename lists the new path only, in BOTH
#                                  dispatch branches (diff-tree without -M
#                                  would list old+new and diverge from the
#                                  range branch)
#   --ignore-submodules=none       defeats a user's diff.ignoreSubmodules
# Notes:
#   - Dispatch: is_range <target> → `git diff <format> <pins> <target>`;
#     else → `git diff-tree --no-commit-id <format> -r --root <pins> <target>`.
#   - --null with --stat is rejected via error_usage (NUL is a --name-only
#     contract; --stat is human-formatted).
#   - Merge-commit single-commit shows nothing (diff-tree without -m) — known
#     parity with the stats mode, see elifarley/hug-scm#268.
pinned_diff() { ... }
```

Implementation shape (arrays, `set -u`-safe pathspec passthrough, `-z` threaded only into
the name-only branch):

```bash
pinned_diff() {
    local null_mode=false
    [[ "${1:-}" == "--null" ]] && { null_mode=true; shift; }
    # Arg-count guard BEFORE any positional read: under set -u, touching $1/$2 with
    # too few args dies as "unbound variable" (exit 1) — a caller bug must surface
    # as error_usage (exit 2), not a raw bash trace.
    if [[ $# -lt 2 ]]; then
        error_usage "pinned_diff: expected [--null] <format> <resolved_ref> [pathspec...]"
    fi
    local format="$1" resolved_ref="$2"
    shift 2
    local -a path_args=()
    [[ $# -gt 0 ]] && path_args=(-- "$@")
    local -a zflag=()
    $null_mode && zflag=(-z)

    if [[ "$format" != "--name-only" && "$format" != "--stat" ]]; then
        error_usage "pinned_diff: unknown format '$format' (expected --name-only or --stat)"
    fi
    if $null_mode && [[ "$format" != "--name-only" ]]; then
        error_usage "pinned_diff: --null is only valid with --name-only"
    fi

    if is_range "$resolved_ref"; then
        git -c core.quotePath=false -c diff.relative=false \
            diff "$format" "${zflag[@]+"${zflag[@]}"}" --find-renames --ignore-submodules=none \
            "$resolved_ref" "${path_args[@]+"${path_args[@]}"}"
    else
        git -c core.quotePath=false -c diff.relative=false \
            diff-tree --no-commit-id "$format" -r --root "${zflag[@]+"${zflag[@]}"}" \
            --find-renames --ignore-submodules=none \
            "$resolved_ref" "${path_args[@]+"${path_args[@]}"}"
    fi
}
```

**Reachability (verified):** `hug-git-diff` is loaded by `hug-git-kit`, and every
`hug-file-input` consumer sources `hug-git-kit` before `hug-file-input` (git-a,
git-untrack, git-us, git-ccp). `git-shc` sources the kit directly. No new sourcing
edges. Belt-and-braces: `hug-common` itself lists `hug-git-diff` in `_hug_common_libs`,
so every standard-template script already carries it. `error_usage`/`is_range` are
already available at every call site (`error_usage` is defined in `hug-output`, loaded
transitively via hug-common's lib list; `is_range` is defined in hug-git-repo).

### 2. Call-site changes — three thin wrappers

| Site | Before | After |
|---|---|---|
| `hug-git-show: show_changed_file_names` (line ~183) | own git calls; pins duplicated across its range/single branches | resolve ref → `pinned_diff ${z:+"--null"} --name-only "$resolved" "$@"`; doc contract unchanged (exit-128 propagation, no HUG_QUIET) |
| `git-shc` stats path (line ~201) | two unpinned branches (`git diff --stat` / `git diff-tree --stat`) | one `stats_output=$(pinned_diff --stat "$commit_ref" …)`; emoji headers stay in the script, keyed off `is_range` |
| `hug-file-input: extract_files_from_commit` (line ~141) | unpinned `git diff-tree --no-commit-id --name-only -r --root` | same rev-parse guard + `pinned_diff --name-only "$commit" 2>/dev/null \|\| true` — the swallow policy stays AT the call site. Post-refactor the swallow ALSO masks exit 127 (an unsourced `pinned_diff`), not just git's 128: document that dependency in hug-file-input's header comment and in the swallow comment itself. Not a live bug — every current consumer loads hug-git-diff via hug-common's lib list — but a future consumer that drops hug-common inherits a silently-empty file list |

`show_changed_file_names` gains an optional leading `-z`/`--null` (mirrors the CLI
vocabulary; `pinned_diff` itself takes only the long form):

```bash
# Usage: show_changed_file_names [-z|--null] "commit_or_range" [pathspec...]
show_changed_file_names() {
    local null_mode=false
    case "${1:-}" in -z | --null) null_mode=true; shift ;; esac
    ...
    local -a zflag=()
    $null_mode && zflag=(--null)
    pinned_diff "${zflag[@]+"${zflag[@]}"}" --name-only "$resolved" "$@"
}
```

Its doc-comment "keep them in sync with hug-file-input" note is deleted — replaced by
"delegates to `pinned_diff`, the single canonical invocation". Output contracts:
line mode — paths raw for non-ASCII bytes, while git C-quotes structural chars (one
quoted token per line — safe, but not the path; the pin changes nothing here); with
`-z` — paths NUL-terminated and fully raw (including structural chars), never captured
(callers pipe to `xargs -0` / `read -d ''`).

**Blast radius (verified by grep):** `show_changed_file_names` has exactly one bin caller
(git-shc) + tests. `extract_files_from_commit` has four (git-a, git-ccp, git-untrack,
git-us) — they receive raw, rename-collapsed, repo-relative paths instead of
config-dependent output, which is strictly more correct for paths fed back into git
commands.

### 3. `git-shc` script changes (items 1–3)

**Arg loop** — add the `-z` token and the second-positional guard (both ref-assigning
branches, so `-3 main..HEAD` fails exactly like `main..HEAD -3`):

```bash
name_only=false
null_sep=false
commit_ref=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  -n | --name-only) name_only=true; shift ;;
  -z | --null)      null_sep=true; shift ;;
  -*)
    reject_flag_ref "$1"
    [[ -n "$commit_ref" ]] && error_usage "unexpected second argument '$1' — commit ref is already '$commit_ref' (pathspecs go after --)"
    commit_ref="$1"; shift ;;
  *)
    [[ -n "$commit_ref" ]] && error_usage "unexpected second argument '$1' — commit ref is already '$commit_ref' (pathspecs go after --)"
    commit_ref="$1"; shift ;;
  esac
done
```

**Post-loop coupling guard:**

```bash
if $null_sep && ! $name_only; then
  error_usage "-z/--null is only valid with -n/--name-only"
fi
```

**Unborn-HEAD guard** — one check after `check_git_repo`, before mode dispatch (covers
single-commit, range shorthand `-3`, explicit ranges, both modes). An unborn repo has zero
commits, so every ref fails; branding once up front covers them all:

```bash
# Unborn HEAD (fresh init): every ref below would fail with a raw git fatal.
# Brand it (issue #274 item 2). Invalid-ref raw fatals (exit 128) in BORN
# repos remain the documented contract (show_changed_file_names doc).
git rev-parse --verify -q HEAD >/dev/null 2>&1 ||
  error "no commits yet (unborn HEAD) — nothing to show; make a commit first"   # exit 1
```

**`-n` dispatch** threads the flag as a leading token (the arg loop has already consumed
`"$@"` — the ref lives in `$commit_ref`, pathspecs in `_pathspec_pathspecs`, so the flag
is prepended explicitly; an args-array refactor is fine too, the contract is only:
`-z` leads, and nothing is captured on the way out — command substitution would strip
NULs):

```bash
if $name_only; then
  if $null_sep; then
    show_changed_file_names -z "$commit_ref" "${_pathspec_pathspecs[@]+"${_pathspec_pathspecs[@]}"}"
  else
    show_changed_file_names "$commit_ref" "${_pathspec_pathspecs[@]+"${_pathspec_pathspecs[@]}"}"
  fi
  exit 0
fi
```

**Stats path** — both branches collapse to:

```bash
stats_output=$(pinned_diff --stat "$commit_ref" "${_pathspec_pathspecs[@]+"${_pathspec_pathspecs[@]}"}")
```

with the existing `is_range`-keyed stderr headers, no-match hint, and HUG_QUIET behavior
untouched. Command substitution is safe here: `--stat` output contains no NUL bytes.

The `pathspec_args` builder (git-shc:178-181) is DELETED in this change: its only
consumers are the two git calls this single `pinned_diff` call replaces (git-shc:193,
201), and the `-n` path already uses `_pathspec_pathspecs` directly (git-shc:171). Name
the deletion explicitly so the implementer doesn't ship a dead builder.

## Registered behavior deltas (deliberate — D4, "pins everywhere")

These are the point of the unification: the pins stop protecting one of three sites.
All deltas are tested and cited in the PR body as intended changes.

| Site | Delta | Old → New |
|---|---|---|
| stats | rename | two lines (del old + add new) → one `{old => new}` line |
| stats | submodules | honored user `diff.ignoreSubmodules` → always shown (`=none` resets it) |
| `extract_files_from_commit` (git-a, git-ccp, git-untrack, git-us) | non-ASCII paths, rename, submodules | config-dependent output → non-ASCII raw (quotePath pin; structural chars STAY C-quoted in line mode — git's behavior, not a hug delta), rename-collapsed (new path only), submodule-deterministic |
| all sites | `diff.relative` | paths always repo-relative even if a user sets `diff.relative=true` (belt-and-braces for tree-to-tree diffs; uniformity is the win) |

**Probe-refuted delta (dropped from this table):** "stats special-char paths:
C-quoted → raw" does NOT exist — probe on git 2.34.1 shows `--stat` output
byte-identical with and without `-c core.quotePath=false` on BOTH dispatch branches
(diff-tree single-commit, diff range). The pin governs only bytes > 0x7f, and `--stat`
ignores it entirely (control: the pin demonstrably works for `--name-only` non-ASCII —
`café.txt` prints raw vs `"caf\303\251.txt"`). The pin stays in the set for uniformity,
documented as inert for `--stat`. Consequences: no "stats now prints raw paths" claim in
the PR body/changelog, and the stats special-char test asserts byte-identity pinned vs
unpinned, not rawness. Newer gits changed `--stat` quoting/width handling as late as
2.54, so CI's git gets its own probe before commit 2 lands its changelog claims (probe
item 6 below).

Non-deltas (regression safety): for plain-ASCII paths with default-ish config, output is
byte-identical to today — that expectation is itself a test. Merge-commit parity
([elifarley/hug-scm#268](https://github.com/elifarley/hug-scm/issues/268)) is preserved
unchanged.

## Correctness evidence to gather during implementation (probe before trusting)

The prior spec's "probe-verified" discipline — these git behaviors must be confirmed
before the plan is written on the project's git floor: **2.34** (Ubuntu 22.04 LTS class
— the platform this spec's own probes ran on, git 2.34.1). Commit 3 also declares the
floor in README prerequisites. CI's git (ubuntu-latest, currently newer) gets its own
re-confirmation where an item says so — "verified on the floor" does not imply
"verified on CI":

1. `git diff-tree --no-commit-id -z --name-only -r --root HEAD` emits exactly `path\0`
   per entry, final entry NUL-terminated, **no trailing newline**. `--no-commit-id` is
   load-bearing: without it, the commit hash is emitted as the first NUL entry
   (probe-verified). The `pinned_diff` invocation already carries it.
2. `--find-renames` + `-z` + `--name-only` on a rename → new path only (consistent with
   the line-mode contract).
3. `-z` disables C-quoting entirely — INCLUDING the structural chars that line mode
   always quotes (probe-verified: `back\slash.txt` and `we\nird` print raw,
   NUL-terminated) — so the `core.quotePath=false` pin is redundant-but-harmless in `-z`
   mode; keep it for uniformity, document the redundancy.
4. A bad ref through `pinned_diff` propagates exit 128 + git's fatal (no swallowing).
5. `--stat` output for ASCII paths is byte-identical pinned vs unpinned.
6. `--stat` output for special-char paths under `-c core.quotePath=false` vs default —
   BOTH dispatch branches, on the floor git AND CI's git. Already probed on 2.34.1:
   byte-identical — the pin is inert for `--stat` (this is what dropped delta row 1);
   re-confirm on CI's git before commit 2 lands its changelog claims.

## Help text additions (in `git-shc` show_help)

```text
OPTIONS:
    ...
    -z, --null      With -n only: separate paths with NUL (\0) instead of
                    newline. Handles filenames containing newlines; pair with
                    xargs -0 / read -d ''. Without -n: usage error.
```

- `-n` entry: "Assumes filenames contain no newlines" → "Paths print raw for non-ASCII
  bytes (core.quotePath=false pin); git still C-quotes structural characters (newline,
  backslash, quote, tab) in line mode — use `-z` for a fully raw, NUL-separated stream."
  The old wording implied newlines break `-n`; they don't — the path arrives as one
  C-quoted token. The truthful contract is what makes `-z` the honest fix.
- `ARGUMENTS`: add "At most one positional (commit ref or range) is accepted; a second is
  a usage error."
- `CAPTURING OUTPUT`: add `hug shc -n -z main..HEAD | xargs -0 <cmd>` and the NUL-safety
  note.
- `GIT EQUIVALENTS`: add the `-z` line (`git diff-tree -z --no-commit-id --name-only -r
  --root HEAD → hug shc -n -z HEAD`).

## Tests

| File | Covers |
|---|---|
| `tests/lib/test_hug_git_diff.bats` **(new)** | `pinned_diff`: range/single dispatch; `--name-only`/`--stat`; `--null` NUL output; `--null`+`--stat` → exit 2; unknown format → exit 2; pins honored under hostile config (test repo sets `core.quotePath=true`, `diff.renames=false`, `diff.ignoreSubmodules=all` → output still raw / rename-collapsed / submodules shown); pathspec passthrough; bad ref → exit 128 |
| `tests/unit/test_sh.bats` (shc section) | `shc -n -z`: NUL-separated (od/xxd assertion), incl. filename with embedded newline (`$'we\nird'`) — line mode asserts ONE C-quoted line `"we\nird"` (the actual before-behavior — git never split it), `-z` mode asserts raw bytes + NUL terminator; `shc -z` w/o `-n` → exit 2 + usage message; second positional → exit 2 naming both tokens (stats mode AND `-n` mode); unborn HEAD (`git init` only) → branded message, exit 1, no raw `fatal:` (all ref forms: none, `1`, `-3`, `main..HEAD`); stats deltas (rename collapse; special-char paths stay C-quoted → byte-identity pinned vs unpinned per the probe-refuted-delta note); existing `-n` line-mode tests stay green |
| `tests/lib/test_hug-file-input.bats` | `extract_files_from_commit`: raw paths under `core.quotePath=true`; rename → new path only |
| `tests/lib/test_hug_git_show.bats` | `show_changed_file_names` regression (thin-wrapper refactor keeps line-mode byte-identical); `-z` leading-token passthrough |

**NUL-testing technique (project learning, mandatory):** bash cannot hold NUL — assert
via a pipe (`hug shc -n -z | od -An -c` / `xxd -p`), NEVER via BATS `$output` (it drops
NUL bytes and the assertion would vacuously pass on the wrong output). Same class as the
`sl*` NUL work tracked in [elifarley/hug-scm#249](https://github.com/elifarley/hug-scm/issues/249).

**Audit step (before commit 3 lands):** grep every internal `git shc` caller
(`HUG_QUIET=T git shc …` in sh, shp, shcp, h files/squash, lol, cmv) and confirm none
passes two positionals — spot-check says they pass one ref + optional `--` pathspecs;
the spec makes it a verified step, not an assumption.

## Docs

- `docs/commands/head.md` — `shc` section: `-z` flag, positional rule, deltas note.
- `git-config/lib/README.md` — `pinned_diff` entry (the canonical invocation; when to
  call it vs `show_changed_file_names`).
- PR body: `Closes elifarley/hug-scm#274`, cites the behavior-delta table.

## Deliverables — 3 atomic commits, each independently green

1. `feat(lib)`: add `pinned_diff` to hug-git-diff + `tests/lib/test_hug_git_diff.bats`
   (pure addition; no caller changes).
2. `refactor`: adopt `pinned_diff` at the three call sites + delta/regression tests +
   lib README entry (pins everywhere; behavior deltas registered above).
3. `feat(shc)`: `-z/--null` + second-positional rejection + unborn-HEAD guard + help/docs
   updates.

## Non-goals

- `git-shcp`'s `-p` diff-tree site and `git-config/lib/python/deps.py`'s diff-tree call —
  adjacent duplicates outside the issue's three named sites; noted for a possible future
  pass.
- The `sl*` family NUL mode ([elifarley/hug-scm#249](https://github.com/elifarley/hug-scm/issues/249))
  — separate surface, shares only the NUL-testing learning.
- Branding invalid-ref errors in born repos (exit-128 contract stays).
- Merge-commit parity ([elifarley/hug-scm#268](https://github.com/elifarley/hug-scm/issues/268))
  — pre-existing, deliberately preserved.
