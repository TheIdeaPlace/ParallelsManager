#!/usr/bin/env bash
# build.sh — Build Parallels Manager.app for Apple silicon and sign it with
# Developer ID. (Apple silicon only, like the other Mac apps: Xcode has
# deprecated Intel builds, and macOS 27 runs only on Apple silicon.)
#
# Usage: ./build.sh [--skip-sign]
# Output: ./build/Parallels Manager.app
#
#   SIGN_ID    signing identity (default: Kelly's Developer ID Application)
#   KEYCHAIN   keychain holding it (default: the login keychain; the release
#              workflow passes its throwaway one)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Parallels Manager"
BUNDLE_ID="com.kellyford.parallels-manager"
SIGN_ID="${SIGN_ID:-Developer ID Application: Kelly Ford (P887QF74N8)}"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
RESOURCES_SRC="$SCRIPT_DIR/Sources/ParallelsManager/Resources"
SKIP_SIGN=false

for arg in "$@"; do
  [[ "$arg" == "--skip-sign" ]] && SKIP_SIGN=true
done

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$SCRIPT_DIR/Info.plist")
echo "==> Building $APP_NAME $VERSION"
cd "$SCRIPT_DIR"
swift build -c release --arch arm64 2>&1

BIN="$(swift build -c release --arch arm64 --show-bin-path)/ParallelsManager"
if [[ ! -f "$BIN" ]]; then
  echo "ERROR: binary not found at $BIN" >&2
  exit 1
fi
echo "    $(lipo -info "$BIN" | sed 's/.*: //')"

echo "==> Assembling app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN" "$APP_BUNDLE/Contents/MacOS/ParallelsManager"
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# The install scripts the New VM dialogs run (Bundle.main finds them here).
for script in "$RESOURCES_SRC"/*.sh "$RESOURCES_SRC"/*.command; do
  [[ -f "$script" ]] || continue
  cp "$script" "$APP_BUNDLE/Contents/Resources/"
  chmod +x "$APP_BUNDLE/Contents/Resources/$(basename "$script")"
done

# Strip quarantine and Finder metadata, which codesign rejects.
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

if $SKIP_SIGN; then
  echo "==> Skipping code signing (--skip-sign)"
else
  echo "==> Signing with: $SIGN_ID"
  # The bundle as a whole, with the hardened runtime notarization requires.
  # Not --deep: the bundle has one executable, and --deep is the wrong tool
  # for anything bigger.
  KEYCHAIN_ARGS=()
  [[ -n "${KEYCHAIN:-}" ]] && KEYCHAIN_ARGS=(--keychain "$KEYCHAIN")
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$SIGN_ID" \
    --identifier "$BUNDLE_ID" \
    ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} \
    "$APP_BUNDLE"
  echo "==> Verifying signature"
  codesign --verify --strict --verbose=2 "$APP_BUNDLE"
fi

echo ""
echo "Done: $APP_BUNDLE"
echo "      Binary: $(du -sh "$APP_BUNDLE/Contents/MacOS/ParallelsManager" | cut -f1)"
