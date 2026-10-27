
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Building Shroud..."

# Build the Swift executable.
swift build -c debug

APP=".build/Shroud.app"
CONTENTS="$APP/Contents"

# Create the macOS app bundle directories.
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

# Copy the latest compiled executable.
cp .build/debug/Shroud "$CONTENTS/MacOS/Shroud"

# Copy the application metadata.
cp Resources/Info.plist "$CONTENTS/Info.plist"

# Copy the official Shroud application icon.
if [ ! -f "Resources/Shroud.icns" ]; then
    echo "Error: Resources/Shroud.icns not found."
    exit 1
fi

cp Resources/Shroud.icns \
   "$CONTENTS/Resources/Shroud.icns"

# Validate the Info.plist.
plutil -lint "$CONTENTS/Info.plist"

# Ad-hoc sign the local development app.
codesign --force --deep --sign - "$APP"

echo ""
echo "Shroud.app created successfully!"
echo "Location: $APP"
echo "App icon: Shroud.icns"
