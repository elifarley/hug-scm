# PR-C Design Spec — uniform pathspec contract, final rung: the w-* family, `llu`, `sh`

Issue: elifarley/hug-scm#292 (umbrella PRD + ratified contract)
Umbrella spec: `docs/superpowers/specs/2026-08-16-uniform-pathspec-contract-for-all-path-accepting-hug-commands-design.md`
PR-B spec (the immediately prior rung; this document is a DELTA against it):
`docs/superpowers/specs/2026-08-17-uniform-pathspec-contract-pr-b-design.md`
Office-hours design record (ratified D1–D5): `docs/designs/prc-uniform-pathspec-final-rung.md`
Date: 2026-08-19

## 0. What carries over unchanged (delta baseline)

Everything the umbrella spec and PR-B ratified applies verbatim; this
document does not restate it:

- The `-- <path>...` contract: flags before `--`, data after; exactly-one
  `--` per layer; option-named pathspecs are data; positionals-as-pathspecs
  (git parity); loud `-*` rejection exit 2 with the family error template;
  trailing bare `--` inert on listings / picker on interactive actions;
  summary suppressed iff the pathspec array is non-empty.
- The PR-B toolchain: `parse_common_flags_with_pathspecs`,
  `validate_pathspecs_or_die`, `drain_pathspecs_after_separator`,
  `pathspec_pathspecs_into`, `forward_pathspecs_to_picker`, the
  `_HUG_CLI_FLAGS_LOADED` guard, and the conformance-suite roster/sentinel
  machinery (`tests/unit/test_pathspec_conformance.bats`).
- Exit codes: usage errors = 2 (`error_usage`), including unknown
  dash-tokens, malformed magic pathspecs, mutual exclusion, and (new in
  PR-C) known-flag-spelled-after-`--`.
- `reject_action_flags` does NOT transfer to PR-C targets: every PR-C
  command is an action or a log-viewer, not a stateless listing; `-f`,
  `--dry-run`, `-y` are their contract.

## 1. Scope (ratified in office hours, D1 + D2)

PR-C is the LAST rung. After it, the `:pathspec` article's support matrix
has zero `not yet` rows and #292 closes.

Family breadth beyond the umbrella §8 roster (`w-discard`/`w-purge`/
`w-zap`/`w-get`) was ratified in-session: the whole working-directory
family plus `llu` and `sh`. Parked issues #301–#304 are explicitly OUT.

## 2. Class taxonomy and per-class contract

### Class 1 — scoped destructives: FULL pathspec scoping
`w-discard`, `w-purge`, `w-zap`, `w-wipe` (+ the `w` gateway, pending OQ-3)

Target semantics (each pinned two-sided by conformance rows):

- `-- <path>...` is the SCOPE of destruction (narrowing only, §3.1: a scope
  never widens what the unscoped command would touch).
- Bare pre-`--` positionals remain accepted and mean the same as after `--`
  (compat rule; `hug w wipe file.js` ≡ `hug w wipe -- file.js`).
- `validate_pathspecs_or_die` at command entry, before ANY preview,
  confirmation, or mutation: malformed magic → exit 2, nothing touched.
- Unknown dash-tokens before `--` → exit 2 family template (kills the
  probed silent path-typo on `w-discard`/`w-wipe`/`w-purge`).
- A token after `--` that SPELLS a known flag of the command (e.g.
  `--dry-run`) → exit 2 loud ("flags must precede '--'"), never a path.
  NEVER honored as a flag post-separator: probed today,
  `w zap -- src/ --dry-run` silently SKIPS the dry-run preview.
- Preview (dry-run), confirmation list, and the destructive git call all
  flow through the ONE validated pathspec set — what was previewed is
  provably what is destroyed.
- Category flags intersect the scope: `w-discard -s -- src/` = staged
  changes under src/ only; `w-purge -i -- build/` = ignored files under
  build/ only. (Spike note: `w-purge -i -- src/` today errors on tracked
  paths — the plan pins the exact category×scope matrix per command.)
- Scoped invocation suppresses the trailing `hug s` summary (same rule as
  sl*/us: a scoped answer is the answer).
- Trailing bare `--` on an interactive destructive = picker (same as `a`):
  OQ-1 pins per command; commands whose interactive flow is confirm-only
  (not a picker) treat it as inert.

### Class 2a — whole-tree variants: parsing hygiene only
`w-discard-all`, `w-purge-all`, `w-zap-all`, `w-wipe-all`

No scope by definition (the documented whole-tree escape hatch, like `aa`
vs `a`). They gain: loud unknown dash-tokens (exit 2), position-
independent custom flags, and the post-`--` known-flag rejection. Paths
after `--` are rejected loudly ("whole-tree command; use the non-all form
to scope") rather than silently ignored.

### Class 2b — wip workflow: parsing convergence only
`w-wip`, `w-unwip`, `w-wipdel`

Branch-workflow commands; no pathspec meaning exists to give them. They
gain: position-independent custom flags (`--stay`, `--no-squash`, `-f`)
and loud unknown dash-tokens. Spike note: `w-wipdel` already rejects
`-xX` loudly but exits 1 — normalize to the family exit 2 + template.
Their action flags stay (no `reject_action_flags`).

### Class 3 — log viewers gain pathspec features (umbrella user stories 16–17)

- `hug llu -- src/`: outgoing commits touching src/. The outgoing RANGE
  computation is unchanged; separator + pathspecs append to the log
  invocation. Malformed magic → exit 2; unknown dash-token → exit 2
  (today: `llu -- src/` → "Unknown option: --" exit 1 — no separator
  support at all).
- `hug sh <ref> -- src/a.py`: commit details filtered to the path,
  matching `shc`/`shcp`/`shp` (probed today: `sh` rejects any second
  positional with "accepts one commit reference; unexpected"). The ref
  stays a ref; everything after `--` is pathspecs. Both become picker-less
  inert-`--` commands (listings, not actions): summary/behavior parity
  with `l`/`ll` inert rows.

### `w-get`
Partially migrated in PR-A (pathspec machinery exists). Finish to the full
contract: entry validation, post-`--` known-flag rejection, scoped summary
gate. Its `-u`/`--upstream`, `-f`, `--dry-run` stay action flags.

## 3. Probed today-behavior (spike receipts, 2026-08-19 scratch repo)

The plan's red-first rows come from these:

| Probe | Today | PR-C target |
|---|---|---|
| `w wipe root.txt` | confirm-prompt (cancelled non-TTY), exit 1 | unchanged (bare positional compat) |
| `w wipe -xX` / `w discard -xX` | silent "Nothing to discard … from the specified paths", exit 0 | exit 2 Unknown option |
| `w discard -- ':(exclude)build/' --dry-run` | "Nothing to discard" exit 0 — magic flow-through broken/unpinned while an unstaged change exists outside build/ | exclude-scoped dry-run lists the change; malformed magic exit 2 |
| `w zap -- src/ --dry-run` | dry-run NOT honored (confirm path; real destruction risk) | exit 2: flag after '--' |
| `w zap src/ --dry-run` | works (flag-after-path already tolerated) | still works (flags position-independent, before `--`) |
| `w purge -i -- src/` | error "path 'src/a.py' is tracked or has staged change" | category×scope matrix pinned per command |
| `w wipdel -xX` | loud, exit 1 | loud, exit 2 + family template |
| `llu -- src/` | "Unknown option: --" exit 1 | scoped outgoing list, exit 0 |
| `sh HEAD -- src/` / `sh HEAD src/a.py` | "accepts one commit reference; unexpected …" exit 1 | ref + scoped details / bare positional = pathspec |

## 4. Error & Rescue Registry (PR-C rows)

| Situation | Git behavior | Exit | User sees |
|---|---|---|---|
| Malformed magic on any PR-C command | git fatal (stderr, unsuppressed) | 2 | `Invalid pathspec: '…'. See 'hug help :pathspec'.` |
| Unknown dash-token pre-`--` | n/a (hug-owned) | 2 | family Unknown-option template |
| Known flag spelled after `--` | n/a (hug-owned) | 2 | `Flags must precede '--': hug w zap --dry-run -- src/. See 'hug help :pathspec'.` |
| Pathspec after `--` on a Class 2a `-all` command | n/a (hug-owned) | 2 | whole-tree pointer to the scoped form |
| Scope matches nothing on a destructive | n/a (hug-owned) | 0 | `No files matching '<specs>' to <verb>.` (info; nothing touched) |
| `sh` given a second non-path positional | n/a (hug-owned) | 2 | one-commit-reference error (existing, normalized exit) |

## 5. Testing strategy

- Conformance suite expansion: new rosters
  `PATHSPEC_W_DESTRUCTIVE_ROWS`, `PATHSPEC_W_ALL_ROWS`, `PATHSPEC_WIP_ROWS`,
  `PATHSPEC_LOG_VIEWER_ROWS=(llu sh)` — sentinel arms on every loop
  (unknown row fails loudly), two-sided assertions with raw-git oracles.
- Every spike receipt in §3 becomes a red-first row before its migration
  lands (the PR-B discipline: probe red, pin, migrate, green).
- Mutating tests use the selecting-stub-gum (GUM_PICK) fixture; non-TTY
  confirm-cancel behavior stays pinned where it is today's contract.
- The category×scope matrix (Class 1) gets a dedicated probe-then-pin
  table in the PLAN (not resolved by this spec — see OQ-2).

## 6. Documentation (same-PR claim-flip discipline)

- `:pathspec` article: support matrix loses every `not yet` row; w-*/llu/sh
  sections with worked examples; migration notes for the exit-code flips
  (silent-accept → exit 2; wipdel 1 → 2; `--`-flag-as-path → exit 2).
- README command reference: `sh`/`llu` pathspec rows (umbrella items 16–17).
- `docs/commands/working-directory.md` (or the w-family page per
  `docs/DOCS_ORGANIZATION.md`): scoped-destruction examples + the
  narrowing-only safety property.
- CHANGELOG: script-migration section for the observable flips.

## 7. Open questions routed to the PLAN (probe-first, not guessed here)

- **OQ-1** trailing bare `--` per Class 1 command: picker vs inert — decide
  by each command's existing interactive flow (picker exists → picker).
- **OQ-2** category×scope matrix: exact interplay of `-u/-s` (discard),
  `-u/-i` (purge), `--browse-root`, and pathspec scope — pin per command
  with probes before migration; the spike's `purge -i -- src/` tracked-path
  error is the first cell.
- **OQ-3** `w` gateway: pass-through only (subcommands own the contract
  surface) — presumed yes, verified by probing `hug w discard -- src/`
  end-to-end through the gateway.

## 8. Out of scope (parked, separate PRs)

elifarley/hug-scm#301 (roast-minor polish), #302 (LOW batch), #303
(us-extraction + sl* templating — the post-ladder cleanup), #304 (nullsafe
sweep). The `hg-config/` Mercurial parallel (per ADR-002, follows Git).
