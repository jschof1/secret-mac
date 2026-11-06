# Secret

A small native Mac app for finding, copying and saving local envs. It uses the same `~/.env` file as `secret`.

Open **Secret** from Applications. Search an env name and click its copy button. Use **New env** to add one. The row menu has **Edit** and **Reveal value**.

| Shortcut | Action |
| --- | --- |
| ⌘F | Search |
| ⌘N | New env |
| ↩ in search | Copy the first match |
| ⇧⌘C | Copy the selected env |
| ⌘E | Edit the selected env |
| ⌘R | Reload |
| Esc | Close the form or hide a revealed value |

Copied values clear after 60 seconds or when the app quits, provided another app has not changed the clipboard. Revealed values hide when the app loses focus. Clipboard privacy flags are advisory; other apps can still read the clipboard.

## Install

Requires an Apple silicon Mac with macOS 14 or later and Xcode Command Line Tools. No package downloads are needed.

```sh
./scripts/install.sh
```

This builds `build/Secret.app`, installs it in `~/Applications` and updates `~/.local/bin/secret`. It backs up the previous app and helper first. It does not change any credentials during installation.

To install an existing build, run `./scripts/install.sh --skip-build`. `SECRET_BUILD_DIR` changes the build location. `SECRET_INSTALL_HOME` changes the installation root for testing.

## CLI

```sh
secret --list
secret SERVICE_API_KEY
secret --json
```

`--json` contains names only. Literal quoted values now return their contents without the surrounding quotes. Unquoted values keep the previous helper's behavior. No expansion or command execution occurs when reading values.

The app uses `--revision`, `--inspect NAME`, `--add NAME --expected REVISION` and `--set NAME --expected REVISION`. Save commands read the new value from stdin. Do not pass values as command arguments. `--inspect` returns a value and revision as JSON, so keep its output private.

`--export` retains the previous helper's behavior. It sources the env file with Bash and prints the exported environment. The app never uses this command.

## Data

Credentials stay in the existing plaintext env file. This is a local utility, without encryption, a sandbox, account login or automatic sync. It does not change `.env.keys`, shell startup files or other machines.

Each changed save first makes a private backup in `~/Library/Application Support/Secret/Backups`. Backups are plaintext, mode `0600`, inside a `0700` folder. The app keeps them until you remove them. A save replaces one assignment or appends a new one, preserves unrelated text and uses a private temporary file followed by an atomic rename. Symlinks to owned regular files are preserved. Extended attributes are copied.

Name validation, safe shell literal quoting and single-line values keep new entries readable by both the CLI and shells. The helper refuses ambiguous shell scripts, multiline values and duplicate target names. Files with Windows line endings are read-only until you convert them to LF in a text editor. Existing line endings are never converted automatically. If the file changed since the form opened, cancel the form, reload and try again. A lock serializes this helper's writes; a final fingerprint check detects other edits made before replacement. Arbitrary editors do not share that lock, so this is not a transactional guarantee against every external writer.

Existing shell sessions retain values they already loaded. New sessions read the updated file.

## Check

```sh
/usr/bin/python3 -m unittest discover -s tests -v
bash -n scripts/build.sh scripts/install.sh
```

Tests use temporary fixtures. For native UI testing, launch a separate app bundle with `SECRETS_FILE`, `SECRET_BACKUP_DIR` and `SECRET_HELPER_PATH` set to fixture paths. The app reads those variables but does not persist them. No credential values belong in screenshots or source control.
