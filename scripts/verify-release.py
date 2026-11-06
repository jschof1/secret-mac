#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tarfile
import tempfile
import zipfile


def run(arguments, **options):
    return subprocess.run(arguments, check=True, capture_output=True, **options).stdout


release = Path(sys.argv[1]).resolve()
version = (Path(__file__).resolve().parents[1] / "VERSION").read_text().strip()
for line in (release / "SHA256SUMS.txt").read_text().splitlines():
    expected, name = line.split("  ", 1)
    assert name == Path(name).name, "Checksum file contains an unexpected path"
    assert hashlib.sha256((release / name).read_bytes()).hexdigest() == expected, "Checksum mismatch"

with tempfile.TemporaryDirectory(prefix="secret-release-check-") as temporary:
    root = Path(temporary)
    archive = release / "Secret.zip"
    with zipfile.ZipFile(archive) as contents:
        assert not any("/.env" in name or name.endswith(".py") for name in contents.namelist()), "Unexpected data or Python source in app"
    run(["/usr/bin/ditto", "-xk", str(archive), str(root)])
    app = root / "Secret.app"
    with (app / "Contents/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    assert info["CFBundleShortVersionString"] == version
    assert info["LSMinimumSystemVersion"] == "14.0"
    assert "LSEnvironment" not in info, "Fixture environment leaked into release"
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)])
    for binary in (app / "Contents/MacOS/Secret", app / "Contents/Helpers/secret"):
        architectures = set(run(["/usr/bin/lipo", "-archs", str(binary)]).decode().split())
        assert architectures == {"arm64", "x86_64"}, "Release is not universal"
        dependencies = run(["/usr/bin/otool", "-L", str(binary)]).decode().lower()
        assert "python" not in dependencies, "Release links a Python runtime"
    helper = str(app / "Contents/Helpers/secret")
    environment = {"HOME": str(root), "PATH": "/usr/bin:/bin", "SECRETS_FILE": str(root / "fresh.env"), "SECRET_BACKUP_DIR": str(root / "backups")}
    assert json.loads(run([helper, "--json"], env=environment)) == []
    assert not (root / "fresh.env").exists()
    revision = run([helper, "--revision"], env=environment).decode().strip()
    value = b"fixture $literal 'quote' = only"
    run([helper, "--add=FRESH_INSTALL", "--expected", revision], input=value, env=environment)
    assert run([helper, "FRESH_INSTALL"], env=environment) == value
    assert (root / "fresh.env").stat().st_mode & 0o777 == 0o600
    assert not (root / ".local/bin/secret").exists(), "App requires or silently installs a user helper"
    with tarfile.open(release / "secret-cli-universal.tar.gz") as contents:
        assert set(contents.getnames()) == {"secret", "LICENSE", "README.md"}
        native = contents.extractfile("secret").read()
        assert hashlib.sha256(native).digest() == hashlib.sha256(Path(helper).read_bytes()).digest()
    mount = root / "mounted"
    mount.mkdir()
    run(["/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(release / "Secret.dmg")])
    try:
        assert (mount / "Secret.app").is_dir()
        assert (mount / "Applications").is_symlink()
        assert os.readlink(str(mount / "Applications")) == "/Applications"
        assert (mount / ".DS_Store").is_file()
        assert (mount / "Read Me.html").is_file()
        run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(mount / "Secret.app")])
    finally:
        run(["/usr/bin/hdiutil", "detach", str(mount)])
print(json.dumps({"version": version, "checksums": "passed", "fresh_install": "passed", "universal_binaries": "passed", "python_runtime_required": False, "disk_image": "passed", "developer_id_signed": False, "notarised": False}))
