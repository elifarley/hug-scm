"""Tests for articles_loader.py — `hug help :<article>` engine."""

from pathlib import Path

import pytest

from articles_loader import (
    ArticleMeta,
    parse_article,
)

FIXTURES = Path(__file__).parent / "fixtures" / "articles"
BAD = Path(__file__).parent / "fixtures" / "articles_bad"


class TestParseArticle:
    """Frontmatter parser: +++ TOML +++ then markdown body."""

    def test_happy_path(self):
        meta = parse_article(FIXTURES / "hug-test.md")
        assert isinstance(meta, ArticleMeta)
        assert meta.slug == "hug-test"
        assert meta.title == "Hug test article"
        assert meta.summary == "Fixture article for unit tests."
        assert meta.order == 10
        assert meta.body.startswith("# Hug test article")
        assert "Subsection" in meta.body
        # Guard the contract: parse_article must store the original Path so
        # error messages and future --explain output can show the file source.
        assert meta.path == FIXTURES / "hug-test.md"

    def test_missing_fences_raises(self):
        with pytest.raises(ValueError, match="frontmatter"):
            parse_article(BAD / "no_fences.md")

    def test_missing_title_raises(self):
        with pytest.raises(ValueError, match="title"):
            parse_article(BAD / "missing_title.md")

    def test_long_summary_raises(self):
        # Match "exceeds" rather than "summary" so this test catches only the
        # length-exceeded error and not a spurious "missing 'summary'" failure.
        with pytest.raises(ValueError, match="exceeds"):
            parse_article(BAD / "long_summary.md")

    def test_default_order_when_absent(self, tmp_path):
        p = tmp_path / "x.md"
        p.write_text('+++\ntitle   = "X"\nsummary = "S"\n+++\n\n# X\n')
        meta = parse_article(p)
        assert meta.order == 100
        assert meta.slug == "x"
