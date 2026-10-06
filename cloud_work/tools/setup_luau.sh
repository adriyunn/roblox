#!/usr/bin/env bash
# setup_luau.sh (About Fishing F1 cloud work; Cloud, 2026-10-06)
# Installs the Luau command line (luau, luau-analyze, luau-compile, luau-ast) from the official
# GitHub release into $PREFIX (default /usr/local/bin). Linux x64 only; on Windows the team already
# has the CLI at C:\Users\adria\OneDrive\Desktop\Capital Rift\tools\luau\.
# Usage: bash cloud_work/tools/setup_luau.sh [version]   e.g. 0.712 ; default = latest
set -euo pipefail
VERSION="${1:-latest}"
PREFIX="${PREFIX:-/usr/local/bin}"
TMP="$(mktemp -d)"
if [ "$VERSION" = "latest" ]; then
  URL="https://github.com/luau-lang/luau/releases/latest/download/luau-ubuntu.zip"
else
  URL="https://github.com/luau-lang/luau/releases/download/${VERSION}/luau-ubuntu.zip"
fi
echo "downloading $URL"
curl -sSL -o "$TMP/luau.zip" "$URL"
(cd "$TMP" && unzip -o -q luau.zip)
install -m 0755 "$TMP"/luau "$TMP"/luau-analyze "$TMP"/luau-compile "$TMP"/luau-ast "$PREFIX/"
rm -rf "$TMP"
printf 'print("luau ok")\n' > /tmp/_luau_probe.luau && "$PREFIX/luau" /tmp/_luau_probe.luau
echo "installed to $PREFIX"
