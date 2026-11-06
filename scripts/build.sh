#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${SECRET_BUILD_DIR:-$repo_dir/build}"
app_dir="$build_dir/Secret.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

xcrun swiftc -parse-as-library -swift-version 5 \
  -target arm64-apple-macos14.0 -O \
  -framework AppKit -framework SwiftUI \
  "$repo_dir/Sources/HelperClient.swift" \
  "$repo_dir/Sources/SecretModel.swift" \
  "$repo_dir/Sources/ContentView.swift" \
  "$repo_dir/Sources/SecretApp.swift" \
  -o "$app_dir/Contents/MacOS/Secret"

/usr/bin/python3 "$repo_dir/scripts/icon.py" "$build_dir"
cp "$build_dir/Secret.icns" "$app_dir/Contents/Resources/Secret.icns"
cp "$repo_dir/helper/secret" "$app_dir/Contents/Resources/secret"
chmod 755 "$app_dir/Contents/MacOS/Secret" "$app_dir/Contents/Resources/secret"

cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Secret</string>
  <key>CFBundleIdentifier</key><string>net.aspectstudio.secret</string>
  <key>CFBundleName</key><string>Secret</string>
  <key>CFBundleDisplayName</key><string>Secret</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>Secret</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSSupportsSuddenTermination</key><false/>
</dict></plist>
PLIST

/usr/bin/plutil -lint "$app_dir/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app_dir"
printf '%s\n' "$app_dir"
