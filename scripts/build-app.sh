#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${1:-release}"

if [[ "$CONFIGURATION" != "debug" &&
      "$CONFIGURATION" != "release" ]]; then
    echo "Usage: $0 [debug|release]"
    exit 1
fi

echo "================================"
echo "Shroud macOS Build"
echo "Configuration: $CONFIGURATION"
echo "================================"

# Build the requested configuration.
swift build -c "$CONFIGURATION"

APP=".build/Shroud.app"
CONTENTS="$APP/Contents"
EXECUTABLE=".build/$CONFIGURATION/Shroud"

if [[ ! -f "$EXECUTABLE" ]]; then
    echo "Error: Executable not found: $EXECUTABLE"
    exit 1
fi

if [[ ! -f "Resources/Info.plist" ]]; then
    echo "Error: Info.plist not found."
    exit 1
fi

if [[ ! -f "Resources/Shroud.icns" ]]; then
    echo "Error: Shroud.icns not found."
    exit 1
fi

# Remove the previous app bundle to prevent stale files.
rm -rf "$APP"

mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

# Copy executable and resources.
cp "$EXECUTABLE" "$CONTENTS/MacOS/Shroud"
cp "Resources/Info.plist" "$CONTENTS/Info.plist"
cp "Resources/Shroud.icns" \
   "$CONTENTS/Resources/Shroud.icns"

chmod +x "$CONTENTS/MacOS/Shroud"

# Validate bundle metadata.
plutil -lint "$CONTENTS/Info.plist"

# Development/testing signature only.
# Public releases will use Developer ID and hardened runtime.
codesign --force --sign - "$APP"

# Verify the bundle signature.
codesign --verify --strict --verbose=2 "$APP"

echo ""
echo "================================"
echo "Shroud build completed"
echo "================================"
echo "Configuration: $CONFIGURATION"
echo "App: $APP"
echo "Signing: Ad-hoc (testing only)"
echo ""