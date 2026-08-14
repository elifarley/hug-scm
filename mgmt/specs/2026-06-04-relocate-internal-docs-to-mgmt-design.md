# Design: Relocate internal artifacts from `docs/` to a top-level `mgmt/`

- **Date:** 2026-06-04
- **Status:** Approved (brainstorming) — pending implementation plan
- **Related:** Resolves [elifarley/hug-scm#170](https://github.com/elifarley/hug-scm/issues/170) (docs deploy broken). Sibling of the v1.1.0 follow-up cluster (#169, #171, #172).

## Problem

`docs/` mixes two unrelated things:

1. **Published user docs** — the VitePress site (`architecture/` ADRs, `commands/`, `mcp-server/`, `skills/`, guides).
2. **Internal artifacts** — planning/review scratch (`plans/` 57 tracked + 24 untracked, `planning/` 17, `superpowers/` 9 untracked, `mgmt/ADL/`).

VitePress's `srcDir` is `docs/`, so it compiles **every** `.md` under it as a Vue SFC — including the internal artifacts. A single stray `<token>` in a planning doc (e.g. `@<cat>`, `/<query>` in an unfenced diagram) is parsed as an unclosed HTML element and fails the whole build. That is the root cause of #170: the GitHub Pages deploy has been red for weeks, so the published site is stale.

The deeper issue is the mixing itself: internal scratch does not belong in the published-docs source tree. Fixing one file is whack-a-mole; the next planning doc reintroduces the break.

## Decisions (and why)

1. **Top-level `mgmt/`, not `docs/mgmt/` or `srcExclude`-in-place.** Moving internal artifacts to a sibling of `docs/` puts them physically outside `srcDir`, so VitePress can never compile them. This fixes #170 *by construction* (no `srcExclude` rule to maintain, no "remember to exclude the next folder"). The alternatives — consolidating under `docs/mgmt/` or just adding `srcExclude` — keep the artifacts inside the build tree and rely on an exclude rule for safety.

2. **One true home: ADL moves to `mgmt/ADL` too** (not left behind at `docs/mgmt/`). A split home (`mgmt/` for plans, `docs/mgmt/` for ADL) would be confusing. The cost is that `adl-ops` and `kanban-ops` **hardcode** `docs/mgmt` in a shared `resolve_mgmt()` helper, so unifying requires a small global-tooling edit (decision 3).

3. **Make the global `resolve_mgmt()` prefer a top-level `mgmt/` when present, else `docs/mgmt/`.** This is additive and backward-compatible: repos without a top-level `mgmt/` keep using `docs/mgmt/` unchanged; only repos that adopt the new layout switch over. The same change applies to both `adl-ops/scripts/adl_append.py` and the duplicated logic in `kanban-ops/scripts/bootstrap.py`.

## Target structure

```
repo/
  docs/                     # published VitePress site ONLY (srcDir)
    index.md, getting-started.md, workflows.md, ...
    architecture/   # ADRs (published)
    commands/  mcp-server/  meta/  screencasts/  skills/  img/  public/
    .vitepress/
  mgmt/                     # NEW top-level: internal artifacts, never built
    plans/                  # from docs/plans
    planning/               # from docs/planning
    superpowers/            # from docs/superpowers (keeps specs/, plans/ substructure)
    ADL/                    # from docs/mgmt/ADL
    specs/                  # design specs (this doc is the first)
```

## Taxonomy — what moves vs. stays

**Stays in `docs/` (published or externally referenced):**

- `architecture/` — ADRs are user/contributor-facing decisions.
- `commands/`, `mcp-server/`, `meta/` — published reference.
- `screencasts/` — VHS build tooling (non-`.md`, does not break the build).
- `skills/` — **its README documents a `curl …/main/docs/skills/hug-workflow.skill` install URL**; moving it would break that documented link.
- `img/`, `public/`, root `*.md`, `.vitepress/`.

**Moves to `mgmt/` (internal artifacts):**

- `docs/plans/` → `mgmt/plans/`
- `docs/planning/` → `mgmt/planning/`
- `docs/superpowers/` → `mgmt/superpowers/`
- `docs/mgmt/ADL/` → `mgmt/ADL/`

## Migration mechanics

- **Tracked files:** `git mv` (preserves `git log --follow` history).
- **Untracked WIP** (24 in `plans/`, 2 in `planning/`, 9 in `superpowers/`): plain `mv` — they are not in git, so they move as files and remain uncommitted at the new location. Junk cleanup is a separate concern, not this migration's job.
- **1:1 move**, preserving each folder's internal substructure. No merging of `plans/` + `planning/`; no renaming of `superpowers/`.

## In-repo reference updates

- `CLAUDE.md`: the documentation decision tree and the "Planning Docs | `docs/plans/`" row → `mgmt/plans/`; the ADL "Base path: `docs/mgmt/ADL`" → `mgmt/ADL`; `docs/superpowers` references.
- `docs/DOCS_ORGANIZATION.md`: placement rules now route internal artifacts to `mgmt/`.
- Cross-reference sweep over moved `*.md` for **absolute** `docs/plans|planning|superpowers` references (relative cross-refs survive the bulk move automatically).
- VitePress nav: **no change needed** — the sidebar only links `/mcp-server/architecture`; the internal folders were orphan pages, never linked.
- `.gitignore`: no change needed (only `docs/screencasts/bin/vhs` is listed; that folder stays).

## Global tooling change (outside this repo)

- `~/.claude/claude-a/skills/adl-ops/scripts/adl_append.py` — `resolve_mgmt(root)`: return `root/"mgmt"` if it exists, else `root/"docs"/"mgmt"`.
- `~/.claude/claude-a/skills/kanban-ops/scripts/bootstrap.py` — the duplicated `detect_mgmt`/`resolve_mgmt` logic gets the same change (the source comment flags this duplication).
- `~/.claude/claude-a/CLAUDE.md` — update the ADL "Base path" note to describe the `mgmt/` preference with `docs/mgmt/` fallback.

These are global and shared by all the user's repos; the preference-with-fallback shape keeps every existing repo working unchanged.

## #170 resolution & build safety

Once `docs/plans/` (and the other internal folders) leave `srcDir`, VitePress no longer sees them, so the build break disappears. **The migration closes #170 and makes its proposed `srcExclude` band-aid unnecessary** — no `srcExclude` is added at all. Build safety is structural (out of `srcDir`), not rule-based.

## Verification

- `make docs-build` is green.
- `git log --follow mgmt/plans/<some-file>.md` shows pre-move history survived.
- After the global edit, `adl-ops` writes a new entry to `mgmt/ADL/` (not `docs/mgmt/ADL/`); a repo *without* a top-level `mgmt/` still resolves to `docs/mgmt/` (fallback unbroken).
- No broken in-repo links (grep finds no stale `docs/plans|planning|superpowers` absolute refs).
- The GitHub Pages deploy goes green on the next push.

## Rollout order

1. Create `mgmt/` and migrate folders (`git mv` + `mv`).
2. Update in-repo references.
3. Edit the two global skills + global ADL note.
4. Verify (`make docs-build`, history, adl-ops fallback) and confirm deploy is green; close #170.

## Out of scope

- Merging `plans/` and `planning/`.
- Renaming `superpowers/`.
- Inventing `kanban/`/`DEC` structure (the now-`mgmt/`-aware skills create those on first use).
- Cleaning up untracked junk under the moved folders (separate housekeeping).

## Risks

- **A global skill that bypasses `resolve_mgmt()` and hardcodes `docs/...` elsewhere** could still write into `docs/`. Mitigation: the verification step exercises `adl-ops` end-to-end; if anything recreates a `docs/`-internal folder, that is a follow-up, not a blocker.
- **The global edit affects work repos.** Mitigation: preference-with-fallback is additive; test in a scratch repo with and without a top-level `mgmt/` before relying on it.
