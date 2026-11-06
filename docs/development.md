# Development and releases

## Build

Requires macOS and Xcode Command Line Tools. No application runtime dependencies are downloaded.

```sh
./scripts/build.sh
```

The build compiles the GUI and native CLI for `arm64` and `x86_64`, combines them into universal binaries, signs the nested helper, then signs and verifies the app. `VERSION` supplies the app version. `SECRET_BUILD_DIR` changes the output directory.

`SECRET_SIGN_IDENTITY` defaults to `-`, which creates an ad-hoc signature. A supplied Developer ID identity enables hardened runtime and timestamp signing. A Developer ID signature alone is not notarisation.

## Test

```sh
/usr/bin/python3 -m unittest discover -s tests -v
SECRET_TEST_HELPER="$PWD/build/Secret.app/Contents/Helpers/secret" /usr/bin/python3 -m unittest discover -s tests -v
```

The Python helper in `helper/secret` is a reference implementation. It is not bundled or executed by the released app. The shared fixture suite runs against the native binary when `SECRET_TEST_HELPER` is set. A Python-only monkeypatch test is skipped in native mode; native conflict, lock, revision and symlink tests still run. Native-only tests are skipped in reference mode. A legacy-helper comparison also skips when no previous helper is installed.

To exercise the GUI's real process client without an installed CLI:

```sh
xcrun swiftc -parse-as-library -swift-version 5 Sources/HelperClient.swift tests/HelperClientSmoke.swift -o build/HelperClientSmoke
fresh_home="$(mktemp -d)"
build/HelperClientSmoke "$PWD/build/Secret.app" "$fresh_home"
```

All automated checks use disposable fixtures. Native UI tests can set `SECRETS_FILE` and `SECRET_BACKUP_DIR` in a separate test bundle's environment. Omit `SECRET_HELPER_PATH` to test the actual bundled helper. Never put real credentials in a screenshot or test fixture.

## Package

Packaging uses Python 3.10 or later and the small `ds-store` build dependency to set the disk image's Finder layout. This dependency is not shipped to users.

```sh
python3 -m venv build/packaging-venv
build/packaging-venv/bin/pip install -r packaging/requirements.txt
SECRET_PACKAGING_PYTHON="$PWD/build/packaging-venv/bin/python" ./scripts/package.sh
/usr/bin/python3 scripts/verify-release.py build/release
```

The output contains `Secret.dmg`, `Secret.zip`, `secret-cli-universal.tar.gz` and `SHA256SUMS.txt`. Verification checks signatures, architectures, checksums, a first save with no installed CLI, and the mounted disk image. The ZIP and disk image contain the same app.

## Publish

1. Update `VERSION`, `CHANGELOG.md` and `packaging/RELEASE_NOTES.md`.
2. Push the checked source to `main` and wait for the Apple Silicon and Intel CI jobs to pass.
3. Tag that commit as `v<version>` and push the tag.
4. The tag workflow rebuilds and tests both architectures, then creates a **draft** GitHub release with downloads.
5. Download the draft assets, verify their checksums and test the actual app before publishing the release.

The current release is explicitly unsigned by Developer ID and not notarised. For a future notarised release, sign with a Developer ID identity, submit the app using Apple's `notarytool`, wait for acceptance, staple the ticket, then package and verify the final downloads. Update the release notes only after those steps succeed. Never claim notarisation from an ad-hoc signature or a passing build.
