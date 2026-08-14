# Implementation Plan: Fix Combined Short Flags Bug (`-qs`, `-sq`)

## Status

**COMPLETED** ✅

All implementation steps completed and verified. Tests passing.

## Summary

Fixed a bug where combined short flags like `hug sw -qs` and `hug sw -sq` didn't work correctly - the summary line appeared and stats mode didn't activate. The root cause was that `parse_common_flags` doesn't recognize `-s`, so combined flags failed to parse properly.

**Solution**: Replaced the two-step parsing approach (`parse_common_flags` + manual loop) with direct GNU getopt calls in `git-su`, `git-ss`, and `git-sw`. This follows existing patterns in the codebase (e.g., `git-bc`, `git-wtc`, `git-bdel-backup`).

---

## Problem Analysis

### Bug Symptoms
- `hug sw -qs` shows summary line (should be suppressed) and doesn't show stats only
- `hug sw -sq` has the same issue
- Affects `git-su`, `git-ss`, and `git-sw`

### Root Cause
The two-step parsing approach (`parse_common_flags` + manual loop) fails for combined short flags:

1. `parse_common_flags` is called with `-qs`
2. GNU getopt sees `-s` as unknown (not in its option spec) and fails
3. Fallback manual parsing in `parse_common_flags` only handles exact matches (`-q` matches, `-qs` doesn't)
4. `-qs` gets passed through as a "remaining arg"
5. Manual loop in command scripts only matches `-s` exactly, not combined flags
6. Result: neither `-q` nor `-s` are recognized

### Why Not Add `-s` to `parse_common_flags`?
**Namespace conflict**: Git's `log` command uses `--stat` for file change statistics. Adding `-s` globally breaks commands like `git-llf` that need to pass git options through to underlying git commands.

---

## Implementation (Completed)

### Step 1: Modify `git-su` ✅
**File**: `/home/ecc/IdeaProjects/hug-scm/git-config/bin/git-su`

**Replaced lines 49-68** (the `parse_common_flags` eval and manual loop) with direct GNU getopt parsing:

```bash
# Parse all flags (common + command-specific) using getopt
set +e
PARSED=$(getopt --options hqs --longoptions help,quiet,stat,browse-root --name "hug su" -- "$@" 2>&1)
getopt_status=$?
set -e

if [ $getopt_status -ne 0 ]; then
  if [ -n "$PARSED" ]; then
    echo "$PARSED" >&2
  fi
  exit 1
fi

eval set -- "$PARSED"

# Initialize variables
stats_only=false
browse_root=false

# Process all options
while true; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -q|--quiet)
      export HUG_QUIET=T
      shift
      ;;
    -s|--stat)
      stats_only=true
      shift
      ;;
    --browse-root)
      browse_root=true
      export HUG_INTERACTIVE_FILE_SELECTION=true
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Internal error in option parsing" >&2
      exit 1
      ;;
  esac
done
```

**Updated function calls** to use the boolean variable instead of string expansion:
```bash
# Before: show_unstaged_diff ${stats_only:+--stats-only} -- "$file"
# After:
if $stats_only; then
  show_unstaged_diff --stats-only -- "$file"
else
  show_unstaged_diff -- "$file"
fi
```

### Step 2: Modify `git-ss` ✅
**File**: `/home/ecc/IdeaProjects/hug-scm/git-config/bin/git-ss`

Applied the same pattern as `git-su`, but for staged diff:
- Replaced getopt line with: `getopt --options hqs --longoptions help,quiet,stat,browse-root`
- Updated function calls to use `show_staged_diff`

### Step 3: Modify `git-sw` ✅
**File**: `/home/ecc/IdeaProjects/hug-scm/git-config/bin/git-sw`

Applied the same pattern as `git-su`, but for combined diff:
- Replaced getopt line with: `getopt --options hqs --longoptions help,quiet,stat,browse-root`
- Updated function calls to use `show_combined_diff`

### Step 4: Add Tests ✅
**File**: `/home/ecc/IdeaProjects/hug-scm/tests/unit/test_status_staging.bats`

Added 8 new tests for combined flags:
- `hug su -qs` and `hug su -sq`
- `hug ss -qs` and `hug ss -sq`
- `hug sw -qs` and `hug sw -sq`
- `hug su --stat --quiet` and `hug su --quiet --stat` (long flags in any order)

All tests verify:
1. Stats output is shown (e.g., "Unstaged file stats")
2. Diff patches are suppressed (no "@@" markers)
3. Summary line is suppressed (no "HEAD:" or emoji indicators)

---

## Verification Results

### Test Results
```
✓ All 116 tests passed in test_status_staging.bats
✓ Combined flags tests (tests 109-116) all pass
✓ No regressions in existing tests
```

### Manual Verification
```bash
# Before fix: summary line shown, stats-only mode not working
# After fix:
$ hug sw -qs
📝 📊 Unstaged file stats:
 file.txt | 1 +
 1 file changed, 1 insertion(+)
# (No summary line, no diff patches)

$ hug sw -sq
# Same correct behavior

# Stats-only mode verified (no @@ diff markers):
$ hug sw -qs 2>&1 | grep "^@@"
# (empty - correctly no diff markers)

# Summary suppression verified:
$ hug sw -qs 2>&1 | grep -E "(HEAD:|🟣|🟡|🔴|🟢|⚪)"
# (empty - correctly no summary line)
```

---

## Files Modified

| File | Changes |
|------|---------|
| `git-config/bin/git-su` | Replaced two-step parsing with direct GNU getopt (+57/-19 lines) |
| `git-config/bin/git-ss` | Replaced two-step parsing with direct GNU getopt (+57/-19 lines) |
| `git-config/bin/git-sw` | Replaced two-step parsing with direct GNU getopt (+57/-19 lines) |
| `tests/unit/test_status_staging.bats` | Added 8 tests for combined flags (+57/-0 lines) |

**Total**: +228 lines, -57 lines across 4 files

---

## Lessons Learned

### Why the Two-Step Parsing Failed

The original code used a two-step approach:
1. `parse_common_flags` - handled global flags (`-q`, `-h`, `--browse-root`)
2. Manual loop - handled command-specific flags (`-s`)

**Problem**: GNU getopt in `parse_common_flags` only knew about `-h`, `-q`, and `--browse-root`. When it encountered `-qs`, it saw `-s` as unknown and failed. The fallback manual parsing only matched exact flags (`-q` matches, `-qs` doesn't), so combined flags were never recognized.

### Pattern Recognition: Direct GNU Getopt

The solution followed an existing pattern in the codebase:

**Reference implementations:**
- `git-bc` (lines 71-72): `getopt --options hfqk:o:`
- `git-wtc`: Similar pattern
- `git-bdel-backup`: Similar pattern

**Key insight**: When a command needs both common and command-specific flags, don't use `parse_common_flags`. Instead, define all flags in a single getopt call. This:
1. Provides a single source of truth for flag parsing
2. Natively handles combined short flags (`-qs`, `-sq`)
3. Avoids namespace pollution (flags are only defined where needed)
4. Follows the principle of explicit over implicit

### Namespace Pollution Consideration

**Why not add `-s` to `parse_common_flags` globally?**

Git's `log` command uses `--stat` for file change statistics. If `-s` were added globally:
1. Commands like `git-llf` (log with filters) would intercept `--stat`
2. The `--stat` option would never reach the underlying `git log` command
3. Users couldn't use `hug llf --stat` to see file statistics in log output

**Lesson**: Command-specific flags should remain command-specific. Only add truly global flags to `parse_common_flags`.

### Boolean Variables vs String Expansion

**Before** (string expansion pattern):
```bash
stats_only=""  # or "1"
show_unstaged_diff ${stats_only:+--stats-only}
```

**After** (boolean pattern):
```bash
stats_only=false
if $stats_only; then
  show_unstaged_diff --stats-only
else
  show_unstaged_diff
fi
```

**Why the change?**

The string expansion pattern `${stats_only:+--stats-only}` is elegant but harder to read in conditional logic. When switching to direct getopt with proper variable initialization, using actual booleans (`true`/`false`) makes the intent clearer and the code more maintainable.

### Testing Strategy

**Comprehensive test coverage is critical for flag parsing bugs:**

1. **Test all combinations**: `-qs`, `-sq`, `--stat --quiet`, `--quiet --stat`
2. **Test across all affected commands**: `su`, `ss`, `sw`
3. **Verify both behaviors**: stats shown AND patches suppressed AND summary suppressed
4. **Test for regressions**: Run full test suite after changes

**Test pattern used:**
```bats
@test "hug su -qs: combined flags work correctly" {
  run hug su -qs
  assert_success
  assert_output --partial "Unstaged file stats"   # Positive check
  refute_output --partial "@@"                      # Negative check
  refute_output --partial "HEAD:"                   # Negative check
}
```

### Getopt Error Handling

**Critical pattern from `git-bdel-backup`**: Capture getopt stderr to show proper error messages:

```bash
set +e
PARSED=$(getopt --options hqs --longoptions help,quiet,stat,browse-root --name "hug su" -- "$@" 2>&1)
getopt_status=$?
set -e

if [ $getopt_status -ne 0 ]; then
  if [ -n "$PARSED" ]; then
    echo "$PARSED" >&2
  fi
  exit 1
fi
```

**Why this matters**: Without capturing stderr (`2>&1`), getopt errors would be lost, and users would see generic "option parsing failed" messages instead of helpful hints about which option was invalid.

---

## Remaining Work

**None** - Implementation is complete and verified.

### Optional Enhancements (Not Required)
1. Consider applying this pattern to other commands that use `parse_common_flags` + manual loops
2. Document the direct getopt pattern in CLAUDE.md for future reference

---

## References

- **Similar implementations**: `git-bc`, `git-wtc`, `git-bdel-backup`
- **Test file**: `tests/unit/test_status_staging.bats`
- **Library functions**: `git-config/lib/hug-cli-flags` (GNU getopt utilities)
