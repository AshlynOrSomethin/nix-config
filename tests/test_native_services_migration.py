import importlib.util
from contextlib import closing
import os
import json
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile
import unittest
from unittest.mock import patch


MODULE = Path(__file__).resolve().parents[1] / "server/native-migration/migrate.py"
spec = importlib.util.spec_from_file_location("native_migration", MODULE)
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


class NativeMigrationTests(unittest.TestCase):
    def test_forgejo_conversion_retains_secrets_and_paths(self):
        source = """APP_NAME = Existing Forge
RUN_USER = git
[database]
DB_TYPE = mysql
HOST = 172.17.0.1:3306
NAME = forgejo
USER = forgejo
PASSWD = old-password
[server]
ROOT_URL = https://git.example.test/
SSH_PORT = 22
LFS_JWT_SECRET = existing-lfs
[security]
SECRET_KEY = existing-encryption-key
INTERNAL_TOKEN = existing-token
[mailer]
PASSWD = smtp-password-with-%-character
[repository]
ROOT = /data/git/repositories
[session]
PROVIDER_CONFIG = /data/gitea/sessions
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "app.ini"
            path.write_text(source)
            path.write_text(migration.convert_forgejo_config(migration.read_ini(path)))
            converted = migration.read_ini(path)
        self.assertEqual(converted["database"]["DB_TYPE"], "postgres")
        self.assertEqual(converted["database"]["HOST"], "/run/postgresql")
        self.assertEqual(converted["database"]["PASSWD"], "")
        self.assertEqual(converted["DEFAULT"]["RUN_USER"], "forgejo")
        self.assertEqual(converted["server"]["HTTP_PORT"], "3005")
        self.assertEqual(converted["server"]["HTTP_ADDR"], "0.0.0.0")
        self.assertEqual(converted["server"]["SSH_LISTEN_PORT"], "222")
        self.assertEqual(converted["server"]["SSH_PORT"], "22")
        self.assertEqual(converted["server"]["ROOT_URL"], "https://git.example.test/")
        self.assertEqual(converted["server"]["LFS_JWT_SECRET"], "existing-lfs")
        self.assertEqual(converted["security"]["SECRET_KEY"], "existing-encryption-key")
        self.assertEqual(converted["security"]["INTERNAL_TOKEN"], "existing-token")
        self.assertEqual(converted["mailer"]["PASSWD"], "smtp-password-with-%-character")
        self.assertEqual(converted["repository"]["ROOT"], "/data/git/repositories")
        self.assertEqual(converted["session"]["PROVIDER_CONFIG"], "/data/gitea/sessions")
        self.assertEqual(converted["server"]["START_SSH_SERVER"], "true")
        self.assertIn("/data/ssh/ssh_host_ed25519_key", converted["server"]["SSH_SERVER_HOST_KEYS"])

    def test_environment_rewrite_keeps_secrets_verbatim(self):
        original = "# preserved\nPASSWORD=literal$secret=#value\nPOSTGRES_HOST=postgres\nPOSTGRES_HOST=other\n"
        result = migration.rewrite_environment(original, {
            "POSTGRES_HOST": "/run/postgresql", "POSTGRES_USER": "bitmagnet",
        })
        self.assertIn("PASSWORD=literal$secret=#value\n", result)
        self.assertEqual(result.count("POSTGRES_HOST="), 1)
        self.assertIn("POSTGRES_HOST=/run/postgresql\n", result)
        self.assertIn("POSTGRES_USER=bitmagnet\n", result)

    def test_environment_rewrite_rejects_multiline_values(self):
        with self.assertRaises(ValueError):
            migration.rewrite_environment("", {"KEY": "value\nINJECTED=true"})

    def test_sql_quoting(self):
        self.assertEqual(migration.literal("can't"), "'can''t'")
        self.assertEqual(migration.identifier('a"b'), '"a""b"')
        self.assertEqual(migration.identifier("a`b", "`"), "`a``b`")

    def test_sqlite_integrity_and_exact_counts(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "existing.sqlite"
            with closing(sqlite3.connect(path)) as database:
                database.execute('CREATE TABLE "odd""table" (id INTEGER)')
                database.executemany('INSERT INTO "odd""table" VALUES (?)', [(1,), (2,)])
                database.commit()
            self.assertEqual(migration.sqlite_counts(path), {'odd"table': 2})

    def test_missing_sqlite_database_is_not_created(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "missing.sqlite"
            with self.assertRaises(sqlite3.OperationalError):
                migration.sqlite_counts(path)
            self.assertFalse(path.exists())

    def test_verification_fails_closed(self):
        with self.assertRaises(RuntimeError):
            migration.assert_equal({"users": 10}, {"users": 0}, "row counts")

    def test_mysql_auto_increment_values_are_preserved(self):
        with patch.object(migration, "postgres_query", return_value="public.users_id_seq\n") as query:
            migration.restore_forgejo_sequences([["users", "id", 100]])
        self.assertEqual(query.call_args.args,
                         ("forgejo", "SELECT setval('public.users_id_seq', 100, false);"))

    def test_missing_postgres_sequence_fails_closed(self):
        with patch.object(migration, "postgres_query", return_value="\n"):
            with self.assertRaises(RuntimeError):
                migration.restore_forgejo_sequences([["users", "id", 100]])

    def test_metadata_omitted_by_forgejo_export_is_preserved(self):
        schemas = [
            "id\tbigint\t0\tNO\tPRI\tauto_increment\nversion\tbigint\t0\tYES\t\t\n",
            "id\tvarchar\t255\tNO\tPRI\t\ncreated_unix\tbigint\t0\tYES\t\t\n",
        ]
        with patch.object(migration, "mariadb_query", side_effect=schemas), \
                patch.object(migration, "output", side_effect=['[1, 45]\n', '["migration;with\\u0027quote", 100]\n']):
            sql = migration.forgejo_metadata_sql({
                "host": "localhost", "port": 3306, "user": "test", "password": "", "name": "test",
            })
        self.assertIn('CREATE TABLE "forgejo_version"', sql)
        self.assertIn('INSERT INTO "forgejo_version" VALUES (1, 45)', sql)
        self.assertIn("migration;with''quote", sql)

    def test_unrecognized_forgejo_metadata_schema_is_rejected(self):
        with patch.object(migration, "mariadb_query", return_value="unexpected schema"):
            with self.assertRaises(RuntimeError):
                migration.forgejo_metadata_sql({})

    def test_postgres_inventory_counts_tables_and_sequences(self):
        with patch.object(migration, "postgres_query", side_effect=[
            '["public", "odd\\"table"]\n',
            '["table","public","odd\\"table",12]\n["sequence","public","users_id_seq",20]\n',
        ]) as query:
            result = migration.postgres_inventory("example")
        self.assertEqual(len(result), 2)
        self.assertIn('FROM "public"."odd""table"', query.call_args.args[1])
        self.assertIn("FROM pg_sequences", query.call_args.args[1])

    def test_finish_activates_and_verifies_without_restoring_live_data(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            backup = root / "backup"
            backup.mkdir()
            ready = root / "state"
            ready.mkdir()
            (ready / "ready").touch()
            state = {
                "target": str(Path("/run/current-system").resolve()),
                "stage": "needs-attention", "native_writers_started": True,
            }
            migration.save_json(backup / "state.json", state)
            system = Path("/nix/store/corrected-system")
            with patch.object(migration, "BACKUPS", root), patch.object(migration, "STATE", ready), \
                    patch.object(migration, "validate_system") as validate, \
                    patch.object(migration, "check_supervisors") as supervisors, \
                    patch.object(migration, "run") as run, \
                    patch.object(migration, "complete_cutover") as complete, \
                    patch.object(migration, "copy_tree") as copy, \
                    patch.object(migration, "postgres_query") as query:
                migration.finish_cutover(system, backup, allow_docker_restart=True)
            validate.assert_called_once_with(system)
            supervisors.assert_called_once_with(system, True)
            self.assertEqual(run.call_args_list[1].args[0],
                             [str(system / "bin/switch-to-configuration"), "test"])
            self.assertEqual(run.call_args_list[-1].args[0],
                             ["systemctl", "start", *migration.NATIVE, *migration.CLIENTS])
            complete.assert_called_once()
            copy.assert_not_called()
            query.assert_not_called()
            saved = json.loads((backup / "state.json").read_text())
            self.assertEqual(saved["recovery_system"], str(system))
            self.assertTrue(saved["native_writers_started"])

    def test_finish_rejects_unrelated_or_pre_writer_state(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "ready").touch()
            for updates in [
                {"stage": "rolled-back"},
                {"native_writers_started": False},
                {"target": "/nix/store/unrelated-system"},
            ]:
                state = {
                    "target": str(Path("/run/current-system").resolve()),
                    "stage": "needs-attention", "native_writers_started": True,
                    **updates,
                }
                migration.save_json(root / "state.json", state)
                with self.subTest(updates=updates), \
                        patch.object(migration, "BACKUPS", root), \
                        patch.object(migration, "STATE", root), \
                        patch.object(migration, "run") as run:
                    with self.assertRaises(RuntimeError):
                        migration.finish_cutover(Path("/nix/store/corrected-system"), root)
                    run.assert_not_called()

    def test_finish_failure_keeps_recovery_state_and_never_rolls_back(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "ready").touch()
            state = {
                "target": str(Path("/run/current-system").resolve()),
                "stage": "needs-attention", "native_writers_started": True,
            }
            migration.save_json(root / "state.json", state)
            with patch.object(migration, "BACKUPS", root), patch.object(migration, "STATE", root), \
                    patch.object(migration, "validate_system"), \
                    patch.object(migration, "check_supervisors"), \
                    patch.object(migration, "complete_cutover") as complete, \
                    patch.object(migration, "restore_old_system") as rollback, \
                    patch.object(migration, "run", side_effect=[
                        None, subprocess.CalledProcessError(4, ["switch-to-configuration"]),
                    ]):
                with self.assertRaises(subprocess.CalledProcessError):
                    migration.finish_cutover(Path("/nix/store/corrected-system"), root)
            saved = json.loads((root / "state.json").read_text())
            self.assertEqual(saved["stage"], "needs-attention")
            self.assertEqual(saved["recovery_system"], "/nix/store/corrected-system")
            self.assertEqual(saved["target"], state["target"])
            complete.assert_not_called()
            rollback.assert_not_called()

    def test_unhealthy_cutover_is_not_persisted(self):
        with patch.object(migration, "wait_http", side_effect=RuntimeError("unhealthy")), \
                patch.object(migration, "run") as run:
            with self.assertRaises(RuntimeError):
                migration.complete_cutover(Path("/nix/store/new"), Path("/backup"), {})
            run.assert_not_called()

    def test_healthy_cutover_verifies_keys_and_persists_profile_and_boot(self):
        with tempfile.TemporaryDirectory() as temporary:
            backup = Path(temporary)
            keys = backup / "forgejo/ssh"
            keys.mkdir(parents=True)
            (keys / "ssh_host_ed25519_key.pub").write_text("ssh-ed25519 test-key\n")
            state = {"stage": "needs-attention", "native_writers_started": True}
            system = Path("/nix/store/corrected-system")
            with patch.object(migration, "wait_http") as health, \
                    patch.object(migration, "docker_inspect", return_value={
                        "State": {"Health": {"Status": "healthy"}},
                    }), patch.object(migration, "output", return_value="host ssh-ed25519 test-key\n"), \
                    patch.object(migration, "failed_units", return_value=[]), \
                    patch.object(migration, "run") as run:
                migration.complete_cutover(system, backup, state)
            self.assertEqual(health.call_count, 6)
            health.assert_any_call("http://127.0.0.1:8842/healthz")
            self.assertNotIn(("http://127.0.0.1:8842/",),
                             [call.args for call in health.call_args_list])
            self.assertEqual(run.call_args_list[-2].args[0], [
                "nix-env", "--profile", "/nix/var/nix/profiles/system", "--set", str(system),
            ])
            self.assertEqual(run.call_args_list[-1].args[0],
                             [str(system / "bin/switch-to-configuration"), "boot"])
            self.assertEqual(json.loads((backup / "state.json").read_text())["stage"], "complete")

    def test_rollback_stops_writers_before_restoring_original_system(self):
        state = {
            "old_system": "/nix/store/old-system",
            "old_profile": "/nix/store/old-profile",
            "original_active": ["docker-forgejo", "docker-authentik-postgresql-1"],
        }
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "ready").touch()
            with patch.object(migration, "STATE", root), patch.object(migration, "run") as run:
                run.return_value.returncode = 0
                migration.restore_old_system(state)
            self.assertFalse((root / "ready").exists())
        self.assertEqual(run.call_args_list[0].args[0][:2], ["systemctl", "stop"])
        self.assertIn("postgresql", run.call_args_list[0].args[0])
        self.assertEqual(run.call_args_list[1].args[0],
                         ["/nix/store/old-system/bin/switch-to-configuration", "test"])
        self.assertEqual(run.call_args_list[-2].args[0],
                         ["systemctl", "start", *state["original_active"]])
        self.assertEqual(run.call_args_list[-3].args[0],
                         ["/nix/store/old-profile/bin/switch-to-configuration", "boot"])

    def test_unit_snapshot_includes_nixos_dropins(self):
        with tempfile.TemporaryDirectory() as temporary:
            system = Path(temporary)
            directory = system / "etc/systemd/system"
            dropins = directory / "docker.service.d"
            dropins.mkdir(parents=True)
            (directory / "docker.service").write_text("[Service]\nExecStart=base\n")
            (dropins / "overrides.conf").write_text("[Service]\nExecStart=override\n")
            snapshot = migration.unit_contents(system, "docker.service")
        self.assertEqual(set(snapshot), {"docker.service", "docker.service.d/overrides.conf"})
        self.assertIn(b"ExecStart=override", snapshot["docker.service.d/overrides.conf"])

    def test_docker_dropin_change_requires_explicit_restart_authorization(self):
        target = Path("/nix/store/new-system")

        def contents(system, name):
            return {"unit": b"changed" if system == target and name == "docker.service" else b"original"}

        with patch.object(migration, "unit_contents", side_effect=contents):
            with self.assertRaisesRegex(RuntimeError, "--allow-docker-restart"):
                migration.check_supervisors(target, False)
            migration.check_supervisors(target, True)

    def test_retry_archives_copies_without_deleting_them(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            backup = root / "backup"
            backup.mkdir()
            native = root / "native"
            native.mkdir()
            (native / "retained").write_text("data")
            state_dir = root / "state"
            state_dir.mkdir()
            (state_dir / "credentials.env").write_text("SECRET=keep")
            state = {"stage": "restoring"}
            with patch.object(migration, "NATIVE_PATHS", {"native": native}), \
                    patch.object(migration, "STATE", state_dir):
                migration.archive_retry(backup, state)
            archived = backup / "unfinished-native-copies"
            self.assertEqual((archived / "native/retained").read_text(), "data")
            self.assertEqual((archived / "migration-state/credentials.env").read_text(), "SECRET=keep")
            self.assertFalse(native.exists())
            self.assertFalse(state_dir.exists())
            self.assertEqual(json.loads((backup / "state.json").read_text())["stage"], "archived-for-retry")

    def test_retry_refuses_post_cutover_data(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            backup = root / "backup"
            backup.mkdir()
            (backup / "state.json").write_text(json.dumps({
                "stage": "needs-attention", "native_writers_started": True,
            }))
            with patch.object(migration, "BACKUPS", root), patch.object(migration, "STATE", root / "state"):
                with self.assertRaises(RuntimeError):
                    migration.validate_retry(backup)

    def test_rollback_completes_profile_and_boot_before_reporting_unknown_failures(self):
        state = {
            "old_system": "/nix/store/old-system", "old_profile": "/nix/store/old-profile",
            "original_active": ["docker-forgejo"],
        }
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(migration, "STATE", Path(temporary)), \
                    patch.object(migration, "run") as run, \
                    patch.object(migration, "failed_units", return_value=["unrelated.service"]):
                run.return_value.returncode = 4
                with self.assertRaises(RuntimeError):
                    migration.restore_old_system(state)
            commands = [call.args[0] for call in run.call_args_list]
            self.assertIn(["/nix/store/old-profile/bin/switch-to-configuration", "boot"], commands)
            self.assertIn(["systemctl", "start", "docker-forgejo"], commands)

    def test_rollback_recovers_only_the_known_database_readiness_failure(self):
        state = {
            "old_system": "/nix/store/old-system", "old_profile": "/nix/store/old-profile",
            "original_active": ["docker-forgejo"],
        }
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(migration, "STATE", Path(temporary)), \
                    patch.object(migration, "run") as run, \
                    patch.object(migration, "wait_mariadb") as wait, \
                    patch.object(migration, "failed_units", return_value=["pelican-panel-upgrade.service"]):
                run.return_value.returncode = 4
                migration.restore_old_system(state)
            wait.assert_called_once()
            commands = [call.args[0] for call in run.call_args_list]
            self.assertIn(["systemctl", "restart", "pelican-panel-upgrade.service"], commands)


@unittest.skipUnless(shutil.which("initdb") and os.geteuid() != 0,
                     "Requires PostgreSQL tools and a non-root user")
class PostgresRestoreTests(unittest.TestCase):
    def test_role_restore_extensions_rows_and_sequences(self):
        with tempfile.TemporaryDirectory(prefix="native-pg-test-") as temporary:
            root = Path(temporary)
            data = root / "data"
            subprocess.run(["initdb", "-D", str(data), "-U", "postgres", "--no-locale",
                            "--auth-local=trust"], check=True, stdout=subprocess.DEVNULL)
            subprocess.run([
                "pg_ctl", "-D", str(data), "-l", str(root / "server.log"), "-w", "start",
                "-o", f"-k {root} -p 65431 -c listen_addresses=''",
            ], check=True, stdout=subprocess.DEVNULL)
            try:
                connection = ["-h", str(root), "-p", "65431", "-U", "postgres"]

                def query(database, sql, source=None):
                    self.assertIsNone(source)
                    return subprocess.run(
                        ["psql", *connection, "-XqAt", "-v", "ON_ERROR_STOP=1", "-d", database],
                        input=sql, text=True, stdout=subprocess.PIPE, check=True,
                    ).stdout

                query("postgres", "CREATE ROLE native_owner LOGIN; CREATE DATABASE original;")
                query("postgres", "CREATE DATABASE restored OWNER native_owner;")
                query("original", """
                    CREATE EXTENSION pg_trgm;
                    CREATE EXTENSION btree_gin;
                    CREATE TABLE example (id SERIAL PRIMARY KEY, title TEXT);
                    INSERT INTO example (title) VALUES ('first'), ('second');
                    CREATE INDEX example_search ON example USING gin (title gin_trgm_ops);
                """)
                dump = root / "original.dump"
                subprocess.run([
                    "pg_dump", *connection, "-d", "original", "--format=custom",
                    "--no-owner", "--no-acl", "--file", str(dump),
                ], check=True)
                subprocess.run([
                    "pg_restore", *connection, "-d", "restored", "--role=native_owner",
                    "--no-owner", "--no-acl", "--exit-on-error", str(dump),
                ], check=True)
                with patch.object(migration, "postgres_query", side_effect=query):
                    original = migration.postgres_inventory("original")
                    restored = migration.postgres_inventory("restored")
                self.assertEqual(original, restored)
                self.assertEqual(
                    query("restored", "SELECT tableowner FROM pg_tables WHERE tablename='example';").strip(),
                    "native_owner",
                )
                self.assertEqual(query("restored", "SELECT count(*) FROM pg_extension;").strip(), "3")

                def forgejo_query(database, sql, source=None):
                    self.assertEqual(database, "forgejo")
                    return query("restored", sql, source)

                with patch.object(migration, "postgres_query", side_effect=forgejo_query):
                    migration.restore_forgejo_sequences([["example", "id", 100]])
                self.assertEqual(query("restored", "SELECT nextval('example_id_seq');").strip(), "100")
                if importlib.util.find_spec("pglast"):
                    query("postgres", "CREATE DATABASE converted OWNER native_owner;")
                    export = """
                        CREATE TABLE child (
                            id BIGSERIAL PRIMARY KEY,
                            parent_id BIGINT,
                            label TEXT,
                            CONSTRAINT child_parent FOREIGN KEY (parent_id) REFERENCES parent(id)
                        );
                        INSERT INTO child VALUES (1, 2, 'semicolon; and ''quote''');
                        CREATE TABLE parent (
                            id BIGSERIAL PRIMARY KEY,
                            child_id BIGINT REFERENCES child(id)
                        );
                        INSERT INTO parent VALUES (2, 1);
                    """
                    query("converted", "BEGIN; SET ROLE native_owner;\n"
                          + migration.prepare_forgejo_sql(export) + "\nCOMMIT;")
                    self.assertEqual(
                        query("converted", "SELECT label FROM child;").strip(),
                        "semicolon; and 'quote'",
                    )
                    self.assertEqual(
                        query("converted", "SELECT count(*) FROM pg_constraint WHERE contype='f' AND convalidated;").strip(),
                        "2",
                    )
            finally:
                subprocess.run(["pg_ctl", "-D", str(data), "-m", "fast", "-w", "stop"],
                               check=True, stdout=subprocess.DEVNULL)


if __name__ == "__main__":
    unittest.main()
