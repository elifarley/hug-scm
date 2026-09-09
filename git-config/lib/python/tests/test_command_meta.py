"""Tests for command_meta: registry loading, validation, drift guarantees.

Drift 2b note: we assert git-hughelp's SOURCE form (the -x existence test and
the $dir/-prefixed invocation), NOT exec-path/PATH probes — registry names MAY
collide with git-core dashed builtins (fetch does) by design.
"""

import re
from pathlib import Path

import pytest

from command_meta import REQUIRED_FIELDS, RegistryError, load_commands

REPO = Path(__file__).resolve().parents[4]
PY_DIR = REPO / "git-config" / "lib" / "python"
CATS = PY_DIR / "categories"
GITCONFIG = REPO / "git-config" / ".gitconfig"
HUGHELP = REPO / "git-config" / "bin" / "git-hughelp"
BIN = REPO / "git-config" / "bin"

REQUIRED = {"kind", "description", "keywords", "categories", "git_equivalent", "usage", "related"}
# The literal set above must EXACTLY mirror the loader's REQUIRED_FIELDS —
# a new loader field must consciously update this pin (and its truthiness
# row below), never drift silently.
assert set(REQUIRED_FIELDS) == REQUIRED


@pytest.fixture(scope="module")
def registry():
    return load_commands(categories_dir=CATS, bin_dir=BIN, gitconfig=GITCONFIG)


def test_loads_seven_entries(registry):
    assert set(registry) == {"fetch", "bpull", "bpullr", "pullall", "tpull", "tpullf", "bs"}


def test_every_entry_has_required_fields(registry):
    # String fields must be TRUTHY (catches 'usage = ""'-style regressions);
    # list fields must be non-empty lists (catches silently emptied arrays).
    # "summary" is DERIVED from description (not a REQUIRED_FIELDS member),
    # but it is the card/listing line — so it is truthiness-checked too via
    # the REQUIRED | {"summary"} iteration.
    strings = {"kind", "description", "summary", "git_equivalent", "usage"}
    for name, cmd in registry.items():
        for field in REQUIRED | {"summary"}:
            value = getattr(cmd, field)
            if field in strings:
                assert isinstance(value, str) and value.strip(), (name, field)
            else:
                assert isinstance(value, list) and value, (name, field)


def test_summary_derived_from_first_sentence(registry):
    assert registry["fetch"].summary.startswith(
        "Download new commits and refs from remotes without merging"
    )
    assert len(registry["bs"].summary) <= 70


def test_name_grammar_rejects_bad_names(tmp_path):
    src = (PY_DIR / "commands.toml").read_text()
    bad = tmp_path / "commands.toml"
    # [Bad_Name] is a VALID TOML bare key that violates the command grammar
    # (uppercase + underscore). The originally drafted '[Bad Name]' (space in
    # a bare key) is INVALID TOML — tomllib fails with a parse error whose
    # message never reaches the grammar check, so 'match="name"' misses.
    bad.write_text(src + '\n[Bad_Name]\nkind = "alias"\n')
    with pytest.raises(RegistryError, match="name"):
        load_commands(path=bad, categories_dir=CATS, bin_dir=BIN, gitconfig=GITCONFIG)


def test_missing_required_field_is_loud(tmp_path):
    # Drop bpull's 'kind' line SPECIFICALLY: 'kind' is also read directly via
    # entry["kind"] after the REQUIRED_FIELDS loop, so dropping it from the
    # tuple would regress to a raw KeyError — a usage-only drop could never
    # catch that. '[bpull]' is unique ('[bpullr]' lacks the closing bracket).
    src = (PY_DIR / "commands.toml").read_text()
    bad = tmp_path / "commands.toml"
    bad.write_text(src.replace('[bpull]\nkind = "alias"\n', "[bpull]\n", 1))
    with pytest.raises(RegistryError, match="kind"):
        load_commands(path=bad, categories_dir=CATS, bin_dir=BIN, gitconfig=GITCONFIG)


def test_empty_git_equivalent_is_loud(tmp_path):
    # Presence-only validation would let `git_equivalent = ""` reach the card
    # as `Full flags: git help ` at exit 0 — the loader must reject it loudly
    # (consumer-facing: card mode maps RegistryError to exit >=2). Pins the
    # non-empty-string check on git_equivalent; `usage` shares the same loop.
    src = (PY_DIR / "commands.toml").read_text()
    bad = tmp_path / "commands.toml"
    bad.write_text(src.replace('git_equivalent = "git fetch"', 'git_equivalent = ""', 1))
    with pytest.raises(RegistryError, match="git_equivalent"):
        load_commands(path=bad, categories_dir=CATS, bin_dir=BIN, gitconfig=GITCONFIG)


def test_array_elements_must_be_strings(tmp_path):
    # `keywords = [1, true]` passes an isinstance(list) check but would
    # pollute search via str-coercion downstream; every element must be a
    # string, rejected with table+field+element-index context.
    src = (PY_DIR / "commands.toml").read_text()
    bad = tmp_path / "commands.toml"
    bad.write_text(
        src.replace(
            'keywords = ["fetch", "download", "sync", "update", "remote", "refs"]',
            "keywords = [1, true]",
            1,
        )
    )
    with pytest.raises(RegistryError, match=r"keywords.*element 0.*got int"):
        load_commands(path=bad, categories_dir=CATS, bin_dir=BIN, gitconfig=GITCONFIG)


def test_nested_array_element_is_loud_not_typeerror(tmp_path):
    # A nested `categories = [["x"]]` used to escape as an uncontextualized
    # TypeError inside set() — it must be a RegistryError instead (the loader
    # fires the element check BEFORE any set()-based category validation).
    src = (PY_DIR / "commands.toml").read_text()
    bad = tmp_path / "commands.toml"
    bad.write_text(src.replace('categories = ["push-pull"]', 'categories = [["x"]]', 1))
    with pytest.raises(RegistryError, match=r"categories.*element 0.*got list"):
        load_commands(path=bad, categories_dir=CATS, bin_dir=BIN, gitconfig=GITCONFIG)


def test_related_resolves_forward_to_later_table(tmp_path):
    # Regression for order-dependent `related` validation (it used to see
    # only processed-so-far registry entries): an entry referencing a LATER
    # table — a passthrough, which has no alias and no bin script — must
    # load cleanly. Probe names use hyphens: the grammar forbids '_'.
    bad = tmp_path / "commands.toml"

    def entry(name: str, kind: str, related: str) -> str:
        return (
            f"[{name}]\n"
            f'kind = "{kind}"\n'
            'description = "Order-dependence regression probe."\n'
            'keywords = ["probe"]\n'
            'categories = ["branching"]\n'
            'git_equivalent = "git status"\n'
            f'usage = "hug {name}"\n'
            f"related = {related}\n\n"
        )

    bad.write_text(
        entry("aaa-first", "alias", '["zzz-later"]') + entry("zzz-later", "passthrough", "[]")
    )
    out = load_commands(path=bad, categories_dir=CATS, bin_dir=BIN, gitconfig=GITCONFIG)
    assert set(out) == {"aaa-first", "zzz-later"}


def test_missing_file_is_loud(tmp_path):
    with pytest.raises(RegistryError):
        load_commands(
            path=tmp_path / "nope.toml", categories_dir=CATS, bin_dir=BIN, gitconfig=GITCONFIG
        )


def test_unknown_category_rejected(tmp_path):
    src = (PY_DIR / "commands.toml").read_text()
    bad = tmp_path / "commands.toml"
    bad.write_text(src.replace('categories = ["push-pull"]', 'categories = ["nope"]', 1))
    with pytest.raises(RegistryError, match="categor"):
        load_commands(path=bad, categories_dir=CATS, bin_dir=BIN, gitconfig=GITCONFIG)


def test_corrupt_toml_is_loud(tmp_path):
    # coverage audit: the unparsable-TOML branch had no pin — only the
    # missing-file path was probed. A syntax-broken registry must die loudly
    # with 'unparsable' context, never degrade to a silent-empty index.
    bad = tmp_path / "commands.toml"
    bad.write_text("[[[not toml\n")
    with pytest.raises(RegistryError, match="unparsable"):
        load_commands(path=bad, categories_dir=CATS, bin_dir=BIN, gitconfig=GITCONFIG)


def test_non_table_entry_is_loud(tmp_path):
    # coverage audit: a top-level scalar key (valid TOML, valid command
    # grammar — no underscore) reaches the isinstance(entry, dict) guard and
    # must be a RegistryError with table context, not a mystery downstream.
    src = (PY_DIR / "commands.toml").read_text()
    bad = tmp_path / "commands.toml"
    bad.write_text("scalar = 1\n\n" + src)
    with pytest.raises(RegistryError, match="table"):
        load_commands(path=bad, categories_dir=CATS, bin_dir=BIN, gitconfig=GITCONFIG)


def test_list_field_string_not_array_is_loud(tmp_path):
    # coverage audit: element-type checks were pinned (int/bool/nested) but
    # the field-level isinstance(value, list) guard was not — the code
    # comment's own hazard (`keywords = "tag"` silently ['t','a','g']) was
    # unpinned. bpull's keywords line is unique (bpullr's differs).
    src = (PY_DIR / "commands.toml").read_text()
    bad = tmp_path / "commands.toml"
    bad.write_text(
        src.replace('keywords = ["pull", "update", "integrate"]', 'keywords = "pull"', 1)
    )
    with pytest.raises(RegistryError, match=r"keywords.*got str"):
        load_commands(path=bad, categories_dir=CATS, bin_dir=BIN, gitconfig=GITCONFIG)


def test_invalid_kind_value_is_loud(tmp_path):
    # coverage audit: only the MISSING-kind path was pinned (which also
    # guards entry["kind"] KeyError). The kind not-in-VALID_KINDS branch —
    # claimed pinned by test_help_search's card-corrupt comment, but that
    # fixture dies earlier on description — gets its own all-fields-valid
    # probe here. [bs]'s kind line is unique enough via its table prefix.
    src = (PY_DIR / "commands.toml").read_text()
    bad = tmp_path / "commands.toml"
    bad.write_text(src.replace('[bs]\nkind = "alias"\n', '[bs]\nkind = "transparent"\n', 1))
    with pytest.raises(RegistryError, match="kind"):
        load_commands(path=bad, categories_dir=CATS, bin_dir=BIN, gitconfig=GITCONFIG)


def test_dangling_related_is_loud(tmp_path):
    # coverage audit: the FORWARD-resolution happy path was pinned, but the
    # rejection branch (related name resolving to no registry entry, bin
    # script, or alias) had no test — the loader's core drift guard.
    src = (PY_DIR / "commands.toml").read_text()
    bad = tmp_path / "commands.toml"
    bad.write_text(src.replace('related = ["b", "bc"]', 'related = ["ghost-cmd"]', 1))
    with pytest.raises(RegistryError, match="related"):
        load_commands(path=bad, categories_dir=CATS, bin_dir=BIN, gitconfig=GITCONFIG)


def test_empty_registry_is_loud(tmp_path):
    # coverage audit: `if not registry` forbids silent-empty — the exact
    # failure the loader exists to prevent — yet was never probed. A
    # comment-only TOML parses fine and must still die loudly.
    bad = tmp_path / "commands.toml"
    bad.write_text("# nothing but comments\n")
    with pytest.raises(RegistryError, match="empty"):
        load_commands(path=bad, categories_dir=CATS, bin_dir=BIN, gitconfig=GITCONFIG)


# ── Drift guarantees ─────────────────────────────────────────────────────


def test_drift1_alias_resolution_and_semantics(registry):
    # Multi-line aliases (tpull, tpullf) use backslash continuations; join
    # them FIRST or the line regex only captures the shell-function opener
    # ('"!f() { \') and the git_equivalent tokens would spuriously "miss".
    raw = GITCONFIG.read_text().replace("\\\n", " ")
    body_by_alias = dict(re.findall(r"^  ([a-z0-9-]+) = (.+)$", raw, re.M))
    for name, cmd in registry.items():
        if cmd.kind != "alias":
            continue
        body = body_by_alias.get(name)
        assert body, f"alias {name} missing from .gitconfig"
        toks = [t for t in cmd.git_equivalent.split() if t != "git"]
        missing = [t for t in toks if t not in body]
        assert not missing, f"{name}: git_equivalent tokens {missing} not in alias body {body!r}"


def test_drift2a_no_hug_bin_shadowing(registry):
    # strip the git- prefix: stem alone yields 'git-bpush', never matching
    # registry keys ('bpush') — the intersection would be vacuously empty.
    scripts = {p.stem.removeprefix("git-") for p in BIN.glob("git-*")}
    assert not (set(registry) & scripts)


def test_drift2b_branch1_is_pathfree_source():
    src = HUGHELP.read_text()
    assert '-x "$dir/git-$prefix"' in src  # existence test on hug's bin dir
    assert '"$dir/git-$prefix" --help' in src  # $dir/-prefixed invocation
