import argparse
from contextlib import contextmanager
import datetime
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import tempfile
import time
import zipfile

import migrate as common


spec = importlib.util.spec_from_file_location("shared_mariadb", Path(__file__).with_name("shared-mariadb.py"))
shared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shared)

SERVER = "ae52fc19-aa2d-4b93-850a-0fc31766c961"
VOLUME = Path("/var/lib/pelican/volumes") / SERVER
CONFIG = VOLUME / "plugins/luckperms/config.yml"
DATABASE = "s14_minecraft"
BACKUPS = Path("/var/backups/luckperms")
TABLES = {
    "luckperms_actions", "luckperms_groups", "luckperms_group_permissions",
    "luckperms_players", "luckperms_tracks", "luckperms_user_permissions",
}


@contextmanager
def recovery_mariadb(root):
    for unit in ("docker-mariadb.service", "mysql.service", "mariadb.service"):
        if common.run(["systemctl", "is-active", "--quiet", unit], check=False).returncode == 0:
            raise RuntimeError(f"Refusing a physical copy while {unit} is running.")
    source = Path("/var/lib/mariadb")
    if not (source / DATABASE).is_dir():
        raise RuntimeError("Retained MariaDB source is missing.")
    clone = root / "mariadb-copy"
    common.run(["cp", "-a", "--reflink=auto", str(source), str(clone)])
    socket = root / "mariadb.sock"
    with (root / "mariadb.log").open("w") as log:
        process = subprocess.Popen([
            "mariadbd", "--no-defaults", f"--datadir={clone}", "--user=root",
            "--skip-networking", "--skip-grant-tables", "--skip-slave-start",
            "--event-scheduler=OFF", "--skip-log-bin", "--innodb-buffer-pool-size=64M",
            f"--socket={socket}", f"--pid-file={root / 'mariadb.pid'}",
        ], stdout=log, stderr=subprocess.STDOUT)
        args = ["mariadb", "--no-defaults", f"--socket={socket}", "--user=root",
                "--default-character-set=utf8mb4", "--batch", "--raw", "--skip-column-names"]

        def query(sql):
            return common.output([*args, DATABASE], input="SET time_zone='+00:00';\n" + sql)

        try:
            for _ in range(90):
                if process.poll() is not None:
                    raise RuntimeError(f"Recovery MariaDB exited; inspect {root / 'mariadb.log'}")
                if common.run([*args, "-e", "SELECT 1;"], check=False,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
                    break
                time.sleep(1)
            else:
                raise RuntimeError(f"Recovery MariaDB not ready; inspect {root / 'mariadb.log'}")
            with (root / "source-mariadb.sql").open("xb") as stream:
                common.run([
                    "mariadb-dump", "--no-defaults", f"--socket={socket}", "--user=root",
                    "--default-character-set=utf8mb4", "--single-transaction",
                    "--skip-lock-tables", "--hex-blob", DATABASE,
                ], stdout=stream, text=False)
            yield query
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=60)
    if process.returncode not in (0, -15):
        raise RuntimeError(f"Recovery MariaDB shutdown failed; retained {clone}")
    shutil.rmtree(clone)


def export_dataset(query):
    columns = {}
    rows = query("""
        SELECT TABLE_NAME,COLUMN_NAME,DATA_TYPE FROM information_schema.columns
        WHERE table_schema=DATABASE() ORDER BY TABLE_NAME,ORDINAL_POSITION;
    """)
    for row in rows.splitlines():
        table, column, kind = row.split("\t")
        columns.setdefault(table, []).append((column, kind, kind))
    common.assert_equal(TABLES | {"luckperms_messenger"}, set(columns), "source table set")
    common.assert_equal("0", query("SELECT count(*) FROM luckperms_messenger;").strip(),
                        "empty MariaDB messenger (PostgreSQL uses LISTEN/NOTIFY)")
    data = {}
    for table in sorted(TABLES):
        fields = columns[table]
        expressions = ", ".join(
            f"CAST({common.identifier(field[0], '`')} AS CHAR CHARACTER SET utf8mb4)" for field in fields
        )
        values = query(f"SELECT JSON_ARRAY({expressions}) FROM {common.identifier(table, '`')};")
        data[table] = {"columns": fields, "rows": [json.loads(row) for row in values.splitlines()]}
        print(f"{table}: preserving {len(data[table]['rows'])} rows", flush=True)
    next_ids = query("""
        SELECT TABLE_NAME,AUTO_INCREMENT FROM information_schema.tables
        WHERE table_schema=DATABASE() AND AUTO_INCREMENT IS NOT NULL
            AND TABLE_NAME <> 'luckperms_messenger' ORDER BY TABLE_NAME;
    """)
    return data, dict(row.split("\t") for row in next_ids.splitlines())


def postgres_sql(schema, data, next_ids):
    statements = ["BEGIN;", schema]
    for table, content in data.items():
        fields = content["columns"]
        names = ", ".join(common.identifier(field[0]) for field in fields)
        for row in content["rows"]:
            if len(row) != len(fields):
                raise RuntimeError("Source row width does not match schema.")
            values = []
            for field, value in zip(fields, row):
                if field[0] == "value":
                    if value not in ("0", "1"):
                        raise RuntimeError("Permission boolean is not 0 or 1.")
                    values.append("TRUE" if value == "1" else "FALSE")
                else:
                    values.append("NULL" if value is None else common.literal(value))
            statements.append(f"INSERT INTO {common.identifier(table)} ({names}) VALUES ({', '.join(values)});")
    for table, next_id in next_ids.items():
        if table not in TABLES or not next_id.isdigit() or int(next_id) < 1:
            raise RuntimeError("Unexpected source auto-increment metadata.")
        statements.append(
            f"SELECT setval(pg_get_serial_sequence({common.literal(table)}, 'id'), {int(next_id)}, false);"
        )
    return "\n".join([*statements, "COMMIT;"])


def verify_dataset(query, data):
    for table, content in data.items():
        fields = content["columns"]
        actual_columns = query(DATABASE, f"""
            SELECT column_name FROM information_schema.columns
            WHERE table_schema='public' AND table_name={common.literal(table)}
            ORDER BY ordinal_position;
        """).splitlines()
        common.assert_equal([field[0] for field in fields], actual_columns, f"{table} columns")
        expressions = [
            f"CASE WHEN {common.identifier(field[0])} THEN '1' ELSE '0' END"
            if field[0] == "value" else f"{common.identifier(field[0])}::text"
            for field in fields
        ]
        rows = query(DATABASE, f"""
            SELECT json_build_array({', '.join(expressions)}) FROM {common.identifier(table)};
        """)
        original = "\n".join(json.dumps(row, ensure_ascii=False) for row in content["rows"])
        common.assert_equal(shared.row_fingerprints(original, fields),
                            shared.row_fingerprints(rows, fields), f"{table} every value")


def rewritten_config(text, password):
    if not re.fullmatch(r"[A-Za-z0-9_-]+", password):
        raise RuntimeError("Unsafe generated password encoding.")
    text, count = re.subn(r"(?m)^storage-method:.*$", "storage-method: PostgreSQL", text)
    if count != 1:
        raise RuntimeError("Expected one LuckPerms storage-method.")
    section = re.search(r"(?ms)^data:\n.*?(?=^\S|\Z)", text)
    if section is None:
        raise RuntimeError("Missing LuckPerms data section.")
    data = section.group()
    for key, value in {
        "address": "'172.18.0.1:5432'", "database": f"'{DATABASE}'",
        "username": f"'{DATABASE}'", "password": f"'{password}'",
    }.items():
        data, count = re.subn(rf"(?m)^  {key}:.*$", f"  {key}: {value}", data)
        if count != 1:
            raise RuntimeError(f"Expected one data.{key} setting.")
    if not re.search(r"(?m)^  table-prefix: ['\"]?luckperms_['\"]?\s*$", data):
        raise RuntimeError("Unexpected LuckPerms table prefix.")
    if not re.search(r"(?m)^split-storage:\s*\n(?:[ \t]*#.*\n)*  enabled: false\s*$", text):
        raise RuntimeError("Split storage must be disabled.")
    data = re.sub(r"(?m)^      (?:useUnicode|characterEncoding):.*\n", "", data)
    properties = re.search(r"(?ms)^    properties:\n.*?(?=^  \S|\Z)", data)
    if properties and not re.search(r"(?m)^      [^#\s]", properties.group()):
        data = data[:properties.start()] + properties.group().replace(
            "    properties:\n", "    properties: {}\n", 1) + data[properties.end():]
    return text[:section.start()] + data + text[section.end():]


def prepare(root):
    with recovery_mariadb(root) as query:
        data, next_ids = export_dataset(query)
    jars = list((VOLUME / "plugins").glob("LuckPerms-Velocity-*.jar"))
    if len(jars) != 1:
        raise RuntimeError("Expected one installed LuckPerms Velocity JAR.")
    with zipfile.ZipFile(jars[0]) as jar:
        schema = jar.read("me/lucko/luckperms/schema/postgresql.sql").decode().replace("{prefix}", "luckperms_")
    sql = postgres_sql(schema, data, next_ids)
    (root / "converted.sql").write_text(sql)
    common.save_json(root / "rows.json", data)
    temporary = Path(tempfile.mkdtemp(prefix="luckperms-rehearsal-"))
    try:
        with shared.temporary_postgres(temporary) as (query, prefix):
            query("postgres", f"CREATE DATABASE {DATABASE};")
            query(DATABASE, sql)
            verify_dataset(query, data)
            common.save_json(root / "postgres-proof.json", shared.postgres_proof(DATABASE, query))
            dump = temporary / "converted.dump"
            common.run([*prefix, "pg_dump", "-h", str(temporary), "-U", "postgres",
                        "-d", DATABASE, "-Fc", "--no-owner", "--no-acl", "-f", str(dump)])
            shutil.copyfile(dump, root / "converted.dump")
    except Exception:
        print(f"Rehearsal failed; private diagnostics retained at {temporary}", flush=True)
        raise
    else:
        shutil.rmtree(temporary)
    print("Isolated PostgreSQL conversion: all six tables, every value and source next IDs verified.",
          flush=True)


def live_query(database, sql):
    return common.postgres_query(database, sql)


def refresh_postgres_auth(system):
    unit = (system / "etc/systemd/system/postgresql.service").read_text()
    commands = re.findall(r"^ExecStartPre=(/nix/store/\S+)\s*$", unit, re.MULTILINE)
    if len(commands) != 1 or not Path(commands[0]).is_file():
        raise RuntimeError("Expected one target PostgreSQL pre-start script.")
    # A target dependency can start the old unit before activation's daemon-reload.
    # Relink the target configuration before checking its startup-only HBA path.
    common.run(["runuser", "-u", "postgres", "--", "env", f"PATH={os.environ['PATH']}",
                commands[0]])
    live_query("postgres", "SELECT pg_reload_conf();")
    for _ in range(30):
        pending = live_query("postgres", """
            SELECT pending_restart FROM pg_settings WHERE name='hba_file';
        """).strip()
        if pending == "t":
            print("PostgreSQL requires an explicit restart to load the target authentication file.",
                  flush=True)
            common.run(["systemctl", "restart", "postgresql.service"])
            break
        rules = live_query("postgres", """
            SELECT count(*) FROM pg_hba_file_rules
            WHERE type='local' AND database=ARRAY['s14_minecraft']::text[]
                AND user_name=ARRAY['s14_minecraft']::text[]
                AND auth_method='scram-sha-256' AND error IS NULL;
        """).strip()
        if rules == "1":
            return
        time.sleep(0.1)
    for _ in range(30):
        rules = live_query("postgres", """
            SELECT count(*) FROM pg_hba_file_rules
            WHERE type='local' AND database=ARRAY['s14_minecraft']::text[]
                AND user_name=ARRAY['s14_minecraft']::text[]
                AND auth_method='scram-sha-256' AND error IS NULL;
        """).strip()
        if rules == "1":
            return
        time.sleep(0.1)
    raise RuntimeError("The live PostgreSQL configuration did not load the dedicated SCRAM rule.")


def verify_live(root):
    common.run(["systemctl", "is-active", "--quiet", "luckperms-postgresql.socket"])
    state = json.loads((root / "state.json").read_text())
    password = state["password"]
    probe = VOLUME / "LuckPermsDatabaseCheck.java"
    if probe.exists():
        raise RuntimeError(f"Unexpected preexisting probe file: {probe}")
    probe.write_text("""
        import java.sql.*;
        import java.util.Scanner;
        class LuckPermsDatabaseCheck {
            public static void main(String[] args) throws Exception {
                String password = new Scanner(System.in).nextLine();
                try (Connection c = DriverManager.getConnection(
                        "jdbc:postgresql://172.18.0.1:5432/s14_minecraft",
                        "s14_minecraft", password);
                     Statement s = c.createStatement()) {
                    for (String table : new String[] {"luckperms_groups", "luckperms_tracks",
                            "luckperms_players", "luckperms_user_permissions"}) {
                        try (ResultSet r = s.executeQuery("SELECT count(*) FROM " + table)) {
                            r.next();
                            System.out.println(table + ": " + r.getLong(1) + " rows via game JDBC");
                        }
                    }
                }
            }
        }
    """)
    probe.chmod(0o644)
    try:
        for _ in range(60):
            running = json.loads(common.output(["docker", "inspect", SERVER]))[0]["State"]["Running"]
            if running:
                break
            time.sleep(1)
        else:
            raise RuntimeError("Velocity container did not remain running.")
        common.run([
            "docker", "exec", "-i", SERVER, "java", "--class-path",
            "/home/container/plugins/luckperms/libs/postgresql-driver-42.7.6.jar",
            "/home/container/LuckPermsDatabaseCheck.java",
        ], input=password + "\n")
    finally:
        probe.unlink()
    for _ in range(90):
        result = common.run(["docker", "logs", "--since", state["started_at"], SERVER],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        log = result.stdout + result.stderr
        if "[POSTGRESQL]" in log and "Successfully enabled." in log:
            if "Failed to init storage implementation" in log or "PSQLException" in log:
                raise RuntimeError("LuckPerms startup contains PostgreSQL errors; inspect latest.log.")
            break
        time.sleep(1)
    else:
        raise RuntimeError("LuckPerms PostgreSQL startup did not complete; inspect latest.log.")
    expected_groups = len(json.loads((root / "rows.json").read_text())["luckperms_groups"]["rows"])
    common.assert_equal(str(expected_groups), live_query(DATABASE, "SELECT count(*) FROM luckperms_groups;").strip(),
                        "recovered groups")
    common.assert_equal("t", live_query(DATABASE, """
        SELECT pg_get_userbyid(datdba)='s14_minecraft'
        FROM pg_database WHERE datname='s14_minecraft';
    """).strip(), "database ownership")
    common.assert_equal("f", live_query(DATABASE, """
        SELECT rolsuper OR rolcreatedb OR rolcreaterole FROM pg_roles WHERE rolname='s14_minecraft';
    """).strip(), "unprivileged role")
    common.assert_equal("", live_query(DATABASE, "SHOW listen_addresses;").strip(), "Unix-only PostgreSQL")
    if common.failed_units():
        raise RuntimeError(f"Failed services remain: {common.failed_units()}")


def cutover(system, root):
    common.check_supervisors(system, False)
    inspection = json.loads(common.output(["docker", "inspect", SERVER]))[0]
    if not any(mount["Source"] == str(VOLUME) and mount["Destination"] == "/home/container"
               for mount in inspection["Mounts"]):
        raise RuntimeError("Target container does not mount the expected game volume.")
    network = inspection["NetworkSettings"]["Networks"].get("pelican_nw", {})
    if network.get("Gateway") != "172.18.0.1":
        raise RuntimeError("Unexpected Pelican bridge gateway.")
    rewritten_config(CONFIG.read_text(), "validation_only")
    root.mkdir(mode=0o700, parents=True, exist_ok=False)
    print(f"Recovery backups and private diagnostics: {root}", flush=True)
    prepare(root)
    shutil.copyfile(CONFIG, root / "config-before.yml")
    common.run([str(system / "bin/switch-to-configuration"), "test"])
    common.run(["systemctl", "start", "postgresql.target", "luckperms-postgresql.socket"])
    refresh_postgres_auth(system)
    exists = live_query("postgres", f"""
        SELECT count(*) FROM pg_database WHERE datname={common.literal(DATABASE)};
    """).strip()
    if exists == "0":
        live_query("postgres", f"CREATE DATABASE {common.identifier(DATABASE)};")
    if live_query(DATABASE, "SELECT count(*) FROM pg_tables WHERE schemaname='public';").strip() != "0":
        raise RuntimeError("Destination is not empty; refusing to overwrite live permissions.")
    password = secrets.token_urlsafe(36)
    state = {"stage": "importing", "password": password, "system": str(system)}
    common.save_json(root / "state.json", state)
    common.run(["docker", "stop", "--timeout", "60", SERVER])
    live_query("postgres", f"""
        DO $role$ BEGIN
            IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='{DATABASE}') THEN
                CREATE ROLE {DATABASE} LOGIN;
            END IF;
        END $role$;
        ALTER ROLE {DATABASE} WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION
            PASSWORD {common.literal(password)};
        ALTER DATABASE {DATABASE} OWNER TO {DATABASE};
    """)
    with (root / "converted.dump").open("rb") as stream:
        common.run([
            "runuser", "-u", "postgres", "--", "pg_restore", "-h", "/run/postgresql",
            "-d", DATABASE, "--role", DATABASE, "--no-owner", "--no-acl", "--exit-on-error",
            "--single-transaction",
        ], stdin=stream, text=False)
    finish(root)


def configure_imported_database(root, state):
    inspection = json.loads(common.output(["docker", "inspect", SERVER]))[0]
    if CONFIG.read_bytes() != (root / "config-before.yml").read_bytes():
        raise RuntimeError("LuckPerms config changed since backup; inspect it before completing the cutover.")
    verify_dataset(live_query, json.loads((root / "rows.json").read_text()))
    expected = json.loads((root / "postgres-proof.json").read_text())
    actual = shared.postgres_proof(DATABASE, live_query)
    # JSON round-tripping changes the Counter proof's tuples into lists.
    common.assert_equal(json.dumps(expected, sort_keys=True), json.dumps(actual, sort_keys=True),
                        "restored constraints and next IDs")
    new_config = rewritten_config(CONFIG.read_text(), state["password"])
    if inspection["State"]["Running"]:
        common.run(["docker", "stop", "--timeout", "60", SERVER])
    metadata = CONFIG.stat()
    temporary = CONFIG.with_name("config.yml.postgres-new")
    with temporary.open("x") as stream:
        stream.write(new_config)
    os.chown(temporary, metadata.st_uid, metadata.st_gid)
    temporary.chmod(0o640)
    temporary.replace(CONFIG)
    state["stage"] = "starting"
    common.save_json(root / "state.json", state)


def finish(root):
    state = json.loads((root / "state.json").read_text())
    refresh_postgres_auth(Path(state["system"]))
    if state["stage"] == "importing":
        configure_imported_database(root, state)
    if state["stage"] not in ("starting", "complete"):
        raise RuntimeError("Only a fully imported/configured migration can be resumed.")
    if state["stage"] == "starting":
        common.run(["docker", "stop", "--timeout", "60", SERVER])
        state["started_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        common.save_json(root / "state.json", state)
    common.run(["docker", "start", SERVER])
    verify_live(root)
    system = Path(state["system"])
    common.run(["nix-env", "--profile", "/nix/var/nix/profiles/system", "--set", str(system)])
    common.run([str(system / "bin/switch-to-configuration"), "boot"])
    state["stage"] = "complete"
    common.save_json(root / "state.json", state)
    print(f"LuckPerms now uses native PostgreSQL; MariaDB permissions preserved. Backup: {root}", flush=True)


def main():
    parser = argparse.ArgumentParser(description="Recover missed LuckPerms MariaDB data into native PostgreSQL.")
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--system", type=Path)
    modes.add_argument("--finish", type=Path)
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error("Run with sudo in your terminal.")
    os.umask(0o077)
    with Path("/run/lock/luckperms-migrate.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.finish:
            root = args.finish.resolve()
            if root.parent != BACKUPS or not re.fullmatch(r"\d{8}T\d{6}Z", root.name):
                parser.error("--finish must name a timestamped LuckPerms backup.")
            finish(root)
        else:
            system = args.system.resolve()
            if not system.is_relative_to("/nix/store") or not (system / "bin/switch-to-configuration").is_file():
                parser.error("--system must name a built NixOS system.")
            cutover(system, BACKUPS / datetime.datetime.now(
                datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ"))


if __name__ == "__main__":
    main()
