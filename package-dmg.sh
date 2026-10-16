#!/usr/bin/env bash
# package-dmg.sh — Build Parallels Manager and package it as a signed,
# optionally notarized, drag-to-Applications disk image.
#
# Usage: ./package-dmg.sh [--skip-sign]
# Output: ./build/ParallelsManager-<version>.dmg
#
#   NOTARIZE=1        notarize and staple the disk image (needs a signed build).
#                     Uses the App Store Connect API key from NOTARY_KEY_PATH,
#                     NOTARY_KEY_ID and NOTARY_ISSUER_ID, which default to the
#                     local signing kit (~/.signing-kit/asc-api-key.p8).
#   SIGN_ID, KEYCHAIN as for build.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Parallels Manager"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$SCRIPT_DIR/Info.plist")
SIGN_ID="${SIGN_ID:-Developer ID Application: Kelly Ford (P887QF74N8)}"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
STAGING="$BUILD_DIR/dmg-staging"
# No spaces, so the download link needs no escaping.
DMG_OUT="$BUILD_DIR/ParallelsManager-$VERSION.dmg"
DMG_TMP="$BUILD_DIR/ParallelsManager-$VERSION-tmp.dmg"
NOTARIZE="${NOTARIZE:-0}"
SKIP_SIGN=false
for arg in "$@"; do
  [[ "$arg" == "--skip-sign" ]] && SKIP_SIGN=true
done
if $SKIP_SIGN && [[ "$NOTARIZE" == 1 ]]; then
  echo "ERROR: notarizing needs a signed build; drop --skip-sign or NOTARIZE=1." >&2
  exit 1
fi

# ── Step 1: build ────────────────────────────────────────────────────────────
echo "==> Building app…"
"$SCRIPT_DIR/build.sh" "$@"

# ── Step 2: create staging folder ───────────────────────────────────────────
echo "==> Staging DMG contents"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

# ── Step 3: create writable DMG from staging folder ─────────────────────────
echo "==> Creating DMG"
rm -f "$DMG_TMP" "$DMG_OUT"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -fs HFS+ -format UDRW "$DMG_TMP"

# ── Step 4: window layout (Finder), on a Mac someone is signed in to ─────────
# GitHub's runners have no one to answer Finder's automation prompt, so the
# layout is skipped there (CI is set); the image works the same without it.
if [[ -z "${CI:-}" ]]; then
  echo "==> Setting DMG window layout"
  DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TMP" | grep -E '^/dev/' | awk 'NR==1{print $1}')
  sleep 1
  osascript <<APPLESCRIPT || echo "    (window layout skipped: Finder didn't answer)"
tell application "Finder"
  tell disk "$APP_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 760, 440}
    set theViewOptions to icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 100
    set position of item "$APP_NAME.app" of container window to {150, 170}
    set position of item "Applications" of container window to {400, 170}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
  sync
  hdiutil detach "$DEV" -quiet 2>/dev/null || true
  sleep 1
fi

# ── Step 5: convert to compressed read-only DMG ──────────────────────────────
echo "==> Converting to compressed DMG"
hdiutil convert "$DMG_TMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_OUT"
rm -f "$DMG_TMP"
rm -rf "$STAGING"

# ── Step 6: sign, notarize and staple the disk image ─────────────────────────
if ! $SKIP_SIGN; then
  echo "==> Signing the disk image"
  KEYCHAIN_ARGS=()
  [[ -n "${KEYCHAIN:-}" ]] && KEYCHAIN_ARGS=(--keychain "$KEYCHAIN")
  codesign --force --timestamp --sign "$SIGN_ID" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} "$DMG_OUT"
fi

if [[ "$NOTARIZE" == 1 ]]; then
  KEY_PATH="${NOTARY_KEY_PATH:-$HOME/.signing-kit/asc-api-key.p8}"
  KEY_ID="${NOTARY_KEY_ID:-38ANZ53D9L}"
  ISSUER_ID="${NOTARY_ISSUER_ID:-d36bb41d-a198-401d-b36c-2e4fd15163e1}"
  [[ -f "$KEY_PATH" ]] || { echo "ERROR: no notarization key at $KEY_PATH" >&2; exit 1; }
  echo "==> Notarizing (this usually takes a few minutes)"
  xcrun notarytool submit "$DMG_OUT" --key "$KEY_PATH" --key-id "$KEY_ID" \
    --issuer "$ISSUER_ID" --wait --timeout 30m --output-format json > "$BUILD_DIR/notarize.json"
  STATUS=$(/usr/bin/plutil -extract status raw -o - "$BUILD_DIR/notarize.json" 2>/dev/null || echo unknown)
  echo "    Apple says: $STATUS"
  if [[ "$STATUS" != "Accepted" ]]; then
    SUB_ID=$(/usr/bin/plutil -extract id raw -o - "$BUILD_DIR/notarize.json" 2>/dev/null || true)
    [[ -n "$SUB_ID" ]] && xcrun notarytool log "$SUB_ID" --key "$KEY_PATH" --key-id "$KEY_ID" --issuer "$ISSUER_ID" || true
    echo "ERROR: notarization was not accepted." >&2
    exit 1
  fi
  echo "==> Stapling the ticket, so it opens offline too"
  xcrun stapler staple "$DMG_OUT"
  xcrun stapler validate "$DMG_OUT"
  # What a downloaded copy will face: Gatekeeper's own check.
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_OUT"
fi

echo ""
echo "Done: $DMG_OUT"
echo "      Size: $(du -sh "$DMG_OUT" | cut -f1)"
