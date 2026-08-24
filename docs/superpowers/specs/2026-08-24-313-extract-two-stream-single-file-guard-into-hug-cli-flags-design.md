# Design: Extract the two-stream single-file guard into hug-cli-flags

- **Date:** 2026-08-24
- **Status:** Approved (brainstorming session)
- **Issue:** [elifarley/hug-scm#313](https://github.com/elifarley/hug-scm/issues/313)
- **Refs:** [elifarley/hug-scm#310](https://github.com/elifarley/hug-scm/issues/310) (pre-landing review where the duplication was found)
- **Scope decision:** Guard extraction for the four byte-identical sites; `error_unknown_option` + `pathspecs_nonempty` adopted also by h-steps/fblame/stats-file without restructuring their bespoke loops.

## Problem

The "two-stream single-file guard" — collect first-candidate + extras from `$@`,
merge `_pathspec_pathspecs` as data, loud unknown-option checks, truthful
`reject_multiple_files`, re-point `$@` at the survivor — is copy-pasted
byte-identically (modulo cmd label/comments) across four commands:

| Site | Block |
|---|---|
| `git-config/bin/git-fa` | lines 99–142 |
| `git-config/bin/git-fb` | lines 97–137 |
| `git-config/bin/git-fborn` | lines 94–133 |
| `git-config/bin/git-fcon` | lines 95–135 |

(fborn ≡ fcon verified by diff: only the command label differs.)

Structural variants of the same contract exist in:

- `git-config/bin/git-h-steps` (lines 72–132): consumes `--raw` in its own loop;
  different check ordering (browse-root check between unknown-option and separator merge).
- `git-config/bin/git-fblame` (lines 65–118): bespoke `--churn/--since/--json` own-flag loop.
- `git-config/bin/git-stats-file`: `collect_positional_args_before_flags` + slice-before-tally variant.

Repeated strings/conditions:

- `Unknown option: … See 'hug help :pathspec'.` — 9 occurrences.
- The nullsafe separator-aware emptiness condition
  `[[ ${_pathspec_pathspecs[*]+x} && ${#_pathspec_pathspecs[@]} -gt 0 ]]`
  (and its negation in the no-args branch) — 4+ occurrences in the fa-family alone.

This exceeds the rule of three by 4x. Every future single-file command copies ~40
lines and can silently drop one of the adversarial-hardening invariants
(F1 empty-positional loud reject, F2 pre-'--'-only option checking).

## Goals

1. One named contract for the two-stream guard in `git-config/lib/hug-cli-flags`,
   following the repo's established extraction pattern (`drain_pathspecs_after_separator`,
   `parse_scoped_own_flags`, `reject_multiple_files`).
2. Kill the message-template and nullsafe-condition repeats via small helpers.
3. Behavior-preserving: identical messages, exit codes, and check precedence.
4. Standardize collection-array naming *by construction* — `file_candidates` /
   `extra_files` disappear from the four sites into the helper's internals.

## Non-goals

- No restructuring of h-steps or fblame onto the shared guard (their flag loops and
  check ordering differ observably).
- No sweep of `error_unknown_option` beyond the sites listed below (stats-file,
  llf, sls family keep inline calls this round).
- No change to browse-root check placement (ordering differs per family).

## Design

### New functions in `git-config/lib/hug-cli-flags`

```bash
# Predicate — replaces the repeated nullsafe condition.
pathspecs_nonempty()
# Exit 0 iff _pathspec_pathspecs is set AND non-empty; set -u safe (Bash 4.0–4.3 floor).

# Message template — replaces the 9x repeat.
error_unknown_option <token>
# → error_usage "Unknown option: $1. See 'hug help :pathspec'."   (exit 2)

# The guard itself.
guard_single_file_candidates <cmd-label> <file-var-name> [pre-args...]
```

Guard semantics (byte-for-byte the current inline behavior):

1. **Pre-'--' stream** over `[pre-args...]`: an empty string is a usage error
   (`error_usage "Empty file argument."`, adversarial F1); the first token becomes
   the surviving candidate, the rest go to an internal candidates array
   (reserved prefix `__gsfc_`, same nameref-collision discipline as `__dps_`/`__pso_`).
2. **Loud unknown-option check** on the pre-'--' stream only (survivor + candidates),
   BEFORE any separator data joins (adversarial F2 invariant: post-'--' DATA spelled
   `-name` must never be misclassified as an option).
3. **Post-'--' stream**: every `_pathspec_pathspecs` token merges into the tally
   verbatim — data by contract, never option-re-parsed.
4. **`reject_multiple_files "<cmd-label>"`** over survivor + candidates (truthful count).
5. Survivor written to the caller-named scalar (empty string when no candidate).
   Callers keep their own `set -- ${file:+"$file"}` line — see API-shape rationale.

### Why in-process, not eval-emitting (key decision)

`parse_pathspecs` emits shell code for `eval "$(...)"`. That style is wrong here:
the guard CALLS `error_usage`, which exits. Inside a `$( )` subshell, an exit kills
only the subshell — the violation would not stop the script. So violation checks must
run in-process, which forces the nameref/out-param shape used by
`reject_multiple_files` and `drain_pathspecs_after_separator`. Consequence: the helper
cannot re-point the caller's `$@`; the two-line caller idiom
(`guard_single_file_candidates "hug fa" file "$@"` + `set -- ${file:+"$file}"`)
is the deliberate contract.

### Site migrations

| Site | Change |
|---|---|
| `git-fa`, `git-fb`, `git-fborn`, `git-fcon` | ~40-line block → `guard_single_file_candidates "<cmd>" file "$@"`; three nullsafe conditions adopt `pathspecs_nonempty` |
| `git-h-steps` | adopts `error_unknown_option` + `pathspecs_nonempty`; `--raw` loop and check ordering untouched |
| `git-fblame` | adopts `error_unknown_option` (its `-*` arm); bespoke loop untouched |
| `git-stats-file` | adopts `error_unknown_option`; collection flow untouched |

Browse-root checks stay put at each site (precedence differences are observable and
pinned by conformance rows).

## Error handling & compatibility

Pure behavior-preserving refactor:

- Identical messages (byte-for-byte), including the short-form template
  `Unknown option: <tok>. See 'hug help :pathspec'.` — note this is deliberately NOT
  the family long-form (`Pathspecs beginning with '-' require '--': <cmd> -- <tok>…`)
  used by listing/status commands; the guard keeps the existing short form so
  pinned conformance rows pass unmodified.
- Identical exit codes: all rejections stay in the exit-2 usage family.
- Identical precedence within each migrated site.
- No new globals beyond load-time state already in the lib; helper state is either
  function-local or behind the reserved `__gsfc_` prefix.

## Testing

- **Unit rows** in `tests/lib/test_hug-cli-flags.bats` for each new function:
  happy path; each rejection branch (empty positional, unknown `-*` pre-'--',
  cardinality overcount naming the command); `-- -dash.txt` stays data and reaches
  the truthful cardinality reject rather than an option complaint; unset-variable
  safety under `set -u`.
- **Behavior-preservation proof**: the existing `test_pathspec_conformance.bats`
  rows covering fa/fb/fborn/fcon must pass unmodified — they pin every observable
  behavior this extraction touches.
- **Mutation receipts** (repo convention): remove the unknown-option check inside
  the guard → a conformance row goes red; restore. Same receipt pattern for the
  empty-positional check (F1).

## Adoption checklist (implementation order)

1. Add the three functions to `git-config/lib/hug-cli-flags` (+ header Functions list).
2. Unit rows red→green against the lib only.
3. Migrate the four clone sites; run the conformance suite (expect zero diffs).
4. Adopt small helpers in h-steps, fblame, stats-file.
5. Mutation receipts; `make sanitize` gate before commit.
