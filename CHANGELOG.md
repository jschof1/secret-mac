# Changelog

## 2.0.0

- The app and CLI agree on quoted literals, inline comments and lines beginning with `export`. Unsupported shell syntax and ambiguous duplicate values produce errors.
- `secret --export` now emits shell-quoted exports from the selected env file. Scripts that depended on shell evaluation or inherited variables need to be updated.
- Saves preserve inline comments and refuse changes that would exceed the 2 MiB file limit.
- Editor reveals use a separate preview with clipboard expiry, and the app always runs its bundled helper.
- Verify that ZIP, DMG and CLI downloads contain the same build. Pin the release workflow's actions and packaging dependencies.

## 1.0.0

- Native Mac interface for finding, copying, revealing and saving local envs.
- Self-contained universal app for Apple Silicon and Intel Macs on macOS 14 or later.
- Bundled native CLI. Python and developer tools are not required to use the app.
- Private backups, atomic saves and detection of conflicting edits.
- Keyboard shortcuts and concealed clipboard copies with automatic expiry.
- Drag-to-Applications disk image, ZIP download, optional CLI archive and checksums.

This release is ad-hoc signed and is not Apple-notarised. macOS may require manual approval on first launch.
