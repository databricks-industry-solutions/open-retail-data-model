#!/usr/bin/env python3
# ============================================================
# ORDM · Optional integration · push ODCS contracts to Ontos
# ============================================================
# Pushes ORDM's committed ODCS contracts (contracts/odcs/*.odcs.yaml) into a
# running Ontos deployment (databrickslabs/ontos) via its REST API, so the
# generated contracts show up as Ontos data contracts without a hand copy-paste.
#
# This is an OPTIONAL, one-directional convenience for the ODCS integration
# (see docs/odcs-integration.md). ORDM does not depend on it and nothing in the
# model changes if it is never run. It is a *client* of Ontos — it sends the
# contracts ORDM already generates; it does not modify them.
#
# Transport / auth (verified against a live Databricks Apps deployment):
#   - Ontos runs as a Databricks App behind OBO auth. It accepts a user OAuth
#     bearer token as the caller identity.
#   - We mint that token by shelling out to the Databricks CLI:
#         databricks auth token --profile <PROFILE>
#     so this tool inherits whatever auth the operator already has configured
#     (no secrets handled here). A service principal profile works identically
#     for CI use.
#   - Contracts are POSTed to  /api/data-contracts/upload  (multipart YAML),
#     which is the highest-fidelity ODCS ingest path Ontos exposes today.
#
# Known Ontos-side limitation (NOT this tool's bug): Ontos's importer currently
# drops primary keys and object-level quality rules on ingest. Schema, columns,
# descriptions, domain, and authoritativeDefinitions import correctly. Tracked
# upstream; this tool sends the full contract regardless, so it benefits
# automatically once Ontos is fixed.
#
# Pure Python stdlib (urllib, no requests), matching tools/generate_odcs.py's
# "runs anywhere including CI" property.
#
# TLS behind a corporate proxy: TLS verification is always ON. If you are behind
# TLS interception, Python's default trust store may not carry your proxy's CA
# (curl works because it uses the OS store). Two clean fixes, in preference order:
#   1. `pip install truststore` — if importable, this tool uses the OS trust
#      store automatically (same certs curl trusts). Nothing else to do.
#   2. Export SSL_CERT_FILE=/path/to/your-corp-ca.pem before running.
# The tool never disables verification.
#
# Selection is explicit by design: a bare invocation (no --include / --contracts-glob
# / --all) pushes NOTHING and prints how to select, so it can never silently fire
# every contract at a live Ontos. Push the full set only via the explicit --all.
#
# Usage:
#   python push_contracts_to_ontos.py --app-url <URL> --profile ordm --include store,customer
#   python push_contracts_to_ontos.py --app-url <URL> --profile ordm --all
#   python push_contracts_to_ontos.py --app-url <URL> --profile ordm --all --dry-run
#   python push_contracts_to_ontos.py --app-url <URL> --token-env ONTOS_TOKEN --all   # CI
#
# Exit codes: 0 success · 1 push failure / no glob match · 2 no selection made.
# ============================================================
from __future__ import annotations

import argparse
import glob
import json
import mimetypes
import os
import ssl
import subprocess
import sys
import urllib.error
import urllib.request
import uuid

UPLOAD_PATH = "/api/data-contracts/upload"
DEFAULT_CONTRACTS_GLOB = "contracts/odcs/*.odcs.yaml"


# ---------- TLS ----------------------------------------------------------------

def build_ssl_context() -> ssl.SSLContext:
    """A verifying TLS context that works behind corporate TLS interception.

    Verification is always on. If `truststore` is installed we use the OS trust
    store (the same CAs curl trusts, so an intercepting proxy CA is picked up
    automatically); otherwise we fall back to Python's default context, which
    honours SSL_CERT_FILE / SSL_CERT_DIR if set. We never disable verification.
    """
    try:
        import truststore  # optional; pip install truststore
        return truststore.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    except ImportError:
        return ssl.create_default_context()


# ---------- discovery ----------------------------------------------------------

def find_contracts(root: str, contracts_glob: str, include: list[str] | None) -> list[str]:
    """Return the absolute paths of the ODCS contracts to push.

    `include` filters by unit name (the file stem before `.odcs.yaml`), e.g.
    `store` or `customer`; None means every contract under the glob.
    """
    paths = sorted(glob.glob(os.path.join(root, contracts_glob)))
    if include:
        wanted = {name.strip() for name in include}
        paths = [p for p in paths if _unit_name(p) in wanted]
        missing = wanted - {_unit_name(p) for p in paths}
        if missing:
            raise SystemExit(
                f"--include named units with no contract: {', '.join(sorted(missing))}"
            )
    return paths


def _unit_name(path: str) -> str:
    base = os.path.basename(path)
    return base[: -len(".odcs.yaml")] if base.endswith(".odcs.yaml") else base


# ---------- auth ---------------------------------------------------------------

def resolve_token(profile: str | None, token_env: str | None) -> str:
    """Get an OAuth bearer token.

    Prefer an explicit env var (CI-friendly, no CLI dependency); otherwise mint
    one from the Databricks CLI for the given profile. Kept deliberately simple:
    this tool never stores or logs the token.
    """
    if token_env:
        tok = os.environ.get(token_env)
        if not tok:
            raise SystemExit(f"--token-env {token_env} is set but that env var is empty")
        return tok
    if not profile:
        raise SystemExit("provide either --profile <name> or --token-env <VAR>")
    try:
        out = subprocess.run(
            ["databricks", "auth", "token", "--profile", profile],
            capture_output=True, text=True, timeout=60, check=True,
        ).stdout
    except FileNotFoundError:
        raise SystemExit("databricks CLI not found on PATH; install it or use --token-env")
    except subprocess.CalledProcessError as e:
        raise SystemExit(f"databricks auth token failed for profile '{profile}': {e.stderr.strip()}")
    except subprocess.TimeoutExpired:
        raise SystemExit(f"databricks auth token timed out for profile '{profile}'")
    try:
        return json.loads(out)["access_token"]
    except (json.JSONDecodeError, KeyError):
        raise SystemExit("could not parse access_token from `databricks auth token` output")


# ---------- HTTP (multipart, stdlib only) --------------------------------------

def _multipart_body(field: str, filename: str, content: bytes) -> tuple[bytes, str]:
    """Build a minimal multipart/form-data body for a single file field."""
    boundary = f"----ordm-ontos-{uuid.uuid4().hex}"
    ctype = mimetypes.guess_type(filename)[0] or "application/x-yaml"
    pre = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="{field}"; filename="{filename}"\r\n'
        f"Content-Type: {ctype}\r\n\r\n"
    ).encode("utf-8")
    post = f"\r\n--{boundary}--\r\n".encode("utf-8")
    return pre + content + post, boundary


def push_one(app_url: str, token: str, path: str, timeout: int,
             ssl_ctx: ssl.SSLContext | None = None) -> tuple[bool, str]:
    """POST a single contract file to Ontos. Returns (ok, message)."""
    with open(path, "rb") as fh:
        content = fh.read()
    body, boundary = _multipart_body("file", os.path.basename(path), content)
    req = urllib.request.Request(
        url=app_url.rstrip("/") + UPLOAD_PATH,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ssl_ctx) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
            cid = payload.get("id", "?")
            name = payload.get("name", _unit_name(path))
            return True, f"created id={cid} name={name}"
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:300]
        return False, f"HTTP {e.code}: {detail}"
    except urllib.error.URLError as e:
        hint = ""
        if "CERTIFICATE_VERIFY_FAILED" in str(e.reason):
            hint = (" (TLS interception? `pip install truststore` to use the OS trust store, "
                    "or set SSL_CERT_FILE to your proxy CA bundle)")
        return False, f"connection error: {e.reason}{hint}"
    except json.JSONDecodeError:
        return False, "non-JSON response (auth or routing problem?)"


# ---------- reusable push (importable from a notebook) -------------------------

def push_paths(app_url: str, token: str, paths: list[str], timeout: int = 60,
               ssl_ctx: "ssl.SSLContext | None" = None) -> list[tuple[str, bool, str]]:
    """Push a list of contract files to Ontos; return one (unit, ok, message) per file.

    The importable core the CLI and the Databricks notebook both call. It does no
    printing and no selection logic — callers pick the paths (via `find_contracts`)
    and render the results however they like. `ssl_ctx` defaults to a verifying
    context from `build_ssl_context()`.
    """
    if ssl_ctx is None:
        ssl_ctx = build_ssl_context()
    results: list[tuple[str, bool, str]] = []
    for p in paths:
        ok, msg = push_one(app_url, token, p, timeout, ssl_ctx)
        results.append((_unit_name(p), ok, msg))
    return results


# ---------- main ---------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Push ORDM ODCS contracts into an Ontos deployment.")
    ap.add_argument("--app-url", required=True,
                    help="Ontos app base URL, e.g. https://ontos-....databricksapps.com")
    ap.add_argument("--profile", help="Databricks CLI profile to mint an OAuth token from")
    ap.add_argument("--token-env",
                    help="Env var holding a bearer token instead (CI; takes precedence over --profile)")
    ap.add_argument("--root", default=".", help="Repo root containing contracts/odcs/ (default: cwd)")
    ap.add_argument("--contracts-glob",
                    help=f"Glob selecting the contracts to push (e.g. {DEFAULT_CONTRACTS_GLOB})")
    ap.add_argument("--include",
                    help="Comma-separated unit names to push (e.g. store,customer)")
    ap.add_argument("--all", action="store_true",
                    help=f"Push every contract under {DEFAULT_CONTRACTS_GLOB} (explicit opt-in)")
    ap.add_argument("--timeout", type=int, default=60, help="Per-request timeout seconds (default 60)")
    ap.add_argument("--dry-run", action="store_true",
                    help="List what would be pushed, contact nothing")
    args = ap.parse_args(argv)

    # Safety default: with no explicit selection, push NOTHING. The full set is
    # only sent when the operator opts in via --all (or names a glob/units), so a
    # bare invocation can never silently fire every contract at a live Ontos.
    if not (args.include or args.contracts_glob or args.all):
        print(
            "No contracts selected — nothing was pushed.\n"
            "Choose one of:\n"
            "  --include <units>       e.g. --include store,customer\n"
            f"  --contracts-glob <glob> e.g. --contracts-glob '{DEFAULT_CONTRACTS_GLOB}'\n"
            "  --all                   push every contract (explicit opt-in)\n"
            "Add --dry-run to preview without contacting Ontos.",
            file=sys.stderr,
        )
        return 2

    contracts_glob = args.contracts_glob or DEFAULT_CONTRACTS_GLOB
    include = args.include.split(",") if args.include else None
    contracts = find_contracts(args.root, contracts_glob, include)
    if not contracts:
        print(f"no contracts matched {contracts_glob!r} under {args.root!r}", file=sys.stderr)
        return 1

    if args.dry_run:
        print(f"[dry-run] would push {len(contracts)} contract(s) to {args.app_url}{UPLOAD_PATH}:")
        for p in contracts:
            print(f"  - {_unit_name(p)}  ({p})")
        return 0

    token = resolve_token(args.profile, args.token_env)

    print(f"pushing {len(contracts)} contract(s) to {args.app_url}{UPLOAD_PATH}")
    results = push_paths(args.app_url, token, contracts, args.timeout)
    failures = 0
    for unit, ok, msg in results:
        mark = "OK " if ok else "ERR"
        print(f"  [{mark}] {unit:40s} {msg}")
        if not ok:
            failures += 1

    print(f"done: {len(results) - failures} succeeded, {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
