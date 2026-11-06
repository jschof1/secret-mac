#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
install_home="${SECRET_INSTALL_HOME:-$HOME}"
build_dir="${SECRET_BUILD_DIR:-$repo_dir/build}"
if [[ "${1:-}" == "--skip-build" ]]; then
  shift
else
  "$repo_dir/scripts/build.sh"
fi
if [[ $# -ne 0 ]]; then
  printf 'Usage: install.sh [--skip-build]\n' >&2
  exit 2
fi
app_source="$build_dir/Secret.app"
[[ -x "$app_source/Contents/MacOS/Secret" && -f "$app_source/Contents/Resources/secret" ]] || {
  printf 'Build Secret.app before installing.\n' >&2
  exit 2
}

umask 077
backup_dir="$install_home/Library/Application Support/Secret/Backups"
apps_dir="$install_home/Applications"
bin_dir="$install_home/.local/bin"
mkdir -p "$backup_dir" "$apps_dir" "$bin_dir"
[[ ! -L "$backup_dir" && ! -L "$bin_dir" ]] || {
  printf 'Install and backup folders must not be symbolic links.\n' >&2
  exit 2
}
chmod 700 "$backup_dir"
install_stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
if [[ -e "$bin_dir/secret" || -L "$bin_dir/secret" ]]; then
  cp -p "$bin_dir/secret" "$backup_dir/secret-helper-$install_stamp"
  chmod 600 "$backup_dir/secret-helper-$install_stamp"
fi
if [[ -e "$apps_dir/Secret.app" || -L "$apps_dir/Secret.app" ]]; then
  /usr/bin/ditto "$apps_dir/Secret.app" "$backup_dir/Secret-$install_stamp.app"
fi
app_stage="$(mktemp -d "$apps_dir/.secret-install.XXXXXX")"
helper_stage="$(mktemp "$bin_dir/.secret-install.XXXXXX")"
trap 'rm -rf "$app_stage"; rm -f "$helper_stage"' EXIT
/usr/bin/ditto "$app_source" "$app_stage/Secret.app"
/usr/bin/codesign --verify --deep --strict "$app_stage/Secret.app"
cp "$app_source/Contents/Resources/secret" "$helper_stage"
chmod 755 "$helper_stage"
"$helper_stage" --help >/dev/null
if [[ -e "$apps_dir/Secret.app" || -L "$apps_dir/Secret.app" ]]; then
  mv "$apps_dir/Secret.app" "$app_stage/previous.app"
fi
mv "$app_stage/Secret.app" "$apps_dir/Secret.app"
mv -f "$helper_stage" "$bin_dir/secret"
printf 'Installed %s\n' "$apps_dir/Secret.app"
