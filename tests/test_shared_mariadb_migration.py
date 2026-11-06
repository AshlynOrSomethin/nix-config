import importlib.util
import json
import shutil
import subprocess
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


DIRECTORY = Path(__file__).resolve().parents[1] / "server/native-migration"
sys.path.insert(0, str(DIRECTORY))
spec = importlib.util.spec_from_file_location("shared_migration", DIRECTORY / "shared-mariadb.py")
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


class SharedMariaDBTests(unittest.TestCase):
    def test_mysql_client_preserves_full_unicode(self):
        args = migration.common.mariadb_args({"host": "localhost", "port": 3306, "user": "test"})
        self.assertIn("--default-character-set=utf8mb4", args)

    def test_row_proof_preserves_duplicates_nulls_and_unicode(self):
        fields = [("body", "text", "text")]
        first = migration.row_fingerprints('["\\ud83e\\udd8a"]\n[null]\n[""]\n[""]\n', fields)
        reordered = migration.row_fingerprints('[""]\n[""]\n[null]\n["\\ud83e\\udd8a"]\n', fields)
        fewer = migration.row_fingerprints('[""]\n[null]\n["\\ud83e\\udd8a"]\n', fields)
        self.assertEqual(first, reordered)
        self.assertNotEqual(first, fewer)
        self.assertEqual(sum(first.values()), 4)

    def test_row_proof_rejects_changed_column_count(self):
        with self.assertRaises(RuntimeError):
            migration.row_fingerprints('["one","two"]\n', [("body", "text", "text")])

    def test_timestamp_comparison_preserves_instant(self):
        self.assertEqual(migration.normalized("2026-11-06 20:00:00", "timestamp"),
                         migration.normalized("2026-11-06 14:00:00-06:00", "timestamp"))
        self.assertNotEqual(migration.normalized("2026-11-06 20:00:00", "timestamp"),
                            migration.normalized("2026-11-06 20:00:00-06:00", "timestamp"))
        self.assertEqual(migration.normalized("1.000", "decimal"), "1")

    def test_unsigned_bigint_overflow_refuses_conversion(self):
        with patch.object(migration.common, "mariadb_query", return_value="1\n"):
            with self.assertRaises(RuntimeError):
                migration.check_bigints({}, {"table": [("id", "bigint", "bigint unsigned")]})

    def test_panel_environment_preserves_app_key_and_unrelated_settings(self):
        source = "APP_KEY=base64:unchanged\nDB_CONNECTION=mariadb\nDB_PASSWORD=old\nMAIL_PASSWORD=kept\nDB_URL=old\n"
        result = migration.panel_environment(source, "/run/postgresql", "pelican-panel")
        for setting in ["APP_KEY=base64:unchanged", "MAIL_PASSWORD=kept",
                        "DB_CONNECTION=pgsql", "DB_HOST=/run/postgresql",
                        "DB_USERNAME=pelican-panel", "DB_DATABASE=pelican", "DB_PASSWORD=\n", "DB_URL=\n"]:
            self.assertIn(setting, result)
        self.assertEqual(result.count("DB_CONNECTION="), 1)

    def test_loader_password_is_environment_only_and_casts_keep_foreign_keys(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = {"user": "reader", "password": "special:@%password", "host": "127.0.0.1",
                      "port": 3306, "name": "source"}
            log = root / "freshrss-pgloader.log"
            log.write_text("LOG conversion completed\n")
            with patch.object(migration, "private_run") as run:
                migration.load_database("freshrss", source, root, [])
            command = run.call_args.args[0]
            config = (root / "freshrss.load").read_text()
            self.assertNotIn(source["password"], config)
            self.assertNotIn(source["password"], " ".join(command))
            self.assertEqual(run.call_args.kwargs["env"]["MYSQL_PWD"], source["password"])
            self.assertIn("type bigint to bigint drop typemod", config)
            self.assertIn("type tinyint to smallint drop typemod", config)
            self.assertIn(f"unix:{root}:5432/freshrss", config)
            self.assertIn("foreign keys", config)

    def test_pgloader_errors_are_fatal_even_with_exit_zero(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "pelican-pgloader.log").write_text("ERROR foreign key cannot be implemented\n")
            with patch.object(migration, "private_run"):
                with self.assertRaises(RuntimeError):
                    migration.load_database("pelican", {
                        "user": "test", "password": "", "host": "localhost", "port": 3306, "name": "panel",
                    }, root, [])

    def test_private_command_failure_is_explicit_and_retains_log(self):
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary) / "command.log"
            with self.assertRaisesRegex(RuntimeError, "private diagnostics"):
                migration.private_run([sys.executable, "-c", "raise SystemExit(4)"], log)
            self.assertTrue(log.exists())

    def test_proof_preserves_uncalled_sequence_next_values(self):
        from unittest.mock import Mock
        query = Mock(side_effect=["", "", "id_seq\n", "100|f\n"])
        result = migration.postgres_proof("test", query)
        self.assertEqual(query.call_args.args,
                         ("test", 'SELECT last_value, is_called FROM "id_seq";'))
        self.assertEqual(result["__sequences"]["id_seq"], "100|f")

    def test_finish_refuses_pre_writer_state(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "state.json").write_text(json.dumps({
                "stage": "restoring", "native_writers_started": False,
            }))
            with patch.object(migration, "BACKUPS", root), \
                    patch.object(migration, "validate_system") as validate:
                with self.assertRaises(RuntimeError):
                    migration.finish(Path("/nix/store/system"), root)
                validate.assert_not_called()

    def test_writer_start_records_irreversible_boundary_before_service_commands(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            state = {"stage": "restoring", "native_writers_started": False}

            def command(args, *extra, **kwargs):
                saved = json.loads((root / "state.json").read_text())
                self.assertTrue(saved["native_writers_started"])
                self.assertEqual(saved["stage"], "starting-writers")
                self.assertTrue((root / "ready").exists())

            with patch.object(migration, "STATE", root), \
                    patch.object(migration.common, "run", side_effect=command), \
                    patch.object(migration, "private_run", side_effect=command):
                migration.start_writers(root, state)

    def test_unhealthy_finish_never_persists_system(self):
        with patch.object(migration.common, "wait_http", side_effect=RuntimeError("unhealthy")), \
                patch.object(migration.common, "run") as run:
            with self.assertRaises(RuntimeError):
                migration.persist(Path("/nix/store/system"), Path("/backup"), {})
            run.assert_not_called()

    def test_finish_preserves_live_data_and_applies_only_corrective_configuration(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "ready").touch()
            state = {
                "stage": "needs-attention", "native_writers_started": True,
                "target": str(Path("/run/current-system").resolve()),
            }
            (root / "state.json").write_text(json.dumps(state))
            system = Path("/nix/store/corrected-system")
            with patch.object(migration, "STATE", root), \
                    patch.object(migration, "BACKUPS", root), \
                    patch.object(migration, "validate_system"), \
                    patch.object(migration.common, "run") as run, \
                    patch.object(migration, "start_writers") as start, \
                    patch.object(migration, "persist") as persist, \
                    patch.object(migration, "load_database") as load, \
                    patch.object(migration.common, "copy_tree") as copy:
                migration.finish(system, root)
            start.assert_called_once()
            persist.assert_called_once()
            load.assert_not_called()
            copy.assert_not_called()
            self.assertEqual(run.call_args_list[-1].args[0],
                             [str(system / "bin/switch-to-configuration"), "test"])

    def test_full_unicode_php_config_rewrite_retains_non_database_settings(self):
        if not shutil.which("php"):
            self.skipTest("PHP is required")
        with tempfile.TemporaryDirectory() as temporary:
            config = Path(temporary) / "config.php"
            config.write_text("<?php return ['title'=>'Existing title','db'=>["
                              "'type'=>'mysql','prefix'=>'keep_','password'=>'old']];")
            migration.configure_fresh(config, "/run/postgresql", "freshrss", "new:'$password")
            result = migration.php_json("$c=include $argv[1]; echo json_encode($c);", config)
            self.assertEqual(result["title"], "Existing title")
            self.assertEqual(result["db"]["prefix"], "keep_")
            self.assertEqual(result["db"]["type"], "pgsql")
            self.assertEqual(result["db"]["password"], "new:'$password")


@unittest.skipUnless(shutil.which("initdb"), "PostgreSQL binaries are required")
class PostgresProofTests(unittest.TestCase):
    def create_panel_json_tables(self, query):
        query("postgres", "CREATE DATABASE pelican;")
        for table, fields in migration.PANEL_JSON_COLUMNS.items():
            definitions = ", ".join(f'{migration.common.identifier(field)} text' for field in fields)
            query("pelican", f"CREATE TABLE {migration.common.identifier(table)} ({definitions});")

    def test_panel_json_repair_preserves_values_and_enables_notification_query(self):
        with tempfile.TemporaryDirectory(prefix="panel-json-test-") as temporary:
            with migration.temporary_postgres(Path(temporary)) as (query, _):
                self.create_panel_json_tables(query)
                query("pelican", """
                    INSERT INTO notifications VALUES
                    ('{ "format" : "filament", "unicode" : "\\uD83E\\uDD8A" }'),
                    ('{ "format" : "filament", "unicode" : "\\uD83E\\uDD8A" }'),
                    ('null'), (NULL);
                """)
                before = query("pelican", "SELECT data::text FROM notifications ORDER BY data::text NULLS FIRST;")
                query("pelican", migration.panel_json_sql())
                query("pelican", migration.panel_json_sql())
                self.assertEqual(before, query("pelican", """
                    SELECT data::text FROM notifications ORDER BY data::text NULLS FIRST;
                """))
                self.assertEqual(query("pelican", """
                    SELECT count(*) FROM notifications WHERE data->>'format'='filament';
                """).strip(), "2")
                self.assertEqual(query("pelican", """
                    SELECT count(*) FROM information_schema.columns
                    WHERE table_schema='public' AND data_type='json';
                """).strip(), "20")

    def test_panel_json_repair_invalid_data_rolls_back_every_column(self):
        with tempfile.TemporaryDirectory(prefix="panel-json-test-") as temporary:
            with migration.temporary_postgres(Path(temporary)) as (query, _):
                self.create_panel_json_tables(query)
                query("pelican", "INSERT INTO webhooks VALUES ('invalid JSON');")
                with self.assertRaises(subprocess.CalledProcessError):
                    query("pelican", migration.panel_json_sql())
                self.assertEqual(query("pelican", """
                    SELECT count(*) FROM information_schema.columns
                    WHERE table_schema='public' AND data_type='json';
                """).strip(), "0")
                self.assertEqual(query("pelican", "SELECT payload FROM webhooks;").strip(), "invalid JSON")

    def test_dump_restore_preserves_all_rows_foreign_keys_and_uncalled_sequences(self):
        with tempfile.TemporaryDirectory(prefix="shared-proof-test-") as temporary:
            root = Path(temporary)
            with migration.temporary_postgres(root) as (query, prefix):
                self.assertEqual(prefix, [])
                query("postgres", "CREATE ROLE native_owner LOGIN; CREATE DATABASE original;")
                query("postgres", "CREATE DATABASE restored OWNER native_owner;")
                query("original", """
                    CREATE TABLE parent (id BIGSERIAL PRIMARY KEY, title TEXT, created TIMESTAMPTZ);
                    CREATE TABLE child (parent BIGINT REFERENCES parent(id), content TEXT);
                    INSERT INTO parent VALUES (1, 'Unicode ' || chr(129418), '2026-11-06 20:00:00+00');
                    INSERT INTO child VALUES (1, ''), (1, ''), (1, NULL);
                    SELECT setval('parent_id_seq', 100, false);
                """)
                before = migration.postgres_proof("original", query)
                dump = root / "converted.dump"
                subprocess.run([
                    "pg_dump", "-h", str(root), "-U", "postgres", "-d", "original",
                    "--format=custom", "--no-owner", "--no-acl", "--file", str(dump),
                ], check=True, stdout=subprocess.DEVNULL)
                with dump.open("rb") as stream:
                    subprocess.run([
                        "pg_restore", "-h", str(root), "-U", "postgres", "-d", "restored",
                        "--role=native_owner", "--no-owner", "--no-acl", "--exit-on-error",
                    ], check=True, stdin=stream)
                self.assertEqual(before, migration.postgres_proof("restored", query))
                self.assertEqual(query("restored", "SELECT nextval('parent_id_seq');").strip(), "100")
                query("restored", "DELETE FROM child WHERE content IS NULL;")
                self.assertNotEqual(before, migration.postgres_proof("restored", query))


if __name__ == "__main__":
    unittest.main()
