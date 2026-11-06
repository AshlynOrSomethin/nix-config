import argparse
from collections import Counter
from contextlib import contextmanager
import datetime
from decimal import Decimal
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import pwd
import re
import secrets
import shutil
import subprocess
import sys
import tarfile
import tempfile
from urllib.parse import quote

import migrate as common


BACKUPS = Path("/var/backups/shared-mariadb")
STATE = Path("/var/lib/shared-mariadb-migration")
PANEL = Path("/srv/http/pelican-panel")
FRESH = Path("/var/www/FreshRSS/www/freshrss/data")
DATABASES = {"freshrss": "freshrss", "pelican": "pelican-panel"}
WRITERS = [
    "docker-freshrss", "phpfpm-pelican-panel", "pelican-panel-queue",
    "pelican-panel-schedule.timer", "pelican-panel-schedule", "pelican-panel-upgrade",
]
# JSON types from a clean PostgreSQL migration of the installed Panel application.
PANEL_JSON_COLUMNS = {
    "activity_logs": ("properties",),
    "api_keys": ("permissions",),
    "backup_hosts": ("configuration",),
    "egg_variables": ("rules",),
    "eggs": ("docker_images", "features", "file_denylist", "startup_commands"),
    "notifications": ("data",),
    "passkeys": ("credential",),
    "server_transfers": ("new_additional_allocations", "old_additional_allocations"),
    "server_user_settings": ("settings",),
    "subusers": ("permissions",),
    "users": ("customization", "oauth"),
    "webhook_configurations": ("events", "headers", "payload"),
    "webhooks": ("payload",),
}


def private_run(args, log, **kwargs):
    with log.open("ab") as stream:
        result = subprocess.run(args, stdout=stream, stderr=stream, **kwargs)
    if result.returncode:
        raise RuntimeError(f"Command failed ({args[0]}); private diagnostics: {log}")


def php_json(script, *args):
    return json.loads(common.output(["php", "-r", script, *map(str, args)]))


def source_credentials():
    fresh = php_json("$c=include $argv[1]; echo json_encode($c['db']);", FRESH / "config.php")
    panel = php_json(
        "require $argv[1].'/vendor/autoload.php';"
        "echo json_encode(Dotenv\\Dotenv::parse(file_get_contents($argv[1].'/.env')));", PANEL,
    )
    if fresh["type"] != "mysql" or panel["DB_CONNECTION"] not in ("mysql", "mariadb"):
        raise RuntimeError("Both source applications must still use the shared MariaDB.")
    return {
        "freshrss": {
            "host": "127.0.0.1", "port": 3306, "name": fresh["base"],
            "user": fresh["user"], "password": fresh["password"],
        },
        "pelican": {
            "host": panel["DB_HOST"], "port": int(panel.get("DB_PORT", 3306)),
            "name": panel["DB_DATABASE"], "user": panel["DB_USERNAME"],
            "password": panel["DB_PASSWORD"],
        },
    }


def source_columns(credentials):
    rows = common.mariadb_query(credentials, """
        SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, COLUMN_TYPE
        FROM information_schema.columns WHERE TABLE_SCHEMA = DATABASE()
        ORDER BY TABLE_NAME, ORDINAL_POSITION;
    """)
    result = {}
    for line in rows.splitlines():
        table, name, kind, definition = line.split("\t")
        result.setdefault(table, []).append((name, kind, definition))
    return result


def check_bigints(credentials, columns):
    for table, fields in columns.items():
        for name, kind, definition in fields:
            if kind == "bigint" and "unsigned" in definition:
                count = common.mariadb_query(credentials, (
                    f"SELECT count(*) FROM {common.identifier(table, '`')} "
                    f"WHERE {common.identifier(name, '`')} > 9223372036854775807;"
                )).strip()
                common.assert_equal("0", count, f"Signed bigint capacity for {table}.{name}")


@contextmanager
def temporary_postgres(root):
    data = root / "pg"
    account = pwd.getpwnam("postgres") if os.geteuid() == 0 else None
    prefix = ["runuser", "-u", "postgres", "--"] if account else []
    if account:
        os.chown(root, account.pw_uid, account.pw_gid)
    log = root / "cluster.log"
    private_run([
        *prefix, "initdb", "-D", str(data), "-U", "postgres", "--encoding=UTF8",
        "--locale=en_US.UTF-8", "--auth-local=trust", "--auth-host=reject",
    ], log)
    private_run([
        *prefix, "pg_ctl", "-D", str(data), "-l", str(root / "postgres.log"),
        "-w", "start", "-o", f"-k {root} -p 5432 -c listen_addresses='' -c timezone=UTC",
    ], log)

    def query(database, sql):
        return common.output([
            *prefix, "psql", "-h", str(root), "-U", "postgres", "-XqAt",
            "-v", "ON_ERROR_STOP=1", "-d", database,
        ], input=sql)

    try:
        yield query, prefix
    finally:
        private_run([*prefix, "pg_ctl", "-D", str(data), "-m", "fast", "-w", "stop"], log)


def load_database(name, credentials, root, prefix):
    source = (
        f"mysql://{quote(credentials['user'], safe='')}"
        f"@{credentials['host']}:{credentials['port']}/{credentials['name']}"
    )
    target = f"postgresql://postgres@unix:{root}:5432/{name}"
    config = root / f"{name}.load"
    casts = "type bigint to bigint drop typemod"
    if name == "freshrss":
        casts += ", type tinyint to smallint drop typemod"
    if not re.fullmatch(r"[A-Za-z0-9_]+", credentials["name"]):
        raise RuntimeError("Unsupported source database identifier.")
    config.write_text(
        f"LOAD DATABASE FROM {source} INTO {target}\n"
        "WITH include drop, create tables, create indexes, reset sequences, foreign keys, quote identifiers\n"
        "SET MySQL PARAMETERS time_zone = '\"+00:00\"'\n"
        f"CAST {casts}\nALTER SCHEMA '{credentials['name']}' RENAME TO 'public';\n"
    )
    config.chmod(0o600)
    if os.geteuid() == 0:
        account = pwd.getpwnam("postgres")
        os.chown(config, account.pw_uid, account.pw_gid)
    log = root / f"{name}-pgloader.log"
    private_run([*prefix, "pgloader", "--root-dir", str(root / f"{name}-logs"),
                 "--logfile", str(root / f"{name}-loader-detail.log"), str(config)], log,
                env={**os.environ, "MYSQL_PWD": credentials["password"]})
    if re.search(r"\b(?:ERROR|FATAL|KABOOM)\b", log.read_text()):
        raise RuntimeError(f"pgloader reported errors despite its exit status; private diagnostics: {log}")


def panel_json_sql():
    columns = ",\n".join(
        f"({common.literal(table)}, {common.literal(column)})"
        for table, fields in PANEL_JSON_COLUMNS.items() for column in fields
    )
    return """
        BEGIN;
        SET LOCAL lock_timeout = '10s';
        SET LOCAL statement_timeout = '120s';
        DO $repair$
        DECLARE field record; kind text;
        BEGIN
            FOR field IN SELECT * FROM (VALUES
    """ + columns + """
            ) AS expected(table_name, column_name) LOOP
                SELECT data_type INTO kind FROM information_schema.columns
                WHERE table_schema='public' AND table_name=field.table_name
                      AND column_name=field.column_name;
                IF kind = 'json' THEN CONTINUE; END IF;
                IF kind IS NULL OR kind NOT IN ('text', 'character varying') THEN
                    RAISE EXCEPTION 'Unexpected type for %.%: %',
                        field.table_name, field.column_name, kind;
                END IF;
                EXECUTE format('LOCK TABLE public.%I IN ACCESS EXCLUSIVE MODE', field.table_name);
                EXECUTE format(
                    'CREATE TEMP TABLE panel_json_values ON COMMIT DROP AS '
                    'SELECT %I::text AS value FROM public.%I',
                    field.column_name, field.table_name);
                EXECUTE format(
                    'ALTER TABLE public.%I ALTER COLUMN %I TYPE json USING %I::json',
                    field.table_name, field.column_name, field.column_name);
                EXECUTE format(
                    'CREATE TEMP TABLE panel_json_after ON COMMIT DROP AS '
                    'SELECT %I::text AS value FROM public.%I',
                    field.column_name, field.table_name);
                IF EXISTS (
                    (SELECT * FROM panel_json_values EXCEPT ALL SELECT * FROM panel_json_after)
                    UNION ALL
                    (SELECT * FROM panel_json_after EXCEPT ALL SELECT * FROM panel_json_values)
                ) THEN
                    RAISE EXCEPTION 'JSON conversion changed values in %.%',
                        field.table_name, field.column_name;
                END IF;
                DROP TABLE panel_json_values, panel_json_after;
            END LOOP;
        END $repair$;
        COMMIT;
    """


def repair_panel_json():
    backup = Path("/var/backups/pelican-json") / datetime.datetime.now(
        datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup.mkdir(mode=0o700, parents=True, exist_ok=False)
    print(f"Panel repair backup and private diagnostics: {backup}", flush=True)
    with (backup / "pelican-before.dump").open("xb") as dump, \
            (backup / "repair.log").open("ab") as log:
        common.run(["runuser", "-u", "postgres", "--", "pg_dump", "-h", "/run/postgresql",
                    "-Fc", "-d", "pelican"], stdout=dump, stderr=log)
    private_run([
        "runuser", "-u", "postgres", "--", "psql", "-h", "/run/postgresql",
        "-X", "-v", "ON_ERROR_STOP=1", "-d", "pelican",
    ], backup / "repair.log", input=panel_json_sql(), text=True)
    common.postgres_query("pelican", """SELECT count(*) FROM notifications
        WHERE data->>'format'='filament' AND read_at IS NULL;""")
    print(f"Panel JSON schema repaired; all converted values verified unchanged. Backup: {backup}",
          flush=True)


def normalized(value, kind):
    if value is None:
        return None
    if kind in ("decimal", "float", "double"):
        return str(Decimal(value).normalize())
    if kind in ("datetime", "timestamp"):
        parsed = datetime.datetime.fromisoformat(value)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=datetime.timezone.utc)
        return parsed.astimezone(datetime.timezone.utc).isoformat()
    return value


def row_fingerprints(rows, fields):
    result = Counter()
    for line in rows.splitlines():
        values = json.loads(line)
        if len(values) != len(fields):
            raise RuntimeError("Database row width changed during verification.")
        values = [normalized(value, field[1]) for value, field in zip(values, fields)]
        result[hashlib.sha256(json.dumps(values, ensure_ascii=False).encode()).hexdigest()] += 1
    return result


def verify_rows(name, credentials, columns, query):
    target_columns = query(name, """
        SELECT json_build_array(table_name, column_name, data_type)
        FROM information_schema.columns WHERE table_schema='public'
        ORDER BY table_name, ordinal_position;
    """)
    types = {}
    for line in target_columns.splitlines():
        table, column, kind = json.loads(line)
        types.setdefault(table, {})[column] = kind
    common.assert_equal(set(columns), set(types), f"{name} complete table set")
    for table, fields in columns.items():
        common.assert_equal({field[0] for field in fields}, set(types[table]), f"{name}.{table} columns")
        mysql_values, pg_values = [], []
        for column, kind, _ in fields:
            mysql = common.identifier(column, "`")
            pg = common.identifier(column)
            if kind in ("blob", "tinyblob", "mediumblob", "longblob", "binary", "varbinary", "bit"):
                mysql_values.append(f"REPLACE(TO_BASE64({mysql}), '\\n', '')")
                pg_values.append(f"replace(encode({pg}, 'base64'), E'\\n', '')")
            else:
                mysql_values.append(f"CAST({mysql} AS CHAR CHARACTER SET utf8mb4)")
                pg_values.append(
                    f"CASE WHEN {pg} IS NULL THEN NULL WHEN {pg} THEN '1' ELSE '0' END"
                    if types[table][column] == "boolean" else f"{pg}::text"
                )
        source = common.output([
            *common.mariadb_args(credentials), "--batch", "--raw", "--skip-column-names",
            credentials["name"],
        ], input=("SET time_zone='+00:00';\n"
                  f"SELECT JSON_ARRAY({', '.join(mysql_values)}) FROM {common.identifier(table, '`')};"),
            env={**os.environ, "MYSQL_PWD": credentials["password"]})
        target = query(name, f"SELECT json_build_array({', '.join(pg_values)}) FROM {common.identifier(table)};")
        common.assert_equal(row_fingerprints(source, fields), row_fingerprints(target, fields),
                            f"{name}.{table} all row values")
    source_fks = common.mariadb_query(credentials, """
        SELECT CONSTRAINT_NAME FROM information_schema.referential_constraints
        WHERE CONSTRAINT_SCHEMA=DATABASE() ORDER BY CONSTRAINT_NAME;
    """).splitlines()
    target_fks = query(name, """
        SELECT conname FROM pg_constraint
        WHERE contype='f' AND connamespace='public'::regnamespace AND convalidated
        ORDER BY conname;
    """).splitlines()
    common.assert_equal(sorted(source_fks), sorted(target_fks), f"{name} validated foreign keys")
    print(f"{name}: all values in {len(columns)} tables and {len(source_fks)} foreign keys verified.", flush=True)


def restore_next_ids(name, credentials, query):
    for table, column, next_id in common.mariadb_next_ids(credentials):
        sequence = query(name, (
            f"SELECT pg_get_serial_sequence({common.literal('public.' + common.identifier(table))}, "
            f"{common.literal(column)});"
        )).strip()
        if not sequence:
            raise RuntimeError(f"Missing sequence: {name}.{table}.{column}")
        query(name, f"SELECT setval({common.literal(sequence)}, {next_id}, false);")
        value = query(name, f"SELECT last_value, is_called FROM {sequence};").strip()
        common.assert_equal(f"{next_id}|f", value, f"{name}.{table} next identifier")


def panel_environment(source, host, user):
    replacements = {
        "DB_CONNECTION": "pgsql", "DB_HOST": host, "DB_PORT": "5432",
        "DB_DATABASE": "pelican", "DB_USERNAME": user, "DB_PASSWORD": "",
        "DB_URL": "", "DATABASE_URL": "",
    }
    return common.rewrite_environment(source, replacements)


def configure_fresh(path, host, user, password):
    private_script = """
        $c=include $argv[1];
        $db=json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR);
        $c['db']=array_merge($c['db'], $db);
        if (file_put_contents($argv[1], "<?php\\nreturn ".var_export($c,true).";\\n") === false) exit(1);
    """
    common.run(["php", "-r", private_script, str(path)], input=json.dumps({
        "type": "pgsql", "host": host, "base": "freshrss", "user": user, "password": password,
    }))


def fresh_archive():
    return common.output([
        "docker", "exec", "freshrss", "tar", "-C", "/app/www",
        "--exclude=./data", "--exclude=./extensions", "--exclude=./static", "-cf", "-", ".",
    ], text=False)


def check_fresh(root, archive=None):
    app = root / "freshrss-app"
    app.mkdir()
    if archive is None:
        archive = fresh_archive()
    with tarfile.open(fileobj=io.BytesIO(archive)) as source:
        source.extractall(app, filter="data")
    data = root / "freshrss-data"
    shutil.copytree(FRESH, data, symlinks=True)
    configure_fresh(data / "config.php", str(root), "postgres", "")
    script = """
        require $argv[1].'/cli/_cli.php';
        foreach (FreshRSS_user_Controller::listUsers() as $user) {
            cliInitUser($user);
            FreshRSS_Factory::createEntryDao()->count();
            FreshRSS_Factory::createFeedDao()->listFeeds();
            FreshRSS_Factory::createCategoryDao()->listCategories();
        }
    """
    private_run(["php", "-r", script, str(app)], root / "freshrss-application.log",
                env={**os.environ, "DATA_PATH": str(data)})
    print("FreshRSS: installed application boot and per-user PostgreSQL DAO queries passed.", flush=True)


def check_panel(root, query):
    app = root / "panel-app"
    common.run(["rsync", "-a", "--exclude=storage", "--exclude=bootstrap/cache", f"{PANEL}/", f"{app}/"],
               stdout=subprocess.DEVNULL)
    (app / "bootstrap/cache").mkdir(parents=True, exist_ok=True)
    for directory in ("app/private", "app/public", "framework/cache/data", "framework/sessions",
                      "framework/views", "logs"):
        (app / "storage" / directory).mkdir(parents=True, exist_ok=True)
    (app / ".env").write_text(panel_environment((PANEL / ".env").read_text(), str(root), "postgres"))
    script = """
        require $argv[1].'/vendor/autoload.php';
        $app=require $argv[1].'/bootstrap/app.php';
        $app->make(Illuminate\\Contracts\\Console\\Kernel::class)->bootstrap();
        if (Illuminate\\Support\\Facades\\DB::connection()->getDriverName() !== 'pgsql') exit(10);
        foreach (['users','servers','nodes','eggs','migrations'] as $table) {
            Illuminate\\Support\\Facades\\DB::table($table)->count();
        }
        Illuminate\\Support\\Facades\\DB::table('notifications')
            ->where('data->format', 'filament')->whereNull('read_at')->count();
        exit(Illuminate\\Support\\Facades\\Artisan::call('migrate', ['--force'=>true]));
    """
    before = query("pelican", 'SELECT count(*) FROM migrations;').strip()
    private_run(["php", "-r", script, str(app)], root / "pelican-application.log",
                env={**os.environ, "APP_ENV": "testing", "LOG_CHANNEL": "stderr"})
    after = query("pelican", 'SELECT count(*) FROM migrations;').strip()
    common.assert_equal(before, after, "Pelican migration ledger unchanged")
    print("Pelican: installed application boot, PostgreSQL queries and migrate passed.", flush=True)


def rehearsal(root, credentials):
    with temporary_postgres(root) as (query, prefix):
        for name, source in credentials.items():
            columns = source_columns(source)
            check_bigints(source, columns)
            query("postgres", f"CREATE DATABASE {common.identifier(name)};")
            load_database(name, source, root, prefix)
            if name == "pelican":
                query(name, panel_json_sql())
            restore_next_ids(name, source, query)
            verify_rows(name, source, columns, query)
        check_fresh(root)
        check_panel(root, query)
    print("Isolated conversion passed; source services and databases were not changed.", flush=True)


def postgres_proof(name, query):
    tables = query(name, "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename;")
    proof = {}
    for table in tables.splitlines():
        rows = query(name, f"SELECT row_to_json(t)::text FROM {common.identifier(table)} t;")
        proof[table] = sorted(Counter(hashlib.sha256(line.encode()).hexdigest()
                                     for line in rows.splitlines()).items())
    proof["__constraints"] = sorted(query(name, """
        SELECT json_build_array(conname, pg_get_constraintdef(oid), convalidated)
        FROM pg_constraint WHERE connamespace='public'::regnamespace;
    """).splitlines())
    sequences = query(name, "SELECT sequencename FROM pg_sequences WHERE schemaname='public';")
    proof["__sequences"] = {
        sequence: query(name, f"SELECT last_value, is_called FROM {common.identifier(sequence)};").strip()
        for sequence in sequences.splitlines()
    }
    return proof


def validate_system(system):
    if not system.is_relative_to("/nix/store") or not (system / "bin/switch-to-configuration").is_file():
        raise RuntimeError("Pass a built system store path.")
    units = system / "etc/systemd/system"
    for name in ["docker-freshrss", "phpfpm-pelican-panel", "pelican-panel-upgrade",
                 "pelican-panel-queue", "pelican-panel-schedule", "pelican-panel-deploy"]:
        text = (units / f"{name}.service").read_text()
        if f"ConditionPathExists={STATE}/ready" not in text or "postgresql.target" not in text:
            raise RuntimeError(f"Missing database migration guard/dependency on {name}.")
    for name in ["docker-mariadb", "uptime-kuma"]:
        if (units / f"{name}.service").exists():
            raise RuntimeError(f"Target still enables {name}.")
    common.check_supervisors(system, False)


def persist(system, backup, state):
    for url in ["http://127.0.0.1:9900/", "http://127.0.0.1:8080/"]:
        common.wait_http(url)
    for unit in ["docker-freshrss", "phpfpm-pelican-panel", "pelican-panel-queue",
                 "pelican-panel-schedule.timer", "postgresql"]:
        common.run(["systemctl", "is-active", "--quiet", unit])
    for unit in ["docker-mariadb", "uptime-kuma"]:
        if common.run(["systemctl", "is-active", "--quiet", unit], check=False,
                      stderr=subprocess.DEVNULL).returncode == 0:
            raise RuntimeError(f"Retired unit remains running: {unit}")
    drivers = php_json("$c=include $argv[1]; echo json_encode($c['db']['type']);", FRESH / "config.php")
    common.assert_equal("pgsql", drivers, "FreshRSS active backend")
    private_run([
        "runuser", "-u", "pelican-panel", "--", "php", "-r",
        "require $argv[1].'/vendor/autoload.php'; $app=require $argv[1].'/bootstrap/app.php';"
        "$app->make(Illuminate\\Contracts\\Console\\Kernel::class)->bootstrap();"
        "if (Illuminate\\Support\\Facades\\DB::connection()->getDriverName()!=='pgsql') exit(1);"
        "Illuminate\\Support\\Facades\\DB::table('servers')->count();", str(PANEL),
    ], backup / "live-pelican-check.log")
    failures = common.failed_units()
    if failures:
        raise RuntimeError(f"Failed units remain: {failures}")
    common.run(["nix-env", "--profile", "/nix/var/nix/profiles/system", "--set", str(system)])
    common.run([str(system / "bin/switch-to-configuration"), "boot"])
    state["target"] = str(system)
    state["stage"] = "complete"
    common.save_json(backup / "state.json", state)
    print(f"Shared MariaDB migration complete and persistent. Backups: {backup}", flush=True)


def start_writers(backup, state):
    state["stage"] = "starting-writers"
    state["native_writers_started"] = True
    common.save_json(backup / "state.json", state)
    (STATE / "ready").touch(mode=0o600)
    common.run(["systemctl", "reset-failed", *WRITERS])
    common.run(["systemctl", "start", "pelican-panel-deploy"])
    private_run([
        "runuser", "-u", "pelican-panel", "--", "php", str(PANEL / "artisan"), "optimize:clear",
    ], backup / "pelican-cache-clear.log", cwd=PANEL)
    common.run(["systemctl", "start", "pelican-panel-upgrade"])
    common.run(["systemctl", "start", "docker-freshrss", "phpfpm-pelican-panel",
                "pelican-panel-queue", "pelican-panel-schedule.timer"])


def finish(system, backup):
    if not backup.is_relative_to(BACKUPS):
        raise RuntimeError("Finish requires a backup under /var/backups/shared-mariadb.")
    state = json.loads((backup / "state.json").read_text())
    if (not state["native_writers_started"] or state["stage"] not in ("starting-writers", "needs-attention")
            or not (STATE / "ready").exists()):
        raise RuntimeError("Not an interrupted post-restore cutover.")
    if str(Path("/run/current-system").resolve()) not in (state["target"], state.get("recovery_system")):
        raise RuntimeError("Running system does not match the interrupted cutover.")
    validate_system(system)
    common.run(["nix-store", "--add-root", str(backup / ("recovery-" + system.name)),
                "--indirect", "--realise", str(system)])
    state["recovery_system"] = str(system)
    common.save_json(backup / "state.json", state)
    common.run([str(system / "bin/switch-to-configuration"), "test"])
    start_writers(backup, state)
    persist(system, backup, state)


def cutover(system):
    validate_system(system)
    if STATE.exists():
        raise RuntimeError(f"{STATE} already exists; review the prior migration before proceeding.")
    credentials = source_credentials()
    source_size = int(common.output(["du", "-sb", "/var/lib/mariadb"]).split()[0])
    if shutil.disk_usage("/var/lib").free < source_size * 3 + 5 * 1024**3:
        raise RuntimeError("Need three times the shared MariaDB size plus 5 GiB free before migration.")
    for name in DATABASES:
        exists = common.postgres_query("postgres", (
            f"SELECT count(*) FROM pg_database WHERE datname={common.literal(name)};"
        )).strip()
        common.assert_equal("0", exists, f"Unused destination database {name}")
    if common.failed_units():
        raise RuntimeError("Resolve failed units before migration.")
    for unit in ["docker-mariadb", "docker-freshrss", "uptime-kuma", "postgresql",
                 "phpfpm-pelican-panel", "pelican-panel-queue"]:
        common.run(["systemctl", "is-active", "--quiet", unit])
    BACKUPS.mkdir(mode=0o700, parents=True, exist_ok=True)
    backup = BACKUPS / datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup.mkdir(mode=0o700)
    STATE.mkdir(mode=0o700)
    state = {
        "old_system": str(Path("/run/current-system").resolve()),
        "old_profile": str(Path("/nix/var/nix/profiles/system").resolve()),
        "target": str(system), "stage": "backing-up", "native_writers_started": False,
    }
    common.save_json(backup / "state.json", state)
    for label, target in [("old-system", state["old_system"]), ("new-system", str(system))]:
        common.run(["nix-store", "--add-root", str(backup / label), "--indirect", "--realise", target])
    shutil.copy2(FRESH / "config.php", backup / "freshrss-config.php")
    shutil.copy2(PANEL / ".env", backup / "pelican.env")
    fresh_code = fresh_archive()
    switched = False
    print(f"Backups: {backup}", flush=True)
    try:
        common.run(["systemctl", "stop", *WRITERS, "uptime-kuma"])
        common.copy_tree(FRESH, backup / "freshrss-data")
        common.copy_tree(Path("/var/lib/uptime-kuma"), backup / "uptime-kuma")
        common.copy_tree(PANEL / "storage", backup / "pelican-storage")
        for name, source in credentials.items():
            with (backup / f"{name}-mariadb.sql").open("wb") as stream:
                common.run([
                    *common.mariadb_args(source, "mariadb-dump"), "--single-transaction",
                    "--routines", "--events", source["name"],
                ], env={**os.environ, "MYSQL_PWD": source["password"]}, stdout=stream, text=False)
        conversion = Path(tempfile.mkdtemp(prefix="shared-mariadb-conversion-"))
        common.save_json(backup / "conversion-path.json", str(conversion))
        proofs = {}
        with temporary_postgres(conversion) as (query, prefix):
            columns = {}
            for name, source in credentials.items():
                columns[name] = source_columns(source)
                check_bigints(source, columns[name])
                query("postgres", f"CREATE DATABASE {common.identifier(name)};")
                load_database(name, source, conversion, prefix)
                if name == "pelican":
                    query(name, panel_json_sql())
                restore_next_ids(name, source, query)
                verify_rows(name, source, columns[name], query)
            check_fresh(conversion, fresh_code)
            check_panel(conversion, query)
            for name in DATABASES:
                proofs[name] = postgres_proof(name, query)
                private_run([
                    *prefix, "pg_dump", "-h", str(conversion), "-U", "postgres", "-d", name,
                    "--format=custom", "--no-owner", "--no-acl", "--file", str(conversion / f"{name}.dump"),
                ], backup / "dump-converted.log")
        shutil.move(str(conversion), str(backup / "conversion"))
        conversion = backup / "conversion"
        common.save_json(backup / "converted-proof.json", proofs)
        common.run(["systemctl", "stop", "docker-mariadb"])
        common.copy_tree(Path("/var/lib/mariadb"), backup / "shared-mariadb-data")
        (PANEL / ".env").write_text(panel_environment((PANEL / ".env").read_text(),
                                                    "/run/postgresql", "pelican-panel"))
        password = secrets.token_hex(32)
        configure_fresh(FRESH / "config.php", "/run/postgresql", "freshrss", password)
        state["stage"] = "restoring"
        common.save_json(backup / "state.json", state)
        switched = True
        common.run([str(system / "bin/switch-to-configuration"), "test"])
        common.run(["systemctl", "start", "postgresql.target"])
        common.postgres_query("postgres", (
            f"ALTER ROLE freshrss PASSWORD {common.literal(password)};"
            'ALTER DATABASE pelican OWNER TO "pelican-panel";'
        ))
        for name, owner in DATABASES.items():
            with (conversion / f"{name}.dump").open("rb") as stream:
                private_run([
                    "runuser", "-u", "postgres", "--", "pg_restore", "--exit-on-error",
                    "--no-owner", "--no-acl", f"--role={owner}", "-d", name,
                ], backup / f"restore-{name}.log", stdin=stream)
            common.assert_equal(proofs[name], postgres_proof(name, common.postgres_query),
                                f"{name} native rows, constraints and sequences")
            owners = common.postgres_query(name, (
                "SELECT DISTINCT tableowner FROM pg_tables WHERE schemaname='public';"
            )).splitlines()
            common.assert_equal([owner], owners, f"{name} table ownership")
        start_writers(backup, state)
        persist(system, backup, state)
    except (Exception, KeyboardInterrupt):
        if state["native_writers_started"]:
            state["stage"] = "needs-attention"
            print(f"Native writers may have accepted data; no automatic rollback. Recovery state: {backup}",
                  file=sys.stderr)
        else:
            (STATE / "ready").unlink(missing_ok=True)
            shutil.copy2(backup / "freshrss-config.php", FRESH / "config.php")
            shutil.copy2(backup / "pelican.env", PANEL / ".env")
            state["stage"] = "rollback-needed"
            common.save_json(backup / "state.json", state)
            if switched:
                common.run([state["old_system"] + "/bin/switch-to-configuration", "test"])
            common.run(["systemctl", "start", "docker-mariadb", "uptime-kuma",
                        "docker-freshrss", "phpfpm-pelican-panel", "pelican-panel-queue",
                        "pelican-panel-schedule.timer"])
            state["stage"] = "rolled-back"
            print("Original applications restored; converted copies and backups retained.", file=sys.stderr)
        common.save_json(backup / "state.json", state)
        raise


def main():
    parser = argparse.ArgumentParser(description="Migrate remaining shared MariaDB clients safely.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--rehearse", action="store_true")
    mode.add_argument("--system", type=Path)
    mode.add_argument("--repair-panel-json", action="store_true")
    parser.add_argument("--finish", type=Path)
    args = parser.parse_args()
    if args.finish and not args.system:
        parser.error("--finish requires --system.")
    os.umask(0o077)
    if args.rehearse:
        root = Path(tempfile.mkdtemp(prefix="shared-mariadb-rehearsal-"))
        try:
            rehearsal(root, source_credentials())
        except (Exception, KeyboardInterrupt):
            print(f"Private rehearsal diagnostics retained at {root}", file=sys.stderr)
            raise
        else:
            shutil.rmtree(root)
    else:
        if os.geteuid() != 0:
            parser.error("Run with sudo in your terminal.")
        with Path("/run/lock/shared-mariadb-migration.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            if args.repair_panel_json:
                repair_panel_json()
            elif args.finish:
                finish(args.system.resolve(), args.finish.resolve())
            else:
                cutover(args.system.resolve())


if __name__ == "__main__":
    main()
