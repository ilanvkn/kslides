#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="$PWD/dist/KSlides.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/KSlides "$APP/Contents/MacOS/KSlides"
cp .build/release/KSlidesMCP "$APP/Contents/MacOS/KSlidesMCP"
cp Resources/geometry_worker.py "$APP/Contents/Resources/geometry_worker.py"
cp Resources/park-world.png Resources/cat-sleeps.png Resources/dog-runs.png Resources/bird-sings.png "$APP/Contents/Resources/"
if [[ -f Resources/KSlides.icns ]]; then cp Resources/KSlides.icns "$APP/Contents/Resources/KSlides.icns"; fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>KSlides</string>
<key>CFBundleDisplayName</key><string>KSlides</string>
<key>CFBundleIdentifier</key><string>io.github.ilanvkn.kslides</string>
<key>CFBundleExecutable</key><string>KSlides</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundleIconFile</key><string>KSlides</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Built by IK</string>
</dict></plist>
PLIST
codesign --force --sign - --options runtime "$APP/Contents/MacOS/KSlidesMCP"
codesign --force --sign - --options runtime --entitlements Resources/KSlides.entitlements "$APP"
printf '%s\n' "$APP"
