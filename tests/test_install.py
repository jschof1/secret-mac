import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
NATIVE_HELPER = os.environ.get("SECRET_TEST_HELPER")
BUNDLED_HELPER = ROOT / "build/Secret.app/Contents/Helpers/secret"
HELPER = Path(NATIVE_HELPER) if NATIVE_HELPER else BUNDLED_HELPER if BUNDLED_HELPER.exists() else Path("/usr/bin/true")


@unittest.skipUnless(sys.platform == "darwin", "native installer test requires macOS")
class InstallTests(unittest.TestCase):
    def test_fixture_install_preserves_env_and_backs_up_previous_helper(self):
        with tempfile.TemporaryDirectory(prefix="secret-install-fixture-") as temporary:
            directory = Path(temporary)
            home = directory / "home"
            build = directory / "build"
            app = build / "Secret.app"
            (app / "Contents/MacOS").mkdir(parents=True)
            (app / "Contents/Resources").mkdir()
            (app / "Contents/Helpers").mkdir()
            shutil.copyfile("/usr/bin/true", str(app / "Contents/MacOS/Secret"))
            (app / "Contents/MacOS/Secret").chmod(0o755)
            shutil.copyfile(str(HELPER), str(app / "Contents/Helpers/secret"))
            (app / "Contents/Helpers/secret").chmod(0o755)
            with (app / "Contents/Info.plist").open("wb") as stream:
                plistlib.dump({"CFBundleExecutable": "Secret", "CFBundleIdentifier": "net.aspectstudio.secret.fixture", "CFBundlePackageType": "APPL", "CFBundleName": "Secret"}, stream)
            subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(app / "Contents/Helpers/secret")], check=True, capture_output=True, timeout=30)
            subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True, timeout=30)
            (home / ".local/bin").mkdir(parents=True)
            old_helper = b"#!/bin/sh\nprintf legacy\n"
            (home / ".local/bin/secret").write_bytes(old_helper)
            (home / ".local/bin/secret").chmod(0o755)
            envfile = home / ".env"
            envfile.write_bytes(b"# fixture\nFIRST=one\n")
            environment = dict(os.environ, SECRET_INSTALL_HOME=str(home), SECRET_BUILD_DIR=str(build), SECRETS_FILE=str(envfile))
            result = subprocess.run(["/bin/bash", str(ROOT / "scripts/install.sh"), "--skip-build"], env=environment, capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr.decode("utf-8"))
            self.assertEqual(envfile.read_bytes(), b"# fixture\nFIRST=one\n")
            self.assertTrue((home / "Applications/Secret.app/Contents/MacOS/Secret").exists())
            self.assertEqual((home / ".local/bin/secret").read_bytes(), (app / "Contents/Helpers/secret").read_bytes())
            backups = list((home / "Library/Application Support/Secret/Backups").glob("secret-helper-*"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_bytes(), old_helper)
            self.assertEqual(backups[0].stat().st_mode & 0o777, 0o600)
            result = subprocess.run([str(home / ".local/bin/secret"), "FIRST"], env=environment, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, b"" if HELPER == Path("/usr/bin/true") else b"one")
            repeat = subprocess.run(["/bin/bash", str(ROOT / "scripts/install.sh"), "--skip-build"], env=environment, capture_output=True, timeout=30)
            self.assertEqual(repeat.returncode, 0, repeat.stderr.decode("utf-8"))
            self.assertEqual(len(list((home / "Library/Application Support/Secret/Backups").glob("Secret-*.app"))), 1)
            self.assertEqual(envfile.read_bytes(), b"# fixture\nFIRST=one\n")


if __name__ == "__main__":
    unittest.main()
