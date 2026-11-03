# mgmt/ — project governance

This directory is the **single source of truth** for project governance.
Decisions, risks, RFCs, and agent decision logs live here.
Work tracking (tasks, backlog, incidents) is managed via GitHub Issues + Projects.

## Map

| File | Content |
|---|---|
| `decisions.md` | DEC-NNN log. Append-only. |
| `rfcs/RFC-NNN-{slug}.md` | Formal proposals. |
| `risks.md` | Risks with mandatory auto-flip trigger. |
| `config.yml` | Tracking provider config + ID series. |
| `ADL/YYYY-MM-DD.adl.md` | Autonomous Decision Log. Daily append. → see `/adl-ops` |

## Inviolable rules

### 1. Pointer pattern (single source of truth)

Justification lives in **one canonical place** — almost always a DEC. Other files reference, never duplicate.

### 2. Superseded-by — never addendum

Obsolete plan, RFC, or DEC gets a header **at the top**:

```markdown
> **Superseded-by:** DEC-NNN (YYYY-MM-DD) — short summary of new direction.
```

Don't delete old content. It's history.

### 3. Auto-flip trigger in risks

Every row in `risks.md` needs a "Mitigated when ..." column. No trigger = no row.

### 4. Zero-padded sequential IDs

DEC-NNN (3 digits), RFC-NNN (3), R-DOMAIN-NN (2). Use `next_id.py` to generate — never guess.

### 5. Tracking via provider

Work tracking goes through `python -m tracking`. Never construct raw `gh` commands.

## When to create

| Situation | Create |
|---|---|
| Cross-module decision, possibly reversible | DEC-NNN in `decisions.md` |
| Long proposal (>1 page) needing formal review | RFC-NNN in `rfcs/` |
| Identified risk | Row in `risks.md` |
| Non-obvious implementation choice made by agent | Entry in `ADL/` (via `/adl-ops`) |
| Task, bug, backlog item, incident | GitHub Issue (via `python -m tracking`) |

## When NOT to create

- Informal discussion, "try this" notes, raw brainstorm — use the PR/thread.
- Implementation details of an already-decided feature — code + comments.
- Trivial within-module decision (variable naming, small lib choice).
