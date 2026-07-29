- **gum-mock `confirm` defaults to YES (exit 0)** when `HUG_TEST_GUM_CONFIRM` is unset and no gum exists at /usr/bin or /usr/local/bin (tests/bin/gum-mock:186-205, empirically verified). Warn-tier prompts under the suite default therefore AUTO-CONFIRM unless a test sets `HUG_TEST_GUM_CONFIRM=no` or `HUG_DISABLE_GUM=true`. Cancel-via-`HUG_TEST_GUM_INPUT_RETURN_CODE=1` tests silently break when a prompt is lowered danger→warn (that env var only drives mock `input`/`filter`).

## Key Learnings

- **2026-07-28 — hug HEAD-mover recovery pitfall (code-roast):** `handle_standard_operation`
  (hug-git-upstream:96-108) exits 0 "Already at target" whenever
  `count_commits_in_range target HEAD` == 0 — which is ALWAYS true for a FORWARD (descendant)
  target. Any "recover by re-running the same command with the pre-op SHA" design is a silent
  no-op for h-back/h-undo/h-rewind/h-rollback. h-squash escapes only by topology luck (squash
  commit is a sibling of pre-op HEAD, so the range is non-empty). A restore path needs a
  gate-less reset primitive or a descendant-target-aware mode.
- **2026-07-28 — spec-claim verification lesson:** "Verified" claims must be replayed AT THE
  LAYER CLAIMED. Spec §5's raw `reset --keep` probes were correct, but its conclusion was
  asserted about `hug h rollback` — which never reaches git. Similarly §4 "Verified: all five
  commands accept an arbitrary target" verified rev-parse, not end-to-end recovery.
- **2026-07-28 — cmv switches branches last (git-cmv:242-243).** Any hint/recovery design for
  cmv must be branch-aware; a same-branch recovery command run after cmv executes on the
  destination branch (empirically orphaned main's own commits, exit 0).
- **2026-07-28 — the mover names lie about direction (user correction).** `hug h back` moves HEAD
  FORWARD too (`hug h back -u` when behind upstream; help: "Moves HEAD to target"), yet agents
  kept assuming `back` = backward-only. Don't reuse these names as direction cues: `hug h restore
  --<op>` flags are reset-MODE selectors (`--back` ≡ `reset --soft`); direction comes ONLY from the
  target vs HEAD. Document the mode equivalence in help so the name can't mislead again. (And note:
  the recovery no-op of Critical #1 is the aligned-target SHORT-CIRCUIT, not direction — `h-back
  <descendant>` no-ops on a clean tree via handle_standard_operation, git-h-back:106.)

## Do-Not-Repeat

- **2026-07-28:** Don't trust a worktree's claimed base ("off origin/main") — check
  `hug merge-base HEAD origin/main`. The head-movers-tier-unify worktree was actually based on
  pre-#225 3c4b825 while the spec it carries is written against post-#225 origin/main.

## Decision Log

- **2026-07-28 — recovery = one gate-bypassing primitive, not re-invoked movers.** To fix the
  forward-target no-op (Key Learnings), recovery is a purpose-built `hug h restore <SHA> --<mode>`
  whose no-op test is exact-SHA equality (never the range-count gate). `--mode` is REQUIRED so the
  mode-match is enforced by construction; one helper templates all five warn-tier hints. Chosen over
  (a) a descendant-aware mode in handle_standard_operation — smaller surface but keeps six hint
  strings and the branch-blindness that breaks cmv — and (b) printing raw `git reset` equivalents —
  leaks plumbing, can't express branch-awareness. (OB a45012ac.)
- **2026-07-28 — cmv is danger, not warn.** cmv switches branch (git-cmv:242-243) AND rewrites SHAs
  (cherry-pick), so by the §2 standard no complete single-command recovery exists; a same-branch
  hint is worse than none (it orphaned main's commits, exit 0). Its clean-gate (git-cmv:130) stays
  to protect uncommitted work from the --hard, but the tier is danger with NO recovery hint. A
  genuinely complete branch-aware recovery is deferred to separate work. (OB a45012ac.)
- **2026-07-28 — empty-target guard (re-roast discovery):** `handle_upstream_operation`'s
  "Already synced" `exit 0` (hug-git-upstream:44-47) fires INSIDE the caller's `$(...)`
  subshell — the parent gets empty stdout and keeps running. Only git-h-rewind:91-93 and
  git-cmv:142-144 guard `[[ -z "$target" ]]`; h-back/h-undo/h-rollback don't → `hug X -u`
  on a synced/strictly-behind upstream crashes exit 128 (`rev-parse --short ""` fatal,
  reproduced at 1296dbf). h-squash survives only via the `|| echo 0` swallow (Defect 2 of
  elifarley/hug-scm#229). Any spec rewriting those call sites must own the guard.
- **2026-07-28 — h-back -u direction nuance (re-roast):** strictly behind (fast-forwardable,
  zero local commits) ⇒ "Already synced" + exit 128, NO movement; FORWARD movement only in
  the DIVERGED case (local commits exist AND upstream ahead) — verified empirically. Don't
  write "moves forward when behind" — write "when diverged with upstream ahead."
- **2026-07-28 — #229's contract lives in its SECOND comment (re-roast):** the issue BODY
  proposes `commits_ahead_behind` (a behind/ahead PAIR); the superseding second comment is
  where `commit_offset` (0⟺identity via SHA-equality short-circuit, ±N clean distance,
  EMPTY+exit2 ⟺ diverged, exit3 ⟺ unresolvable) and `is_same_commit` are defined. Citing
  #229 for that contract? It's the comment, not the body — check both before calling a
  cross-reference wrong.
- **2026-07-28 — post-rewind tree is tracked-clean (re-roast, E8):** after `h-rewind -f`
  on a dirty tree, `get_dirty_files` is empty (untracked files remain, correctly ignored).
  So a recovery hint's `-y` DOES proceed at recovery time — a "uniformly -y" hint design is
  mechanically right; the destroyed-edits caveat belongs on the OP's success output, not on
  the recovery hint (whose job is forward-looking).
