import argparse
import configparser
from contextlib import closing
import datetime
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import pwd
import secrets
import shutil
import sqlite3
import subprocess
import sys
import tarfile
import time


STATE = Path("/var/lib/native-services-migration")
BACKUPS = Path("/var/backups/native-services")
WRITERS = [
    "docker-audiobookshelf-audiobookshelf-1",
    "docker-forgejo",
    "docker-searxng",
    "docker-uptimekuma-uptime-kuma-1",
    "docker-authentik-server-1",
    "docker-authentik-worker-1",
    "docker-bitmagnet",
]
NATIVE = ["audiobookshelf", "forgejo", "uptime-kuma", "uwsgi"]
CLIENTS = ["docker-authentik-server-1", "docker-authentik-worker-1", "docker-bitmagnet"]
DATABASES = {
    "authentik": ("authentik-postgresql-1", "authentik"),
    "bitmagnet": ("bitmagnet-postgres", "postgres"),
}
SOURCES = {
    "audiobookshelf": Path("/etc/docker-compose/AudioBookShelf/audiobookshelf"),
    "forgejo": Path("/etc/docker-compose/ForgeJo/forgejo"),
    "uptime-kuma": Path("/etc/docker-compose/UptimeKuma/data"),
    "authentik-data": Path("/etc/docker-compose/authentik"),
    "searxng": Path("/var/www/SearXNG"),
    "environment": Path("/var/lib/docker-compose-env"),
}
NATIVE_PATHS = {
    "postgresql-16": Path("/var/lib/postgresql/16"),
    "audiobookshelf": Path("/var/lib/audiobookshelf"),
    "forgejo": Path("/var/lib/forgejo"),
    "uptime-kuma": Path("/var/lib/uptime-kuma"),
    "private-uptime-kuma": Path("/var/lib/private/uptime-kuma"),
}


def run(args, *, text=True, check=True, **kwargs):
    return subprocess.run(args, check=check, text=text, **kwargs)


def output(args, **kwargs):
    return run(args, stdout=subprocess.PIPE, **kwargs).stdout


def save_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def read_ini(path):
    config = configparser.ConfigParser(interpolation=None, delimiters=("=",))
    config.optionxform = str
    config.read_string("[DEFAULT]\n" + path.read_text())
    return config


def convert_forgejo_config(config):
    config["DEFAULT"]["RUN_USER"] = "forgejo"
    config["DEFAULT"]["WORK_PATH"] = "/data/gitea"
    config["database"].update({
        "DB_TYPE": "postgres",
        "HOST": "/run/postgresql",
        "NAME": "forgejo",
        "USER": "forgejo",
        "PASSWD": "",
        "SSL_MODE": "disable",
    })
    config["server"].update({
        "HTTP_ADDR": "0.0.0.0",
        "HTTP_PORT": "3005",
        "APP_DATA_PATH": "/data/gitea",
        "START_SSH_SERVER": "true",
        "SSH_LISTEN_HOST": "0.0.0.0",
        "SSH_LISTEN_PORT": "222",
        "SSH_SERVER_HOST_KEYS": ",".join(
            f"/data/ssh/ssh_host_{kind}_key" for kind in ("rsa", "ecdsa", "ed25519")
        ),
    })
    stream = io.StringIO()
    config.write(stream)
    return stream.getvalue().removeprefix("[DEFAULT]\n")


def rewrite_environment(source, replacements):
    lines = [
        line for line in source.splitlines()
        if line.partition("=")[0].strip() not in replacements
    ]
    for key, value in replacements.items():
        if "\n" in value or "\r" in value:
            raise ValueError(f"Invalid multiline environment value for {key}")
        lines.append(f"{key}={value}")
    return "\n".join(lines) + "\n"


def literal(value):
    return "'" + value.replace("'", "''") + "'"


def identifier(value, quote='"'):
    return quote + value.replace(quote, quote * 2) + quote


def postgres_query(database, sql, source=None):
    args = ["psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1"]
    if source:
        container, user = source
        args = ["docker", "exec", "-i", container, *args, "-U", user]
    else:
        args = ["runuser", "-u", "postgres", "--", *args]
    return output([*args, "-d", database], input=sql)


def postgres_inventory(database, source=None):
    tables = postgres_query(database, """
        SELECT json_build_array(schemaname, tablename)
        FROM pg_tables
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
        ORDER BY schemaname, tablename;
    """, source)
    statements = []
    for line in tables.splitlines():
        schema, table = json.loads(line)
        statements.append(
            f"SELECT json_build_array('table', {literal(schema)}, "
            f"{literal(table)}, count(*)) FROM {identifier(schema)}.{identifier(table)};"
        )
    statements.append("""
        SELECT json_build_array('sequence', schemaname, sequencename, last_value)
        FROM pg_sequences
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
        ORDER BY schemaname, sequencename;
    """)
    return sorted(
        json.loads(line)
        for line in postgres_query(database, "\n".join(statements), source).splitlines()
    )


def mariadb_args(credentials, binary="mariadb"):
    return [
        binary, "--default-character-set=utf8mb4",
        "--host", credentials["host"], "--port", str(credentials["port"]),
        "--user", credentials["user"],
    ]


def mariadb_query(credentials, sql):
    return output(
        [*mariadb_args(credentials), "--batch", "--skip-column-names", credentials["name"]],
        input=sql,
        env={**os.environ, "MYSQL_PWD": credentials["password"]},
    )


def mariadb_counts(credentials):
    tables = mariadb_query(credentials, """
        SELECT TABLE_NAME FROM information_schema.tables
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE'
        ORDER BY TABLE_NAME;
    """).splitlines()
    queries = [
        f"SELECT {literal(table)}, count(*) FROM {identifier(table, '`')};"
        for table in tables
    ]
    rows = mariadb_query(credentials, "\n".join(queries)).splitlines()
    return {name: int(count) for name, count in (line.split("\t") for line in rows)}


def mariadb_next_ids(credentials):
    rows = mariadb_query(credentials, """
        SELECT c.TABLE_NAME, c.COLUMN_NAME, t.AUTO_INCREMENT
        FROM information_schema.columns c
        JOIN information_schema.tables t
          ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME
        WHERE c.TABLE_SCHEMA = DATABASE() AND c.EXTRA LIKE '%auto_increment%'
        ORDER BY c.TABLE_NAME, c.COLUMN_NAME;
    """).splitlines()
    return [
        [table, column, int(next_id)]
        for table, column, next_id in (row.split("\t") for row in rows)
    ]


def forgejo_metadata_sql(credentials):
    schemas = {
        "forgejo_version": (
            ["id\tbigint\t0\tNO\tPRI\tauto_increment", "version\tbigint\t0\tYES\t\t"],
            '"id" BIGSERIAL PRIMARY KEY, "version" BIGINT',
            ["id", "version"],
        ),
        "forgejo_migration": (
            ["id\tvarchar\t255\tNO\tPRI\t", "created_unix\tbigint\t0\tYES\t\t"],
            '"id" VARCHAR(255) PRIMARY KEY, "created_unix" BIGINT',
            ["id", "created_unix"],
        ),
    }
    statements = []
    for table, (expected, definition, columns) in schemas.items():
        schema = mariadb_query(credentials, f"""
            SELECT COLUMN_NAME, DATA_TYPE, COALESCE(CHARACTER_MAXIMUM_LENGTH, 0),
                   IS_NULLABLE, COLUMN_KEY, EXTRA
            FROM information_schema.columns
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = {literal(table)}
            ORDER BY ORDINAL_POSITION;
        """).splitlines()
        assert_equal(expected, schema, f"{table} metadata schema")
        statements.append(f"CREATE TABLE {identifier(table)} ({definition});")
        rows = output([
            *mariadb_args(credentials), "--batch", "--raw", "--skip-column-names", credentials["name"],
        ], input=(
            "SELECT JSON_ARRAY(" + ", ".join(identifier(column, "`") for column in columns)
            + f") FROM {identifier(table, '`')} ORDER BY {identifier('id', '`')};"
        ), env={**os.environ, "MYSQL_PWD": credentials["password"]})
        for line in rows.splitlines():
            values = []
            for value in json.loads(line):
                if value is None:
                    values.append("NULL")
                elif type(value) is int:
                    values.append(str(value))
                elif isinstance(value, str):
                    values.append(literal(value))
                else:
                    raise TypeError(f"Unexpected metadata value type in {table}")
            statements.append(f"INSERT INTO {identifier(table)} VALUES ({', '.join(values)});")
    return "\n".join(statements)


def restore_forgejo_sequences(next_ids):
    for table, column, next_id in next_ids:
        sequence = postgres_query("forgejo", (
            f"SELECT pg_get_serial_sequence({literal('public.' + identifier(table))}, "
            f"{literal(column)});"
        )).strip()
        if not sequence:
            raise RuntimeError(f"No PostgreSQL sequence for Forgejo {table}.{column}.")
        postgres_query("forgejo", f"SELECT setval({literal(sequence)}, {next_id}, false);")


def prepare_forgejo_sql(sql):
    from pglast import ast, enums, parse_sql
    from pglast.stream import RawStream

    statements = []
    foreign_keys = []
    for raw in parse_sql(sql):
        statement = raw.stmt
        if isinstance(statement, ast.CreateStmt):
            elements = []
            relation = statement.relation
            table = ".".join(identifier(name) for name in (relation.schemaname, relation.relname) if name)
            for element in statement.tableElts or ():
                if isinstance(element, ast.Constraint) and element.contype == enums.ConstrType.CONSTR_FOREIGN:
                    foreign_keys.append(f"ALTER TABLE {table} ADD {RawStream()(element)};")
                    continue
                if isinstance(element, ast.ColumnDef):
                    constraints = []
                    for constraint in element.constraints or ():
                        if constraint.contype == enums.ConstrType.CONSTR_FOREIGN:
                            constraint.fk_attrs = (ast.String(sval=element.colname),)
                            foreign_keys.append(f"ALTER TABLE {table} ADD {RawStream()(constraint)};")
                        else:
                            constraints.append(constraint)
                    element.constraints = tuple(constraints)
                elements.append(element)
            statement.tableElts = tuple(elements)
        statements.append(RawStream()(statement) + ";")
    # Forgejo exports forward/cyclic foreign keys before their referenced tables.
    # Adding them after all rows exist also validates the converted relationships.
    return "\n".join([*statements, *foreign_keys])


def sqlite_counts(path):
    with closing(sqlite3.connect(f"{path.as_uri()}?mode=ro", uri=True)) as db:
        if db.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
            raise RuntimeError(f"SQLite integrity check failed: {path}")
        tables = db.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
        return {
            name: db.execute(f"SELECT count(*) FROM {identifier(name)}").fetchone()[0]
            for (name,) in tables
        }


def assert_equal(expected, actual, label):
    if expected != actual:
        raise RuntimeError(f"{label} verification failed; backups retained. Do not cut over.")


def copy_tree(source, destination):
    destination.mkdir(parents=True, exist_ok=True)
    run(["rsync", "-aHAX", "--numeric-ids", f"{source}/", f"{destination}/"])


def docker_inspect(name):
    return json.loads(output(["docker", "inspect", name]))[0]


def unit_contents(system, name):
    directory = system / "etc/systemd/system"
    files = [directory / name, *sorted((directory / f"{name}.d").glob("*.conf"))]
    return {str(path.relative_to(directory)): path.read_bytes() for path in files if path.is_file()}


def check_supervisors(system, allow_docker_restart):
    current = Path("/run/current-system")
    if unit_contents(current, "wings.service") != unit_contents(system, "wings.service"):
        raise RuntimeError("Wings unit or drop-ins would change; refusing to alter game management.")
    for name in ["docker.service", "docker.socket", "containerd.service"]:
        if unit_contents(current, name) != unit_contents(system, name):
            if not allow_docker_restart:
                raise RuntimeError(
                    f"{name}, including drop-ins, would change. "
                    "A planned game restart requires --allow-docker-restart."
                )
            print(f"Explicitly authorized runtime restart: {name}", flush=True)


def validate_retry(backup):
    backup = backup.resolve()
    if not backup.is_relative_to(BACKUPS):
        raise RuntimeError("Retry backup must be under /var/backups/native-services.")
    state = json.loads((backup / "state.json").read_text())
    if state["stage"] not in ("backing-up", "restoring", "rolled-back", "rollback-failed"):
        raise RuntimeError("Retry is only allowed for a failure before native writers started.")
    if (state.get("native_writers_started") and state["stage"] != "rolled-back") or (STATE / "ready").exists():
        raise RuntimeError("Native writers may have accepted data; refusing an automatic retry.")
    if str(Path("/run/current-system").resolve()) != state["old_system"]:
        raise RuntimeError("Restore the original running system before retrying.")
    return backup, state


def archive_retry(backup, state):
    archive = backup / "unfinished-native-copies"
    archive.mkdir(mode=0o700)
    paths = {**NATIVE_PATHS, "migration-state": STATE}
    save_json(archive / "original-paths.json", {name: str(path) for name, path in paths.items()})
    for name, path in paths.items():
        if path.exists() or path.is_symlink():
            shutil.move(str(path), str(archive / name))
    state["stage"] = "archived-for-retry"
    save_json(backup / "state.json", state)
    print(f"Retained unfinished native copies in {archive}", flush=True)


def wait_mariadb():
    for _ in range(150):
        result = run([
            "docker", "exec", "mariadb", "mariadb-admin",
            "--protocol=tcp", "--host=127.0.0.1", "ping", "--silent",
        ], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode == 0:
            return
        time.sleep(2)
    raise RuntimeError("Shared MariaDB did not become ready.")


def failed_units():
    return [
        line.split()[0]
        for line in output([
            "systemctl", "list-units", "--failed", "--all", "--plain", "--no-legend", "--no-pager",
        ]).splitlines() if line.strip()
    ]


def checksum(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def wait_http(url):
    for _ in range(120):
        result = subprocess.run(
            ["curl", "--fail", "--silent", "--location", "--max-redirs", "5", "--output", "/dev/null",
             "--max-time", "5", url],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        if result.returncode == 0:
            return
        time.sleep(2)
    raise RuntimeError(f"Health check timed out: {url}")


def restore_old_system(state):
    (STATE / "ready").unlink(missing_ok=True)
    run(["systemctl", "stop", *NATIVE, *CLIENTS, "postgresql.target", "postgresql"])
    activation = run([state["old_system"] + "/bin/switch-to-configuration", "test"], check=False)
    run(["nix-env", "--profile", "/nix/var/nix/profiles/system",
         "--set", state["old_profile"]])
    run([state["old_profile"] + "/bin/switch-to-configuration", "boot"])
    run(["systemctl", "start", *state["original_active"]])
    if activation.returncode != 0:
        failures = failed_units()
        if activation.returncode == 4 and failures == ["pelican-panel-upgrade.service"]:
            print("Recovering Pelican Panel's MariaDB startup-order failure during rollback.",
                  file=sys.stderr)
            wait_mariadb()
            run(["systemctl", "restart", "pelican-panel-upgrade.service"])
        else:
            raise RuntimeError(
                f"Old profile/boot and containers restored, but activation returned "
                f"{activation.returncode}; failed units: {failures}"
            )
    run(["systemctl", "is-active", "--quiet", *state["original_active"]])


def validate_system(system):
    if not system.is_relative_to("/nix/store") or not (system / "bin/switch-to-configuration").is_file():
        raise RuntimeError("Pass the built NixOS system store path, not a flake or directory.")
    for name in NATIVE:
        unit = system / "etc/systemd/system" / f"{name}.service"
        if not unit.is_file() or f"ConditionPathExists={STATE}/ready" not in unit.read_text():
            raise RuntimeError(f"Target system lacks the migration guard on {name}.")


def complete_cutover(system, backup, state):
    for url in [
        "http://127.0.0.1:13378/healthcheck", "http://127.0.0.1:3005/api/healthz",
        "http://127.0.0.1:3001/", "http://127.0.0.1:8842/healthz",
        "http://127.0.0.1:9180/-/health/ready/", "http://127.0.0.1:3333/",
    ]:
        wait_http(url)
    for container in ["authentik-server-1", "authentik-worker-1"]:
        for _ in range(120):
            if docker_inspect(container)["State"].get("Health", {}).get("Status") == "healthy":
                break
            time.sleep(2)
        else:
            raise RuntimeError(f"{container} did not become healthy.")
    for unit in NATIVE + CLIENTS:
        run(["systemctl", "is-active", "--quiet", unit])
    keys = output(["ssh-keyscan", "-T", "10", "-p", "222", "127.0.0.1"],
                  stderr=subprocess.DEVNULL)
    expected_keys = {
        tuple(path.read_text().split()[:2])
        for path in (backup / "forgejo/ssh").glob("ssh_host_*_key.pub")
    }
    actual_keys = {tuple(line.split()[1:3]) for line in keys.splitlines() if not line.startswith("#")}
    assert_equal(expected_keys, actual_keys, "Forgejo SSH host keys")
    failures = failed_units()
    if failures:
        raise RuntimeError(f"Failed units remain; refusing to finalize migration: {failures}")
    run(["nix-env", "--profile", "/nix/var/nix/profiles/system", "--set", str(system)])
    run([str(system / "bin/switch-to-configuration"), "boot"])
    state["target"] = str(system)
    state["stage"] = "complete"
    save_json(backup / "state.json", state)
    print(f"Migration complete and persistent. Backups and rollback state: {backup}", flush=True)


def finish_cutover(system, backup, *, allow_docker_restart=False):
    backup = backup.resolve()
    if not backup.is_relative_to(BACKUPS):
        raise RuntimeError("Finish backup must be under /var/backups/native-services.")
    state = json.loads((backup / "state.json").read_text())
    if (state["stage"] not in ("starting-writers", "needs-attention")
            or not state.get("native_writers_started") or not (STATE / "ready").exists()):
        raise RuntimeError("Finish requires an interrupted cutover with native writers already started.")
    if str(Path("/run/current-system").resolve()) not in (state["target"], state.get("recovery_system")):
        raise RuntimeError("The running system does not match this interrupted cutover.")
    validate_system(system)
    check_supervisors(system, allow_docker_restart)
    run(["nix-store", "--add-root", str(backup / ("recovery-" + system.name)),
         "--indirect", "--realise", str(system)])
    state["recovery_system"] = str(system)
    state["stage"] = "needs-attention"
    save_json(backup / "state.json", state)
    run([str(system / "bin/switch-to-configuration"), "test"])
    run(["systemctl", "reset-failed", *NATIVE, *CLIENTS])
    run(["systemctl", "start", *NATIVE, *CLIENTS])
    complete_cutover(system, backup, state)


def migrate(system, *, allow_docker_restart=False, retry=None):
    previous = validate_retry(retry) if retry else None
    if (STATE / "ready").exists():
        raise RuntimeError("Migration is already complete; refusing to overwrite live data.")
    if STATE.exists() and not previous:
        raise RuntimeError(f"{STATE} already exists. Review the previous attempt before retrying.")
    for path in NATIVE_PATHS.values():
        if path.exists() and not previous:
            raise RuntimeError(f"Destination already exists: {path}")
    if Path("/run/postgresql/.s.PGSQL.5432").exists():
        raise RuntimeError("A native PostgreSQL socket already exists; refusing to replace its cluster.")
    for path in SOURCES.values():
        if not path.is_dir():
            raise RuntimeError(f"Missing source directory: {path}")
    validate_system(system)
    check_supervisors(system, allow_docker_restart)

    inspections = {
        name: docker_inspect(name)
        for name in [unit.removeprefix("docker-") for unit in WRITERS]
        + [item[0] for item in DATABASES.values()]
    }
    for name, expected in {
        "audiobookshelf-audiobookshelf-1": "2.37.2", "forgejo": "17.0.1",
    }.items():
        actual = inspections[name]["Config"]["Labels"]["org.opencontainers.image.version"]
        assert_equal(expected, actual, f"{name} source version")
    assert_equal("2.5.9", output([
        "docker", "exec", "uptimekuma-uptime-kuma-1", "node", "-p",
        'require("/app/package.json").version',
    ]).strip(), "Uptime Kuma source version")
    for name, source in DATABASES.items():
        version = postgres_query(name, "SHOW server_version_num;", source).strip()
        if not 160000 <= int(version) < 170000:
            raise RuntimeError(f"{name} is not PostgreSQL 16.")
    size = sum(
        int(postgres_query(name, "SELECT pg_database_size(current_database());", source))
        for name, source in DATABASES.items()
    )
    if shutil.disk_usage("/var/lib").free < size * 3 + 10 * 1024**3:
        raise RuntimeError("Need free space for three times the source PostgreSQL size plus 10 GiB.")

    forgejo = read_ini(SOURCES["forgejo"] / "gitea/conf/app.ini")
    assert_equal("mysql", forgejo["database"]["DB_TYPE"], "Forgejo source database type")
    host, port = forgejo["database"]["HOST"].rsplit(":", 1)
    forgejo_db = {
        "host": host, "port": int(port), "name": forgejo["database"]["NAME"],
        "user": forgejo["database"]["USER"], "password": forgejo["database"]["PASSWD"],
    }
    kuma = json.loads((SOURCES["uptime-kuma"] / "db-config.json").read_text())
    assert_equal("mariadb", kuma["type"], "Uptime Kuma source database type")
    kuma_db = {
        "host": kuma["hostname"], "port": kuma["port"], "name": kuma["dbName"],
        "user": kuma["username"], "password": kuma["password"],
    }
    for credentials in [forgejo_db, kuma_db]:
        assert_equal("1", mariadb_query(credentials, "SELECT 1;").strip(), "MariaDB connection")
    for unit in WRITERS + ["docker-" + item[0] for item in DATABASES.values()]:
        run(["systemctl", "is-active", "--quiet", unit])
    for unit in ["docker-bazarr", "docker-radarr", "docker-sonarr"]:
        if subprocess.run(["systemctl", "is-active", "--quiet", unit]).returncode == 0:
            raise RuntimeError(f"{unit} is now running; review its manual-start configuration first.")
    for unit in [*NATIVE, "postgresql"]:
        if run(["systemctl", "is-active", "--quiet", unit], check=False).returncode == 0:
            raise RuntimeError(f"{unit} is already running; refusing to replace native data in use.")

    if previous:
        archive_retry(*previous)
    STATE.mkdir(mode=0o700)
    BACKUPS.mkdir(mode=0o700, parents=True, exist_ok=True)
    backup = BACKUPS / datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup.mkdir(mode=0o700)
    state = {
        "backup": str(backup),
        "old_system": str(Path("/run/current-system").resolve()),
        "old_profile": str(Path("/nix/var/nix/profiles/system").resolve()),
        "target": str(system),
        "original_active": WRITERS + ["docker-" + item[0] for item in DATABASES.values()],
        "stage": "backing-up",
        "native_writers_started": False,
    }
    save_json(backup / "state.json", state)
    save_json(backup / "containers.json", inspections)
    run(["nix-store", "--add-root", str(backup / "old-system"), "--indirect",
         "--realise", state["old_system"]])
    run(["nix-store", "--add-root", str(backup / "new-system"), "--indirect",
         "--realise", str(system)])
    print(f"Backups: {backup}", flush=True)
    writers_started = False
    switched = False
    try:
        run(["systemctl", "stop", *WRITERS])
        for name, source in SOURCES.items():
            copy_tree(source, backup / name)
        for name, credentials in [("forgejo", forgejo_db), ("kuma", kuma_db)]:
            with (backup / f"{name}-mariadb.sql").open("wb") as stream:
                run([
                    *mariadb_args(credentials, "mariadb-dump"),
                    "--single-transaction", "--routines", "--events", credentials["name"],
                ], env={**os.environ, "MYSQL_PWD": credentials["password"]},
                    stdout=stream, text=False)
        forgejo_counts = mariadb_counts(forgejo_db)
        forgejo_next_ids = mariadb_next_ids(forgejo_db)
        (backup / "forgejo-metadata-postgres.sql").write_text(forgejo_metadata_sql(forgejo_db))
        kuma_counts = mariadb_counts(kuma_db)
        abs_counts = sqlite_counts(backup / "audiobookshelf/config/absdatabase.sqlite")
        save_json(backup / "forgejo-counts.json", forgejo_counts)
        save_json(backup / "forgejo-next-ids.json", forgejo_next_ids)
        save_json(backup / "kuma-counts.json", kuma_counts)
        save_json(backup / "audiobookshelf-counts.json", abs_counts)

        roles = {}
        for name, source in DATABASES.items():
            print(f"Counting every table and dumping {name}; this may take a long time.", flush=True)
            inventory = postgres_inventory(name, source)
            save_json(backup / f"{name}-inventory.json", inventory)
            roles[name] = postgres_query(
                name, f"SELECT rolpassword FROM pg_authid WHERE rolname={literal(source[1])};",
                source,
            ).strip()
            if not roles[name].startswith("SCRAM-SHA-256$"):
                raise RuntimeError(f"{name} requires a SCRAM password before migration.")
            with (backup / f"{name}.dump").open("wb") as stream:
                run([
                    "docker", "exec", source[0], "pg_dump", "-U", source[1],
                    "-d", name, "--format=custom", "--compress=1", "--no-owner", "--no-acl",
                ], stdout=stream, text=False)
            run(["pg_restore", "--list", str(backup / f"{name}.dump")],
                stdout=subprocess.DEVNULL)
        save_json(backup / "postgres-role-passwords.json", roles)

        for name in ["forgejo", "audiobookshelf", "uptime-kuma"]:
            copy_tree(backup / name, Path("/var/lib") / name)
        print("Exporting Forgejo using PostgreSQL SQL syntax.", flush=True)
        with (backup / "forgejo-postgres.tar").open("wb") as stream:
            run([
                "docker", "run", "--rm", "--network", "host", "--user", "1000:1000",
                "--entrypoint", "/usr/local/bin/forgejo",
                "--mount", "type=bind,source=/var/lib/forgejo,target=/data",
                inspections["forgejo"]["Image"],
                "--config", "/data/gitea/conf/app.ini", "--work-path", "/data/gitea",
                "--custom-path", "/data/gitea", "dump", "--database", "postgres",
                "--type", "tar", "--file", "-", "--quiet", "--skip-repository",
                "--skip-log", "--skip-custom-dir", "--skip-lfs-data",
                "--skip-attachment-data", "--skip-package-data", "--skip-index",
                "--skip-repo-archives",
            ], stdout=stream, text=False)
        with tarfile.open(backup / "forgejo-postgres.tar") as archive:
            members = [m for m in archive.getmembers() if m.isfile() and m.name.endswith("-db.sql")]
            if len(members) != 1 or members[0].size == 0:
                raise RuntimeError("Forgejo export did not contain exactly one nonempty SQL dump.")
            with archive.extractfile(members[0]) as source, (backup / "forgejo-postgres.sql").open("wb") as target:
                shutil.copyfileobj(source, target)

        for name in ["authentik-server-1", "authentik-worker-1", "bitmagnet"]:
            overrides = (
                {"POSTGRES_HOST": "/run/postgresql", "POSTGRES_USER": "bitmagnet",
                 "POSTGRES_NAME": "bitmagnet"}
                if name == "bitmagnet" else
                {"AUTHENTIK_POSTGRESQL__HOST": "/run/postgresql",
                 "AUTHENTIK_POSTGRESQL__NAME": "authentik",
                 "AUTHENTIK_POSTGRESQL__USER": "authentik"}
            )
            (STATE / f"{name}.env").write_text(rewrite_environment(
                (backup / "environment" / f"{name}.env").read_text(), overrides,
            ))
        (STATE / "searx.env").write_text(f"SEARX_SECRET_KEY={secrets.token_hex(32)}\n")
        (Path("/var/lib/forgejo/gitea/conf/app.ini")).write_text(convert_forgejo_config(forgejo))
        checksums = {
            path.name: checksum(path)
            for path in backup.iterdir() if path.is_file() and path.suffix in (".sql", ".dump", ".tar")
        }
        save_json(backup / "sha256.json", checksums)
        run(["systemctl", "stop", *["docker-" + item[0] for item in DATABASES.values()]])
        state["stage"] = "restoring"
        save_json(backup / "state.json", state)
        switched = True
        run([str(system / "bin/switch-to-configuration"), "test"])
        run(["systemctl", "start", "postgresql.target"])
        for name in ["audiobookshelf", "forgejo"]:
            account = pwd.getpwnam(name)
            run(["chown", "-R", f"{account.pw_uid}:{account.pw_gid}", f"/var/lib/{name}"])

        for name, password in roles.items():
            postgres_query("postgres", f"ALTER ROLE {identifier(name)} PASSWORD {literal(password)};")
        for name in DATABASES:
            print(f"Restoring {name} into native PostgreSQL.", flush=True)
            with (backup / f"{name}.dump").open("rb") as stream:
                run([
                    "runuser", "-u", "postgres", "--", "pg_restore",
                    "--exit-on-error", "--no-owner", "--no-acl", f"--role={name}", "-d", name,
                ], stdin=stream, text=False)
            expected = json.loads((backup / f"{name}-inventory.json").read_text())
            assert_equal(expected, postgres_inventory(name), f"{name} rows and sequences")
            postgres_query(name, "ANALYZE;")
        with (backup / "forgejo-postgres.sql").open("r") as stream:
            sql = stream.read()
        sql += "\n" + (backup / "forgejo-metadata-postgres.sql").read_text()
        postgres_query("forgejo", "BEGIN;\nSET ROLE forgejo;\n" + prepare_forgejo_sql(sql) + "\nCOMMIT;")
        restore_forgejo_sequences(forgejo_next_ids)
        restored_forgejo = {
            row[2]: row[3] for row in postgres_inventory("forgejo") if row[0] == "table"
        }
        assert_equal(forgejo_counts, restored_forgejo, "Forgejo converted rows")
        assert_equal(kuma_counts, mariadb_counts(kuma_db), "Uptime Kuma retained MariaDB rows")
        assert_equal(abs_counts, sqlite_counts(Path("/var/lib/audiobookshelf/config/absdatabase.sqlite")),
                     "Audiobookshelf copied rows")

        state["stage"] = "starting-writers"
        state["native_writers_started"] = True
        save_json(backup / "state.json", state)
        (STATE / "ready").touch(mode=0o600)
        writers_started = True
        run(["systemctl", "start", *NATIVE, *CLIENTS])
        complete_cutover(system, backup, state)
    except (Exception, KeyboardInterrupt):
        if not writers_started:
            print("Migration failed before native writers started; restoring old services.", file=sys.stderr)
            try:
                if switched:
                    restore_old_system(state)
                else:
                    run(["systemctl", "start", *state["original_active"]])
            except (Exception, KeyboardInterrupt):
                state["stage"] = "rollback-failed"
                save_json(backup / "state.json", state)
                print(f"Rollback needs attention; recovery state saved in {backup}", file=sys.stderr)
                raise
            state["stage"] = "rolled-back"
        else:
            state["stage"] = "needs-attention"
            print(
                "Cutover health verification failed. Native writers may have accepted data; "
                "NOT automatically rolling back. Review service logs and the backup state. "
                f"Explicit rollback: native-services-migrate --rollback {backup} --accept-data-loss",
                file=sys.stderr,
            )
        save_json(backup / "state.json", state)
        raise


def main():
    parser = argparse.ArgumentParser(description="Back up and migrate the selected server services.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--system", type=Path, help="Built NixOS system to activate after backups")
    mode.add_argument("--rollback", type=Path, help="Backup directory; discards post-cutover changes")
    parser.add_argument("--retry", type=Path, help="Archive a pre-writer failed attempt, then take fresh backups")
    parser.add_argument("--finish", type=Path, help="Finish an interrupted post-restore cutover without reimporting data")
    parser.add_argument("--allow-docker-restart", action="store_true",
                        help="Explicitly allow Docker/containerd changes and game restarts")
    parser.add_argument("--accept-data-loss", action="store_true", help="Required for explicit rollback")
    args = parser.parse_args()
    if args.retry and not args.system:
        parser.error("--retry requires --system.")
    if args.finish and (not args.system or args.retry):
        parser.error("--finish requires --system and cannot be combined with --retry.")
    if os.geteuid() != 0:
        parser.error("Run with sudo in your terminal.")
    os.umask(0o077)
    with Path("/run/lock/native-services-migration.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.rollback:
            backup = args.rollback.resolve()
            if not backup.is_relative_to(BACKUPS) or not args.accept_data_loss:
                parser.error("Rollback requires a backup under /var/backups/native-services and --accept-data-loss.")
            state = json.loads((backup / "state.json").read_text())
            restore_old_system(state)
            state["stage"] = "rolled-back"
            save_json(backup / "state.json", state)
            print("Old system restored. Original container data was retained.")
        elif args.finish:
            finish_cutover(args.system.resolve(), args.finish,
                           allow_docker_restart=args.allow_docker_restart)
        else:
            migrate(args.system.resolve(), allow_docker_restart=args.allow_docker_restart,
                    retry=args.retry)


if __name__ == "__main__":
    main()
