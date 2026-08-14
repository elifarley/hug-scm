# Codebase Hardening Action Plan

**Date:** 2026-03-06  
**Derived from:** `docs/planning/2026-03-06-whole-codebase-code-roast.md`

---

## Goal

Reduce the largest long-term maintenance and safety risks in Hug SCM without destabilizing the CLI surface.

## Planning Principles

- Prioritize risk-reduction over broad rewrites.
- Prefer compatibility-preserving refactors.
- Add contract tests before or alongside architectural cleanup.
- Treat destructive-command safety and backend parity as release-critical.

---

## Ranked Action Plan

### Priority 0: Establish safety and parity baselines

**Why first:** Before refactoring, the project needs a reliable way to detect regressions.

**Deliverables:**
- Contract test matrix for `--force`, confirmations, `--dry-run`, stderr, and exit codes
- Test fixtures for path edge cases (spaces, leading `-`, glob chars)
- Shared acceptance tests for Git and Mercurial command parity where semantics should match

**Success criteria:** High-risk behavior is encoded in tests and can gate future changes.

### Priority 1: Centralize destructive-operation execution

**Why second:** This is the highest safety payoff per unit of engineering effort.

**Deliverables:**
- One reusable destructive-operation executor in the shared library layer
- Standard API for action label, confirmation token, dry-run preview, and final execution
- Migration of the most dangerous command families first (`w*`, `h*`, and Hg equivalents)

**Success criteria:** Destructive commands no longer implement confirmation and dry-run logic ad hoc.

### Priority 2: Decompose ambient libraries into capability modules

**Why third:** Hidden coupling is the main source of regression radius and poor testability.

**Deliverables:**
- Inventory of functions currently exposed by `hug-common` and `hug-git-kit`
- Module boundaries for repo state, file selection, branch logic, discard logic, upstream logic, and rendering
- Compatibility shims where needed to avoid breaking commands during migration

**Success criteria:** New and existing commands depend on smaller, explicit capability modules with documented contracts.

### Priority 3: Introduce a single command manifest

**Why now:** Once tests and safety patterns are in place, the next major win is reducing drift across implementation and docs.

**Deliverables:**
- Declarative command inventory with command name, backend support, summary, and safety classification
- Validation or generation for alias/config surfaces and command-reference inventories
- Drift check in CI or local quality validation

**Success criteria:** It becomes difficult to add or change a command without updating the canonical inventory.

### Priority 4: Harden Bash↔Python interfaces

**Why now:** The cross-language seam is a correctness risk and a blocker for future incremental migration.

**Deliverables:**
- Stable machine-readable interface contracts for Python helpers
- Boundary tests from Bash callers through rendered output
- Clear failure handling for missing Python, bad helper output, or version mismatch

**Success criteria:** Python helper changes fail loudly and predictably instead of breaking downstream shell code silently.

### Priority 5: Define platform support and portability strategy

**Why now:** The project needs a principled answer for GNU-specific assumptions.

**Deliverables:**
- Explicit policy: supported platforms and required toolchain expectations
- Fast-fail diagnostics for unsupported environments
- Portable replacements where the current behavior is unnecessarily fragile

**Success criteria:** Users and contributors know what is supported, and platform failures happen early with clear guidance.

### Priority 6: Reduce Git/Hg semantic drift systematically

**Why last:** This is strategically important, but it depends on stronger tests and a canonical manifest.

**Deliverables:**
- Backend capability matrix describing where behavior must match and where divergence is intentional
- Shared acceptance suite across both backends
- Documentation of intentional differences

**Success criteria:** Git/Hg divergence is explicit, tested, and reviewable instead of accidental.

---

## Suggested Execution Sequence

### Phase 1: Guardrails
1. Add contract tests for safety behavior and path edge cases.
2. Add initial Git/Hg parity tests for a small command slice.
3. Identify the destructive commands with the highest blast radius.

### Phase 2: Safety refactor
1. Build the central destructive-operation executor.
2. Migrate high-risk working-directory and HEAD commands.
3. Verify no behavior regressions through the new contract suite.

### Phase 3: Architectural cleanup
1. Decompose `hug-common` and `hug-git-kit` incrementally.
2. Introduce the command manifest.
3. Add validation for manifest drift.

### Phase 4: Cross-language and platform hardening
1. Freeze Bash↔Python contracts.
2. Clarify platform support and prerequisites.
3. Expand parity tests across both VCS backends.

---

## Near-Term Milestones

- **Milestone A:** Safety contract suite exists and covers destructive semantics.
- **Milestone B:** Top destructive command families use the centralized executor.
- **Milestone C:** At least one large ambient library has been split without user-visible regression.
- **Milestone D:** Command inventory is canonical and validated.

---

## Recommendation

If only one workstream can begin now, start with **Priority 0 + Priority 1 together**: encode current safety behavior in tests, then centralize destructive execution. That pairing delivers the fastest risk reduction while creating a safer foundation for broader refactors.

