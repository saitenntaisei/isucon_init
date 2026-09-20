"""Exercise Make recipes without sudo, service changes, or network access."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


MAKEFILE = Path(__file__).resolve().parents[1] / "Makefile"


class MakefileTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="isucon-make-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        shutil.copyfile(MAKEFILE, self.root / "Makefile")
        (self.root / "env.sh").write_text("", encoding="utf-8")
        self.nginx = self.root / "nginx access.log"
        self.mysql = self.root / "mysql slow.log"
        self.trace = self.root / "operations.txt"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.command("sudo", '''#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$TEST_TRACE"
case "$1" in
  systemctl) exit 0 ;;
  mv) if [ "${FAIL_MOVE:-0}" = 1 ]; then exit 7; fi ;;
  test|touch|chmod) ;;
  *) printf 'Unexpected command: %s\n' "$1" >&2; exit 99 ;;
esac
exec "$@"
''')
        self.command("date", "#!/bin/sh\nprintf '20000101T000000Z\\n'\n")
        self.environment = os.environ | {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "TEST_TRACE": str(self.trace),
            "MAKEFLAGS": "",
            "MFLAGS": "",
            "MAKEOVERRIDES": "",
            "SERVER_ID": "",
        }

    def command(self, name, content):
        path = self.bin / name
        path.write_text(content, encoding="utf-8")
        path.chmod(0o755)

    def make(self, *arguments, server_id="s1", fail_move=False):
        return subprocess.run(
            ["make", "-j1", f"SERVER_ID={server_id}",
             f"NGINX_LOG={self.nginx}", f"DB_SLOW_LOG={self.mysql}",
             "WEBHOOK_URL=", *arguments],
            cwd=self.root,
            env=self.environment | {"FAIL_MOVE": "1" if fail_move else "0"},
            capture_output=True, text=True, timeout=10, check=False,
        )

    def test_repeated_rotation_keeps_both_runs_and_existing_archives(self):
        previous = self.root / "s1" / "logs" / "previous"
        previous.mkdir(parents=True)
        (previous / "nginx").write_text("older requests\n")
        archives = []
        for number in (1, 2):
            self.nginx.write_text(f"requests {number}\n")
            self.mysql.write_text(f"queries {number}\n")
            result = self.make("mv-logs")
            self.assertEqual(result.returncode, 0, result.stderr)
            archive = set(previous.parent.iterdir()) - {previous, *archives}
            self.assertEqual(len(archive), 1)
            archives.extend(archive)
            self.assertEqual(self.nginx.read_text(), "")
            self.assertEqual(self.mysql.read_text(), "")
        for number, archive in enumerate(archives, 1):
            self.assertEqual((archive / "nginx").read_text(), f"requests {number}\n")
            self.assertEqual((archive / "mysql").read_text(), f"queries {number}\n")
        self.assertEqual((previous / "nginx").read_text(), "older requests\n")

    def test_missing_logs_are_created_without_fabricated_archives(self):
        result = self.make("mv-logs")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.nginx.read_text(), "")
        self.assertEqual(self.mysql.read_text(), "")
        archives = list((self.root / "s1" / "logs").iterdir())
        self.assertEqual(len(archives), 1)
        self.assertEqual(list(archives[0].iterdir()), [])

    def test_move_failure_stops_before_restarting_services(self):
        self.nginx.write_text("keep these requests\n")
        self.mysql.write_text("keep these queries\n")
        result = self.make("mv-logs", fail_move=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.nginx.read_text(), "keep these requests\n")
        self.assertEqual(self.mysql.read_text(), "keep these queries\n")
        self.assertNotIn("systemctl", self.trace.read_text())

    def test_missing_server_id_stops_before_filesystem_changes(self):
        result = self.make("mv-logs", server_id="")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.trace.exists())
        self.assertFalse((self.root / "logs").exists())

    def test_command_line_overrides_build_and_service_defaults(self):
        self.environment["BUILD_DIR"] = "/ignored/environment/path"
        self.environment["SERVICE_NAME"] = "ignored.service"
        result = self.make(
            "-n", "BUILD_DIR=/example/app", "BIN_NAME=example",
            "SERVICE_NAME=example.service", "build", "restart",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("cd /example/app;", result.stdout)
        self.assertIn("go build -o example", result.stdout)
        self.assertIn("systemctl restart example.service", result.stdout)
        self.assertNotIn("/ignored/environment/path", result.stdout)
        self.assertFalse(self.trace.exists())


if __name__ == "__main__":
    unittest.main()
