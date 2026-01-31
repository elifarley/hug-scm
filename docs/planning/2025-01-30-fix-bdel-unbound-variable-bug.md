# Fix: `hug bdel` Unbound Variable Error

## Problem Statement

Running `hug bdel` produces an unbound variable error:
```
/home/ecc/IdeaProjects/hug-scm/git-config/lib/hug-git-branch: line 1068: 13: unbound variable
```

## Root Cause Analysis

In `git-bdel` (lines 94-96), `filter_branches` is called with only 10 positional arguments, but the function signature expects 14 parameters after the `dates` parameter was added:

```bash
# Current (broken) call in git-bdel:94-96
filter_branches branches hashes subjects tracks "$current_branch" \
  filtered_branches filtered_hashes filtered_subjects filtered_tracks \
  "true" "true" ""
```

The `filter_branches` function signature (hug-git-branch:1040):
```bash
# Usage: filter_branches input_branches input_hashes input_subjects input_tracks input_dates current_branch output_branches output_hashes output_subjects output_tracks output_dates exclude_current exclude_backup [filter_function]
```

Parameters:
1. `input_branches` - ✅ passed as `branches`
2. `input_hashes` - ✅ passed as `hashes`
3. `input_subjects` - ✅ passed as `subjects`
4. `input_tracks` - ✅ passed as `tracks`
5. `input_dates` - ❌ **MISSING** - This is the bug!
6. `current_branch` - ✅ passed as `"$current_branch"`
7. `output_branches` - ✅ passed as `filtered_branches`
8. `output_hashes` - ✅ passed as `filtered_hashes`
9. `output_subjects` - ✅ passed as `filtered_subjects`
10. `output_tracks` - ✅ passed as `filtered_tracks`
11. `output_dates` - ❌ **MISSING**
12. `exclude_current` - ✅ passed as `"true"`
13. `exclude_backup` - ✅ passed as `"true"`
14. `filter_function` - ✅ passed as `""`

When parameters 5 and 11 are missing, parameter 13 becomes unbound (line 1068 references `${13}`).

## Why Tests Didn't Catch This

The existing tests in `test_bdel.bats` don't exercise the code path that triggers the bug:

1. Tests with explicit branch arguments skip the interactive mode entirely
2. Tests using `echo '' | hug bdel` send EOF input which causes gum to exit before reaching the `filter_branches` call
3. The bug only manifests when gum would actually show the menu (real interactive mode)

## Solution

### Code Fix in `git-bdel`

Added the missing `dates` array declaration and passed it to `filter_branches`:

```bash
# Before (broken - git-bdel:93-96)
declare -a filtered_branches=()
declare -a filtered_hashes=() filtered_subjects=() filtered_tracks=()
filter_branches branches hashes subjects tracks "$current_branch" \
  filtered_branches filtered_hashes filtered_subjects filtered_tracks \
  "true" "true" ""

# After (fixed)
declare -a filtered_branches=()
declare -a filtered_hashes=() filtered_subjects=() filtered_tracks=() filtered_dates=()
filter_branches branches hashes subjects tracks dates "$current_branch" \
  filtered_branches filtered_hashes filtered_subjects filtered_tracks filtered_dates \
  "true" "true" ""
```

## Files Modified

1. **`git-config/bin/git-bdel`** - Fixed the `filter_branches` call (lines 92-96)

## Verification Results

1. ✅ Manual test: `hug bdel` no longer throws "unbound variable" error
2. ✅ Unit tests: `make test-unit TEST_FILE=test_bdel.bats` - 20/20 passed
3. ✅ Library tests: `make test-lib TEST_FILE=test_hug_git_branch.bats` - 19/19 passed
4. ✅ Branch switch tests: `make test-unit TEST_FILE=test_branch_switch.bats` - 10/10 passed
5. ✅ Full BATS suite: 1531/1531 tests passed

## Lessons Learned

### Critical Issues Discovered

1. **Parameter Signature Fragility in Bash**
   - **Issue**: Adding a new parameter to a function (like `dates` to `filter_branches`) requires updating ALL call sites
   - **Impact**: Missing parameter at ONE call site caused "unbound variable" error that only manifested in interactive mode
   - **Detection**: Tests with EOF input (`echo '' | hug bdel`) bypassed the actual bug because gum exited before reaching the broken code

2. **Test Coverage Gaps for Interactive Commands**
   - **Issue**: Tests using `echo '' | command` for interactive commands can miss bugs in the code path before the interactive prompt
   - **Root Cause**: Empty input causes early exit, skipping the code that would execute during real interactive sessions
   - **Solution**: Use gum mock infrastructure (`setup_gum_mock`) for comprehensive interactive testing, or add unit tests that call the underlying library functions directly

3. **Positional Parameters > 9 Require Braces**
   - **Issue**: Bash positional parameters beyond 9 MUST use braces: `${10}`, `${11}`, etc.
   - **ShellCheck Warning**: SC1087 warns about this, but the codebase suppresses it
   - **Best Practice**: When modifying functions with many positional parameters, always check if new parameters push the count beyond 9

### Prevention Strategies

1. **Function Signature Documentation**
   - Always update usage comments when modifying function signatures
   - Include parameter count in the comment (e.g., "14 parameters")
   - Example: `# Usage: filter_branches (14 params): input_* input_dates current_branch output_* exclude_* [filter]`

2. **Grepping for Call Sites**
   - After modifying a function signature, grep for ALL call sites:
     ```bash
     grep -r "filter_branches" git-config/
     ```
   - Verify each call site matches the new signature

3. **Library-Level Tests for Core Functions**
   - Test library functions directly (not just through commands)
   - Validate parameter handling at the function level
   - The existing `test_hug_git_branch.bats` already does this well

4. **Testing Interactive Commands Properly**
   - Use `setup_gum_mock` for gum-based interactive commands
   - Test both success and failure paths
   - Don't rely on EOF input alone for comprehensive testing

### Architectural Insights

This bug highlights a classic challenge in Bash development: **positional parameters are fragile**.

**More robust alternatives for future work:**
1. **Named parameters via associative arrays**: Pass a single config object
2. **Structural validation**: Check parameter count at function entry
3. **Migration to Python**: For complex functions with many parameters, Python's type safety is superior

**Current mitigation:**
- The existing library tests in `test_hug_git_branch.bats` caught the function signature change
- The call site in `select_branches` (hug-git-branch:1007) was already updated correctly
- Only the `git-bdel` call site was missed, which is now fixed
