# Local data

Secret uses the same `~/.env` file as the CLI. A missing file is created on the first save, with mode `0600`. It does not change shell startup files, macOS's global environment, `.env.keys`, other machines or cloud services.

Values are plaintext. Secret is an env-file editor, without encryption, Keychain storage, a sandbox or cloud sync. Other software running as your user can read your env file and clipboard.

Each changed save makes a private backup in `~/Library/Application Support/Secret/Backups`. Backups are plaintext files with mode `0600`, inside a `0700` directory. They remain until you remove them.

Saves preserve unrelated lines, comments and ordering. They use a private temporary file, an atomic rename, a revision check and a nonblocking lock. The private `.secret.lock` file remains next to the env file. The final revision check detects external changes made before replacement; arbitrary editors do not share the lock, so it is not a transactional guarantee against every writer.

Secret manages uppercase variable names in literal, single-line assignments, including indented lines and `export NAME=value`. It preserves the assignment prefix and inline comment when editing. Shell expressions and multiline values produce an error with the first unsupported line number. Files with Windows line endings can be read and must be converted to LF before editing.

Symlinks to owned regular files retain their links, and extended attributes are preserved. Saves require an owned folder with group and other write permissions disabled. Hard-linked files and duplicate target names are refused. The file limit is 2 MiB, and new values may be up to 64 KiB.

Values copied with the app's copy controls clear after 60 seconds or on app exit, if another app has not changed the clipboard. Concealed and transient clipboard flags are advisory. The editor keeps input masked and shows a separate preview when you reveal a value. Revealed values hide when the app loses focus or the selection changes.

Existing terminal sessions keep envs they have already loaded. The app does not inject new values into running processes.
