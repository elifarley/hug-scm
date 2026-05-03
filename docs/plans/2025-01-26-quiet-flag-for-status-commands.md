# `-q` / `--quiet` / `HUG_QUIET` Support for Status/Listing Commands Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `-q` / `--quiet` flag support to 8 Hug status/listing commands to suppress the summary line (`git s`) that they call at the end.

**Architecture:**
- Simple commands: Manual case statement parsing for `-q` / `--quiet`, check both flag and `HUG_QUIET` env var
- Complex commands: Already use `parse_common_flags` which exports `HUG_QUIET=T`, just check it before calling `git s`
- Key design principle: `git-s` is the "summary line generator" - it always generates. The callers decide whether to invoke it.

**Tech Stack:** Bash scripting, BATS testing

---

## Task 1: Modify `git-sls` (template for simple commands)

**Files:**
- Modify: `git-config/bin/git-sls`

**Step 1: Add quiet variable initialization**

After line 15 (after `pathspecs=()`), add:

```bash
quiet=false
if [[ ${HUG_QUIET:-} == T ]]; then
  quiet=true
fi
```

**Step 2: Add -q/--quiet flag parsing**

In parsing loop (after `--json` case), add:

```bash
  -q | --quiet)
    quiet=true
    ;;
```

**Step 3: Conditionally show summary line**

Replace line 53 `exec hug s` with:

```bash
  # Show summary line (unless quiet mode)
  if ! $quiet; then
    exec hug s
  fi
```

---

## Task 2: Modify `git-slu` (same pattern as sls)

**Files:**
- Modify: `git-config/bin/git-slu`

**Step 1: Add quiet variable initialization**

After line 15 (after `pathspecs=()`), add:

```bash
quiet=false
if [[ ${HUG_QUIET:-} == T ]]; then
  quiet=true
fi
```

**Step 2: Add -q/--quiet flag parsing**

In parsing loop (after `--json` case), add:

```bash
  -q | --quiet)
    quiet=true
    ;;
```

**Step 3: Conditionally show summary line**

Replace line 53 `exec hug s` with:

```bash
  # Show summary line (unless quiet mode)
  if ! $quiet; then
    exec hug s
  fi
```

---

## Task 3: Modify `git-slk` (same pattern as sls)

**Files:**
- Modify: `git-config/bin/git-slk`

**Step 1: Add quiet variable initialization**

After line 15 (after `pathspecs=()`), add:

```bash
quiet=false
if [[ ${HUG_QUIET:-} == T ]]; then
  quiet=true
fi
```

**Step 2: Add -q/--quiet flag parsing**

In parsing loop (after `--json` case), add:

```bash
  -q | --quiet)
    quiet=true
    ;;
```

**Step 3: Conditionally show summary line**

Replace line 53 `exec hug s` with:

```bash
  # Show summary line (unless quiet mode)
  if ! $quiet; then
    exec hug s
  fi
```

---

## Task 4: Modify `git-sli` (same pattern as sls)

**Files:**
- Modify: `git-config/bin/git-sli`

**Step 1: Add quiet variable initialization**

After line 15 (after `pathspecs=()`), add:

```bash
quiet=false
if [[ ${HUG_QUIET:-} == T ]]; then
  quiet=true
fi
```

**Step 2: Add -q/--quiet flag parsing**

In parsing loop (after `--json` case), add:

```bash
  -q | --quiet)
    quiet=true
    ;;
```

**Step 3: Conditionally show summary line**

Replace line 53 `exec hug s` with:

```bash
  # Show summary line (unless quiet mode)
  if ! $quiet; then
    exec hug s
  fi
```

---

## Task 5: Modify `git-statusbase` (supports sl and sla)

**Files:**
- Modify: `git-config/bin/git-statusbase`

**Step 1: Add quiet variable initialization**

After line 17 (after `pathspecs=()`), add:

```bash
quiet=false
if [[ ${HUG_QUIET:-} == T ]]; then
  quiet=true
fi
```

**Step 2: Add -q/--quiet flag parsing**

In parsing loop (after `-uno | --untracked-files=no` case), add:

```bash
  -q | --quiet)
    quiet=true
    ;;
```

**Step 3: Conditionally show summary line**

Replace line 77 `exec hug s` with:

```bash
  # Show summary line (unless quiet mode)
  if ! $quiet; then
    exec hug s
  fi
```

---

## Task 6: Modify `git-su` (template for complex commands)

**Files:**
- Modify: `git-config/bin/git-su`

**Step 1: Update help text**

After line 24 (after `-h, --help     Show this help`), add:

```bash
    -q, --quiet    Suppress summary line (also honors HUG_QUIET env var)
```

**Step 2: Wrap first git s call (line 90)**

Replace line 90 `git s` with:

```bash
  if [[ ${HUG_QUIET:-} != T ]]; then
    git s
  fi
```

**Step 3: Wrap second exec hug s call (line 102)**

Replace line 102 `exec hug s` with:

```bash
if [[ ${HUG_QUIET:-} != T ]]; then
  exec hug s
fi
```

---

## Task 7: Modify `git-ss` (same pattern as su)

**Files:**
- Modify: `git-config/bin/git-ss`

**Step 1: Update help text**

After line 24 (after `-h, --help     Show this help`), add:

```bash
    -q, --quiet    Suppress summary line (also honors HUG_QUIET env var)
```

**Step 2: Wrap first git s call (line 90)**

Replace line 90 `git s` with:

```bash
  if [[ ${HUG_QUIET:-} != T ]]; then
    git s
  fi
```

**Step 3: Wrap second exec hug s call (line 102)**

Replace line 102 `exec hug s` with:

```bash
if [[ ${HUG_QUIET:-} != T ]]; then
  exec hug s
fi
```

---

## Task 8: Modify `git-sw` (same pattern as su)

**Files:**
- Modify: `git-config/bin/git-sw`

**Step 1: Update help text**

After line 24 (after `-h, --help     Show this help`), add:

```bash
    -q, --quiet    Suppress summary line (also honors HUG_QUIET env var)
```

**Step 2: Wrap first git s call (line 89)**

Replace line 89 `git s` with:

```bash
  if [[ ${HUG_QUIET:-} != T ]]; then
    git s
  fi
```

**Step 3: Wrap second exec hug s call (line 101)**

Replace line 101 `exec hug s` with:

```bash
if [[ ${HUG_QUIET:-} != T ]]; then
  exec hug s
fi
```

---

## Task 9: Add tests for `hug sls`

**Files:**
- Modify: `tests/unit/test_status_staging.bats`

**Step 1: Write test for --quiet flag**

Add after line 889 (after `hug slu with wildcard pattern` test):

```bats
@test "hug sls: suppresses summary with --quiet flag" {
  git add staged.txt
  run hug sls --quiet
  assert_success
  assert_output --partial "S:Mod"
  refute_output --partial "HEAD:"
}

@test "hug sls: suppresses summary with HUG_QUIET environment" {
  git add staged.txt
  export HUG_QUIET=T
  run hug sls
  assert_success
  assert_output --partial "S:Mod"
  refute_output --partial "HEAD:"
  unset HUG_QUIET
}

@test "hug sls: shows summary without quiet flag" {
  git add staged.txt
  run hug sls
  assert_success
  assert_output --partial "S:Mod"
  assert_output --partial "HEAD:"
}
```

**Step 2: Run tests to verify they pass**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="sls.*quiet" TEST_SHOW_ALL_RESULTS=1`

Expected: PASS

---

## Task 10: Add tests for `hug slu`

**Files:**
- Modify: `tests/unit/test_status_staging.bats`

**Step 1: Write tests for --quiet flag and HUG_QUIET**

Add after the tests from Task 9:

```bats
@test "hug slu: suppresses summary with --quiet flag" {
  run hug slu --quiet
  assert_success
  assert_output --partial "U:Mod"
  refute_output --partial "HEAD:"
}

@test "hug slu: suppresses summary with HUG_QUIET environment" {
  export HUG_QUIET=T
  run hug slu
  assert_success
  assert_output --partial "U:Mod"
  refute_output --partial "HEAD:"
  unset HUG_QUIET
}
```

**Step 2: Run tests to verify they pass**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="slu.*quiet" TEST_SHOW_ALL_RESULTS=1`

Expected: PASS

---

## Task 11: Add tests for `hug slk`

**Files:**
- Modify: `tests/unit/test_status_staging.bats`

**Step 1: Write tests for --quiet flag and HUG_QUIET**

Add after the tests from Task 10:

```bats
@test "hug slk: suppresses summary with --quiet flag" {
  run hug slk --quiet
  assert_success
  assert_output --partial "untrcK"
  refute_output --partial "HEAD:"
}

@test "hug slk: suppresses summary with HUG_QUIET environment" {
  export HUG_QUIET=T
  run hug slk
  assert_success
  assert_output --partial "untrcK"
  refute_output --partial "HEAD:"
  unset HUG_QUIET
}
```

**Step 2: Run tests to verify they pass**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="slk.*quiet" TEST_SHOW_ALL_RESULTS=1`

Expected: PASS

---

## Task 12: Add tests for `hug sli`

**Files:**
- Modify: `tests/unit/test_status_staging.bats`

**Step 1: Write tests for --quiet flag and HUG_QUIET**

Add after the tests from Task 11:

```bats
@test "hug sli: suppresses summary with --quiet flag" {
  echo "*.log" > .gitignore
  git add .gitignore
  git commit -m "Add gitignore" >/dev/null 2>&1
  echo "log" > debug.log

  run hug sli --quiet
  assert_success
  assert_output --partial "debug.log"
  refute_output --partial "HEAD:"
}

@test "hug sli: suppresses summary with HUG_QUIET environment" {
  echo "*.log" > .gitignore
  git add .gitignore
  git commit -m "Add gitignore" >/dev/null 2>&1
  echo "log" > debug.log

  export HUG_QUIET=T
  run hug sli
  assert_success
  assert_output --partial "debug.log"
  refute_output --partial "HEAD:"
  unset HUG_QUIET
}
```

**Step 2: Run tests to verify they pass**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="sli.*quiet" TEST_SHOW_ALL_RESULTS=1`

Expected: PASS

---

## Task 13: Add tests for `hug sl`

**Files:**
- Modify: `tests/unit/test_status_staging.bats`

**Step 1: Write tests for --quiet flag and HUG_QUIET**

Add after the tests from Task 12:

```bats
@test "hug sl: suppresses summary with --quiet flag" {
  run hug sl --quiet
  assert_success
  assert_output --partial "README.md"
  refute_output --partial "HEAD:"
}

@test "hug sl: suppresses summary with HUG_QUIET environment" {
  export HUG_QUIET=T
  run hug sl
  assert_success
  assert_output --partial "README.md"
  refute_output --partial "HEAD:"
  unset HUG_QUIET
}
```

**Step 2: Run tests to verify they pass**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="hug sl.*quiet" TEST_SHOW_ALL_RESULTS=1`

Expected: PASS

---

## Task 14: Add tests for `hug sla`

**Files:**
- Modify: `tests/unit/test_status_staging.bats`

**Step 1: Write tests for --quiet flag and HUG_QUIET**

Add after the tests from Task 13:

```bats
@test "hug sla: suppresses summary with --quiet flag" {
  run hug sla --quiet
  assert_success
  assert_output --partial "untracked.txt"
  refute_output --partial "HEAD:"
}

@test "hug sla: suppresses summary with HUG_QUIET environment" {
  export HUG_QUIET=T
  run hug sla
  assert_success
  assert_output --partial "untracked.txt"
  refute_output --partial "HEAD:"
  unset HUG_QUIET
}
```

**Step 2: Run tests to verify they pass**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="hug sla.*quiet" TEST_SHOW_ALL_RESULTS=1`

Expected: PASS

---

## Task 15: Add tests for `hug su`

**Files:**
- Modify: `tests/unit/test_status_staging.bats`

**Step 1: Write tests for --quiet flag and HUG_QUIET**

Add after the tests from Task 14:

```bats
@test "hug su: suppresses summary with --quiet flag" {
  run hug su --quiet
  assert_success
  assert_output --partial "Unstaged diff"
  refute_output --partial "HEAD:"
}

@test "hug su: suppresses summary with HUG_QUIET environment" {
  export HUG_QUIET=T
  run hug su
  assert_success
  assert_output --partial "Unstaged diff"
  refute_output --partial "HEAD:"
  unset HUG_QUIET
}

@test "hug su --stat: suppresses summary with --quiet flag" {
  run hug su --stat --quiet
  assert_success
  assert_output --partial "Unstaged file stats"
  refute_output --partial "HEAD:"
}
```

**Step 2: Run tests to verify they pass**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="hug su.*quiet" TEST_SHOW_ALL_RESULTS=1`

Expected: PASS

---

## Task 16: Add tests for `hug ss`

**Files:**
- Modify: `tests/unit/test_status_staging.bats`

**Step 1: Write tests for --quiet flag and HUG_QUIET**

Add after the tests from Task 15:

```bats
@test "hug ss: suppresses summary with --quiet flag" {
  git add staged.txt
  run hug ss --quiet
  assert_success
  assert_output --partial "Staged diff"
  refute_output --partial "HEAD:"
}

@test "hug ss: suppresses summary with HUG_QUIET environment" {
  git add staged.txt
  export HUG_QUIET=T
  run hug ss
  assert_success
  assert_output --partial "Staged diff"
  refute_output --partial "HEAD:"
  unset HUG_QUIET
}

@test "hug ss --stat: suppresses summary with --quiet flag" {
  git add staged.txt
  run hug ss --stat --quiet
  assert_success
  assert_output --partial "Staged file stats"
  refute_output --partial "HEAD:"
}
```

**Step 2: Run tests to verify they pass**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="hug ss.*quiet" TEST_SHOW_ALL_RESULTS=1`

Expected: PASS

---

## Task 17: Add tests for `hug sw`

**Files:**
- Modify: `tests/unit/test_status_staging.bats`

**Step 1: Write tests for --quiet flag and HUG_QUIET**

Add after the tests from Task 16:

```bats
@test "hug sw: suppresses summary with --quiet flag" {
  run hug sw --quiet
  assert_success
  assert_output --partial "Working dir changes"
  refute_output --partial "HEAD:"
}

@test "hug sw: suppresses summary with HUG_QUIET environment" {
  export HUG_QUIET=T
  run hug sw
  assert_success
  assert_output --partial "Working dir changes"
  refute_output --partial "HEAD:"
  unset HUG_QUIET
}

@test "hug sw --stat: suppresses summary with --quiet flag" {
  run hug sw --stat --quiet
  assert_success
  assert_output --partial "Unstaged file stats"
  refute_output --partial "HEAD:"
}
```

**Step 2: Run tests to verify they pass**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="hug sw.*quiet" TEST_SHOW_ALL_RESULTS=1`

Expected: PASS

---

## Task 18: Run full test suite for verification

**Files:**
- Test: `tests/unit/test_status_staging.bats`

**Step 1: Run all quiet flag tests**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="quiet" TEST_SHOW_ALL_RESULTS=1`

Expected: All PASS (18 new tests)

**Step 2: Run entire status_staging test file**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_SHOW_ALL_RESULTS=1`

Expected: All PASS (existing + new tests)

**Step 3: Run full unit test suite**

Run: `make test-unit TEST_SHOW_ALL_RESULTS=1`

Expected: All PASS (no regressions)

---

## Task 19: Manual verification

**Files:**
- Manual testing required

**Step 1: Test quiet flag works**

Run: `hug sls -q`

Expected: Shows staged files, no summary line

**Step 2: Test HUG_QUIET environment variable**

Run: `HUG_QUIET=T hug slu`

Expected: Shows unstaged files, no summary line

**Step 3: Verify git-s itself is unaffected**

Run: `hug s -q`

Expected: Still shows summary (git-s itself doesn't respect quiet)

**Step 4: Test with no flags**

Run: `hug slk`

Expected: Shows untracked files AND summary line

---

## Verification Summary

After completing all tasks, verify:

1. All 8 commands (`sls`, `slu`, `slk`, `sli`, `sl`, `sla`, `su`, `ss`, `sw`) support `-q` / `--quiet` flag
2. All 8 commands honor `HUG_QUIET=T` environment variable
3. `git s` itself still shows summary when called directly (it's the generator, not suppressor)
4. All existing tests still pass
5. All new tests pass

**Test Commands:**

```bash
# Run specific test file with all results
make test-unit TEST_FILE=test_status_staging.bats TEST_SHOW_ALL_RESULTS=1

# Run only quiet-related tests
make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="quiet" TEST_SHOW_ALL_RESULTS=1

# Run full unit test suite
make test-unit TEST_SHOW_ALL_RESULTS=1
```
