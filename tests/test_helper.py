import fcntl
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "helper/secret"
loader = importlib.machinery.SourceFileLoader("secret_backend", str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
backend = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = backend
loader.exec_module(backend)


class HelperTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="secret-fixture-")
        self.root = Path(self.temporary.name)
        self.envfile = self.root / "fixture.env"
        self.backups = self.root / "backups"
        self.environment = {"HOME": str(self.root), "PATH": "/usr/bin:/bin", "SECRETS_FILE": str(self.envfile), "SECRET_BACKUP_DIR": str(self.backups)}
        self.write(b"# fixture\nFIRST=one\nSECOND=two=three\n")

    def tearDown(self):
        self.temporary.cleanup()

    def write(self, data):
        self.envfile.write_bytes(data)
        self.envfile.chmod(0o600)

    def run_helper(self, *arguments, value=None, success=True):
        result = subprocess.run([sys.executable, str(HELPER)] + list(arguments), input=None if value is None else value.encode("utf-8"), capture_output=True, env=self.environment)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr.decode("utf-8"))
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def revision(self):
        return self.run_helper("--revision").stdout.decode("ascii").strip()

    def save(self, name, value, adding=True, expected=None, success=True):
        return self.run_helper("--add" if adding else "--set", name, "--expected", self.revision() if expected is None else expected, value=value, success=success)

    def test_legacy_reads_and_names_only_json(self):
        self.write(b"# fixture\nFIRST=one\nFIRST=later\nSECOND=two=three\nexport OTHER=hidden\nlower=hidden\n")
        self.assertEqual(self.run_helper("FIRST").stdout, b"one")
        self.assertEqual(self.run_helper("SECOND").stdout, b"two=three")
        self.assertEqual(self.run_helper("--list").stdout, b"FIRST\nFIRST\nSECOND\n")
        self.assertEqual(json.loads(self.run_helper("--json").stdout), ["FIRST", "FIRST", "SECOND"])
        self.assertNotIn(b"one", self.run_helper("--json").stdout)

    def test_inspect_and_regex_injection(self):
        result = json.loads(self.run_helper("--inspect", "FIRST").stdout)
        self.assertEqual(result, {"name": "FIRST", "value": "one", "revision": self.revision()})
        self.run_helper("FIRST|SECOND", success=False)
        self.run_helper(".*", success=False)

    def test_double_quoted_literal_escapes_match_shell(self):
        cases = [r'"a\$b"', r'"a\`b"', r'"a\"b"', r'"a\\b"', r'"a\qb"']
        for raw in cases:
            self.write(("FIRST=" + raw + "\n").encode("utf-8"))
            shell = subprocess.run(["/bin/bash", "-c", '. "$1"; printf "%s" "$FIRST"', "fixture", str(self.envfile)], env={"PATH": "/usr/bin:/bin"}, capture_output=True, check=True)
            self.assertEqual(self.run_helper("FIRST").stdout, shell.stdout)

    def test_check_does_not_change_file_or_print_values(self):
        original = self.envfile.read_bytes()
        self.assertEqual(self.run_helper("--check").stdout, b"OK\n")
        self.assertEqual(self.envfile.read_bytes(), original)
        self.assertFalse(self.backups.exists())
        self.write(b"FIRST=$(false)\n")
        result = self.run_helper("--check", success=False)
        self.assertNotIn(b"$(false)", result.stderr)

    def test_option_like_name_has_a_name_validation_error(self):
        result = self.run_helper("--add=-NAME", "--expected", self.revision(), value="value", success=False)
        self.assertIn(b"uppercase letters", result.stderr)

    def test_maximum_value_inspect_is_complete(self):
        value = "x" * backend.MAX_VALUE_BYTES
        self.save("LARGE", value)
        self.assertEqual(self.run_helper("LARGE").stdout.decode("ascii"), value)
        self.assertEqual(json.loads(self.run_helper("--inspect", "LARGE").stdout)["value"], value)

    def test_literal_values_round_trip_and_source_without_execution(self):
        sentinel = self.root / "should-not-exist"
        values = ["ordinary-token", " a leading and trailing space ", "quote'and\"double", "$HOME", "`touch %s`" % sentinel, "$(touch %s)" % sentinel, "a=b=c", "a;b|c&d", "#comment", "é 世界", "\\path\\value", "~", " "]
        for index, value in enumerate(values):
            name = "VALUE_%s" % index
            self.save(name, value)
            self.assertEqual(self.run_helper(name).stdout.decode("utf-8"), value)
            result = subprocess.run(["/bin/bash", "-c", '. "$1"; printf "%s" "${!2}"', "fixture", str(self.envfile), name], env={"PATH": "/usr/bin:/bin"}, capture_output=True)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout.decode("utf-8"), value)
            self.assertFalse(sentinel.exists())

    def test_edit_preserves_other_bytes_and_order(self):
        original = b"# first comment\nFIRST=one\n\n# second comment\nSECOND=two=three"
        self.write(original)
        self.save("FIRST", "new value", adding=False)
        self.assertEqual(self.envfile.read_bytes(), b"# first comment\nFIRST='new value'\n\n# second comment\nSECOND=two=three")
        backups = list(self.backups.iterdir())
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_bytes(), original)

    def test_append_to_file_without_final_newline(self):
        self.write(b"FIRST=one")
        self.save("NEW", "new")
        self.assertEqual(self.envfile.read_bytes(), b"FIRST=one\nNEW=new\n")

    def test_crlf_reads_stay_compatible_and_writes_are_refused(self):
        original = b"# comment\r\nFIRST=one\r\n"
        self.write(original)
        self.assertEqual(self.run_helper("FIRST").stdout, b"one\r")
        self.save("NEW", "space value", success=False)
        self.assertEqual(self.envfile.read_bytes(), original)

    def test_invalid_names_and_values_leave_file_unchanged(self):
        before = self.envfile.read_bytes()
        for name in ["lower", "1FIRST", "", "FOO;BAD", "NAME-WITH-DASH", "A\nB"]:
            self.save(name, "value", success=False)
        for value in ["", "a\nb", "a\rb", "a\0b", "a" * (backend.MAX_VALUE_BYTES + 1)]:
            self.save("VALID", value, success=False)
        self.assertEqual(self.envfile.read_bytes(), before)
        self.assertFalse(self.backups.exists())

    def test_duplicate_targets_and_export_alias_rejected(self):
        for data in [b"FIRST=one\nFIRST=two\n", b"FIRST=one\nexport FIRST=two\n", b"FIRST=one\n  FIRST=two\n"]:
            self.write(data)
            self.save("FIRST", "three", adding=False, success=False)
            self.assertEqual(self.envfile.read_bytes(), data)
        self.write(b"export FIRST=one\n")
        self.save("FIRST", "two", success=False)

    def test_add_does_not_overwrite_and_set_does_not_create(self):
        original = self.envfile.read_bytes()
        self.save("FIRST", "new", success=False)
        self.save("MISSING", "new", adding=False, success=False)
        self.assertEqual(self.envfile.read_bytes(), original)

    def test_ambiguous_shell_files_cannot_be_changed(self):
        for data in [b"FIRST='unclosed\n", b"FIRST='multi\nline'\n", b"echo command\n", b"FIRST=$(touch unsafe)\n", b'FIRST="$HOME"\n', b"FIRST=value;echo bad\n", b"\xef\xbb\xbfFIRST=one\n", b"FIRST=a\0b\n"]:
            self.write(data)
            self.save("NEW", "new", success=False)
            self.assertEqual(self.envfile.read_bytes(), data)

    def test_noop_edit_does_not_create_backup(self):
        before = self.envfile.stat()
        result = self.save("FIRST", "one", adding=False)
        self.assertEqual(result.stdout.strip(), b"Unchanged")
        self.assertEqual(self.envfile.stat().st_ino, before.st_ino)
        self.assertFalse(self.backups.exists())

    def test_stale_revision_rejected(self):
        revision = self.revision()
        self.write(self.envfile.read_bytes() + b"THIRD=external\n")
        before = self.envfile.read_bytes()
        self.save("FIRST", "new", adding=False, expected=revision, success=False)
        self.assertEqual(self.envfile.read_bytes(), before)

    def test_private_modes_and_backups(self):
        self.envfile.chmod(0o644)
        self.save("NEW", "new")
        self.assertEqual(stat.S_IMODE(self.envfile.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.backups.stat().st_mode), 0o700)
        for backup in self.backups.iterdir():
            self.assertEqual(stat.S_IMODE(backup.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(Path(str(self.envfile) + ".secret.lock").stat().st_mode), 0o600)

    def test_symlink_keeps_link_and_updates_target(self):
        target = self.root / "actual.env"
        self.envfile.rename(target)
        self.envfile.symlink_to(target)
        self.save("NEW", "new")
        self.assertTrue(self.envfile.is_symlink())
        self.assertIn(b"NEW=new\n", target.read_bytes())

    def test_symlink_retarget_conflicts(self):
        first = self.root / "first.env"
        second = self.root / "second.env"
        first.write_bytes(b"FIRST=one\n")
        second.write_bytes(b"FIRST=one\n")
        self.envfile.unlink()
        self.envfile.symlink_to(first)
        revision = self.revision()
        self.envfile.unlink()
        self.envfile.symlink_to(second)
        self.save("NEW", "new", expected=revision, success=False)
        self.assertEqual(second.read_bytes(), b"FIRST=one\n")

    def test_hardlinks_rejected(self):
        os.link(str(self.envfile), str(self.root / "hardlink.env"))
        self.run_helper("--list", success=False)

    def test_lock_contention_is_reported_without_waiting(self):
        with open(str(self.envfile) + ".secret.lock", "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.save("NEW", "new", success=False)

    def test_backup_failure_leaves_original_intact(self):
        blocked = self.root / "blocked"
        blocked.write_text("not a directory")
        self.environment["SECRET_BACKUP_DIR"] = str(blocked)
        before = self.envfile.read_bytes()
        self.save("NEW", "new", success=False)
        self.assertEqual(self.envfile.read_bytes(), before)
        self.assertEqual(list(self.root.glob(".secret-*")), [])

    def test_external_write_before_replace_is_detected(self):
        before = self.envfile.read_bytes()
        revision = self.revision()
        external = before + b"EXTERNAL=keep\n"
        def change_while_backing_up(document):
            self.envfile.write_bytes(external)
        with mock.patch.dict(os.environ, self.environment), mock.patch.object(backend, "make_backup", side_effect=change_while_backing_up):
            with self.assertRaises(backend.SecretError):
                backend.save(self.envfile, "NEW", "new", True, revision)
        self.assertEqual(self.envfile.read_bytes(), external)

    def test_empty_env_can_be_edited(self):
        self.write(b"FIRST=\n")
        self.run_helper("FIRST", success=False)
        self.assertEqual(json.loads(self.run_helper("--inspect", "FIRST").stdout)["value"], "")
        self.save("FIRST", "filled", adding=False)
        self.assertEqual(self.run_helper("FIRST").stdout, b"filled")

    def test_missing_env_file_can_be_created(self):
        self.envfile.unlink()
        self.assertEqual(self.run_helper("--list").stdout, b"")
        self.save("NEW", "new")
        self.assertEqual(self.envfile.read_bytes(), b"NEW=new\n")

    def test_xattrs_survive_save(self):
        if sys.platform == "darwin":
            attribute = "com.aspectstudio.secret-fixture"
            subprocess.run(["/usr/bin/xattr", "-w", attribute, "fixture", str(self.envfile)], check=True)
            self.save("NEW", "new")
            actual = subprocess.run(["/usr/bin/xattr", "-p", attribute, str(self.envfile)], check=True, capture_output=True)
            self.assertEqual(actual.stdout.strip(), b"fixture")
            return
        if not hasattr(os, "setxattr"):
            self.skipTest("xattrs unavailable")
        attribute = "user.secret-fixture"
        try:
            os.setxattr(str(self.envfile), attribute, b"fixture")
        except OSError:
            self.skipTest("filesystem does not support xattrs")
        self.save("NEW", "new")
        self.assertEqual(os.getxattr(str(self.envfile), attribute), b"fixture")

    def test_existing_helper_matches_safe_fixture_reads(self):
        legacy = Path.home() / ".local/bin/secret"
        if not legacy.exists():
            self.skipTest("existing helper unavailable")
        for arguments in [("--list",), ("FIRST",), ("SECOND",)]:
            previous = subprocess.run([str(legacy)] + list(arguments), env=self.environment, capture_output=True)
            self.assertEqual(previous.returncode, 0)
            self.assertEqual(previous.stdout, self.run_helper(*arguments).stdout)


if __name__ == "__main__":
    unittest.main()
