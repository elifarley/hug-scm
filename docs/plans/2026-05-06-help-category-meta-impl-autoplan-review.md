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

## Phase 3 — Eng Review (post-revision)

User accepted **B-tweaked**; plan now has 15 tasks (T0, T0.5, T1-T13). Eng
review focuses on the revised architecture.

### Step 0 — Scope challenge (against revised plan)

Reading the revised plan against existing code: the change is structurally
smaller than the original. `CommandInfo.keywords: list[str]` is parsed in
`_query_script`; no separate hydration step needed (drops one function,
`hydrate_category_fields` keeps only the `category_desc` join). One fewer
field in `CategoryMeta`. Validation simpler (no `>= 3 keywords` check).
Net: **fewer LOC** than the original plan, despite adding T0.5.

### Section 1 — Architecture (ASCII dependency graph)

```
git-hughelp (bash, thin)
  │
  └─ exec uv run help_search.py
       │
       ├─ category_meta.py
       │     ├─ load_categories()        ──> reads categories/*.toml
       │     │                               (label, description only)
       │     └─ validate_against_scripts() (strict; missing manifest = exit 1)
       │
       └─ help_search.py
             ├─ collect_metadata()       ──> queries each git-* via --search-meta
             │     └─ _query_script()    ──> parses category=[..] AND keywords=[..]
             │     └─ hydrate_category_fields() (joins category_desc only)
             │
             ├─ MatchSpec / run_search   ──> generic field-by-field scorer
             │
             ├─ KEYWORD_SPECS (5 specs)  ──> name=, name~, desc, @cat-desc, keywords
             ├─ INTENT_SPECS  (3 specs)  ──> desc, @cat-desc, keywords (token_set)
             │
             ├─ diversify()              ──> top-N + per-category soft cap
             │
             └─ format_*()               ──> @ listing / @<cat> page (boxed)
                                             /<query>, !<query> with --explain
```

Coupling: low. `category_meta.py` knows nothing about `help_search.py`.
`help_search.py` consumes `CategoryMeta` as data. Bash dispatcher untouched
beyond the tip-line edit.

### Section 2 — Code Quality

- **DRY**: `MatchSpec.run_search` consolidates the previously ad-hoc
  `search_keyword`/`search_category` loops. The new `_query_script` extension
  parses two TOML keys with one regex pattern — no duplication.
- **Naming**: `KEYWORD_SPECS` / `INTENT_SPECS` are explicit. `_hug_keywords`
  follows the existing `_hug_category` convention. No surprises.
- **Complexity**: `diversify()` is the highest-complexity new function (~15
  lines, one loop with a counter dict). Cyclomatic ≤ 4. Acceptable.

### Section 3 — Test Review (NEVER SKIP)

| Path / behavior | Type | Coverage |
|---|---|---|
| `derive_summary` truncation | Unit (test_category_meta) | ✅ T1 |
| TOML loader schema (label, description required) | Unit | ✅ T1 |
| TOML loader: missing manifest → ValueError | Unit | ✅ T1 |
| `validate_against_scripts` flags missing manifest | Unit | ✅ T1 |
| `_query_script` parses `keywords = [..]` | Unit (test_help_search, NEW) | ⚠️ **GAP — add explicit unit test in T3** |
| `_query_script` handles missing `keywords` line gracefully | Unit | ⚠️ **GAP — add in T3** |
| `MatchSpec.run_search` weight + threshold + label | Unit | ✅ T2 |
| `KEYWORD_SPECS` per-command keyword match | Unit | ✅ T3 |
| F3 regression: `/save` does NOT match `wipdel` | Unit (corpus) | ✅ T11 (added in revision) |
| `INTENT_SPECS` token-aware (word order) | Unit | ✅ T4 |
| `diversify()` cap, soft-cap, penalty | Unit | ✅ T5 |
| `--explain` annotation correctness | Unit | ✅ T6 |
| `format_category_list` summary column | Unit | ✅ T7 |
| `format_category_page` boxed + stream split | Unit | ✅ T8 |
| Runtime validation exit 1 on missing manifest | Unit (subprocess test) | ✅ T10 |
| Cache invalidation when categories/*.toml newer | Unit | ✅ T10 |
| `thefuzz` fallback path (substring-only) | **Unit** | ❌ **GAP — Claude subagent flagged; add to T2 or T3** |
| `hug help @<cat>` boxed page reaches stderr | BATS | ✅ T12 |
| `hug help @<cat> | grep` pipe-safe | BATS | ✅ T12 |
| `hug help !save my work` finds wip | BATS | ✅ T12 |
| `--explain` BATS | BATS | ✅ T12 |
| `--all` disables cap | BATS | ✅ T12 |
| Validation failure exit 1 | BATS smoke | ✅ T12 |

**3 test gaps to add to the plan** (non-blocking — engineers can patch in T3
and T2 as needed):

1. T3 unit test: `_query_script` parses both `category` and `keywords` lines
   when both present.
2. T3 unit test: `_query_script` returns empty `keywords` list when only
   `category` line is emitted (graceful for un-bootstrapped commands).
3. T2 or T3 unit test: with `thefuzz` mocked unavailable, the fallback
   substring-only scorer still returns predictable binary scores. Test the
   fallback branch explicitly.

### Section 4 — Performance

- `collect_metadata` runs ~100 subprocess calls per cold cache; warm cache
  is O(1). Already addressed (existing behavior).
- `run_search` is O(n_commands × n_specs) — for 100 commands × 5 specs = 500
  ops per query. Negligible.
- `diversify` is O(n_results × log n_results) for the post-penalty sort.
  Negligible.
- TOML parse is O(19 files × 1 KB) — < 5ms cold, cached after.

No performance concerns.

### Section 5 — Security

- No new attack surface. `_hug_keywords` is parsed via regex
  (`re.search(r'keywords\s*=\s*\[(.*?)\]')`), not `eval`/`exec`. No shell
  injection vector.
- TOML loaded via stdlib `tomllib` — battle-tested.
- Strict validation on category manifests prevents typos from silently
  becoming queryable categories.

### Eng Phase Completion Summary

| Section | Status |
|---|---|
| 0 Scope challenge | ✅ Plan structurally smaller post-revision |
| 1 Architecture (ASCII graph) | ✅ Above |
| 2 Code quality | ✅ DRY/naming/complexity all green |
| 3 Test review | ⚠️ 3 gaps identified — engineers add inline |
| 4 Performance | ✅ Negligible cost |
| 5 Security | ✅ No new attack surface |

---

## Phase 3.5 — DX Review (post-revision)

`hug` is a developer CLI. Users are intermediate-to-advanced devs using hug
for daily VCS work (the primary persona is the hug-scm author + small team).

### Developer Journey Map

| Stage | What dev does | Friction |
|---|---|---|
| Discover | Types `hug help` | Sees command-group list + topic-search hints |
| Browse categories | Types `hug help @` | Sees catalog with one-line summaries (NEW) |
| Drill into category | Types `hug help @branching` | Sees boxed page with description + commands (NEW) |
| Search by word | Types `hug help /branch` | Top-10 results, precise keyword matches |
| Search by intent | Types `hug help !save my work` | Finds `wip` via per-command keyword (NEW) |
| Debug a result | Adds `--explain` | Sees match-source annotation |
| Inspect a single command | Types `hug help <command>` | Existing path, unchanged |

### TTHW (Time To Hello World)

- Cold start: zero install — ships with hug. < 5 seconds from "I want to find
  the right command" to "I see candidates."
- Onboarding for a new contributor adding a script: needs to know to add
  `_hug_category` and (optionally) `_hug_keywords`. The latter is undocumented
  beyond example scripts. **GAP** — add a one-paragraph mention in
  `git-config/bin/CLAUDE.md` so future contributors discover the convention.

### Error Message Quality (problem + cause + fix)

| Error | Surface | Quality |
|---|---|---|
| Missing TOML for declared category | stderr + exit 1 | ✅ "category 'flubber' is referenced by a script but has no manifest at categories/flubber.toml" — names problem, cause, fix path |
| Bad TOML schema | ValueError stack trace | ⚠️ Default Python traceback is noisy. **GAP** — consider catching at `main()` boundary and printing a shorter `error: <path>: <reason>` line. Plan-level only — easy follow-up. |
| Empty `_hug_keywords` | Silent (graceful) | ✅ Intentional |

### API/CLI Naming

| Name | Guessable? | Consistency |
|---|---|---|
| `hug help @` | ✅ — sigil already in use | Matches `/`, `!` |
| `hug help @<cat>` | ✅ | Matches existing pattern |
| `--all` | ✅ — universal flag idiom | Matches other CLIs |
| `--explain` | ✅ — common debug pattern | Matches `git diff --explain`, `pip --explain` |
| `--categories-dir` | ⚠️ — testing/path override; only documented in `--help` | Acceptable for advanced flag |
| `_hug_keywords=` (per-script) | ⚠️ — discoverable only by reading existing scripts | Mitigated by adding to CLAUDE.md (see TTHW gap above) |

### Documentation

- `git-config/CLAUDE.md` mentions `--search-meta` as an existing convention.
  **GAP** — extend it to document `_hug_keywords` so contributors know to set
  it on new commands.
- The 19 category TOMLs serve as documentation for what each category covers.
- Plan does not require user-facing release notes; the change is internal.

### Upgrade Path

- Existing `--search-meta` scripts work without `_hug_keywords` —
  graceful fallback to description-only scoring.
- Users running `hug help` after the upgrade see the new boxed pages
  immediately; no opt-in.
- Cache mtime detection handles category TOML updates automatically.
- `--explain` is opt-in (off by default).

### DX Scorecard

| Dimension | Score | Notes |
|---|---|---|
| 1. Getting started < 5 min | 9/10 | Zero install; one command to discover |
| 2. CLI naming guessable | 9/10 | Sigil + flag conventions consistent |
| 3. Error messages actionable | 7/10 | Missing-manifest excellent; TOML schema errors raw — fix at follow-up |
| 4. Docs findable & complete | 7/10 | TTHW gap for `_hug_keywords` convention; non-blocking |
| 5. Upgrade path safe | 10/10 | Fully graceful; no breaking change |
| 6. Dev environment friction-free | 9/10 | `make test-lib-py` already covers; uv handles venv |
| 7. Escape hatches present | 9/10 | `--all`, `--categories-dir`, `--explain`, `HUG_HELP_EXPLAIN` env-var |
| 8. Internal consistency | 9/10 | Per-command keywords mirror per-command categories — same shape |
| **Overall** | **8.6/10** | Strong DX; 2 small gaps to patch in follow-up |

### DX Phase Completion Summary

- TTHW: < 5 sec for end users; ~2 min for new-script contributors (after CLAUDE.md gap is patched).
- Two small gaps captured (test-plan inline; not blockers).
- One nice-to-have (better TOML schema error message) deferred to TODOS.md.

---

## Phase 4 — Final Approval Gate

(Below.)

---

## Decision Audit Trail

| # | Phase | Decision | Class | Principle | Rationale |
|---|---|---|---|---|---|
| 1 | Phase 0 | UI scope: NO (terminal text not graphical) | Mechanical | P3 (pragmatic) | Plan-design-review skill is for graphical UIs; reading the plan, only `layout`/`header` matches and they're CLI-text contexts |
| 2 | Phase 0 | DX scope: YES | Mechanical | P3 | `hug` is a developer CLI; plan adds flags + error messages; many DX terms in plan |
| 3 | Phase 1 | Run dual voices first before sections 1-10 | Mechanical | P6 (action) | Voices may surface section-level concerns; defer per-section work until consensus is built |
| 4 | Phase 1 | Compress sections 1-10 into Failure Modes + Alternatives tables | Mechanical | P3, P5 | Voices already produced cross-section findings; per-section repetition would be redundant on a 1900-line plan; tables capture severity and concrete fixes |
| 5 | Phase 1 | Surface dual-voice findings as USER CHALLENGE at premise gate (not Phase 4) | Mechanical | P6 (action) | Findings affect P3-P5 directly; deferring to Phase 4 wastes Phase 3/3.5 work if user revises scope |
