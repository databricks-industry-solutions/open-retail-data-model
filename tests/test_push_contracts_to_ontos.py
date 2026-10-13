"""Pin the Ontos contract-push tool (tools/push_contracts_to_ontos.py) so its
selection, discovery, and safety behaviours cannot regress.

These exercise only the pure, offline parts — unit-name parsing, contract
discovery/filtering, multipart body assembly, the TLS-context builder, and the
"no selection pushes nothing" guard. Nothing here opens a socket or shells out:
the network push (`push_one`) and token minting (`resolve_token`) are deliberately
not exercised, matching the import-safe, no-Spark/no-SDK style of the rest of
tests/. Pushing to Ontos is an OPTIONAL ORDM integration.

conftest.py puts the repo root on sys.path.
"""
import ssl

import pytest

import tools.push_contracts_to_ontos as pc
from tools.push_contracts_to_ontos import (
    DEFAULT_CONTRACTS_GLOB,
    _multipart_body,
    _unit_name,
    build_ssl_context,
    find_contracts,
    main,
    push_paths,
)


def _make_contracts(root, names):
    """Create empty <name>.odcs.yaml files under root/contracts/odcs/."""
    d = root / "contracts" / "odcs"
    d.mkdir(parents=True)
    for n in names:
        (d / f"{n}.odcs.yaml").write_text(f"id: ordm-core-{n}\n")
    return d


def test_unit_name_strips_odcs_yaml_suffix():
    assert _unit_name("/x/contracts/odcs/store.odcs.yaml") == "store"
    assert _unit_name("customer.odcs.yaml") == "customer"


def test_find_contracts_all(tmp_path):
    _make_contracts(tmp_path, ["store", "customer", "order"])
    found = find_contracts(str(tmp_path), DEFAULT_CONTRACTS_GLOB, include=None)
    assert sorted(_unit_name(p) for p in found) == ["customer", "order", "store"]


def test_find_contracts_include_filters(tmp_path):
    _make_contracts(tmp_path, ["store", "customer", "order"])
    found = find_contracts(str(tmp_path), DEFAULT_CONTRACTS_GLOB, include=["store", "order"])
    assert sorted(_unit_name(p) for p in found) == ["order", "store"]


def test_find_contracts_include_unknown_raises(tmp_path):
    _make_contracts(tmp_path, ["store"])
    with pytest.raises(SystemExit) as exc:
        find_contracts(str(tmp_path), DEFAULT_CONTRACTS_GLOB, include=["nope"])
    assert "nope" in str(exc.value)


def test_multipart_body_shape():
    body, boundary = _multipart_body("file", "store.odcs.yaml", b"id: x\n")
    assert boundary in body.decode()
    assert b'name="file"; filename="store.odcs.yaml"' in body
    assert body.rstrip().endswith(f"--{boundary}--".encode())


def test_build_ssl_context_is_a_verifying_context():
    ctx = build_ssl_context()
    assert isinstance(ctx, ssl.SSLContext)
    # Verification must never be disabled by this tool.
    assert ctx.verify_mode == ssl.CERT_REQUIRED


def test_no_selection_pushes_nothing(capsys):
    """A bare invocation must select nothing and exit 2 — never fan out to all."""
    rc = main(["--app-url", "https://example.invalid"])
    assert rc == 2
    err = capsys.readouterr().err
    assert "No contracts selected" in err
    assert "--all" in err and "--include" in err


def test_dry_run_all_lists_without_network(tmp_path, capsys):
    _make_contracts(tmp_path, ["store", "customer"])
    rc = main(["--app-url", "https://example.invalid", "--root", str(tmp_path), "--all", "--dry-run"])
    assert rc == 0
    out = capsys.readouterr().out
    assert "would push 2 contract(s)" in out
    assert "store" in out and "customer" in out


def test_push_paths_collects_results_without_network(tmp_path, monkeypatch):
    """push_paths returns one (unit, ok, message) per file and opens no socket."""
    d = _make_contracts(tmp_path, ["store", "customer"])
    paths = sorted(str(p) for p in d.glob("*.odcs.yaml"))

    calls = []

    def fake_push_one(app_url, token, path, timeout, ssl_ctx):
        calls.append(path)
        return (True, f"created id=fake-{_unit_name(path)}")

    monkeypatch.setattr(pc, "push_one", fake_push_one)
    # ssl_ctx=None → push_paths builds a verifying context offline; push_one is mocked
    results = push_paths("https://example.invalid", "tok", paths, timeout=5, ssl_ctx=None)

    assert [u for u, _, _ in results] == ["customer", "store"]
    assert all(ok for _, ok, _ in results)
    assert len(calls) == 2


def test_dry_run_include_subset(tmp_path, capsys):
    _make_contracts(tmp_path, ["store", "customer", "order"])
    rc = main([
        "--app-url", "https://example.invalid", "--root", str(tmp_path),
        "--include", "store", "--dry-run",
    ])
    assert rc == 0
    out = capsys.readouterr().out
    assert "would push 1 contract(s)" in out
    assert "store" in out and "customer" not in out
