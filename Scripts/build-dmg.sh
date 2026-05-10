#!/bin/bash
set -euo pipefail

# Build a drag-to-Applications DMG installer for HavenOS.
# Usage: ./Scripts/build-dmg.sh [--configuration debug|release] [--output /path/HavenOS.dmg] [--app /path/HavenOS.app] [--sign] [--sign-identity "Developer ID Application: ..."] [--notarize --notary-profile PROFILE]

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

CONFIGURATION="release"
APP_NAME="HavenOS"
OUTPUT_DMG="$REPO_ROOT/.build/app/$APP_NAME.dmg"
APP_BUNDLE=""
SIGN_ARGS=()
SIGN_IDENTITY=""
SHOULD_SIGN=false
SHOULD_NOTARIZE=false
NOTARY_PROFILE=""
VOLUME_NAME="$APP_NAME"

usage() {
    echo "Usage: $0 [--configuration debug|release] [--output /path/HavenOS.dmg] [--app /path/HavenOS.app] [--sign] [--sign-identity \"Developer ID Application: ...\"] [--notarize --notary-profile PROFILE]"
}

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
            SHOULD_SIGN=true
            shift
            ;;
        --sign-identity)
            SIGN_IDENTITY="${2:-}"
            SIGN_ARGS+=("--sign-identity" "$SIGN_IDENTITY")
            shift 2
            ;;
        --notarize)
            SHOULD_NOTARIZE=true
            shift
            ;;
        --notary-profile)
            NOTARY_PROFILE="${2:-}"
            shift 2
            ;;
        --volume-name)
            VOLUME_NAME="${2:-}"
            shift 2
            ;;
        *)
            echo "ERROR: Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ "$SHOULD_NOTARIZE" = true ]]; then
    if [[ "$SHOULD_SIGN" != true ]]; then
        echo "ERROR: --notarize requires --sign with a Developer ID Application identity."
        usage
        exit 1
    fi

    if [[ -z "$NOTARY_PROFILE" ]]; then
        echo "ERROR: --notarize requires --notary-profile PROFILE."
        echo "Create one with: xcrun notarytool store-credentials PROFILE"
        exit 1
    fi
fi

STAGING_ROOT="$(mktemp -d /private/tmp/haven-dmg-build.XXXXXX)"
MOUNT_DIR="$STAGING_ROOT/mount"
RW_DMG="$STAGING_ROOT/$APP_NAME-rw.dmg"
BACKGROUND="$STAGING_ROOT/${APP_NAME}DmgBackground.png"
DEVICE=""

cleanup() {
    if [[ -n "$DEVICE" ]]; then
        hdiutil detach "$DEVICE" -quiet -force 2>/dev/null || true
    fi
    rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

if [[ -z "$APP_BUNDLE" ]]; then
    APP_BUNDLE="$REPO_ROOT/.build/app/$APP_NAME.app"
    BUILD_APP_COMMAND=(
        "$REPO_ROOT/Scripts/build-app.sh"
        --configuration "$CONFIGURATION"
        --output "$APP_BUNDLE"
        --bundle-identifier "app.haven.HavenOS"
    )
    if [[ ${#SIGN_ARGS[@]} -gt 0 ]]; then
        BUILD_APP_COMMAND+=("${SIGN_ARGS[@]}")
    fi
    "${BUILD_APP_COMMAND[@]}"
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "ERROR: $APP_NAME.app not found at $APP_BUNDLE"
    exit 1
fi

if [[ "$SHOULD_NOTARIZE" = true ]]; then
    echo "==> Checking app signature for Developer ID notarization..."
    APP_SIGNATURE="$(codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1 || true)"
    if ! printf '%s\n' "$APP_SIGNATURE" | grep -q "Authority=Developer ID Application"; then
        echo "ERROR: Notarization requires $APP_NAME.app to be signed with a Developer ID Application certificate."
        echo "Current signature authorities:"
        printf '%s\n' "$APP_SIGNATURE" | grep "Authority=" || true
        exit 1
    fi

    echo "==> Submitting app for notarization..."
    APP_NOTARY_ZIP="$STAGING_ROOT/$APP_NAME-app-notary.zip"
    APP_NOTARY_PARENT="$(cd "$(dirname "$APP_BUNDLE")" && pwd)"
    APP_NOTARY_NAME="$(basename "$APP_BUNDLE")"
    pushd "$APP_NOTARY_PARENT" >/dev/null
    ditto -c -k --sequesterRsrc --keepParent "$APP_NOTARY_NAME" "$APP_NOTARY_ZIP"
    popd >/dev/null
    xcrun notarytool submit "$APP_NOTARY_ZIP" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    echo "==> Stapling notarization ticket to app..."
    xcrun stapler staple "$APP_BUNDLE"

    echo "==> Validating stapled app ticket..."
    xcrun stapler validate "$APP_BUNDLE"
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
ditto --norsrc --noextattr --noqtn --noacl --noclone "$APP_BUNDLE" "$MOUNT_DIR/$APP_NAME.app"
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
    set position of item "$APP_NAME.app" of containerWindow to {287, 258}
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
FINAL_STAGING_DMG="$STAGING_ROOT/$APP_NAME.dmg"
hdiutil convert "$RW_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$FINAL_STAGING_DMG" >/dev/null
mv "$FINAL_STAGING_DMG" "$OUTPUT_DMG"

echo "==> Verifying DMG..."
hdiutil verify "$OUTPUT_DMG" >/dev/null

if [[ "$SHOULD_SIGN" = true ]]; then
    if [[ -z "$SIGN_IDENTITY" ]]; then
        SIGN_IDENTITY="Apple Development"
    fi

    echo "==> Signing DMG with $SIGN_IDENTITY..."
    DMG_TIMESTAMP_ARGS=()
    if [[ "$SIGN_IDENTITY" == Developer\ ID* || "$SIGN_IDENTITY" == Apple\ Distribution:* ]]; then
        DMG_TIMESTAMP_ARGS+=("--timestamp")
    fi
    codesign --force --sign "$SIGN_IDENTITY" "${DMG_TIMESTAMP_ARGS[@]}" "$OUTPUT_DMG"
    codesign --verify --verbose "$OUTPUT_DMG"
fi

if [[ "$SHOULD_NOTARIZE" = true ]]; then
    echo "==> Submitting DMG for notarization..."
    xcrun notarytool submit "$OUTPUT_DMG" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "$OUTPUT_DMG"

    echo "==> Validating stapled ticket..."
    xcrun stapler validate "$OUTPUT_DMG"

    echo "==> Assessing DMG with Gatekeeper..."
    spctl -a -vv -t open --context context:primary-signature "$OUTPUT_DMG"
fi

echo ""
echo "==> Done! $APP_NAME DMG is at:"
echo "    $OUTPUT_DMG"
