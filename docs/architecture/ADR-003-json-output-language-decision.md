# ADR-003: JSON Output Language Decision

## Status

Accepted

## Context

Hug SCM includes JSON output functionality for machine-readable data from commands like:
- `hug s --json` (status)
- `hug lf --json` (commit message search)
- `hug lc --json` (code search)
- `hug bll --json` (branch listing)

The current implementation uses pure Bash for JSON serialization, with questions about whether to migrate to Python for better JSON handling.

## Decision

**Keep JSON output in pure Bash** with specific quality improvements and migration criteria.

### Rationale

#### 1. Architectural Alignment
- **Zero Dependencies**: Hug CLI aims for dependency-free operation
- **Language Boundaries**: Bash for CLI/IO, Python for computational analysis
- **Performance**: Bash has faster startup for simple data transformation tasks
- **Portability**: Bash works consistently across platforms without Python requirement

#### 2. Current Use Case Analysis
JSON output in Hug serves **data formatting**, not **computation**:
```bash
# Current JSON operations (simple transformation):
Git text output → Parse fields → Format JSON
# NOT complex analysis (which already uses Python):
Git history → Statistical analysis → Insights
```

#### 3. Implementation Quality
Existing Bash JSON implementation is functional but needs improvements:
- **Escaping**: Partial Unicode support, missing control character handling
- **Arrays**: Fragile `IFS=,` patterns, no empty array handling
- **Duplication**: Status JSON duplicated across bin/lib files
- **Performance**: Per-commit `git show` calls in search operations

## Detailed Decision

### Keep in Bash (Primary)
**JSON output stays in Bash with these improvements:**

1. **Enhanced JSON Library** (`hug-json`):
   - Full Unicode character support
   - Proper control character escaping
   - Safe empty array handling
   - Better error messages

2. **Consolidated Implementation**:
   - Create `hug-git-json` for shared Git parsing
   - Eliminate duplication in status output
   - Extract common patterns (status mapping, file parsing)

3. **Performance Optimizations**:
   - Batch Git operations instead of per-commit calls
   - Stream large outputs instead of building huge arrays
   - Optimize parsing with single-pass processing

4. **Comprehensive Testing**:
   - Edge case coverage (Unicode, special characters, empty states)
   - Performance testing for large repositories
   - Error condition validation

### Python Migration Criteria (Future)
**Convert to Python when ANY of these thresholds are met:**

1. **Complexity Threshold**:
   - JSON codebase > 1000 LOC
   - >5 distinct JSON output modules

2. **Performance Threshold**:
   - Operations consistently >1 second for typical repos
   - Memory usage issues with large data sets

3. **Maintainability Threshold**:
   - Frequent escaping/format bugs (3+ in 6 months)
   - Complex JSON schema validation needed
   - Need for advanced JSON features (schemas, custom serialization)

4. **Feature Threshold**:
   - Integration with Python analytics libraries
   - Real-time JSON transformation pipelines
   - Complex data aggregation beyond simple counts/summaries

### Hybrid Approach (Interim)
**Strategic Python usage for complex cases:**

```bash
# Simple cases (stay Bash):
hug s --json                    # File listing, counts
hug lf "term" --json           # Basic commit search

# Complex cases (use Python):
hug lf "term" --json --stats    # Add commit frequency analysis
hug analyze deps --json         # Dependency graphs (already Python)
```

## Consequences

### Positive
- **Consistency**: Aligns with Hug's dependency-free philosophy
- **Performance**: Faster startup for simple JSON operations
- **Maintainability**: Clear boundaries between Bash/Python responsibilities
- **User Experience**: No Python dependency required for basic JSON output
- **Incremental Migration**: Clear criteria when to move to Python

### Negative
- **Maintenance**: Requires careful Bash JSON library maintenance
- **Edge Cases**: Bash string handling less robust than Python's native JSON
- **Testing**: More comprehensive testing needed for Bash edge cases
- **Complexity**: Dual implementation approach during transition

### Neutral
- **Learning Curve**: Team needs to understand language boundary decisions
- **Code Reviews**: Need to validate both Bash and Python code quality

## Implementation Plan

### Phase 1: Quality Improvements (Completed)
- ✅ Enhanced `hug-json` with Unicode and control character support
- ✅ Safe empty array handling
- ✅ Fixed array concatenation bugs
- ✅ Added comprehensive error handling

### Phase 2: Consolidation (Completed)
- ✅ Created `hug-git-json` for shared Git JSON patterns
- ✅ Merged duplicate status implementations
- ✅ Extracted common parsing functions
- ✅ Optimized commit search with batch operations

### Phase 3: Testing (Completed)
- ✅ Comprehensive edge case BATS tests
- ✅ Unicode and special character validation
- ✅ Performance testing for large operations
- ✅ Error condition coverage

### Phase 4: Monitoring (Ongoing)
- 🔄 Track bug reports in JSON handling
- 🔄 Monitor performance for large repositories
- 🔄 Measure code complexity metrics
- 🔄 Evaluate against migration criteria quarterly

## Migration Path

If migration criteria are met:

1. **Phase 1**: Create `git-config/lib/python/output_json.py`
2. **Phase 2**: Implement parallel Python functions
3. **Phase 3**: Add environment variable `HUG_JSON_PYTHON=1` for toggle
4. **Phase 4**: Gradual migration with feature flags
5. **Phase 5**: Remove Bash implementation after validation

## Documentation Updates

- **Library Documentation**: Updated `git-config/lib/README.md` with JSON patterns
- **Design Philosophy**: Clear guidance on Bash vs Python boundaries
- **Migration Guide**: Documented criteria and process for future migration
- **Testing**: Added comprehensive JSON edge case tests

## References

- [ADR-001: Automated Testing Strategy](ADR-001-automated-testing-strategy.md)
- [ADR-002: Mercurial Support Architecture](ADR-002-mercurial-support-architecture.md)
- [JSON Output Roadmap](../planning/json-output-roadmap.md)
- [Testing Strategy](../../TESTING.md)
- [Python Helpers Documentation](../../git-config/lib/python/README.md)

---

**Decision Date**: 2025-11-19
**Status**: Accepted
**Implementer**: Claude
**Reviewers**: TBD
**Next Review**: 2026-05-19 (6-month evaluation)