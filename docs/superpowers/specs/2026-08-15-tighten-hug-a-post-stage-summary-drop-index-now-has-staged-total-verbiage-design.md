# Tighten "hug a" Post-Stage Summary

**Issue:** elifarley/hug-scm#278
**Date:** 2026-08-15

## Problem

`hug a` prints a post-stage summary with two issues:

1. **Sloppy plural:** `file(s)` is lazy — the code already knows the count and uses a plural helper for the first sentence, but the second sentence punts with `(s)`.
2. **Verbose second sentence:** `Index now has 2 file(s) staged total.` is 8 words where fewer would do. "Index" is git internals jargon.

Current output:
```
Staged 1 file. Index now has 1 file(s) staged total.
```

## Design

### Format string change

**File:** `git-config/bin/git-a:77-78`

```bash
# Before
printf 'Staged %d file%s. Index now has %d file(s) staged total.\n' \
  "$_staged" "$([[ $_staged -eq 1 ]] && echo '' || echo 's')" "$_index_after" >&2

# After
printf 'Staged %d file%s. %d staged total now.\n' \
  "$_staged" "$([[ $_staged -eq 1 ]] && echo '' || echo 's')" "$_index_after" >&2
```

The existing plural helper (`[[ $_staged -eq 1 ]] && echo '' || echo 's'`) stays as-is. Only the format string changes.

New output:
```
Staged 1 file. 1 staged total now.
```

### Test adjustments

**File:** `tests/unit/test_add.bats`

Update assertions to match new wording. Tests should assert on the presence of the count number and "staged total now" rather than exact phrasing, so they remain resilient to future wording changes.

| Line | Before | After |
|------|--------|-------|
| 19 | `"Index now has 1 file(s) staged total."` | `"1 staged total now."` |
| 32 | `"Index now has 2 file(s) staged total."` | `"2 staged total now."` |
| 44 | `"file(s) staged total."` | `"staged total now."` |
| 53 | `refute_output --partial "file(s) staged total."` | `refute_output --partial "staged total now."` |

## Scope

- One format string in `git-config/bin/git-a`
- Four assertion updates in `tests/unit/test_add.bats`
- No new features, no behavioral changes beyond message text
