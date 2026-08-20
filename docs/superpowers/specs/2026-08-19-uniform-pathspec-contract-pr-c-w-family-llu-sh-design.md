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

### Class 0 — the `w` gateway: enumerated arms, one is a live bug

The gateway is NOT pure pass-through. Arm inventory (git-w):

- `w discard|purge|zap|wipe|...` -> pass-through (contract surface owned by
  the subcommand).
- `w wips` -> NOT pass-through: appends `--stay` AFTER the user's args
  (git-w:73). Probed live: `hug w wips -- "draft"` creates branch
  WIP/....draftSTAY - the injected flag drains into the message and stay
  never applies (silent wrong result today), and post-migration the
  known-flag-after-`--` rejection would exit 2 on a flag HUG injected.
  PR-C fix, pinned red-first: the `wips` arm PREPENDS its flag
  (dispatch_w_subcommand "wip" --stay "$@") so `w wips -- "draft"`
  composes as `wip --stay -- "draft"`.
- unknown subcommand -> prints usage but exits 0 (probed `hug w badcmd`).
  Normalize to exit 2 in the same gateway pass.

OQ-3 is thereby RESOLVED by arm enumeration (was: presumed pass-through;
the prior probe choice `w discard -- src/` could not detect the `wips`
falsifier - roast Critical 1).

### Class 1 — scoped destructives: FULL pathspec scoping
`w-discard`, `w-purge`, `w-zap`, `w-wipe` (via the Class 0 gateway)

Target semantics (each pinned two-sided by conformance rows):

- `-- <path>...` is the SCOPE of destruction (narrowing only, §3.1: a scope
  never widens what the unscoped command would touch).
- Bare pre-`--` positionals remain accepted and mean the same as after `--`
  (compat rule; `hug w wipe file.js` ≡ `hug w wipe -- file.js`).
- `validate_pathspecs_or_die` at command entry, before ANY preview,
  confirmation, or mutation: malformed magic → exit 2, nothing touched.
- Unknown dash-tokens before `--` → exit 2 family template (kills the
  probed silent path-typo on `w-discard`/`w-wipe`/`w-purge`).
- A token after `--` that EXACTLY SPELLS a known flag of the command (e.g.
  `--dry-run`; `./--dry-run` is a filename, not a spelling) → exit 2 loud ("flags must precede '--'"), never a path.
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
to scope"); a BARE trailing `--` is inert (`zap-all --` == `zap-all`,
pinned). Spike note: today `purge-all -- src/` and `zap-all --` both die
`unknown option: --` exit 1 — wrong message and wrong exit; the 2a pass
normalizes both.

### Class 2b — wip workflow: parsing convergence only
`w-wip`, `w-unwip`, `w-wipdel`

Branch-workflow commands; no pathspec meaning exists to give them, and
they already give `--` a DATA meaning the contract must NOT overwrite
(roast Major 2): `w-wip -- "-fix"` makes `-fix` the MESSAGE (probed:
branch WIP/....fix); `w-unwip`/`w-wipdel` take the WIP branch name after
`--`. Disposition, pinned: Class 2b does NOT adopt the pathspec split —
post-`--` tokens stay message/branch data. The actual delta is ONLY exit
discipline: all three already reject unknown dash-tokens loudly at exit 1
(w-wip:90, w-unwip:86, w-wipdel:79, probed) — normalize to exit 2 with
the family template; do not rewrite their compliant loops. Their action
flags stay (no `reject_action_flags`).

### Class 3 — log viewers gain pathspec features (umbrella user stories 16–17)

- `hug llu -- src/`: outgoing commits touching src/. The outgoing RANGE
  computation is unchanged; separator + pathspecs append to the log
  invocation. Malformed magic → exit 2; unknown dash-token → exit 2
  (today: `llu -- src/` → "Unknown option: --" exit 1 — no separator
  support at all).
- `hug sh <ref> -- src/a.py`: commit details filtered to the path,
  matching `shc`/`shcp`/`shp` (probed today: `sh` rejects any second
  positional with "accepts one commit reference; unexpected"). The ref
  stays a ref; everything after `--` is pathspecs. sh's RANGE syntax
  (`sh -3 -- src/`, `-N`/`N` committish spellings) is DATA, not flags —
  the `-*` rejection must not eat it (umbrella §6.1 composition, restated
  here because sh is the one PR-C command whose legal dash-tokens are not
  flags; plan pins a row). Both become picker-less inert-`--` commands
  (listings, not actions): summary/behavior parity with `l`/`ll` inert
  rows.
- `llu --json -- src/`: the JSON sink is pathspec-aware too (umbrella
  §6.2): scoped count guard, scoped stderr message, empty-envelope shape
  on zero matching commits. The plan must plumb BOTH the human and the
  JSON path — a plan reading this spec alone must not plumb only stdout.

### `w-get`
Partially migrated in PR-A (pathspec machinery exists; probed:
`w-get HEAD -- src/` already scopes). Finish to the full contract: entry
validation, post-`--` known-flag rejection (probed today: `w-get --
--dry-run` swallows the flag into the COMMITISH slot — "Invalid commitish
for --target: --dry-run" exit 1; target: exit 2 flags-must-precede), and
the scoped summary gate. Its `-u`/`--upstream`, `-f`, `--dry-run` stay
action flags.

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
| `w purge-all -- src/` / `w zap-all --` | "unknown option: --" exit 1 | path → exit 2 whole-tree pointer; bare `--` inert |
| `w-get HEAD -- src/` | works (scope flows; "Will reset files to commit HEAD") | unchanged compat + entry validation |
| `w-get -- --dry-run` | flag swallowed into commitish slot, exit 1 | exit 2: flags must precede '--' |
| `w wip -- "-fix"` | message delimiter honored (branch WIP/….fix) | UNCHANGED — Class 2b keeps `--` data semantics |
| `w wips -- "draft"` (gateway) | branch WIP/….draftSTAY pollution; stay never applies | gateway prepends `--stay`; composes as `wip --stay -- "draft"` |
| `w badcmd` | usage printed, exit 0 | exit 2 |

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

- Conformance suite expansion — ONE new roster per behavioral class, and
  the MASTER roster is the single enrollment point (roast Major 5, the
  PR-A under-transcription trap):
  - `PATHSPEC_W_DESTRUCTIVE_ROWS=(w-discard w-purge w-zap w-wipe)`
  - `PATHSPEC_W_ALL_ROWS=(w-discard-all w-purge-all w-zap-all w-wipe-all)`
  - `PATHSPEC_WIP_ROWS=(w-wip w-unwip w-wipdel)` (exit-discipline rows
    only — their `--` data semantics get characterization rows, not
    pathspec rows)
  - `sh` ENROLLS IN THE EXISTING SHOW rows (`PATHSPEC_SHOW_ROWS`) and
    `llu` IN THE EXISTING LOG rows — one roster per behavioral class, not
    per PR; no `LOG_VIEWER_ROWS` near-collision (roast simplification,
    adopted).
  - Membership is enforced BY RULE, not re-enumeration: every PR-C command
    appears in the master roster AND in >=1 applicable column roster; the
    plan adds a membership-diff check (PR-C commands minus column
    enrollments must be empty) so a command cannot migrate silently
    untested.
- Every spike receipt in §3 becomes a red-first row before its migration
  lands (the PR-B discipline: probe red, pin, migrate, green).
- Mutating tests use the selecting-stub-gum (GUM_PICK) fixture; non-TTY
  confirm-cancel behavior stays pinned where it is today's contract.
- The category×scope matrix (Class 1) gets a dedicated probe-then-pin
  table in the PLAN (not resolved by this spec — see OQ-2).

## 6. Documentation and claim flips (derived BY RULE from §4 + umbrella §7)

**Flip table** — the rule (roast Major 4): every §4 registry row and §3
spike row whose Today != PR-C target ships a CHANGELOG flip entry. The
full list, mechanically:

| Observable flip | Today | PR-C |
|---|---|---|
| unknown dash-token on w-discard/w-wipe/w-purge (and zap) | silent path, exit 0 | exit 2 family template |
| known flag after `--` on any PR-C command | swallowed as path/commitish/message | exit 2 "flags must precede '--'" |
| malformed magic on any PR-C command | silent no-match / unvalidated flow-through | exit 2 Invalid pathspec |
| scope matches nothing on a destructive | (varies per command) | info "No files matching … to <verb>." exit 0 |
| `w wipdel`/`w-wip`/`w-unwip` unknown dash-token | exit 1 | exit 2 family template |
| `-all` command + pathspec after `--` | "unknown option: --" exit 1 | exit 2 whole-tree pointer; bare `--` inert |
| `llu -- <path>` | "Unknown option: --" exit 1 | scoped outgoing list, exit 0 |
| `sh <ref> [path]` | "accepts one commit reference" exit 1 | ref + scoped details, exit 0 |
| `w wips -- <msg>` | branch-name pollution, stay not applied | composes `wip --stay -- <msg>` |
| `w badcmd` | usage, exit 0 | exit 2 |

**Doc change-set** — the rule: every artifact that states a Today claim in
the flip table flips in the SAME PR, plus what the umbrella §7 and PR-B
§3.5 already assigned to PR-C:

- `:pathspec` article (git-config/lib/python/articles/pathspec.md):
  support matrix loses every `not yet` row; w-*/llu/sh sections with
  worked examples; migration notes carrying the flip table.
- README command reference: `sh`/`llu` pathspec rows (umbrella 16–17).
- `docs/commands/working-dir.md` (ACTUAL filename; the office-hours doc
  said working-directory.md): scoped-destruction examples, the
  narrowing-only safety property.
- `docs/commands/logging.md` — umbrella §7 flags it "stale the moment
  PR-C lands": llu/sh pathspec rows.
- `docs/git-to-hug.md`: translation rows for the new scoped forms.
- Help `:pathspec` pointer blocks in every migrated command's --help —
  PR-B deferred "their blocks land with their features"; PR-C is that
  landing for w-*/llu/sh.
- CHANGELOG: script-migration section carrying the flip table verbatim.

## 7. Open questions routed to the PLAN (probe-first, not guessed here)

- **OQ-1** trailing bare `--` per Class 1 command: picker vs inert — decide
  by each command's existing interactive flow (picker exists → picker).
- **OQ-2** category×scope matrix: exact interplay of `-u/-s` (discard),
  `-u/-i` (purge), `--browse-root`, and pathspec scope — pin per command
  with probes before migration; the spike's `purge -i -- src/` tracked-path
  error is the first cell.
- ~~OQ-3~~ RESOLVED in §2 Class 0 by arm enumeration (roast Critical 1):
  the gateway is pass-through EXCEPT the `wips` arm (prepends its injected
  flag) and the unknown-subcommand arm (normalized to exit 2).

## 8. Out of scope (parked, separate PRs)

elifarley/hug-scm#301 (roast-minor polish), #302 (LOW batch), #303
(us-extraction + sl* templating — the post-ladder cleanup), #304 (nullsafe
sweep). The `hg-config/` Mercurial parallel (per ADR-002, follows Git).
