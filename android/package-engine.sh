#!/usr/bin/env bash
# Packs the engine data the Android app needs (Red Alert only) into one zip asset.
# The app unpacks it to its private storage on first launch.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="$ROOT/android/OpenRA.Android/Assets"
STAGE="$ROOT/build/engine-stage"
VERSION="${OPENRA_VERSION:-$(cd "$ROOT" && git describe --tags --always 2>/dev/null || echo dev)}"
ENGINE_VERSION="${ENGINE_VERSION:-release-20250330}"

rm -rf "$STAGE"
mkdir -p "$STAGE/mods" "$ASSETS"

cp -r "$ROOT/glsl" "$STAGE/"
cp "$ROOT/global mix database.dat" "$ROOT/VERSION" "$ROOT/COPYING" "$ROOT/AUTHORS" "$STAGE/"
for mod in common common-content ra ra-content; do
	cp -r "$ROOT/mods/$mod" "$STAGE/mods/"
done

# Stamp the release version (as `make version` does) so maps and servers match release-20250330.
sed -i "s/{DEV_VERSION}/$ENGINE_VERSION/g" "$STAGE/VERSION" "$STAGE"/mods/*/mod.yaml

rm -f "$ASSETS/engine.zip"
(cd "$STAGE" && zip -qr -9 "$ASSETS/engine.zip" .)
echo "$ENGINE_VERSION+$VERSION" > "$ASSETS/engine.version"

echo "engine.zip: $(du -h "$ASSETS/engine.zip" | cut -f1), version $(cat "$ASSETS/engine.version")"
