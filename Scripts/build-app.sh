#!/bin/bash
set -euo pipefail

# Build HavenOS.app from Swift Package
# Usage: ./Scripts/build-app.sh [--configuration debug|release] [--output /path/HavenOS.app] [--bundle-identifier app.haven.HavenOS] [--sign] [--sign-identity "Developer ID Application: ..."]

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SIGN_IDENTITY="Apple Development"
TEAM_ID="KS9Z78DCVM"
SHOULD_SIGN=false
CONFIGURATION="release"
APP_NAME="HavenOS"
SOURCE_PRODUCT="Haven"
SOURCE_EXECUTABLE="Haven"
APP_BUNDLE="$REPO_ROOT/.build/app/$APP_NAME.app"
BUNDLE_IDENTIFIER="app.haven.HavenOS"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign)
            SHOULD_SIGN=true
            shift
            ;;
        --sign-identity)
            SIGN_IDENTITY="${2:-}"
            shift 2
            ;;
        --configuration)
            CONFIGURATION="${2:-}"
            shift 2
            ;;
        --output)
            APP_BUNDLE="${2:-}"
            shift 2
            ;;
        --bundle-identifier)
            BUNDLE_IDENTIFIER="${2:-}"
            shift 2
            ;;
        *)
            echo "ERROR: Unknown argument: $1"
            echo "Usage: $0 [--configuration debug|release] [--output /path/HavenOS.app] [--bundle-identifier app.haven.HavenOS] [--sign] [--sign-identity \"Developer ID Application: ...\"]"
            exit 1
            ;;
    esac
done

FINAL_APP_BUNDLE="$APP_BUNDLE"
FINAL_BUILD_DIR="$(dirname "$FINAL_APP_BUNDLE")"
STAGING_ROOT="$(mktemp -d /private/tmp/haven-app-build.XXXXXX)"
trap 'rm -rf "$STAGING_ROOT"' EXIT
APP_BUNDLE="$STAGING_ROOT/$APP_NAME.app"

NORMALIZED_CONFIGURATION="$(printf '%s' "$CONFIGURATION" | tr '[:upper:]' '[:lower:]')"

case "$NORMALIZED_CONFIGURATION" in
    debug) SWIFT_CONFIGURATION="debug" ;;
    release) SWIFT_CONFIGURATION="release" ;;
    *)
        echo "ERROR: Unsupported configuration: $CONFIGURATION"
        echo "Use: debug or release"
        exit 1
        ;;
esac

BUILD_DIR="$STAGING_ROOT"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
FRAMEWORKS="$CONTENTS/Frameworks"

echo "==> Building $APP_NAME ($SWIFT_CONFIGURATION)..."
cd "$REPO_ROOT"
swift build -c "$SWIFT_CONFIGURATION" --product "$SOURCE_PRODUCT" 2>&1 | tail -5

BINARY="$(swift build -c "$SWIFT_CONFIGURATION" --product "$SOURCE_PRODUCT" --show-bin-path)/$SOURCE_EXECUTABLE"

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

echo "==> Creating $APP_NAME.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$FINAL_BUILD_DIR"
mkdir -p "$MACOS"
mkdir -p "$CONTENTS/Resources"

# Copy binary
cp "$BINARY" "$MACOS/$APP_NAME"

# Copy Info.plist
cp "$REPO_ROOT/Sources/HavenApp/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_IDENTIFIER" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$CONTENTS/Info.plist"

# Copy app resources used by Info.plist and Bundle.module lookups.
cp "$REPO_ROOT/Sources/HavenApp/Resources/HavenIcon.icns" "$CONTENTS/Resources/HavenIcon.icns"
BIN_DIR="$(dirname "$BINARY")"
find "$BIN_DIR" -maxdepth 1 \( -name "*.bundle" -o -name "*.resources" \) -exec cp -R {} "$CONTENTS/Resources/" \;

# Copy Sparkle if the executable links against it. SwiftPM keeps binary
# artifacts under .build, and ditto preserves the framework symlinks.
if otool -L "$BINARY" | grep -q "Sparkle.framework"; then
    SPARKLE_FRAMEWORK="$(find "$REPO_ROOT/.build" -name Sparkle.framework -type d -print -quit)"
    if [ -z "$SPARKLE_FRAMEWORK" ]; then
        echo "ERROR: $APP_NAME links Sparkle, but Sparkle.framework was not found in .build"
        exit 1
    fi

    echo "==> Copying Sparkle.framework..."
    mkdir -p "$FRAMEWORKS"
    ditto --norsrc --noextattr --noqtn --noacl --noclone "$SPARKLE_FRAMEWORK" "$FRAMEWORKS/Sparkle.framework"
    xattr -cr "$FRAMEWORKS/Sparkle.framework"
    find "$FRAMEWORKS/Sparkle.framework" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
    find "$FRAMEWORKS/Sparkle.framework" -exec xattr -d com.apple.ResourceFork {} \; 2>/dev/null || true
    find "$FRAMEWORKS/Sparkle.framework" -exec xattr -d 'com.apple.fileprovider.fpfs#P' {} \; 2>/dev/null || true

    if ! otool -l "$MACOS/$APP_NAME" | grep -q "@executable_path/../Frameworks"; then
        install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/$APP_NAME"
    fi
fi

# Sign if requested
xattr -cr "$APP_BUNDLE"
find "$APP_BUNDLE" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
find "$APP_BUNDLE" -exec xattr -d com.apple.ResourceFork {} \; 2>/dev/null || true
find "$APP_BUNDLE" -exec xattr -d 'com.apple.fileprovider.fpfs#P' {} \; 2>/dev/null || true

if [ "$SHOULD_SIGN" = true ]; then
    echo "==> Signing with $SIGN_IDENTITY (Team: $TEAM_ID)..."
    TIMESTAMP_ARGS=()
    if [[ "$SIGN_IDENTITY" == Developer\ ID* || "$SIGN_IDENTITY" == Apple\ Distribution:* ]]; then
        TIMESTAMP_ARGS+=("--timestamp")
    fi

    if [ -d "$FRAMEWORKS/Sparkle.framework" ]; then
        codesign --force --sign "$SIGN_IDENTITY" \
            "${TIMESTAMP_ARGS[@]}" \
            --options runtime \
            "$FRAMEWORKS/Sparkle.framework"
    fi
    codesign --force --sign "$SIGN_IDENTITY" \
        "${TIMESTAMP_ARGS[@]}" \
        --options runtime \
        "$APP_BUNDLE"
    echo "==> Verifying signature..."
    codesign --verify --verbose "$APP_BUNDLE"
else
    echo "==> Ad-hoc signing..."
    if [ -d "$FRAMEWORKS/Sparkle.framework" ]; then
        codesign --force --sign - \
            "$FRAMEWORKS/Sparkle.framework"
    fi
    codesign --force --sign - \
        "$APP_BUNDLE"
fi

echo "==> Copying signed bundle to output..."
rm -rf "$FINAL_APP_BUNDLE"
ditto --norsrc --noextattr --noqtn --noacl --noclone "$APP_BUNDLE" "$FINAL_APP_BUNDLE"

echo ""
echo "==> Done! $APP_NAME.app is at:"
echo "    $FINAL_APP_BUNDLE"
echo ""
echo "    To open:  open $FINAL_APP_BUNDLE"
echo "    To copy:  cp -R $FINAL_APP_BUNDLE /Applications/"
