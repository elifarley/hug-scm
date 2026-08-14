# Design: `dd` visual-diff command family (staged / unstaged / working)

**Date:** 2026-06-04
**Status:** Revised after `/autoplan` review (CEO + Eng + DX, dual-voice Codex + Claude).
This supersedes the original `-d`/`--visual`-on-`sw`/`ss`/`su` draft — recoverable from the
restore point linked at the top of this file. See the **Review Report** at the bottom.

## Context

Hug's text-diff commands show patches to stdout: `ss` (staged), `su` (unstaged),
`sw` (combined — renders an unstaged section *then* a staged section). For deep review,
users want a visual side-by-side difftool (e.g. kitty diff). Today the only path is a bare
`dd` gitconfig alias (`difftool --no-symlinks --dir-diff`). That alias:

- can't scope to staged-only / unstaged-only,
- is an **undocumented, untested, un-completed API** (no `hug help dd`, no completion, no tests),
- has a latent semantic trap: bare `dd` is *worktree-vs-index* (unstaged only), not the
  "all my changes" view users assume.

## Decision (from `/autoplan` premise gate — user-directed)

Build a canonical **visual-diff family** instead of scattering a `--visual` flag across the
text commands. Realize it by **productizing `dd` into a real `git-dd` script** with `s`/`u`/`w`
variants that mirror `ss`/`su`/`sw`. This gives one mental model, fixes the combined-diff bug
by construction (the `w` variant targets `HEAD`), and turns `dd` into a first-class command.

## Command surface

| Command | Semantics | git invocation |
|---|---|---|
| `hug dd s` *(staged)* — mirrors `ss` | index vs HEAD | `git difftool --no-symlinks --dir-diff --no-prompt --cached` |
| `hug dd u` *(unstaged)* — mirrors `su` | worktree vs index | `git difftool --no-symlinks --dir-diff --no-prompt` |
| `hug dd w` *(working)* — mirrors `sw` | worktree vs HEAD (**net**) | `git difftool --no-symlinks --dir-diff --no-prompt HEAD` |
| `hug dd [<committish>\|<range>] [-- <path>…]` | visual diff of a commit/range | `git difftool --no-symlinks --dir-diff --no-prompt <ref> [-- <path>…]` |

> **Shape is an open taste decision** (see end): gateway-subcommand `dd s/u/w` (recommended,
> matches your "subcommands" lean and keeps `dd` a single discoverable entry) vs prefix-tokens
> `dds/ddu/ddw` (truest structural mirror of `ss/su/sw`) vs flags `dd --staged/--unstaged/--working`.
> Subcommand and prefix-token forms can coexist (one as thin alias of the other).

### Semantic honesty (the CRITICAL fix — unanimous across all 7 review voices)

`dd w` is `git difftool --dir-diff HEAD` = **net** worktree-vs-HEAD. This is intentionally
**not identical** to text `sw`, which renders two separate sections (unstaged, then staged).
A hunk that is staged and then reverted in the worktree *cancels out* in the net view. A single
dir-diff cannot show two sections without launching two blocking tools (rejected — poor UX).
So `dd w` is documented as "all uncommitted changes, net working-vs-HEAD"; the split view stays
in text `sw`. The original plan's `sw -d → git difftool --dir-diff` (no ref) was **unstaged-only**
and silently dropped staged changes — that defect is designed out here.

> **User-facing walkthrough lives elsewhere (single source of truth):** see
> `docs/commands/status-staging.md` → "Visual diff: `hug dd`" for the three-trees model and a
> worked cancellation example. This section records the *decision*; that doc explains it for users.

## Must-fix requirements (from review — baked in, not optional)

1. **Difftool configuration** *(taste decision on approach, below)*: never fall through to raw
   git's surprise (`vimdiff` / per-file prompt). Either bundle a sane default difftool in
   hug-scm's gitconfig, **or** (recommended) preflight `git config diff.tool` / `difftool.<t>.cmd`
   and, when absent, emit a Hug-style error — **problem → cause → fix** — and exit non-zero.
2. **No-changes guard**: before launching, reuse the existing `git diff [--cached] --quiet`
   (and `--quiet HEAD` for `w`) checks, including path-scoped variants. Print
   `No staged changes.` / `No unstaged changes.` / `No changes.` and exit 0 — mirror text mode.
3. **Non-TTY guard**: if `! [[ -t 1 ]]` (piped / CI), refuse to launch the blocking tool and
   error to stderr. Always pass `--no-prompt` so git never prompts per file. (Honors the project's
   stdout/stderr discipline: a visual command must not hijack a pipeline.)
4. **Strict-mode safety**: `set -euo pipefail` is active. Wrap the difftool call so an expected
   non-zero exit (user cancels, tool missing, trusted-exit) does not abort the script; classify
   expected exits and decide whether the trailing `hug s` summary still runs.
5. **Path scoping + normalization**: `hug dd w -- src/` → `git difftool … HEAD -- src/`. Build a
   single normalized `--` boundary; never emit `-- --` or leak control flags as pathspecs.
6. **Interactive `--` / multi-select**: batch *all* selected files into **one** difftool
   invocation (`-- f1 f2 …`), never N blocking sessions.
7. **No silent flag conflicts**: if a stats+visual combination is ever expressible, make it an
   explicit error ("choose one"), not a silent drop.

## Implementation outline

### Task 1 — `git-config/bin/git-dd` (new, productizes the alias)
Thin script over a library helper (per `bin/CLAUDE.md`: scripts are thin, logic lives in `../lib/`).
Responsibilities: parse optional `s|u|w` subcommand (or committish/range) + pathspecs; preflight
difftool config + TTY; no-changes guard; normalized pathspec build; invoke difftool with
`--no-prompt`; strict-mode-safe wrapper; `show_help`. Add `_hug_category` / `_hug_keywords`.

### Task 2 — library helper in `git-config/lib/`
Single source of truth for `git difftool --no-symlinks --dir-diff --no-prompt` (DRY — one string,
not four). Reuse `diff_has_staged_changes` / `diff_has_unstaged_changes` from `hug-git-diff` for
the guards; add a `diff_has_working_changes` (`git diff --quiet HEAD`) if needed.

### Task 3 — difftool config *(per taste decision)*
Preflight + friendly error (recommended), and/or a documented opt-in difftool config + setup hint.
Remove the `dd` alias from the user's shellbase `.gitconfig` (superseded by `git-dd`).

### Task 4 — docs & cross-refs
- `hug help dd` (new). SEE ALSO both directions: `sw/ss/su` → `dd` family; `dd` → `sw/ss/su`; `shp` → `dd`.
- `CAPTURING OUTPUT` note: `dd*` is interactive/visual, not pipe data (TTY-guarded).

### Task 5 — tests (BATS) — see test plan artifact
Fake difftool via `difftool.<x>.cmd` writing argv to `$BATS_TEST_TMPDIR` (or a PATH `git` shim
logging only `git difftool` argv). Assert per-mode ref correctness, no-changes, non-TTY refusal,
path scoping, multi-select batching, non-zero difftool resilience, unconfigured-difftool error.

### Dropped from the original plan (review-driven)
- ~~`-d`/`--visual` flag on `sw`/`ss`/`su`~~ → replaced by the `dd` family (text commands stay pure stdout).
- ~~dev meta-note comment in `lc`/`lcr`~~ → **noise in production code**; instead filed as a backlog
  item: *"visual-diff support on log/show commands (`shp`, `lp`, `lc -p`, `lcr -p`) — global contract."*

## Verification (manual smoke, after automated tests pass)
1. `hug dd s` — staged-only visual diff   2. `hug dd u` — unstaged-only   3. `hug dd w` — all uncommitted (net)
4. `hug dd HEAD~3` — commit range   5. `hug dd w -- file` — scoped   6. `hug dd w` with nothing changed → `No changes.` (no launch)
7. `hug dd w | head` (non-TTY) → friendly refusal   8. unconfigured difftool → problem/cause/fix error
9. cancel the tool mid-review → command still exits cleanly   10. `hug help dd` + SEE ALSO cross-refs render

## Taste decisions — DECIDED (approved as-is at `/autoplan` final gate, 2026-06-04)
1. **Shape:** ✅ `hug dd s/u/w` subcommands — `git-dd` gateway dispatches `s`/`u`/`w`; keeps `dd`
   a single discoverable command. Prefix-token aliases `dds/ddu/ddw` MAY be added later as thin
   wrappers if muscle-memory parity with `ss/su/sw` is wanted.
2. **Bare `hug dd`:** ✅ defaults to **working / all uncommitted** (= `dd w` → `git difftool
   --dir-diff HEAD`). ⚠️ This changes today's alias behavior (currently unstaged-only) — call it
   out in the commit message.
3. **Difftool config:** ✅ preflight `git config diff.tool` and emit a problem→cause→fix error when
   unset; document the opt-in difftool setup. Do **not** force a default tool on users.

---

## Review Report — `/autoplan` (CEO + Eng + DX · dual-voice Codex + Claude)

**Verdict:** the original draft was **not safe to implement** (unanimous). Reframed per the premise
gate into the `dd` family above, with every must-fix folded in. Ready to implement pending the 3
taste decisions. Consensus on the CRITICAL combined-diff bug was **7/7** (3 Claude subagents +
3 Codex voices + grounded code analysis).

### Consolidated findings → disposition

| Sev | Finding | Voices | Disposition |
|-----|---------|--------|-------------|
| CRIT | `sw -d` "combined" = `git difftool --dir-diff` is unstaged-only; **drops staged changes** | 7/7 | `dd w` → `HEAD` net view, documented |
| HIGH | difftool unconfigured in hug-scm (kitty cfg lives in shellbase) → vimdiff fallback | 4 | preflight + friendly error (T3) |
| HIGH | no no-changes guard → launches tool on empty diff | 5 | guard added (req #2) |
| HIGH | blocking GUI in non-TTY/pipeline | 2 | `[[ -t 1 ]]` refusal + `--no-prompt` (#3) |
| HIGH | `set -e` + difftool exit≠0 (cancel/missing) → silent abort | 2 | strict-mode wrap (#4) |
| HIGH | visual-helper argv: `--stats-only` leaks as pathspec + `-- --` | 3 | productized cmd, normalized argv (#5) |
| HIGH | zero automated tests (80% coverage goal) | 4 | BATS + fake difftool (test-plan artifact) |
| MED | multi-select launches N blocking tools | 1 | batch into one call (#6) |
| MED | `-d` collides (`git difftool -d`, `git clean -d`) | 4 | subcommands → no `-d` |
| MED | `-s`+`-d` silent precedence reads like a bug | 3 | N/A (subcommands); else error (#7) |
| MED | `dd` move = scope creep unless productized | 3 | productized into `git-dd` |
| MED | dev meta-note = product debt in prod code | 2 | dropped → backlog item |
| MED | dd ↔ sw/ss/su not discoverable | 2 | SEE ALSO both directions |
| HIGH (strat) | partial convention; global visual contract for shp/lp/lc ignored | Codex CEO | deferred to backlog (ocean, not this lake) |

### Decision audit trail

| # | Phase | Decision | Class | Principle | Rejected |
|---|-------|----------|-------|-----------|----------|
| 1 | CEO | Reframe to canonical `dd` family + `s/u/w` | user-directed | — | `-d`-on-sw/ss/su; flags-on-dd |
| 2 | CEO | Drop `lc`/`lcr` meta-note; backlog instead | Mechanical | P3/P5 | in-source comment |
| 3 | CEO | Defer global visual contract (shp/lp/lc) | Mechanical | P2 | implement now (ocean) |
| 4 | Eng | Productize `dd` → `git-dd` script | Mechanical | P4 | alias-only |
| 5 | Eng | `dd w` = `HEAD` net, documented as collapsing split | by-design | P1 | claim == text `sw`; two launches |
| 6 | Eng | No-changes guard mirrors text path | Mechanical | P1 | launch on empty |
| 7 | Eng | Strict-mode wrap difftool exit | Mechanical | P1 | naked call |
| 8 | Eng/DX | Non-TTY refusal + `--no-prompt` | Mechanical | P1 + stdout discipline | launch in pipe |
| 9 | DX | Batch multi-select → one difftool call | Mechanical | P5 | per-file loop |
| 10 | DX | Drop `-d` short flag | Mechanical | P5 | keep `-d` |
| 11 | Eng | BATS + fake difftool (record argv) | Mechanical | P1 | manual-only |
| 12 | DX | SEE ALSO both directions | Mechanical | P1 | one-way |
| T1 | — | **Shape** — `dd s/u/w` subcommands *(rec.)* | **Taste → gate** | P5 | prefix-tokens; flags |
| T2 | — | **Bare `dd`** = working/`dd w` *(rec.)* | **Taste → gate** | P3 | current unstaged; require-arg |
| T3 | — | **Difftool config** — preflight+document *(rec.)* | **Taste → gate** | P5 | bundle a default tool |

**Artifacts:** test plan → `~/.gstack/projects/elifarley-hug-scm/main-test-plan-20260604.md` ·
restore point → top-of-file comment.
