# ADR-001: Automated Testing Strategy for Hug SCM

**Status**: Accepted  
**Date**: 2025-10-22  
**Decision Makers**: Engineering Team  
**Context**: Hug SCM is a Bash-based CLI tool that wraps Git commands with a humane interface. Currently, there is no automated testing infrastructure.

## Problem Statement

Hug SCM needs a robust automated testing strategy to:
- Ensure command behavior remains consistent across changes
- Prevent regressions when adding new features
- Validate error handling and edge cases
- Support confident refactoring
- Enable continuous integration and deployment
- Document expected behavior through tests

## Constraints

1. **Technology Stack**: The project is primarily Bash scripts
2. **Target Environment**: Linux/macOS with Git 2.23+
3. **Minimal Dependencies**: Should not require heavy testing frameworks
4. **Developer Experience**: Tests should be easy to write and run
5. **CI/CD Integration**: Must work in GitHub Actions
6. **Coverage Needs**: Need to test both individual commands and integration scenarios

## Options Considered

### Option 1: Bash Testing Framework (BATS - Bash Automated Testing System)

**Description**: Use BATS (Bash Automated Testing System), a TAP-compliant testing framework designed specifically for Bash scripts.

**Pros**:
- ✅ **Native Bash**: Written in Bash, perfect match for our codebase
- ✅ **TAP Output**: Standard Test Anything Protocol output
- ✅ **Simple Syntax**: Test blocks are straightforward `@test "description" { ... }`
- ✅ **Mature & Stable**: Well-established project with active community
- ✅ **Excellent Documentation**: Comprehensive guides and examples
- ✅ **Helper Libraries**: BATS-support, BATS-assert, BATS-file libraries available
- ✅ **Mocking Support**: Can mock external commands and functions
- ✅ **CI/CD Ready**: Easy to integrate with GitHub Actions
- ✅ **Parallel Execution**: Supports running tests in parallel for speed
- ✅ **Minimal Setup**: Single binary installation, no complex dependencies

**Cons**:
- ⚠️ Requires installation of BATS (but this is trivial in CI)
- ⚠️ Learning curve for team members unfamiliar with BATS syntax

**Example Test**:
```bash
@test "hug s shows status" {
  run hug s
  assert_success
  assert_output --partial "working tree"
}
```

**CI Integration**: Simple GitHub Actions setup with bats-core/bats-action

---

### Option 2: ShUnit2

**Description**: xUnit-based unit test framework for Bourne-based shell scripts.

**Pros**:
- ✅ xUnit-style testing familiar to many developers
- ✅ Works with sh, bash, dash, ksh, zsh
- ✅ Lightweight single-file framework
- ✅ Setup/teardown support

**Cons**:
- ⚠️ Less active development than BATS
- ⚠️ More verbose test syntax
- ⚠️ Smaller community and fewer resources
- ⚠️ No built-in helpers for common assertions
- ⚠️ Less intuitive output format

**Example Test**:
```bash
testHugStatus() {
  output=$(hug s)
  assertEquals "should succeed" 0 $?
  assertContains "$output" "working tree"
}
```

---

### Option 3: Custom Shell Script Testing

**Description**: Write custom test scripts without a framework, using simple Bash conditionals.

**Pros**:
- ✅ No external dependencies
- ✅ Complete control over test execution
- ✅ Simplest possible approach

**Cons**:
- ❌ Reinventing the wheel
- ❌ No standardized output format
- ❌ Difficult to integrate with CI/CD tools
- ❌ No test discovery or automatic execution
- ❌ Manual assertion handling
- ❌ Harder to maintain as test suite grows
- ❌ Poor error reporting and debugging
- ❌ No test isolation or cleanup mechanisms

**Example Test**:
```bash
#!/bin/bash
test_hug_status() {
  output=$(hug s)
  if [ $? -ne 0 ]; then
    echo "FAIL: hug s should succeed"
    return 1
  fi
  if ! echo "$output" | grep -q "working tree"; then
    echo "FAIL: output should contain 'working tree'"
    return 1
  fi
  echo "PASS: hug status works"
}
```

---

### Option 4: Python-Based Testing (pytest + subprocess)

**Description**: Use Python's pytest framework to execute and validate Bash commands.

**Pros**:
- ✅ Powerful assertion library
- ✅ Excellent test discovery and reporting
- ✅ Rich plugin ecosystem
- ✅ Familiar to many developers
- ✅ Great CI/CD integration

**Cons**:
- ❌ Introduces Python dependency for a Bash project
- ❌ Tests would be in different language than implementation
- ❌ More complex setup and configuration
- ❌ Heavier dependency footprint
- ❌ Less natural for testing shell scripts
- ❌ Potential environment mismatch issues

**Example Test**:
```python
def test_hug_status(tmp_repo):
    result = subprocess.run(['hug', 's'], capture_output=True, text=True)
    assert result.returncode == 0
    assert 'working tree' in result.stdout
```

---

### Option 5: Docker-Based End-to-End Testing

**Description**: Run complete end-to-end tests in isolated Docker containers.

**Pros**:
- ✅ Complete isolation
- ✅ Reproducible environments
- ✅ Can test installation procedures
- ✅ Tests real-world scenarios

**Cons**:
- ❌ Overkill for unit testing individual commands
- ❌ Slower test execution
- ❌ More complex setup and maintenance
- ❌ Requires Docker in CI environment
- ❌ Higher resource consumption
- ❌ Should be used in addition to, not instead of, unit tests

---

## Decision

**We will adopt Option 1: BATS (Bash Automated Testing System) as our primary testing framework.**

This will be implemented with the following structure:
```
tests/
├── test_helper.bash          # Common test utilities and setup
├── unit/                     # Unit tests for individual commands
│   ├── test_status.bats
│   ├── test_staging.bats
│   ├── test_head.bats
│   └── test_working_dir.bats
├── integration/              # Integration tests
│   ├── test_workflow.bats
│   └── test_safety.bats
└── fixtures/                 # Test data and mock repos
    └── sample_repo/
```

### Rationale

1. **Perfect Fit**: BATS is specifically designed for testing Bash scripts, making it the most natural choice for our Bash-based codebase.

2. **Developer Experience**: BATS provides a clean, readable test syntax that's easy to write and maintain. Tests read almost like documentation.

3. **Industry Standard**: BATS is widely used in the Bash/shell scripting community and has proven itself in production environments (used by Docker, Homebrew, and many other projects).

4. **Comprehensive Tooling**: The BATS ecosystem includes helper libraries (bats-assert, bats-support, bats-file) that provide rich assertion capabilities out of the box.

5. **CI/CD Integration**: GitHub Actions has first-class support for BATS through the official bats-core/bats-action, making CI integration trivial.

6. **Minimal Overhead**: BATS adds minimal complexity to the project while providing professional-grade testing capabilities.

7. **Flexibility**: BATS works well for both unit tests (individual command testing) and integration tests (workflow scenarios), covering all our testing needs.

8. **Debugging Support**: BATS provides excellent error messages and supports debugging with standard Bash debugging tools.

9. **Future-Proof**: Active development and strong community ensure long-term viability.

10. **Minimal Dependencies**: BATS itself has minimal dependencies and can be easily installed in any environment.

### Why Not Other Options?

- **ShUnit2**: Less active, smaller community, more verbose
- **Custom Scripts**: Too much effort to build what BATS already provides reliably
- **Python/pytest**: Language mismatch; adds unnecessary complexity
- **Docker E2E**: Too heavy for primary testing; may be added later for specific scenarios

## Implementation Plan

### Phase 1: Foundation (Immediate)
1. ✅ Document decision in ADR
2. Install BATS and helper libraries
3. Create test directory structure
4. Write test helper utilities
5. Create sample tests for 2-3 core commands
6. Set up GitHub Actions workflow for running tests

### Phase 2: Core Coverage (Next Sprint)
1. Write unit tests for all status/staging commands
2. Write unit tests for working directory commands
3. Write unit tests for HEAD operations
4. Write unit tests for branch operations
5. Add integration tests for common workflows

### Phase 3: Complete Coverage (Ongoing)
1. Achieve >80% command coverage
2. Add edge case and error handling tests
3. Add performance/regression tests
4. Document testing guidelines for contributors
5. Add pre-commit hooks (optional)

### Phase 4: Enhancement (Future)
1. Add mutation testing to verify test quality
2. Consider adding Docker-based E2E tests for installation verification
3. Add coverage reporting
4. Performance benchmarking suite

## Metrics for Success

- All new commands must include tests
- Tests run in < 30 seconds in CI
- >80% command coverage within 3 months
- Zero regression bugs in tested commands
- Contributors can add tests without assistance

## References

- [BATS GitHub](https://github.com/bats-core/bats-core)
- [BATS Tutorial](https://bats-core.readthedocs.io/en/stable/)
- [bats-assert](https://github.com/bats-core/bats-assert)
- [bats-support](https://github.com/bats-core/bats-support)
- [bats-file](https://github.com/bats-core/bats-file)

## Revision History

- 2025-10-22: Initial decision document created
