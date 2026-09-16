# Intent: Truthful pathspec-scoped commit preview for `hug c`

Author: HugSCM Agent. Status: draft.
Issue: [elifarley/hug-scm#352](https://github.com/elifarley/hug-scm/issues/352)
Branch: 352-hug-c-pathspec-scoped-commit-preview-and-scope-aware-guard

## Problem

`hug c`'s pre-commit preview ignores pathspecs, so it announces files git will not commit:

```
$ hug c -F - -- c.txt            # a.txt, b.txt, c.txt all staged
stdout: [master 8eac150] probe: pathspec-scoped commit / 1 file changed     <- only c.txt
stderr: Committing staged file(s) (3): a.txt b.txt c.txt                    <- FALSE
after:  hug sls shows S:Mod a.txt, S:Mod b.txt
```

Three sinks model three different realities for one argv: the preview reads the whole index
(`git diff --cached --name-only`), the guard demands staged changes regardless of scope, and the
forwarded `git commit "$@"` runs without the `--` separator (already consumed by
`parse_common_flags`' fallback arm). The path *tokens* survive positionally, so the commit is usually
right while the preview is wrong — the failure mode is silence, not error.

Two sharper findings make this more than a stale list. First, a pathspec commit takes the named
paths' **working-tree** content (git's `--only` semantics — probed: index=STAGED, worktree=WORKTREE →
HEAD holds WORKTREE), so `hug a -p file` followed by `hug c -- file` commits more than was staged:
a silent *widening* in a tool whose stated rule is "narrowing only, never widening". Second, the
swallowed separator means `hug c -m x -- -weird-file` hands `-weird-file` to git as an option.

The preview exists precisely to make the index state visible (elifarley/hug-scm#207, shipped in
elifarley/hug-scm#210); today it is the least trustworthy surface in the command.

## Proposed outcome

`hug c … -- <path>...` becomes a first-class, previewed mode with one coherent story:

- the scope is known at entry (`parse_pathspecs` before flag parsing, the `git-cmod` idiom) and
  validated loudly before any preview;
- the preview answers both questions a user actually has — **what goes in** (the named paths'
  changes) and **what stays out** (staged entries left in the index) — plus a warning when named
  paths carry unstaged changes that will ride along;
- the forwarded `git commit` gets the separator back, so "what was previewed is what is committed";
- the guard matches the mode: staged changes are required only in the unscoped form, where the index
  *is* the commit; in the scoped form git's own "nothing to commit" is the honest gate;
- help text, the `:pathspec` article's support matrix, `docs/commands/commits.md` and CHANGELOG all
  state the mode, its `--only` content semantics, and the observable flips.

Deliberately outside this outcome: `-a`/`--all`/`--only`/`--patch` detection (parked as
elifarley/hug-scm#211) and bare-positional scoping (`hug c -m x file.txt`), because git's
value-taking option set is open and hug cannot classify those tokens without guessing.

## Affected users and systems

- **Users**: humans recovering from a soft reset who commit a subset by path; agents doing
  path-scoped commits mid-workflow; anyone relying on the preview to confirm intent before a commit
  lands. Scripts grepping `hug c` stderr: the unscoped string stays byte-identical; the scoped form
  gains new, distinct strings.
- **Surface**: `git-config/bin/git-c` (parse, guard, preview, forwarded call, help),
  `git-config/lib/hug-git-files` (one new pathspec-scoped lister), `git-config/lib/README.md`, the
  `:pathspec` article (the `hug help :pathspec` matrix), `docs/commands/commits.md`, CHANGELOG, and
  the BATS unit + lib suites.
- **Unchanged by design**: unscoped `hug c` behavior and messages; `hug cmod`/`cmoda`; the exit-code
  classes (usage errors stay exit 2).

## Constraints

- **Repo pathspec law**: uniform contract — parse the separator first, validate at entry, and flow
  ONE validated set to every sink; `parse_pathspecs` must run before `parse_common_flags` because the
  latter consumes a trailing `--`. Bare positionals keep git parity (compat rule).
- **Naming**: the working name `list_changed_files` sits dangerously close to branch 282's
  `list_changed_files_in_range` (a range differ in `hug-git-commit`); the spec must pick a distinct,
  scope-explicit name rather than extend a name family it does not belong to.
- **Display stance** (elifarley/hug-scm#282): the changed-files family carries a documented
  sorted-unique output contract, with `sort -u` made load-bearing by a hostile `diff.orderFile` test.
  New preview lists must either adopt that stance or justify diverging.
- **Path spelling** (elifarley/hug-scm#269): machine-mode spelling conventions live there; these
  preview lists are stderr chatter, but they must agree with `hug sls` — the preview's own hint sends
  users to it, and disagreeing spellings in the same workflow are the bug class being fixed.
- **Portability/idioms**: Bash 4.0–4.3 floor (no `mapfile -d`; count-guarded empty-array expansion),
  `set -euo pipefail` safety at every new branch, `print_list` does not honor `HUG_QUIET` so the
  call-site gate must stay, and staged listings keep `--ignore-submodules=none`.
- **Coordination**: the explicit `-- <path>` form is hug's own previewed contract; raw
  `--only`/`-a`/`--patch` stay elifarley/hug-scm#211's target, so the two must not produce
  contradictory guidance.
- **Verification**: Makefile targets only (`make test-unit` / `make test-lib` / `make test`), and the
  suite run from a linked worktree is known to pollute the worktree index
  (elifarley/hug-scm#168) — the verification steps must account for it rather than assume a clean
  tree after a run.
- **Process**: intent → spec → `/code-roast` → `cv-roast-receive` → `cv-plan-pr`; no quality gates
  before the markdown commits.

## Open questions

1. **Ordering contract**: sort-unique all three preview lists (adopting the #282 stance; default
   config output stays byte-identical) or only the newly computed union? *Leaning: all three — one
   rule for every list the preview prints.*
2. **Ride-along severity**: should the unstaged-content notice be a `warning` (it is a widening) or a
   `tip`, and should it name a count or the affected files?
3. **Scoped acknowledgement**: `cmod` announces its mode (`Amending last commit with the named paths'
   changes…`). Should the scoped `hug c` print a matching one-line `info`, or is the preview list
   enough?
4. **#211 hand-off**: when #211 lands, should its abort path for a raw `--only` point users at
   `hug c -- <path>` (the supported, previewed spelling)? If yes, file that as a coordination note on
   elifarley/hug-scm#211 at PR time.
