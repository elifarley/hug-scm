# Python Tests — git-config/lib/python/tests

## Running tests

```bash
# Via Makefile (recommended — handles venv + extras automatically)
make test-lib-py

# Specific test file
make test-lib-py TEST_FILTER=test_help_search

# Direct invocation (if you need flags the Makefile doesn't pass)
cd git-config/lib/python
uv run --extra dev --extra search pytest tests/test_help_search.py -v
```

**Critical:** The `--extra search` flag is required because `help_search.py` uses `thefuzz` for fuzzy matching (optional `[search]` dependency in `pyproject.toml`). Without it, two fuzzy-match tests fail:
- `test_fuzzy_match` — tests typo tolerance (`"undoo"` → `"h undo"`)
- `test_fuzzy_match_category` — tests typo tolerance (`"brnaching"` → `"branching"`)

The module has a substring-only fallback when thefuzz is missing, but these tests specifically exercise fuzzy matching.

## Test files

| File | What it tests |
|------|---------------|
| `test_help_search.py` | Topic search for `hug help` (/keyword, @category, !intent) |
| `test_search.py` | General search utilities |
| Other `test_*.py` | Git analysis helpers (churn, ownership, co-changes, etc.) |

## help_search.py test categories

- **TestDeriveCommandName** — Command name derivation from script filenames (gateway rules for `h-*`, `w-*`)
- **TestParseDescription** — Extracting one-line descriptions from `--help` output
- **TestCollectMetadata** — Collecting metadata from scripts via `--search-meta` + `--help`
- **TestSearchKeyword** — Fuzzy keyword search across descriptions and command names
- **TestSearchCategory** — Category filtering with strict fuzzy matching (`ratio()`)
- **TestCache** — mtime-based cache invalidation

## Integration tests

See `tests/integration/test_help_topic_search.bats` (13 BATS tests) for end-to-end testing of the `/ @ !` sigils through `hug help`.
