# sh merge patch parity + shc -n wording cleanup — Design

- **Date:** 2026-09-12 (Rev 2 — mechanism + test inventory corrected after spec-roast round 1)
- **Status:** Approved (brainstorming session; user picked both contract decisions). Rev 2 folds in all roast findings: C-001/C-002 (wrong site-1 mechanism), C-006 (version floor), C-007/C-009 (inverted test inventory), C-010/C-011/C-012 (doc perimeter), F-001 (summary precision), O-002 (ours-merges).
- **Addresses:** [elifarley/hug-scm#346](https://github.com/elifarley/hug-scm/issues/346) (patch parity) and [elifarley/hug-scm#329](https://github.com/elifarley/hug-scm/issues/329) (wording fix)
- **Origin:** PR [elifarley/hug-scm#345](https://github.com/elifarley/hug-scm/pull/345) review (issue-268 merge-aware stats) + the `shc -n` adversarial review

## Summary

Two independent but sh-family-adjacent fixes land on one branch:

1. **#346 — Merge-commit patch parity.** Since the issue-268 fix, `hug shp` and `shcp` show merge-aware *stats* (per-parent, via the `git shc` delegation) but an *empty patch section* on clean merges — `shcp`'s "Diff for \<ref\>:" / `shp`'s "Commit diff:" header followed by nothing directly above a populated stats block (`hug sh` has no patch section at all — its only stake is its help text). Fix: merge patches become **first-parent diffs**, the contract `hug dd` already uses.
2. **#329 — Wording accuracy.** The `shc -n` example in CAPTURING OUTPUT help labels line output "pipe-safe", which overpromises (git still C-quotes structural characters in line mode; only `-z` is fully raw). Drop the label everywhere it appears for `shc -n`.

## The contract (stated once, reused verbatim)

> On a merge commit, hug **patch views diff against parent 1 only** — "what the merge brought in" (the `hug dd` contract). **File lists and stats stay per-parent** (issue-268 contract). Non-merge commit output is byte-identical to before. A merge whose result equals parent 1 (e.g. `git merge -s ours`) has an **empty** first-parent patch — the empty section legitimately persists for that class, so no wording may promise non-empty patches on *all* clean merges.

Why first-parent (Option B) over per-parent patches (Option A):

- On a clean merge of `side` (adds `side.txt`) into `main` (which added `main.txt` since divergence), per-parent patches print a `main.txt` hunk "against parent 2" — a mainline change that the merge did not introduce, duplicating commits reviewable via `shp <merge>^1`. First-parent prints exactly the merge's contribution: `side.txt`.
- Uniformity across hug's patch views (`dd`, `shp`, `shcp` all say "merge → parent 1") beats axis uniformity within one screen. The mixed axes (patch = parent 1, stats = each parent) are documented in every touched help text.

Rejected: keeping `git show`'s combined-`--cc` patch and documenting it — clean merges stay empty, which is the reported bug. (Subtlety: `git show` on a merge is a combined diff — empty on *clean* merges, conflict-resolution hunks on *dirty* merges. First-parent supersedes both; resolution hunks are a subset of the first-parent diff — probe-verified.)

## Behavior changes (code)

**The one merge mechanism, both sites (probe-verified on git 2.34.1):** an `is_merge_commit` gate (the existing `git-shc:278` predicate from hug-git-diff); on a merge, emit the **two-tree diff** `git diff-tree -p --no-commit-id -r --root "$m^1" "$m"`; otherwise keep today's invocation. Receipts: the two-tree form is byte-identical to `git show -m --first-parent` on a clean merge; byte-identical to the single-rev form and to `git show` on non-merges; exit-128 parity on bad refs.

> **Lesson (why not flag pairs):** Rev 1 specified `-m --first-parent` appended to both sites. Probing refuted site 1: `git diff-tree -p … -m --first-parent <merge>` emits the **per-parent concatenation** (parent-1 AND parent-2 hunks, both flag orders) — `--first-parent` is a history-traversal option, and single-rev `diff-tree` does not traverse, so there is nothing for it to restrict. `git show` (log family) honors the pair; `diff-tree` does not. Site 2's flag pair worked but was proven only on git 2.34.1 with no documented repo version floor (roast C-006) — the two-tree form is version-insensitive by construction and kills that exposure. One mechanism, one proven output shape, no version matrix.

| # | Site | Change |
|---|------|--------|
| 1 | `git-config/bin/git-shcp:148` (single-commit branch; `git diff-tree -p --no-commit-id -r --root "$commit_ref"`) | Gate on `is_merge_commit` (hug-git-diff — already sourced by git-shcp, line 9): merges → two-tree `git diff-tree -p --no-commit-id -r --root "$m^1" "$m"`; non-merges/root keep the single-rev form unchanged (a root has no `^1`). The range branch (`git diff <range>`) is untouched — endpoint diffs have no merge semantics. |
| 2 | `git-config/lib/hug-git-show` `_show_commit_standard` (`git show "$commit" --pretty=format:""`) and `_show_commit_llm` (`<diff>` CDATA, same invocation) | Same gate: merges → the two-tree form (with pathspecs appended after the two trees); **non-merges and root commits keep `git show` byte-for-byte** — this is load-bearing, see the rename note below. Covers `shp` standard and `--llm` output. Dirty merges deliberately change: combined-`--cc` hunks → full first-parent diff (superset; documented in help). |
| 3 | `sh` | No behavior change (no patch section). |

**Rename-rendering note (why site 2 keeps `git show` off-merge):** `git show` honors `diff.renames` (default true) and renders `rename from/to`; `git diff-tree -p` does not (probe-verified: same rename commit, show → 1 `rename from`, diff-tree → 0). Swapping `git show` for diff-tree wholesale would silently change every non-merge patch with a rename — breaking the byte-identity guarantee. With the merge gate, the diff-tree rendering applies only to merges, where output changes by design anyway. Consequence, documented here so nobody "fixes" it by accident: **merge patches render renames as delete+add**, matching the diff-tree semantics `shcp` already uses for its non-merge patches today (`git show`/`diff-tree` already disagree there; unifying that pre-existing split is out of scope).

Deliberate non-change: the stats axis. Per-parent stats are pinned by the issue-268 tests and stay exactly as they are.

## Help & docs updates

Single contract sentence, adapted per command; all help texts keep pointing at the stats contract that `hug shc -h` documents, and none may promise non-empty patches on all clean merges (ours-strategy merges stay empty).

- `git-config/bin/git-shc` NOTE block (`git-shc:14-19`): patch parity is **done** — state the patch = parent 1 / stats = each parent split (with the ours-merge empty-patch caveat); `hug-file-input` suppression boundary unchanged.
- `git-config/bin/git-sh` (`:63-65`): replace "(sh shows no patch; shp/shcp patches stay empty on clean merges.)" with the first-parent contract.
- `git-config/bin/git-shp` (`:42-44`) and `git-config/bin/git-shcp` (`:49-51`): replace "the patch section stays empty on clean merges" with the first-parent contract.
- `git-config/bin/git-shv` (`:52-54`): reword the now-dead contrast — "A single commit is diffed against its FIRST parent, so `shv <merge>` can differ from `shp <merge>` (which renders a combined diff)" → `shv` and `shp` **agree** on merges (both diff against parent 1). After this change the two help texts must not contradict each other.
- `docs/commands/head.md` (`:217`): flip "Patch sections stay empty on clean merges" to the new contract.
- `tests/unit/test_sh.bats` (`:634-635`): update the stale comment "(sh's PATCH section stays empty on clean merges — patch parity is elifarley/hug-scm#346, deliberately not pinned here.)" → "(sh has no patch section; shp/shcp patches diff against parent 1 on merges — elifarley/hug-scm#346.)"
- `CHANGELOG.md` (`:10`, v1.18.0.0): released entries stay as history — but the **next** release note must explicitly supersede: "Patch sections on merges now show the first-parent diff (supersedes the v1.18.0.0 note)." The ship workflow owns adding that entry; this spec records the requirement so an upgrading reader never holds two contradictory authoritative statements.
- **#329 wording (4 sites):**
  - `git-shc:97` — `hug shc -n main..HEAD   # Paths only (repo-relative)` (label dropped; the `-z` example two lines below already covers arbitrary filenames).
  - `docs/cookbook.md:192` — same drop.
  - `docs/skills/hug-repo-analysis/SKILL.md:114,289` — `# files changed, paths only` (label dropped).
- Implementation-time docs sweep (widened after round 1): `grep -rnE "stays? empty|patch parity|combined diff" docs/ README.md git-config/ tests/ CHANGELOG.md` — exclude `docs/.vitepress/dist/` (generated) and this spec's own quotations of the old wording (self-reference hits are expected).

Out-of-scope "pipe-safe" mentions (accurate as written): `git-dd:105`, `git-shv:59` — they refer to patch commands, not `shc -n`.

## Tests (TDD: new pins first, then implementation)

Corrected inventory after round 1 — the roast found Rev 1's map inverted (it cited a nonexistent lib-level merge pin and omitted the live one). Current truth, grep-verified:

`tests/unit/test_sh.bats` reuses `_setup_merge_fixture`:

- **Flip** `test_sh.bats:679` — `@test "hug shp: merge stats list merged files while the patch stays empty (delegation, issue 268)"`: rename the test, and invert the `:700` pin (`refute_output --partial "diff --git"` → assert the parent-1 file's `diff --git` hunk present AND the parent-2-only file's hunk absent), while keeping the both-parents stats assertions (`side-shp.txt` + `feature2.txt`) and the "Changed files" chatter containment. This is the only existing pin of the old patch behavior.
- **Add** `shcp <merge>` (single commit): first-parent patch contract, mirroring the shp pin.
- **Add** `shcp -N` range whose tip is a merge: unchanged endpoint diff (regression pin).
- **Add** `shp --llm <merge>`: `<diff>` CDATA contains the first-parent patch.
- **Add** ours-merge pin: `shp` on an `-s ours` merge → patch section empty (legitimately — result equals parent 1) while stats stay per-parent; guards the wording caveat.
- **Add** rename-commit regression at site 2: a non-merge commit that renames a file still renders `rename from/to` (guards the keep-`git show`-for-non-merges decision).
- Non-merge and root commit: patch output unchanged (byte-identical pins).
- Dirty merge: full first-parent diff, not just `--cc` hunks (pins the deliberate change).
- Help-contract probes: update refutes pinning the old wording ("stay empty", "renders a combined diff", "pipe-safe"); assert the new contract sentence in sh/shp/shcp/shv help.

`tests/lib/test_hug_git_show.bats`: has **no** lib-level merge pin today (`grep -n "merge\|Merge"` → zero hits; the `:564` comment is a pathspec-tail characterization and belongs to the non-merge byte-identical pins at `:562-570`, which must NOT change). **Add** a lib-level pin: `_show_commit_standard`/`_show_commit_llm` on a merge emit the first-parent patch (and the LLM `<diff>` CDATA carries it).

## Edge cases

- Octopus merges: parent-1-only diff — the two-tree form diffs `M^1` vs `M` regardless of parent count by construction; roast round 1 additionally probed a 3-parent fixture directionally (its `diff-tree -m --first-parent` variant leaked extra per-parent blocks, consistent with C-001 on a second shape).
- Ours-strategy merges (`-s ours`): first-parent diff is empty (probe: 0 bytes, both forms) — the empty section persists for this class; covered by a dedicated pin and the wording caveat.
- `-- <path>` filtering: the two-tree form appends pathspecs after the trees (flag order: `git diff-tree <flags> M^1 M -- <pathspec>`); site 2 keeps its existing pathspec plumbing.
- `sh`'s dash-data `-N` handling: untouched.
- Stdout/stderr discipline: patch/stats data stays on stdout; headers stay where they are today (no re-routing in this change).

## Error handling

No new failure modes — the merge branch only changes git's argument shape for commits that today produce empty output, and bad refs keep git's own exit-128 (parity probed for both forms). `is_merge_commit` is the same predicate `git-shc` already exercises in production.

## Out of scope

- Stats axis (per-parent; pinned by issue-268 tests).
- `pinned_diff` patch-format extension (`--name-only`/`--stat` only today).
- Version bump mechanics (ship workflow owns the new CHANGELOG entry — but its superseding sentence is a requirement of this change, see Help & docs).
- Unifying the pre-existing `git show` vs `diff-tree` rename-rendering split between `shp` and `shcp` non-merge patches.
- hg-config parallel implementation (the hg sh family has no merge-aware patch/stats contract — verify applicability during implementation).

## Success criteria

1. `hug shp <merge>` and `hug shcp <merge>` show the **first-parent diff** above per-parent stats — empty only when the merge introduced nothing vs parent 1 (e.g. `-s ours`), which is pinned as correct behavior.
2. `shp --llm` `<diff>` shows the same first-parent patch.
3. Non-merge output byte-identical to pre-change (test-pinned, including rename rendering).
4. No user-facing text claims `shc -n` line output is "pipe-safe"; `shc -z` remains documented as the fully-raw stream.
5. No user-facing text says `shp <merge>` renders a combined diff or that merge patches stay empty; `shv` and `shp` help agree on merges.
6. `make test-bash` passes in the worktree, and `make docs-build` succeeds (three markdown docs are touched: `head.md`, `cookbook.md`, `SKILL.md`).

## Rev 1 → Rev 2 corrections (roast round 1, all probe-verified)

- Site-1 mechanism: flag pair (`-m --first-parent`) → merge-gated two-tree diff (the flag pair emitted per-parent output — C-001/C-002).
- Site-2 mechanism: same two-tree form on merges only; `git show` kept for non-merges/root, which also preserves rename rendering the flag-pair simplification would have silently changed (C-006 + rename probe).
- Test inventory: removed the phantom `test_hug_git_show.bats:564` flip; added the real flip target `test_sh.bats:679/700` and the new lib-level pin (C-007/C-009).
- Doc perimeter: added `git-shv:52-54`, `CHANGELOG.md:10` supersession policy, `test_sh.bats:634` comment; sweep pattern widened with `combined diff` and `tests/`/`CHANGELOG.md` paths (C-010/C-011/C-012).
- Summary precision: `sh` has no patch section; header attribution per command (F-001). Contract wording must not promise non-empty patches on all clean merges (O-002).
