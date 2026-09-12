# sh merge patch parity + shc -n wording cleanup — Design

- **Date:** 2026-09-12
- **Status:** Approved (brainstorming session; user picked both contract decisions)
- **Addresses:** [elifarley/hug-scm#346](https://github.com/elifarley/hug-scm/issues/346) (patch parity) and [elifarley/hug-scm#329](https://github.com/elifarley/hug-scm/issues/329) (wording fix)
- **Origin:** PR [elifarley/hug-scm#345](https://github.com/elifarley/hug-scm/pull/345) review (issue-268 merge-aware stats) + the `shc -n` adversarial review

## Summary

Two independent but sh-family-adjacent fixes land on one branch:

1. **#346 — Merge-commit patch parity.** Since the issue-268 fix, `hug sh`, `shp`, and `shcp` show merge-aware *stats* (per-parent, via the `git shc` delegation) but an *empty patch section* on clean merges — "Diff for HEAD:" followed by nothing above a populated stats block. Fix: merge patches become **first-parent diffs**, the contract `hug dd` already uses.
2. **#329 — Wording accuracy.** The `shc -n` example in CAPTURING OUTPUT help labels line output "pipe-safe", which overpromises (git still C-quotes structural characters in line mode; only `-z` is fully raw). Drop the label everywhere it appears for `shc -n`.

## The contract (stated once, reused verbatim)

> On a merge commit, hug **patch views diff against parent 1 only** — "what the merge brought in" (the `hug dd` contract). **File lists and stats stay per-parent** (issue-268 contract). Non-merge commit output is byte-identical to before.

Why first-parent (Option B) over per-parent patches (Option A):

- On a clean merge of `side` (adds `side.txt`) into `main` (which added `main.txt` since divergence), per-parent patches print a `main.txt` hunk "against parent 2" — a mainline change that the merge did not introduce, duplicating commits reviewable via `shp <merge>^1`. First-parent prints exactly the merge's contribution: `side.txt`.
- Uniformity across hug's patch views (`dd`, `shp`, `shcp` all say "merge → parent 1") beats axis uniformity within one screen. The mixed axes (patch = parent 1, stats = each parent) are documented in every touched help text.

Rejected: keeping `git show`'s combined-`--cc` patch and documenting it — clean merges stay empty, which is the reported bug. (Subtlety: `git show` on a merge is a combined diff — empty on *clean* merges, conflict-resolution hunks on *dirty* merges. First-parent supersedes both; resolution hunks are a subset of the first-parent diff.)

## Behavior changes (code)

| # | Site | Change |
|---|------|--------|
| 1 | `git-config/bin/git-shcp` single-commit path (`git diff-tree -p --no-commit-id -r --root`) | Add `-m --first-parent`. Both flags are no-ops on non-merges; `--root` keeps root-commit diffs. The range path (`git diff <range>`) is untouched — endpoint diffs have no merge semantics. No `is_merge_commit` probe on this branch (already single-commit, never a range); if test probing on a real repo shows git needs it, fall back to the `git-shc:278` probe pattern. |
| 2 | `git-config/lib/hug-git-show` `_show_commit_standard` and `_show_commit_llm` (`git show "$commit" --pretty=format:""`) | Add `-m --first-parent`. Covers `shp` standard and `--llm` `<diff>` CDATA output. Dirty merges deliberately change: combined-`--cc` hunks → full first-parent diff (superset; documented in help). |
| 3 | `sh` | No behavior change (no patch section). |

Deliberate non-change: the stats axis. Per-parent stats are pinned by the issue-268 tests and stay exactly as they are.

## Help & docs updates

Single contract sentence, adapted per command; all four help texts keep pointing at the stats contract that `hug shc -h` documents.

- `git-config/bin/git-shc` NOTE block (`git-shc:14-19`): patch parity is **done** — state the patch = parent 1 / stats = each parent split; `hug-file-input` suppression boundary unchanged.
- `git-config/bin/git-sh` (`:63-65`): replace "(sh shows no patch; shp/shcp patches stay empty on clean merges.)" with the first-parent contract.
- `git-config/bin/git-shp` (`:42-44`) and `git-config/bin/git-shcp` (`:49-51`): replace "the patch section stays empty on clean merges" with the first-parent contract.
- `docs/commands/head.md` (`:217`): flip "Patch sections stay empty on clean merges" to the new contract.
- **#329 wording (4 sites):**
  - `git-shc:97` — `hug shc -n main..HEAD   # Paths only (repo-relative)` (label dropped; the `-z` example two lines below already covers arbitrary filenames).
  - `docs/cookbook.md:192` — same drop.
  - `docs/skills/hug-repo-analysis/SKILL.md:114,289` — `# files changed, paths only` (label dropped).
- Implementation-time docs sweep: `grep -rn "stay empty\|patch parity" docs/ README.md git-config/` for stragglers, excluding `docs/.vitepress/dist/` (generated).

Out-of-scope "pipe-safe" mentions (accurate as written): `git-dd:105`, `git-shv:59` — they refer to patch commands, not `shc -n`.

## Tests (TDD: new pins first, then implementation)

`tests/unit/test_sh.bats` reuses `_setup_merge_fixture`:

- `shp <merge>`: patch contains the parent-1 file's hunk; a parent-2-only file's hunk absent; stats still list both parents' files (per-parent).
- `shcp <merge>` (single commit): same patch contract.
- `shcp -N` range whose tip is a merge: unchanged endpoint diff (regression pin).
- `shp --llm <merge>`: `<diff>` CDATA contains the first-parent patch.
- Non-merge and root-commit: patch output unchanged (byte-identical pins).
- Dirty merge: full first-parent diff, not just `--cc` hunks (pins the deliberate change).
- Help-contract probes: update refutes pinning the old wording ("stay empty", "pipe-safe"); assert the new contract sentence in sh/shp/shcp help.

`tests/lib/test_hug_git_show.bats:564`: currently pins that merge `git show` output stays empty — flip to pin the first-parent patch; keep the neighboring non-merge byte-identical pins.

## Edge cases

- Octopus merges: parent-1-only diff (the contract covers 3+ parents without special-casing).
- `-- <path>` filtering: new diff flags must precede the `--` pathspec separator (arg order preserved).
- `sh`'s dash-data `-N` handling: untouched.
- Stdout/stderr discipline: patch/stats data stays on stdout; headers stay where they are today (no re-routing in this change).

## Error handling

No new failure modes — both sites only extend existing git invocations with no-op-on-non-merge flags. Bad refs still surface via git's own fatal, unchanged.

## Out of scope

- Stats axis (per-parent; pinned by issue-268 tests).
- `pinned_diff` patch-format extension (`--name-only`/`--stat` only today).
- CHANGELOG / version bump (ship workflow owns that).
- hg-config parallel implementation (the hg sh family has no merge-aware patch/stats contract — verified during implementation if applicable).

## Success criteria

1. `hug shp <clean-merge>` and `hug shcp <clean-merge>` show a first-parent patch above per-parent stats — no empty section on the same screen.
2. `shp --llm` `<diff>` shows the same patch.
3. Non-merge output byte-identical to pre-change (test-pinned).
4. No user-facing text claims `shc -n` line output is "pipe-safe"; `shc -z` remains documented as the fully-raw stream.
5. `make test-bash` passes in the worktree, and `make docs-build` succeeds (three markdown docs are touched: `head.md`, `cookbook.md`, `SKILL.md`).
