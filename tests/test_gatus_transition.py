import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


DIRECTORY = Path(__file__).resolve().parents[1] / "server/native-migration"
sys.path.insert(0, str(DIRECTORY))
spec = importlib.util.spec_from_file_location("gatus_transition", DIRECTORY / "gatus-transition.py")
transition = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transition)


class GatusTransitionTests(unittest.TestCase):
    def test_prepares_target_database_before_activation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            system = root / "system"
            units = system / "etc/systemd/system"
            units.mkdir(parents=True)
            (units / "gatus.service").touch()
            (system / "bin").mkdir()
            (system / "bin/switch-to-configuration").touch()
            events = []
            with patch.object(transition, "STATE", root / "state"), \
                    patch.object(Path, "is_relative_to", return_value=True), \
                    patch.object(transition.common, "check_supervisors"), \
                    patch.object(transition, "prepare_postgres",
                                 side_effect=lambda _: events.append("setup")), \
                    patch.object(transition.common, "run",
                                 side_effect=lambda command: events.append(command)), \
                    patch.object(transition, "verify_monitoring"), \
                    patch.object(transition, "delete_kuma_data"):
                transition.activate(system, True)
            activation = [str(system / "bin/switch-to-configuration"), "test"]
            self.assertLess(events.index("setup"), events.index(activation))
            self.assertIn(["systemctl", "reset-failed", "gatus.service"], events)

    def test_setup_executes_target_script_as_postgres_without_restarting_clients(self):
        with tempfile.TemporaryDirectory() as temporary:
            system = Path(temporary)
            units = system / "etc/systemd/system"
            units.mkdir(parents=True)
            script = "/nix/store/example-postgresql-setup/bin/postgresql-setup-start"
            (units / "postgresql-setup.service").write_text(f"[Service]\nExecStart={script} \n")
            with patch.object(Path, "is_file", return_value=True), \
                    patch.object(transition.common, "run") as run:
                transition.prepare_postgres(system)
            self.assertEqual(run.call_args_list[0].args[0],
                             ["systemctl", "start", "postgresql.service"])
            command = run.call_args_list[1].args[0]
            self.assertEqual(command[:5], ["runuser", "-u", "postgres", "--", "env"])
            self.assertEqual(command[-2:], ["PGPORT=5432", script])
            self.assertEqual(run.call_count, 2)

    def test_cleanup_deletes_only_kuma_data_and_updates_dump_checksums(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            state = root / "state"
            state.mkdir()
            backups = root / "backups"
            backup = backups / "20261106T205349Z"
            archive = backup / "unfinished-native-copies"
            archive.mkdir(parents=True)
            for base in (backup, archive):
                (base / "uptime-kuma").mkdir()
                (base / "uptime-kuma" / "config").write_text("old")
                (base / "private-uptime-kuma").symlink_to(base / "uptime-kuma", target_is_directory=True)
                (base / "kuma-mariadb.sql").write_text("old")
                (base / "kuma-counts.json").write_text("{}")
                (base / "forgejo-mariadb.sql").write_text("retain")
                (base / "sha256.json").write_text(json.dumps({
                    "kuma-mariadb.sql": "old-hash", "forgejo-mariadb.sql": "retain-hash",
                }))
                (base / "shared-mariadb-data").mkdir()
            standalone = root / "standalone"
            standalone.mkdir()
            link = root / "link"
            link.symlink_to(standalone, target_is_directory=True)
            unrelated = backups / "not-a-backup"
            unrelated.mkdir()
            (unrelated / "uptime-kuma").mkdir()
            with patch.object(transition, "STATE", state), \
                    patch.object(transition, "BACKUP_ROOTS", (backups,)), \
                    patch.object(transition, "STANDALONE", (link, standalone)):
                transition.delete_kuma_data()
                self.assertEqual(transition.cleanup_paths(), [])
            self.assertFalse(standalone.exists())
            self.assertFalse(link.is_symlink())
            for base in (backup, archive):
                self.assertTrue((base / "forgejo-mariadb.sql").exists())
                self.assertTrue((base / "shared-mariadb-data").exists())
                self.assertEqual(json.loads((base / "sha256.json").read_text()),
                                 {"forgejo-mariadb.sql": "retain-hash"})
            self.assertTrue((unrelated / "uptime-kuma").exists())
            self.assertEqual(json.loads((state / "kuma-cleanup.json").read_text())["status"], "complete")

    def test_cleanup_rejects_symlinked_backup_roots(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            actual = root / "actual"
            actual.mkdir()
            link = root / "link"
            link.symlink_to(actual, target_is_directory=True)
            with patch.object(transition, "BACKUP_ROOTS", (link,)):
                with self.assertRaises(RuntimeError):
                    transition.cleanup_paths()

    def test_cleanup_rejects_symlinked_directory_parent(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            state = root / "state"
            state.mkdir()
            actual = root / "actual"
            actual.mkdir()
            target = actual / "uptime-kuma"
            target.mkdir()
            link = root / "linked-parent"
            link.symlink_to(actual, target_is_directory=True)
            with patch.object(transition, "STATE", state), \
                    patch.object(transition, "BACKUP_ROOTS", ()), \
                    patch.object(transition, "STANDALONE", (link / "uptime-kuma",)):
                with self.assertRaises(RuntimeError):
                    transition.delete_kuma_data()
            self.assertTrue(target.exists())

    def test_health_failure_prevents_persistence_and_deletion(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            system = root / "system"
            units = system / "etc/systemd/system"
            units.mkdir(parents=True)
            (units / "gatus.service").touch()
            (system / "bin").mkdir()
            (system / "bin/switch-to-configuration").touch()
            with patch.object(transition, "STATE", root / "state"), \
                    patch.object(Path, "is_relative_to", return_value=True), \
                    patch.object(transition.common, "check_supervisors"), \
                    patch.object(transition, "prepare_postgres"), \
                    patch.object(transition.common, "run") as run, \
                    patch.object(transition, "verify_monitoring", side_effect=RuntimeError("unhealthy")), \
                    patch.object(transition, "delete_kuma_data") as cleanup:
                with self.assertRaises(RuntimeError):
                    transition.activate(system, True)
            cleanup.assert_not_called()
            self.assertFalse(any(call.args[0][0] == "nix-env" for call in run.call_args_list))


if __name__ == "__main__":
    unittest.main()
