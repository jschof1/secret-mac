Secret is a native Mac app for finding, copying and editing variables in your local `~/.env` file.

### Changes in 2.0.0

- Copy, reveal, edit and export use the same parser for quoted values, inline comments and `export NAME=value` lines. Ambiguous values produce an error.
- The CLI's `--export` command now prints shell-quoted exports from the selected env file. Scripts that used shell evaluation or inherited variables need to be updated.
- Saves preserve inline comments and stay within the 2 MiB file limit.
- The editor uses a separate reveal preview with a copy button that clears the clipboard after 60 seconds.

### Download

- **Secret.dmg** is the recommended download. Open it, then drag Secret into Applications.
- **Secret.zip** contains the same universal app without the disk image.
- **secret-cli-universal.tar.gz** is the optional standalone command-line tool.
- **SHA256SUMS.txt** contains checksums for all downloads.

Requires macOS 14 or later. Universal binaries support Apple Silicon and Intel Macs. No Python, developer tools or preinstalled helper is required to use the app.

### First launch

**This release is not Developer ID signed or Apple-notarised.** After attempting to open it, macOS may require approval in **System Settings → Privacy & Security → Open Anyway**. Download only from this repository's official releases. No commands to disable Gatekeeper are needed.

### Included

- Search, copy, reveal, add and edit envs in a native Mac interface.
- A bundled native helper with the same env file as the CLI.
- Private backups, atomic saves and detection of conflicting edits.
- Keyboard shortcuts and clipboard cleanup.

Credentials stay in your local `~/.env` file. The app creates it on your first save if needed. Values and backups are plaintext with private permissions. There is no cloud sync or credential upload.

See the [README](https://github.com/jschof1/secret-mac#readme) for shortcuts and setup, and [Local data](https://github.com/jschof1/secret-mac/blob/main/docs/data.md) for storage details.
