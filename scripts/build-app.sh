
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Building Shroud..."

swift build -c debug

APP=".build/Shroud.app"
CONTENTS="$APP/Contents"

mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

cp .build/debug/Shroud "$CONTENTS/MacOS/Shroud"
cp Resources/Info.plist "$CONTENTS/Info.plist"

# Ad-hoc sign the local development app
codesign --force --deep --sign - "$APP"

echo "Shroud.app created at $APP"
