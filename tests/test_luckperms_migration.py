import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


DIRECTORY = Path(__file__).resolve().parents[1] / "server/native-migration"
sys.path.insert(0, str(DIRECTORY))
spec = importlib.util.spec_from_file_location("luckperms_migration", DIRECTORY / "luckperms.py")
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)

CONFIG = """storage-method: h2
data:
  address: old-host
  database: old-db
  username: old-user
  password: old-password
  pool-settings:
    properties:
      useUnicode: true
      characterEncoding: utf8
      #useSSL: false
  table-prefix: 'luckperms_'
split-storage:
  # Must remain disabled.
  enabled: false
redis:
  password: unrelated-password
"""


class LuckPermsTests(unittest.TestCase):
    def test_config_preserves_unrelated_settings_and_removes_mysql_properties(self):
        result = migration.rewritten_config(CONFIG, "fresh_password")
        for value in ("storage-method: PostgreSQL", "address: '172.18.0.1:5432'",
                      "database: 's14_minecraft'", "username: 's14_minecraft'",
                      "password: 'fresh_password'", "properties: {}",
                      "password: unrelated-password"):
            self.assertIn(value, result)
        self.assertNotIn("old-password", result)
        self.assertNotIn("useUnicode:", result)
        self.assertNotIn("characterEncoding:", result)

    def test_config_retains_other_driver_properties(self):
        result = migration.rewritten_config(
            CONFIG.replace("      useUnicode: true", "      sslmode: disable\n      useUnicode: true"),
            "fresh_password",
        )
        self.assertIn("    properties:\n", result)
        self.assertIn("      sslmode: disable", result)
        self.assertNotIn("properties: {}", result)

    def test_config_rejects_split_storage_custom_prefix_and_missing_fields(self):
        for text in (CONFIG.replace("enabled: false", "enabled: true"),
                     CONFIG.replace("'luckperms_'", "'custom_'"),
                     CONFIG.replace("  database: old-db\n", "")):
            with self.subTest(text=text):
                with self.assertRaises(RuntimeError):
                    migration.rewritten_config(text, "fresh_password")

    def test_export_refuses_unexpected_tables_and_unmigrated_messages(self):
        with self.assertRaises(RuntimeError):
            migration.export_dataset(lambda _: "unrelated\tid\tint\n")
        columns = "\n".join(f"{table}\tid\tint" for table in sorted(
            migration.TABLES | {"luckperms_messenger"}))
        with self.assertRaises(RuntimeError):
            migration.export_dataset(lambda sql: columns if "information_schema.columns" in sql else "1")

    def test_invalid_permission_boolean_refuses_conversion(self):
        data = {"luckperms_user_permissions": {
            "columns": [("value", "tinyint", "tinyint")], "rows": [["2"]],
        }}
        with self.assertRaises(RuntimeError):
            migration.postgres_sql("", data, {})

    def test_finish_never_reimports_or_overwrites_data(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "state.json").write_text(json.dumps({
                "stage": "starting", "system": "/nix/store/test-system",
            }))
            with patch.object(migration, "verify_live", side_effect=RuntimeError("unhealthy")), \
                    patch.object(migration, "refresh_postgres_auth"), \
                    patch.object(migration.common, "run") as run:
                with self.assertRaises(RuntimeError):
                    migration.finish(root)
            self.assertEqual([call.args[0] for call in run.call_args_list],
                             [["docker", "stop", "--timeout", "60", migration.SERVER],
                              ["docker", "start", migration.SERVER]])
            self.assertEqual(json.loads((root / "state.json").read_text())["stage"], "starting")

    def test_import_resume_compares_serialized_proofs_without_reimport(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config = root / "live-config.yml"
            config.write_text(CONFIG)
            (root / "config-before.yml").write_text(CONFIG)
            (root / "rows.json").write_text("{}")
            proof = {"luckperms_groups": [("row-hash", 2)], "__sequences": {"id_seq": "100|f"}}
            (root / "postgres-proof.json").write_text(json.dumps(proof))
            state = {"stage": "importing", "password": "fresh_password"}
            with patch.object(migration, "CONFIG", config), \
                    patch.object(migration.common, "output",
                                 return_value='[{"State":{"Running":false}}]'), \
                    patch.object(migration, "verify_dataset") as verify, \
                    patch.object(migration.shared, "postgres_proof", return_value=proof):
                migration.configure_imported_database(root, state)
            verify.assert_called_once()
            self.assertIn("password: 'fresh_password'", config.read_text())
            self.assertEqual(state["stage"], "starting")
            self.assertEqual(config.stat().st_mode & 0o777, 0o640)

    def test_import_resume_does_not_change_config_if_verified_data_differs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config = root / "live-config.yml"
            config.write_text(CONFIG)
            (root / "config-before.yml").write_text(CONFIG)
            (root / "rows.json").write_text("{}")
            (root / "postgres-proof.json").write_text('{"table": [["original", 1]]}')
            with patch.object(migration, "CONFIG", config), \
                    patch.object(migration.common, "output",
                                 return_value='[{"State":{"Running":false}}]'), \
                    patch.object(migration, "verify_dataset"), \
                    patch.object(migration.shared, "postgres_proof",
                                 return_value={"table": [("changed", 1)]}):
                with self.assertRaises(RuntimeError):
                    migration.configure_imported_database(root, {"stage": "importing"})
            self.assertEqual(config.read_text(), CONFIG)

    def test_import_resume_stops_running_target_only_after_full_verification(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config = root / "live-config.yml"
            config.write_text(CONFIG)
            (root / "config-before.yml").write_text(CONFIG)
            (root / "rows.json").write_text("{}")
            (root / "postgres-proof.json").write_text("{}")
            events = []
            with patch.object(migration, "CONFIG", config), \
                    patch.object(migration.common, "output",
                                 return_value='[{"State":{"Running":true}}]'), \
                    patch.object(migration, "verify_dataset",
                                 side_effect=lambda *args: events.append("verified")), \
                    patch.object(migration.shared, "postgres_proof", return_value={}), \
                    patch.object(migration.common, "run",
                                 side_effect=lambda command: events.append(command)):
                migration.configure_imported_database(
                    root, {"stage": "importing", "password": "fresh_password"})
            self.assertEqual(events, [
                "verified", ["docker", "stop", "--timeout", "60", migration.SERVER],
            ])
            self.assertIn("password: 'fresh_password'", config.read_text())

    def test_auth_refresh_runs_target_setup_and_reloads_without_restart(self):
        with tempfile.TemporaryDirectory() as temporary:
            system = Path(temporary)
            unit = system / "etc/systemd/system/postgresql.service"
            unit.parent.mkdir(parents=True)
            unit.write_text("ExecStartPre=/nix/store/test-target/bin/postgresql-pre-start\n")
            with patch.object(Path, "is_file", return_value=True), \
                    patch.object(migration.common, "run") as run, \
                    patch.object(migration, "live_query", side_effect=["t", "f", "1"]) as query:
                migration.refresh_postgres_auth(system)
            self.assertEqual(run.call_count, 1)
            self.assertEqual(run.call_args.args[0][-1],
                             "/nix/store/test-target/bin/postgresql-pre-start")
            self.assertEqual(query.call_args_list[0].args, ("postgres", "SELECT pg_reload_conf();"))

    def test_auth_refresh_restarts_database_when_hba_path_requires_it(self):
        with tempfile.TemporaryDirectory() as temporary:
            system = Path(temporary)
            unit = system / "etc/systemd/system/postgresql.service"
            unit.parent.mkdir(parents=True)
            unit.write_text("ExecStartPre=/nix/store/test-target/bin/postgresql-pre-start\n")
            with patch.object(Path, "is_file", return_value=True), \
                    patch.object(migration.common, "run") as run, \
                    patch.object(migration, "live_query", side_effect=["t", "t", "1"]):
                migration.refresh_postgres_auth(system)
            self.assertEqual(run.call_args_list[-1].args[0],
                             ["systemctl", "restart", "postgresql.service"])


@unittest.skipUnless(shutil.which("initdb"), "PostgreSQL binaries are required")
class PostgresConversionTests(unittest.TestCase):
    def test_hba_file_path_change_requires_postgresql_restart(self):
        with tempfile.TemporaryDirectory(prefix="luckperms-hba-test-") as temporary:
            root = Path(temporary)
            with migration.shared.temporary_postgres(root) as (query, _):
                original = query("postgres", "SHOW hba_file;").strip()
                replacement = root / "replacement-hba.conf"
                replacement.write_text("local s14_minecraft s14_minecraft scram-sha-256\n"
                                       + Path(original).read_text())
                query("postgres", "ALTER SYSTEM SET hba_file = "
                      + migration.common.literal(str(replacement)) + ";")
                query("postgres", "SELECT pg_reload_conf();")
                import time
                for _ in range(30):
                    pending = query("postgres", """
                        SELECT pending_restart FROM pg_settings WHERE name='hba_file';
                    """).strip()
                    if pending == "t":
                        break
                    time.sleep(0.1)
                self.assertEqual(pending, "t")
                self.assertEqual(query("postgres", "SHOW hba_file;").strip(), original)
                migration.shared.private_run([
                    "pg_ctl", "-D", str(root / "pg"), "-w", "restart",
                    "-o", f"-k {root} -p 5432 -c listen_addresses='' -c timezone=UTC",
                ], root / "restart.log")
                self.assertEqual(query("postgres", "SHOW hba_file;").strip(), str(replacement))

    @unittest.skipUnless(Path("/run/current-system/systemd/lib/systemd/systemd-socket-proxyd").is_file(),
                         "systemd socket proxy is required")
    def test_tcp_proxy_to_unix_socket_enforces_scram_password(self):
        with tempfile.TemporaryDirectory(prefix="luckperms-proxy-test-") as temporary:
            root = Path(temporary)
            with migration.shared.temporary_postgres(root) as (query, _):
                query("postgres", """
                    CREATE ROLE s14_minecraft LOGIN PASSWORD 'test-password';
                    CREATE DATABASE s14_minecraft OWNER s14_minecraft;
                """)
                hba = root / "pg/pg_hba.conf"
                hba.write_text("local s14_minecraft s14_minecraft scram-sha-256\n" + hba.read_text())
                query("postgres", "SELECT pg_reload_conf();")
                listener = socket.socket()
                listener.bind(("127.0.0.1", 0))
                listener.listen()
                port = listener.getsockname()[1]
                pid = os.fork()
                if pid == 0:
                    try:
                        os.dup2(listener.fileno(), 3)
                        os.set_inheritable(3, True)
                        binary = "/run/current-system/systemd/lib/systemd/systemd-socket-proxyd"
                        os.execve(binary, [binary, str(root / ".s.PGSQL.5432")],
                                  {**os.environ, "LISTEN_PID": str(os.getpid()), "LISTEN_FDS": "1"})
                    finally:
                        os._exit(1)
                try:
                    command = ["psql", "-h", "127.0.0.1", "-p", str(port),
                               "-U", "s14_minecraft", "-d", "s14_minecraft",
                               "-XAt", "-c", "SELECT current_user;"]
                    result = subprocess.run(command, env={
                        **os.environ, "PGPASSWORD": "test-password", "PGCONNECT_TIMEOUT": "5",
                    }, check=True, capture_output=True, text=True)
                    self.assertEqual(result.stdout.strip(), "s14_minecraft")
                    rejected = subprocess.run(command, env={
                        **os.environ, "PGPASSWORD": "wrong-password", "PGCONNECT_TIMEOUT": "5",
                    }, capture_output=True, text=True)
                    self.assertNotEqual(rejected.returncode, 0)
                    self.assertIn("password authentication failed", rejected.stderr)
                finally:
                    listener.close()
                    os.kill(pid, 15)
                    os.waitpid(pid, 0)

    def test_native_schema_conversion_keeps_values_booleans_and_next_ids(self):
        schema = """
            CREATE TABLE luckperms_user_permissions (
                id SERIAL PRIMARY KEY, permission VARCHAR(200) NOT NULL,
                value BOOLEAN NOT NULL, expiry BIGINT NOT NULL, contexts VARCHAR(200) NOT NULL
            );
        """
        data = {"luckperms_user_permissions": {
            "columns": [("id", "int", "int"), ("permission", "varchar", "varchar"),
                        ("value", "tinyint", "tinyint"), ("expiry", "bigint", "bigint"),
                        ("contexts", "varchar", "varchar")],
            "rows": [["1", "quote' and slash\\ and Unicode \U0001f98a", "1", "9223372036854775807", "{}"],
                     ["2", "negative.node", "0", "0", '{"server":"lobby"}']],
        }}
        with tempfile.TemporaryDirectory(prefix="luckperms-test-") as temporary:
            with migration.shared.temporary_postgres(Path(temporary)) as (query, _):
                query("postgres", "CREATE DATABASE s14_minecraft;")
                query(migration.DATABASE, migration.postgres_sql(
                    schema, data, {"luckperms_user_permissions": "100"}))
                migration.verify_dataset(query, data)
                self.assertEqual(query(migration.DATABASE, """
                    SELECT last_value,is_called FROM luckperms_user_permissions_id_seq;
                """).strip(), "100|f")
                self.assertEqual(query(migration.DATABASE, """
                    SELECT count(*) FROM luckperms_user_permissions WHERE value;
                """).strip(), "1")
                query(migration.DATABASE, "UPDATE luckperms_user_permissions SET value=TRUE;")
                with self.assertRaises(RuntimeError):
                    migration.verify_dataset(query, data)


if __name__ == "__main__":
    unittest.main()
