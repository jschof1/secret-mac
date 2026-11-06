# Command-line tool

The app includes the native `secret` helper. You can use the app without installing a command-line tool.

Run the bundled helper directly:

```sh
/Applications/Secret.app/Contents/Helpers/secret --list
```

To install the standalone CLI, download its archive from the [latest release](https://github.com/jschof1/secret-mac/releases/latest), extract it, then copy the binary into a directory on your PATH. Keep a copy of an existing `secret` helper before replacing it.

```sh
mkdir -p "$HOME/.local/bin"
install -m 755 secret "$HOME/.local/bin/secret"
```

No shell startup files are changed automatically.

## Read

```sh
secret --list
secret SERVICE_API_KEY
secret --json
secret --check
```

`--json` contains names only. `--check` validates the file without changing it or printing values. Quoted literals are decoded without expansion or execution. The CLI reads `${SECRETS_FILE:-$HOME/.env}`.

## Save

Read a revision before saving. Pass the value on stdin, using `printf %s` rather than `echo` so you do not add a newline.

```sh
revision="$(secret --revision)"
printf %s 'example-only-value' | secret --add SERVICE_API_KEY --expected "$revision"
```

Use `--set` to update an existing name. A stale revision refuses the save. Do not put real credentials directly into command arguments or saved shell history.

`--inspect NAME` returns a value and revision as JSON for the GUI. Keep its output private. `--export` retains the original helper's explicit Bash-source behaviour and prints the exported environment. The app never uses it.
