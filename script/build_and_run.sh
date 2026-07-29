#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPLAY_NAME="Agent Memory"
EXECUTABLE_NAME="QMDMenuBar"
ARTIFACT_NAME="Agent-Memory"
BUNDLE_ID="com.mountainmeadowsystems.qmdmenubar"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
CONFIGURATION="${CONFIGURATION:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"

show_usage() {
  cat <<USAGE
Usage: ./script/build_and_run.sh [options]

Builds the SwiftPM macOS menu bar app and stages a versioned app, ZIP, and DMG in dist/.

Options:
  --debug                    Build the debug configuration (default: release)
  --release                  Build the release configuration
  --version VERSION          Override the marketing version
  --sign IDENTITY            Sign with an Apple Developer ID identity
  --notarize-profile NAME    Submit with an xcrun notarytool keychain profile
  --no-launch                Build without launching the app
  --verify                   Verify the signature and launched process
  --logs                     Stream app logs after launch
USAGE
}

VERIFY=0
STREAM_LOGS=0
NO_LAUNCH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify)
      VERIFY=1
      shift
      ;;
    --debug)
      CONFIGURATION="debug"
      shift
      ;;
    --release)
      CONFIGURATION="release"
      shift
      ;;
    --version)
      VERSION="${2:?--version requires a value}"
      shift 2
      ;;
    --sign)
      SIGN_IDENTITY="${2:?--sign requires an identity}"
      shift 2
      ;;
    --notarize-profile)
      NOTARY_PROFILE="${2:?--notarize-profile requires a profile name}"
      shift 2
      ;;
    --no-launch)
      NO_LAUNCH=1
      shift
      ;;
    --logs|--telemetry)
      STREAM_LOGS=1
      shift
      ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      show_usage
      exit 2
      ;;
  esac
done

cd "$ROOT_DIR"

if [[ -z "$VERSION" ]]; then
  VERSION="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
  VERSION="${VERSION#v}"
  VERSION="${VERSION:-0.2.0}"
fi
if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
fi

EXECUTABLE="$ROOT_DIR/.build/$CONFIGURATION/$EXECUTABLE_NAME"
ARCHIVE="$DIST_DIR/$ARTIFACT_NAME-$VERSION.zip"
DMG="$DIST_DIR/$ARTIFACT_NAME-$VERSION.dmg"

if [[ "$NO_LAUNCH" -eq 0 ]] && pgrep -x "$EXECUTABLE_NAME" >/dev/null 2>&1; then
  pkill -x "$EXECUTABLE_NAME" || true
  sleep 0.3
fi

swift build -c "$CONFIGURATION"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ROOT_DIR/Sources/QMDMenuBar/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/Sources/QMDMenuBar/Resources/QMDAperture.svg" "$APP_BUNDLE/Contents/Resources/QMDAperture.svg"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

rm -f "$ARCHIVE"
/usr/bin/ditto -c -k --norsrc --keepParent "$APP_BUNDLE" "$ARCHIVE"

if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "--notarize-profile requires --sign with a Developer ID identity" >&2
    exit 2
  fi
  xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
  rm -f "$ARCHIVE"
  /usr/bin/ditto -c -k --norsrc --keepParent "$APP_BUNDLE" "$ARCHIVE"
fi

DMG_STAGING="$(mktemp -d "$DIST_DIR/.dmg-staging.XXXXXX")"
cleanup_dmg_staging() {
  rm -rf "$DMG_STAGING"
}
trap cleanup_dmg_staging EXIT

/usr/bin/ditto "$APP_BUNDLE" "$DMG_STAGING/$DISPLAY_NAME.app"
ln -s /Applications "$DMG_STAGING/Applications"
rm -f "$DMG"
hdiutil create \
  -volname "$DISPLAY_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG"

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
hdiutil verify "$DMG"
echo "Built $APP_BUNDLE"
echo "Archived $ARCHIVE"
echo "Packaged $DMG"

if [[ "$NO_LAUNCH" -eq 0 ]]; then
  /usr/bin/open -n "$APP_BUNDLE"
fi

if [[ "$VERIFY" -eq 1 && "$NO_LAUNCH" -eq 0 ]]; then
  for _ in {1..20}; do
    if pgrep -x "$EXECUTABLE_NAME" >/dev/null 2>&1; then
      echo "$DISPLAY_NAME is running"
      break
    fi
    sleep 0.25
  done

  if ! pgrep -x "$EXECUTABLE_NAME" >/dev/null 2>&1; then
    echo "$DISPLAY_NAME did not start" >&2
    exit 1
  fi
fi

if [[ "$STREAM_LOGS" -eq 1 ]]; then
  /usr/bin/log stream --style compact --predicate "process == '$EXECUTABLE_NAME'"
fi
