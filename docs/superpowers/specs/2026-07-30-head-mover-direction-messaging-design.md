# Design (Phase 2): Direction-truthful previews + result messaging for the HEAD-movers

- **Parent:** [elifarley/hug-scm#229](https://github.com/elifarley/hug-scm/issues/229) — depends on **Phase 1** (`2026-07-29-count-commits-in-range-audit-design.md`) landing first.
- **Date:** 2026-07-30
- **Status:** Design draft (design settled across code-roast rounds 3–5; carved into its own phase so the safety-critical Phase 1 ships minimal)

> Line anchors against local `main` @ `36d2eea`. Re-resolve at implementation time. Assumes Phase 1 has landed: `is_aligned` + `commits_ahead_behind` exist, `handle_standard_operation` is called bare with its `exit 0` guard intact, and forward targets already move HEAD (Phase 1's fix).

---

## 0. Why this is a separate phase

Phase 1 stops the forward-target no-op. That *exposes* two cosmetic defects that were previously hidden (forward targets no-op'd, so they never surfaced):

1. The **result message lies about direction**: the movers print "Moved HEAD **back** to …" (`git-h-back:130`, `git-h-undo:155`, `git-h-rollback:134`) and "Rewind complete" (`git-h-rewind:130`) even when HEAD moved **forward**.
2. The **preview is internally contradictory**: `handle_standard_operation`'s preview hardcodes `target..HEAD`, so a forward target shows "changes in **0 commit**:" above a **non-empty** `diff --stat` (the trees differ; the one-directional commit range is empty).

Neither is required by #229's acceptance criteria, and both live in the mover tails / preview path — the area that took three roast rounds to get right and produced four regressions. Isolating it here keeps Phase 1 surgical and gives this shell-runtime-subtle work its own focused review.

## 1. The settled design: compute direction in the mover tail

Rounds 3–5 tried three ways to get the direction to the movers, and **two were wrong**:

- **Round 3 — a process-global** (`HUG_HEAD_MOVE_DIRECTION` set by the helpers, read by the movers): an undocumented setter-before-reader contract, a `set -u` footgun, and a multi-year maintenance liability. Rejected.
- **Round 4 — emit on stdout**: `direction=$(handle_standard_operation …)` **voids the aligned-target guard** (`exit 0` inside `$(…)` quits only the subshell, so the mover proceeds and moves HEAD under "Already at target" — reproduced) AND **collides with `handle_upstream_operation`'s documented stdout contract** ("upstream commit hash", `hug-git-upstream:24-25`), captured by **6 callers across 8 sites** (`h-back:89`, `h-undo:93/95/98`, `h-rollback:94`, `h-rewind:105`, `git-cmv:141`, `git-h-squash:165`). Rejected.
- **Round 5 — compute in the mover tail (adopted):** the direction is computed where `$target` and `$pre_op_head` (HEAD captured before the reset) are **already live**, via a thin `direction_between` wrapper. Helpers emit nothing new and keep their existing stdout contracts; `exit 0` works because helpers stay called bare; each mover's diff is ~2 lines. This kills the round-3 and round-4 defects at the source.

## 2. The two helpers — `git-config/lib/hug-git-upstream`

### `direction_between <a> <b>` — the single direction-labeling site

```bash
# Label how a move from <b> to <a> goes. Thin wrapper over commits_ahead_behind
# (Phase 1). The ONE place direction is labeled for messaging/preview.
#   a ancestor of b -> "backward"    a descendant of b -> "forward"
#   a == b          -> "aligned"     neither           -> "diverged"
direction_between() {
  local a="${1:?}" b="${2:?}" rel f1 f2
  rel=$(commits_ahead_behind "$a" "$b") || return 1
  f1=${rel%%$'\t'*}; f2=${rel##*$'\t'}     # positional fields (see Phase 1 §3 for the order contract)
  if   [ "$f1" -gt 0 ] && [ "$f2" -eq 0 ]; then echo forward
  elif [ "$f1" -eq 0 ] && [ "$f2" -gt 0 ]; then echo backward
  elif [ "$f1" -eq 0 ] && [ "$f2" -eq 0 ]; then echo aligned
  else echo diverged; fi
}
```

### `report_head_move <direction> <target> [extra]` — the single direction-casing site

```bash
# Words the post-move result line truthfully from a DIRECTION ARGUMENT (not a global),
# so all four movers share ONE direction-casing site. `case` (not &&-chains) avoids any
# `set -e` short-circuit hazard. (An earlier draft took a dead `mode_noun` param — dropped.)
#   backward -> "Moved HEAD back to <sha> <extra>"
#   forward  -> "Moved HEAD forward to <sha> <extra>"   (NOT "back", NOT "Rewind complete")
#   diverged -> "Moved HEAD to <sha> <extra>"           (neutral; neither ahead nor behind)
#   aligned/"" -> "Moved HEAD to <sha> <extra>"         (defensive; HEAD didn't actually move)
report_head_move() {
  local direction="${1:-}" target="${2:?}" extra="${3:-}"
  local word
  case "$direction" in
    forward)      word="forward" ;;
    backward)     word="back" ;;
    diverged|''|aligned|*) word="" ;;
  esac
  info "Moved HEAD ${word:+$word }to $(git rev-parse --short "$target")${extra:+ $extra}"
}
```

## 3. Mover-tail changes (~2 lines each)

Each mover computes the direction in its shared tail and passes it to `report_head_move`. **Everything else is preserved — including `pre_op_head` and `emit_head_recovery_hint`** (round-5 MAJOR #5: an earlier blueprint dropped these, deleting the #222 recovery hint; do not repeat that). Shown for `git-h-back`; the other three are analogous:

```bash
# git-h-back: handle_standard_operation called BARE (Phase 1) — exit 0 still terminates
# the mover on aligned. Confirmation gate UNCHANGED (tier + staged-changes).
handle_standard_operation "move back" "$target"
if has_staged_changes; then
    prompt_confirm_warn "Move HEAD, keeping changes staged? [y/N]: "
else
    info "No staged changes detected; skipping confirmation."
fi
pre_op_head=$(git rev-parse HEAD)                          # preserved
git reset --soft "$target"
direction=$(direction_between "$target" "$pre_op_head")    # ← NEW: computed in-tail
report_head_move "$direction" "$target" "(uncommitted changes preserved)."  # ← NEW (was `info "Moved HEAD back…"`)
emit_head_recovery_hint "$pre_op_head" "back"              # preserved
```

**`handle_upstream_operation` is UNCHANGED** — still `echo "$target"`; the 8 captures (6 callers) keep working. Its `-u` path converges on the same mover tail (`git-h-back:86-130`), so the tail's `direction_between "$target" "$pre_op_head"` yields `backward` there too (HEAD is ahead of the upstream tip) — fixing the `-u` double-space/directionless result **without** touching the helper's stdout contract. The `-u` retained no-op (`local_commits == 0` → "Already synced", exit 0) is unchanged.

## 4. Direction-cased preview (inside `handle_standard_operation`)

Phase 2 also fixes the "changes in 0 commit:" preview. `handle_standard_operation` already computes the relationship for the guard (via `is_aligned` → `commits_ahead_behind`); it computes it once more for the preview and cases all **three** range-dependent artifacts together (commit list, diff stat, count/word) — flipping only some relocates the symptom (empty commit list above a non-empty stat):

```bash
# In handle_standard_operation, after the is_aligned guard, for the PREVIEW only.
# Positional fields (Phase 1 §3 order contract): for ("$target" HEAD):
#   f1 = HEAD-behind-target (FORWARD magnitude); f2 = HEAD-ahead-of-target (BACKWARD magnitude)
local rel f1 f2
rel=$(commits_ahead_behind "$target" HEAD) || return 1
f1=${rel%%$'\t'*}; f2=${rel##*$'\t'}
local list_start list_end diff_range count
if [ "$f1" -gt 0 ] && [ "$f2" -eq 0 ]; then          # FORWARD
    list_start="HEAD"; list_end="$target"; diff_range="HEAD..$target"; count="$f1"
else                                                  # backward / diverged
    list_start="$target"; list_end="HEAD"; diff_range="$target..HEAD"; count="$f2"
fi
local commit_word="commit"; [ "$count" -gt 1 ] && commit_word="commits"
printf 'Commits to be affected:\n' >&2
print_commit_list_in_range "$list_start" "$list_end" >&2   # was hardcoded: "$target" HEAD
if git diff --quiet "$diff_range"; then                    # was hardcoded: "$target..HEAD"
    printf '\nPreview: no file changes in %d %s.\n' >&2 "$count" "$commit_word"
else
    printf '\nPreview: changes in %d %s:\n' >&2 "$count" "$commit_word"
    git diff --stat "$diff_range" >&2
fi
```

(The redundant `commits_ahead_behind` call — one for the guard via `is_aligned`, one for the preview — is a single `git rev-list --count`; trivial cost vs. removing a process-global.)

## 5. Behavior enumeration (all four movers, forward target)

Confirmation is **direction-independent** (unchanged from Phase 1 — see Phase 1 §5; #231 per-state tier model). Only the **wording** changes:

| Caller | Forward-target result line (Phase 2) | Notes |
|---|---|---|
| `git-h-back` | "Moved HEAD **forward** to …" (was "back") | full→short SHA already; message via `report_head_move` |
| `git-h-undo` | "Moved HEAD **forward** to … (to undo commits)" (was "back") | the "to undo commits" extra preserved |
| `git-h-rollback` | "Moved HEAD **forward** to …" (was "Roll back HEAD to … done") | sentence rewritten via `report_head_move` |
| `git-h-rewind` | "Moved HEAD **forward** to …" (was "Rewind complete. Repository is now at …") | there is **no "back" string** to flip — the verb "Rewind" itself lies for a forward move; `report_head_move` words it truthfully. h-rewind's separate tier-based warning/hint (`:132-140`) is preserved. |
| divergent target (any mover) | "Moved HEAD to …" (neutral) | neither ahead nor behind |

## 6. Documentation

- **`git-config/lib/README.md:425-435`** — refresh the helper-usage examples: add `direction_between` + `report_head_move` with a worked mover-tail example; keep `handle_upstream_operation` shown returning the upstream SHA (the preserved contract) and `handle_standard_operation` called bare (Phase 1).
- **`git-config/lib/README.md`** — document `direction_between` / `report_head_move` in the `hug-git-upstream` section.

## 7. Testing strategy

- `direction_between` (unit): ancestor→`backward`; descendant→`forward`; equal→`aligned`; sibling→`diverged`; invalid ref→non-zero.
- `report_head_move` (unit): `backward`→"Moved HEAD back to …"; `forward`→"Moved HEAD **forward** to …"; `diverged`→neutral "Moved HEAD to …"; empty/`*`→neutral; no crash under `set -euo pipefail` (uses `case`, not `&&`-chains).
- **`h-rewind` verb truthfulness:** forward target → result line says "forward", NOT "Rewind complete"/"back".
- **`handle_upstream_operation` SHA contract preserved:** `target=$(handle_upstream_operation …)` still yields the SHA (not a direction token) on all 8 capturing sites (6 callers); no `-u` path renders a double-space or directionless result.
- **Recovery hint preserved:** after a successful warn-tier move, `emit_head_recovery_hint` still prints the `hug h restore <SHA> --<op> -y` line (`pre_op_head` + hint not dropped).
- **Preview coherence:** forward target → commit list AND `diff --stat` use `HEAD..target` with the behind-count; NO "changes in 0 commit:" above a non-empty stat.
- **Divergent target** (`h back <sibling-branch-tip>`) → neutral "Moved HEAD to …"; preview uses `target..HEAD`.
- **Confirmation unchanged:** forward + clean on `h-back`/`h-undo` still skips confirmation; forward + dirty on `h-rewind` still fires danger; backward behavior unchanged.

## 8. Acceptance criteria

- [ ] No mover result line lies about direction (forward → "forward"; diverged → neutral).
- [ ] `handle_upstream_operation`'s stdout contract (SHA) unchanged; all 8 captures (6 callers) work; no `-u` double-space.
- [ ] `pre_op_head` + `emit_head_recovery_hint` preserved in all four mover tails.
- [ ] Preview's three artifacts flip together; no "changes in 0 commit:" above a non-empty stat.
- [ ] Confirmation behavior unchanged from Phase 1 (direction-independent).
- [ ] `report_head_move` is `case`-based (no `set -e` short-circuit hazard); no dead parameters.
- [ ] `lib/README.md` examples refreshed.

## 9. Sequencing note

Land **Phase 1 first** (the safety fix; forward targets move HEAD; helper contracts untouched). Phase 2 then adds direction-awareness on top — its mover-tail edits are independent of Phase 1's helper internals (it only relies on `commits_ahead_behind` existing and the helpers being called bare). Each Phase-2 mover edit is independently green; land the two helpers, then the four mover tails, then docs.
