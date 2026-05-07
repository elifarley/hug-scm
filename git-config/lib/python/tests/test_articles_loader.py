"""Tests for articles_loader.py — `hug help :<article>` engine."""

from pathlib import Path

import pytest

from articles_loader import (
    ArticleMeta,
    load_articles,
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


class TestLoadArticles:
    """Loader returns ArticleMeta list sorted by order, then slug."""

    def test_loads_all_md_files(self):
        articles = load_articles(FIXTURES)
        slugs = [a.slug for a in articles]
        assert slugs == ["hug-test", "zzz-second"]  # order=10 then order=20

    def test_default_order_falls_back_to_alpha(self, tmp_path):
        # Two articles with same default order → alphabetical by slug.
        (tmp_path / "bbb.md").write_text(
            '+++\ntitle = "B"\nsummary = "b"\n+++\n\n# B\n'
        )
        (tmp_path / "aaa.md").write_text(
            '+++\ntitle = "A"\nsummary = "a"\n+++\n\n# A\n'
        )
        articles = load_articles(tmp_path)
        assert [a.slug for a in articles] == ["aaa", "bbb"]

    def test_empty_dir(self, tmp_path):
        assert load_articles(tmp_path) == []

    def test_missing_dir(self, tmp_path):
        # Missing dir is treated as empty (articles are an opt-in feature).
        assert load_articles(tmp_path / "nope") == []

    def test_propagates_parse_errors(self):
        # The loader iterates files alphabetically; long_summary.md sorts
        # before missing_title.md, so the first error is the summary-length
        # violation. What matters is that *some* parse error propagates — the
        # loader must not swallow individual file failures.
        with pytest.raises(ValueError, match="exceeds"):
            load_articles(BAD)
