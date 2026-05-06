"""Tests for category_meta.py — per-category metadata loader/validator."""

import pytest

from category_meta import (
    CategoryMeta,
    derive_summary,
    load_categories,
    validate_against_scripts,
)


class TestDeriveSummary:
    """First-sentence truncation matches the @ listing column budget."""

    def test_first_sentence_short(self):
        assert derive_summary("A short sentence. Another one.") == "A short sentence."

    def test_first_sentence_truncated(self):
        long = "A " + "very " * 30 + "long sentence."
        s = derive_summary(long)
        assert len(s) <= 70
        # Truncation should be on a word boundary, ending with an ellipsis.
        assert s.endswith("…")
        assert " " in s

    def test_strips_leading_newlines(self):
        assert derive_summary("\n\n  A sentence.\n  More.") == "A sentence."

    def test_empty_input(self):
        assert derive_summary("") == ""

    def test_no_sentence_terminator(self):
        # No `.!?` in input — treat the whole text as the first "sentence".
        assert derive_summary("just words no terminator") == "just words no terminator"


class TestLoadCategories:
    """Loader reads <name>.toml files; schema is label + description only."""

    @pytest.fixture
    def cat_dir(self, tmp_path):
        d = tmp_path / "categories"
        d.mkdir()
        (d / "branching.toml").write_text(
            'label = "Branch operations"\n'
            'description = """\n'
            "Create, list, switch, and delete branches.\n"
            "Details follow.\n"
            '"""\n'
        )
        (d / "staging.toml").write_text(
            'label = "Staging area"\n'
            'description = "Stage and unstage changes."\n'
        )
        return d

    def test_loads_all_files(self, cat_dir):
        cats = load_categories(cat_dir)
        assert set(cats.keys()) == {"branching", "staging"}

    def test_meta_fields_populated(self, cat_dir):
        cats = load_categories(cat_dir)
        b = cats["branching"]
        assert isinstance(b, CategoryMeta)
        assert b.name == "branching"
        assert b.label == "Branch operations"
        assert "Create, list, switch" in b.description

    def test_summary_derived(self, cat_dir):
        cats = load_categories(cat_dir)
        assert cats["branching"].summary == "Create, list, switch, and delete branches."

    def test_missing_label_raises(self, tmp_path):
        d = tmp_path / "categories"
        d.mkdir()
        (d / "x.toml").write_text('description = "x"\n')
        with pytest.raises(ValueError, match="missing 'label'"):
            load_categories(d)

    def test_missing_description_raises(self, tmp_path):
        d = tmp_path / "categories"
        d.mkdir()
        (d / "x.toml").write_text('label = "X"\n')
        with pytest.raises(ValueError, match="missing 'description'"):
            load_categories(d)


class TestValidateAgainstScripts:
    """Strict policy: each script-declared category must have a manifest."""

    def _meta(self, name):
        return CategoryMeta(name=name, label=name, description="x", summary="x")

    def test_no_errors_when_complete(self):
        cats = {"branching": self._meta("branching"), "staging": self._meta("staging")}
        used = {"branching", "staging"}
        assert validate_against_scripts(cats, used) == []

    def test_error_for_missing_manifest(self):
        cats = {"branching": self._meta("branching")}
        used = {"branching", "flubber"}
        errors = validate_against_scripts(cats, used)
        assert len(errors) == 1
        assert "flubber" in errors[0]
        assert "categories/flubber.toml" in errors[0]

    def test_orphan_manifest_is_warning_not_error(self):
        # Orphans (manifest exists but no script uses it) are silently allowed.
        # They may be placeholders for upcoming commands.
        cats = {"branching": self._meta("branching"), "ghost": self._meta("ghost")}
        used = {"branching"}
        errors = validate_against_scripts(cats, used)
        assert errors == []


class TestRepoIntegrity:
    """Real repo: every category referenced by a real script must have a manifest.

    Runs against the actual git-config/bin scripts and categories TOMLs in this
    repo. Fails CI if a contributor adds a category to a script without
    bootstrapping its manifest.
    """

    def test_all_used_categories_have_manifests(self):
        import re
        from pathlib import Path

        repo_root = Path(__file__).resolve().parents[3]
        bin_dir = repo_root / "git-config" / "bin"
        cat_dir = repo_root / "git-config" / "lib" / "python" / "categories"

        used: set[str] = set()
        for script in bin_dir.glob("git-*"):
            try:
                text = script.read_text(errors="ignore")
            except (OSError, UnicodeDecodeError):
                continue
            m = re.search(r"_hug_category=\'(\[.*?\])\'", text)
            if not m:
                continue
            for raw in re.findall(r'"([^"]+)"', m.group(1)):
                used.add(raw)

        cats = load_categories(cat_dir)
        errors = validate_against_scripts(cats, used)
        assert errors == [], "\n".join(errors)
