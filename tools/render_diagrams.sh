#!/usr/bin/env bash
# Render every committed Mermaid .mmd under */diagrams/ to a committed SVG with a
# baked-in opaque background (light -> white, dark -> #0d1117), deterministically.
# Run after `python tools/gen_er_diagrams.py --write`. Requires mermaid-cli (mmdc).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CFG="$ROOT/tools/mermaid-config.json"
# Puppeteer needs --no-sandbox to launch Chromium inside CI containers; harmless locally.
# Do NOT suppress stderr (a swallowed Chromium launch error is a silent CI failure).
PUPPETEER="$ROOT/tools/puppeteer-config.json"
n=0
skipped=0
while IFS= read -r mmd; do
  svg="${mmd%.mmd}.svg"
  # Incremental: skip if the .svg already stamps THIS .mmd's sha, so re-running only
  # re-renders CHANGED diagrams (cheap, and CI auto-render never churns unchanged SVGs).
  if [ -f "$svg" ]; then
    cur=$(python3 -c "import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$mmd")
    if grep -q "ordm-mmd-sha:$cur" "$svg" 2>/dev/null; then skipped=$((skipped+1)); continue; fi
  fi
  mmdc -i "$mmd" -o "$svg" -c "$CFG" -p "$PUPPETEER" >/dev/null
  case "$mmd" in *.dark.mmd) bg="#0d1117";; *) bg="#ffffff";; esac
  # Bake the opaque background AND stamp the source .mmd's sha so a stale snapshot is
  # detectable (tools/check_diagram_svgs.py), not silent (#53 M1).
  python3 - "$svg" "$bg" "$mmd" <<'PY'
import re, sys, hashlib
svg, bg, mmd = sys.argv[1], sys.argv[2], sys.argv[3]
sha = hashlib.sha256(open(mmd, "rb").read()).hexdigest()
s = open(svg).read()
if "ordm-bg-rect" not in s:
    inj = (f'<rect id="ordm-bg-rect" x="0" y="0" width="100%" height="100%" fill="{bg}"/>'
           f'<!--ordm-mmd-sha:{sha}-->')
    s = re.sub(r'(<svg\b[^>]*>)', r'\1' + inj, s, count=1)
    open(svg, "w").write(s)
PY
  n=$((n+1))
done < <(find "$ROOT/docs/diagrams" "$ROOT/canonical-core" "$ROOT/outcome-packages" -path '*/diagrams/*.mmd' | sort)
echo "rendered $n SVGs (skipped $skipped already fresh)"
