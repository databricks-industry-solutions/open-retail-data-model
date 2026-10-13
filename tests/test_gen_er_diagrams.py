import subprocess, sys, os, pathlib

import pytest

# Rewrites the diagram sources and READMEs in the checkout: run serially in CI.
pytestmark = pytest.mark.writes_repo

ROOT = pathlib.Path(__file__).resolve().parents[1]

def test_write_then_check_is_clean():
    w = subprocess.run([sys.executable, "tools/gen_er_diagrams.py", "--write"], cwd=ROOT)
    assert w.returncode == 0
    c = subprocess.run([sys.executable, "tools/gen_er_diagrams.py", "--check"], cwd=ROOT)
    assert c.returncode == 0

def test_customer_artifacts_and_picture():
    subprocess.run([sys.executable, "tools/gen_er_diagrams.py", "--write"], cwd=ROOT, check=True)
    assert (ROOT / "canonical-core/customer/diagrams/customer.light.mmd").exists()
    assert (ROOT / "canonical-core/customer/diagrams/customer.dbml").exists()
    readme = (ROOT / "canonical-core/customer/README.md").read_text()
    assert "<picture>" in readme and "customer.dark.svg" in readme
