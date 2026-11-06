# Local data

Secret uses the same `~/.env` file as the CLI. A missing file is created on the first save, with mode `0600`. It does not change shell startup files, macOS's global environment, `.env.keys`, other machines or cloud services.

Values are plaintext. Secret is an env-file editor, without encryption, Keychain storage, a sandbox or cloud sync. Other software running as your user can read your env file and clipboard.

Each changed save makes a private backup in `~/Library/Application Support/Secret/Backups`. Backups are plaintext files with mode `0600`, inside a `0700` directory. They remain until you remove them.

Saves preserve unrelated lines, comments and ordering. They use a private temporary file, an atomic rename, a revision check and a nonblocking lock. The private `.secret.lock` file remains next to the env file. The final revision check detects external changes made before replacement; arbitrary editors do not share the lock, so it is not a transactional guarantee against every writer.

Symlinks to owned regular files retain their links. Extended attributes are preserved. Hard-linked files, duplicate target names, ambiguous shell scripts and multiline values are refused. Files with Windows line endings remain read-only until converted to LF in a text editor.

Values copied with the app's copy controls clear after 60 seconds or on app exit, if another app has not changed the clipboard. Concealed and transient clipboard flags are advisory. Revealed values hide when the app loses focus or the selection changes.

Existing terminal sessions keep envs they have already loaded. The app does not inject new values into running processes.
