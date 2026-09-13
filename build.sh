#!/bin/bash
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:-$(dirname "$SOURCE")/Aside.app}"
CACHE="${TMPDIR:-/tmp}/desknotes-swift-cache"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources" "$CACHE"
SDK="$(xcrun --show-sdk-path)"
swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 -module-cache-path "$CACHE" -I "$SOURCE/Support/CLibXML2" -Xcc -I -Xcc "$SDK/usr/include/libxml2" "$SOURCE"/Sources/*.swift -framework AppKit -framework SwiftUI -framework Carbon -framework CoreText -framework JavaScriptCore -lxml2 -o "$DEST/Contents/MacOS/DeskNotes"
cp -R "$SOURCE/Resources/" "$DEST/Contents/Resources/"
cp "$SOURCE/Info.plist" "$DEST/Contents/Info.plist"
codesign --force --sign - "$DEST"
echo "Built: $DEST"
