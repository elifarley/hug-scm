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
3. Unborn HEAD → hug-branded error (exit 1) before any git diff runs — HEAD-derived
   ref forms only (explicit refs still work in orphan repos; see Architecture §3).
4. A second positional → `error_usage` (exit 2), both modes.

## Decisions (locked during brainstorming)

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | Scope: all four items | Item 4's helper is item 1's natural home; items 2–3 are small |
| D2 | Flag: `-z, --null`; **requires** `-n` (`shc -z` alone → usage error, exit 2) | Family convention (`git-s` ships `-z, --null`); mirrors the `-nq` reject-loop philosophy; git's own `-z` implies no format |
| D3 | Second positional → `error_usage` (exit 2) naming both tokens | Issue's recommendation; a second ref is always a mistake (pathspecs go after `--`) |
| D4 | Pins everywhere: stats path and `extract_files_from_commit` gain the determinism pins, with tested behavior deltas. The rename axis is a TWO-VALUED CONTRACT: display callers pin `--find-renames` (collapsed), action-list callers pin `--no-renames` (both sides) | One flag set is the point of item 4; parameterized pins would preserve the divergence the issue complains about. Amendment (user-directed during roast reception): `hug a --from-commit` & co. were working fine — a consolidation must not silently drop the deleted side of a rename from action lists. The determinism pins stay non-negotiable everywhere; the rename stance is pinned EXPLICITLY in both directions (never config-dependent, never a per-site ad-hoc pick) |
| D5 | Branded error for **unborn HEAD only**, and only for HEAD-derived ref forms; invalid refs keep today's raw git fatal (exit 128) | Preserves `show_changed_file_names`'s documented exit-128 contract; matches the issue's scope. Scoping amendment (probe-driven): orphan repos (`git switch --orphan`) have unborn HEAD WITH commits — explicit refs must keep working there, so the guard fires only when the resolved ref mentions HEAD |
| D6 | Approach A: one pinned runner function in `hug-git-diff` (vs. delegating to hug-git-show, vs. a shared flag array) | Kills the fourth near-duplication too (pins repeated across `show_changed_file_names`'s own branches); reachable from every call site via `hug-git-kit` |

## Architecture

### 1. New plumbing function — `pinned_diff()` in `git-config/lib/hug-git-diff`

The ONE canonical changed-files invocation for a commit or range. Pure data out; headers,
emoji, and error policy stay at call sites (exactly as the issue sketches).

```bash
# Runs the canonical pinned changed-files invocation for a commit or range.
# Usage: pinned_diff [--null] [--no-renames] <format> <resolved_ref> [pathspec...]
# Parameters:
#   --null       - Optional leading flag: NUL-separated output (--name-only only).
#   --no-renames - Optional leading flag: renames list BOTH sides — the ACTION-LIST
#                  contract (staging/untrack lists need the deleted side). Default is
#                  the DISPLAY contract (--find-renames: new path only / collapsed
#                  `{old => new}` stat line). Both stances are explicit and
#                  config-immune — neither depends on the user's diff.renames.
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
#   2    - usage errors this function rejects itself: too few core args,
#          unknown format, --null with --stat (all via error_usage).
#   Else - the underlying git command's (0 on success; 128 + git's fatal on
#          a bad ref). Nothing is swallowed here; callers own error policy
#          (2>/dev/null, || true, branding).
# Environment:
#   None read; does NOT honor HUG_QUIET (pure data by design).
# Pins (every invocation, immune to user/server config — the determinism
# contract from the shc --name-only adversarial review, now protecting ALL
# call sites instead of one of three):
#   -c core.quotePath=false        non-ASCII bytes (> 0x7f) print raw, in BOTH
#                                  --name-only and --stat output. Git STILL C-quotes
#                                  structural chars (newline, backslash, quote, tab)
#                                  in line-oriented output regardless of this config —
#                                  -z is the only fully-raw stream (probe-verified,
#                                  git 2.34.1)
#   -c diff.relative=false         paths stay repo-relative
#   --find-renames / --no-renames  the rename CONTRACT, pinned explicitly in both
#                                  directions. Default (--find-renames, display):
#                                  a rename lists the new path only, in BOTH dispatch
#                                  branches. --no-renames (action lists): both sides.
#                                  Neither stance reads the user's diff.renames.
#   --ignore-submodules=none       defeats a user's diff.ignoreSubmodules
# Notes:
#   - Dispatch: is_range <resolved_ref> → `git diff <format> <pins> <resolved_ref>`;
#     else → `git diff-tree --no-commit-id <format> -r --root <pins> <resolved_ref>`.
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
    local null_mode=false no_renames=false
    [[ "${1:-}" == "--null" ]] && { null_mode=true; shift; }
    [[ "${1:-}" == "--no-renames" ]] && { no_renames=true; shift; }
    # Arg-count guard BEFORE any positional read: under set -u, touching $1/$2 with
    # too few args dies as "unbound variable" (exit 1) — a caller bug must surface
    # as error_usage (exit 2), not a raw bash trace.
    if [[ $# -lt 2 ]]; then
        error_usage "pinned_diff: expected [--null] [--no-renames] <format> <resolved_ref> [pathspec...]"
    fi
    local format="$1" resolved_ref="$2"
    shift 2
    local -a path_args=()
    [[ $# -gt 0 ]] && path_args=(-- "$@")
    local -a zflag=()
    $null_mode && zflag=(-z)
    # Rename stance is a never-empty scalar, so plain "$rename_flag" is set -u-safe
    # without the + guard the possibly-empty arrays need. Explicit BOTH ways — the
    # invocation never inherits the user's diff.renames config.
    local rename_flag=--find-renames
    $no_renames && rename_flag=--no-renames

    if [[ "$format" != "--name-only" && "$format" != "--stat" ]]; then
        error_usage "pinned_diff: unknown format '$format' (expected --name-only or --stat)"
    fi
    if $null_mode && [[ "$format" != "--name-only" ]]; then
        error_usage "pinned_diff: --null is only valid with --name-only"
    fi

    if is_range "$resolved_ref"; then
        git -c core.quotePath=false -c diff.relative=false \
            diff "$format" "${zflag[@]+"${zflag[@]}"}" "$rename_flag" --ignore-submodules=none \
            "$resolved_ref" "${path_args[@]+"${path_args[@]}"}"
    else
        git -c core.quotePath=false -c diff.relative=false \
            diff-tree --no-commit-id "$format" -r --root "${zflag[@]+"${zflag[@]}"}" \
            "$rename_flag" --ignore-submodules=none \
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

**Reachability exception — the TEST harness (verified):** the above holds for BIN
contexts only. `tests/lib/test_hug-file-input.bats` loads just `test_helper` +
`hug-common` + `hug-file-input`, and hug-common's 12-lib list does NOT include
hug-git-repo — the only definition site of `is_range`. Unfixed, commit 2 turns
`extract_files_from_commit` → `pinned_diff` → `is_range` into exit 127 inside the
spec-mandated `2>/dev/null || true` swallow: empty output, every existing extract test
fails (`assert_line "file1.txt"` vs nothing), and the no-change test passes vacuously —
the worst kind of green. Commit 2 therefore adds
`load '../../git-config/lib/hug-git-repo'` to that test file (called out in the Tests
table).

### 2. Call-site changes — three thin wrappers

| Site | Before | After |
|---|---|---|
| `hug-git-show: show_changed_file_names` (line ~183) | own git calls; pins duplicated across its range/single branches | resolve ref → `pinned_diff "${zflag[@]+"${zflag[@]}"}" --name-only "$resolved" "$@"` (zflag array, the same idiom pinned_diff itself uses — sketches get transcribed, so no ad-hoc expansion forms); doc contract unchanged (exit-128 propagation, no HUG_QUIET) |
| `git-shc` stats path (line ~201) | two unpinned branches (`git diff --stat` / `git diff-tree --stat`) | one `stats_output=$(pinned_diff --stat "$commit_ref" …)`; emoji headers stay in the script, keyed off `is_range` |
| `hug-file-input: extract_files_from_commit` (line ~141) | unpinned `git diff-tree --no-commit-id --name-only -r --root` | same rev-parse guard + `pinned_diff --no-renames --name-only "$commit" 2>/dev/null \|\| true` — ACTION-LIST contract: renames keep BOTH sides, output byte-identical to today (probe receipt in the delta table). The swallow policy stays AT the call site. Post-refactor the swallow ALSO masks exit 127 (an unsourced `pinned_diff`) and exit 2 (`pinned_diff`'s own error_usage guards) — not just git's 128: document that dependency in hug-file-input's header comment and in the swallow comment itself. Not a live bug — every current consumer loads hug-git-diff via hug-common's lib list — but a future consumer that drops hug-common inherits a silently-empty file list |

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
(callers pipe to `xargs -0 -r` / `read -d ''`).

**Blast radius (verified by grep):** `show_changed_file_names` has exactly one bin caller
(git-shc) + tests. `extract_files_from_commit` has four (git-a, git-ccp, git-untrack,
git-us) — they receive raw, repo-relative, submodule-deterministic paths instead of
config-dependent output: strictly more deterministic, and strictly better for non-ASCII
path handling. These are ACTION-LIST consumers (git-a:181 `mapfile < <(extract_files_from_commit …)` →
`hug_add_with_summary`; git-us/git-untrack same shape around their `--from-commit` paths;
git-ccp: `mapfile < <(extract_files_from_commit "$source_commit")`), so they call
`pinned_diff --no-renames`: both sides of a rename keep listing and their behavior is
byte-identical to today for the rename axis and ASCII paths (probe: `diff` clean against
the unpinned invocation on the ASCII rename fixture); the registered non-ASCII flip
(C-quoted → raw) applies to these consumers too — see the delta table. The
rename axis is the ONE pin that is a contract rather than a constant — display callers
pin collapse, action callers pin expansion — and it is explicit in both directions, so
no call site ever inherits the user's `diff.renames` config.

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

**Unborn-HEAD guard** — after `check_git_repo` AND after `resolve_commit_ref`, before
mode dispatch, scoped to HEAD-DERIVED ref forms only. Premise correction (probe, git
2.34.1): unborn HEAD does NOT imply zero commits — after `git switch --orphan` (git ≥
2.23; gh-pages-style flows), HEAD-verify fails while `hug shc master` works today
(`diff-tree master` exit 0). An unconditional guard would block valid explicit refs
with a factually wrong "make a commit first" message. The guard therefore fires only
when the RESOLVED ref still mentions HEAD — the empty default (`HEAD`), `N`
(`HEAD~N`), `-N` (`HEAD~N..HEAD`), explicit `HEAD…` forms, and git's `@` alias
forms (`@`, `@~N`, `@^…`, `@{N}`), which pass through resolution unchanged.
`@{-N}` (previous checkout) is deliberately exempt: it reads the HEAD reflog,
which does not exist while HEAD is unborn (probe on 2.34.1: `git rev-parse
@{-1}` in an orphan repo → exit 128), so it can only be unresolvable here and
keeps the raw fatal like any invalid explicit ref (D5). Post-review, `@{u}`/
`@{upstream}` join it as deliberate D5 escapees (same probe → exit 128 in an
unborn repo; the digit-guarded `'@{'[0-9]*` arm does not match the `u`).
Explicit refs
(branches, tags, SHAs) keep today's behavior exactly: they work in orphan state and
die with the raw exit-128 fatal when invalid (D5 unchanged):

```bash
# Unborn HEAD, HEAD-derived refs only (issue #274 item 2). An unconditional
# check would mis-block `hug shc master` in a git-switch --orphan repo —
# HEAD-unborn does not mean commit-less. resolve_commit_ref maps the default
# to HEAD and N/-N to HEAD~N[..HEAD] (pure string mapping, no git calls), so
# running this AFTER resolution, `*HEAD*` plus the narrow `@` arms is the
# complete set of HEAD-dependent forms: @ (alias), @~N, @^…, @{N} (HEAD
# reflog). A broad `@*` arm would also catch @{-N} (previous checkout) —
# wrong per D5: @{-N} reads the HEAD reflog, which does not exist while HEAD
# is unborn (probe: rev-parse @{-1} in an orphan repo → exit 128), so it is
# just an unresolvable ref and keeps git's raw fatal.
# Invalid explicit refs keep git's raw exit-128 fatal (show_changed_file_names
# doc contract). REVISED post-review: the *HEAD* substring also sweeps refs
# that RESOLVE while HEAD is unborn — origin/HEAD, FETCH_HEAD (and ORIG_HEAD/
# MERGE_HEAD when present), even a real branch literally named `A-HEAD` — so
# the body rescues: verify the REF first, only then fall back to HEAD. The
# branded path fires only for refs unresolvable while HEAD is unborn; this
# supersedes the original registration of `A-HEAD` as an acceptable false
# positive.
case "$commit_ref" in
  *HEAD* | @ | @~* | @^* | '@{'[0-9]*)
    git rev-parse --verify -q "$commit_ref" >/dev/null 2>&1 ||
      { git rev-parse --verify -q HEAD >/dev/null 2>&1 ||
          error "no commits yet (unborn HEAD) — nothing to show; make a commit first"; }   # exit 1
    ;;
esac
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

PR-body rule: cite each delta at its verified scope. The rename delta below is
single-commit-branch-only at default config — the range branch ALREADY collapses renames
(`diff.renames` defaults true in porcelain since git 2.9; probe on 2.34.1: unpinned
`git diff --stat A..B` prints `b.txt => renamed-b.txt | 0`), so the pin's range-branch
effect is hostile-config normalization, not a user-visible change.

| Site | Delta | Old → New |
|---|---|---|
| stats, BOTH branches | non-ASCII paths | C-quoted (`"caf\303\251.txt" \| 1 +`) → raw (`café.txt \| 1 +`) — probe on 2.34.1, BOTH dispatch branches. Structural chars (`back\slash.txt`, `we\nird`) stay C-quoted either way — no delta for them |
| stats, single-commit branch (diff-tree) | rename | two lines (del old + add new) → one `{old => new}` line — probe on 2.34.1: `5 files changed` → `4 files changed` on the rename fixture (plumbing does no rename detection unpinned) |
| stats, range branch (git diff) | rename | NO delta at default config — porcelain already collapses. The pin normalizes only hostile config (probe: `-c diff.renames=false` prints two lines; pinned prints one). Do NOT cite this as a user-visible change in the PR body |
| stats | submodules | honored user `diff.ignoreSubmodules` → always shown (`=none` resets it) |
| `extract_files_from_commit` (git-a, git-ccp, git-untrack, git-us) | non-ASCII paths, submodules | config-dependent output → non-ASCII raw (quotePath pin; structural chars STAY C-quoted in line mode — git's behavior, not a hug delta), submodule-deterministic |
| git-a/us/untrack/ccp `--from-commit` on a rename commit | action-list completeness | NO CHANGE — deliberately. The action contract pins `--no-renames`: both sides of a rename keep listing, byte-identical to today (probe on 2.34.1: today's unpinned output == pinned `--no-renames` output, `diff` clean). An earlier draft applied the display pin (`--find-renames`) here and registered the lost deletion side as a trade-off — rejected in review: `hug a --from-commit` was working, and a consolidation must not silently shrink action lists |
| all sites | `diff.relative` | paths always repo-relative even if a user sets `diff.relative=true` (belt-and-braces for tree-to-tree diffs; uniformity is the win) |

**Delta-registration correction (the earlier refutation was fixture-bad):** the
original delta row said "stats special-char paths: C-quoted → raw". A first probe
"refuted" it with a `--stat` fixture containing NO non-ASCII path — structural chars
(`back\slash.txt`, `we\nird`) are C-quoted in `--stat` regardless of quotePath, so that
fixture proved byte-identity for structural chars ONLY and the refutation
over-generalized to "the pin is inert for `--stat`". Corrected probe on git 2.34.1 with
a non-ASCII fixture, BOTH dispatch branches:

```
unpinned:  "caf\303\251.txt" | 1 +        pinned:  café.txt | 1 +
```

So the TRUE contract, registered in the table above: non-ASCII paths in stats mode flip
C-quoted → raw — real, user-visible, CITE it in the PR body/changelog. Structural chars
stay C-quoted in `--stat` either way (byte-identity holds for structural-only fixtures —
no delta, no claim). Lesson now encoded in probe item 6: a quoting probe's fixture must
contain BOTH a non-ASCII and a structural-char path; a fixture missing either class
proves nothing about quotePath. Newer gits changed `--stat` width/quoting handling as
late as 2.54, so CI's git still gets its own probe before commit 2 lands its changelog
claims.

Non-deltas (regression safety): for plain-ASCII paths, ABSENT renames (see the rename
deltas above — a rename flips `5 files changed` to `4 files changed` on the
single-commit DISPLAY branch), and default-ish config, output is byte-identical to
today — that expectation is itself a test. The action-list path is stronger:
byte-identical INCLUDING renames (`--no-renames` probe receipt in the delta table) —
`hug a --from-commit` and its three siblings keep their exact working behavior. Merge-commit parity
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
5. `--stat` output for ASCII paths is byte-identical pinned vs unpinned — on a fixture
   with NO renames (a rename flips it: the registered single-branch collapse delta;
   same fixture discipline as item 6, applied to this item after round 4 of review).
6. `--stat` output under `-c core.quotePath=false` vs default, with a fixture containing
   BOTH a non-ASCII and a structural-char path — BOTH dispatch branches, on the floor
   git AND CI's git. Probed on 2.34.1: non-ASCII flips raw (`café.txt | 1 +` vs
   `"caf\303\251.txt" | 1 +`), structural chars identical. Fixture discipline: a quoting
   probe without both path classes proves nothing — an earlier fixture missing the
   non-ASCII path produced a false refutation (see the delta-registration correction).
   Re-confirm on CI's git before commit 2 lands its changelog claims.
7. Range-branch `-z` shape: `git diff -z --name-only <range>` — final entry
   NUL-terminated, no trailing newline, no commit-id entry (diff porcelain never prints
   one). `shc -n -z main..HEAD` emits exactly this stream, and item 1's diff-tree probe
   does not cover it — they are different git code paths. (Pre-probed on 2.34.1: raw
   `caf\303\251.txt` bytes + NUL, no trailing newline; still bake the assertion into the
   plan.)
8. `--find-renames` (display modes only — the `--no-renames` action path runs no rename
   detection) on the diff-tree branch is bounded by `diff.renameLimit`; exceeding it
   emits an inexact-rename warning to stderr — a NEW stats-mode stderr emission the
   unpinned command never produced. Decide deliberately before commit 2: accept
   (stderr-only, informative) or pin `-c diff.renameLimit=<higher>` into the flag set.
   Probe with a fixture over the limit on the floor git — the default limit is
   version-dependent, so measure, don't assume.
9. Rename-contract mechanics (pre-probed on 2.34.1, receipts baked into the delta
   table; re-confirm on the floor): `--no-renames` is accepted by BOTH `git diff-tree`
   and `git diff` (exit 0); `diff.renames` config does NOT affect diff-tree plumbing
   (both sides listed under `-c diff.renames=true`) but DOES affect the porcelain range
   branch — which `--no-renames` overrides. Conclusion encoded in the design: the
   explicit stance is belt-and-braces on the single branch, load-bearing on the range
   branch, and self-documenting everywhere.

## Help text additions (in `git-shc` show_help)

```text
OPTIONS:
    ...
    -z, --null      With -n only: separate paths with NUL (\0) instead of
                    newline. Handles filenames containing newlines; pair with
                    xargs -0 -r / read -d ''. Without -n: usage error.
                    (-r matters: GNU xargs otherwise runs the command ONCE,
                    operand-less, on empty input — e.g. a no-match `| xargs -0 rm`.)
```

- `-n` entry: "Assumes filenames contain no newlines" → "Paths print raw for non-ASCII
  bytes (core.quotePath=false pin); git still C-quotes structural characters (newline,
  backslash, quote, tab) in line mode — use `-z` for a fully raw, NUL-separated stream."
  The old wording implied newlines break `-n`; they don't — the path arrives as one
  C-quoted token. The truthful contract is what makes `-z` the honest fix.
- `ARGUMENTS`: add "At most one positional (commit ref or range) is accepted; a second is
  a usage error."
- `CAPTURING OUTPUT`: add `hug shc -n -z main..HEAD | xargs -0 -r <cmd>` and the
  NUL-safety note (the `-r` is not optional in the example — empty matches are a
  legitimate exit-0 case, and operand-less `<cmd>` is the foot-gun).
- `GIT EQUIVALENTS`: add the `-z` line (`git diff-tree -z --no-commit-id --name-only -r
  --root HEAD → hug shc -n -z HEAD`).
- Stale internal-caller claims in the same help block (git-shc:52-54: "used internally
  by other Hug commands (sh, shp, shcp, h files, h squash, lol, cmv) via HUG_QUIET=T") —
  both qualifiers are refuted by the audit step below: git-h-squash:197 uses NO
  HUG_QUIET (pipes the header to `>&2`), and lol/cmv never invoke `git shc`. Replace
  with the verified picture: "used internally by h files, h squash, shcp, and via
  hug-git-show/hug-git-commit by sh, shp and commit-range flows — most pass
  HUG_QUIET=T; h squash redirects the header to stderr instead."

## Tests

| File | Covers |
|---|---|
| `tests/lib/test_hug_git_diff.bats` **(new)** | `pinned_diff`: range/single dispatch; `--name-only`/`--stat`; `--null` NUL output; `--null`+`--stat` → exit 2; unknown format → exit 2; pins honored under hostile config (test repo sets `core.quotePath=true`, `diff.renames=false`, `diff.ignoreSubmodules=all`, `diff.relative=true` → output still raw / rename-collapsed / submodules shown / repo-relative, the relative case asserted from a subdirectory); `pinned_diff --name-only` (missing ref, the too-few-args guard) → exit 2; `--no-renames`: both rename sides listed, overriding hostile `diff.renames=true` on the range branch; pathspec passthrough; bad ref → exit 128 |
| `tests/unit/test_sh.bats` (shc section) | `shc -n -z`: NUL-separated (od/xxd assertion), incl. filename with embedded newline (`$'we\nird'`) — line mode asserts ONE C-quoted line `"we\nird"` (the actual before-behavior — git never split it), `-z` mode asserts raw bytes + NUL terminator; `shc -z` w/o `-n` → exit 2 + usage message; second positional → exit 2 naming both tokens (stats mode AND `-n` mode); unborn HEAD (`git init` only) → branded message, exit 1, no raw `fatal:` (all HEAD-derived ref forms: none, `1`, `-3`, `main..HEAD`, `@`, `@~2`, `@{1}`; `@{-1}` is unresolvable unborn and keeps the raw exit-128 fatal per D5); orphan repo (`git switch --orphan` after a commit) → explicit ref (`master`) WORKS unchanged, HEAD-derived forms → branded exit 1; stats rename delta on a SINGLE-COMMIT fixture (two lines → one `{old => new}` line); range-branch rename asserted UNCHANGED at default config (already collapses — the pin's range effect is hostile-config-only: pinned vs `-c diff.renames=false`); non-ASCII stats path flips C-quoted → raw (literal byte oracle: `café.txt | 1 +`); structural-char stats paths stay C-quoted both ways (byte-identity pinned vs unpinned); existing `-n` line-mode tests stay green |
| `tests/lib/test_hug-file-input.bats` | PREREQUISITE: add `load '../../git-config/lib/hug-git-repo'` — hug-common does not load it, and without it `is_range` exits 127 inside the `2>/dev/null \|\| true` swallow → empty output, existing tests break (see Reachability). Harness quirk: this file overrides `error()` to `return 1` (no exit), so `pinned_diff`'s exit-2 guards do NOT exit here — assert guard paths on output, not exit codes. Then: `extract_files_from_commit`: raw paths under `core.quotePath=true`; rename → BOTH sides listed, byte-identical with today (the action contract; a comment explains why action lists must not collapse renames) |
| `tests/lib/test_hug_git_show.bats` | `show_changed_file_names` regression (thin-wrapper refactor keeps line-mode byte-identical); `-z` leading-token passthrough |

**NUL-testing technique (project learning, mandatory):** bash cannot hold NUL — assert
via a pipe (`hug shc -n -z | od -An -c` / `xxd -p`), NEVER via BATS `$output` (it drops
NUL bytes and the assertion would vacuously pass on the wrong output). Same class as the
`sl*` NUL work tracked in [elifarley/hug-scm#249](https://github.com/elifarley/hug-scm/issues/249).

**Audit step (before commit 3 lands):** grep every internal `git shc` caller and
confirm none passes two positionals. The verified literal call sites (grep of
git-config/bin + git-config/lib): git-h-files:195, git-h-squash:197 (note: does NOT use
`HUG_QUIET=T` — sends full header output to `>&2`), git-shcp:140,147,
hug-git-show:267,269,339,341 (this is how `git-sh`/`git-shp` reach shc — they contain
no literal call themselves), and hug-git-commit:447. (`lol` is a .gitconfig alias for
log-outgoing, and neither it nor `git-cmv` invokes `git shc` — both were phantom
entries in an earlier draft of this list.) Spot-check: all nine sites pass exactly one
positional + optional `--` pathspecs — none trips the new guard. The spec makes this a
verified step, not an assumption.

## Docs

- `docs/commands/head.md` — `shc` section: `-z` flag, positional rule, deltas note.
- `git-config/lib/README.md` — `pinned_diff` entry (the canonical invocation; when to
  call it vs `show_changed_file_names`).
- `README.md` — the shc synopsis line (~546) gains `-z` alongside `-n`; prerequisites
  gain the minimum-supported-git declaration (floor 2.34 — see the probe discipline
  above).
- `docs/meta/hug-completion-reference.md` — the shc entry (~105) enumerates today's flags
  (`[-n|--name-only]`); add `[-z|--null]` (requires `-n`) and the one-positional rule.
  This is the authoritative surface for completion authors — leaving it stale is the
  same omission class as 05817b7, one grep away from the other doc fixes.
- `CHANGELOG.md` — entry under `## [Unreleased]`. Repo convention: changelog + version
  bump land inside the feature PR (v1.9.0 precedent, c37d716). The prior shc feature
  needed a post-ship doc-fix commit (05817b7) for exactly this omission class — don't
  pay that tax twice.
- PR body: `Closes elifarley/hug-scm#274`, cites the behavior-delta table.

## Deliverables — 3 atomic commits, each independently green

1. `feat(lib)`: add `pinned_diff` to hug-git-diff + `tests/lib/test_hug_git_diff.bats`
   (pure addition; no caller changes).
2. `refactor`: adopt `pinned_diff` at the three call sites + delta/regression tests +
   lib README entry (pins everywhere; behavior deltas registered above).
3. `feat(shc)`: `-z/--null` + second-positional rejection + unborn-HEAD guard + help/docs
   updates (docs/commands/head.md, lib README, README.md synopsis + minimum-git
   prerequisite, docs/meta/hug-completion-reference.md shc entry, CHANGELOG.md
   `[Unreleased]` entry — see Docs).

## Non-goals

- `git-shcp`'s `-p` diff-tree site and `git-config/lib/python/deps.py`'s diff-tree call —
  adjacent duplicates outside the issue's three named sites; noted for a possible future
  pass.
- The `sl*` family NUL mode ([elifarley/hug-scm#249](https://github.com/elifarley/hug-scm/issues/249))
  — separate surface, shares only the NUL-testing learning.
- Branding invalid-ref errors in born repos (exit-128 contract stays).
- Merge-commit parity ([elifarley/hug-scm#268](https://github.com/elifarley/hug-scm/issues/268))
  — pre-existing, deliberately preserved.
- The `xargs -0`-without-`-r` shape at git-s:84 (`hug s -z -b -H | xargs -0`) — same
  foot-gun, different command; fixing it here would leave the family half-fixed and
  expand this PR's blast radius. Separate pass over the `-z` consumers once `-r`
  guidance lands here.
- Skills-guide `-z` adoption (docs/skills/hug-repo-analysis: SKILL.md:114,289,
  guides/bug-hunting.md:105, guides/pre-commit-review.md:311 recommend `hug shc -n`
  for piping into other tools) — their claims are correct today (line mode never split
  filenames; verified), but piping-for-tools is exactly what `-z` is for, so these four
  snippets are the highest-value adoption surface once the flag lands. File a
  follow-up issue when the PR merges; not a change-set addition.
