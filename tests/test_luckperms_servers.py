import base64
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


DIRECTORY = Path(__file__).resolve().parents[1] / "server/native-migration"
sys.path.insert(0, str(DIRECTORY))
spec = importlib.util.spec_from_file_location("luckperms_servers", DIRECTORY / "luckperms-servers.py")
servers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(servers)


def empty():
    return {table: [] for table in servers.single.TABLES}


def node(value=True, expiry=0, contexts="{}"):
    return {
        "id": 1, "name": "default", "permission": "example.node", "value": value,
        "server": "global", "world": "global", "expiry": expiry, "contexts": contexts,
    }


class MergePlanTests(unittest.TestCase):
    def test_missing_container_is_not_started_or_inspected_by_volume_uuid(self):
        with patch.object(servers.common, "output", return_value="") as output:
            self.assertIsNone(servers.inspect(servers.SERVERS[0]))
        output.assert_called_once_with(["docker", "container", "ls", "--all", "--quiet"])

    def test_container_is_matched_by_volume_not_name(self):
        container = {
            "Id": "actual-id",
            "Mounts": [{"Source": str(servers.volume(servers.SERVERS[0])),
                        "Destination": "/home/container", "RW": True}],
            "NetworkSettings": {"Networks": {"pelican_nw": {}}},
            "State": {"Running": False},
        }
        with patch.object(servers.common, "output", side_effect=[
            "actual-id\n", json.dumps([container]),
            json.dumps([{"IPAM": {"Config": [{"Gateway": "172.18.0.1"}]}}]),
        ]):
            self.assertEqual(servers.inspect(servers.SERVERS[0]), container)

    def test_multiple_containers_using_volume_are_rejected(self):
        container = {"Mounts": [{"Source": str(servers.volume(servers.SERVERS[0]))}]}
        with patch.object(servers.common, "output", side_effect=[
            "first\nsecond\n", json.dumps([container, container]),
        ]):
            with self.assertRaisesRegex(RuntimeError, "Multiple containers"):
                servers.inspect(servers.SERVERS[0])

    def test_identical_nodes_deduplicate_but_conflicting_values_require_decision(self):
        current, local = empty(), empty()
        current["luckperms_group_permissions"] = [node()]
        local["luckperms_group_permissions"] = [dict(node(), id=99)]
        additions, conflicts = servers.merge_plan(current, local)
        self.assertEqual(additions["luckperms_group_permissions"], [])
        self.assertEqual(conflicts, [])
        local["luckperms_group_permissions"] = [node(False), node(expiry=100)]
        _, conflicts = servers.merge_plan(current, local)
        self.assertEqual(len(conflicts), 2)

    def test_context_order_is_not_a_different_permission_scope(self):
        current, local = empty(), empty()
        current["luckperms_group_permissions"] = [node(contexts='{"a":1,"b":2}')]
        local["luckperms_group_permissions"] = [node(False, contexts='{"b":2,"a":1}')]
        additions, conflicts = servers.merge_plan(current, local)
        self.assertEqual(additions["luckperms_group_permissions"], [])
        self.assertEqual(len(conflicts), 1)
        local["luckperms_group_permissions"] = [node(contexts='{"b":2,"a":1}')]
        additions, conflicts = servers.merge_plan(current, local)
        self.assertEqual(additions["luckperms_group_permissions"], [])
        self.assertEqual(conflicts, [])

    def test_tracks_and_primary_groups_are_not_silently_overwritten(self):
        current, local = empty(), empty()
        current["luckperms_tracks"] = [{"name": "staff", "groups": '["mod","admin"]'}]
        local["luckperms_tracks"] = [{"name": "staff", "groups": '["admin","mod"]'}]
        current["luckperms_players"] = [{"uuid": "test", "username": "player", "primary_group": "default"}]
        local["luckperms_players"] = [{"uuid": "test", "username": "player", "primary_group": "admin"}]
        _, conflicts = servers.merge_plan(current, local)
        self.assertEqual({row["table"] for row in conflicts},
                         {"luckperms_tracks", "luckperms_players"})

    def test_additive_merge_preserves_distinct_rows_and_action_duplicate_counts(self):
        current, local = empty(), empty()
        current["luckperms_groups"] = [{"name": "default"}]
        local["luckperms_groups"] = [{"name": "default"}, {"name": "local"}]
        current["luckperms_actions"] = [{"id": 100, "action": "same"}]
        local["luckperms_actions"] = [{"id": 1, "action": "same"}, {"id": 2, "action": "same"}]
        additions, conflicts = servers.merge_plan(current, local)
        self.assertEqual(conflicts, [])
        self.assertEqual(additions["luckperms_groups"], [{"name": "local"}])
        self.assertEqual(additions["luckperms_actions"], [{"action": "same"}])

    def test_h2_parser_decodes_utf8_and_typed_values(self):
        output = []
        for table in sorted(servers.single.TABLES):
            output.append(f"TABLE\t{table}\tname\tvalue\texpiry")
            if table == "luckperms_groups":
                values = [base64.b64encode(value.encode()).decode()
                          for value in ("Unicode \U0001f98a", "TRUE", "100")]
                output.append("ROW\t" + "\t".join(values))
        data = servers.parse_h2("\n".join(output))
        self.assertEqual(data["luckperms_groups"],
                         [{"name": "Unicode \U0001f98a", "value": True, "expiry": 100}])

    def test_running_server_blocks_offline_cutover(self):
        with patch.object(servers, "inspect", return_value={"State": {"Running": True}}):
            with self.assertRaisesRegex(RuntimeError, "is running"):
                servers.assert_stopped()

    def test_config_replace_preserves_owner_and_refuses_concurrent_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "config.yml"
            path.write_text("before")
            path.chmod(0o777)
            servers.replace_config(path, "before", "after")
            self.assertEqual(path.read_text(), "after")
            self.assertEqual(path.stat().st_mode & 0o777, 0o640)
            self.assertEqual(path.stat().st_uid, os.getuid())
            with self.assertRaisesRegex(RuntimeError, "Config changed"):
                servers.replace_config(path, "before", "unexpected")
            self.assertEqual(path.read_text(), "after")

    def test_merge_failure_never_changes_configs_or_starts_servers(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "backup"
            configs = {}
            for server in servers.SERVERS:
                configs[server] = Path(temporary) / server
                configs[server].write_text("original")
            with patch.object(servers, "assert_stopped"), \
                    patch.object(servers, "source_password", return_value="secret"), \
                    patch.object(servers, "verify_connection"), \
                    patch.object(servers, "config", side_effect=configs.__getitem__), \
                    patch.object(servers.single, "rewritten_config", return_value="rewritten"), \
                    patch.object(servers, "read_h2", return_value=empty()), \
                    patch.object(servers, "read_postgres", return_value=empty()), \
                    patch.object(servers.common, "run") as run, \
                    patch.object(servers.common, "postgres_query", side_effect=RuntimeError("rollback")):
                with self.assertRaisesRegex(RuntimeError, "rollback"):
                    servers.apply(root)
            self.assertTrue(all(path.read_text() == "original" for path in configs.values()))
            self.assertEqual(len(run.call_args_list), 1)
            self.assertIn("pg_dump", run.call_args.args[0])

    def test_transactional_additive_merge_preserves_rows_ids_and_rolls_back_stale_plan(self):
        with tempfile.TemporaryDirectory(prefix="luckperms-merge-test-") as temporary:
            with servers.single.shared.temporary_postgres(Path(temporary)) as (query, _):
                query("postgres", "CREATE DATABASE s14_minecraft;")
                query(servers.single.DATABASE, """
                    CREATE TABLE luckperms_groups (name TEXT PRIMARY KEY);
                    CREATE TABLE luckperms_tracks (name TEXT PRIMARY KEY, groups TEXT);
                    CREATE TABLE luckperms_players (uuid TEXT PRIMARY KEY, username TEXT, primary_group TEXT);
                    CREATE TABLE luckperms_actions (id SERIAL PRIMARY KEY, action TEXT);
                    CREATE TABLE luckperms_group_permissions (
                        id SERIAL PRIMARY KEY, name TEXT, permission TEXT, value BOOLEAN,
                        server TEXT, world TEXT, expiry BIGINT, contexts TEXT);
                    CREATE TABLE luckperms_user_permissions (
                        id SERIAL PRIMARY KEY, uuid TEXT, permission TEXT, value BOOLEAN,
                        server TEXT, world TEXT, expiry BIGINT, contexts TEXT);
                    INSERT INTO luckperms_groups VALUES ('default');
                    INSERT INTO luckperms_players VALUES ('one','shared','default');
                    INSERT INTO luckperms_group_permissions
                        VALUES (nextval('luckperms_group_permissions_id_seq'),
                                'default','example.node',TRUE,'global','global',0,'{}');
                """)
                with patch.object(servers.common, "postgres_query", side_effect=query):
                    current = servers.read_postgres()
                    incoming = empty()
                    incoming["luckperms_groups"] = [{"name": "local"}]
                    incoming["luckperms_group_permissions"] = [
                        dict(node(), id=99),
                        dict(node(False, expiry=9223372036854775807), id=100,
                             permission="quote' slash\\ $check$ Unicode \U0001f98a"),
                    ]
                    incoming["luckperms_players"] = [{"uuid": "one", "username": "local", "primary_group": "admin"}]
                    incoming["luckperms_actions"] = [{"id": 99, "action": "a"}] * 2
                    additions, conflicts = servers.merge_plan(current, incoming)
                    self.assertEqual([conflict["table"] for conflict in conflicts], ["luckperms_players"])
                    query(servers.single.DATABASE, servers.merge_sql(current, additions))
                    merged = servers.read_postgres()
                    self.assertEqual(merged["luckperms_players"], current["luckperms_players"])
                    self.assertIn(current["luckperms_group_permissions"][0],
                                  merged["luckperms_group_permissions"])
                    added_node = next(row for row in merged["luckperms_group_permissions"] if row["id"] != 1)
                    self.assertFalse(added_node["value"])
                    self.assertEqual(added_node["expiry"], 9223372036854775807)
                    self.assertEqual(len(merged["luckperms_actions"]), 2)
                    repeat, _ = servers.merge_plan(merged, incoming)
                    self.assertTrue(all(not rows for rows in repeat.values()))
                    with self.assertRaises(subprocess.CalledProcessError):
                        query(servers.single.DATABASE, servers.merge_sql(current, additions))
                    self.assertEqual(servers.read_postgres(), merged)
                    extra = empty()
                    extra["luckperms_actions"] = [{"action": "must roll back"}]
                    query(servers.single.DATABASE, """
                        INSERT INTO luckperms_user_permissions
                        VALUES (nextval('luckperms_user_permissions_id_seq'),
                                'new-player','new.node',TRUE,'global','global',0,'{}');
                    """)
                    before_failure = servers.read_postgres()
                    with self.assertRaises(subprocess.CalledProcessError):
                        query(servers.single.DATABASE, servers.merge_sql(merged, extra))
                    self.assertEqual(servers.read_postgres(), before_failure)

    def test_real_h2_export_uses_read_only_copy_and_preserves_values(self):
        java = shutil.which("java")
        driver = servers.volume(servers.H2_SERVER) / "plugins/LuckPerms/libs/h2-driver-2.1.214.jar"
        if java is None or not driver.is_file():
            self.skipTest("JDK and installed LuckPerms H2 driver are required")
        with tempfile.TemporaryDirectory(prefix="luckperms-h2-test-") as temporary:
            root = Path(temporary)
            source = root / "Fixture.java"
            creates = " ".join(
                f's.execute("CREATE TABLE {table} (name VARCHAR, \\"value\\" BOOLEAN, expiry BIGINT)");'
                for table in sorted(servers.single.TABLES)
            )
            source.write_text("""
                import java.sql.*;
                import java.util.*;
                class Fixture {
                    public static void main(String[] args) throws Exception {
                        try (Connection c = DriverManager.getConnection("jdbc:h2:"+args[0], new Properties());
                             Statement s = c.createStatement()) {
            """ + creates + """
                            try (PreparedStatement p = c.prepareStatement(
                                    "INSERT INTO luckperms_groups VALUES (?,FALSE,9223372036854775807)")) {
                                p.setString(1, "quote' slash\\\\ Unicode \\u2603");
                                p.executeUpdate();
                            }
                            s.execute("INSERT INTO luckperms_groups VALUES (NULL,TRUE,0)");
                        }
                    }
                }
            """)
            database = root / "test"
            subprocess.run([java, "--class-path", str(driver), str(source), str(database)],
                           check=True, capture_output=True, text=True)
            original = (root / "test.mv.db").read_bytes()
            result = subprocess.run([
                java, "--class-path", str(driver), str(DIRECTORY / "LuckPermsH2Export.java"), str(database),
            ], check=True, capture_output=True, text=True)
            rows = servers.parse_h2(result.stdout)["luckperms_groups"]
            self.assertIn({"name": "quote' slash\\ Unicode \u2603", "value": False,
                           "expiry": 9223372036854775807}, rows)
            self.assertIn({"name": None, "value": True, "expiry": 0}, rows)
            self.assertEqual((root / "test.mv.db").read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
