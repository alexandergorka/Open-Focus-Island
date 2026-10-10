#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app="$project_dir/.build/Open Focus Island.app"
app_icon="$project_dir/Assets/AppIcon.icns"
export APP_VERSION="${APP_VERSION:-0.1.0}"

cd "$project_dir"
test -s "$app_icon"
# UNIVERSAL=1 builds arm64 + x86_64 (needs Xcode); the default builds for this Mac only.
if [[ "${UNIVERSAL:-}" == 1 ]]; then
    swift build --disable-sandbox --scratch-path .build/universal --configuration release --product OpenFocusIsland --arch arm64 --arch x86_64
    executable=.build/universal/apple/Products/Release/OpenFocusIsland
else
    swift build --disable-sandbox --scratch-path .build/developer-c --cache-path .build/developer-c/cache --manifest-cache local --configuration release --product OpenFocusIsland
    executable=.build/developer-c/release/OpenFocusIsland
fi
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$executable" "$app/Contents/MacOS/OpenFocusIsland"
cp "$app_icon" "$app/Contents/Resources/AppIcon.icns"
# Approved completion sounds go into the bundle before signing; a fresh directory keeps it deterministic.
rm -rf "$app/Contents/Resources/Sounds"
mkdir "$app/Contents/Resources/Sounds"
for sound_file in focus-completed.caf break-completed.caf manifest.json; do
    test -s "Assets/Sounds/$sound_file"
    cp "Assets/Sounds/$sound_file" "$app/Contents/Resources/Sounds/$sound_file"
done
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>OpenFocusIsland</string>
	<key>CFBundleIdentifier</key>
	<string>org.openfocusisland.app</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleName</key>
	<string>Open Focus Island</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$APP_VERSION</string>
	<key>CFBundleVersion</key>
	<string>$APP_VERSION</string>
	<key>LSUIElement</key>
	<true/>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$app"
./scripts/check-app-bundle.sh "$app"
