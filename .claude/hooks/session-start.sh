#!/bin/bash
# session-start.sh (About Fishing F1 cloud work; Cloud, 2026-10-07)
# SessionStart hook for Claude Code cloud sessions on adriyunn/roblox: installs the Luau CLI (the
# offline gate), Blender as a Python module (bpy, for the asset generators) and Pillow (preview
# strips), then proves each works. Idempotent: every step checks before it installs. Runs only in a
# cloud session (CLAUDE_CODE_REMOTE=true); on a local machine it exits at once.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
BIN="$HOME/.local/bin"
mkdir -p "$BIN"

# 1. The Luau CLI: luau, luau-compile, luau-analyze, luau-ast
if ! command -v luau >/dev/null 2>&1 && [ ! -x "$BIN/luau" ]; then
  echo "[session-start] installing the Luau CLI into $BIN"
  PREFIX="$BIN" bash "$ROOT/cloud_work/tools/setup_luau.sh"
else
  echo "[session-start] Luau CLI present"
fi
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "export PATH=\"$BIN:\$PATH\"" >> "${CLAUDE_ENV_FILE:-/dev/null}"; export PATH="$BIN:$PATH" ;;
esac

# 2. Python extras: bpy (Blender 5.x as a module, ~300 MB, cached with the container) and Pillow.
#    A failed download must not block the session: the gate does not need either.
if ! python3 -c "import bpy" >/dev/null 2>&1; then
  echo "[session-start] installing bpy (Blender as a Python module)"
  pip install --quiet --disable-pip-version-check bpy || echo "[session-start] WARNING: bpy install failed; Blender scripts will not run"
else
  echo "[session-start] bpy present"
fi
if ! python3 -c "import PIL" >/dev/null 2>&1; then
  pip install --quiet --disable-pip-version-check pillow || echo "[session-start] WARNING: pillow install failed"
fi

# 3. Prove the gate's tools answer
printf 'print("luau ok")\n' > /tmp/_probe.luau
luau /tmp/_probe.luau
luau-compile --null /tmp/_probe.luau >/dev/null
python3 -c "import bpy; print('bpy', bpy.app.version_string)" 2>/dev/null || true
echo "[session-start] done. Gate: bash cloud_work/tests/run_all.sh"
