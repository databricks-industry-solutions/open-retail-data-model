"""The teardown helper refuses unless the bundle it found is this repository's, so its
bundle-name check must keep matching databricks.yml."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_cleanup_bundle_name_check_matches_databricks_yml():
    script = (ROOT / "runtime" / "examples" / "deploy-with-dab" / "cleanup.sh").read_text()
    m = re.search(r"grep -q '([^']+)' databricks\.yml", script)
    assert m, "cleanup.sh no longer checks the bundle name in databricks.yml"
    assert re.search(m.group(1), (ROOT / "databricks.yml").read_text(), re.M), (
        f"databricks.yml does not match cleanup.sh's bundle-name check {m.group(1)!r}; "
        "update one so teardown does not refuse this repository's own bundle")
