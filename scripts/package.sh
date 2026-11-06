#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${SECRET_BUILD_DIR:-$repo_dir/build}"
app_dir="$build_dir/Secret.app"
release_dir="$build_dir/release"
packaging_python="${SECRET_PACKAGING_PYTHON:-python3}"
version="$(tr -d '[:space:]' < "$repo_dir/VERSION")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Invalid VERSION.\n' >&2; exit 2; }
[[ -x "$app_dir/Contents/Helpers/secret" ]] || { printf 'Build the app before packaging.\n' >&2; exit 2; }
/usr/bin/codesign --verify --deep --strict "$app_dir"
mkdir -p "$release_dir"
stage="$(mktemp -d "$build_dir/.package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/dmg" "$stage/cli"
/usr/bin/ditto "$app_dir" "$stage/dmg/Secret.app"
ln -s /Applications "$stage/dmg/Applications"
cp "$repo_dir/packaging/Read Me.html" "$stage/dmg/Read Me.html"
cp "$app_dir/Contents/Resources/Secret.icns" "$stage/dmg/.VolumeIcon.icns"
"$packaging_python" "$repo_dir/scripts/dmg-layout.py" "$stage/dmg"
xcrun SetFile -a C "$stage/dmg"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$release_dir/Secret.zip"
/usr/bin/hdiutil create -quiet -ov -volname Secret -fs HFS+ -srcfolder "$stage/dmg" -format UDZO "$release_dir/Secret.dmg"

cp "$app_dir/Contents/Helpers/secret" "$stage/cli/secret"
cp "$repo_dir/LICENSE" "$stage/cli/LICENSE"
cp "$repo_dir/docs/cli.md" "$stage/cli/README.md"
/usr/bin/tar -czf "$release_dir/secret-cli-universal.tar.gz" -C "$stage/cli" secret LICENSE README.md
(
    cd "$release_dir"
    /usr/bin/shasum -a 256 Secret.dmg Secret.zip secret-cli-universal.tar.gz > SHA256SUMS.txt
)
printf '%s\n' "$release_dir"
