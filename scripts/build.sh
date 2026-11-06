#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${SECRET_BUILD_DIR:-$repo_dir/build}"
app_dir="$build_dir/Secret.app"
version="1.0.0"
if [[ -f "$repo_dir/VERSION" ]]; then
  version="$(tr -d '[:space:]' < "$repo_dir/VERSION")"
fi
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  printf 'VERSION must contain a numeric major.minor.patch version.\n' >&2
  exit 2
}
bundle_version="${SECRET_BUNDLE_VERSION:-$version}"
[[ "$bundle_version" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || {
  printf 'SECRET_BUNDLE_VERSION must contain one to three numeric components.\n' >&2
  exit 2
}
export MACOSX_DEPLOYMENT_TARGET=14.0
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$build_dir/native" "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$app_dir/Contents/Helpers"

for architecture in arm64 x86_64; do
  xcrun swiftc -parse-as-library -swift-version 5 -O \
    -sdk "$sdk_path" -target "$architecture-apple-macos14.0" \
    "$repo_dir/NativeHelper/EnvDocument.swift" \
    "$repo_dir/NativeHelper/EnvStore.swift" \
    "$repo_dir/NativeHelper/SecretCommand.swift" \
    -o "$build_dir/native/secret-$architecture"
  xcrun swiftc -parse-as-library -swift-version 5 -O \
    -sdk "$sdk_path" -target "$architecture-apple-macos14.0" \
    -framework AppKit -framework SwiftUI \
    "$repo_dir/Sources/HelperClient.swift" \
    "$repo_dir/Sources/SecretModel.swift" \
    "$repo_dir/Sources/ContentView.swift" \
    "$repo_dir/Sources/SecretApp.swift" \
    -o "$build_dir/native/Secret-$architecture"
done

/usr/bin/lipo -create "$build_dir/native/secret-arm64" "$build_dir/native/secret-x86_64" -output "$app_dir/Contents/Helpers/secret"
/usr/bin/lipo -create "$build_dir/native/Secret-arm64" "$build_dir/native/Secret-x86_64" -output "$app_dir/Contents/MacOS/Secret"
/usr/bin/lipo -verify_arch arm64 x86_64 "$app_dir/Contents/Helpers/secret"
/usr/bin/lipo -verify_arch arm64 x86_64 "$app_dir/Contents/MacOS/Secret"
rm -f "$app_dir/Contents/Resources/secret"

/usr/bin/python3 "$repo_dir/scripts/icon.py" "$build_dir"
cp "$build_dir/Secret.icns" "$app_dir/Contents/Resources/Secret.icns"
chmod 755 "$app_dir/Contents/MacOS/Secret" "$app_dir/Contents/Helpers/secret"

cat > "$app_dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Secret</string>
  <key>CFBundleIdentifier</key><string>net.aspectstudio.secret</string>
  <key>CFBundleName</key><string>Secret</string>
  <key>CFBundleDisplayName</key><string>Secret</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$bundle_version</string>
  <key>CFBundleIconFile</key><string>Secret</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSSupportsSuddenTermination</key><false/>
</dict></plist>
PLIST

/usr/bin/plutil -lint "$app_dir/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app_dir/Contents/Helpers/secret"
/usr/bin/codesign --force --sign - "$app_dir"
/usr/bin/codesign --verify --deep --strict "$app_dir"
printf '%s\n' "$app_dir"
