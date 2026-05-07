"""Tests for articles_loader.py — `hug help :<article>` engine."""

from pathlib import Path

import pytest

from articles_loader import (
    ArticleMeta,
    find_article,
    format_article_list,
    load_articles,
    parse_article,
    render_article,
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
        # Any file in the bad-fixture dir should cause a ValueError.
        # We don't pin which specific error fires, because that depends on
        # alphabetical ordering of the fixture filenames — adding a new bad
        # fixture later shouldn't break this test. The exact error messages
        # for each failure mode are covered by TestParseArticle.
        with pytest.raises(ValueError):
            load_articles(BAD)


class TestFindArticle:
    """Lookup: exact slug match, else fuzzy suggestions."""

    def test_exact_match(self):
        articles = load_articles(FIXTURES)
        result = find_article(articles, "hug-test")
        assert result.found is not None
        assert result.found.slug == "hug-test"
        # suggestions is a tuple (frozen=True on a list field would still allow
        # mutation; tuple is genuinely immutable).
        assert result.suggestions == ()

    def test_no_match_returns_suggestions(self):
        articles = load_articles(FIXTURES)
        result = find_article(articles, "hug-tst")  # typo
        assert result.found is None
        # Check non-empty first so a missing suggestion gives a clear failure
        # message rather than a silent False from `any()` on an empty sequence.
        assert result.suggestions, "expected at least one suggestion"
        # The closest fuzzy match should rank first.
        assert result.suggestions[0].slug == "hug-test"

    def test_unrelated_query_returns_empty_suggestions(self):
        articles = load_articles(FIXTURES)
        result = find_article(articles, "zzzzzzzzzzz")
        assert result.found is None
        # No fuzzy hits — empty suggestions, caller renders generic
        # "no article" message.
        assert result.suggestions == ()

    def test_empty_articles_list(self):
        # Defensive: empty articles list returns no found, no suggestions.
        result = find_article([], "anything")
        assert result.found is None
        assert result.suggestions == ()


class TestFormatArticleList:
    """Listing format: stdout-safe slug column + summary, stderr chatter separate."""

    def test_listing_includes_slugs_and_summaries(self):
        articles = load_articles(FIXTURES)
        header, body, footer = format_article_list(articles, width=72)
        assert ":hug-test" in body
        assert "Fixture article for unit tests." in body
        assert "Articles" in header
        assert "hug help :<article>" in footer

    def test_empty_listing_message(self):
        header, body, footer = format_article_list([], width=72)
        assert body == ""
        assert "No articles available yet" in header

    def test_slug_column_aligns(self):
        articles = load_articles(FIXTURES)
        _, body, _ = format_article_list(articles, width=72)
        # Both lines should have the em-dash separator at the same column.
        lines = [ln for ln in body.split("\n") if " — " in ln]
        positions = {ln.index(" — ") for ln in lines}
        assert len(positions) == 1, f"slug columns misaligned: {positions}"


class TestRenderArticle:
    """Rendering pipeline: gum format if TTY+available, else raw markdown."""

    def test_non_tty_emits_raw_markdown(self, capsys, monkeypatch):
        # Force stdout.isatty() False so the function takes the pipe-safe path.
        monkeypatch.setattr("sys.stdout.isatty", lambda: False)
        articles = load_articles(FIXTURES)
        render_article(articles[0])  # hug-test
        captured = capsys.readouterr()
        # Body is markdown source — heading marker visible.
        assert "# Hug test article" in captured.out
        # No ANSI escape sequences in pipe-safe path.
        assert "\x1b[" not in captured.out
        # Trailing-newline guard: shell prompt must land on a clean line.
        assert captured.out.endswith("\n"), (
            "stdout must end with newline so shell prompt lands on a clean line"
        )

    def test_tty_without_gum_or_less_falls_back_to_print(
        self, capsys, monkeypatch
    ):
        monkeypatch.setattr("sys.stdout.isatty", lambda: True)
        # No gum, no less → just prints body.
        monkeypatch.setattr("shutil.which", lambda name: None)
        articles = load_articles(FIXTURES)
        render_article(articles[0])
        captured = capsys.readouterr()
        assert "# Hug test article" in captured.out
        # Trailing-newline guard: shell prompt must land on a clean line.
        assert captured.out.endswith("\n"), (
            "stdout must end with newline so shell prompt lands on a clean line"
        )
