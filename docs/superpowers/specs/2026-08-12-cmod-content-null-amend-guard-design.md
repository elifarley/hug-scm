# Design: content-null amend guard for `cmod` / `cmoda`

**Date:** 2026-08-12
**Status:** Approved (brainstorming complete; awaiting user spec review → writing-plans)
**Issue:** [elifarley/hug-scm#263](https://github.com/elifarley/hug-scm/issues/263)
**Branch / worktree:** `fix-263-content-null-amend-guard`

## Problem

`hug cmod --no-edit` with **nothing staged** silently rewrites the HEAD
commit's hash — identical tree, identical message, brand-new commit object —
with no warning, and prints an actively misleading **"Amending last commit
with staged changes"** message when there were no staged changes at all.
An agent reasoning "nothing staged → nothing to amend → no-op" is wrong: it
is a silent history rewrite that produces a duplicate commit on merge.

The same hazard applies to `hug cmoda --no-edit` in a fully **clean** tree
(no staged *and* no unstaged tracked changes): `git commit -a --amend`
captures nothing and re-hashes HEAD.

This is the opposite end of the family from
[elifarley/hug-scm#190](https://github.com/elifarley/hug-scm/issues/190)
(`cmoda` capturing *too much* in a dirty tree): here the amend captures
*nothing* — pure hash churn. Both are degenerate index states the amend
family has no runtime guard for; only advisory `hug sls` TIPs, i.e. agent
discipline — exactly what failed in
[elifarley/hug-scm#207](https://github.com/elifarley/hug-scm/issues/207)
and #190.

### Real incident (2026-08-11, abridged from the issue)

In a fresh worktree, `hug -C <worktree> cmod --no-edit` ran *before* the
intended cherry-pick, with nothing staged. HEAD `a80a4e7` became `fb8ed4fe`
(same tree, same message, new committer timestamp), and the subsequent
cherry-pick stacked on top of the re-hashed duplicate — which on merge would
have landed a second copy of `a80a4e7`'s change under a different SHA. The
only signal was the post-hoc tip line. Recovery: `hug h rewind a80a4e7 -f`
+ re-cherry-pick (~5 minutes, no data lost — but only because the hash churn
was noticed before push).

## Decisions (made with the user during brainstorming)

| Decision | Choice | Rationale |
|---|---|---|
| **Guard form** | **Hard refusal** via `error_blocked` (exit 3), bypassed by `-f`/`--force` | Deterministic in agent and TTY contexts alike; matches the issue's proposal and the existing `error_blocked` idiom (`git-wtc:321`, `git-wtdel:493`). A prompt tier was rejected: there is essentially never a good "yes" reason for a content-null amend, and warn/danger prompts are TTY-dependent. `-y`/`HUG_YES` deliberately does **NOT** bypass — this is a semantic guard, not a confirmation. |
| **Scope** | **`cmod` + `cmoda`** via one shared library guard | `cmoda --no-edit` in a clean tree is the identical degenerate outcome; the issue frames the gap as family-wide. Composes cleanly with the future deferred #191 dirty-tree prompt (mutually exclusive triggers: zero changes vs. staged+unstaged mix). |
| **Shape** | **Shared guard in `hug-git-commit`** (thin scripts) | The `bin/` convention ("keep most of the work in library functions") and the #191 precedent both put amend guards in `hug-git-commit`. Post-hoc hash-compare warning (amend first, warn after) was rejected: it is a transparency aid, not prevention — the hash is already rewritten when it prints (the `git-c` #207 comments codify this lesson). |

## Design

### §1 — Trigger semantics

The guard refuses an amend iff **all four** hold:

1. **Content-null.**
   - `cmod` (mode `staged`): index identical to HEAD — `git diff --cached --quiet` exits 0.
   - **Exception — trailing paths present** (bare paths like `cmod --no-edit a.txt`, or paths after `--`): `git commit <pathspec>` runs in `--only` mode and takes the named paths' content from the **worktree**, not the index (probe-verified both forms: empty index + worktree-modified file + pathspec amend folds the worktree content). The content check then becomes `git diff HEAD --quiet -- <paths…>` — worktree state vs HEAD, which is exactly what the amend folds.
   - `cmoda` (mode `tracked`): no tracked changes anywhere — `git diff HEAD --quiet` exits 0 (covers staged + unstaged in one shot, exactly what `-a` would capture).
2. **Keep-message intent.** The amend would deterministically reproduce HEAD's message, with no editor opening:
   - `--no-edit` present (and no change-flag, per trigger 3), or
   - `-C <ref>` / `--reuse-message=<ref>` / `-c <ref>` / `--reedit-message=<ref>` where `<ref>` **resolves to HEAD** and `--no-edit` is present — git replaces the message without an editor and the replacement is byte-identical (probe-verified churn for all four spellings, including `@`: same message, new hash). "Resolves to HEAD" means `git rev-parse --verify <ref>^{commit}` equals `git rev-parse HEAD` — literal string comparison is NOT sufficient (`@`, `HEAD~0`, a full SHA equal to HEAD are all HEAD).
   `-m`/`-F`/`-C <non-HEAD>` change the message; bare/`-c <commit>` (without `--no-edit`) open an editor where the message may change (the editor is the human gate) — all exempt.
3. **No message-change flag** before a `--` separator. `-m`/`--message`, `-F`/`--file`, `-C <non-HEAD>`/`--reuse-message=<non-HEAD>`, `--signoff`/`-s`, `--trailer`, `--fixup=`/`--squash=` all change the message (probe-verified: `-s` appends a Signed-off-by trailer; `--fixup=HEAD` replaces the message with "fixup! …"); so does `-c <non-HEAD> --no-edit` / `--reedit-message=<non-HEAD> --no-edit` (git replaces the message silently — probe-verified); if both `-m` and `--no-edit` appear, `-m` wins (git uses the `-m` message; `--no-edit` only suppresses the editor) → message-change intent. `-e`/`--edit` overrides `--no-edit` and opens the editor (probe-verified: a failing editor aborts the amend loudly) — an editor gate, not a message change. The recognized set is exactly `amend_args_message_intent`'s (§2).
4. **No force** — `HUG_FORCE=true` (set by `parse_common_flags` from `-f`/`--force`, or exported in the environment) bypasses. `-y`/`HUG_YES` does not.

Decision table for `hug cmod` (`cmoda` analogous, "empty" = "no tracked changes anywhere"):

| Index state | args | Result |
|---|---|---|
| staged changes | any | proceed (unchanged behavior) |
| empty | `-m` / `-F` / `-C <non-HEAD>` / `--reuse-message=<non-HEAD>` / `--signoff` / `-s` / `--trailer` / `--fixup=` / `--squash=` | proceed — definite message change; honest info line |
| empty | bare / `-c <commit>` / `--reedit-message=` / `-e` (editor forms, no `--no-edit`; `-e` opens the editor even with `--no-edit`) | proceed — the editor is the gate |
| empty | `-C <ref>` / `--reuse-message=<ref>` / `-c <ref>` / `--reedit-message=<ref>` where `<ref>` resolves to HEAD, with `--no-edit` | **refuse, exit 3** — message stays byte-identical; pure hash churn |
| empty | `--no-edit` | **refuse, exit 3** |
| empty | `--no-edit -f` (or `HUG_FORCE=true`) | proceed; honest info line |
| empty | `-m "msg" --no-edit` | proceed — `-m` wins: verified probe shows git uses the `-m` message and skips the editor |
| empty | `--no-edit <paths>` (bare paths or after `--`; named paths worktree-modified) | proceed — `--only` mode folds worktree content, not the index |
| empty | `--no-edit <paths>` (named paths identical to HEAD) | **refuse, exit 3** — the paths check (`diff HEAD -- <paths>`) is content-null |

**Content-expanding passthrough flags re-mode the guard — never skip it.**
`hug cmod` forwards arbitrary options to `git commit`, so `-a`/`--all` can
pull unstaged tracked changes into the amend even with an empty index. A
clean tree with `-a` is still content-null (probe-verified: `cmod --no-edit
-a` on a clean tree rewrites the hash with zero content change), so a
skip would silently re-open the exact incident this guard exists to
prevent. Instead, when `-a`/`--all` is present the guard switches to the
`tracked` check (the cmoda one — `git diff HEAD --quiet`), which is the
honest content model for `-a` semantics: worktree+index vs HEAD, exactly
what `-a` folds. Dirty tree → rc 1 → proceed, no false refusal; clean
tree → rc 0 → refuse.

The interactive content flags (`-p`/`--patch`, `-i`/`--interactive`) get the
same re-mode, not a skip: they are NOT reliably human-gated when the tree
has nothing to select. Probe-verified: on a clean tree `--amend --no-edit -p`
exits 0 and rewrites the hash with the tree byte-identical (no hunks → no
prompt). So `-p`/`-i` present → `tracked` check: clean tree → refuse;
dirty tree → rc 1 → proceed (the human then gates hunk selection inside
git). Caveat, probe-verified: with stdin closed, `-p` auto-answers "n" to
its own prompt and a dirty-tree amend still churns — the guard proceeds
because content EXISTS, and whether it lands is git's interactive
behavior; agents wanting deterministic content-folding should pass `-a`.
`-i` alone on a clean tree also fails loudly inside git itself (exit 128,
"No paths with --include/--only"), which the fail-open branch passes
through. With an explicit path list, `-i` and `--only` behave like pathspec
`--only` commits and the trailing-paths check above applies instead.

The three content-shape flags are mutually exclusive — git rejects `-a`
together with `-p`/`-i`/`--only` ("Only one of
--include/--only/--all/--interactive/--patch can be used", probe-verified)
and rejects `-a` with any path ("paths … with -a does not make sense",
probe-verified) — so exactly one content model applies to any invocation:
paths → pathspec check; `-a`/`-p`/`-i` → tracked check; otherwise → staged
check. No mixed-mode case exists.

**Simplification vs. the issue text:** the issue distinguishes "empty index"
(refuse) from "a staged set whose resulting tree is identical to HEAD"
(warn). Those are **mechanically indistinguishable** — both are
`index == HEAD` at run time (a stage-then-unstage leaves no residue in the
index). One check, one behavior: refuse.

**Same-second identity caveat.** A content-null amend only changes the hash
when the committer timestamp differs: an amend landing in the SAME second as
the original commit produces a byte-identical commit object (verified probe:
same tree + same message + same second → identical SHA). Real incidents
always span seconds (that's the churn), but hash-asserting tests must force
a distinct `GIT_COMMITTER_DATE` or they flake.

**Fail-open.** Exit codes are handled explicitly: `0` → content-null,
`1` → changes exist, `>1` (diff error) → **proceed** and let
`git commit --amend` emit its own error. Note unborn HEAD is NOT the
error case for the `staged` check: with no commits,
`git diff --cached --quiet` exits **0** on an
empty index (guard's "nothing to amend" refusal is still truthful there —
there is no commit to amend) and `1` with staged content (guard proceeds;
git then fails with its own message). For the `tracked` check (cmoda, and
cmod with `-a`/pathspec), `git diff HEAD --quiet` **does** exit `>1` on
unborn HEAD (`fatal: ambiguous argument 'HEAD'`) — that lands in the same
fail-open branch and git's own "You have nothing to amend." surfaces. The
`rc>1` branch covers genuinely broken state (e.g. a corrupt index). The
guard never invents a refusal it cannot justify.

**Not affected:** mid-merge / conflicted index (unmerged entries make
`diff --cached` non-quiet → proceed), amending merge commits (guard is
orthogonal), `--reset-author`/`--date` metadata amends (content-null +
`--no-edit` → refused; the intentional re-hash/re-date is exactly the
documented `-f` escape hatch, per the issue).

### §2 — Library contract (`git-config/lib/hug-git-commit`)

Two new functions, following the scanning pattern of the existing
`commit_args_indicate_amend` (skip `-m`/`-C`/`-c` values, respect the `--`
terminator; `amend_args_message_intent` extends the value-skip to `-F`
and resolves `-C`/`-c` values against HEAD — see the KEEP rule):

```bash
# amend_args_message_intent "$@" — three-way scan of forwarded commit args.
# Returns:
#   0 = KEEP message    (--no-edit present and no change-flag; also
#                        -C <ref>/--reuse-message=<ref>/ -c <ref>/
#                        --reedit-message=<ref> with --no-edit where <ref>
#                        RESOLVES to HEAD (git rev-parse <ref>^{commit} ==
#                        HEAD) — the replacement is byte-identical,
#                        probe-verified churn. Literal matching is NOT
#                        enough: @, HEAD~0, and HEAD's SHA are all HEAD.)
#   1 = CHANGE message  (-m/-F/-s/--signoff/--trailer/--fixup=/--squash=/
#                        -C <non-HEAD>/--reuse-message=<non-HEAD> present;
#                        also -c <non-HEAD> --no-edit — git replaces the
#                        message silently, no editor (probe-verified);
#                        wins over --no-edit — probe-verified git behavior)
#   2 = EDITOR decides  (bare, -e/--edit, or -c/--reedit-message= form
#                        without --no-edit; -e overrides --no-edit and
#                        opens the editor — probe-verified: a failing
#                        editor aborts the amend loudly)
# Message-source flags recognized (attached short forms -m<msg>/-C<ref>/
# -F<file>/-c<ref>/-s AND long passthrough forms, since cmod/cmoda forward
# arbitrary options to git commit): -m/--message, -C/--reuse-message,
# -F/--file, -s/--signoff, --trailer, --fixup=, --squash= → change (1);
# -c/--reedit-message, -e/--edit → editor (2) unless a HEAD-resolving
# value plus --no-edit makes them keep (0).
# Scanning follows commit_args_indicate_amend: skip flag values, stop at --
# (pathspec data after -- never counts).
# WHY three-way: the guard needs "keep" (fires); the caller's info line
# needs "change"/"editor" to stay honest. Callers MUST capture via
# `rc=0; amend_args_message_intent "$@" || rc=$?` — under `set -e` a bare
# call returning 1/2 kills the script (the commit_offset errexit lesson).
amend_args_message_intent()

# guard_content_null_amend <staged|tracked> "$@"
# Refuses a content-null amend (exit 3 via error_blocked) unless HUG_FORCE.
# Sets the caller global _amend_content_null=true|false so the caller picks
# an honest info line (computed once, used twice — the git-c idiom).
# Content model is the honest one for the amend's actual content source:
#   - trailing paths (bare, or after a -- pre-parsed by parse_pathspecs —
#     see §4) switch the check to `git diff HEAD --quiet -- <paths>`
#     (--only mode folds worktree content, not the index). The refusal's
#     "no staged changes" wording stays truthful: the paths check verifies
#     the named paths' content is also absent.
#   - -a/--all, -p/--patch, -i/--interactive switch the check to `tracked`
#     mode (worktree+index vs HEAD). A clean tree still refuses: -a and -p
#     both silently churn with nothing to capture (probe-verified). With
#     paths AND -p/-i/--only present, git is in --only mode and the paths
#     branch applies instead. No mixed-mode case exists: git rejects -a
#     with any path and rejects -a together with -p/-i/--only
#     (probe-verified) — exactly one content model per invocation.
#
# WHY called BARE (never `$(guard_content_null_amend ...)`): error_blocked
# must exit the SCRIPT. Captured via `local x=$(...)` the substitution's
# exit status is masked and the amend proceeds silently — the exact
# head-mover lesson; captured via a plain `x=$(...)` assignment under
# set -e, errexit kills the script before the refusal prints. Either way
# the refusal is lost; only a bare call exits 3 from the script itself.
#
# Assumes parse_common_flags already ran: -f/-y/-q are stripped from "$@"
# and HUG_FORCE/HUG_YES are set. Uses raw `git diff` with explicit
# exit-code handling, NOT hug-git-state's has_staged_changes — that helper
# conflates "diff error" with "no changes" (both return 1), and the
# fail-open contract above requires distinguishing rc>1.
guard_content_null_amend()
```

Refusal path detail: when untracked files exist, the refusal appends a note
(count via `get_untracked_files` — already a non-exiting reporting
primitive; `| wc -l` is SIGPIPE-safe, `wc` never closes early):

```
Note: 3 untracked file(s) exist; cmod never includes untracked files —
stage them first with 'hug a <file>…' (bare 'hug a' only stages tracked
changes) or 'hug aa'.
```

(`cmoda` wording: "cmoda never includes untracked files".) This addresses
the incident's likely confusion — running amend expecting new files to be
picked up.

### §3 — Refusal message & honest output

Refusal (stderr, exit 3):

```
❌ Error: Nothing to amend — no staged changes and no message change;
the amend would only rewrite HEAD's hash (same tree, same message;
unless --date/--reset-author were passed, metadata too).
Stage changes first ('hug a <files>') or change the message ('hug cmod -m "msg"').
To re-hash/re-date HEAD anyway, re-run with -f/--force.
```

(`cmoda` first line: "Nothing to amend — no tracked changes (staged or
unstaged) and no message change; …".)

The current unconditional `info "Amending last commit with staged
changes..."` becomes **state-dependent** and moves **after** the guard (the
#191 call-site pattern — never announce an amend we then refuse):

| State | info line |
|---|---|
| content present, staged source | unchanged: "Amending last commit with staged changes…" (cmod) / "…with all tracked changes…" (cmoda) |
| content present, paths source | "Amending last commit with the named paths' changes…" (the staged wording would be a false claim — `--only` folds worktree, not index) |
| content-null, forced | "Amending last commit (--force: no content change — only the hash will be rewritten)…" |
| content-null, message flag (`-m`/`-F`/`-s`/`--signoff`/`--trailer`/`--fixup=`/`--squash=`/`-C <non-HEAD>`) | "Amending last commit (message change only — no staged changes)…" (cmoda: "…no tracked changes") |
| content-null, editor form (bare/`-c` without `--no-edit`/`-e`) | "Amending last commit (no content change; the editor decides the message)…" |

`suggest_next_push_command --amend` is unchanged (still after a successful
amend).

### §4 — Call sites

`git-cmod`:

```bash
# Pre-parse pathspecs FIRST: parse_common_flags intercepts a trailing --
# (hug-cli-flags:21-23 "Commands that accept -- <path>... must pre-parse
# pathspecs first"), so a pathspec-keyed guard that runs after it can never
# see the separator. Same idiom as git-shp:76-77.
eval "$(parse_pathspecs "$@")"
eval "$(parse_common_flags "${_pathspec_pre_args[@]}")"
# NOTE: the eval above did `set --` — $@ is now the stripped pre_args.
# The guard receives pre_args (flag scan) plus pathspecs (content check)
# as two groups; a literal -- between them keeps the guard's scanner honest.
check_git_repo
guard_content_null_amend staged "${_pathspec_pre_args[@]}" \
    -- "${_pathspec_pathspecs[@]}"                   # exits 3 on refusal
# pick honest info line from $_amend_content_null + amend_args_message_intent:
#   0=KEEP → content-null variants; 1=CHANGE → message-change line;
#   2=EDITOR → editor line (only reachable when the guard proceeded)
if [[ ${#_pathspec_pathspecs[@]} -gt 0 ]]; then
    git commit --amend "$@" -- "${_pathspec_pathspecs[@]}" \
        && suggest_next_push_command --amend
else
    git commit --amend "$@" && suggest_next_push_command --amend
fi
```

The final `git commit --amend` re-inserts the pathspecs (with `--`) after
the stripped pre_args — git's own parsing sees exactly what the user
passed. Bare trailing paths (no `--`) live in `_pathspec_pre_args`; the
guard's paths branch must treat trailing non-flag arguments as paths too
(see §2).

`git-cmoda`: identical, with `guard_content_null_amend tracked ...` and
`git commit -a --amend "$@"` (cmoda's `-a` makes the tracked check the
default; paths passed to cmoda still name `--only` content, and the same
pre-parse applies).

### §5 — Help text

`git-cmod` `show_help` — new section after the WARNING block:

```
  SAFETY GUARD:
  cmod refuses a content-null amend: with nothing staged and --no-edit (no
  message change either), the amend would only rewrite HEAD's hash — same
  tree, same message (unless --date/--reset-author were passed, metadata
  too) — which is almost always a mistake (e.g. running cmod
  before staging). The refusal exits 3 with an actionable message.
    - Stage changes first ('hug a <files>' — bare 'hug a' only stages tracked
      changes) or pass -m to change the message.
    - To re-hash/re-date HEAD anyway, re-run with -f/--force.
    - -y does NOT bypass the guard (it is not a confirmation).
```

`git-cmoda` `show_help` — same section, mode-specific first sentence:
"cmoda refuses a content-null amend: with no tracked changes at all
(nothing staged, nothing modified) and --no-edit, …".

Existing TIPs ("Run 'hug sls' first…", the cmod/cmoda contrast) stay — they
remain correct.

### §6 — Tests

**Behavioral — `tests/unit/test_commit.bats`** (existing non-interactive
harness; capture HEAD hash before/after with `git rev-parse HEAD`, tree with
`git show -s --format=%T`, message with `%B`):

**Determinism note (same-second identity, §1):** the content-null forced
amends below assert hash churn, which requires a different committer
timestamp. Tests 2/3/18 export `GIT_COMMITTER_DATE` (e.g.
`2030-01-01T00:00:00Z`) for the amend invocation so the churn is
observable; content/message-changing amends (4/5/8/11/13/15/19/21/22)
differ in tree or message and need no timestamp forcing.

cmod:
1. empty index + `--no-edit` → **exit 3**; HEAD hash unchanged; message unchanged; refusal text present; "with staged changes" absent from output.
2. empty index + `--no-edit -f` (+ forced `GIT_COMMITTER_DATE`) → success; hash **changed**; tree and message **byte-identical** to before; forced info line present.
3. `HUG_FORCE=true` env variant of #2 (env-var bypass parity).
4. empty index + `-m "new msg"` → success; message updated; hash changed.
5. staged changes + `--no-edit` → proceeds as today (no regression; staged content folded in).
6. untracked-only tree + `--no-edit` → exit 3 + the untracked note.
7. empty index + `-y --no-edit` → **still exit 3** (pins `-y` ≠ bypass).
8. unstaged tracked changes + `--no-edit -a` → **proceeds** (the `-a` re-mode: dirty tree → tracked check rc 1, no false refusal; unstaged content folded in).
9. clean tree + `--no-edit -a` → **exit 3** (the `-a` re-mode: clean tree → tracked check rc 0; pins that `-a` never skips the guard).
10. empty index + `--no-edit -C HEAD` → **exit 3** (keep-message classification: message stays byte-identical).
11. empty index + `--no-edit -- a.txt` (a.txt worktree-modified) → **proceeds** (pathspec `--only` folds worktree content; no false refusal).
12. empty index + `--no-edit -- a.txt` (a.txt worktree-identical to HEAD) → **exit 3** (pathspec content check rc 0).
13. empty index + `--no-edit a.txt` (a.txt worktree-modified, bare path no `--`) → **proceeds** (bare trailing paths are `--only` too; pins the pre-parse + bare-path detection).
14. clean tree + `--no-edit -p` → **exit 3** (the `-p` re-mode: no hunks → git would churn silently; pins that `-p` never skips the guard).
15. dirty tree + `--no-edit -p` → **proceeds** (tracked check rc 1; content exists).
16. clean tree + `--no-edit -i` → git's own loud error surfaces (fail-open passes exit 128 through).

cmoda:

17. clean tree + `--no-edit` → exit 3; hash unchanged.
18. clean tree + `--no-edit -f` (+ forced `GIT_COMMITTER_DATE`) → success; hash changed; tree/message identical; forced info line.
19. clean tree + `-m "new msg"` → success; message-only amend.
20. unstaged-only tracked changes + `--no-edit` → proceeds as today (no regression).
21. staged-only tracked changes + `--no-edit` → proceeds (cmoda ≡ cmod case; no regression).
22. intent-to-add file + `--no-edit` → proceeds (ITA shows in `diff HEAD`; `-a` folds the file's content).

**Library — `tests/lib/test_hug-git-commit.bats`:**

23. `amend_args_message_intent` table (oracle: literal git outputs; the parentheticals below are what git demonstrably does, and the test asserts message equality after a real amend — NOT the spec's assertion): `--no-edit` → 0; `-m x` → 1; `-m x --no-edit` → 1; `-C HEAD~1` → 1; `--reuse-message=HEAD~1` → 1; `-F msgfile` → 1; `-c X` → 2; `--reedit-message=X` → 2; bare → 2; `-m --no-edit` (value eats the flag) → 1; `--no-edit -- -m` (after `--` is pathspec data) → 0; `-m"attached"` → 1; `-CHEAD~1` (attached value) → 1; `-c X --no-edit` → 1 (git replaces the message silently); `--no-edit --signoff` → 1; `-s` → 1; `--no-edit --trailer Co-Authored-By: x <x@x>` → 1; `--no-edit -C HEAD` → 0; `--no-edit --reuse-message=HEAD` → 0; `--no-edit -c HEAD` → 0; `--no-edit --reedit-message=HEAD` → 0; `--no-edit -C @` → 0 (HEAD alias); `--no-edit -c @` → 0; `--no-edit -C HEAD~0` → 0; `--no-edit --fixup=HEAD` → 1; `--no-edit --squash=HEAD` → 1; `--no-edit -e` → 2 (editor gate overrides --no-edit).
24. `guard_content_null_amend` fail-open: corrupt the index fixture (e.g. truncate `.git/index`) so `git diff` exits >1 → guard returns 0 without refusing. (Unborn HEAD is NOT this branch for the `staged` check — probe-verified: `git diff --cached --quiet` exits 0 there on an empty index, a truthful refusal; it IS the `>1` branch for the `tracked` check — see §1 fail-open.)
25. `guard_content_null_amend` paths branch: staged mode + `_pathspec_pathspecs=(a.txt)` with a.txt worktree-modified → rc 0 (proceeds); a.txt identical to HEAD → exit 3. Bare trailing path in pre_args → same paths branch.

**Regression nets:**

- `make test-lib-py TEST_FILTER=test_quality_corpus` — the help-text edits must not drop `hug cmod` out of top-5 for query "amend".
- Full `make test`, `make sanitize-check`, `make docs-build`.

### §7 — Doc sync

- `docs/commands/commits.md` — cmod (§ ~line 124) and cmoda sections: document the guard, the exit-3 refusal, and the `-f` escape hatch.
- `git-config/lib/python/articles/agents.md` (the `hug help :agents` article, Amending section) — one line: cmod/cmoda refuse content-null amends (exit 3); stage or pass `-m`; `-f` only for a deliberate re-hash/re-date. Agents are the primary incident class — this channel is load-bearing.
- `docs/skills/hug-workflow/SKILL.md` — same one line in the agent-loaded skill (frontmatter triggers on "commit, amend"); its existing cmod workflow claims remain true post-change, so this is additive coverage of the exit-3 refusal and `-f` hatch, not a correction.
- `README.md` (~line 477) — light annotation of the `cmod` one-liner, matching the `cmoda` precedent at line 478 (e.g. "…staged changes — refuses no-op amends without `-f`").
- `CHANGELOG.md` — `[Unreleased]` entry under `### Fixed`, referencing elifarley/hug-scm#263, calling out the deliberate behavior change and exit 3.

## Out of scope

- The **#191** cmoda dirty-tree prompt (staged subset + unstaged mix) — still deferred; its trigger is mutually exclusive with this guard's and composes cleanly later.
- **Bare/`-c` editor forms without `--no-edit`** — the message outcome is unknowable pre-amend; the editor is the human gate. (`-c <ref> --no-edit` is NOT an editor form — git replaces the message silently; it is a message-change flag unless `<ref>` resolves to HEAD, in which case it is keep-intent, trigger 2.)
- **`--reset-author`/`--date` as message-equivalent intent** — covered by `-f` (per the issue's escape hatch).
- **`hug c --amend`** passthrough — already refused by `git-c`'s empty-index guard (`git-c:87-90`).
- **Post-hoc hash-compare warning** (approach 3) — rejected above.

## Backward compatibility

Deliberate behavior change: scripts/agents relying on empty-index
`cmod --no-edit` (e.g. to re-date HEAD) now receive **exit 3** — distinct
from generic exit 1, so scriptable — and must add `-f`. That is the fix.
`-y`-everywhere agents are unaffected when content exists; when it doesn't,
the refusal message teaches `-f`. Release notes cover it.

## Acceptance criteria

- [ ] `guard_content_null_amend` + `amend_args_message_intent` live in `hug-git-commit` with the §2 contracts (fail-open, bare-call WHY comments, `_amend_content_null` global, HEAD-resolving KEEP rule).
- [ ] `cmod --no-edit` with an index identical to HEAD exits 3 with the §3 message; `-f`/`HUG_FORCE` bypass; `-y` does not.
- [ ] `cmoda --no-edit` with zero tracked changes behaves identically (mode `tracked`).
- [ ] The "with staged changes" info line prints **only** when staged changes exist; the content-null variants and the paths-source variant match §3.
- [ ] Untracked-files note appears in refusals when untracked files exist.
- [ ] Content-shape passthrough flags re-mode the guard — `-a`/`--all`/`-p`/`--patch`/`-i`/`--interactive` use the tracked check (dirty tree proceeds, clean tree refuses); trailing paths (bare or after `--`) use the paths check; exactly one model per invocation.
- [ ] The §4 pre-parse idiom (`parse_pathspecs` before `parse_common_flags`) preserves original `"$@"` for the final `git commit --amend` — pathspec invocations proceed or refuse correctly (tests 11/12/13).
- [ ] All §6 behavioral + library tests pass (including `-y` no-bypass, the `-a`/`-p` re-modes, bare-path detection, corrupt-index fail-open, and `GIT_COMMITTER_DATE`-deterministic hash-churn assertions).
- [ ] Help texts carry the SAFETY GUARD section; `test_quality_corpus.py` stays green.
- [ ] `docs/commands/commits.md`, `articles/agents.md`, `docs/skills/hug-workflow/SKILL.md`, `README.md`, `CHANGELOG.md` synced; `make docs-build` and `make sanitize-check` green.

## Files touched

| File | Change |
|---|---|
| `git-config/lib/hug-git-commit` | + `amend_args_message_intent`, + `guard_content_null_amend` |
| `git-config/bin/git-cmod` | `parse_pathspecs` pre-parse, guard call (`staged`), state-dependent info line, SAFETY GUARD help section |
| `git-config/bin/git-cmoda` | guard call (`tracked`), state-dependent info line, SAFETY GUARD help section |
| `tests/lib/test_hug-git-commit.bats` | helper unit tests (arg-intent table, fail-open) |
| `tests/unit/test_commit.bats` | 22 behavioral cases |
| `docs/commands/commits.md` | guard documented in cmod/cmoda sections |
| `git-config/lib/python/articles/agents.md` | Amending section: guard one-liner |
| `docs/skills/hug-workflow/SKILL.md` | agent skill: guard one-liner |
| `README.md` | `cmod` one-liner annotation |
| `CHANGELOG.md` | `[Unreleased]` → `### Fixed` entry |

## Verification

```bash
make test-unit TEST_FILE=test_commit.bats
make test-lib TEST_FILE=test_hug-git-commit.bats
make test-lib-py TEST_FILTER=test_quality_corpus
make test                     # full suite
make sanitize-check           # static analysis
make docs-build               # VitePress still builds
```

## References

- Issue: [elifarley/hug-scm#263](https://github.com/elifarley/hug-scm/issues/263)
- Family: [elifarley/hug-scm#190](https://github.com/elifarley/hug-scm/issues/190) (cmoda over-capture), [elifarley/hug-scm#191](https://github.com/elifarley/hug-scm/issues/191) (deferred cmoda guard design — `mgmt/plans/2026-06-29-cmoda-dirty-tree-safety-design.md`), [elifarley/hug-scm#207](https://github.com/elifarley/hug-scm/issues/207) (runtime visibility beats advisory TIPs)
- Sources: `git-config/bin/git-cmod`, `git-config/bin/git-cmoda`, `git-config/bin/git-c` (empty-index guard precedent)
- Libraries: `git-config/lib/hug-git-commit` (`commit_args_indicate_amend`, `suggest_next_push_command`), `git-config/lib/hug-output` (`error_blocked`, `HUG_EX_BLOCKED=3`), `git-config/lib/hug-cli-flags` (`parse_common_flags` strips `-f`/`-y`; `parse_pathspecs` pre-parses pathspecs — the §4 call site uses it before `parse_common_flags`), `git-config/lib/hug-git-state` (`get_untracked_files`)
- Prior art: `mgmt/plans/2026-06-29-cmoda-dirty-tree-safety-design.md` §3 (guard placement + call-site ordering), `docs/superpowers/specs/2026-07-14-visibility-batch-207-208-design.md` (prevention vs. transparency-aid distinction)
