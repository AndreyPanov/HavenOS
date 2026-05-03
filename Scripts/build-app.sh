#!/bin/bash
set -euo pipefail

# Build Haven.app from Swift Package
# Usage: ./Scripts/build-app.sh [--sign]

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build/app"
APP_BUNDLE="$BUILD_DIR/Haven.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"

SIGN_IDENTITY="Apple Development"
TEAM_ID="KS9Z78DCVM"
SHOULD_SIGN=false

for arg in "$@"; do
    case "$arg" in
        --sign) SHOULD_SIGN=true ;;
    esac
done

echo "==> Building Haven (Release)..."
cd "$REPO_ROOT"
swift build -c release --product Haven 2>&1 | tail -5

BINARY="$(swift build -c release --product Haven --show-bin-path)/Haven"

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

echo "==> Creating Haven.app bundle..."
rm -rf "$APP_BUNDLE"
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
