#!/bin/bash
# Wraps the release binary into build/ShotStash.app and signs it.
# Override the identity with SHOTSTASH_SIGN_IDENTITY, or set it to "-" for ad-hoc.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/.build/release/ShotStash"
APP="$ROOT/build/ShotStash.app"
BUNDLE_ID="com.roscodetech.shotstash"

[ -x "$BIN" ] || { echo "Release binary missing. Run: swift build -c release" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ShotStash"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

IDENTITY="${SHOTSTASH_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"' || true)"
fi
if [ -z "$IDENTITY" ]; then
  echo "No Apple Development identity found; signing ad-hoc (Screen Recording permission will re-prompt after each rebuild)." >&2
  IDENTITY="-"
fi

codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$APP"
codesign --verify --verbose=2 "$APP"
echo "Bundled: $APP (signed with: $IDENTITY)"
