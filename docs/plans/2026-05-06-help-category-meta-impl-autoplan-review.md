# /autoplan Review Report — Help Category Metadata Plan

**Date**: 2026-05-06
**Plan reviewed**: `docs/plans/2026-05-06-help-category-meta-impl.md` (commit `f24562a`)
**Design doc**: `docs/plans/2026-05-06-help-category-meta-design.md` (commit `52d44e7`)
**Mode**: SELECTIVE EXPANSION
**Status**: AT PREMISE GATE — awaiting user decision

---

## Phase 1 — CEO Review

### CEO Dual-Voice Consensus Table

| # | Dimension | Claude subagent | Codex | Consensus |
|---|---|---|---|---|
| 1 | Premises valid? | Mostly assumed, untested | Assumed without evidence | **DISAGREE with plan** |
| 2 | Right problem to solve? | No — first-contact discovery is the real gap | No — no evidence the problem is real | **DISAGREE — reframe** |
| 3 | Scope calibration correct? | Over-scoped for unproven gain | Too much ceremony for uneven categories | **CONFIRMED concern** |
| 4 | Alternatives sufficiently explored? | No — per-script keywords, drop !intent, synonym map skipped | No — many real alternatives skipped | **CONFIRMED gap** |
| 5 | Competitive/market risks covered? | No — AI assistants obsoleting static help; MCP is future | No — MCP/agent manifests are the 10x reframe | **CONFIRMED gap** |
| 6 | 6-month trajectory sound? | TOML rot, vague categories, no keyword-quality enforcement | TOML rot, vague buckets, hand-tuned weights | **CONFIRMED risk** |

### Cross-Voice Convergence (high-confidence findings)

Both voices independently arrived at the same recommendations:

1. **Per-command metadata > per-category metadata** — category keywords are blunt; adding `save` to `parking` makes every parking command inherit the match (including destructive ones like unpark/wipdel). Per-command keywords would be precise.
2. **Drop or merge `!intent` and `/keyword`** — both are lexical fuzzy matchers; the distinction misleads users into expecting semantic understanding without delivering it.
3. **MCP-shaped manifest is the right north-star schema** — name, aliases, args, safety level, mutates yes/no, examples, failure modes, VCS support, category. Generates human help + completion + search index + agent-facing tool descriptions from one source. The current TOML schema (label/description/keywords) is incompatible with this direction.
4. **Evidence before tuning** — golden query corpus should come from real workflows / user logs, not author intuition. The plan's T11 corpus is author-written and bakes in the same blind spots the scoring model has.

### Failure Modes Registry

| # | Failure | Severity | Source | Mitigation in plan? |
|---|---|---|---|---|
| F1 | TOML files rot (categories accumulate vague catch-all keywords like `utility`, `helper`, `misc`) | High | Both | ❌ No CI check on keyword quality |
| F2 | `utilities.toml` and `garbage.toml` already are vague catch-alls (only 1-2 commands each) | Medium | Codex | ❌ Not addressed |
| F3 | Category-level keywords pollute precise commands (e.g. `save` matches `unpark` + `wipdel` + `wip`) | High | Codex | ❌ Direct architectural consequence |
| F4 | `thefuzz` fallback (substring-only) silently degrades scoring; no test covers the absent path | Medium | Claude | ❌ Test gap |
| F5 | `token_set_ratio` at threshold 75 false-positives on short multi-word queries | Medium | Claude | ❌ Not tested |
| F6 | `--explain` becomes a maintainer-only debug UI exposed to users; surfaces internal jargon | Low | Codex | ⚠️ Could be an env-var-gated dev mode |
| F7 | Hand-tuned scorer weights with no rationale; future contributor can't justify changes | Medium | Codex | ⚠️ T11 corpus partially mitigates |
| F8 | Top-10 cap + diversification hides valid niche results without surfacing the cut | Low | Codex | ⚠️ Overflow note partially mitigates |
| F9 | Two sigils for one lexical engine creates user confusion and maintenance burden | Medium | Both | ❌ Architectural |
| F10 | Plan locks in a schema (label/description/keywords) incompatible with MCP/agent-manifest direction | High | Both | ❌ Not addressed |

### Error & Rescue Registry

| Error path | User sees | Rescue |
|---|---|---|
| Script declares unmanifested category | `error: category 'X' is referenced by a script but has no manifest` + exit 1 | Plan: strict, blocks `hug help @*` until fixed. Sufficient. |
| TOML manifest malformed | `ValueError` from loader | Plan: pytest catches in CI. Runtime path also fails fast. Sufficient. |
| Cache invalidation bug | Stale results | Plan: mtime-tracked. Sufficient. |
| User runs `hug help /short-query` and gets unrelated results | No error, just bad UX | Plan: per-spec thresholds + corpus regression. **Partial** — corpus is author-written. |

### Implementation Alternatives Table

| Alt | What it is | Effort | Risk | Pros | Cons |
|---|---|---|---|---|---|
| A | **Plan as written** (per-category TOML + MatchSpec) | Baseline (~14 commits) | Medium | User-chosen; matches existing `--search-meta` shape | TOML rot; per-category granularity blunt; locks out MCP |
| B | **Per-command metadata** (extend `--search-meta` with `keywords = [...]` per script) | -1 day | Low | No staleness (each script owns its words); fits existing protocol; precise | Slightly more authoring per command |
| C | **Drop `!intent`, expand `/keyword`** with a small synonym map (10-line dict) | -2 days | Low | Eliminates user confusion; fewer modes to maintain; covers the `save → wip` case | Loses the "phrase search" promise |
| D | **MCP-shaped manifest** as the single source of truth (one file or per-command), generate help + completion + search + tool descriptions | +2 days | Medium | Future-proof for AI agents; one schema; structured | More upfront design; bigger rewrite |
| E | **Pause & gather evidence** (instrument `hug help` to log queries, ship telemetry, return after 4 weeks of data) | -3 days, +4 weeks | Low | Empirical foundation; corpus from real workflows | Delays delivery; needs telemetry infra |

### Dream State Delta

- **CURRENT**: noisy `/keyword`, `!intent` is alias of `/`, bare `@` listing, no per-category metadata.
- **THIS PLAN**: precise scoring, distinct `!intent`, rich `@<cat>` page, validation, caps, `--explain`.
- **12-MONTH IDEAL**: MCP-shaped tool manifest emitting human help + agent tool definitions; semantic embedding-based search; evidence-driven keyword tuning; per-command metadata.
- **DELTA**: Plan reaches ~50% of ideal. Both voices argue the missing 50% (per-command metadata + MCP shape + evidence) should drive the schema decisions in *this* plan, not be deferred.

### Scope Decisions

**In scope (held)**: per-category TOML manifests, MatchSpec model, top-N + diversification, `--explain` flag, `!intent` token-aware mode, validation hooks, cache extension, regression corpus, BATS extension.

**Out of scope (deferred to TODOS.md)**:
- Per-command keywords / examples / aliases
- MCP/agent manifest output mode (`hug help --mcp-manifest`)
- Embedding-based semantic search
- Telemetry on `hug help` usage
- Decision-tree command (`hug choose "..."`)
- Shell completion driven by category names

### Premise Restatement (with dual-voice critique)

| # | Premise | Plan position | Dual-voice critique |
|---|---|---|---|
| P1 | Users use `hug help` for command discovery | ✅ Stated | ❓ No usage evidence; could be that 95%+ of users go via README/AI assistant |
| P2 | Current search results are noisy enough to warrant fixing | ✅ Stated (user observation) | ✅ Confirmed by reading `partial_ratio` use; risk is whether fix is right |
| P3 | Curated keywords > fuzzy description matching | ✅ Stated | ❌ Both voices: only true if keywords reflect observed user language, not author intuition |
| P4 | `!intent` token-aware is meaningfully different from `/keyword` partial | ✅ Stated | ❌ Both voices: still lexical, just different failure modes — misleads user expectation |
| P5 | One TOML per category is the right granularity | ✅ Stated (user-chosen) | ❌ Both voices: per-command would be more precise and avoids staleness |
| P6 | 14 bite-sized commits is the right execution shape | ✅ Stated | ⚠️ Could compress to 5-7; not load-bearing for the architecture decision |

### CEO Completion Summary

| Section | Status | Notes |
|---|---|---|
| 0A Premise challenge | ✅ Done | 6 premises catalogued; 4 challenged by dual voices |
| 0B Existing-code leverage | ✅ Done | High reuse; 600 LOC net new |
| 0C Dream state | ✅ Done | Plan covers ~50% of ideal |
| 0C-bis Alternatives | ✅ Done | 5 alternatives surfaced (A-E) |
| 0D Mode-specific (SELECTIVE EXPANSION) | ✅ Done | Hold scope; cherry-pick `--all`/`--explain`/cap |
| 0E Temporal interrogation | ✅ Done | HOUR 1 → 24 mapped |
| 0F Mode confirmation | ⚠️ Held by user | Both voices argue for SCOPE REDUCTION |
| Step 0.5 Dual voices | ✅ Done | Both voices converge on per-command + MCP + evidence |
| Sections 1-10 | ⚠️ Compressed | Findings absorbed into Failure Modes / Alternatives tables; full per-section repetition would be redundant given the structural concerns surfaced by dual voices |
| Premise gate | ⏳ **Awaiting user** | Single non-auto-decided AUQ |

---

## Phase 2 — SKIPPED

No graphical UI scope detected. Plan formats terminal text only.

---

## Phase 3 — Eng Review

⏳ Pending premise gate decision. If user proceeds with plan as-written, will run with focus on Section 3 (Test Review) and Section 1 (Architecture).

---

## Phase 3.5 — DX Review

⏳ Pending premise gate decision. If user proceeds, will run focused on TTHW for `hug help` discovery, error message quality (validation failures), and `--explain` UX.

---

## Phase 4 — Final Approval Gate

⏳ Pending.

---

## Decision Audit Trail

| # | Phase | Decision | Class | Principle | Rationale |
|---|---|---|---|---|---|
| 1 | Phase 0 | UI scope: NO (terminal text not graphical) | Mechanical | P3 (pragmatic) | Plan-design-review skill is for graphical UIs; reading the plan, only `layout`/`header` matches and they're CLI-text contexts |
| 2 | Phase 0 | DX scope: YES | Mechanical | P3 | `hug` is a developer CLI; plan adds flags + error messages; many DX terms in plan |
| 3 | Phase 1 | Run dual voices first before sections 1-10 | Mechanical | P6 (action) | Voices may surface section-level concerns; defer per-section work until consensus is built |
| 4 | Phase 1 | Compress sections 1-10 into Failure Modes + Alternatives tables | Mechanical | P3, P5 | Voices already produced cross-section findings; per-section repetition would be redundant on a 1900-line plan; tables capture severity and concrete fixes |
| 5 | Phase 1 | Surface dual-voice findings as USER CHALLENGE at premise gate (not Phase 4) | Mechanical | P6 (action) | Findings affect P3-P5 directly; deferring to Phase 4 wastes Phase 3/3.5 work if user revises scope |
