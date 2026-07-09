# Design: Ship the worktree ritual with hug — `hug help :worktree` + a shipped skill

**Date:** 2026-07-09
**Status:** Approved
**Author:** brainstorming session

## Context

Hug ships worktree commands (`hug wtc` / `wtl` / `wtdel`) and an agent guide
(`hug help :agents`). What it does **not** yet ship is the *ritual* around those
commands at any depth: always start branch-worthy work in a fresh worktree, base
it off an up-to-date integration branch, provision it, work **inside** it, clean
it up after merge. Today that ritual exists only as a cramped section in
`agents.md`.

Two gaps follow:

1. **Not reachable at depth, tool-agnostically.** Any agent driving hug — Claude
   Code, Codex, Cursor, Gemini, OpenCode — should get the same ritual, at the
   same depth, regardless of host. A few lines in one guide isn't that.
2. **Adding a skill naively would duplicate it.** Skill-aware hosts want a
   `hug-worktree` *skill* affordance; authored naively, that skill would carry
   its own copy of the ritual and drift from `agents.md`. The ritual needs one
   canonical home *before* a second consumer exists.

This design ships the ritual **with hug** as a first-class article
(`hug help :worktree`) — the canonical home — collapses the `agents.md` section
to a menu + safety echo + pointer, and adds a **thin, host-neutral skill** that
delegates to the article (no prose of its own). One prose home, three access
paths. The article mechanism is the one from `2026-05-06-help-articles-design.md`;
this is a drop-in markdown file, no loader changes.

## Goals

1. `hug help :worktree` renders the full worktree ritual in the terminal —
   reachable by any agent or human using hug.
2. Single source of truth: the ritual prose lives in exactly one place (the
   article). `agents.md` keeps only a command menu + a minimal safety echo + a
   pointer.
3. A shipped, host-neutral `hug-worktree` skill that delegates to the article
   (no ritual prose of its own), so downstream agent configs can consume it by
   symlink or copy without forking the content.
4. The stale `docs/skills/README.md` install path is corrected in the same
   change (it currently points at a `.skill` bundle that does not exist).

## Non-goals

- **No loader changes.** `articles_loader.py` already glob-discovers
  `articles/*.md`; `worktree.md` is a drop-in — no registration, no code.
- **No search integration.** Consistent with the article design, `:worktree`
  stays in the `:` namespace; it does not appear in `/keyword` or `!intent`.
- **No new worktree behavior.** Documentation + packaging only; the
  `wtc` / `wtl` / `wtdel` commands are unchanged.
- **No host-specific wiring.** How a particular agent config consumes the
  shipped skill (symlink, copy, per-host dirs) is that config's concern, not
  hug's. This design stops at "hug ships a consumable skill."

## Approach

The packaging decision (article + thin per-host wrapper) was chosen over two
alternatives:

| | A — Article + thin shipped skill (chosen) | B — Fat skill only | C — agents.md only |
|---|---|---|---|
| Tool-agnostic reach | Yes — any agent via `hug help :worktree` | No — only skill-aware hosts | Yes, but cramped |
| Single source of truth | Yes — article is canonical | Skill is canonical; agents.md drifts | One place, no skill affordance |
| Host skill affordance | Yes — thin wrapper delegates | Yes, but duplicates prose | No |
| Drift risk | Low — one prose home | High — skill vs agents.md | Low |

A wins: the article is the tool-agnostic canonical home; the skill is a thin
affordance for skill-aware hosts; `agents.md` shrinks to a pointer. One prose
home, three access paths (`hug help :worktree`, the skill, the agents.md
pointer).

## Architecture

### Deliverables

```
git-config/lib/python/articles/
  worktree.md          ← NEW — full ritual prose (canonical), order=30
  agents.md            ← SHRINK — worktree section → menu + safety echo + pointer
docs/skills/
  hug-worktree/
    SKILL.md           ← NEW — thin wrapper, delegates to `hug help :worktree`
  README.md            ← FIX — directory-based install; list all shipped skills
```

### `worktree.md` — the canonical article

Frontmatter (per the article schema — TOML fenced by `+++`, `summary` ≤ 70
chars, `order` sorts the listing ascending):

```markdown
+++
title   = "Worktrees: the branch-worthy-work ritual"
summary = "Always start branch-worthy work in a fresh worktree — the ritual."
order   = 30
+++
```

`order = 30` slots it right after `agents` (20) in `hug help :` — the two
agent-facing articles sit together. Slug = filename stem → `hug help :worktree`.

Body = the full ritual, **harness-neutral** (no host/tool names in the prose):

- **Worktree-first + WHY** — branch-worthy work (spec / feature / bugfix /
  refactor / multi-step) always starts in a NEW worktree, never a bare branch in
  the main checkout; it is the first step, before any other action.
- **Skip conditions** — trivial one-file edits, read-only inspection, or already
  being inside the right worktree.
- **The ritual** — create (`hug wtc <branch> --base [remote/]<pt> -y`, basing
  off an UP-TO-DATE integration branch, not a stale local HEAD) → work INSIDE
  the new worktree (the #1 mistake is creating it then editing the main
  checkout) → provision project deps via the project's Makefile target where one
  exists (e.g. a `dev-env-init` / deps-sync target) → before finishing, run the
  project's sanitize/verify → after merge, clean up
  (`hug wtdel <branch> --force`; `--with-branch` to drop the branch too).
- **Hard rules** — never `git worktree` (use `hug wtc`); never pass an explicit
  path or `.worktrees/` (hug chooses the canonical `<repo>.WT.<branch>` path).
- **Subagent note** — dispatched agents inherit the worktree; they must act
  inside it, not re-derive a path.

### `agents.md` — shrink to pointer + safety echo

The worktree section collapses to: the command menu, a two-line safety echo
(never `git worktree`; never an explicit path), and `Full ritual:
hug help :worktree`. The current "Load the hug-worktree skill …" line becomes
the `hug help :worktree` pointer. Rationale for keeping a *minimal* echo rather
than a pure pointer: an agent may act on the command menu without opening the
article, so the two hardest safety rules stay inline; the depth lives once, in
the article.

### `docs/skills/hug-worktree/SKILL.md` — thin wrapper

A host-neutral skill whose body is essentially "run `hug help :worktree` and
follow that ritual," plus an authoritative-syntax pointer (the article and
`hug help wtc|wtl|wtdel` are the source of truth for flags). No ritual prose of
its own — it delegates, so it can never drift from the article. Frontmatter:
`name`, `description` (when to use — starting branch-worthy work), and a minimal
`allowed-tools` (Bash, to run `hug`).

### `docs/skills/README.md` — fix the install path

Current instructions install a single-file `hug-workflow.skill` bundle that does
not exist; the real shipped format is a directory (`hug-workflow/SKILL.md`). Fix:

- Replace the `.skill` curl/cp with directory-based install (both current skills
  are a single `SKILL.md`, so `mkdir -p ~/.claude/skills/<name>` +
  `curl … /<name>/SKILL.md` works today; plus `cp -r docs/skills/<name>
  ~/.claude/skills/` for repo clones).
- List all shipped skills: add `hug-worktree` (note it pairs with
  `hug help :worktree` for non-skill agents) and backfill `hug-repo-analysis`,
  which already ships but is undocumented.
- Note the single-file-curl limitation (holds only while a skill is one
  `SKILL.md`); a multi-file-safe installer is a possible follow-up, not part of
  this change.

## Verification

- `hug help :worktree` renders; `hug help :` lists it after `agents`
  (order 20 → 30); `summary` ≤ 70 chars (loader hard-fails otherwise).
- `hug help :agents` still renders; its worktree section points to
  `hug help :worktree` with no dangling reference and no duplicated ritual prose.
- The `hug-worktree` skill loads in a skill-aware host and its body resolves to
  the article (delegation, not a copy).
- README install steps run clean (dry-run the curl + `cp -r`); zero `.skill`
  references remain; all shipped skills listed.

## Rollout

Single hug-scm change (article + agents.md shrink + skill + README). No loader
or command changes, so no migration and no version gate — the article is
discoverable the moment the file lands.
