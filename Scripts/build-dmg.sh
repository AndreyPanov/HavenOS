#!/bin/bash
set -euo pipefail

# Build a drag-to-Applications DMG installer for Haven.
# Usage: ./Scripts/build-dmg.sh [--configuration debug|release] [--output /path/Haven.dmg] [--app /path/Haven.app] [--sign] [--sign-identity "Developer ID Application: ..."]

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

CONFIGURATION="release"
OUTPUT_DMG="$REPO_ROOT/.build/app/Haven.dmg"
APP_BUNDLE=""
SIGN_ARGS=()
VOLUME_NAME="Haven"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configuration)
            CONFIGURATION="${2:-}"
            shift 2
            ;;
        --output)
            OUTPUT_DMG="${2:-}"
            shift 2
            ;;
        --app)
            APP_BUNDLE="${2:-}"
            shift 2
            ;;
        --sign)
            SIGN_ARGS+=("--sign")
            shift
            ;;
        --sign-identity)
            SIGN_ARGS+=("--sign-identity" "${2:-}")
            shift 2
            ;;
        --volume-name)
            VOLUME_NAME="${2:-}"
            shift 2
            ;;
        *)
            echo "ERROR: Unknown argument: $1"
            echo "Usage: $0 [--configuration debug|release] [--output /path/Haven.dmg] [--app /path/Haven.app] [--sign] [--sign-identity \"Developer ID Application: ...\"]"
            exit 1
            ;;
    esac
done

STAGING_ROOT="$(mktemp -d /private/tmp/haven-dmg-build.XXXXXX)"
MOUNT_DIR="$STAGING_ROOT/mount"
RW_DMG="$STAGING_ROOT/Haven-rw.dmg"
BACKGROUND="$STAGING_ROOT/HavenDmgBackground.png"
DEVICE=""

cleanup() {
    if [[ -n "$DEVICE" ]]; then
        hdiutil detach "$DEVICE" -quiet -force 2>/dev/null || true
    fi
    rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

if [[ -z "$APP_BUNDLE" ]]; then
    APP_BUNDLE="$REPO_ROOT/.build/app/Haven.app"
    BUILD_APP_COMMAND=(
        "$REPO_ROOT/Scripts/build-app.sh"
        --configuration "$CONFIGURATION"
        --output "$APP_BUNDLE"
    )
    if [[ ${#SIGN_ARGS[@]} -gt 0 ]]; then
        BUILD_APP_COMMAND+=("${SIGN_ARGS[@]}")
    fi
    "${BUILD_APP_COMMAND[@]}"
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "ERROR: Haven.app not found at $APP_BUNDLE"
    exit 1
fi

echo "==> Generating DMG background..."
swift "$REPO_ROOT/Scripts/generate-dmg-background.swift" "$BACKGROUND" >/dev/null

echo "==> Creating writable DMG..."
mkdir -p "$(dirname "$OUTPUT_DMG")"
rm -f "$OUTPUT_DMG" "$OUTPUT_DMG.tmp"
hdiutil create \
    -size 180m \
    -fs HFS+ \
    -volname "$VOLUME_NAME" \
    -layout SPUD \
    -ov \
    "$RW_DMG" >/dev/null

mkdir -p "$MOUNT_DIR"
ATTACH_OUTPUT="$(hdiutil attach "$RW_DMG" -mountpoint "$MOUNT_DIR" -nobrowse -readwrite -noverify)"
DEVICE="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/Apple_HFS/ {print $1; exit}')"

if [[ -z "$DEVICE" ]]; then
    echo "ERROR: Could not determine mounted DMG device."
    exit 1
fi

echo "==> Copying installer contents..."
ditto --norsrc --noextattr --noqtn --noacl --noclone "$APP_BUNDLE" "$MOUNT_DIR/Haven.app"
ln -s /Applications "$MOUNT_DIR/Applications"
mkdir -p "$MOUNT_DIR/.background"
cp "$BACKGROUND" "$MOUNT_DIR/.background/background.png"

echo "==> Applying Finder window layout..."
if ! osascript >/dev/null <<APPLESCRIPT
tell application "Finder"
    set dmgFolder to POSIX file "$MOUNT_DIR" as alias
    set backgroundPicture to POSIX file "$MOUNT_DIR/.background/background.png" as alias
    open dmgFolder
    set containerWindow to container window of dmgFolder
    set current view of containerWindow to icon view
    set toolbar visible of containerWindow to false
    set statusbar visible of containerWindow to false
    set bounds of containerWindow to {160, 120, 1080, 700}
    set theViewOptions to icon view options of containerWindow
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set background picture of theViewOptions to backgroundPicture
    delay 0.5
    set position of item "Haven.app" of containerWindow to {287, 258}
    set position of item "Applications" of containerWindow to {650, 258}
    update dmgFolder without registering applications
    delay 1
    close containerWindow
end tell
APPLESCRIPT
then
    echo "WARNING: Finder layout could not be applied. The DMG contents were still created."
fi

sync
hdiutil detach "$DEVICE" -quiet
DEVICE=""

echo "==> Compressing DMG..."
FINAL_STAGING_DMG="$STAGING_ROOT/Haven.dmg"
hdiutil convert "$RW_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$FINAL_STAGING_DMG" >/dev/null
mv "$FINAL_STAGING_DMG" "$OUTPUT_DMG"

echo "==> Verifying DMG..."
hdiutil verify "$OUTPUT_DMG" >/dev/null

echo ""
echo "==> Done! Haven DMG is at:"
echo "    $OUTPUT_DMG"
