#!/bin/bash
set -euo pipefail

# Build Haven.app from Swift Package
# Usage: ./Scripts/build-app.sh [--configuration debug|release] [--output /path/Haven.app] [--sign]

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SIGN_IDENTITY="Apple Development"
TEAM_ID="KS9Z78DCVM"
SHOULD_SIGN=false
CONFIGURATION="release"
APP_BUNDLE="$REPO_ROOT/.build/app/Haven.app"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign)
            SHOULD_SIGN=true
            shift
            ;;
        --configuration)
            CONFIGURATION="${2:-}"
            shift 2
            ;;
        --output)
            APP_BUNDLE="${2:-}"
            shift 2
            ;;
        *)
            echo "ERROR: Unknown argument: $1"
            echo "Usage: $0 [--configuration debug|release] [--output /path/Haven.app] [--sign]"
            exit 1
            ;;
    esac
done

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

BUILD_DIR="$(dirname "$APP_BUNDLE")"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"

echo "==> Building Haven ($SWIFT_CONFIGURATION)..."
cd "$REPO_ROOT"
swift build -c "$SWIFT_CONFIGURATION" --product Haven 2>&1 | tail -5

BINARY="$(swift build -c "$SWIFT_CONFIGURATION" --product Haven --show-bin-path)/Haven"

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

echo "==> Creating Haven.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$BUILD_DIR"
mkdir -p "$MACOS"
mkdir -p "$CONTENTS/Resources"

# Copy binary
cp "$BINARY" "$MACOS/Haven"

# Copy Info.plist
cp "$REPO_ROOT/Sources/HavenApp/Info.plist" "$CONTENTS/Info.plist"

# Create minimal entitlements (network client for API calls)
cat > "$BUILD_DIR/Haven.entitlements" <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

# Sign if requested
if [ "$SHOULD_SIGN" = true ]; then
    echo "==> Signing with $SIGN_IDENTITY (Team: $TEAM_ID)..."
    codesign --force --sign "$SIGN_IDENTITY" \
        --entitlements "$BUILD_DIR/Haven.entitlements" \
        --options runtime \
        "$APP_BUNDLE"
    echo "==> Verifying signature..."
    codesign --verify --verbose "$APP_BUNDLE"
else
    echo "==> Ad-hoc signing..."
    codesign --force --sign - \
        --entitlements "$BUILD_DIR/Haven.entitlements" \
        "$APP_BUNDLE"
fi

echo ""
echo "==> Done! Haven.app is at:"
echo "    $APP_BUNDLE"
echo ""
echo "    To open:  open $APP_BUNDLE"
echo "    To copy:  cp -R $APP_BUNDLE /Applications/"
